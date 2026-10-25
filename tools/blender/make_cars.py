"""수사망 자율주행 패널용 로우폴리 차량 9종을 만들어 .glb, PNG 썸네일, 목록 JSON으로 내보낸다.

실행 (저장소 루트에서):
    blender --background --factory-startup --python tools/blender/make_cars.py

결과 (godot/assets/models/)
- <id>.glb, thumbs/<id>.png(256px 투명), vehicles.json(id, 파일, 크기, 삼각형, 노드)

규격
- 1 단위 = 1m, 원점 = 바닥 중앙(바퀴 아래면이 높이 0).
- Blender에서는 차 앞쪽을 +Y로 만든다. glTF(+Y up) 변환을 거치면 Godot에서 -Z가 된다.
- 텍스처 없이 무광 단색 머티리얼만 쓴다. 삼각형 수: 처음 4종은 2천 개, 추가 5종은 1,200개 이하.

노드 구성 (Godot에서 보이는 이름)
- 모든 모델: Body (차체, 창, 바퀴, 등을 하나로 합친 메시. 머티리얼은 여러 개)
- police_car: LightBarRed, LightBarBlue (경광등. 깜빡임 연출용으로 따로 둔다)
- taxi: TaxiSign (지붕 표시등)
"""

import os
import sys

import bmesh

sys.dont_write_bytecode = True  # tools/blender에 __pycache__를 남기지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (  # noqa: E402
    GODOT_ASSETS, Part, bounds, cli_args, cylinder_bm, export_glb, godot_size, hull_bm, materials,
    render_thumbnail, reset_scene, tri_count, write_catalog,
)

MODELS_DIR = os.path.join(GODOT_ASSETS, "models")
RES_DIR = "res://assets/models"


# ---------------------------------------------------------------- 색 (sRGB hex)

PALETTE = {
    "ego": {"body": "F4F5F7", "glass": "3E4756", "wheel": "2E3238", "head": "E6ECF3", "tail": "D9534F"},
    "sedan": {"body": "C9CED6", "glass": "6E7684", "wheel": "4A4F57", "head": "E2E6EB", "tail": "B8706E"},
    "suv": {"body": "BCC2CB", "glass": "666E7B", "wheel": "4A4F57", "head": "E2E6EB", "tail": "B8706E", "rail": "9AA1AB"},
    "police": {
        "body": "F7F8FA", "navy": "1E2B57", "glass": "3E4756", "wheel": "2E3238",
        "head": "E6ECF3", "tail": "D9534F", "bar": "D7DBE1", "red": "E8333A", "blue": "2563EB",
    },
    # 추가 5종: 회색 계열, 버스·택시만 은은한 색
    "bus": {"body": "EEF1F4", "accent": "8FB2D6", "glass": "5E6776", "door": "4B5566", "sign": "2E3238",
            "roof": "C9CED6", "wheel": "3A3F47", "head": "E2E6EB", "tail": "C76B67"},
    "taxi": {"body": "E3B572", "glass": "6E7684", "wheel": "4A4F57", "head": "E2E6EB", "tail": "B8706E",
             "sign": "F7F8FA"},
    "truck": {"body": "D6DBE2", "glass": "5E6776", "wheel": "3A3F47", "frame": "4A4F57", "deck": "B3BAC4",
              "gate": "C5CBD3", "head": "E2E6EB", "tail": "B8706E"},
    "compact": {"body": "C3C8D0", "glass": "6E7684", "wheel": "4A4F57", "head": "E2E6EB", "tail": "B8706E"},
    "scooter": {"body": "C9CED6", "seat": "3A3F47", "wheel": "2E3238", "box": "9FCFC8", "head": "E2E6EB",
                "tail": "C76B67", "jacket": "5B6472", "pants": "374151", "shoe": "2E3238", "skin": "E7C9A9",
                "helmet": "9FCFC8"},
}


# ---------------------------------------------------------------- 차 부품


