"""사건 장소용 로우폴리 랜드마크 11종을 만들어 .glb, PNG 썸네일, 목록 JSON으로 내보낸다.

실행 (저장소 루트에서):
    blender --background --factory-startup --python tools/blender/make_landmarks.py

결과 (godot/assets/models/landmarks/)
- <id>.glb            모델. 노드는 Body 하나(머티리얼 여러 개)
- thumbs/<id>.png     256×256 투명 배경 썸네일(앞 오른쪽 위에서 본 직교 투영)
- landmarks.json      장소 이름/업종 → 모델 id, 파일 경로, 크기, 삼각형 수

규격 (make_cars.py와 같다)
- 1 단위 = 1m, 원점 = 부지 바닥 중앙(높이 0). 모든 모델은 얇은 부지 판(LOT_H) 위에 선다.
- 정면(입구)은 Godot 기준 -Z다. Blender 안에서는 +Y로 만든다.
- 텍스처 없이 무광 단색만 쓴다. 삼각형 수는 모델당 MAX_TRIS 이하.
- 머티리얼 이름은 <id>_<부위>. 정면 표시용 <id>_front(문, 입구)는 항상 정면 쪽 절반에만 둔다.
"""

import json
import math
import os
import sys

sys.dont_write_bytecode = True  # tools/blender에 __pycache__를 남기지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (  # noqa: E402
    GODOT_ASSETS, Part, bounds, cli_args, export_glb, materials, render_thumbnail, reset_scene, tri_count,
)

OUT_DIR = os.path.join(GODOT_ASSETS, "models", "landmarks")
RES_DIR = "res://assets/models/landmarks"
MAX_TRIS = 1500
LOT_H = 0.12
G = LOT_H  # 부지 판 윗면 높이. 건물은 여기서 시작한다.


# ---------------------------------------------------------------- 색 (sRGB hex)

BASE = {
    "lot": "E4E8ED", "wall": "F3F4F6", "wall2": "E2E6EB", "roof": "C3CAD3",
    "glass": "8C99AB", "front": "4B5566", "trim": "D6DBE2", "dark": "4B5566",
}
PALETTE = {
    "cafe": {"accent": "F2994A", "sign": "6B4F3A"},
    "park": {"lot": "D5EAC9", "path": "EEF0E6", "leaf": "8CC77E", "leaf2": "6FB36A", "trunk": "A3825F",
             "wood": "A9785A", "roof": "7C8794"},
    "gov_office": {"accent": "2F6BFF", "flag": "FFFFFF"},
    "plaza": {"lot": "E8E5DF", "paving": "D9D4CA", "basin": "D6DBE2", "water": "8EC5F0", "lamp": "FFF3D1"},
    "clock_tower": {"wall": "F1EDE6", "roof": "C9775B", "clock": "FFFFFF", "hands": "2E3238"},
    "old_station": {"brick": "D48A70", "dome": "7FA595", "roof": "8E9AA5", "clock": "FFFFFF", "hands": "2E3238"},
    "observation_tower": {"accent": "EF4444"},
    "museum": {"wall": "EFE9DD", "column": "FAF8F3", "roof": "D5CCB6", "accent": "E07A5F"},
    "market": {"roof": "3FA7A0", "sign": "E5533D", "awning1": "F2994A", "awning2": "EF4444", "awning3": "2F6BFF",
               "awning4": "16A34A"},
    "station": {"accent": "3DAE5A", "canopy": "A9C3D9", "disc": "FFFFFF"},
    "gym": {"roof": "6C8BE0"},
}


# ---------------------------------------------------------------- 공통 부품


def lot(p, m, w, d, key="lot"):
    """부지 판. 원점 중심, 높이 0..LOT_H."""
    p.box(m[key], -w / 2, w / 2, -d / 2, d / 2, 0, LOT_H)


def win_y(p, mat, x0, x1, z0, z1, y, out=0.04):
    """y 위치의 앞(+)/뒤(-) 벽에 살짝 튀어나온 창이나 문."""
    s = 1 if y > 0 else -1
    p.box(mat, x0, x1, y - s * 0.02, y + s * out, z0, z1)


def win_x(p, mat, y0, y1, z0, z1, x, out=0.04):
    """x 위치의 오른쪽(+)/왼쪽(-) 벽에 살짝 튀어나온 창."""
    s = 1 if x > 0 else -1
    p.box(mat, x - s * 0.02, x + s * out, y0, y1, z0, z1)


