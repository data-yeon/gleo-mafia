"""현장 3D 확대도용 인물(제보자 9종, 범인 포즈 2종)과 소품 4종을 .glb, PNG 썸네일, 목록 JSON으로 내보낸다.

실행 (저장소 루트에서):
    blender --background --factory-startup --python tools/blender/make_figures.py

결과 (godot/assets/models/figures/)
- <파일>.glb, thumbs/<파일>.png(256px 투명), figures.json
- figures.json의 키(id)는 역할 이름(VENDOR, COP …)과 소품 이름(atm …)이고, 파일 이름은 소문자다.
  항목의 kind는 "figure"(인물) 또는 "prop"(소품)이다.

규격 (make_people.py와 같다)
- 1 단위 = 1m, 원점 = 바닥 중앙(모델 전체의 가로·세로 가운데), 정면(얼굴) = Godot -Z(Blender +Y).
- 노드: Body + 서 있는 인물은 LegL, LegR(원점 = 엉덩이 높이 hip_m, rotation.x로 흔들기).
  DRONE은 머리 위에 떠 있는 Drone 노드(원점 = 드론 가운데)가 따로 있다.
  CULPRIT_RUN은 다리 노드에 뛰는 자세 회전이 들어 있다(메시는 곧고, 노드 회전만 있다).
- 머티리얼 이름은 <파일 이름>_<부위>. 텍스처 없이 채도 낮은 무광 단색.
- 누설 금지: 제보자 9종은 '자칭 직업' 모습만 한다. 범인 2종은 결말 연출 전용이다.
"""

import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True  # tools/blender에 __pycache__를 남기지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (  # noqa: E402
    GODOT_ASSETS, Part, bounds, cli_args, cylinder_bm, export_glb, godot_size, materials, render_thumbnail,
    reset_scene, tri_count, write_catalog,
)

OUT_DIR = os.path.join(GODOT_ASSETS, "models", "figures")
RES_DIR = "res://assets/models/figures"
HIP = 0.90                         # 어른 엉덩이(다리 회전축) 높이(m)


# ---------------------------------------------------------------- 색 (sRGB hex)

BASE = {"skin": "E7C9A9", "hair": "3F3A36", "shoe": "2E3238", "pants": "4B5563"}
PALETTE = {
    "vendor": {"top": "B5736A", "apron": "EFE7D6", "cart": "C9A27E", "tray": "E8735A", "food": "B5653A",
               "wheel": "3A3F47", "towel": "F3F4F6"},
    "taxi": {"top": "F3F4F6", "vest": "E3B572", "cap": "5B6472", "brim": "3A3F47"},
    "drone": {"top": "9DB7D5", "pants": "C8B79E", "remote": "3A3F47", "drone": "5B6472", "rotor": "C9CED6",
              "lamp": "7FC4E0"},
    "local": {"top": "D9D4C7", "vest": "8C7B6B", "pants": "6B7280", "hair": "C9CED6", "cane": "6B4F3A",
              "cap": "7A746C"},
    "rider": {"top": "5B6472", "pants": "374151", "helmet": "9FCFC8", "visor": "3A3F47", "bag": "9FCFC8"},
    "guard": {"top": "8E96A3", "pants": "7A828F", "cap": "6B7280", "brim": "2E3238", "belt": "3A3F47"},
    "cop": {"top": "1E2B57", "pants": "1E2B57", "vest": "CFE07A", "stripe": "E5E7EB", "cap": "1E2B57",
            "brim": "1A1F2B", "badge": "D4AF37", "belt": "1A1F2B"},
    "gossip": {"top": "D98F8A", "pants": "6B7280", "hair": "5A4A42", "bag": "7FA595", "leek": "A8D5A0",
               "leek_white": "F3F4F6"},
    "anon": {"top": "4B5563", "pants": "3A3F47", "shoe": "2E3238", "face": "1F242B", "skin": "3A3F47"},
    "culprit_run": {"top": "4B5563", "pants": "374151", "cap": "2E3238", "mask": "D6DBE2", "sack": "C9B37E",
                    "won": "3E6B48"},
    "culprit_cuffed": {"top": "4B5563", "pants": "374151", "cap": "2E3238", "mask": "D6DBE2", "cuffs": "9AA1AB"},
    "atm": {"booth": "4A78B8", "panel": "E2E6EB", "screen": "2F4A6E", "keys": "C9CED6", "slot": "2E3238",
            "sign": "F7F8FA", "base": "5B6472"},
    "handcuffs": {"steel": "9AA1AB"},
    "police_tape": {"post": "D6DBE2", "base": "5B6472", "tape": "F2C14E", "stripe": "2E3238"},
    "money_bag": {"sack": "C9B37E", "tie": "8C7B6B", "won": "3E6B48"},
}


