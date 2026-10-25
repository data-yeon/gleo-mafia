"""데모용 가상 도시: 도로 그래프(간선도로·이면도로·다리), 강, 공원, 블록.
A* 경로(이동 시간 + 회전 벌점)와 경로 계획(회전 안내, 신호 대기, 지하차도)을 만든다.

좌표는 미터 단위 평면(x=동, y=북). 나중에 실제 지도(OSM)로 바꿀 때도 같은 구조(노드·간선·폴리곤)를 채운다.
"""
from __future__ import annotations

import heapq
import math
import random
from dataclasses import dataclass, field

ARTERIAL_NAMES = ["테헤란로", "강남대로", "도산대로", "영동대로", "봉은사로", "언주로", "논현로", "삼성로",
                  "선릉로", "역삼로", "학동로", "압구정로", "남부순환로", "양재대로"]
BRIDGE_NAMES = ["청담대교", "영동대교", "성수대교", "동호대교", "한남대교", "반포대교"]
TUNNEL_NAMES = ["남산1호 지하차도", "금화 지하차도", "구룡 지하차도", "홍지문 지하차도", "북악 지하차도"]
SOUTH_RIVER_ROAD = "올림픽대로"
NORTH_RIVER_ROAD = "강변북로"

SPEED_KMH = {"arterial": 60.0, "local": 40.0, "bridge": 65.0}
CRUISE_KMH = {"arterial": 62.0, "local": 38.0, "bridge": 68.0}   # 주행 시뮬레이션 순항 속도(상대값)
LANES = {"arterial": 3, "local": 1, "bridge": 3}                  # 편도 차로 수 (지도 굵기·3D 도로 폭)
TURN_LEFT_S = 15.0
TURN_RIGHT_S = 5.0
TURN_DEG = 30.0                 # 이 각도 이상 꺾이면 회전으로 본다
SHARP_DEG = 60.0
BLOCK_INSET_M = 14.0            # 블록 폴리곤을 도로에서 띄우는 거리
FILLET_M = 18.0                 # 경로 모서리를 둥글게 깎는 거리


@dataclass
class Edge:
    a: int
    b: int
    cls: str                    # arterial | local | bridge
    name: str
    length: float


@dataclass
class City:
    nodes: list[tuple[float, float]]
    edges: list[Edge]
    adj: list[list[int]] = field(default_factory=list)       # 노드별 간선 인덱스
    water: list[list[tuple[float, float]]] = field(default_factory=list)
    parks: list[list[tuple[float, float]]] = field(default_factory=list)
    blocks: list[list[tuple[float, float]]] = field(default_factory=list)
    grid: dict = field(default_factory=dict)                 # (i, j) -> 노드
    river_rows: tuple[int, int] = (0, 0)

    def other(self, e: int, node: int) -> int:
        ed = self.edges[e]
        return ed.b if ed.a == node else ed.a

    def edge_between(self, u: int, v: int) -> int:
        for e in self.adj[u]:
            if self.other(e, u) == v:
                return e
        return -1

    def translate(self, dx: float, dy: float) -> None:
        self.nodes = [(x + dx, y + dy) for x, y in self.nodes]
        for polys in (self.water, self.parks, self.blocks):
            for k, poly in enumerate(polys):
                polys[k] = [(x + dx, y + dy) for x, y in poly]


# ---------------------------------------------------------------- 도시 만들기

def _spacings(rng: random.Random, n: int, lo: float, hi: float) -> list[float]:
    out = [0.0]
    for _ in range(n - 1):
        out.append(out[-1] + rng.uniform(lo, hi))
    return out