def arch_points(half_w, rise, z0, y, segments=12, cx=0.0):
    """x-z 평면의 반타원 아치(바닥 현 포함) 점들. y 위치에 놓는다."""
    return [(cx + half_w * math.cos(math.pi * k / segments), y, z0 + rise * math.sin(math.pi * k / segments))
            for k in range(segments + 1)]


def clock(p, m, x, y, z, radius, axis, sign):
    """시계 판 + 바늘 두 개. axis="Y"면 ±Y 벽, "X"면 ±X 벽에 붙인다(sign이 방향)."""
    t = 0.12
    if axis == "Y":
        p.disc(m["clock"], x, y + sign * t / 2, z, radius, t, "Y")
        f = y + sign * t
        p.box(m["hands"], x - 0.05, x + 0.05, f, f + sign * 0.04, z, z + radius * 0.6)
        p.box(m["hands"], x, x + radius * 0.8 * sign, f, f + sign * 0.04, z - 0.04, z + 0.04)
    else:
        p.disc(m["clock"], x + sign * t / 2, y, z, radius, t, "X")
        f = x + sign * t
        p.box(m["hands"], f, f + sign * 0.04, y - 0.05, y + 0.05, z, z + radius * 0.6)
        p.box(m["hands"], f, f + sign * 0.04, y, y - radius * 0.8 * sign, z - 0.04, z + 0.04)


def round_tree(p, m, x, y, r, leaf="leaf"):
    p.cylinder(m["trunk"], x, y, G, 0.18, 1.8, segments=6)
    p.sphere(m[leaf], x, y, G + 1.8 + r * 0.75, r, subdivisions=2, squash=0.9)


def pine_tree(p, m, x, y, r, h, leaf="leaf2"):
    p.cylinder(m["trunk"], x, y, G, 0.15, 1.0, segments=6)
    p.cone(m[leaf], x, y, G + 0.8, r, h, segments=10)


# ---------------------------------------------------------------- 랜드마크


def make_cafe(p, m):
    """카페: 2층 상가, 앞 차양, 1층 통유리, 루프탑 파라솔."""
    lot(p, m, 11, 10)
    top = G + 6.4
    p.box(m["wall"], -4, 4, -3.5, 3.5, G, top)
    p.box(m["trim"], -4.15, 4.15, -3.65, 3.65, top, top + 0.35)
    win_y(p, m["glass"], -3.5, -0.8, G + 0.5, G + 2.7, 3.5)
    win_y(p, m["glass"], 0.8, 3.5, G + 0.5, G + 2.7, 3.5)
    win_y(p, m["front"], -0.6, 0.6, G, G + 2.5, 3.5)
    for x0 in (-3.3, -0.7, 1.9):
        win_y(p, m["glass"], x0, x0 + 1.4, G + 4.0, G + 5.8, 3.5)
    for sx in (-1, 1):
        for y0 in (-2.6, 0.6):
            win_x(p, m["glass"], y0, y0 + 2.0, G + 0.8, G + 2.6, sx * 4)
            win_x(p, m["glass"], y0, y0 + 2.0, G + 4.0, G + 5.8, sx * 4)
    # 앞 차양(비스듬한 판)과 간판
    p.hull(m["accent"], [(x, y, z) for x in (-3.8, 3.8) for y, z in
                         ((3.5, G + 3.05), (3.5, G + 3.2), (5.0, G + 2.55), (5.0, G + 2.7))])
    p.box(m["sign"], -1.6, 1.6, 3.5, 3.6, G + 3.3, G + 3.85)
    # 루프탑 파라솔과 테이블
    roof = top + 0.35
    for x, y in ((-2.0, 0.8), (1.6, -1.2)):
        p.cylinder(m["trim"], x, y, roof, 0.05, 2.2, segments=6)
        p.cone(m["accent"], x, y, roof + 1.95, 1.3, 0.55, segments=8)
        p.cylinder(m["wall2"], x, y, roof, 0.5, 0.75, segments=8)