def side_prism(part, mat, profile_yz, half_width, bevel=0.0, segments=2):
    """옆모습 다각형(y 앞, z 위)을 x 방향으로 밀어 차체를 만든다."""
    bm = bmesh.new()
    left = [bm.verts.new((-half_width, y, z)) for y, z in profile_yz]
    right = [bm.verts.new((half_width, y, z)) for y, z in profile_yz]
    bm.faces.new(left[::-1])
    bm.faces.new(right)
    n = len(profile_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left[i], left[j], right[j], right[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if bevel > 0:
        bmesh.ops.bevel(
            bm, geom=bm.edges[:], offset=bevel, offset_type="OFFSET",
            segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True,
        )
    part.add(bm, mat)


def cabin(part, mats, z0, z1, bottom, top, frame=0.05):
    """유리 띠가 있는 캐빈. bottom/top = (y_rear, y_front, half_width).

    옆·앞·뒤 경사면은 유리(테두리는 차체색), 윗면은 지붕(차체색)이다.
    """
    (by0, by1, bw), (ty0, ty1, tw) = bottom, top
    bm = hull_bm([(x, y, z0) for x in (-bw, bw) for y in (by0, by1)] + [(x, y, z1) for x in (-tw, tw) for y in (ty0, ty1)])
    top_faces = [f for f in bm.faces if f.normal.z > 0.99]
    bottom_faces = [f for f in bm.faces if f.normal.z < -0.99]
    bmesh.ops.delete(bm, geom=bottom_faces, context="FACES_ONLY")
    glass = [f for f in bm.faces if f not in top_faces]
    body_i, glass_i = 0, 1
    for f in bm.faces:
        f.material_index = body_i
    for f in glass:
        f.material_index = glass_i
    rim = bmesh.ops.inset_individual(bm, faces=glass, thickness=frame, depth=-0.012)["faces"]
    for f in rim:
        f.material_index = body_i
    part.add(bm, mats)


def wheel(part, mat, x, y, radius, width, verts=14):
    bm = cylinder_bm(radius, width, verts, axis="X")
    # 다각형 바퀴의 가장 낮은 점이 바닥(높이 0)에 닿게 올린다.
    bmesh.ops.translate(bm, vec=(x, y, -min(v.co.z for v in bm.verts)), verts=bm.verts[:])
    part.add(bm, mat)


# ---------------------------------------------------------------- 공통 차 골격


def car(part, m, length, width, profile, cabin_args, wheel_r, wheelbase, lamp_z, tail_z, mirror_y, mirror_z):
    """차체 + 캐빈 + 바퀴 4개 + 앞뒤 등 + 사이드미러."""
    hl, hw = length / 2, width / 2
    side_prism(part, m["body"], profile, hw, bevel=0.07)
    cabin(part, [m["body"], m["glass"]], **cabin_args)
    track = hw - 0.13 + 0.025
    for sx in (-1, 1):
        for sy in (-1, 1):
            wheel(part, m["wheel"], sx * track, sy * wheelbase / 2, wheel_r, 0.25)
    for sx in (-1, 1):
        # 앞 등(밝은 회색), 뒤 등(붉은색). 차체 앞뒤 면에 살짝 붙어 나온다.
        part.box(m["head"], sx * (hw - 0.42), sx * (hw - 0.10), hl - 0.03, hl + 0.012, lamp_z - 0.05, lamp_z + 0.04)
        part.box(m["tail"], sx * (hw - 0.40), sx * (hw - 0.08), -hl - 0.012, -hl + 0.03, tail_z - 0.05, tail_z + 0.05)
        # 사이드미러
        part.box(m["body"], sx * (hw - 0.05), sx * (hw + 0.13), mirror_y - 0.08, mirror_y + 0.04, mirror_z, mirror_z + 0.11)


def make_ego(col):
    """내 차: 흰색 박스형 크로스오버/MPV. 짧은 보닛, 높은 지붕."""
    m = mats_for("ego")
    p = Part("Body")
    L, W = 4.70, 1.90
    hl = L / 2
    profile = [(-hl, 0.32), (hl, 0.32), (hl, 0.74), (hl - 0.16, 0.96), (1.25, 1.06), (-hl, 1.08)]
    cabin = dict(z0=1.02, z1=1.74, bottom=(-hl + 0.04, 1.30, 0.90), top=(-hl + 0.16, 0.20, 0.79))
    car(p, m, L, W, profile, cabin, wheel_r=0.37, wheelbase=2.90, lamp_z=0.60, tail_z=0.94, mirror_y=1.12, mirror_z=1.02)
    return [p.build(col)]


def make_sedan(col):
    """주변 차 1: 밝은 회색 세단."""
    m = mats_for("sedan")
    p = Part("Body")
    L, W = 4.65, 1.82
    hl = L / 2
    profile = [(-hl, 0.30), (hl, 0.30), (hl, 0.62), (hl - 0.14, 0.80), (0.95, 0.90), (-1.45, 0.95), (-hl, 0.92)]
    cabin = dict(z0=0.88, z1=1.44, bottom=(-1.48, 1.00, 0.86), top=(-0.98, 0.08, 0.72))
    car(p, m, L, W, profile, cabin, wheel_r=0.33, wheelbase=2.80, lamp_z=0.50, tail_z=0.78, mirror_y=0.98, mirror_z=0.88)
    return [p.build(col)]


def make_suv(col):
    """주변 차 2: 밝은 회색 SUV. 긴 보닛과 루프레일."""
    m = mats_for("suv")
    p = Part("Body")
    L, W = 4.75, 1.92
    hl = L / 2
    profile = [(-hl, 0.36), (hl, 0.36), (hl, 0.80), (hl - 0.18, 1.02), (0.95, 1.10), (-hl, 1.12)]
    cabin = dict(z0=1.06, z1=1.72, bottom=(-hl + 0.05, 1.00, 0.90), top=(-hl + 0.28, 0.02, 0.80))
    car(p, m, L, W, profile, cabin, wheel_r=0.38, wheelbase=2.85, lamp_z=0.66, tail_z=0.98, mirror_y=0.95, mirror_z=1.06)
    for sx in (-1, 1):
        p.box(m["rail"], sx * 0.62, sx * 0.70, -hl + 0.40, -0.05, 1.72, 1.78)
    return [p.build(col)]


def make_police(col):
    """경찰차: 흰 세단 + 남색 아랫단 + 지붕 경광등(빨강·파랑 메시 분리)."""
    m = mats_for("police")
    p = Part("Body")
    L, W = 4.85, 1.86
    hl = L / 2
    profile = [(-hl, 0.30), (hl, 0.30), (hl, 0.62), (hl - 0.14, 0.80), (1.00, 0.91), (-1.50, 0.96), (-hl, 0.93)]
    cabin = dict(z0=0.89, z1=1.45, bottom=(-1.53, 1.05, 0.88), top=(-1.02, 0.10, 0.74))
    car(p, m, L, W, profile, cabin, wheel_r=0.34, wheelbase=2.85, lamp_z=0.50, tail_z=0.80, mirror_y=1.03, mirror_z=0.89)
    # 차체 아랫단(높이 0.62 아래)을 남색으로 칠한다. 경계에서 면을 잘라 색을 나눈다.
    bm = p.bm
    navy_i = p.slot(m["navy"])
    body_i = p.materials.index(m["body"])
    cut = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0.62), plane_no=(0, 0, 1))
    del cut
    for f in bm.faces:
        if f.material_index == body_i and f.calc_center_median().z < 0.62 and abs(f.normal.z) < 0.9:
            f.material_index = navy_i
    # 경광등 받침(차체에 합침)
    p.box(m["bar"], -0.58, 0.58, -0.42, -0.18, 1.44, 1.50)
    body = p.build(col)

    red = Part("LightBarRed")
    red.box(m["red"], -0.55, -0.02, -0.40, -0.20, 1.50, 1.61)
    blue = Part("LightBarBlue")
    blue.box(m["blue"], 0.02, 0.55, -0.40, -0.20, 1.50, 1.61)
    return [body, red.build(col), blue.build(col)]


