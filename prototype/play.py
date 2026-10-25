"""터미널에서 한 판 플레이하기.

python3 play.py                         # 보통 난이도, 무작위 사건
python3 play.py --preset hard --seed 12
python3 play.py --seed 3 --cmds "t 2; s 1; l"   # 명령을 미리 넣어 재생 (같은 seed면 같은 사건)

명령: 탐문 N(t N) · 잠복 N(s N) · 급습 N(r N) · 정리(l) · 힌트(h) · 메모 N 태그(m N 의심) · 지도(map) · 도움말(?) · 포기(q)
"""
from __future__ import annotations

import argparse
import random
import sys

from puzzle.game import Game
from puzzle.generator import generate_case
from puzzle.model import indices_of
from puzzle.rules import PRESETS
from puzzle.text import place_label

HELP = """명령어
  탐문 N  (t N)   N번 장소 제보자에게 전화. 통화 1회 사용, 시간이 흐름
  잠복 N  (s N)   길가 장소를 지나가는 동안만. 통화·시간 소모 없음, 진술이 항상 참
  출동 N  (r N)   N번으로 출동. 틀리면 신뢰도 -2
  정리    (l)     지금까지 들은 진술 정리
  힌트    (h)     동시에 참일 수 없는 진술 쌍 하나. 신뢰도 -1
  메모 N 태그 (m N 의심 / m N 무고 / m N -)
  지도    (map)   지도 다시 보기
  포기    (q)     정답 보기"""

ALIASES = {"탐문": "t", "잠복": "s", "급습": "r", "출동": "r", "정리": "l", "힌트": "h", "메모": "m",
           "지도": "map", "도움말": "?", "포기": "q", "help": "?"}


def render_map(game: Game, width: int = 72, height: int = 17) -> str:
    b = game.board
    xs = [p.x for p in b.places] + [x for x, _ in b.route]
    ys = [p.y for p in b.places] + [y for _, y in b.route]
    x0, x1 = min(xs) - 200, max(xs) + 200
    y0, y1 = min(ys) - 200, max(ys) + 200

    def cell(x, y):
        c = int((x - x0) / (x1 - x0) * (width - 4))
        r = int((y1 - y) / (y1 - y0) * (height - 1))
        return r, c

    grid = [[" "] * width for _ in range(height)]
    for x, y in b.route:
        r, c = cell(x, y)
        grid[r][c] = "·"
    # 차량 위치
    car_idx = int(game.progress * (len(b.route) - 1))
    r, c = cell(*b.route[car_idx])
    grid[r][c] = "▶"
    r, c = cell(*b.route[-1])
    grid[r][c] = "◎"
    for p in b.places:
        r, c = cell(p.x, p.y)
        if p.index in game.caught:
            label = f"X{p.id}"
        elif p.index in game.revealed:
            label = f"-{p.id}"
        elif p.index in game.observed:
            label = f"*{p.id}"
        else:
            label = f"{p.id}"
        if p.index in game.memos:
            label += "?" if game.memos[p.index] == "의심" else "!"
        for k, ch in enumerate(label):
            if c + k < width:
                grid[r][c + k] = ch
    lines = ["".join(row).rstrip() for row in grid]
    legend = [
        "  ▶ 내 차  ◎ 목적지  · 경로  *탐문함  X검거  -헛걸음  ?의심 메모   (번호 = 지나가는 순서)",
    ]
    for p in b.places:
        tags = [p.kind, p.side] + (["길가"] if p.roadside else []) \
            + (["익명 제보"] if p.index in game.case.file.anonymous else [])
        lines_place = f"  {place_label(b, p.index)} ({', '.join(tags)})"
        legend.append(lines_place)
    return "\n".join(["┌" + "─" * width + "┐"] + ["│" + ln.ljust(width) + "│" for ln in lines]
                     + ["└" + "─" * width + "┘"] + legend)


