"""한 사건의 진행 상태와 규칙 (입출력 없음). 룰 v1(내비 Dupery).

Godot 런타임(godot/scripts/puzzle_case.gd)은 이 클래스와 같은 규칙으로 구현한다.
- 시간: 이동 전체를 진행률 0..1로 본다. 탐문(통화) 한 번에 call_time만큼, 출동 한 번에 RAID_TIME만큼 흐른다.
- 탐문: 예산(통화 수) 1 소모. 예산을 다 쓰면 도착 5분 전 = 최종 단계(출동만, 기회 = 남은 조직원 + 1)
- 잠복: 길가 장소에 다가갈 때부터 지나칠 때까지만. 예산·시간 소모 없음. 진술은 항상 참
- 출동(급습): 정체 공개. 숨은 곳이 아니면 신뢰도 -2
- 힌트: 들은 진술 중 동시에 참일 수 없는 쌍 하나를 알려준다. 신뢰도 -1
- 익명 제보자는 직업을 밝히지 않는다
"""
from __future__ import annotations

from collections import Counter

from .generator import Case
from .model import Role, indices_of
from .rules import FINAL_PHASE_START, RAID_TIME, STAKEOUT_PASS, call_time, stakeout_open
from .solver import CaseAnalyzer
from .text import euro, fact, irago, josa, num, pid, place_label, speak, was

START_REPUTATION = 5
WRONG_RAID_COST = 2
HINT_COST = 1
ANON_LABEL = "익명 제보"


