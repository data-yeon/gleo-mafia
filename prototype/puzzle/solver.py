"""솔버: 플레이어가 아는 정보와 모순되지 않는 '가능한 세계'를 모두 대입한다.

가능한 세계 = 악역과 말썽꾼이 어느 장소에 있는지의 배치.
정직한 장소의 구체적인 직업은 몰라도 된다. 직업 제약은 집합 연산으로 따로 확인한다.
  - 정직한 사람은 자기 직업을 그대로 밝히고, 같은 직업은 한 명뿐이다.
  - 행동대원·사칭범은 판에 있는 직업으로, 협박꾼·보스·취객은 판에 없는 직업으로 위장한다.
  - 판에 있는 직업 수 = n_honest, 판에 없는 직업 수 = 7 - n_honest.
  - 사칭범만 순찰 경관 행세를 할 수 있고, 경관은 오염되지 않는다.
  - 익명 제보자는 직업을 밝히지 않으므로 직업 제약에 쓰지 않는다.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from itertools import combinations, permutations, product

from .generator import Case, CaseFile, all_hidden_sets
from .model import (
    HONEST_ROLES, IN_PLAY_PRETENDERS, Clue, ClueType, Role, honest_bit, is_disguised, is_evil,
    mask_of, popcount,
)
from .rules import taint_candidates


@dataclass(frozen=True)
class World:
    roles: tuple            # 장소별 역할. 정직은 None
    hidden: int
    disguised: int
    taint: int              # 정직이면 오염되는 장소


@dataclass(frozen=True)
class Observation:
    shown: Role | None      # 익명 제보면 None
    clue: Clue
    stakeout: bool


def enumerate_worlds(cf: CaseFile) -> list[World]:
    n = cf.board.n
    evil = list(cf.preset.evil)
    m = cf.preset.meddlers
    seen = set()
    worlds = []
    for perm in permutations(range(n), len(evil) + m):
        for mtypes in product(cf.meddler_types, repeat=m):
            roles: list = [None] * n
            for idx, r in zip(perm, evil + list(mtypes)):
                roles[idx] = r
            key = tuple(roles)
            if key in seen:
                continue
            seen.add(key)
            worlds.append(World(
                roles=key,
                hidden=mask_of(i for i, r in enumerate(key) if is_evil(r)),
                disguised=mask_of(i for i, r in enumerate(key) if is_disguised(r)),
                taint=taint_candidates(cf.board, key),
            ))
    return worlds


def _iter_bits(mask: int):
    while mask:
        low = mask & -mask
        yield low.bit_length() - 1
        mask ^= low


def local_contribution(w: World, i: int, obs: Observation):
    """세계 w에서 장소 i의 관찰이 성립하면 (판에 있어야 할 직업, 없어야 할 직업, 정직 직업) 비트를,
    성립하지 않으면 None을 돌려준다."""
    r = w.roles[i]
    s = obs.shown
    truth = obs.clue.holds(w.hidden, w.disguised)
    if s is None:
        return _anonymous_contribution(w, i, obs, truth)
    if r is None:                                   # 정직
        if s not in HONEST_ROLES:
            return None
        tainted = bool(w.taint >> i & 1) and s is not Role.COP
        expected = True if obs.stakeout else not tainted
        if truth != expected:
            return None
        b = honest_bit(s)
        return b, 0, b
    if r is Role.GOSSIP:
        if s is not Role.GOSSIP:
            return None
        ok = truth if obs.stakeout else obs.clue.holds(w.hidden, w.disguised, offset=1)
        return (0, 0, 0) if ok else None
    # 위장한 역할: 행동대원, 사칭범, 협박꾼, 보스, 취객
    if s not in HONEST_ROLES or (s is Role.COP and r is not Role.IMPOSTER):
        return None
    expected = True if obs.stakeout else False
    if truth != expected:
        return None
    b = honest_bit(s)
    return (b, 0, 0) if r in IN_PLAY_PRETENDERS else (0, b, 0)


def _anonymous_contribution(w: World, i: int, obs: Observation, truth: bool):
    """직업을 모르는 익명 제보. 정직하면 참(단, 오염 대상이면 경관일 수도 있어 참·거짓 모두 가능),
    오지랖이면 +1, 위장 역할이면 거짓. 잠복이면 항상 참."""
    r = w.roles[i]
    if obs.stakeout:
        return (0, 0, 0) if truth else None
    if r is None:
        if w.taint >> i & 1:
            return 0, 0, 0
        return (0, 0, 0) if truth else None
    if r is Role.GOSSIP:
        return (0, 0, 0) if obs.clue.holds(w.hidden, w.disguised, offset=1) else None
    return (0, 0, 0) if not truth else None


def reveal_contribution(w: World, i: int, actual: Role):
    """급습으로 장소 i의 실제 역할이 공개됐을 때."""
    r = w.roles[i]
    if actual in HONEST_ROLES:
        if r is not None:
            return None
        b = honest_bit(actual)
        return b, 0, b
    return (0, 0, 0) if r is actual else None


class CaseAnalyzer:
    """한 사건에 대해 관찰 조합별로 가능한 숨은 곳 집합을 계산한다."""

    def __init__(self, case: Case):
        self.case = case
        self.cf = case.file
        self.truth = case.truth
        self.board = case.file.board
        self.n = self.board.n
        self.worlds = enumerate_worlds(self.cf)
        self.all_mask = (1 << len(self.worlds)) - 1
        self.n_in = self.cf.n_honest
        self.n_out = len(HONEST_ROLES) - self.cf.n_honest
        self._loc: dict = {}
        self._rev: dict = {}

    # ------------------------------------------------------------ 관찰

    def observation(self, i: int, stakeout: bool = False) -> Observation:
        shown = None if i in self.cf.anonymous else self.truth.shown[i]
        if stakeout:
            return Observation(shown, self.truth.stakeout_clues[i], True)
        return Observation(shown, self.truth.clues[i], False)

    def _table(self, i: int, stakeout: bool):
        key = (i, stakeout)
        if key not in self._loc:
            obs = self.observation(i, stakeout)
            ok = 0
            contrib = [None] * len(self.worlds)
            for w_idx, w in enumerate(self.worlds):
                c = local_contribution(w, i, obs)
                if c is not None:
                    ok |= 1 << w_idx
                    contrib[w_idx] = c
            self._loc[key] = (ok, contrib)
        return self._loc[key]

    def _reveal_table(self, i: int):
        if i not in self._rev:
            actual = self.truth.roles[i]
            ok = 0
            contrib = [None] * len(self.worlds)
            for w_idx, w in enumerate(self.worlds):
                c = reveal_contribution(w, i, actual)
                if c is not None:
                    ok |= 1 << w_idx
                    contrib[w_idx] = c
            self._rev[i] = (ok, contrib)
        return self._rev[i]

    # ------------------------------------------------------------ 풀이

    def solve(self, observed: dict[int, bool], revealed=()) -> Counter:
        """observed: {장소: 잠복 여부}, revealed: 급습으로 정체가 공개된 장소들.
        반환: {숨은 곳 비트마스크: 그 경우에 해당하는 세계 수}"""
        mask = self.all_mask
        tables = []
        for i, st in observed.items():
            ok, contrib = self._table(i, st)
            mask &= ok
            tables.append(contrib)
        for i in revealed:
            ok, contrib = self._reveal_table(i)
            mask &= ok
            if i not in observed:
                tables.append(contrib)
        result: Counter = Counter()
        for w_idx in _iter_bits(mask):
            in_m = out_m = hon = 0
            good = True
            for contrib in tables:
                a, b, h = contrib[w_idx]
                if hon & h:
                    good = False
                    break
                hon |= h
                in_m |= a
                out_m |= b
            if not good or in_m & out_m:
                continue
            if popcount(in_m) > self.n_in or popcount(out_m) > self.n_out:
                continue
            result[self.worlds[w_idx].hidden] += 1
        return result

    def unique_with_all(self) -> bool:
        res = self.solve({i: False for i in range(self.n)})
        return len(res) == 1 and next(iter(res)) == self.truth.hidden

    def min_investigations(self, use_stakeout: bool = False, limit: int | None = None):
        """숨은 곳을 하나로 정하는 데 필요한 최소 탐문 수와 그 조합 (급습 정보 없이)."""
        top = self.n if limit is None else min(limit, self.n)
        roadside = {p.index for p in self.board.places if p.roadside}
        for k in range(1, top + 1):
            for subset in combinations(range(self.n), k):
                obs = {i: (use_stakeout and i in roadside) for i in subset}
                if len(self.solve(obs)) == 1:
                    return k, subset
        return None, None

    # ------------------------------------------------------------ 보조 판단

    def _statement_ok(self, h: int, i: int, stakeout: bool) -> bool:
        """'이 사람 말이 참'이라고 믿었을 때 숨은 곳 집합 h와 맞는지 (오지랖 보정 포함)."""
        obs = self.observation(i, stakeout)
        clue = obs.clue
        if clue.type is ClueType.REVEAL:
            hidden_t = bool(h >> clue.target & 1)
            if not clue.claim:
                return not hidden_t          # 진짜라고 했으면 숨은 곳이 아니어야 한다
            # 위장했다고 했으면 숨은 곳이거나, 말썽꾼(취객)일 수 있다
            return hidden_t or self.cf.preset.meddlers > 0
        offset = 1 if (obs.shown is Role.GOSSIP and not stakeout) else 0
        return clue.holds(h, 0, offset=offset)

    def naive_consistent(self, observed: dict[int, bool]) -> bool:
        """들은 말을 전부 믿어도 말이 되는지. False면 누군가의 거짓말을 찾아내야 풀린다."""
        for h in all_hidden_sets(self.n, self.cf.preset.n_evil):
            if all(self._statement_ok(h, i, st) for i, st in observed.items()):
                return True
        return False

    def contradiction_pairs(self, stakeout_for=()) -> list[tuple[int, int]]:
        """둘 다 참일 수 없는 진술 쌍. Gleo 힌트에 쓴다."""
        hs = all_hidden_sets(self.n, self.cf.preset.n_evil)
        pairs = []
        for i, j in combinations(range(self.n), 2):
            si, sj = i in stakeout_for, j in stakeout_for
            if not any(self._statement_ok(h, i, si) and self._statement_ok(h, j, sj) for h in hs):
                pairs.append((i, j))
        return pairs

    @staticmethod
    def evil_probability(result: Counter, n: int) -> list[float]:
        total = sum(result.values())
        if total == 0:
            return [0.0] * n
        return [sum(c for h, c in result.items() if h >> i & 1) / total for i in range(n)]