def make_park(p, m):
    """공원: 잔디 부지, 산책로, 둥근 나무와 침엽수, 정자, 벤치, 입구 안내판."""
    lot(p, m, 14, 12)
    p.box(m["path"], -0.9, 0.9, -6, 6, G, G + 0.03)
    p.cylinder(m["path"], 0, 0, G, 2.2, 0.03, segments=16)
    # 정자: 바닥, 기둥 4개, 사모지붕
    px, py = -3.9, -3.0
    p.box(m["wood"], px - 1.5, px + 1.5, py - 1.5, py + 1.5, G, G + 0.3)
    for dx in (-1.2, 1.2):
        for dy in (-1.2, 1.2):
            p.box(m["wood"], px + dx - 0.1, px + dx + 0.1, py + dy - 0.1, py + dy + 0.1, G + 0.3, G + 2.6)
    p.hull(m["roof"], [(px + dx, py + dy, G + 2.6) for dx in (-1.9, 1.9) for dy in (-1.9, 1.9)] + [(px, py, G + 3.9)])
    round_tree(p, m, -4.6, 3.3, 1.6)
    round_tree(p, m, 4.5, 3.2, 1.4, "leaf2")
    round_tree(p, m, 4.0, -3.4, 1.7)
    pine_tree(p, m, -6.0, 0.6, 0.9, 3.6)
    pine_tree(p, m, 6.1, 0.2, 0.9, 3.9)
    pine_tree(p, m, -1.8, -4.9, 0.8, 3.2)
    # 산책로 옆 벤치
    for x, s in ((1.5, 1), (-1.5, -1)):
        p.box(m["wood"], x - 0.25, x + 0.25, 1.6, 3.4, G, G + 0.45)
        p.box(m["wood"], x + s * 0.2, x + s * 0.28, 1.6, 3.4, G + 0.45, G + 0.95)
    # 입구 안내판(정면)
    p.box(m["trim"], 1.55, 1.65, 5.3, 5.4, G, G + 0.8)
    p.box(m["trim"], 2.75, 2.85, 5.3, 5.4, G, G + 0.8)
    p.box(m["front"], 1.4, 3.0, 5.25, 5.45, G + 0.8, G + 1.6)


def make_gov_office(p, m):
    """관공서(구청, 주민센터, 도서관): 4층 박스 건물, 띠창, 현관 지붕, 깃대."""
    lot(p, m, 20, 16)
    top = G + 13.8
    p.box(m["wall"], -8, 8, -4.5, 4.5, G, top)
    p.box(m["trim"], -8.15, 8.15, -4.65, 4.65, top, top + 0.4)
    p.box(m["wall2"], -2, 3, -2, 1.5, top + 0.4, top + 1.6)
    win_y(p, m["glass"], -7.2, -2.2, G + 0.6, G + 2.6, 4.5)
    win_y(p, m["glass"], 2.2, 7.2, G + 0.6, G + 2.6, 4.5)
    win_y(p, m["front"], -1.4, 1.4, G, G + 2.7, 4.5)
    for i in (1, 2, 3):
        z0 = G + 3.4 * i + 1.0
        for y in (4.5, -4.5):
            win_y(p, m["glass"], -7.4, 7.4, z0, z0 + 1.4, y)
        for x in (8, -8):
            win_x(p, m["glass"], -3.8, 3.8, z0, z0 + 1.4, x)
    # 현관 지붕과 기둥
    p.box(m["trim"], -2.8, 2.8, 4.5, 6.6, G + 3.0, G + 3.3)
    for x in (-2.5, 2.5):
        p.box(m["trim"], x - 0.15, x + 0.15, 6.15, 6.45, G, G + 3.0)
    # 깃대 2개
    for x, key in ((5.0, "flag"), (6.4, "accent")):
        p.cylinder(m["trim"], x, 6.6, G, 0.07, 9.0, segments=6)
        p.box(m[key], x + 0.07, x + 1.4, 6.58, 6.62, G + 7.9, G + 8.8)


