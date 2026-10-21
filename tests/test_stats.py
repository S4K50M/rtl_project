import random
import subprocess
import unittest
from pathlib import Path


class StatsTests(unittest.TestCase):
    def test_divider(self):
        rng=random.Random(721)
        vectors=[(0,1),((1<<64)-1,1),((1<<64)-1,(1<<32)-1),((1<<63)+17,65535)]
        vectors += [(rng.randrange(1<<64),rng.randrange(1,1<<32)) for _ in range(120)]
        Path('build/divider.in').write_text(''.join(f'{a:016x} {b:08x} {a//b:016x}\n' for a,b in vectors))
        subprocess.run(['bash','scripts/iverilog.sh','-g2012','-s','tb_divider','-o','build/divider',
                        'rtl/unsigned_divider.sv','tb/tb_divider.sv'],check=True)
        subprocess.run(['bash','scripts/vvp.sh','build/divider'],check=True,timeout=30)

    def test_fixed_point_reference(self):
        rng=random.Random(98)
        samples=[(1,0,0)]+[(0,1,x) for x in (2,4,4,4,5,5,7,9)]
        samples += [(0,rng.randrange(2),rng.randrange(50000)) for _ in range(500)]
        samples += [(1,0,0)] + [(0,1,32767 if i%2 else 0) for i in range(70)]
        Path('build/stats.in').write_text(''.join(f'{r} {v} {x}\n' for r,v,x in samples))
        subprocess.run(['bash','scripts/iverilog.sh','-g2012','-s','tb_stats','-o','build/stats',
                        'rtl/welford_stats.sv','rtl/unsigned_divider.sv','tb/tb_stats.sv'],check=True)
        subprocess.run(['bash','scripts/vvp.sh','build/stats'],check=True,timeout=60)
        actual=[tuple(map(int,s.split())) for s in Path('build/stats.out').read_text().splitlines()]
        self.assertEqual(len(samples),len(actual))
        n=mean=m2=0
        for i,((reset,valid,x),result) in enumerate(zip(samples,actual)):
            if reset: n=mean=m2=0
            elif valid and n<64:
                x=min(x,32767)<<16
                delta=x-mean
                mean+=(1 if delta>=0 else -1)*(abs(delta)//(n+1))
                m2+=(delta*(x-mean))>>16
                n+=1
            self.assertEqual(result,(n,mean,min(0xffffffff,m2//n if n else 0)),f'cycle {i}')
