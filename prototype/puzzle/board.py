"""경로형 보드: 경로를 따라 지나갈 장소 9곳(또는 12곳).

룰 v1(내비 Dupery)에서는 공간 관계를 경로 기준으로 말한다.
  - 장소 번호 = 지나가는 순서 (인덱스 0부터, 화면 번호 1부터)
  - 왼편 / 오른편 = 진행 방향 기준
  - 길가 = 경로 300m 안 (잠복 찬스 대상)
좌표는 경로 출발점을 원점으로 한 미터 단위 평면(x=동, y=북)이다.
합성 보드(make_board)는 테스트와 통계용이고, 실제 경로·POI 보드는 board_from_points로 만든다.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field

from .model import Place, mask_of

ROADSIDE_M = 300          # 이 거리 안이면 길가 장소(잠복 찬스 대상)
MIN_SPACING_M = 700       # 장소 사이 최소 간격 (차량 화면에서 핀이 겹치지 않게)
OFFROAD_MIN_M = 550
OFFROAD_MAX_M = 1500
RADIUS_OPTIONS_M = (700, 1000, 1500, 2000)
SIDES = ("왼편", "오른편")

KIND_NAMES = {
    "역": ["시청역", "중앙역", "강변역", "터미널역"],
    "공원": ["한강공원", "근린공원", "숲공원"],
    "카페": ["단골 카페", "모퉁이 카페", "루프탑 카페"],
    "시장": ["전통시장", "야시장", "수산시장"],
    "랜드마크": ["전망 타워", "시계탑", "옛 기차역"],
    "문화시설": ["시립미술관", "역사박물관", "공연장"],
    "관공서": ["시립도서관", "구청", "주민센터"],
    "체육시설": ["단골 헬스장", "수영장", "실내 체육관"],
    "광장": ["시민광장", "분수광장", "역앞 광장"],
}


@dataclass
class Board:
    places: list[Place]
    route: list[tuple[float, float]]
    dist: list[list[float]] = field(default_factory=list)
    world: dict = field(default_factory=dict)     # 가상 도시 보드면 {"city": City, "plan": dict}

    def __post_init__(self):
        self.dist = [
            [math.hypot(a.x - b.x, a.y - b.y) for b in self.places] for a in self.places
        ]
        self.road_region = mask_of(p.index for p in self.places if p.roadside)

    @property
    def n(self) -> int:
        return len(self.places)

    def radius_region(self, center: int, radius: float) -> int:
        return mask_of(
            j for j in range(self.n) if j != center and self.dist[center][j] <= radius
        )

    def nearest(self, center: int) -> int:
        return min((j for j in range(self.n) if j != center),
                   key=lambda j: (self.dist[center][j], j))

    def side_region(self, side: str) -> int:
        return mask_of(p.index for p in self.places if p.side == side)

    def span_region(self, lo: int, hi: int) -> int:
        """지나가는 순서상 lo번째부터 hi번째까지(양 끝 포함, 인덱스)."""
        return mask_of(range(lo, hi + 1))

    def route_neighbors(self, i: int) -> list[int]:
        """지나가는 순서상 바로 앞뒤 두 곳. 처음과 마지막 장소는 한쪽 두 곳."""
        if i == 0:
            return [1, 2]
        if i == self.n - 1:
            return [self.n - 3, self.n - 2]
        return [i - 1, i + 1]

    def kinds(self) -> dict[str, list[int]]:
        out: dict[str, list[int]] = {}
        for p in self.places:
            out.setdefault(p.kind, []).append(p.index)
        return out


# ---------------------------------------------------------------- 경로 기하

def cumulative(route):
    cum = [0.0]
    for (x0, y0), (x1, y1) in zip(route, route[1:]):
        cum.append(cum[-1] + math.hypot(x1 - x0, y1 - y0))
    return cum


def point_at(route, cum, frac):
    """경로상 frac 위치의 점과 왼쪽 법선 벡터."""
    target = frac * cum[-1]
    for k in range(len(route) - 1):
        if cum[k + 1] >= target:
            seg = cum[k + 1] - cum[k]
            t = 0.0 if seg == 0 else (target - cum[k]) / seg
            (x0, y0), (x1, y1) = route[k], route[k + 1]
            dx, dy = (x1 - x0) / seg, (y1 - y0) / seg
            return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, -dy, dx
    (x0, y0), (x1, y1) = route[-2], route[-1]
    seg = math.hypot(x1 - x0, y1 - y0)
    return x1, y1, -(y1 - y0) / seg, (x1 - x0) / seg


def project(route, cum, x, y):
    """(경로까지 거리, 경로상 진행 위치 0..1, 진행 방향 기준 편)."""
    best = (float("inf"), 0.0, SIDES[0])
    for k in range(len(route) - 1):
        (x0, y0), (x1, y1) = route[k], route[k + 1]
        dx, dy = x1 - x0, y1 - y0
        seg2 = dx * dx + dy * dy
        t = 0.0 if seg2 == 0 else max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / seg2))
        px, py = x0 + dx * t, y0 + dy * t
        d = math.hypot(x - px, y - py)
        if d < best[0]:
            cross = dx * (y - y0) - dy * (x - x0)
            best = (d, (cum[k] + math.sqrt(seg2) * t) / cum[-1], SIDES[0] if cross > 0 else SIDES[1])
    return best


def board_from_points(route, points) -> Board:
    """경로와 장소 후보 [(x, y, kind, name), ...]로 보드를 만든다. 지나가는 순서대로 번호를 붙인다."""
    cum = cumulative(route)
    raw = []
    for x, y, kind, name in points:
        d, pos, side = project(route, cum, x, y)
        raw.append((pos, x, y, kind, name, d, side))
    raw.sort()
    places = [
        Place(index=i, name=name, kind=kind, x=round(x, 1), y=round(y, 1),
              roadside=d <= ROADSIDE_M, route_pos=round(pos, 4), side=side, route_dist=round(d, 1))
        for i, (pos, x, y, kind, name, d, side) in enumerate(raw)
    ]
    return Board(places=places, route=[(round(x, 1), round(y, 1)) for x, y in route])


# ---------------------------------------------------------------- 합성 보드

def _make_route(rng: random.Random) -> list[tuple[float, float]]:
    length = rng.uniform(9000, 13000)
    amp = rng.uniform(0, 700)
    period = rng.uniform(6000, 12000)
    phase = rng.uniform(0, 2 * math.pi)
    base = amp * math.sin(phase)
    pts = []
    steps = int(length // 250)
    for k in range(steps + 1):
        x = length * k / steps
        pts.append((x, amp * math.sin(2 * math.pi * x / period + phase) - base))
    return pts


def _assign_kinds(rng: random.Random, n: int) -> list[str]:
    distinct = 6 if n <= 9 else 7
    base = rng.sample(list(KIND_NAMES), distinct)
    kinds = list(base)
    while len(kinds) < n:
        k = rng.choice(base)
        if kinds.count(k) < 3:
            kinds.append(k)
    rng.shuffle(kinds)
    return kinds


def make_board(rng: random.Random, n: int = 9) -> Board:
    for _ in range(200):
        board = _try_make_board(rng, n)
        if board is not None:
            return board
    raise RuntimeError("보드 생성 실패")


def _try_make_board(rng: random.Random, n: int) -> Board | None:
    route = _make_route(rng)
    cum = cumulative(route)
    n_road = rng.choice([2, 3])
    roadside_slots = [True] * n_road + [False] * (n - n_road)
    rng.shuffle(roadside_slots)
    n_left = n // 2 + rng.choice((0, n % 2))           # 9곳이면 왼편 4 또는 5
    sides = [1] * n_left + [-1] * (n - n_left)         # +1 = 왼쪽 법선 방향
    rng.shuffle(sides)

    pts: list[tuple[float, float]] = []
    for k in range(n):
        band = k * 3 // n
        want_road = roadside_slots[k]
        for _ in range(300):
            frac = rng.uniform(band / 3 + 0.02, (band + 1) / 3 - 0.02)
            px, py, nx, ny = point_at(route, cum, frac)
            off = rng.uniform(40, 250) if want_road else rng.uniform(OFFROAD_MIN_M, OFFROAD_MAX_M)
            x, y = px + nx * off * sides[k], py + ny * off * sides[k]
            if any(math.hypot(x - qx, y - qy) < MIN_SPACING_M for qx, qy in pts):
                continue
            d, _, side = project(route, cum, x, y)
            if side != (SIDES[0] if sides[k] > 0 else SIDES[1]):
                continue
            if want_road and d > ROADSIDE_M - 20:
                continue
            if not want_road and d < OFFROAD_MIN_M - 50:
                continue
            pts.append((x, y))
            break
        else:
            return None

    kinds = _assign_kinds(rng, n)
    pools = {k: rng.sample(v, len(v)) for k, v in KIND_NAMES.items()}
    points = []
    for (x, y), kind in zip(pts, kinds):
        name = pools[kind].pop() if pools[kind] else f"{kind} {len(points) + 1}"
        points.append((x, y, kind, name))
    return board_from_points(route, points)


# ---------------------------------------------------------------- 가상 도시 보드

def _point_in_poly(x: float, y: float, poly) -> bool:
    inside = False
    n = len(poly)
    for k in range(n):
        x0, y0 = poly[k]
        x1, y1 = poly[(k + 1) % n]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            inside = not inside
    return inside


def make_city_board(rng: random.Random, n: int = 9) -> Board:
    """가상 도시를 만들고 A* 경로를 정한 뒤, 경로 기준으로 장소 9곳을 고른다.
    길가 장소는 경로에 붙은 블록(도로에서 30~60m), 나머지는 경로에서 0.45~1.5km 떨어진 블록."""
    from .city import make_city, pick_trip, plan_route

    for _ in range(80):
        city = make_city(rng)
        trip = pick_trip(city, rng)
        if trip is None:
            continue
        start, goal, path = trip
        plan = plan_route(city, path, rng)
        if not plan["tunnels"] or not (2 <= len(plan["stops"]) <= 3):
            continue
        ox, oy = city.nodes[start]
        city.translate(-ox, -oy)
        plan = plan_route(city, path, random.Random(rng.random()))
        if not plan["tunnels"] or not (2 <= len(plan["stops"]) <= 3):
            continue
        board = _place_on_city(rng, city, plan, n)
        if board is not None:
            return board
    raise RuntimeError("가상 도시 보드 생성 실패")


def _place_on_city(rng: random.Random, city, plan: dict, n: int) -> Board | None:
    route = plan["polyline"]
    cum = cumulative(route)
    water = city.water
    tunnels = plan["tunnels"]
    length = plan["length"]

    def ok_point(x, y) -> bool:
        return not any(_point_in_poly(x, y, w) for w in water)

    # 길가 후보: 경로 간선 위 지점에서 양옆으로 40~55m (터널·다리 구간 제외)
    road_cands = []
    for k, e in enumerate(plan["edges"]):
        ed = city.edges[e]
        if ed.cls == "bridge":
            continue
        u, v = plan["nodes"][k], plan["nodes"][k + 1]
        (x0, y0), (x1, y1) = city.nodes[u], city.nodes[v]
        seg = math.hypot(x1 - x0, y1 - y0)
        for t in (0.3, 0.5, 0.7):
            px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            nx, ny = -(y1 - y0) / seg, (x1 - x0) / seg
            for sgn in (1, -1):
                off = rng.uniform(40.0, 55.0)
                x, y = px + nx * off * sgn, py + ny * off * sgn
                d, pos, _ = project(route, cum, x, y)
                s = pos * length
                if any(tn["from"] - 80 <= s <= tn["to"] + 80 for tn in tunnels):
                    continue
                if d <= 80.0 and ok_point(x, y):
                    road_cands.append((x, y, pos))
    # 떨어진 후보: 블록 중심
    far_cands = []
    for poly in city.blocks + city.parks:
        x = sum(p[0] for p in poly) / len(poly)
        y = sum(p[1] for p in poly) / len(poly)
        d, pos, _ = project(route, cum, x, y)
        if 450.0 <= d <= 1500.0 and ok_point(x, y):
            far_cands.append((x, y, pos))

    n_road = rng.choice([2, 3])
    slots = [True] * n_road + [False] * (n - n_road)
    rng.shuffle(slots)
    n_left = n // 2 + rng.choice((0, n % 2))
    sides = [SIDES[0]] * n_left + [SIDES[1]] * (n - n_left)
    rng.shuffle(sides)
    pts: list[tuple[float, float]] = []
    for k in range(n):
        band = k * 3 // n
        pool = road_cands if slots[k] else far_cands
        for _ in range(400):
            x, y, pos = rng.choice(pool)
            if not (band / 3 + 0.02 <= pos <= (band + 1) / 3 - 0.02):
                continue
            if any(math.hypot(x - qx, y - qy) < MIN_SPACING_M for qx, qy in pts):
                continue
            if project(route, cum, x, y)[2] != sides[k]:
                continue
            pts.append((x, y))
            break
        else:
            return None

    kinds = _assign_kinds(rng, n)
    pools = {k: rng.sample(v, len(v)) for k, v in KIND_NAMES.items()}
    points = []
    for (x, y), kind in zip(pts, kinds):
        name = pools[kind].pop() if pools[kind] else f"{kind} {len(points) + 1}"
        points.append((x, y, kind, name))
    board = board_from_points(route, points)
    if sum(1 for p in board.places if p.roadside) != n_road:
        return None
    board.world = {"city": city, "plan": plan}
    return board