def make_plaza(p, m):
    """광장: 원형 바닥 무늬, 2단 분수, 가로등 4개, 벤치, 앞쪽 표지석."""
    lot(p, m, 16, 16)
    p.cylinder(m["paving"], 0, 0, G, 6.0, 0.02, segments=32)
    p.cylinder(m["basin"], 0, 0, G, 3.3, 0.55, segments=24)
    p.cylinder(m["water"], 0, 0, G + 0.55, 3.0, 0.03, segments=24)
    p.cylinder(m["basin"], 0, 0, G + 0.55, 0.7, 0.9, segments=12)
    p.cylinder(m["basin"], 0, 0, G + 1.45, 1.0, 0.35, segments=16, radius_top=1.6)
    p.cylinder(m["water"], 0, 0, G + 1.8, 1.45, 0.03, segments=16)
    p.cone(m["water"], 0, 0, G + 1.8, 0.35, 1.5, segments=10)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 6.3, sy * 6.3
            p.cylinder(m["dark"], x, y, G, 0.09, 4.2, segments=6)
            p.box(m["lamp"], x - 0.28, x + 0.28, y - 0.28, y + 0.28, G + 4.2, G + 4.55)
    for x, y, along_x in ((4.7, 0, False), (-4.7, 0, False), (0, -4.7, True)):
        if along_x:
            p.box(m["wall2"], x - 0.9, x + 0.9, y - 0.25, y + 0.25, G, G + 0.45)
        else:
            p.box(m["wall2"], x - 0.25, x + 0.25, y - 0.9, y + 0.9, G, G + 0.45)
    p.box(m["front"], -1.5, 1.5, 7.0, 7.4, G, G + 0.7)


def make_clock_tower(p, m):
    """시계탑: 기단, 사각 탑, 네 면 시계, 종루, 뾰족지붕."""
    lot(p, m, 10, 10)
    p.box(m["trim"], -3, 3, -3, 3, G, G + 1.0)
    p.box(m["wall"], -2.2, 2.2, -2.2, 2.2, G + 1.0, G + 13.5)
    p.box(m["trim"], -2.5, 2.5, -2.5, 2.5, G + 13.5, G + 13.9)
    p.box(m["wall2"], -2.3, 2.3, -2.3, 2.3, G + 13.9, G + 16.6)
    p.box(m["trim"], -2.6, 2.6, -2.6, 2.6, G + 16.6, G + 17.0)
    p.hull(m["roof"], [(x, y, G + 17.0) for x in (-2.6, 2.6) for y in (-2.6, 2.6)] + [(0, 0, G + 21.0)])
    p.cylinder(m["dark"], 0, 0, G + 20.6, 0.07, 1.4, segments=6)
    # 종루 창(네 면), 문(정면)
    for s in (-1, 1):
        win_y(p, m["dark"], -1.2, 1.2, G + 14.4, G + 16.1, s * 2.3)
        win_x(p, m["dark"], -1.2, 1.2, G + 14.4, G + 16.1, s * 2.3)
    win_y(p, m["front"], -0.7, 0.7, G + 1.0, G + 3.4, 2.2)
    zc = G + 11.6
    for s in (-1, 1):
        clock(p, m, 0, s * 2.2, zc, 1.25, "Y", s)
        clock(p, m, s * 2.2, 0, zc, 1.25, "X", s)


def make_old_station(p, m):
    """옛 기차역: 붉은 벽돌 본관과 돔, 양쪽 날개, 흰 띠, 정면 시계와 현관."""
    lot(p, m, 22, 14)
    # 본관
    p.box(m["brick"], -4, 4, -4, 4, G, G + 10)
    p.box(m["trim"], -4.1, 4.1, -4.1, 4.1, G + 3.4, G + 3.7)
    p.box(m["trim"], -4.2, 4.2, -4.2, 4.2, G + 9.6, G + 10.0)
    p.cylinder(m["trim"], 0, 0, G + 10.0, 3.0, 1.0, segments=16)
    rings = []
    for k in range(5):
        a = math.pi / 2 * k / 5
        rings += [(3.0 * math.cos(a) * math.cos(t), 3.0 * math.cos(a) * math.sin(t), G + 11.0 + 3.0 * math.sin(a))
                  for t in (2 * math.pi * i / 16 for i in range(16))]
    p.hull(m["dome"], rings + [(0, 0, G + 14.0)])
    p.cylinder(m["dome"], 0, 0, G + 13.8, 0.45, 0.9, segments=8)
    p.cone(m["dome"], 0, 0, G + 14.7, 0.55, 0.8, segments=8)
    for x0 in (-2.9, -0.7, 1.5):
        win_y(p, m["glass"], x0, x0 + 1.4, G + 4.2, G + 8.2, 4)
    win_y(p, m["front"], -1.3, 1.3, G, G + 3.0, 4)
    clock(p, m, 0, 4.0, G + 8.95, 0.6, "Y", 1)
    # 현관 지붕과 기둥
    p.box(m["trim"], -2.2, 2.2, 4, 5.6, G + 3.0, G + 3.3)
    for x in (-2.0, 2.0):
        p.cylinder(m["trim"], x, 5.3, G, 0.15, 3.0, segments=8)
    # 양쪽 날개
    for s in (-1, 1):
        xa, xb = sorted((s * 4, s * 10.5))
        p.box(m["brick"], xa, xb, -3.5, 3.5, G, G + 6.5)
        p.box(m["trim"], xa, xb, -3.6, 3.6, G + 3.4, G + 3.7)
        p.box(m["trim"], xa, xb, -3.65, 3.65, G + 6.3, G + 6.6)
        outer, inner = s * 10.6, s * 4.0
        p.hull(m["roof"], [(x, y, G + 6.6) for x in (outer, inner) for y in (-3.65, 3.65)]
               + [(s * 9.2, 0, G + 8.4), (inner, 0, G + 8.4)])
        for xc in (5.2, 6.6, 8.0, 9.4):
            win_y(p, m["glass"], s * xc - 0.45, s * xc + 0.45, G + 0.9, G + 2.9, 3.5)
            win_y(p, m["glass"], s * xc - 0.45, s * xc + 0.45, G + 4.2, G + 5.8, 3.5)