# ---------------------------------------------------------------- 사람 골격

# 팔 자세: 팔꿈치(E)와 손(H)의 위치. sx는 -1(왼쪽) / 1(오른쪽), s는 키 비율, sh는 어깨 높이, ly는 몸통 위쪽의 앞 기울기
ARM_POSES = {
    "down": lambda sx, s, sh, ly: ((sx * 0.255 * s, ly * 0.6, sh - 0.30 * s), (sx * 0.26 * s, ly * 0.3, 0.84 * s)),
    "front": lambda sx, s, sh, ly: ((sx * 0.25 * s, ly + 0.06 * s, sh - 0.30 * s), (sx * 0.12 * s, ly + 0.30 * s, sh - 0.30 * s)),
    "cart": lambda sx, s, sh, ly: ((sx * 0.25 * s, ly + 0.08 * s, sh - 0.32 * s), (sx * 0.22 * s, ly + 0.36 * s, sh - 0.50 * s)),
    "cane": lambda sx, s, sh, ly: ((sx * 0.26 * s, ly + 0.05 * s, sh - 0.30 * s), (sx * 0.28 * s, ly + 0.22 * s, sh - 0.56 * s)),
    "bag": lambda sx, s, sh, ly: ((sx * 0.26 * s, ly * 0.6, sh - 0.30 * s), (sx * 0.29 * s, ly * 0.3, 0.86 * s)),
    "behind": lambda sx, s, sh, ly: ((sx * 0.24 * s, ly - 0.10 * s, sh - 0.30 * s), (sx * 0.06 * s, ly - 0.20 * s, sh - 0.54 * s)),
    "run_fwd": lambda sx, s, sh, ly: ((sx * 0.25 * s, ly + 0.16 * s, sh - 0.24 * s), (sx * 0.20 * s, ly + 0.32 * s, sh - 0.06 * s)),
    "run_back": lambda sx, s, sh, ly: ((sx * 0.25 * s, ly - 0.18 * s, sh - 0.22 * s), (sx * 0.27 * s, ly - 0.30 * s, sh - 0.46 * s)),
}


class Fig:
    """인물 하나의 부품과 기준점: body(Part), legs(오브젝트 목록), 어깨 높이, 머리 중심, 손 위치."""

    def __init__(self, body, legs, hip, sh, head, head_r, hands):
        self.body, self.legs, self.hip, self.sh = body, legs, hip, sh
        self.head, self.head_r, self.hands = head, head_r, hands


