#!/usr/bin/env python3
import json
import os
from pathlib import Path
rows=[]
for name in ('baseline','fast','espresso'):
    report=json.loads(Path(f'build/synth/{name}.json').read_text())
    types=report['design']['num_cells_by_type']
    rows.append(dict(variant=name,flip_flops=sum(v for k,v in types.items() if k.startswith(('FDRE','FDSE','FDCE','FDPE'))),
                     lut_cells=sum(v for k,v in types.items() if k.startswith('LUT')),cells=types,
                     fmax_mhz=None,method='Yosys xc7 mapping; not Vivado placement/routing'))
Path('build/synth/summary.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))
os.environ.setdefault('MPLCONFIGDIR',str(Path('build/synth/mplcache').resolve()))
os.environ.setdefault('XDG_CACHE_HOME',str(Path('build/synth/cache').resolve()))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig,axes=plt.subplots(1,2,figsize=(8,3),layout='constrained')
for ax,field,label in zip(axes,('lut_cells','flip_flops'),('Logic LUT cells','Flip-flops')):
    ax.bar([r['variant'] for r in rows],[r[field] for r in rows])
    ax.set_ylabel(label); ax.set_title('Yosys xc7 mapping'); ax.grid(axis='y',alpha=.2)
fig.savefig('build/synth/area.svg')