def make_taxi(col):
    """택시: 세단 차체에 은은한 황토색, 지붕 표시등(TaxiSign 노드)."""
    m = mats_for("taxi")
    p = Part("Body")
    L, W = 4.70, 1.82
    hl = L / 2
    profile = [(-hl, 0.30), (hl, 0.30), (hl, 0.62), (hl - 0.14, 0.80), (0.95, 0.90), (-1.45, 0.95), (-hl, 0.92)]
    cabin = dict(z0=0.88, z1=1.44, bottom=(-1.48, 1.00, 0.86), top=(-0.98, 0.08, 0.72))
    car(p, m, L, W, profile, cabin, wheel_r=0.33, wheelbase=2.80, lamp_z=0.50, tail_z=0.78, mirror_y=0.98, mirror_z=0.88)
    body = p.build(col)
    sign = Part("TaxiSign")
    sign.hull(m["sign"], [(x, y, 1.44) for x in (-0.36, 0.36) for y in (-0.64, -0.36)]
              + [(x, y, 1.66) for x in (-0.30, 0.30) for y in (-0.60, -0.40)])
    return [body, sign.build(col)]


def make_compact(col):
    """경차(해치백): 짧은 보닛, 높은 지붕, 수직에 가까운 뒷면."""
    m = mats_for("compact")
    p = Part("Body")
    L, W = 3.60, 1.60
    hl = L / 2
    profile = [(-hl, 0.28), (hl, 0.28), (hl, 0.62), (hl - 0.14, 0.80), (1.00, 0.90), (-hl, 0.96)]
    cabin = dict(z0=0.88, z1=1.52, bottom=(-hl + 0.04, 1.10, 0.76), top=(-hl + 0.12, 0.25, 0.66))
    car(p, m, L, W, profile, cabin, wheel_r=0.29, wheelbase=2.40, lamp_z=0.52, tail_z=0.82, mirror_y=1.02, mirror_z=0.88)
    return [p.build(col)]