def figure(col, m, s=1.0, head_r=0.105, lean=0.0, bow=0.0, arms=("down", "down"), legs=(0.0, 0.0),
           hair="short", face=True):
    """서 있는 사람. s는 키 비율(1.0 ≈ 1.72m). lean은 몸통 위쪽을 앞으로 기울이는 정도(m),
    bow는 고개 숙임(0..1), arms는 (왼팔, 오른팔) 자세, legs는 (왼다리, 오른다리) 앞으로 든 각도(도)."""
    hip = HIP * s
    leg_objs = []
    for (name, sx), angle in zip((("LegL", -1), ("LegR", 1)), legs):
        leg = Part(name)
        x = sx * 0.095 * s
        leg.box(m["pants"], x - 0.068 * s, x + 0.068 * s, -0.075 * s, 0.075 * s, 0.07 * s, hip)
        leg.box(m["shoe"], x - 0.07 * s, x + 0.07 * s, -0.08 * s, 0.15 * s, 0, 0.08 * s)
        obj = leg.build(col, origin=(x, 0, hip))
        obj.rotation_euler.x = math.radians(angle)       # +는 발이 앞(+Y)으로
        leg_objs.append(obj)
    body = Part("Body")
    sh = 1.42 * s
    ly = lean
    body.hull(m["top"], [(x, y, hip - 0.06 * s) for x in (-0.17 * s, 0.17 * s) for y in (-0.10 * s, 0.10 * s)]
              + [(x, ly + y, sh) for x in (-0.21 * s, 0.21 * s) for y in (-0.11 * s, 0.11 * s)])
    body.box(m["skin"], -0.045 * s, 0.045 * s, ly - 0.045 * s, ly + 0.045 * s, sh, sh + 0.09 * s)
    head = (0.0, ly + bow * 0.07 * s, sh + 0.09 * s + head_r * 0.9 - bow * 0.04 * s)
    if face:
        body.sphere(m["skin"], *head, head_r, subdivisions=2)
    if hair in ("short", "short_lo"):
        # short_lo: 모자 아래라 거의 안 보이는 머리카락(삼각형을 아낀다)
        body.sphere(m["hair"], head[0], head[1] - 0.03 * s, head[2] + 0.035 * s, head_r * 1.06,
                    subdivisions=2 if hair == "short" else 1, squash=0.78)
    elif hair == "perm":
        body.sphere(m["hair"], head[0], head[1] - 0.025 * s, head[2] + 0.03 * s, head_r * 1.08, subdivisions=1, squash=0.85)
        for i in range(6):
            a = math.pi * (0.15 + 0.7 * i / 5)
            body.sphere(m["hair"], head[0] + math.cos(a) * head_r * 0.85, head[1] - 0.045 * s,
                        head[2] + math.sin(a) * head_r * 0.75 + 0.02 * s, head_r * 0.42, subdivisions=1)
    hands = {}
    for side, sx, pose in (("L", -1, arms[0]), ("R", 1, arms[1])):
        shoulder = (sx * 0.255 * s, ly, sh - 0.04 * s)
        elbow, hand = ARM_POSES[pose](sx, s, sh, ly)
        body.stick(m["top"], shoulder, elbow, 0.045 * s)
        body.stick(m["top"], elbow, hand, 0.04 * s)
        body.box(m["skin"], hand[0] - 0.04 * s, hand[0] + 0.04 * s, hand[1] - 0.04 * s, hand[1] + 0.04 * s,
                 hand[2] - 0.05 * s, hand[2] + 0.03 * s)
        hands[side] = hand
    return Fig(body, leg_objs, hip, sh, head, head_r, hands)


def vest(f, mat, s=1.0, lean=0.0):
    """몸통을 감싸는 조끼(몸통보다 살짝 크다). 팔과 어깨 끝은 윗옷 색으로 남는다."""
    f.body.hull(mat, [(x, y, f.hip - 0.02 * s) for x in (-0.18 * s, 0.18 * s) for y in (-0.115 * s, 0.115 * s)]
                + [(x, lean + y, f.sh - 0.03 * s) for x in (-0.19 * s, 0.19 * s) for y in (-0.122 * s, 0.122 * s)])


def peaked_cap(f, crown, brim, s=1.0):
    """챙 모자(경찰·경비 제모): 위가 살짝 넓은 원통 + 앞쪽 챙."""
    hx, hy, hz = f.head
    f.body.cylinder(crown, hx, hy - 0.005, hz + f.head_r * 0.35, f.head_r * 1.05, 0.10 * s, segments=12,
                    radius_top=f.head_r * 1.22)
    f.body.hull(brim, [(x, y, hz + f.head_r * 0.38) for x in (-0.08 * s, 0.08 * s) for y in (hy + 0.06 * s, hy + 0.17 * s)]
                + [(x, hy + 0.06 * s, hz + f.head_r * 0.45) for x in (-0.08 * s, 0.08 * s)])