def make_city(rng: random.Random, cols: int = 26, rows: int = 16) -> City:
    xs = _spacings(rng, cols, 380.0, 520.0)
    ys = _spacings(rng, rows, 380.0, 520.0)
    r = rows // 2 - 1                                   # 강은 r행과 r+1행 사이
    nodes: list[tuple[float, float]] = []
    grid: dict = {}
    for j in range(rows):
        for i in range(cols):
            grid[(i, j)] = len(nodes)
            nodes.append((xs[i] + rng.uniform(-30, 30), ys[j] + rng.uniform(-30, 30)))

    names = ARTERIAL_NAMES[:]
    rng.shuffle(names)
    art_rows = {2: names.pop(), r - 3: names.pop(), r: SOUTH_RIVER_ROAD, r + 1: NORTH_RIVER_ROAD,
                r + 4: names.pop(), rows - 3: names.pop()}
    art_cols = {}
    for i in range(2, cols - 2, 5):
        art_cols[i + rng.choice((-1, 0, 1))] = names.pop()
    bridges = rng.sample(sorted(art_cols), min(4, len(art_cols)))
    bridge_names = rng.sample(BRIDGE_NAMES, len(bridges))

    def local_name(along_row: bool, k: int) -> str:
        keys = sorted(art_rows if along_row else art_cols)
        nearest = min(keys, key=lambda a: abs(a - k))
        base = (art_rows if along_row else art_cols)[nearest]
        return f"{base} {abs(k - nearest) * 2 + (1 if k > nearest else 0) + 1}길"

    edges: list[Edge] = []

    def add(u: int, v: int, cls: str, name: str) -> None:
        (x0, y0), (x1, y1) = nodes[u], nodes[v]
        edges.append(Edge(u, v, cls, name, math.hypot(x1 - x0, y1 - y0)))

    for j in range(rows):
        for i in range(cols - 1):
            cls = "arterial" if j in art_rows else "local"
            add(grid[(i, j)], grid[(i + 1, j)], cls, art_rows.get(j) or local_name(True, j))
    for i in range(cols):
        for j in range(rows - 1):
            if j == r:                                   # 강을 건너는 길은 다리만
                if i in bridges:
                    add(grid[(i, j)], grid[(i, j + 1)], "bridge", bridge_names[bridges.index(i)])
                continue
            cls = "arterial" if i in art_cols else "local"
            add(grid[(i, j)], grid[(i, j + 1)], cls, art_cols.get(i) or local_name(False, i))

    city = City(nodes=nodes, edges=edges, grid=grid, river_rows=(r, r + 1))
    _rebuild_adj(city)
    _thin_locals(city, rng, 0.08)

    # 강 폴리곤
    gap = ys[r + 1] - ys[r]
    mid = (ys[r] + ys[r + 1]) / 2.0
    half = max(gap / 2.0 - 90.0, 80.0)
    amp = min(50.0, gap * 0.08)
    top, bottom = [], []
    x = xs[0] - 800.0
    while x <= xs[-1] + 800.0:
        w = amp * math.sin(x / 1700.0)
        top.append((x, mid + w + half))
        bottom.append((x, mid + w - half))
        x += 200.0
    city.water.append(top + bottom[::-1])

    # 블록과 공원 (강 칸은 제외)
    for j in range(rows - 1):
        if j == r:
            continue
        for i in range(cols - 1):
            corners = [nodes[grid[(i, j)]], nodes[grid[(i + 1, j)]], nodes[grid[(i + 1, j + 1)]],
                       nodes[grid[(i, j + 1)]]]
            cx = sum(p[0] for p in corners) / 4.0
            cy = sum(p[1] for p in corners) / 4.0
            poly = []
            for px, py in corners:
                dx, dy = cx - px, cy - py
                d = math.hypot(dx, dy)
                poly.append((px + dx / d * BLOCK_INSET_M * 1.4, py + dy / d * BLOCK_INSET_M * 1.4))
            (city.parks if rng.random() < 0.06 else city.blocks).append(poly)
    return city


def _rebuild_adj(city: City) -> None:
    city.adj = [[] for _ in city.nodes]
    for k, e in enumerate(city.edges):
        city.adj[e.a].append(k)
        city.adj[e.b].append(k)


def _connected(city: City, removed: set[int]) -> bool:
    seen = {0}
    stack = [0]
    while stack:
        u = stack.pop()
        for e in city.adj[u]:
            if e in removed:
                continue
            v = city.other(e, u)
            if v not in seen:
                seen.add(v)
                stack.append(v)
    return len(seen) == len(city.nodes)


def _thin_locals(city: City, rng: random.Random, ratio: float) -> None:
    """이면도로 일부를 지워 격자를 덜 반듯하게. 연결은 유지한다."""
    locals_ = [k for k, e in enumerate(city.edges) if e.cls == "local"]
    rng.shuffle(locals_)
    removed: set[int] = set()
    for k in locals_[: int(len(locals_) * ratio)]:
        removed.add(k)
        if not _connected(city, removed):
            removed.discard(k)
    city.edges = [e for k, e in enumerate(city.edges) if k not in removed]
    _rebuild_adj(city)


# ---------------------------------------------------------------- A*

def _turn_deg(p0, p1, p2) -> float:
    """p0→p1→p2에서 꺾이는 각도(도). 양수 = 왼쪽."""
    a = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    b = math.atan2(p2[1] - p1[1], p2[0] - p1[0])
    d = math.degrees(b - a)
    while d > 180.0:
        d -= 360.0
    while d < -180.0:
        d += 360.0
    return d


