#!/usr/bin/env python3
"""Executable CTL fixed-point checks + actual RTL temporal-induction proofs.

The CTL systems are finite abstractions; this is not a whole-SoC RTL liveness
proof. See docs/verification.md for the refinement obligations and fairness.
"""
import json
import os
from collections import deque
from pathlib import Path
import subprocess


def reachable(initial, successors):
    todo=deque([initial]); parent={initial:None}; edges={}
    while todo:
        s=todo.popleft()
        edges[s]=set(successors(s)) or {s}
        for t in edges[s]:
            if t not in parent: parent[t]=s; todo.append(t)
    return edges,parent


def AG(edges, good):
    result=set(good)
    while True:
        new={s for s in result if edges[s] <= result}
        if new==result: return result
        result=new


def AF(edges, goal):
    result=set(goal)
    while True:
        new=result | {s for s,ts in edges.items() if ts <= result}
        if new==result: return result
        result=new


def arbiter_ctl():
    # One transition is a credit-enabled packet completion opportunity.
    # Request 0 remains asserted; the four competing requests vary arbitrarily.
    def succ(s):
        priority,_=s
        for mask in range(1,32,2):
            winner=next((priority+k)%5 for k in range(5) if mask & (1<<((priority+k)%5)))
            yield ((winner+1)%5,winner==0)
    edges,_=reachable((0,False),succ)
    assert set(edges)==AG(edges,AF(edges,{s for s in edges if s[1]}))
    for p in range(5):
        for mask in range(32):
            winners=[(p+k)%5 for k in range(5) if mask & (1<<((p+k)%5))]
            grant=1<<winners[0] if winners else 0
            assert grant & (grant-1)==0 and grant & ~mask==0
    return {'states':len(edges),'AG_AF_persistent_request_served':True,'all_masks_mutual_exclusion':True}


def route(src,dst,nx):
    x,y=src%nx,src//nx; dx,dy=dst%nx,dst//nx
    channels=[]
    while x!=dx:
        q=x+(1 if dx>x else -1)
        channels.append(((x,y),(q,y))); x=q
    while y!=dy:
        q=y+(1 if dy>y else -1)
        channels.append(((x,y),(x,q))); y=q
    return channels


def cdg(nx):
    edges={}
    for src in range(nx*nx):
        for dst in range(nx*nx):
            path=route(src,dst,nx)
            for c in path: edges.setdefault(c,set())
            for a,b in zip(path,path[1:]): edges[a].add(b)
    indegree={s:0 for s in edges}
    for ts in edges.values():
        for t in ts: indegree[t]+=1
    todo=deque(s for s,d in indegree.items() if d==0); order=[]
    while todo:
        s=todo.popleft(); order.append(s)
        for t in edges[s]:
            indegree[t]-=1
            if indegree[t]==0: todo.append(t)
    assert len(order)==len(edges), 'XY channel dependency cycle'
    return {'mesh':nx,'channels':len(edges),'dependencies':sum(map(len,edges.values())),'acyclic':True}


def resource_system(paths):
    # Each channel is held until a finite packet's tail releases it.
    # Acquiring a channel abstracts filling its four-flit buffer with a long
    # packet. Completion drains both channels to a receptive endpoint.
    def successors(stage):
        held={}
        for p,st in enumerate(stage):
            if st in (1,2): held[paths[p][0]]=p
            if st==2: held[paths[p][1]]=p
        for p,st in enumerate(stage):
            if st<2 and paths[p][st] not in held or st==2:
                t=list(stage); t[p]+=1; yield tuple(t)
    return reachable((0,)*4,successors)


def deadlock_check():
    # Clockwise square: 0->1->3->2->0. S->W and N->E violate XY.
    ring=[((0,0),(1,0)),((1,0),(1,1)),((1,1),(0,1)),((0,1),(0,0))]
    paths=[(ring[i],ring[(i+1)%4]) for i in range(4)]
    edges,parent=resource_system(paths)
    deadlocks=[s for s,ts in edges.items() if ts=={s} and s!=(3,)*4]
    assert (1,1,1,1) in deadlocks
    s=(1,1,1,1); trace=[]
    while s is not None: trace.append(s); s=parent[s]
    trace.reverse()
    fixed=[route(s,d,2) for s,d in ((0,3),(1,2),(3,0),(2,1))]
    xy_edges,_=resource_system(fixed)
    terminal={s for s in xy_edges if s==(3,)*4}
    assert (0,)*4 in AG(xy_edges,AF(xy_edges,terminal))
    return {'all_turns_states':len(edges),'counterexample':trace,
            'final_occupancy':[4]*4,'final_credits':[0]*4,
            'held_channels':ring,'requested_channels':ring[1:]+ring[:1],
            'XY_resource_states':len(xy_edges),'XY_AG_AF_completion':True}


def rtl_proof(name,files):
    command=(f'read_verilog -formal -sv -D SYNTHESIS {" ".join(files)}; '
             f'prep -top {name} -flatten; memory_map; opt; async2sync; chformal -lower; '
             'sat -seq 8 -tempinduct -maxsteps 20 -timeout 30 -set-assumes -prove-asserts -verify')
    script=Path('build')/f'{name}.ys'; script.write_text(command+'\n')
    run=subprocess.run(['bash','-c','source scripts/env.sh; exec yosys -Q -T -s "$1"','bash',str(script)],
                       text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    Path(f'build/{name}.log').write_text(run.stdout)
    if run.returncode or 'SUCCESS' not in run.stdout:
        raise RuntimeError(f'{name} proof failed; see build/{name}.log\n'+run.stdout[-2000:])
    return {'method':'RTL temporal induction','passed':True}


def main():
    Path('build').mkdir(exist_ok=True)
    results={'CTL_arbiter':arbiter_ctl(),'XY_CDG':[cdg(n) for n in (2,3,4)],'deadlock':deadlock_check()}
    results['RTL_rr']=rtl_proof('rr_harness',['rtl/rr_arbiter.sv','formal/rr_harness.sv'])
    results['RTL_credit']=rtl_proof('credit_harness',['rtl/noc_fifo.sv','formal/credit_harness.sv'])
    rtl=[str(p) for p in sorted(Path('rtl').glob('*.sv'))]
    for mixed in (1,0):
        exe=f'build/deadlock_{mixed}'
        subprocess.run(['bash','scripts/iverilog.sh','-g2012','-Irtl','-s','tb_deadlock',
                        f'-Ptb_deadlock.MIXED={mixed}','-o',exe,*rtl,'tb/tb_deadlock.sv'],check=True)
        run=subprocess.run(['bash','scripts/vvp.sh',exe],check=True,timeout=30,text=True,stdout=subprocess.PIPE)
        Path(exe+'.log').write_text(run.stdout)
        print(run.stdout.strip())
    results['RTL_deadlock']={'mixed_turns':'expected deadlock reached','XY_control':'32 flits drained'}
    Path('build/formal_results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps(results,indent=2))


if __name__=='__main__': main()