def ball_cap(f, crown, brim, s=1.0):
    """야구 모자: 머리 윗부분 돔(고리 3단) + 앞 챙."""
    hx, hy, hz = f.head
    r = f.head_r
    dome = []
    for dz, k in ((0.15, 1.1), (0.55, 0.98), (0.9, 0.62)):
        dome += [(hx + k * r * math.cos(2 * math.pi * i / 10), hy - 0.01 * s + k * r * math.sin(2 * math.pi * i / 10),
                  hz + dz * r) for i in range(10)]
    f.body.hull(crown, dome + [(hx, hy - 0.01 * s, hz + 1.05 * r)])
    f.body.box(brim, hx - 0.075 * s, hx + 0.075 * s, hy + 0.05 * s, hy + 0.17 * s, hz + f.head_r * 0.25,
               hz + f.head_r * 0.25 + 0.015 * s)


def money_bag(p, m, cx, cy, z0, k=1.0):
    """돈 가방(자루): 불룩한 몸통, 묶은 목, 앞면 ₩. k는 크기 비율(1.0 ≈ 높이 0.46m)."""
    pts = []
    for z, r in ((0.0, 0.12), (0.08, 0.17), (0.22, 0.17), (0.32, 0.09)):
        pts += [(cx + k * r * math.cos(2 * math.pi * i / 10), cy + k * r * math.sin(2 * math.pi * i / 10), z0 + k * z)
                for i in range(10)]
    p.hull(m["sack"], pts)
    p.cone(m.get("tie", m["sack"]), cx, cy, z0 + k * 0.30, k * 0.07, k * 0.14, segments=8)
    # 앞면 ₩: W 네 획 + 가로 두 줄
    fy = cy + k * 0.165
    w = [(-0.08, 0.27), (-0.045, 0.10), (0.0, 0.21), (0.045, 0.10), (0.08, 0.27)]
    for (x0, z0w), (x1, z1w) in zip(w, w[1:]):
        p.stick(m["won"], (cx + k * x0, fy, z0 + k * z0w), (cx + k * x1, fy, z0 + k * z1w), k * 0.011)
    for zb in (0.20, 0.16):
        p.stick(m["won"], (cx - k * 0.09, fy, z0 + k * zb), (cx + k * 0.09, fy, z0 + k * zb), k * 0.009)


