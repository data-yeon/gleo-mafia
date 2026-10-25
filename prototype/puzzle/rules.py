"""생성기, 솔버, 진행 규칙이 함께 쓰는 게임 규칙: 난이도 구성, 오염, 시간 모델."""
from __future__ import annotations

from dataclasses import dataclass

from .board import Board
from .model import Role, is_evil, is_honest

BOSS_TAINT_M = 1000

# ---------------------------------------------------------------- 시간 모델 (룰 v1)
# 이동 시간 전체를 0..1 진행률로 본다. 도착 5분 전(20분 이동 기준 0.75)부터 최종 단계.
# 탐문(통화) 한 번은 (최종 단계 시작 진행률 ÷ 예산)만큼 시간이 흐른다.
# 잠복은 시간이 들지 않지만, 길가 장소에 다가갈 때부터 지나칠 때까지만 할 수 있다.
FINAL_PHASE_START = 0.75
STAKEOUT_LOOKAHEAD = 0.15     # 장소 진행 위치보다 이만큼 앞에서부터 잠복 가능
STAKEOUT_PASS = 0.03          # 장소를 이만큼 지나치면 잠복 기회가 사라진다
RAID_TIME = 0.05              # 최종 단계에서 출동 한 번에 흐르는 시간


def call_time(budget: int) -> float:
    return FINAL_PHASE_START / budget


def stakeout_open(route_pos: float, progress: float) -> bool:
    return route_pos - STAKEOUT_LOOKAHEAD <= progress <= route_pos + STAKEOUT_PASS


@dataclass(frozen=True)
class Preset:
    key: str
    label: str
    evil: tuple[Role, ...]
    meddlers: int
    budget: int              # 탐문 예산(통화 수). 제품에서는 ETA로 보정한다
                             # v1 통계(smart 봇, 잠복 활용) 찍기 없이 해결: 보통 5→76%, 어려움 7→90%, 보이스피싱 6→84%
    anonymous: int = 0       # 직업을 밝히지 않는 익명 제보자 수
    force_cop_claim: bool = False   # 사칭범이 반드시 경관 행세 (데모 연출용)

    @property
    def n_evil(self) -> int:
        return len(self.evil)


PRESETS = {
    "easy": Preset("easy", "쉬움", (Role.THUG, Role.THUG), 0, 5),
    "normal": Preset("normal", "보통", (Role.THUG, Role.BLACKMAILER), 1, 5),
    "hard": Preset("hard", "어려움", (Role.THUG, Role.BLACKMAILER, Role.BOSS), 1, 7),
    # 보이스피싱 사업부: 경관 사칭, 익명 제보
    "phishing": Preset("phishing", "보이스피싱", (Role.IMPOSTER, Role.BLACKMAILER), 1, 6,
                       anonymous=1, force_cop_claim=True),
}


def taint_candidates(board: Board, roles) -> int:
    """오염될 수 있는 장소의 비트마스크.

    roles는 장소별 실제 역할이다. 솔버의 가능한 세계에서는 정직한 장소를 None으로 둔다.
    - 협박꾼: 가장 가까운 선한 장소(정직 또는 말썽꾼) 한 곳. 그곳이 정직이면 오염.
    - 보스: 반경 1km 안의 정직한 장소 전부.
    순찰 경관은 오염되지 않는데, 경관인지는 겉으로 밝힌 직업으로 판단하므로 여기서는 거르지 않는다.
    """
    mask = 0
    n = board.n
    for i, r in enumerate(roles):
        if r is Role.BLACKMAILER:
            goods = [j for j in range(n) if not is_evil(roles[j])]
            j = min(goods, key=lambda j: (board.dist[i][j], j))
            if is_honest(roles[j]):
                mask |= 1 << j
        elif r is Role.BOSS:
            for j in range(n):
                if is_honest(roles[j]) and board.dist[i][j] <= BOSS_TAINT_M:
                    mask |= 1 << j
    return mask