def make_truck(col):
    """1톤 트럭: 앞쪽 캡오버 운전석, 뒤쪽 낮은 짐칸(옆판 3면과 앞 가림판)."""
    m = mats_for("truck")
    p = Part("Body")
    L, W = 5.10, 1.74
    hl, hw = L / 2, W / 2
    p.box(m["frame"], -0.62, 0.62, -hl + 0.1, hl - 0.3, 0.38, 0.62)
    # 운전석: 앞이 거의 수직이고 위로 갈수록 살짝 뒤로 눕는다
    cab_y = 0.95
    side_prism(p, m["body"], [(cab_y, 0.45), (hl, 0.45), (hl, 1.15), (hl - 0.2, 1.95), (cab_y, 1.98)], hw, bevel=0.06)
    # 앞유리: 비스듬한 앞면을 따라 붙인 얇은 판
    n = (0.97, 0.243)
    face = [(hl - 0.2 * t, 1.15 + 0.8 * t) for t in (0.12, 0.92)]
    p.hull(m["glass"], [(x, y + n[0] * d, z + n[1] * d) for x in (-0.72, 0.72) for y, z in face for d in (-0.01, 0.025)])
    for sx in (-1, 1):
        p.box(m["glass"], sx * (hw - 0.02), sx * (hw + 0.02), 1.35, hl - 0.4, 1.2, 1.75)
        p.box(m["body"], sx * hw, sx * (hw + 0.16), hl - 0.38, hl - 0.26, 1.25, 1.55)
    # 짐칸: 바닥, 옆판, 뒤판, 앞 가림판
    p.box(m["deck"], -hw, hw, -hl, 0.9, 0.72, 0.84)
    for sx in (-1, 1):
        p.box(m["gate"], sx * (hw - 0.05), sx * hw, -hl, 0.9, 0.84, 1.28)
    p.box(m["gate"], -hw, hw, -hl, -hl + 0.05, 0.84, 1.28)
    p.box(m["gate"], -hw, hw, 0.85, 0.92, 0.84, 1.75)
    p.box(m["frame"], -hw, hw, -hl, -hl + 0.12, 0.48, 0.62)
    for sy, r in ((1.70, 0.31), (-1.25, 0.31)):
        for sx in (-1, 1):
            wheel(p, m["wheel"], sx * (hw - 0.13 + 0.025), sy, r, 0.24)
    for sx in (-1, 1):
        p.box(m["head"], sx * (hw - 0.42), sx * (hw - 0.10), hl - 0.03, hl + 0.012, 0.60, 0.72)
        p.box(m["tail"], sx * (hw - 0.40), sx * (hw - 0.08), -hl - 0.012, -hl + 0.03, 0.50, 0.60)
    return [p.build(col)]


