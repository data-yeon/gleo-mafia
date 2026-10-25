"""자동 플레이 봇: 퍼즐이 예산 안에서 풀리는지, 실수 없이 풀리는지 대략 가늠한다.

smart  : 확실한 곳은 바로 급습하고, 남은 탐문은 '아직 애매한 곳'과 '깨끗해 보이는 곳'을 우선한다.
random : 탐문할 곳을 무작위로 고른다(아무 생각 없이 하는 플레이어의 하한선).
두 봇 모두 확실해지면 급습하고, 예산이 끝나면 가장 의심스러운 곳부터 찍어서 급습한다.
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field

from .generator import Case
from .rules import RAID_TIME, call_time, stakeout_open
from .solver import CaseAnalyzer

START_REPUTATION = 5
WRONG_RAID_COST = 2


@dataclass
class BotResult:
    solved: bool
    investigations: int
    stakeouts: int
    raids: int
    wrong_raids: int
    reputation: int
    needed_lie_detection: bool
    certain_before_guess: bool      # 찍기 없이 확신만으로 다 잡았는지
    log: list[str] = field(default_factory=list)


def play(case: Case, policy: str = "smart", use_stakeouts: bool = True,
         rng: random.Random | None = None, analyzer: CaseAnalyzer | None = None) -> BotResult:
    rng = rng or random.Random(0)
    an = analyzer or CaseAnalyzer(case)
    n = case.file.board.n
    places = case.file.board.places
    budget = case.file.budget
    truth_hidden = case.truth.hidden

    observed: dict[int, bool] = {}
    revealed: list[int] = []
    caught: set[int] = set()
    rep = START_REPUTATION
    used = stakes = raids = wrong = 0
    clock = 0.0
    guessed = False
    log: list[str] = []
    roadside = sorted((p.index for p in places if p.roadside), key=lambda i: places[i].route_pos)

    def raid(i: int):
        nonlocal rep, raids, wrong, clock
        raids += 1
        clock += RAID_TIME
        revealed.append(i)
        if truth_hidden >> i & 1:
            caught.add(i)
            log.append(f"급습 {i + 1}번 → 검거")
        else:
            wrong += 1
            rep -= WRONG_RAID_COST
            log.append(f"급습 {i + 1}번 → 오급습 (신뢰도 {rep})")

    while True:
        if caught == {i for i in range(n) if truth_hidden >> i & 1}:
            break
        if rep <= 0:
            break
        res = an.solve(observed, revealed)
        hs = list(res)
        must = hs[0]
        for h in hs[1:]:
            must &= h
        sure = [i for i in range(n) if must >> i & 1 and i not in caught]
        if sure:
            raid(sure[0])
            continue

        avail = [i for i in roadside if i not in observed
                 and stakeout_open(places[i].route_pos, clock)]
        if use_stakeouts and avail:
            observed[avail[0]] = True
            stakes += 1
            log.append(f"잠복 {avail[0] + 1}번")
            continue

        probs = CaseAnalyzer.evil_probability(res, n)
        if used < budget:
            cands = [i for i in range(n) if i not in observed and i not in revealed]
            if cands:
                if policy == "random":
                    pick = rng.choice(cands)
                else:
                    rng.shuffle(cands)
                    pick = max(cands, key=lambda i: probs[i] * (1 - probs[i]) + 0.25 * (1 - probs[i]))
                observed[pick] = False
                used += 1
                clock = used * call_time(budget)
                log.append(f"탐문 {pick + 1}번 (후보 {len(hs)}가지)")
                continue

        # 예산 소진: 가장 의심스러운 곳을 찍는다
        guessed = True
        cands = [i for i in range(n) if i not in caught and i not in revealed]
        pick = max(cands, key=lambda i: (probs[i], rng.random()))
        raid(pick)

    final_obs = {i: st for i, st in observed.items()}
    return BotResult(
        solved=rep > 0,
        investigations=used,
        stakeouts=stakes,
        raids=raids,
        wrong_raids=wrong,
        reputation=rep,
        needed_lie_detection=not an.naive_consistent(final_obs) if final_obs else False,
        certain_before_guess=not guessed,
        log=log,
    )