def make_observation_tower(p, m):
    """전망 타워: 원통 기단 건물, 가늘어지는 기둥, 전망대, 빨간 끝 안테나."""
    lot(p, m, 10, 10)
    p.cylinder(m["wall"], 0, 0, G, 4.0, 4.0, segments=20)
    p.cylinder(m["glass"], 0, 0, G + 1.3, 4.04, 1.4, segments=20)
    p.cylinder(m["trim"], 0, 0, G + 4.0, 4.2, 0.3, segments=20)
    win_y(p, m["front"], -0.9, 0.9, G, G + 2.4, 4.0, out=0.12)
    p.cylinder(m["wall"], 0, 0, G + 4.3, 1.35, 19.7, segments=12, radius_top=1.0)
    p.cylinder(m["trim"], 0, 0, G + 23.0, 1.1, 1.2, segments=16, radius_top=3.3)
    p.cylinder(m["glass"], 0, 0, G + 24.2, 3.3, 2.0, segments=16, radius_top=3.5)
    p.cylinder(m["trim"], 0, 0, G + 26.2, 3.6, 0.6, segments=16, radius_top=2.6)
    p.cylinder(m["wall"], 0, 0, G + 26.8, 1.6, 1.2, segments=12)
    p.cylinder(m["wall2"], 0, 0, G + 28.0, 0.35, 4.0, segments=8, radius_top=0.15)
    p.cylinder(m["accent"], 0, 0, G + 32.0, 0.15, 2.0, segments=8, radius_top=0.05)


def make_museum(p, m):
    """문화시설(박물관): 2단 기단, 열주 6개, 박공 지붕, 정면 현수막."""
    lot(p, m, 18, 14)
    p.box(m["trim"], -7.2, 7.2, -5.0, 5.6, G, G + 0.35)
    p.box(m["trim"], -6.8, 6.8, -4.7, 5.2, G + 0.35, G + 0.7)
    p.box(m["wall"], -6.2, 6.2, -4.4, 2.4, G + 0.7, G + 7.2)
    for x in (-5.25, -3.15, -1.05, 1.05, 3.15, 5.25):
        p.box(m["column"], x - 0.45, x + 0.45, 3.85, 4.75, G + 0.7, G + 0.9)
        p.cylinder(m["column"], x, 4.3, G + 0.9, 0.36, 5.5, segments=10)
        p.box(m["column"], x - 0.45, x + 0.45, 3.85, 4.75, G + 6.4, G + 6.6)
    p.box(m["trim"], -6.6, 6.6, -4.6, 5.0, G + 6.6, G + 7.5)
    p.hull(m["roof"], [(x, y, G + 7.5) for x in (-6.8, 6.8) for y in (-4.7, 5.1)]
           + [(0, y, G + 9.6) for y in (-4.7, 5.1)])
    win_y(p, m["front"], -1.1, 1.1, G + 0.7, G + 4.3, 2.4)
    for x in (-2.55, 2.55):
        win_y(p, m["accent"], x - 0.35, x + 0.35, G + 2.6, G + 6.0, 2.4)