def briefing(game: Game) -> str:
    cf = game.case.file
    p = cf.preset
    evil = ", ".join(r.label for r in p.evil)
    lines = [
        f"=== 사건 브리핑 ({p.label}, seed {game.case.seed}) ===",
        f"Gleo: 형사님, 이 경로 주변 {game.n}곳 중 {p.n_evil}곳에 조직원이 숨어 있어요. ({evil})",
    ]
    if p.meddlers:
        lines.append(f"Gleo: 말썽꾼 {p.meddlers}명도 섞여 있어요. 오지랖 주민(숫자를 1 부풀림) "
                     f"또는 취객(판에 없는 직업이라고 착각, 항상 틀린 말).")
    lines.append(f"Gleo: 정직한 직업 7개 중 이번 판에 나온 건 {cf.n_honest}개예요. "
                 f"직업마다 한 명씩만 있어요.")
    lines.append(f"Gleo: 통화(탐문)는 {cf.budget}번. 길가 장소는 지나가는 동안에만 잠복할 수 있어요. "
                 f"지나치면 기회가 사라져요.")
    lines.append("규칙: 조직원은 거짓말을 해요. 행동대원은 판에 있는 직업으로, 협박꾼·보스는 판에 없는 직업으로 "
                 "위장해요. 협박꾼은 가장 가까운 선한 사람 1명을, 보스는 1km 안 정직한 사람을 협박해서 "
                 "거짓말하게 만들어요. 순찰 경관은 협박당하지 않아요.")
    if any(r.name == "IMPOSTER" for r in p.evil):
        lines.append("보이스피싱 사업부: 사칭범은 순찰 경관 행세도 해요. 익명 제보자는 직업을 밝히지 않아요.")
    return "\n".join(lines)


def parse(cmd: str, game: Game) -> list[str] | None:
    parts = cmd.strip().split()
    if not parts:
        return []
    op = ALIASES.get(parts[0], parts[0])
    try:
        arg = int(parts[1]) - 1 if len(parts) > 1 and op in ("t", "s", "r", "m") else None
    except ValueError:
        return ["번호를 숫자로 입력해 주세요."]
    if arg is not None and not 0 <= arg < game.n:
        return ["없는 장소 번호예요."]
    if op in ("t", "s", "r", "m") and arg is None:
        return ["장소 번호가 필요해요. 예: t 3"]
    if op == "t":
        return game.investigate(arg)
    if op == "s":
        return game.stakeout(arg)
    if op == "r":
        return game.raid(arg)
    if op == "m":
        return game.memo(arg, parts[2] if len(parts) > 2 else "의심")
    if op == "l":
        return game.summary()
    if op == "h":
        return game.hint()
    if op == "map":
        return [render_map(game)]
    if op == "?":
        return [HELP]
    if op == "q":
        game.status = "gave_up"
        return []
    return ["모르는 명령이에요. ?를 입력하면 도움말이 나와요."]


def reveal(game: Game) -> str:
    t = game.truth
    lines = ["=== 정답 ==="]
    for i, (r, s) in enumerate(zip(t.roles, t.shown)):
        flags = []
        if t.hidden >> i & 1:
            flags.append("숨은 곳")
        if i in t.tainted:
            flags.append("협박당함")
        disguise = f" (겉으로는 {s.label})" if r is not s else ""
        if i in game.case.file.anonymous:
            disguise += " [익명 제보]"
        lines.append(f"  {place_label(game.board, i)}: {r.label}{disguise}"
                     + (f" — {', '.join(flags)}" if flags else ""))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", default="normal", choices=list(PRESETS))
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--cmds", default=None, help="세미콜론으로 구분한 명령 목록")
    args = ap.parse_args()
    seed = args.seed if args.seed is not None else random.randrange(10_000)
    game = Game(generate_case(args.preset, seed))

    print(briefing(game))
    print(render_map(game))
    for line in game.stakeout_notices():
        print(line)
    print("(? 를 입력하면 명령어가 나와요)")

    scripted = [c for c in (args.cmds or "").split(";") if c.strip()] if args.cmds else None
    while game.status == "playing":
        if scripted is not None:
            if not scripted:
                break
            cmd = scripted.pop(0).strip()
            print(f"\n> {cmd}")
        else:
            try:
                cmd = input("\n> ")
            except EOFError:
                break
        for line in parse(cmd, game) or []:
            print(line)
    if game.status != "playing":
        print(reveal(game))
        hidden = indices_of(game.truth.hidden)
        print(f"결과: {game.status} · 신뢰도 {game.rep} · 탐문 {game.used}/{game.budget} · "
              f"잠복 {sum(game.observed.values())} · 힌트 {game.hints} · 검거 {len(game.caught)}/{len(hidden)}")


if __name__ == "__main__":
    sys.exit(main())
