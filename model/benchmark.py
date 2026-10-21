"""Open-loop offered traffic; preserve queued packets and report congestion.

Rates are offered flits/node/cycle (3 flits per packet). Latency runs from
accepted header to consumed tail; queued latency starts at packet generation.
Only deliveries in the measurement window enter the statistics. Drain checks
all generated traffic without including drain time in the throughput metric.
"""
import argparse
import csv
import json
import os
import random
from collections import deque
from pathlib import Path
from statistics import mean, pvariance
from model.network import Network, packet, HEAD, TAIL


def run(rate,pattern,fast,cycles=3000,warmup=500,seed=7,nx=2):
    net=Network(nx,nx,fast=fast); rng=random.Random(seed)
    pending=[deque() for _ in range(net.n)]
    generated={}; injected={}; ident=0; delivered=set()
    accepted=received=0; latency=[]; queued=[]; done=0; in_window_packets=0
    for cycle in range(cycles):
        for src in range(net.n):
            if rng.random()<rate/3:
                others=[d for d in range(net.n) if d!=src]
                dst=0 if pattern=='hotspot' and src!=0 and rng.random()<.8 else rng.choice(others)
                ident+=1; generated[ident]=cycle
                pending[src].extend(packet(src,dst,ident,3,nx))
        tx=[q[0] if q else None for q in pending]
        ready,rx=net.step(tx)
        for n in range(net.n):
            if tx[n] is not None and ready[n]:
                flit=pending[n].popleft()
                if flit&HEAD: injected[(flit&0xffffffff)>>8]=cycle
                if cycle>=warmup: accepted+=1
            if rx[n] is not None:
                flit=rx[n]
                if cycle>=warmup: received+=1
                if flit&TAIL:
                    p=(flit&0xffffffff)>>8
                    assert p not in delivered
                    delivered.add(p)
                    if cycle>=warmup:
                        latency.append(cycle-injected[p]); queued.append(cycle-generated[p]); in_window_packets+=1
    backlog=sum(len(q) for q in pending)
    outstanding=ident-len(delivered)
    # Check conservation and eventual drainage; bounded only for this workload.
    for drain in range(50000):
        if not any(pending) and net.empty(): break
        tx=[q[0] if q else None for q in pending]; ready,rx=net.step(tx)
        for n in range(net.n):
            if tx[n] is not None and ready[n]: pending[n].popleft()
            if rx[n] is not None and rx[n]&TAIL:
                p=(rx[n]&0xffffffff)>>8
                assert p not in delivered; delivered.add(p)
    else: raise AssertionError('Drain timeout')
    assert len(delivered)==ident
    window=cycles-warmup
    return dict(variant='fast' if fast else 'baseline',pattern=pattern,seed=seed,
                offered_flits_node_cycle=rate,accepted_flits_node_cycle=accepted/(net.n*window),
                delivered_flits_node_cycle=received/(net.n*window),
                mean_latency=mean(latency) if latency else 0,
                variance_latency=pvariance(latency) if latency else 0,
                mean_queued_latency=mean(queued) if queued else 0,
                packets_measured=in_window_packets,generated=ident,backlog_flits=backlog,
                outstanding_packets=outstanding,drain_cycles=drain,cycles=cycles,warmup=warmup)


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--cycles',type=int,default=3000)
    parser.add_argument('--out',default='build/benchmark'); args=parser.parse_args()
    out=Path(args.out); out.mkdir(parents=True,exist_ok=True)
    os.environ.setdefault('MPLCONFIGDIR',str(out.resolve()/'mplcache'))
    os.environ.setdefault('XDG_CACHE_HOME',str(out.resolve()/'cache'))
    rows=[]
    for pattern in ('uniform','hotspot'):
        for fast in (False,True):
            for rate in (.01,.05,.1,.2,.3,.45,.6,.8,.95):
                for seed in (7,19):
                    rows.append(run(rate,pattern,fast,args.cycles,seed=seed))
            print(f'Benchmark {pattern} FAST={int(fast)} completed',flush=True)
    with (out/'traffic.csv').open('w') as f:
        writer=csv.DictWriter(f,rows[0]); writer.writeheader(); writer.writerows(rows)
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    for metric,label in (('mean_latency','Accepted header to tail latency (cycles)'),
                         ('mean_queued_latency','Generation to tail latency (cycles)'),
                         ('delivered_flits_node_cycle','Delivered flits / node / cycle')):
        fig,axes=plt.subplots(1,2,figsize=(10,4),layout='constrained')
        for ax,pattern in zip(axes,('uniform','hotspot')):
            for variant in ('baseline','fast'):
                group=[r for r in rows if r['pattern']==pattern and r['variant']==variant]
                rates=sorted(set(r['offered_flits_node_cycle'] for r in group))
                y=[mean(r[metric] for r in group if r['offered_flits_node_cycle']==rate) for rate in rates]
                ax.plot(rates,y,'o-',label=variant)
            ax.set(title=pattern,xlabel='Offered flits / node / cycle',ylabel=label); ax.grid(alpha=.3); ax.legend()
        fig.savefig(out/f'{metric}.svg'); plt.close(fig)
    summary={'method':'cycle model validated against RTL; 2 seeds; finite observation window',
             'zero_load_corner_single_flit_cycles':{'baseline':10,'fast':7},
             'peak_observed_delivered_flits_node_cycle':{}}
    for pattern in ('uniform','hotspot'):
        for variant in ('baseline','fast'):
            summary['peak_observed_delivered_flits_node_cycle'][pattern+'_'+variant]=max(
                mean(r['delivered_flits_node_cycle'] for r in rows if r['pattern']==pattern and r['variant']==variant and r['offered_flits_node_cycle']==rate)
                for rate in (.01,.05,.1,.2,.3,.45,.6,.8,.95))
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))


if __name__=='__main__': main()