def turn_penalty(deg: float) -> float:
    if deg > TURN_DEG:
        return TURN_LEFT_S
    if deg < -TURN_DEG:
        return TURN_RIGHT_S
    return 0.0


def edge_seconds(e: Edge) -> float:
    return e.length / (SPEED_KMH[e.cls] / 3.6)


def astar(city: City, start: int, goal: int, prev_start: int = -1) -> tuple[list[int], float, int]:
    """이동 시간 + 회전 벌점이 최소인 경로. 상태 = (노드, 직전 노드)라 회전을 계산할 수 있다.
    반환: (노드 목록, 비용 초, 펼친 상태 수)"""
    vmax = max(SPEED_KMH.values()) / 3.6
    gx, gy = city.nodes[goal]

    def h(n: int) -> float:
        x, y = city.nodes[n]
        return math.hypot(gx - x, gy - y) / vmax

    start_state = (start, prev_start)
    g = {start_state: 0.0}
    parent: dict = {start_state: None}
    heap = [(h(start), 0, start_state)]
    counter = 0
    closed = set()
    while heap:
        _, _, state = heapq.heappop(heap)
        if state in closed:
            continue
        closed.add(state)
        node, prev = state
        if node == goal:
            path = []
            s = state
            while s is not None:
                path.append(s[0])
                s = parent[s]
            return path[::-1], g[state], len(closed)
        for e in city.adj[node]:
            nxt = city.other(e, node)
            if nxt == prev:
                continue                                   # 유턴 금지
            cost = g[state] + edge_seconds(city.edges[e])
            if prev >= 0:
                cost += turn_penalty(_turn_deg(city.nodes[prev], city.nodes[node], city.nodes[nxt]))
            ns = (nxt, node)
            if cost < g.get(ns, float("inf")):
                g[ns] = cost
                parent[ns] = state
                counter += 1
                heapq.heappush(heap, (cost + h(nxt), counter, ns))
    raise ValueError("경로 없음")


def route_through(city: City, stops: list[int]) -> tuple[list[int], float]:
    """출발 → 경유지들 → 도착. 구간마다 A*를 돌려 이어 붙인다(경유지에서는 유턴 허용)."""
    path = [stops[0]]
    total = 0.0
    for a, b in zip(stops, stops[1:]):
        seg, cost, _ = astar(city, a, b)
        path += seg[1:]
        total += cost
    return path, total


# ---------------------------------------------------------------- 경로 계획

