import random
import subprocess
import unittest
from collections import deque
from pathlib import Path
from model.network import Network, packet, HEAD, TAIL

RTL = [str(p) for p in sorted(Path('rtl').glob('*.sv'))]


def mask(bits):
    return sum(int(b) << i for i, b in enumerate(bits))


def simulate_rtl(nx, ny, fast, stimulus, expected, label, minimized=0):
    stem = Path('build') / label
    stem.with_suffix('.in').write_text('\n'.join(stimulus) + '\n')
    subprocess.run(['bash', 'scripts/iverilog.sh', '-g2012', '-Irtl', '-s', 'tb_mesh',
                    f'-Ptb_mesh.NX={nx}', f'-Ptb_mesh.NY={ny}', f'-Ptb_mesh.FAST={int(fast)}', f'-Ptb_mesh.MINIMIZED={minimized}',
                    '-o', str(stem), *RTL, 'tb/tb_mesh.sv'], check=True)
    subprocess.run(['bash', 'scripts/vvp.sh', str(stem),
                    f'+INPUT={stem}.in', f'+OUTPUT={stem}.out'], check=True, timeout=90)
    lines = stem.with_suffix('.out').read_text().splitlines()
    assert len(lines) == len(expected)
    for cycle, (line, (ready, received)) in enumerate(zip(lines, expected)):
        fields = line.split()
        assert int(fields[0], 16) == mask(ready), (label, cycle, 'tx_ready')
        assert int(fields[1], 16) == mask(v is not None for v in received), (label, cycle, 'rx_valid')
        for i, flit in enumerate(received):
            if flit is not None:
                assert int(fields[i+2], 16) == flit, (label, cycle, i, 'flit mismatch')


class NetworkTests(unittest.TestCase):
    def test_random_multiflit_cycle_equivalence(self):
        for nx, ny in ((2, 2), (3, 3)):
            for fast in (False, True):
                with self.subTest(nx=nx, fast=fast):
                    rng = random.Random(4200 + nx)
                    net = Network(nx, ny, fast=fast)
                    pending = [deque() for _ in range(net.n)]
                    expected_packets = {}
                    for ident in range(1, 121):
                        src, dst = rng.randrange(net.n), rng.randrange(net.n)
                        flits = packet(src, dst, ident, rng.randint(1, 11), nx)
                        pending[src].extend(flits)
                        expected_packets[ident] = (dst, flits)
                    assembling = [[] for _ in range(net.n)]
                    delivered = set()
                    stimulus, expected = [], []
                    blocked = False
                    for cycle in range(12000):
                        # Hold endpoint 0 off long enough to exhaust credits.
                        consume = [rng.random() < .67 for _ in range(net.n)]
                        if 50 <= cycle < 250: consume[0] = False
                        tx = [q[0] if q else None for q in pending]
                        stimulus.append(f'{mask(v is not None for v in tx):x} {mask(consume):x} ' +
                                        ' '.join(f'{(v or 0):016x}' for v in tx))
                        ready, received = net.step(tx, consume)
                        expected.append((ready, received))
                        for n in range(net.n):
                            if tx[n] is not None and ready[n]: pending[n].popleft()
                            blocked |= tx[n] is not None and not ready[n]
                            if received[n] is None or not consume[n]: continue
                            flit = received[n]
                            if flit & HEAD: self.assertFalse(assembling[n], 'Packet interleaving')
                            else: self.assertTrue(assembling[n], 'Body without head')
                            assembling[n].append(flit)
                            if flit & TAIL:
                                ident = (assembling[n][0] & 0xffffffff) >> 8
                                self.assertNotIn(ident, delivered)
                                self.assertEqual(expected_packets[ident], (n, assembling[n]))
                                delivered.add(ident); assembling[n] = []
                        if not any(pending) and net.empty(): break
                    self.assertEqual(len(delivered), 120)
                    self.assertTrue(blocked)
                    simulate_rtl(nx, ny, fast, stimulus, expected, f'mesh_{nx}_{int(fast)}')
                    simulate_rtl(nx, ny, fast, stimulus, expected, f'mesh_min_{nx}_{int(fast)}',minimized=1)

    def test_zero_load_latency(self):
        for fast, expected in ((False, 10), (True, 7)):
            net = Network(fast=fast)
            first = packet(0, 3, 1, 1)[0]
            ready, _ = net.step([first, None, None, None])
            self.assertTrue(ready[0])
            for cycle in range(1, 20):
                _, received = net.step()
                if received[3] is not None:
                    self.assertEqual(cycle, expected)
                    break
            else: self.fail('Packet not delivered')