def make_bus(col):
    """시내버스: 둥근 상자 차체, 옆 유리 띠, 아랫단 은은한 파랑, 오른쪽 앞·가운데 문, 지붕 냉방기."""
    m = mats_for("bus")
    p = Part("Body")
    L, W, H = 11.0, 2.5, 3.1
    hl, hw = L / 2, W / 2
    side_prism(p, m["body"], [(-hl, 0.32), (hl, 0.32), (hl, H), (-hl, H)], hw, bevel=0.15)
    # 아랫단(높이 1.05 아래)을 은은한 파랑으로
    bm = p.bm
    accent_i = p.slot(m["accent"])
    body_i = p.materials.index(m["body"])
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 1.05), plane_no=(0, 0, 1))
    for f in bm.faces:
        if f.material_index == body_i and f.calc_center_median().z < 1.05 and abs(f.normal.z) < 0.9:
            f.material_index = accent_i
    # 옆 유리 띠와 기둥
    for sx in (-1, 1):
        p.box(m["glass"], sx * (hw - 0.02), sx * (hw + 0.02), -hl + 0.5, hl - 0.9, 1.30, 2.65)
        for y in (-4.0, -2.5, -1.0, 2.0, 3.5):
            p.box(m["body"], sx * (hw - 0.01), sx * (hw + 0.04), y - 0.07, y + 0.07, 1.30, 2.65)
        p.box(m["body"], sx * hw, sx * (hw + 0.2), hl - 0.3, hl - 0.15, 1.9, 2.4)
    # 오른쪽(+X) 문: 앞문, 가운데 문
    for y0, y1 in ((hl - 1.25, hl - 0.35), (-0.2, 1.0)):
        p.box(m["door"], hw - 0.02, hw + 0.05, y0, y1, 0.40, 2.65)
    # 앞유리, 행선지 표시, 뒤유리, 지붕 냉방기
    p.box(m["glass"], -hw + 0.2, hw - 0.2, hl - 0.02, hl + 0.02, 1.0, 2.55)
    p.box(m["sign"], -hw + 0.3, hw - 0.3, hl - 0.02, hl + 0.03, 2.62, 2.9)
    p.box(m["glass"], -0.85, 0.85, -hl - 0.02, -hl + 0.02, 2.0, 2.75)
    p.box(m["roof"], -0.85, 0.85, -1.6, 1.2, H, H + 0.25)
    for sy in (hl - 2.2, -hl + 3.0):
        for sx in (-1, 1):
            wheel(p, m["wheel"], sx * (hw - 0.13), sy, 0.5, 0.3)
    for sx in (-1, 1):
        p.box(m["head"], sx * (hw - 0.5), sx * (hw - 0.15), hl - 0.03, hl + 0.012, 0.55, 0.75)
        p.box(m["tail"], sx * (hw - 0.45), sx * (hw - 0.15), -hl - 0.012, -hl + 0.03, 0.60, 0.90)
    return [p.build(col)]