def plan_route(city: City, path: list[int], rng: random.Random, waypoints: tuple[int, ...] = ()) -> dict:
    """노드 경로 → 둥근 모서리 폴리라인 + 도로 구간 + 회전 안내 + 신호 + 지하차도."""
    pts = [city.nodes[n] for n in path]
    edge_ids = [city.edge_between(u, v) for u, v in zip(path, path[1:])]
    poly: list[tuple[float, float]] = [pts[0]]
    node_s = [0.0]
    run = 0.0

    def push(p):
        nonlocal run
        q = poly[-1]
        run += math.hypot(p[0] - q[0], p[1] - q[1])
        poly.append(p)

    for k in range(1, len(pts) - 1):
        p0, p1, p2 = pts[k - 1], pts[k], pts[k + 1]
        deg = _turn_deg(p0, p1, p2)
        if abs(deg) < 5.0:
            push(p1)
            node_s.append(run)
            continue
        l0 = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        l1 = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
        r = min(FILLET_M, l0 * 0.4, l1 * 0.4)
        a = (p1[0] + (p0[0] - p1[0]) / l0 * r, p1[1] + (p0[1] - p1[1]) / l0 * r)
        b = (p1[0] + (p2[0] - p1[0]) / l1 * r, p1[1] + (p2[1] - p1[1]) / l1 * r)
        push(a)
        mid_s = None
        for t in (0.25, 0.5, 0.75):
            q = ((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * p1[0] + t * t * b[0],
                 (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * p1[1] + t * t * b[1])
            push(q)
            if t == 0.5:
                mid_s = run
        push(b)
        node_s.append(mid_s)
    push(pts[-1])
    node_s.append(run)
    length = run

    # 도로 구간(이름이 같은 간선 묶음)
    segments = []
    for k, e in enumerate(edge_ids):
        ed = city.edges[e]
        if segments and segments[-1]["name"] == ed.name:
            segments[-1]["to"] = node_s[k + 1]
        else:
            segments.append({"name": ed.name, "cls": ed.cls, "from": node_s[k], "to": node_s[k + 1],
                             "cruise": CRUISE_KMH[ed.cls]})

    # 회전 안내
    maneuvers = []
    wp_set = set(waypoints)
    for k in range(1, len(path) - 1):
        deg = _turn_deg(pts[k - 1], pts[k], pts[k + 1])
        cur = city.edges[edge_ids[k - 1]]
        nxt = city.edges[edge_ids[k]]
        if path[k] in wp_set:
            maneuvers.append({"s": node_s[k], "icon": "flag", "verb": "경유지", "road": nxt.name,
                              "waypoint": True})
            continue
        if abs(deg) >= TURN_DEG:
            left = deg > 0
            sharp = abs(deg) >= SHARP_DEG
            verb = ("좌회전" if sharp else "왼쪽 방향") if left else ("우회전" if sharp else "오른쪽 방향")
            maneuvers.append({"s": node_s[k], "icon": "turn_left" if left else "turn_right",
                              "verb": verb, "road": nxt.name, "at": cur.name})
        elif nxt.name != cur.name:
            maneuvers.append({"s": node_s[k], "icon": "straight", "verb": "직진", "road": nxt.name})
    maneuvers.append({"s": length, "icon": "flag", "verb": "도착", "road": "목적지"})

    # 지하차도: 간선도로의 곧은 구간 1~2곳
    runs = []
    k = 0
    while k < len(edge_ids):
        if city.edges[edge_ids[k]].cls != "arterial":
            k += 1
            continue
        j = k
        while (j + 1 < len(edge_ids) and city.edges[edge_ids[j + 1]].cls == "arterial"
               and abs(_turn_deg(pts[j], pts[j + 1], pts[j + 2])) < 8.0):
            j += 1
        s0, s1 = node_s[k], node_s[j + 1]
        if s1 - s0 >= 520.0 and s0 > 0.15 * length and s1 < 0.85 * length:
            runs.append((s1 - s0, s0, s1))
        k = j + 1
    runs.sort(reverse=True)
    tunnels = []
    tnames = rng.sample(TUNNEL_NAMES, len(TUNNEL_NAMES))
    for _, s0, s1 in runs[:2]:
        a = s0 + 60.0
        b = min(s1 - 60.0, a + rng.uniform(380.0, 620.0))
        tunnels.append({"from": a, "to": b, "name": tnames[len(tunnels)]})
    tunnels.sort(key=lambda t: t["from"])

    # 신호 대기: 간선도로가 만나는 교차로 중 2~3곳 (회전 지점 우선, 터널 밖)
    def in_tunnel(s):
        return any(t["from"] - 40 <= s <= t["to"] + 40 for t in tunnels)

    cands = []
    for k in range(1, len(path) - 1):
        has_art = any(city.edges[e].cls == "arterial" for e in city.adj[path[k]])
        if not has_art or len(city.adj[path[k]]) < 3:
            continue
        s = node_s[k] - 18.0
        if s < 400.0 or s > length - 400.0 or in_tunnel(s):
            continue
        turn = abs(_turn_deg(pts[k - 1], pts[k], pts[k + 1])) >= TURN_DEG
        cands.append((0 if turn else 1, rng.random(), s, path[k]))
    cands.sort()
    want = rng.choice((2, 3))
    stops = []
    for _, _, s, node in cands:
        if len(stops) >= want:
            break
        if all(abs(s - st["s"]) >= 800.0 for st in stops):
            stops.append({"s": s, "dwell": rng.uniform(25.0, 45.0), "node": node})
    stops.sort(key=lambda st: st["s"])

    return {
        "polyline": poly, "length": length, "nodes": path, "node_s": node_s, "edges": edge_ids,
        "segments": segments, "maneuvers": maneuvers, "tunnels": tunnels, "stops": stops,
        "waypoints": list(waypoints),
    }


def pick_trip(city: City, rng: random.Random, min_m: float = 8500.0, max_m: float = 12500.0,
              tries: int = 60) -> tuple[int, int, list[int]] | None:
    """강 남쪽 서편에서 북쪽 동편으로 가는 출발·도착 노드와 A* 경로."""
    r0, r1 = city.river_rows
    cols = max(i for i, _ in city.grid) + 1
    rows = max(j for _, j in city.grid) + 1
    for _ in range(tries):
        s = city.grid[(rng.randint(1, 4), rng.randint(1, r0 - 2))]
        g = city.grid[(rng.randint(cols - 6, cols - 3), rng.randint(r1 + 2, rows - 2))]
        path, _, _ = astar(city, s, g)
        length = sum(city.edges[city.edge_between(u, v)].length for u, v in zip(path, path[1:]))
        if min_m <= length <= max_m:
            return s, g, path
    return None
