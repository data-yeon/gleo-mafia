"""튜토리얼 '수습 첫날' 퍼즐 팩 만들기.

장소 6곳, 숨은 곳 1곳(행동대원 1명), 말썽꾼 없음, 통화 5번. 아래 '아하' 순서가 반드시 나오는 판을 시드에서 고른다.
1. 첫 통화(A, 정직): 믿으면 경우가 6 → 2~4가지로 준다.
2. 같은 직업 두 명(T 행동대원, D 정직): T는 D의 직업으로 위장한다.
3. A·T·D를 다 믿으면 0가지(말이 안 맞음) → 하나를 빼야 한다.
4. 길가 R을 현장 확인(항상 참): T의 말과는 안 맞고, A·D·R을 믿으면 1가지(= T)만 남는다.
5. 출동 → 검거.
판정은 Godot의 용의 장소 검색(CaseDeduction)과 같다: 개수 단서, 보증(VOUCH), 신분 확인 '진짜'만 조건이고
'위장'(REVEAL disguised)은 판단 보류라, 튜토리얼에서는 그런 진술을 쓰지 않는다.

python3 tutorial_pack.py                       # → ../godot/data/puzzles/tutorial-<seed>.json
python3 tutorial_pack.py --seed 5000 --out out/pack
"""
from __future__ import annotations

import argparse
import json
import random
from itertools import combinations
from pathlib import Path

from export_pack import case_json
from puzzle.generator import _generate_once
from puzzle.model import COUNT_CLUES, Clue, ClueType, Role, popcount
from puzzle.rules import Preset
from puzzle.solver import CaseAnalyzer

PRESET = Preset("tutorial", "수습 첫날", (Role.THUG,), 0, 5)
N = 6
OUT = Path(__file__).resolve().parents[1] / "godot" / "data" / "puzzles"


def soft(c: Clue) -> bool:
    return c.type is ClueType.REVEAL and c.claim


def ok(c: Clue, h: int) -> bool:
    """CaseDeduction._condition과 같은 판정(믿은 말 하나가 숨은 곳 조합 h에서 맞는지)."""
    if c.type in COUNT_CLUES:
        return popcount(h & c.region) == c.count
    if c.type is ClueType.VOUCH:
        return bool(h >> c.target & 1) == c.claim
    if c.type is ClueType.REVEAL:
        return True if c.claim else not (h >> c.target & 1)
    return True


def live(clues: list[Clue]) -> list[int]:
    return [1 << i for i in range(N) if all(ok(c, 1 << i) for c in clues)]


def find(seed: int) -> dict | None:
    rng = random.Random(seed)
    case = _generate_once(PRESET, rng, seed, N)
    if not CaseAnalyzer(case).unique_with_all():
        return None
    t = case.truth
    places = case.file.board.places
    thug = next(i for i, r in enumerate(t.roles) if r is Role.THUG)
    dups = [i for i in range(N) if i != thug and t.shown[i] is t.shown[thug]]
    if len(dups) != 1:
        return None
    d = dups[0]
    if soft(t.clues[thug]) or soft(t.clues[d]):
        return None
    best = None
    for a in range(N):
        if a in (thug, d) or soft(t.clues[a]):
            continue
        n_a = len(live([t.clues[a]]))
        if not 2 <= n_a <= 4:
            continue
        if live([t.clues[a], t.clues[thug], t.clues[d]]):
            continue                                    # 셋을 다 믿으면 0가지여야 한다
        for r in range(N):
            if r in (a, d, thug) or not places[r].roadside or places[r].route_pos < 0.3:
                continue
            st = t.stakeout_clues[r]
            if soft(st):
                continue
            if live([t.clues[a], t.clues[d], st]) != [1 << thug]:
                continue
            if live([t.clues[a], t.clues[thug], st]):
                continue                                # 현장 확인이 T의 말을 반박해야 한다
            # 통화 세 곳은 지나가는 순서가 R보다 앞이면 좋다(먼저 듣고, 지나가며 확인)
            score = (places[r].route_pos - max(places[x].route_pos for x in (a, d, thug)), -n_a)
            if best is None or score > best[0]:
                best = (score, a, r)
    if best is None:
        return None
    _, a, r = best
    pair = sorted([thug, d], key=lambda i: places[i].route_pos)
    data = case_json(case, CaseAnalyzer(case))
    data["id"] = f"tutorial-{seed}"
    # 튜토리얼 대본: 플레이어가 누를 곳(정답 자체는 truth에 있다)
    data["tutorial"] = {"first": a + 1, "pair": [i + 1 for i in pair], "stakeout": r + 1}
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=5000, help="여기서부터 시드를 찾는다")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()
    for seed in range(args.seed, args.seed + 3000):
        data = find(seed)
        if data is None:
            continue
        args.out.mkdir(parents=True, exist_ok=True)
        path = args.out / f"{data['id']}.json"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1))
        tut = data["tutorial"]
        print(f"{path.name}: 첫 통화 {tut['first']}, 같은 직업 {tut['pair']}, 현장 확인 {tut['stakeout']}, "
              f"숨은 곳 {data['truth']['hidden']}")
        return
    raise SystemExit("조건에 맞는 튜토리얼 판을 못 찾았다")


if __name__ == "__main__":
    main()
