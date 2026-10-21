#!/usr/bin/env python3
import pathlib, sys
data=pathlib.Path(sys.argv[1]).read_bytes()
assert len(data)<=16384, "Firmware exceeds RAM"
data=data.ljust(16384,b'\0')
pathlib.Path(sys.argv[2]).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
