"""퍼즐 엔진의 기본 데이터 모델: 장소, 역할, 단서.

장소 인덱스는 내부적으로 0부터 시작하고, 화면과 JSON에는 1부터 시작하는 번호(id)로 내보낸다.
숨은 곳 같은 장소 집합은 비트마스크(int)로 다룬다. bit i = 인덱스 i인 장소.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Role(str, Enum):
    # 정직 (선)
    VENDOR = "노점상"
    TAXI = "택시기사"
    DRONE = "드론 유튜버"
    LOCAL = "동네 토박이"
    RIDER = "배달 라이더"
    GUARD = "경비원"
    COP = "순찰 경관"
    # 말썽꾼 (선)
    GOSSIP = "오지랖 주민"
    DRUNK = "취객"
    # 조직원, 보스 (악)
    THUG = "행동대원"
    IMPOSTER = "사칭범"          # 보이스피싱 사업부: 행동대원처럼 판에 있는 직업으로 위장하되 경관 행세도 한다
    BLACKMAILER = "협박꾼"
    BOSS = "보스"

    @property
    def label(self) -> str:
        return self.value


HONEST_ROLES = (
    Role.VENDOR, Role.TAXI, Role.DRONE, Role.LOCAL, Role.RIDER, Role.GUARD, Role.COP,
)
MEDDLER_ROLES = (Role.GOSSIP, Role.DRUNK)
EVIL_ROLES = (Role.THUG, Role.IMPOSTER, Role.BLACKMAILER, Role.BOSS)
# 판에 있는 직업으로 위장하는 역할
IN_PLAY_PRETENDERS = (Role.THUG, Role.IMPOSTER)
HONEST_INDEX = {r: i for i, r in enumerate(HONEST_ROLES)}


def honest_bit(role: Role) -> int:
    return 1 << HONEST_INDEX[role]


def is_evil(role: Role | None) -> bool:
    return role in EVIL_ROLES


def is_honest(role: Role | None) -> bool:
    """솔버의 가능한 세계에서는 정직한 장소를 None으로 둔다."""
    return role is None or role in HONEST_ROLES


def is_disguised(role: Role | None) -> bool:
    """겉으로 밝힌 직업이 실제와 다른 역할: 악역 전부와 취객."""
    return role in EVIL_ROLES or role is Role.DRUNK


class ClueType(str, Enum):
    """룰 v1(내비 Dupery): 공간 관계를 경로 기준으로 말한다."""
    RADIUS = "RADIUS"       # 반경 안 숨은 곳 수 (주변 검색 반경)
    SPAN = "SPAN"           # 경로상 lo~hi번 구간에서 숨은 곳 수
    SIDE = "SIDE"           # 경로 왼편/오른편 숨은 곳 수
    NEIGHBOR = "NEIGHBOR"   # 지나가는 순서상 바로 앞뒤 두 곳 중 숨은 곳 수
    KIND = "KIND"           # 같은 업종 중 숨은 곳 수
    ROAD = "ROAD"           # 길가(바로 지나가는 곳) 중 숨은 곳 수
    VOUCH = "VOUCH"         # 특정 장소 보증(깨끗) / 고발(수상)
    REVEAL = "REVEAL"       # 특정 장소 제보자가 위장했는지


COUNT_CLUES = frozenset({
    ClueType.RADIUS, ClueType.SPAN, ClueType.SIDE, ClueType.NEIGHBOR, ClueType.KIND, ClueType.ROAD,
})
# 오지랖 주민이 쓸 수 있는 단서 (숫자 단서만)
GOSSIP_CLUES = (ClueType.RADIUS, ClueType.SPAN, ClueType.SIDE, ClueType.NEIGHBOR, ClueType.KIND)

# 역할별 단서. 택시기사는 구간과 길가 중 정보량이 큰 쪽을 쓴다.
CLUES_OF_ROLE = {
    Role.VENDOR: (ClueType.RADIUS,),
    Role.TAXI: (ClueType.SPAN, ClueType.ROAD),
    Role.DRONE: (ClueType.SIDE,),
    Role.LOCAL: (ClueType.NEIGHBOR,),
    Role.RIDER: (ClueType.KIND,),
    Role.GUARD: (ClueType.VOUCH,),
    Role.COP: (ClueType.REVEAL,),
}


def popcount(x: int) -> int:
    return bin(x).count("1")      # int.bit_count()는 3.10+ 이라 3.9에서도 돌게


def mask_of(indices) -> int:
    m = 0
    for i in indices:
        m |= 1 << i
    return m


def indices_of(mask: int) -> list[int]:
    out = []
    i = 0
    while mask:
        if mask & 1:
            out.append(i)
        mask >>= 1
        i += 1
    return out


@dataclass(frozen=True)
class Place:
    index: int          # 0부터
    name: str
    kind: str
    x: float            # m, 동쪽 +
    y: float            # m, 북쪽 +
    roadside: bool      # 경로 300m 안
    route_pos: float    # 경로상 진행 위치 0..1 (인덱스 = 지나가는 순서)
    side: str = ""      # 진행 방향 기준 "왼편" / "오른편"
    route_dist: float = 0.0   # 경로까지 거리(m)

    @property
    def id(self) -> int:
        return self.index + 1


@dataclass(frozen=True)
class Clue:
    """제보자 한 명의 진술.

    count 단서: region 안의 숨은 곳 수가 count라고 말한다.
    VOUCH: claim=True면 "target이 수상하다", False면 "target은 깨끗하다".
    REVEAL: claim=True면 "target이 위장했다", False면 "target은 진짜다".
    center/radius/side/kind/lo/hi는 화면 표시와 대사용 파라미터다.
    """

    type: ClueType
    region: int = 0
    count: int = 0
    target: int = -1
    claim: bool = False
    center: int = -1
    radius: int = 0
    side: str = ""
    kind: str = ""
    lo: int = -1
    hi: int = -1

    def actual(self, hidden: int, disguised: int):
        if self.type in COUNT_CLUES:
            return popcount(hidden & self.region)
        if self.type is ClueType.VOUCH:
            return bool(hidden >> self.target & 1)
        return bool(disguised >> self.target & 1)

    def holds(self, hidden: int, disguised: int, offset: int = 0) -> bool:
        """진술이 참인지. offset=1이면 오지랖 주민처럼 '실제+1'로 말한 진술을 보정해서 본다."""
        if self.type in COUNT_CLUES:
            return popcount(hidden & self.region) == self.count - offset
        return self.actual(hidden, disguised) == self.claim