class Game:
    def __init__(self, case: Case):
        self.case = case
        self.board = case.file.board
        self.truth = case.truth
        self.an = CaseAnalyzer(case)
        self.n = self.board.n
        self.observed: dict[int, bool] = {}
        self.revealed: list[int] = []
        self.caught: set[int] = set()
        self.memos: dict[int, str] = {}
        self.rep = START_REPUTATION
        self.used = 0
        self.hints = 0
        self.clock = 0.0                    # 이동 진행률
        self.final_raids_left: int | None = None
        self.status = "playing"           # playing | won | fired | escaped
        self.announced_stakeouts: set[int] = set()
        self.announced_missed: set[int] = set()

    # ------------------------------------------------------------ 상태

    @property
    def budget(self) -> int:
        return self.case.file.budget

    @property
    def n_evil(self) -> int:
        return self.case.file.preset.n_evil

    @property
    def progress(self) -> float:
        return min(1.0, self.clock)

    @property
    def final_phase(self) -> bool:
        return self.final_raids_left is not None

    def shown_label(self, i: int) -> str:
        return ANON_LABEL if i in self.case.file.anonymous else self.truth.shown[i].label

    def stakeout_available(self) -> list[int]:
        return [p.index for p in self.board.places
                if p.roadside and p.index not in self.observed
                and stakeout_open(p.route_pos, self.progress)]

    def stakeout_missed(self) -> list[int]:
        return [p.index for p in self.board.places
                if p.roadside and p.index not in self.observed
                and self.progress > p.route_pos + STAKEOUT_PASS]

    def stakeout_notices(self) -> list[str]:
        out = []
        for i in self.stakeout_available():
            if i not in self.announced_stakeouts:
                self.announced_stakeouts.add(i)
                p = self.board.places[i]
                out.append(f"Gleo: 곧 {p.side} {josa(place_label(self.board, i), '을를')} 지나가요. "
                           f"잠복할까요? (잠복 {i + 1})")
        for i in self.stakeout_missed():
            if i not in self.announced_missed:
                self.announced_missed.add(i)
                out.append(f"Gleo: {josa(place_label(self.board, i), '을를')} 지나쳤어요. 잠복 기회가 사라졌어요.")
        return out

    # ------------------------------------------------------------ 행동

    def investigate(self, i: int) -> list[str]:
        if self.final_phase:
            return ["Gleo: 조직이 눈치챘어요. 이제는 출동만 할 수 있어요."]
        if i in self.observed:
            return [f"Gleo: {num(i)}은 이미 탐문했어요."]
        self.observed[i] = False
        self.used += 1
        self.clock = self.used * call_time(self.budget)
        out = self._statement_lines(i, stakeout=False)
        out += self._after_action()
        return out

    def stakeout(self, i: int) -> list[str]:
        if i not in self.stakeout_available():
            p = self.board.places[i]
            if p.roadside and i not in self.observed:
                if self.progress < p.route_pos:
                    return ["Gleo: 아직 그 근처를 지나지 않았어요."]
                return ["Gleo: 이미 지나쳤어요."]
            return ["Gleo: 거기서는 잠복할 수 없어요."]
        self.observed[i] = True
        out = ["Gleo: 잠복 성공. 이 사람 말은 확실해요."]
        out += self._statement_lines(i, stakeout=True)
        out += self._after_action()
        return out

    def raid(self, i: int) -> list[str]:
        if i in self.revealed:
            return [f"Gleo: {num(i)}은 이미 출동했어요."]
        self.revealed.append(i)
        self.clock += RAID_TIME
        actual = self.truth.roles[i]
        out = []
        if self.truth.hidden >> i & 1:
            self.caught.add(i)
            out.append(f"Gleo: 검거! {josa(place_label(self.board, i), '은는')} "
                       f"{euro(self.shown_label(i))} 숨어 있던 {was(actual.label)}.")
        else:
            self.rep -= WRONG_RAID_COST
            out.append(f"Gleo: 헛걸음이에요… {place_label(self.board, i)}의 제보자는 "
                       f"{was(actual.label)}. 신뢰도 -{WRONG_RAID_COST} (남은 신뢰도 {self.rep})")
        if self.final_phase:
            self.final_raids_left -= 1
        out += self._check_end()
        out += self.stakeout_notices()
        return out

    def hint(self) -> list[str]:
        stakeouts = {i for i, st in self.observed.items() if st}
        pairs = [(a, b) for a, b in self.an.contradiction_pairs(stakeout_for=stakeouts)
                 if a in self.observed and b in self.observed]
        if not pairs:
            return ["Gleo: 지금까지 들은 말 중엔 서로 부딪히는 게 없어요. 더 탐문해 보세요."]
        self.rep -= HINT_COST
        self.hints += 1
        a, b = pairs[0]
        out = [f"Gleo: {num(a)}과 {num(b)}의 말은 동시에 참일 수 없어요. "
               f"둘 중 적어도 한 명은 거짓말을 해요. (신뢰도 -{HINT_COST}, 남은 신뢰도 {self.rep})"]
        out += self._check_end()
        return out

    def memo(self, i: int, tag: str) -> list[str]:
        if tag in ("-", ""):
            self.memos.pop(i, None)
            return [f"{pid(i)} 메모를 지웠어요."]
        self.memos[i] = tag
        return [f"{pid(i)}에 '{tag}' 메모."]

    # ------------------------------------------------------------ 정리

    def summary(self) -> list[str]:
        out = [f"신뢰도 {self.rep} · 남은 통화 {self.budget - self.used} · "
               f"남은 조직원 {self.n_evil - len(self.caught)}명 · 진행 {self.progress:.0%}"
               + (f" · 최종 단계 출동 기회 {self.final_raids_left}" if self.final_phase else "")]
        if not self.observed:
            out.append("아직 들은 진술이 없어요.")
        for i in sorted(self.observed):
            st = self.observed[i]
            clue = self.truth.stakeout_clues[i] if st else self.truth.clues[i]
            tag = " [잠복·확실]" if st else ""
            out.append(f"  {place_label(self.board, i)} — {self.shown_label(i)}{tag}: "
                       f"{fact(clue, self.board)}")
        claims = Counter(self.truth.shown[i] for i in self.observed
                         if i not in self.case.file.anonymous)
        for role, c in claims.items():
            if c > 1 and role is not Role.GOSSIP:
                who = "".join(pid(i) for i in sorted(self.observed)
                              if i not in self.case.file.anonymous and self.truth.shown[i] is role)
                out.append(f"  ※ {irago(role.label)} 밝힌 사람이 {c}명이에요: {who}")
        for i in self.revealed:
            mark = "검거" if i in self.caught else "헛걸음"
            out.append(f"  {place_label(self.board, i)}: {mark} ({self.truth.roles[i].label})")
        if self.memos:
            out.append("  메모: " + ", ".join(f"{pid(i)} {t}" for i, t in sorted(self.memos.items())))
        return out

    # ------------------------------------------------------------ 내부

    def _statement_lines(self, i: int, stakeout: bool) -> list[str]:
        clue = self.truth.stakeout_clues[i] if stakeout else self.truth.clues[i]
        anonymous = i in self.case.file.anonymous
        shown = None if anonymous else self.truth.shown[i]
        return [
            f"[{place_label(self.board, i)} · {self.shown_label(i)}] \"{speak(clue, self.board, shown)}\"",
            f"   → 지도 표시: {fact(clue, self.board)}",
        ]

    def _after_action(self) -> list[str]:
        out = []
        if self.used >= self.budget and not self.final_phase:
            self.clock = max(self.clock, FINAL_PHASE_START)
            self.final_raids_left = self.n_evil - len(self.caught) + 1
            out.append(f"Gleo: 도착 5분 전이에요. 조직이 눈치챘어요! 이제 출동만 할 수 있어요. "
                       f"출동 기회 {self.final_raids_left}번.")
        out += self.stakeout_notices()
        return out

    def _check_end(self) -> list[str]:
        hidden = set(indices_of(self.truth.hidden))
        if self.caught == hidden:
            self.status = "won"
            return [f"Gleo: 사건 해결! 신뢰도 {self.rep}로 마무리했어요."]
        if self.rep <= 0:
            self.status = "fired"
            return ["Gleo: 신뢰도가 바닥났어요… 이번 수사에서 해임됐어요."]
        if self.final_phase and self.final_raids_left <= 0:
            self.status = "escaped"
            left = len(hidden - self.caught)
            return [f"Gleo: 도착했어요. 남은 조직원 {left}명은 도주했어요."]
        return []