def make_scooter(col):
    """배달 오토바이 + 탄 사람: 스쿠터 차체, 뒤 배달 상자, 헬멧 쓴 운전자."""
    m = mats_for("scooter")
    p = Part("Body")
    for y in (0.66, -0.62):
        wheel(p, m["wheel"], 0, y, 0.27, 0.12)
    # 차체: 앞 가림판, 발판, 시트 아래 몸통, 시트, 핸들
    p.hull(m["body"], [(x, y, z) for x in (-0.2, 0.2) for y, z in ((0.33, 0.35), (0.50, 0.35))]
           + [(x, y, 1.0) for x in (-0.17, 0.17) for y in (0.44, 0.58)])
    p.box(m["body"], -0.17, 0.17, -0.15, 0.38, 0.30, 0.40)
    p.hull(m["body"], [(x, y, z) for x in (-0.2, 0.2) for y, z in ((-0.15, 0.32), (-0.85, 0.42))]
           + [(x, y, z) for x in (-0.17, 0.17) for y, z in ((-0.1, 0.70), (-0.8, 0.75))])
    p.box(m["seat"], -0.15, 0.15, -0.75, -0.1, 0.75, 0.84)
    p.box(m["seat"], -0.04, 0.04, 0.46, 0.54, 0.95, 1.04)
    p.box(m["seat"], -0.36, 0.36, 0.50, 0.56, 1.02, 1.07)
    p.box(m["head"], -0.08, 0.08, 0.57, 0.62, 0.85, 0.95)
    p.box(m["tail"], -0.08, 0.08, -0.88, -0.84, 0.60, 0.68)
    # 배달 상자
    p.box(m["seat"], -0.2, 0.2, -0.9, -0.55, 0.80, 0.84)
    p.box(m["box"], -0.24, 0.24, -0.93, -0.50, 0.84, 1.26)
    # 운전자: 다리, 몸통, 팔, 머리와 헬멧
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.07, sx * 0.21))
        p.box(m["pants"], x0, x1, -0.40, 0.15, 0.80, 0.95)
        p.box(m["pants"], x0, x1, 0.08, 0.22, 0.46, 0.92)
        p.box(m["shoe"], x0, x1, 0.05, 0.30, 0.40, 0.48)
        p.hull(m["jacket"], [(sx * 0.21 + dx, -0.25 + dy, 1.34 + dz) for dx in (-0.07, 0.07) for dy in (-0.07, 0.07)
                             for dz in (-0.07, 0.07)]
               + [(sx * 0.30 + dx, 0.47 + dy, 1.07 + dz) for dx in (-0.05, 0.05) for dy in (-0.05, 0.05)
                  for dz in (-0.05, 0.05)])
    p.hull(m["jacket"], [(x, y, 0.86) for x in (-0.19, 0.19) for y in (-0.56, -0.30)]
           + [(x, y, 1.42) for x in (-0.23, 0.23) for y in (-0.40, -0.14)])
    p.box(m["skin"], -0.05, 0.05, -0.32, -0.22, 1.42, 1.50)
    p.sphere(m["helmet"], 0, -0.26, 1.60, 0.15, subdivisions=2, squash=0.95)
    p.box(m["seat"], -0.11, 0.11, -0.13, -0.10, 1.56, 1.64)
    return [p.build(col)]


def mats_for(key):
    return materials(key, PALETTE[key])


# (id, 표시 이름, 색 키, 만드는 함수, 삼각형 상한, 노드)
VEHICLES = [
    ("ego_car", "내 차", "ego", make_ego, 2000, ["Body"]),
    ("traffic_sedan", "세단", "sedan", make_sedan, 2000, ["Body"]),
    ("traffic_suv", "SUV", "suv", make_suv, 2000, ["Body"]),
    ("police_car", "경찰차", "police", make_police, 2000, ["Body", "LightBarRed", "LightBarBlue"]),
    ("bus", "시내버스", "bus", make_bus, 1200, ["Body"]),
    ("taxi", "택시", "taxi", make_taxi, 1200, ["Body", "TaxiSign"]),
    ("truck", "1톤 트럭", "truck", make_truck, 1200, ["Body"]),
    ("compact", "경차", "compact", make_compact, 1200, ["Body"]),
    ("scooter", "배달 오토바이", "scooter", make_scooter, 1200, ["Body"]),
]


def export(name, builder, max_tris, out_dir):
    objs = builder(reset_scene())
    tris = tri_count(objs)
    if tris > max_tris:
        raise SystemExit(f"{name}: {tris} triangles > {max_tris}")
    path = os.path.join(out_dir, f"{name}.glb")
    export_glb(path)
    render_thumbnail(objs, os.path.join(out_dir, "thumbs", f"{name}.png"))
    lo, hi = bounds(objs)
    print(
        f"[make_cars] {name}: {tris} tris, size {hi[0] - lo[0]:.2f} x {hi[1] - lo[1]:.2f} x {hi[2] - lo[2]:.2f} m "
        f"(W x L x H), z_min {lo[2]:.3f}, nodes {[o.name for o in objs]} -> {path}"
    )
    return {"tris": tris, "size_m": godot_size(objs)}


def main():
    out_dir, only = cli_args(MODELS_DIR)
    entries = {}
    for name, label, key, builder, max_tris, nodes in VEHICLES:
        entry = {"label": label, "glb": f"{RES_DIR}/{name}.glb", "thumb": f"{RES_DIR}/thumbs/{name}.png",
                 "max_tris": max_tris, "nodes": nodes, "anchor": "center", "front_material": f"{key}_head"}
        if not only or name in only:
            entry.update(export(name, builder, max_tris, out_dir))
        entries[name] = entry
    write_catalog(os.path.join(out_dir, "vehicles.json"), entries)


if __name__ == "__main__":
    main()
