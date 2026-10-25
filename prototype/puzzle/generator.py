"""퍼즐 생성기: 보드 생성 → 진실 배정 → 진술 생성 → 검증.

진실(누가 어디 숨었는지)은 여기서만 정한다. LLM은 이 결과를 말투로 바꾸기만 한다.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field, replace
from functools import lru_cache
from itertools import combinations

from .board import RADIUS_OPTIONS_M, SIDES, Board, make_board, make_city_board
from .model import (
    CLUES_OF_ROLE, COUNT_CLUES, GOSSIP_CLUES, HONEST_ROLES, MEDDLER_ROLES, Clue, ClueType, Role,
    is_disguised, is_evil, mask_of, popcount,
)
from .rules import PRESETS, Preset, taint_candidates

SPAN_LENGTHS = (3, 4, 5)


@dataclass
class CaseFile:
    """플레이어에게 공개되는 사건 파일."""
    board: Board
    preset: Preset
    n_honest: int                 # 이번 판에 나온 정직 직업 수 (7개 중)
    budget: int
    meddler_types: tuple[Role, ...] = MEDDLER_ROLES
    anonymous: frozenset[int] = field(default_factory=frozenset)   # 직업을 밝히지 않는 장소


@dataclass
class Truth:
    """엔진만 아는 진실."""
    roles: list[Role]
    shown: list[Role]             # 탐문했을 때 밝히는 직업 (익명 장소는 화면에 보이지 않음)
    tainted: frozenset[int]
    clues: list[Clue]             # 일반 탐문 진술
    stakeout_clues: dict[int, Clue]  # 잠복 찬스 진술(항상 참). 길가 장소만

    @property
    def hidden(self) -> int:
        return mask_of(i for i, r in enumerate(self.roles) if is_evil(r))

    @property
    def disguised(self) -> int:
        return mask_of(i for i, r in enumerate(self.roles) if is_disguised(r))


@dataclass
class Case:
    seed: int
    file: CaseFile
    truth: Truth
    attempts: int = 1


@lru_cache(maxsize=None)
def all_hidden_sets(n: int, k: int) -> tuple[int, ...]:
    return tuple(mask_of(c) for c in combinations(range(n), k))


def _entropy(region: int, hs: tuple[int, ...]) -> float:
    counts: dict[int, int] = {}
    for h in hs:
        c = popcount(h & region)
        counts[c] = counts.get(c, 0) + 1
    total = len(hs)
    return -sum(v / total * math.log2(v / total) for v in counts.values())


def _count_candidates(board: Board, i: int, ctype: ClueType) -> list[Clue]:
    if ctype is ClueType.RADIUS:
        return [Clue(ctype, region=board.radius_region(i, r), center=i, radius=r)
                for r in RADIUS_OPTIONS_M]
    if ctype is ClueType.SPAN:
        return [Clue(ctype, region=board.span_region(lo, lo + ln - 1), lo=lo, hi=lo + ln - 1)
                for ln in SPAN_LENGTHS for lo in range(board.n - ln + 1)]
    if ctype is ClueType.SIDE:
        return [Clue(ctype, region=board.side_region(s), side=s) for s in SIDES]
    if ctype is ClueType.NEIGHBOR:
        return [Clue(ctype, region=mask_of(board.route_neighbors(i)), center=i)]
    if ctype is ClueType.KIND:
        groups = board.kinds()
        multi = {k: v for k, v in groups.items() if len(v) >= 2} or groups
        return [Clue(ctype, region=mask_of(v), kind=k) for k, v in multi.items()]
    return [Clue(ClueType.ROAD, region=board.road_region)]


def _choose_count_params(board, i, ctypes, rng, hs) -> Clue:
    cands = [c for t in ctypes for c in _count_candidates(board, i, t)]
    useful = [c for c in cands if 1 <= popcount(c.region) <= board.n - 1] or cands
    useful.sort(key=lambda c: -_entropy(c.region, hs))
    return rng.choice(useful[:2])


def _make_clue(board: Board, i: int, shown: Role, actual: Role, tainted: bool, anonymous: bool,
               hidden: int, disguised: int, n_evil: int, rng: random.Random) -> Clue:
    if actual is Role.GOSSIP:
        mode = "gossip"
    elif actual in HONEST_ROLES and not tainted:
        mode = "true"
    else:
        mode = "lie"

    # 익명 제보는 직업 능력 대신 '들은 소문'(숫자 단서)을 말한다
    ctypes = GOSSIP_CLUES if (anonymous or shown is Role.GOSSIP) else CLUES_OF_ROLE[shown]
    others = [j for j in range(board.n) if j != i]

    if ctypes[0] in COUNT_CLUES:
        base = _choose_count_params(board, i, ctypes, rng, all_hidden_sets(board.n, n_evil))
        c = popcount(hidden & base.region)
        if mode == "true":
            v = c
        elif mode == "gossip":
            v = c + 1
        else:
            hi = min(n_evil, popcount(base.region))
            v = rng.choice([x for x in range(hi + 1) if x != c] or [c + 1])
        return replace(base, count=v)

    if ctypes[0] is ClueType.VOUCH:
        hid = [j for j in others if hidden >> j & 1]
        clean = [j for j in others if not hidden >> j & 1]
        if mode == "true":
            # 정직한 경비원: 40%는 실제 숨은 곳을 고발, 나머지는 깨끗한 곳을 보증
            if hid and rng.random() < 0.4:
                return Clue(ClueType.VOUCH, target=rng.choice(hid), claim=True)
            return Clue(ClueType.VOUCH, target=rng.choice(clean), claim=False)
        # 거짓말: 절반은 숨은 곳(동료)을 감싸고, 절반은 깨끗한 사람을 모함
        if hid and rng.random() < 0.5:
            return Clue(ClueType.VOUCH, target=rng.choice(hid), claim=False)
        return Clue(ClueType.VOUCH, target=rng.choice(clean), claim=True)

    # REVEAL: 가장 가까운 장소의 제보자가 위장했는지
    t = board.nearest(i)
    actual_d = bool(disguised >> t & 1)
    return Clue(ClueType.REVEAL, target=t, claim=actual_d if mode == "true" else not actual_d)


def truthful_version(clue: Clue, hidden: int, disguised: int) -> Clue:
    a = clue.actual(hidden, disguised)
    if clue.type in COUNT_CLUES:
        return replace(clue, count=a)
    return replace(clue, claim=a)


def _generate_once(preset: Preset, rng: random.Random, seed: int, n: int, board_kind: str = "city") -> Case:
    board = make_city_board(rng, n) if board_kind == "city" else make_board(rng, n)
    meddlers = [rng.choice(MEDDLER_ROLES) for _ in range(preset.meddlers)]
    n_honest = n - preset.n_evil - len(meddlers)
    needs_decoy = (any(r in (Role.BLACKMAILER, Role.BOSS) for r in preset.evil)
                   or Role.DRUNK in meddlers)
    for _ in range(200):
        in_play = rng.sample(HONEST_ROLES, n_honest)
        decoys = [r for r in HONEST_ROLES if r not in in_play and r is not Role.COP]
        if (decoys or not needs_decoy) and (Role.COP in in_play or not preset.force_cop_claim):
            break

    order = rng.sample(range(n), n)
    roles: list[Role | None] = [None] * n
    specials = list(preset.evil) + meddlers
    for k, r in enumerate(specials):
        roles[order[k]] = r
    for k, r in enumerate(rng.sample(in_play, len(in_play))):
        roles[order[len(specials) + k]] = r

    claimable_in = [r for r in in_play if r is not Role.COP]
    shown = []
    for r in roles:
        if r in HONEST_ROLES or r is Role.GOSSIP:
            shown.append(r)
        elif r is Role.THUG:
            shown.append(rng.choice(claimable_in))      # 판에 있는 직업으로 위장
        elif r is Role.IMPOSTER:
            # 사칭범: 판에 있는 직업으로 위장하되 경관 행세도 한다
            shown.append(Role.COP if preset.force_cop_claim else rng.choice(in_play))
        else:
            shown.append(rng.choice(decoys))            # 판에 없는 직업으로 위장/착각

    # 익명 제보자: 오지랖 주민이 아닌 장소 중에서 고른다
    anon_pool = [i for i in range(n) if roles[i] is not Role.GOSSIP]
    anonymous = frozenset(rng.sample(anon_pool, preset.anonymous))

    cand = taint_candidates(board, roles)
    tainted = frozenset(
        i for i in range(n)
        if cand >> i & 1 and roles[i] in HONEST_ROLES and roles[i] is not Role.COP
    )
    hidden = mask_of(i for i, r in enumerate(roles) if is_evil(r))
    disguised = mask_of(i for i, r in enumerate(roles) if is_disguised(r))
    clues = [
        _make_clue(board, i, shown[i], roles[i], i in tainted, i in anonymous, hidden, disguised,
                   preset.n_evil, rng)
        for i in range(n)
    ]
    # 잠복 진술(항상 참). 길가 장소 + 경유지 잠복(데모 규칙)을 위해 모든 장소에 만든다.
    # 솔버·봇은 길가 장소의 잠복만 쓴다.
    stakeouts = {
        p.index: truthful_version(clues[p.index], hidden, disguised)
        for p in board.places
    }
    file = CaseFile(board=board, preset=preset, n_honest=n_honest, budget=preset.budget,
                    anonymous=anonymous)
    return Case(seed=seed, file=file, truth=Truth(roles, shown, tainted, clues, stakeouts))


def generate_case(preset_key: str = "normal", seed: int = 0, n_places: int = 9,
                  require_unique: bool = True, max_min_k: int | None = None,
                  max_attempts: int = 400, board_kind: str = "city") -> Case:
    """검증을 통과한 사건 하나를 만든다.

    board_kind: "city"(가상 도시 + A* 경로, 기본) 또는 "synthetic"(예전 곡선 경로, 테스트용)

    require_unique: 9곳을 모두 탐문하면 숨은 곳이 하나로 정해져야 한다.
    max_min_k: 정해지면, 그 수 이하의 탐문으로 숨은 곳이 하나로 정해지는 조합이 있어야 한다.
    """
    from .solver import CaseAnalyzer

    preset = PRESETS[preset_key]
    rng = random.Random(seed)
    for attempt in range(1, max_attempts + 1):
        case = _generate_once(preset, rng, seed, n_places, board_kind)
        case.attempts = attempt
        if not require_unique and max_min_k is None:
            return case
        an = CaseAnalyzer(case)
        if require_unique and not an.unique_with_all():
            continue
        if max_min_k is not None:
            k, _ = an.min_investigations(limit=max_min_k)
            if k is None:
                continue
        return case
    raise RuntimeError(f"{max_attempts}번 시도해도 조건을 만족하는 퍼즐을 못 만들었다")