def make_market(p, m):
    """시장: 양쪽 상점 줄, 아치형 아케이드 지붕, 알록달록 차양, 정면 간판 문."""
    lot(p, m, 20, 14)
    awnings = [m["awning1"], m["awning2"], m["awning3"], m["awning4"]]
    spans = ((-5.5, -3.3), (-3.0, -0.8), (-0.5, 1.7), (2.0, 3.8))
    for s in (-1, 1):
        xa, xb = sorted((s * 2.6, s * 7.0))
        p.box(m["wall2"], xa, xb, -6, 4, G, G + 4.2)
        # 통로 쪽 진열창과 차양
        for i, (y0, y1) in enumerate(spans):
            win_x(p, m["glass"], y0 + 0.2, y1 - 0.2, G + 0.4, G + 2.3, s * 2.6)
            p.box(awnings[(i + (s > 0)) % 4], s * 2.6, s * 1.7, y0, y1, G + 2.5, G + 2.65)
        # 바깥(정면) 진열창과 차양
        win_y(p, m["glass"], xa + 0.5, xb - 0.5, G + 0.5, G + 2.3, 4)
        p.box(awnings[0 if s < 0 else 2], xa, xb, 4, 5.1, G + 2.6, G + 2.75)
    p.hull(m["roof"], arch_points(7.3, 3.0, G + 4.2, -6.3) + arch_points(7.3, 3.0, G + 4.2, 4.6))
    # 정면 문: 기둥 2개와 간판
    for x in (-7.4, 7.4):
        p.box(m["front"], x - 0.2, x + 0.2, 4.7, 5.1, G, G + 6.6)
    p.box(m["sign"], -6.0, 6.0, 4.75, 5.05, G + 5.0, G + 6.2)


def make_station(p, m):
    """역: 유리 정면 역사(초록 띠), 앞쪽 지하철 출입구 지붕, 역 번호 기둥, 버스 정류장."""
    lot(p, m, 14, 12)
    p.box(m["wall"], -6, 6, -5.5, -1.0, G, G + 6.5)
    p.box(m["glass"], -5.4, 5.4, -1.02, -0.96, G + 0.4, G + 5.4)
    p.box(m["dark"], -1.2, 1.2, -0.98, -0.92, G, G + 2.6)
    p.box(m["accent"], -6.05, 6.05, -5.55, -0.95, G + 5.7, G + 6.5)
    p.box(m["trim"], -6.2, 6.2, -5.7, -0.8, G + 6.5, G + 6.9)
    # 지하철 출입구: 낮은 벽, 계단 입구(정면 표시), 기둥 4개, 지붕, 초록 간판
    x0, x1, y0, y1 = -5.2, -1.6, 0.8, 4.6
    p.box(m["wall2"], x0, x0 + 0.2, y0, y1, G, G + 1.0)
    p.box(m["wall2"], x1 - 0.2, x1, y0, y1, G, G + 1.0)
    p.box(m["wall2"], x0, x1, y0, y0 + 0.2, G, G + 1.0)
    p.box(m["front"], x0 + 0.2, x1 - 0.2, y0 + 0.2, y1, G, G + 0.02)
    for x in (x0 - 0.1, x1 + 0.1):
        for y in (y0 - 0.1, y1 + 0.1):
            p.box(m["trim"], x - 0.08, x + 0.08, y - 0.08, y + 0.08, G, G + 2.8)
    p.box(m["canopy"], x0 - 0.3, x1 + 0.3, y0 - 0.3, y1 + 0.3, G + 2.8, G + 2.95)
    p.box(m["accent"], x0 - 0.3, x1 + 0.3, y1 + 0.3, y1 + 0.4, G + 2.6, G + 2.95)
    # 역 번호 기둥
    p.box(m["trim"], 2.0, 2.5, 3.8, 4.3, G, G + 3.6)
    p.box(m["accent"], 1.9, 2.6, 3.7, 4.4, G + 3.6, G + 4.6)
    p.disc(m["disc"], 2.25, 4.42, G + 4.1, 0.25, 0.04, "Y", segments=12)
    # 버스 정류장
    p.box(m["glass"], 3.0, 6.0, 3.6, 3.7, G, G + 2.3)
    p.box(m["trim"], 2.9, 6.1, 3.5, 4.9, G + 2.3, G + 2.45)
    p.box(m["wall2"], 3.4, 5.6, 3.75, 4.1, G, G + 0.45)


