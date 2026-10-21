"""Independent synchronous transition model of the credit-based RTL mesh.

step() returns the ready/valid signals *before* the rising edge, then commits
all router, FIFO, link and endpoint state simultaneously. No link bypasses an
input buffer. Credit return is combinational from pop and counted at that edge.
"""
from collections import deque
from dataclasses import dataclass, field

HEAD, TAIL = 1 << 63, 1 << 62


def packet(src, dst, ident, length=3, nx=2):
    assert 1 <= length <= 256
    header = (HEAD | ((dst % nx) << 60) | ((dst // nx) << 58)
              | ((src % nx) << 56) | ((src // nx) << 54) | (ident << 8))
    return [header | (TAIL if length == 1 else 0)] + [
        (TAIL if i == length - 1 else 0) | (ident << 8) | i for i in range(1, length)]


def xy(x, y, flit):
    dx, dy = (flit >> 60) & 3, (flit >> 58) & 3
    return 1 if dx > x else 2 if dx < x else 3 if dy > y else 4 if dy < y else 0


@dataclass
class Router:
    x: int
    y: int
    depth: int
    fifo: list = field(default_factory=lambda: [deque() for _ in range(5)])
    state: list = field(default_factory=lambda: [0] * 5)
    route: list = field(default_factory=lambda: [0] * 5)
    owner: list = field(default_factory=lambda: [None] * 5)
    priority: list = field(default_factory=lambda: [0] * 5)

    def __post_init__(self):
        self.credit = [self.depth] * 5

    def grants(self):
        result = [None] * 5
        for out in range(5):
            if not self.credit[out]:
                continue
            for offset in range(5):
                i = (self.priority[out] + offset) % 5
                if (self.fifo[i] and self.state[i] in (2, 3) and self.route[i] == out
                        and self.owner[out] in (None, i)):
                    result[out] = i
                    break
        return result


class Network:
    def __init__(self, nx=2, ny=2, depth=4, fast=False):
        assert 1 <= nx <= 4 and 1 <= ny <= 4 and depth >= 2
        self.nx, self.ny, self.depth, self.fast = nx, ny, depth, fast
        self.n = nx * ny
        self.routers = [Router(i % nx, i // nx, depth) for i in range(self.n)]
        self.tx_credit = [depth] * self.n
        self.rx = [deque() for _ in range(self.n)]
        self.cycle = 0

    def neighbor(self, n, port):
        x, y = n % self.nx, n // self.nx
        if port == 1 and x + 1 < self.nx: return n + 1, 2
        if port == 2 and x > 0: return n - 1, 1
        if port == 3 and y + 1 < self.ny: return n + self.nx, 4
        if port == 4 and y > 0: return n - self.nx, 3
        return None

    def step(self, tx=None, consume=None):
        tx = [None] * self.n if tx is None else tx
        consume = [True] * self.n if consume is None else consume
        ready = [c > 0 for c in self.tx_credit]
        received = [q[0] if q else None for q in self.rx]
        grants = [r.grants() for r in self.routers]
        pops = [[i in g for i in range(5)] for g in grants]
        pushes = [[None] * 5 for _ in self.routers]
        for n, r in enumerate(self.routers):
            pushes[n][0] = tx[n] if ready[n] else None
            self.tx_credit[n] += int(pops[n][0]) - int(tx[n] is not None and ready[n])
            if received[n] is not None and consume[n]:
                self.rx[n].popleft()
            for out, i in enumerate(grants[n]):
                if i is None: continue
                flit = r.fifo[i][0]
                if out == 0:
                    self.rx[n].append(flit)
                else:
                    dest = self.neighbor(n, out)
                    assert dest is not None, 'Packet routed beyond mesh edge'
                    pushes[dest[0]][dest[1]] = flit

        # State transitions read only the pre-edge FIFO and credit state.
        for n, r in enumerate(self.routers):
            new_state = list(r.state)
            for i, q in enumerate(r.fifo):
                if r.state[i] == 0 and q:
                    assert q[0] & HEAD, 'Expected packet header'
                    if self.fast:
                        r.route[i] = xy(r.x, r.y, q[0]); new_state[i] = 2
                    else: new_state[i] = 1
                elif r.state[i] == 1:
                    r.route[i] = xy(r.x, r.y, q[0]); new_state[i] = 2
                elif r.state[i] in (2, 3):
                    if pops[n][i] and q[0] & TAIL: new_state[i] = 0
                    else: new_state[i] = 3 if r.credit[r.route[i]] == 0 else 2
            for out, i in enumerate(grants[n]):
                returned = (received[n] is not None and consume[n]) if out == 0 else (
                    pops[self.neighbor(n, out)[0]][self.neighbor(n, out)[1]]
                    if self.neighbor(n, out) else False)
                r.credit[out] += int(returned) - int(i is not None)
                if i is not None:
                    r.owner[out] = None if r.fifo[i][0] & TAIL else i
                    r.priority[out] = (i + 1) % 5
            r.state = new_state
        for n, r in enumerate(self.routers):
            for i, q in enumerate(r.fifo):
                if pops[n][i]: q.popleft()
                if pushes[n][i] is not None: q.append(pushes[n][i])
        self.cycle += 1
        self.check_invariants()
        return ready, received

    def check_invariants(self):
        for n, r in enumerate(self.routers):
            assert 0 <= self.tx_credit[n] <= self.depth
            assert self.tx_credit[n] + len(r.fifo[0]) == self.depth
            assert len(self.rx[n]) <= self.depth
            for port in range(5):
                assert len(r.fifo[port]) <= self.depth
                assert 0 <= r.credit[port] <= self.depth
                if port == 0: assert r.credit[0] + len(self.rx[n]) == self.depth
                elif self.neighbor(n, port):
                    d, p = self.neighbor(n, port)
                    assert r.credit[port] + len(self.routers[d].fifo[p]) == self.depth

    def empty(self):
        return not any(self.rx) and not any(q for r in self.routers for q in r.fifo)
