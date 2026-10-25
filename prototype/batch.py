"""난이도별로 퍼즐을 대량 생성해서 풀 만한지 통계를 낸다.

python3 batch.py --n 200                 # 모든 난이도
python3 batch.py --n 100 --preset hard --max-min-k 6
결과는 out/batch_<preset>.json 과 화면 요약으로 나온다.
"""
from __future__ import annotations

import argparse
import json
import random
import statistics
import time
from collections import Counter
from multiprocessing import Pool
from pathlib import Path

from puzzle.bot import play
from puzzle.generator import generate_case
from puzzle.model import HONEST_ROLES, Role
from puzzle.rules import PRESETS
from puzzle.solver import CaseAnalyzer

OUT = Path(__file__).resolve().parent / "out"


def run_one(args):
    preset, seed, max_min_k = args
    case = generate_case(preset, seed, max_min_k=max_min_k)
    an = CaseAnalyzer(case)
    t = case.truth
    k, _ = an.min_investigations()
    k_st, _ = an.min_investigations(use_stakeout=True)
    smart = play(case, "smart", analyzer=an)
    smart_ns = play(case, "smart", use_stakeouts=False, analyzer=an)
    rnd = [play(case, "random", rng=random.Random(r), analyzer=an) for r in range(5)]
    shown = Counter(t.shown)
    return {
        "seed": seed,
        "attempts": case.attempts,
        "min_k": k,
        "min_k_stakeout": k_st,
        "liars": sum(1 for i, r in enumerate(t.roles)
                     if not (r in HONEST_ROLES and i not in t.tainted) and r is not Role.GOSSIP),
        "tainted": len(t.tainted),
        "duplicate_claims": sum(1 for c in shown.values() if c > 1),
        "contradiction_pairs": len(an.contradiction_pairs()),
        "roadside": sum(1 for p in case.file.board.places if p.roadside),
        "smart": smart.__dict__ | {"log": None},
        "smart_no_stakeout": smart_ns.__dict__ | {"log": None},
        "random": [r.__dict__ | {"log": None} for r in rnd],
    }


def pct(xs):
    return f"{100 * sum(xs) / len(xs):.0f}%" if xs else "-"


def summarize(preset, rows, budget):
    ks = [r["min_k"] for r in rows if r["min_k"] is not None]
    kst = [r["min_k_stakeout"] for r in rows if r["min_k_stakeout"] is not None]
    sm = [r["smart"] for r in rows]
    sns = [r["smart_no_stakeout"] for r in rows]
    rd = [x for r in rows for x in r["random"]]
    k_hist = Counter(r["min_k"] for r in rows)
    lines = [
        f"## {PRESETS[preset].label} ({preset}) — 퍼즐 {len(rows)}개, 탐문 예산 {budget}",
        f"- 생성 시도 수 평균: {statistics.mean(r['attempts'] for r in rows):.2f}",
        f"- 최소 탐문 수(잠복 없이) 분포: "
        + ", ".join(f"{k}회 {v}" for k, v in sorted(k_hist.items(), key=lambda kv: (kv[0] is None, kv[0] or 0))),
        f"- 최소 탐문 수 평균: 잠복 없이 {statistics.mean(ks):.2f} / 잠복 활용 {statistics.mean(kst):.2f}",
        f"- 최소 탐문 수가 예산 이하: {pct([k is not None and k <= budget for k in (r['min_k'] for r in rows)])}",
        f"- 최소 탐문 수 2 이하(너무 쉬움): {pct([k is not None and k <= 2 for k in (r['min_k'] for r in rows)])}",
        f"- 거짓말쟁이(악역+오염+취객) 평균 {statistics.mean(r['liars'] for r in rows):.2f}명, "
        f"오염 평균 {statistics.mean(r['tainted'] for r in rows):.2f}명, "
        f"같은 직업 중복 있는 판 {pct([r['duplicate_claims'] > 0 for r in rows])}",
        "",
        "| 봇 | 해결률 | 실수 없이 해결 | 찍기 없이 확신으로 해결 | 평균 오급습 | 평균 탐문 | 평균 잠복 | 거짓말 간파가 필요했던 판 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for name, rs in (("smart + 잠복", sm), ("smart, 잠복 없음", sns), ("random + 잠복", rd)):
        lines.append(
            f"| {name} | {pct([r['solved'] for r in rs])} | {pct([r['wrong_raids'] == 0 for r in rs])} "
            f"| {pct([r['certain_before_guess'] for r in rs])} | {statistics.mean(r['wrong_raids'] for r in rs):.2f} "
            f"| {statistics.mean(r['investigations'] for r in rs):.2f} | {statistics.mean(r['stakeouts'] for r in rs):.2f} "
            f"| {pct([r['needed_lie_detection'] for r in rs])} |"
        )
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    ap.add_argument("--preset", choices=list(PRESETS), action="append")
    ap.add_argument("--max-min-k", type=int, default=None,
                    help="이 수 이하 탐문으로 풀리는 퍼즐만 채택")
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    reports = []
    for preset in args.preset or list(PRESETS):
        t0 = time.time()
        with Pool() as pool:
            rows = pool.map(run_one, [(preset, s, args.max_min_k) for s in range(args.n)])
        budget = PRESETS[preset].budget
        (OUT / f"batch_{preset}{args.tag}.json").write_text(
            json.dumps(rows, ensure_ascii=False, indent=1))
        report = summarize(preset, rows, budget) + f"\n\n(소요 {time.time() - t0:.1f}s)\n"
        print(report)
        reports.append(report)
    (OUT / f"batch_summary{args.tag}.md").write_text("\n".join(reports))


if __name__ == "__main__":
    main()