def make_gym(p, m):
    """체육시설(체육관, 수영장, 헬스장): 아치 지붕, 정면 아치 유리, 띠창, 현관 지붕."""
    lot(p, m, 20, 16)
    p.box(m["wall"], -8, 8, -6, 6, G, G + 5.0)
    p.box(m["wall2"], -8.05, 8.05, -6.05, 6.05, G, G + 0.6)
    p.hull(m["roof"], arch_points(8.4, 3.4, G + 5.0, -6.4, 14) + arch_points(8.4, 3.4, G + 5.0, 6.4, 14))
    p.hull(m["glass"], arch_points(7.0, 2.6, G + 5.05, 6.4, 14) + arch_points(7.0, 2.6, G + 5.05, 6.46, 14))
    for y in (6, -6):
        win_y(p, m["glass"], -7.0, 7.0, G + 2.9, G + 4.5, y)
    for x in (8, -8):
        win_x(p, m["glass"], -5.0, 5.0, G + 2.9, G + 4.5, x)
    win_y(p, m["front"], -1.6, 1.6, G, G + 2.6, 6)
    p.box(m["trim"], -3.0, 3.0, 6, 7.6, G + 2.7, G + 2.95)


# ---------------------------------------------------------------- 목록

# (id, 표시 이름, 이 모델을 쓰는 업종들, 이 모델을 쓰는 장소 이름들, 만드는 함수)
LANDMARKS = [
    ("cafe", "카페", ["카페"], [], make_cafe),
    ("park", "공원", ["공원"], [], make_park),
    ("gov_office", "관공서", ["관공서"], [], make_gov_office),
    ("plaza", "광장", ["광장"], [], make_plaza),
    ("clock_tower", "시계탑", ["랜드마크"], ["시계탑"], make_clock_tower),
    ("old_station", "옛 기차역", [], ["옛 기차역"], make_old_station),
    ("observation_tower", "전망 타워", [], ["전망 타워"], make_observation_tower),
    ("museum", "문화시설", ["문화시설"], [], make_museum),
    ("market", "시장", ["시장"], [], make_market),
    ("station", "역", ["역"], [], make_station),
    ("gym", "체육시설", ["체육시설"], [], make_gym),
]


# ---------------------------------------------------------------- 내보내기


def build(lid, builder, out_dir):
    col = reset_scene()
    p = Part("Body")
    builder(p, materials(lid, {**BASE, **PALETTE.get(lid, {})}))
    objs = [p.build(col)]
    tris = tri_count(objs)
    if tris > MAX_TRIS:
        raise SystemExit(f"{lid}: {tris} triangles > {MAX_TRIS}")
    export_glb(os.path.join(out_dir, f"{lid}.glb"))
    render_thumbnail(objs, os.path.join(out_dir, "thumbs", f"{lid}.png"))
    lo, hi = bounds(objs)
    w, d, h = hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]
    print(f"[make_landmarks] {lid}: {tris} tris, W x D x H {w:.1f} x {d:.1f} x {h:.1f} m, z_min {lo[2]:.3f}")
    # Godot 축(x 폭, y 높이, z 깊이)으로 기록한다.
    return {"tris": tris, "size_m": [round(w, 2), round(h, 2), round(d, 2)]}


def write_index(out_dir, stats):
    path = os.path.join(out_dir, "landmarks.json")
    old = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            old = json.load(f).get("models", {})
    index = {"by_name": {}, "by_kind": {}, "models": {}}
    for lid, label, kinds, names, _ in LANDMARKS:
        for k in kinds:
            index["by_kind"][k] = lid
        for n in names:
            index["by_name"][n] = lid
        entry = {"label": label, "glb": f"{RES_DIR}/{lid}.glb", "thumb": f"{RES_DIR}/thumbs/{lid}.png"}
        entry.update(stats.get(lid) or {k: v for k, v in old.get(lid, {}).items() if k in ("tris", "size_m")})
        index["models"][lid] = entry
    with open(path, "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main():
    out_dir, only = cli_args(OUT_DIR)
    stats = {}
    for lid, _, _, _, builder in LANDMARKS:
        if not only or lid in only:
            stats[lid] = build(lid, builder, out_dir)
    write_index(out_dir, stats)


if __name__ == "__main__":
    main()
