"""Godot 데모용 퍼즐 팩(JSON) 내보내기.

python3 export_pack.py                                  # 난이도별 10개씩 → out/pack/
python3 export_pack.py --per-preset 20 --out ../godot/data/puzzles
python3 export_pack.py --only normal:101 hard:202       # 특정 사건만

채택 조건: 9곳 전부 탐문하면 답이 하나 + smart 봇이 잠복을 써서 찍기 없이 풀 수 있음.
스키마 설명: docs/puzzle-pack-schema.md
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from puzzle.board import ROADSIDE_M
from puzzle.bot import play
from puzzle.game import ANON_LABEL, HINT_COST, START_REPUTATION, WRONG_RAID_COST
from puzzle.generator import Case, generate_case
from puzzle.model import (
    CLUES_OF_ROLE, COUNT_CLUES, EVIL_ROLES, HONEST_ROLES, MEDDLER_ROLES, Clue, ClueType, Role,
    indices_of,
)
from puzzle.rules import (
    BOSS_TAINT_M, FINAL_PHASE_START, PRESETS, RAID_TIME, STAKEOUT_LOOKAHEAD, STAKEOUT_PASS, call_time,
)
from puzzle.solver import CaseAnalyzer
from puzzle.text import fact, speak

SCHEMA = "gleo-mafia.puzzle/3"
OUT = Path(__file__).resolve().parent / "out" / "pack"
LANDMARKS_JSON = Path(__file__).resolve().parents[1] / "godot" / "assets" / "models" / "landmarks" / "landmarks.json"
DEST_NAME = "해커톤 행사장"
ORIGIN_NAME = "출발지"


def _landmark_map() -> dict:
    """장소 이름 → 업종 순서로 랜드마크 모델 id를 찾는 표 (Blender 세션이 만든 landmarks.json)."""
    if LANDMARKS_JSON.exists():
        return json.loads(LANDMARKS_JSON.read_text())
    return {"by_name": {}, "by_kind": {}}


LANDMARKS = _landmark_map()


def landmark_of(name: str, kind: str) -> str:
    return LANDMARKS["by_name"].get(name) or LANDMARKS["by_kind"].get(kind, "")


def _r(v: float) -> float:
    return round(v, 1)


def _poly(poly) -> list:
    return [[_r(x), _r(y)] for x, y in poly]


def city_json(board) -> dict | None:
    """가상 도시 보드면 도로·강·공원·블록과 경로 계획을 내보낸다."""
    if not board.world:
        return None
    from puzzle.city import LANES
    city = board.world["city"]
    plan = board.world["plan"]
    return {
        "city": {
            # 격자 크기: nodes는 행 우선(j * cols + i). 강은 river행과 river+1행 사이.
            # Godot이 도시 바깥 외곽(그림만)을 이어 그릴 때 쓴다.
            "grid": {"cols": max(i for i, _ in city.grid) + 1, "rows": max(j for _, j in city.grid) + 1,
                     "river": city.river_rows[0]},
            "nodes": [[_r(x), _r(y)] for x, y in city.nodes],
            "roads": [{"a": e.a, "b": e.b, "cls": e.cls, "name": e.name, "lanes": LANES[e.cls]}
                      for e in city.edges],
            "water": [_poly(w) for w in city.water],
            "parks": [_poly(pk) for pk in city.parks],
            "blocks": [_poly(bk) for bk in city.blocks],
        },
        "routePlan": {
            "length": _r(plan["length"]),
            "nodes": plan["nodes"],
            "nodeS": [_r(v) for v in plan["node_s"]],
            "segments": [{"name": sg["name"], "cls": sg["cls"], "from": _r(sg["from"]), "to": _r(sg["to"]),
                          "cruise": sg["cruise"]} for sg in plan["segments"]],
            "maneuvers": [{**m, "s": _r(m["s"])} for m in plan["maneuvers"]],
            "stops": [{"s": _r(st["s"]), "dwell": round(st["dwell"], 1), "node": st["node"]}
                      for st in plan["stops"]],
            "tunnels": [{"from": _r(t["from"]), "to": _r(t["to"]), "name": t["name"]} for t in plan["tunnels"]],
            "waypoints": plan["waypoints"],
            "originName": ORIGIN_NAME,
            "destName": DEST_NAME,
        },
    }


def ids(mask: int) -> list[int]:
    return [i + 1 for i in indices_of(mask)]


def clue_json(clue: Clue, case: Case) -> dict:
    b = case.file.board
    d: dict = {"type": clue.type.value}
    if clue.type in COUNT_CLUES:
        d["count"] = clue.count
        d["members"] = ids(clue.region)
    if clue.type is ClueType.RADIUS:
        d |= {"center": clue.center + 1, "radiusM": clue.radius}
    elif clue.type is ClueType.SPAN:
        d |= {"from": clue.lo + 1, "to": clue.hi + 1}
    elif clue.type is ClueType.SIDE:
        d |= {"side": clue.side}
    elif clue.type is ClueType.NEIGHBOR:
        d |= {"center": clue.center + 1}
    elif clue.type is ClueType.KIND:
        d |= {"kind": clue.kind}
    elif clue.type is ClueType.ROAD:
        d |= {"bufferM": ROADSIDE_M}
    elif clue.type is ClueType.VOUCH:
        d |= {"target": clue.target + 1, "claim": "suspicious" if clue.claim else "clean"}
    elif clue.type is ClueType.REVEAL:
        d |= {"target": clue.target + 1, "claim": "disguised" if clue.claim else "genuine"}
    return d


def statement_json(case: Case, i: int, clue: Clue) -> dict:
    b = case.file.board
    shown = None if i in case.file.anonymous else case.truth.shown[i]
    return {"clue": clue_json(clue, case), "fact": fact(clue, b), "line": speak(clue, b, shown)}


def contradictions(an: CaseAnalyzer) -> list[dict]:
    """동시에 참일 수 없는 진술 쌍. 잠복 진술(항상 참)과의 조합도 포함."""
    n = an.n
    # 잠복 진술은 모든 장소에 있다(길가 + 경유지 잠복)
    variants = [(i, False) for i in range(n)] + [(i, True) for i in range(n)]
    from puzzle.generator import all_hidden_sets
    hs = all_hidden_sets(n, an.cf.preset.n_evil)
    out = []
    for x in range(len(variants)):
        for y in range(x + 1, len(variants)):
            (a, sa), (b, sb) = variants[x], variants[y]
            if a == b:
                continue
            if not any(an._statement_ok(h, a, sa) and an._statement_ok(h, b, sb) for h in hs):
                out.append({"a": a + 1, "aStakeout": sa, "b": b + 1, "bStakeout": sb})
    return out


def roles_table() -> dict:
    table = {}
    for r in HONEST_ROLES:
        table[r.name] = {"label": r.label, "side": "honest",
                         "clues": [c.value for c in CLUES_OF_ROLE[r]]}
    for r in MEDDLER_ROLES:
        table[r.name] = {"label": r.label, "side": "meddler"}
    for r in EVIL_ROLES:
        table[r.name] = {"label": r.label, "side": "evil"}
    return table


def case_json(case: Case, an: CaseAnalyzer) -> dict:
    b = case.file.board
    t = case.truth
    p = case.file.preset
    k, _ = an.min_investigations()
    k_st, _ = an.min_investigations(use_stakeout=True)
    bot = play(case, "smart", analyzer=an)
    return {
        "schema": SCHEMA,
        "id": f"{p.key}-{case.seed}",
        "seed": case.seed,
        "preset": {"key": p.key, "label": p.label, "budget": case.file.budget,
                   "evil": [r.name for r in p.evil], "meddlers": p.meddlers,
                   "meddlerTypes": [r.name for r in case.file.meddler_types]},
        "nHonest": case.file.n_honest,
        "rules": {"startReputation": START_REPUTATION, "wrongRaidCost": WRONG_RAID_COST,
                  "hintCost": HINT_COST, "roadsideM": ROADSIDE_M, "bossTaintM": BOSS_TAINT_M,
                  "finalPhaseStart": FINAL_PHASE_START, "callTime": round(call_time(case.file.budget), 4),
                  "raidTime": RAID_TIME, "stakeoutLookahead": STAKEOUT_LOOKAHEAD,
                  "stakeoutPass": STAKEOUT_PASS},
        "roles": roles_table(),
        "anonymousLabel": ANON_LABEL,
        "units": "m, x=east y=north, origin=route start",
        "route": [[x, y] for x, y in b.route],
        "places": [{"id": pl.id, "name": pl.name, "kind": pl.kind, "x": pl.x, "y": pl.y,
                    "side": pl.side, "roadside": pl.roadside, "routePos": pl.route_pos,
                    "routeDistM": pl.route_dist, "anonymous": pl.index in case.file.anonymous,
                    "landmark": landmark_of(pl.name, pl.kind)}
                   for pl in b.places],
        "statements": [
            {"placeId": i + 1,
             "shownRole": None if i in case.file.anonymous else t.shown[i].name,
             **statement_json(case, i, t.clues[i]),
             "stakeout": statement_json(case, i, t.stakeout_clues[i]) if i in t.stakeout_clues else None}
            for i in range(b.n)
        ],
        **(city_json(b) or {}),
        "truth": {"hidden": ids(t.hidden), "roles": [r.name for r in t.roles],
                  "shownRoles": [r.name for r in t.shown],
                  "tainted": sorted(i + 1 for i in t.tainted)},
        "hints": {"contradictions": contradictions(an)},
        "analysis": {"minInvestigations": k, "minInvestigationsWithStakeout": k_st,
                     "botInvestigations": bot.investigations, "botStakeouts": bot.stakeouts,
                     "botWrongRaids": bot.wrong_raids,
                     "botSolvedWithoutGuess": bot.certain_before_guess},
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-preset", type=int, default=10)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--only", nargs="*", help="preset:seed 목록 (자동 선별 없이 이것만)")
    ap.add_argument("--extra", nargs="*", default=[], help="자동 선별에 더할 preset:seed 목록")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    targets: list[tuple[str, int]] = []
    for s in (args.only or []) + args.extra:
        targets.append((s.split(":")[0], int(s.split(":")[1])))
    index = []
    for key in PRESETS if not args.only else []:
        seed, got = 1000, 0
        while got < args.per_preset:
            case = generate_case(key, seed)
            an = CaseAnalyzer(case)
            if play(case, "smart", analyzer=an).certain_before_guess:
                targets.append((key, seed))
                got += 1
            seed += 1
    for key, seed in targets:
        case = generate_case(key, seed)
        data = case_json(case, CaseAnalyzer(case))
        path = args.out / f"{data['id']}.json"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1))
        index.append({"id": data["id"], "preset": key, "file": path.name,
                      "minInvestigations": data["analysis"]["minInvestigations"]})
    (args.out / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1))
    print(f"{len(index)}개 퍼즐 → {args.out}")


if __name__ == "__main__":
    main()