def torus_bm(cx, cz, R, r, major=10, minor=4):
    """x-z 평면에 선 고리(축이 Y). 수갑 고리에 쓴다."""
    bm = bmesh.new()
    rows = []
    for i in range(major):
        a = 2 * math.pi * i / major
        row = []
        for j in range(minor):
            b = 2 * math.pi * j / minor
            d = R + r * math.cos(b)
            row.append(bm.verts.new((cx + d * math.cos(a), r * math.sin(b), cz + d * math.sin(a))))
        rows.append(row)
    for i in range(major):
        for j in range(minor):
            a, b = rows[i], rows[(i + 1) % major]
            bm.faces.new((a[j], b[j], b[(j + 1) % minor], a[(j + 1) % minor]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


# ---------------------------------------------------------------- 제보자 9종


def make_vendor(col, m):
    """노점상: 앞치마, 머리 수건, 앞에 작은 손수레(떡볶이 판)."""
    f = figure(col, m, arms=("cart", "cart"))
    b = f.body
    b.box(m["apron"], -0.16, 0.16, 0.105, 0.125, f.hip - 0.32, f.sh - 0.16)
    hx, hy, hz = f.head
    b.cylinder(m["towel"], hx, hy - 0.01, hz + 0.02, f.head_r * 1.06, 0.035, segments=12)
    # 손수레: 몸통, 떡볶이 판, 손잡이, 바퀴 2개, 앞 다리
    b.box(m["cart"], -0.42, 0.42, 0.48, 1.18, 0.36, 0.84)
    b.box(m["tray"], -0.36, 0.36, 0.54, 1.12, 0.84, 0.90)
    for i in range(3):
        b.box(m["food"], -0.25 + i * 0.18, -0.13 + i * 0.18, 0.62, 1.04, 0.90, 0.93)
    for sx in (-1, 1):
        b.stick(m["cart"], (sx * 0.22, 0.48, 0.78), (sx * 0.22, 0.40, 0.92), 0.02)
        wheel = cylinder_bm(0.18, 0.06, 10, axis="X")
        bmesh.ops.translate(wheel, vec=(sx * 0.45, 0.78, 0.18), verts=wheel.verts[:])
        b.add(wheel, m["wheel"])
    b.box(m["cart"], -0.38, 0.38, 1.10, 1.16, 0.0, 0.36)
    return f


def make_taxi_driver(col, m):
    """택시기사: 흰 셔츠, 택시색 조끼, 납작한 모자."""
    f = figure(col, m)
    vest(f, m["vest"])
    hx, hy, hz = f.head
    f.body.sphere(m["cap"], hx, hy - 0.01, hz + f.head_r * 0.58, f.head_r * 1.08, subdivisions=2, squash=0.5)
    f.body.box(m["brim"], hx - 0.08, hx + 0.08, hy + 0.05, hy + 0.16, hz + f.head_r * 0.5, hz + f.head_r * 0.5 + 0.015)
    return f


def make_drone_youtuber(col, m):
    """드론 유튜버: 후드, 두 손에 조종기, 머리 위 앞쪽에 떠 있는 작은 드론(Drone 노드)."""
    f = figure(col, m, arms=("front", "front"))
    hl, hr = f.hands["L"], f.hands["R"]
    cz, cy = (hl[2] + hr[2]) / 2, (hl[1] + hr[1]) / 2
    f.body.box(m["remote"], -0.11, 0.11, cy - 0.04, cy + 0.06, cz - 0.02, cz + 0.03)
    for sx in (-1, 1):
        f.body.box(m["remote"], sx * 0.05 - 0.01, sx * 0.05 + 0.01, cy, cy + 0.02, cz + 0.03, cz + 0.07)
    # 드론: 원점이 드론 가운데인 따로 노드
    d = Part("Drone")
    dc = Vector((0.0, 0.32, 2.25))
    d.box(m["drone"], dc.x - 0.09, dc.x + 0.09, dc.y - 0.09, dc.y + 0.09, dc.z - 0.03, dc.z + 0.03)
    d.box(m["lamp"], dc.x - 0.03, dc.x + 0.03, dc.y + 0.09, dc.y + 0.10, dc.z - 0.015, dc.z + 0.01)
    for ax, ay in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        tip = (dc.x + ax * 0.2, dc.y + ay * 0.2, dc.z + 0.01)
        d.stick(m["drone"], (dc.x, dc.y, dc.z + 0.01), tip, 0.012)
        d.cylinder(m["rotor"], tip[0], tip[1], dc.z + 0.03, 0.09, 0.01, segments=8)
    drone = d.build(col, origin=tuple(dc))
    f.legs.append(drone)
    return f


def make_local(col, m):
    """동네 토박이(어르신): 조금 작은 키, 살짝 굽은 등, 흰머리, 니트 조끼, 납작 모자, 오른손 지팡이."""
    s = 0.93
    f = figure(col, m, s=s, lean=0.05, bow=0.3, arms=("down", "cane"), hair="short")
    vest(f, m["vest"], s, lean=0.05)
    hx, hy, hz = f.head
    f.body.sphere(m["cap"], hx, hy - 0.005, hz + f.head_r * 0.62, f.head_r * 1.06, subdivisions=1, squash=0.5)
    f.body.box(m["cap"], hx - 0.07, hx + 0.07, hy + 0.05, hy + 0.15, hz + f.head_r * 0.55, hz + f.head_r * 0.55 + 0.015)
    h = f.hands["R"]
    f.body.stick(m["cane"], (h[0], h[1], h[2] + 0.04), (h[0] + 0.03, h[1] + 0.08, 0.0), 0.014)
    f.body.stick(m["cane"], (h[0] - 0.05, h[1], h[2] + 0.04), (h[0] + 0.02, h[1], h[2] + 0.04), 0.014)
    return f


def make_rider(col, m):
    """배달 라이더: 민트 헬멧(어두운 앞가리개), 짙은 재킷, 등에 민트 배달 가방."""
    f = figure(col, m, hair=None)
    hx, hy, hz = f.head
    f.body.sphere(m["helmet"], hx, hy - 0.01, hz + 0.01, f.head_r * 1.32, subdivisions=2, squash=0.95)
    f.body.box(m["visor"], hx - 0.09, hx + 0.09, hy + 0.10, hy + 0.13, hz - 0.02, hz + 0.05)
    f.body.box(m["bag"], -0.21, 0.21, -0.40, -0.11, 0.98, 1.40)
    return f


def make_guard(col, m):
    """경비원: 회색 제복, 챙 모자, 허리띠."""
    f = figure(col, m, hair="short")
    peaked_cap(f, m["cap"], m["brim"])
    f.body.box(m["belt"], -0.18, 0.18, -0.105, 0.105, f.hip - 0.02, f.hip + 0.04)
    return f


def make_cop(col, m):
    """순찰 경관: 남색 제복과 경찰 모자(금색 모표), 형광 조끼(흰 반사 띠), 허리띠."""
    f = figure(col, m, hair="short")
    vest(f, m["vest"])
    for z in (f.hip + 0.12, f.hip + 0.24):
        f.body.box(m["stripe"], -0.185, 0.185, -0.125, 0.125, z, z + 0.035)
    f.body.box(m["belt"], -0.185, 0.185, -0.12, 0.12, f.hip - 0.03, f.hip + 0.02)
    peaked_cap(f, m["cap"], m["brim"])
    hx, hy, hz = f.head
    f.body.box(m["badge"], hx - 0.02, hx + 0.02, hy + f.head_r * 1.1, hy + f.head_r * 1.1 + 0.015,
               hz + f.head_r * 0.55, hz + f.head_r * 0.85)
    return f


def make_gossip(col, m):
    """오지랖 주민: 파마머리, 분홍 윗옷, 왼손에 장바구니(대파가 삐죽)."""
    f = figure(col, m, arms=("bag", "down"), hair="perm")
    h = f.hands["L"]
    b = f.body
    bx = h[0] - 0.02
    b.box(m["bag"], bx - 0.07, bx + 0.07, h[1] - 0.17, h[1] + 0.17, 0.42, 0.74)
    b.stick(m["bag"], (bx, h[1] - 0.12, 0.74), (bx, h[1] - 0.05, h[2]), 0.012)
    b.stick(m["bag"], (bx, h[1] + 0.12, 0.74), (bx, h[1] + 0.05, h[2]), 0.012)
    b.stick(m["leek_white"], (bx - 0.02, h[1] + 0.06, 0.70), (bx - 0.03, h[1] + 0.10, 0.82), 0.02)
    b.stick(m["leek"], (bx - 0.03, h[1] + 0.10, 0.82), (bx - 0.05, h[1] + 0.16, 1.02), 0.022)
    return f


def make_anon(col, m):
    """익명 제보자: 후드를 깊게 쓴 어두운 실루엣. 얼굴 자리는 더 어두운 단색으로 비운다."""
    f = figure(col, m, hair=None, face=False)
    hx, hy, hz = f.head
    f.body.sphere(m["top"], hx, hy - 0.015, hz + 0.01, f.head_r * 1.3, subdivisions=2, squash=1.05)
    f.body.disc(m["face"], hx, hy + f.head_r * 1.12, hz - 0.01, f.head_r * 0.78, 0.04, "Y", segments=12)
    return f


# ---------------------------------------------------------------- 범인 2종 (결말 전용)


def mask_and_cap(f, m):
    hx, hy, hz = f.head
    ball_cap(f, m["cap"], m["cap"])
    f.body.hull(m["mask"], [(x, hy + f.head_r * 0.55, z) for x in (-0.07, 0.07) for z in (hz - 0.07, hz - 0.005)]
                + [(x, hy + f.head_r * 1.02, z) for x in (-0.05, 0.05) for z in (hz - 0.06, hz - 0.01)])


def make_culprit_run(col, m):
    """달아나는 범인: 모자와 마스크, 앞으로 기운 뛰는 자세, 왼손에 돈 가방."""
    f = figure(col, m, lean=0.10, arms=("run_back", "run_fwd"), legs=(-25.0, 35.0), hair="short_lo")
    mask_and_cap(f, m)
    h = f.hands["L"]
    money_bag(f.body, m, h[0], h[1], h[2] - 0.36, k=0.8)
    return f


def make_culprit_cuffed(col, m):
    """수갑 찬 범인: 모자와 마스크, 고개를 숙이고 손을 등 뒤로 모아 수갑을 찼다."""
    f = figure(col, m, bow=1.0, arms=("behind", "behind"), hair="short_lo")
    mask_and_cap(f, m)
    hl, hr = f.hands["L"], f.hands["R"]
    for h in (hl, hr):
        f.body.box(m["cuffs"], h[0] - 0.05, h[0] + 0.05, h[1] - 0.05, h[1] + 0.05, h[2] + 0.03, h[2] + 0.06)
    f.body.stick(m["cuffs"], (hl[0], hl[1] - 0.05, hl[2] + 0.045), (hr[0], hr[1] - 0.05, hr[2] + 0.045), 0.008)
    return f


# ---------------------------------------------------------------- 소품 4종


def make_atm(col, m):
    """ATM 부스: 은행 파랑 몸체, 밝은 앞판, 화면, 키패드, 카드·지폐 투입구, 위 간판 띠."""
    p = Part("Body")
    p.box(m["base"], -0.47, 0.47, -0.37, 0.37, 0, 0.06)
    p.box(m["booth"], -0.45, 0.45, -0.35, 0.35, 0.06, 1.95)
    p.box(m["panel"], -0.38, 0.38, 0.35, 0.37, 0.75, 1.65)
    p.box(m["screen"], -0.22, 0.22, 0.37, 0.385, 1.25, 1.55)
    p.hull(m["keys"], [(x, y, z) for x in (-0.20, 0.06) for y, z in ((0.37, 1.04), (0.37, 0.96), (0.47, 0.96))])
    p.box(m["slot"], 0.10, 0.26, 0.37, 0.39, 1.08, 1.11)
    p.box(m["slot"], -0.16, 0.16, 0.37, 0.385, 0.84, 0.88)
    p.box(m["sign"], -0.45, 0.45, 0.35, 0.38, 1.75, 1.90)
    return [p.build(col)]


def make_handcuffs(col, m):
    """수갑: 선 고리 두 개 + 짧은 사슬. 실제 크기(폭 약 0.3m). 머리 위 아이콘으로 쓸 때는 2~3배 키운다."""
    p = Part("Body")
    for sx in (-1, 1):
        p.add(torus_bm(sx * 0.085, 0.08, 0.065, 0.012), m["steel"])
    p.box(m["steel"], -0.03, -0.005, -0.006, 0.006, 0.072, 0.088)
    p.box(m["steel"], 0.005, 0.03, -0.006, 0.006, 0.072, 0.088)
    return [p.build(col)]


def make_police_tape(col, m):
    """폴리스 라인: 기둥 2개(4m 간격) + 노란 띠(앞면에 검은 사선 무늬)."""
    p = Part("Body")
    for sx in (-1, 1):
        p.cylinder(m["base"], sx * 2.0, 0, 0, 0.18, 0.05, segments=8)
        p.cylinder(m["post"], sx * 2.0, 0, 0.05, 0.04, 1.0, segments=6)
    # 띠는 기둥 앞면에 붙인다(정면 = 띠 쪽)
    p.box(m["tape"], -2.0, 2.0, 0.04, 0.05, 0.86, 0.94)
    for i in range(10):
        x = -1.8 + 0.4 * i
        p.hull(m["stripe"], [(x - 0.09 + dz, y, 0.86 + dz) for dz in (0.0, 0.08) for y in (0.05, 0.054)]
               + [(x - 0.03 + dz, y, 0.86 + dz) for dz in (0.0, 0.08) for y in (0.05, 0.054)])
    return [p.build(col)]


def make_money_bag(col, m):
    """돈 가방(자루): 앞면에 ₩."""
    p = Part("Body")
    money_bag(p, m, 0, 0, 0)
    return [p.build(col)]


# ---------------------------------------------------------------- 목록과 내보내기

# (id, 파일 이름, 표시 이름, 만드는 함수, 삼각형 상한, 종류, 정면 표시 머티리얼 부위)
FIGURES = [
    ("VENDOR", "vendor", "노점상", make_vendor, 600, "figure", "shoe"),
    ("TAXI", "taxi", "택시기사", make_taxi_driver, 600, "figure", "shoe"),
    ("DRONE", "drone", "드론 유튜버", make_drone_youtuber, 600, "figure", "shoe"),
    ("LOCAL", "local", "동네 토박이", make_local, 600, "figure", "shoe"),
    ("RIDER", "rider", "배달 라이더", make_rider, 600, "figure", "shoe"),
    ("GUARD", "guard", "경비원", make_guard, 600, "figure", "shoe"),
    ("COP", "cop", "순찰 경관", make_cop, 600, "figure", "shoe"),
    ("GOSSIP", "gossip", "오지랖 주민", make_gossip, 600, "figure", "shoe"),
    ("ANON", "anon", "익명 제보자", make_anon, 400, "figure", "face"),
    ("CULPRIT_RUN", "culprit_run", "달아나는 범인", make_culprit_run, 500, "figure", "mask"),
    ("CULPRIT_CUFFED", "culprit_cuffed", "수갑 찬 범인", make_culprit_cuffed, 500, "figure", "mask"),
    ("atm", "atm", "ATM 부스", make_atm, 300, "prop", "screen"),
    ("handcuffs", "handcuffs", "수갑", make_handcuffs, 300, "prop", None),
    ("police_tape", "police_tape", "폴리스 라인", make_police_tape, 300, "prop", "stripe"),
    ("money_bag", "money_bag", "돈 가방", make_money_bag, 300, "prop", "won"),
]


def settle(objs):
    """최저점을 높이 0에 맞추고, 가로·세로 가운데를 원점으로 옮긴다.

    원점에 있는 오브젝트(Body)는 메시를 옮기고, 축이 따로 있는 노드(다리, 드론)는 위치를 옮긴다.
    """
    lo, hi = bounds(objs)
    d = Vector((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    for o in objs:
        if o.location.length < 1e-9:
            o.data.transform(Matrix.Translation(d))
        else:
            o.location += d


def export(fid, stem, builder, max_tris, out_dir):
    col = reset_scene()
    m = materials(stem, {**BASE, **PALETTE[stem]})
    result = builder(col, m)
    objs = [result.body.build(col)] + result.legs if isinstance(result, Fig) else result
    settle(objs)
    tris = tri_count(objs)
    if tris > max_tris:
        raise SystemExit(f"{fid}: {tris} triangles > {max_tris}")
    export_glb(os.path.join(out_dir, f"{stem}.glb"))
    render_thumbnail(objs, os.path.join(out_dir, "thumbs", f"{stem}.png"))
    size = godot_size(objs)
    names = [o.name for o in objs]
    print(f"[make_figures] {fid}: {tris} tris, W x H x D {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m, nodes {names}")
    out = {"tris": tris, "size_m": size, "nodes": names}
    legs = {o.name: o for o in objs if o.name in ("LegL", "LegR")}
    # 다리를 곧게 세운 인물만 엉덩이 높이를 적는다(검사가 다리 길이를 확인한다)
    if legs and all(abs(o.rotation_euler.x) < 1e-6 for o in legs.values()):
        out["hip_m"] = round(legs["LegL"].location.z, 3)
    return out


def main():
    out_dir, only = cli_args(OUT_DIR)
    entries = {}
    for fid, stem, label, builder, max_tris, kind, front in FIGURES:
        entry = {"label": label, "kind": kind, "glb": f"{RES_DIR}/{stem}.glb", "thumb": f"{RES_DIR}/thumbs/{stem}.png",
                 "max_tris": max_tris, "anchor": "center", "front_material": f"{stem}_{front}" if front else None}
        if not only or fid in only or stem in only:
            entry.update(export(fid, stem, builder, max_tris, out_dir))
        entries[fid] = entry
    write_catalog(os.path.join(out_dir, "figures.json"), entries)


if __name__ == "__main__":
    main()
