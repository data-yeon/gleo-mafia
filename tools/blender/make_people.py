"""주행 화면 횡단보도용 로우폴리 보행자 4종을 만들어 .glb, PNG 썸네일, 목록 JSON으로 내보낸다.

실행 (저장소 루트에서):
    blender --background --factory-startup --python tools/blender/make_people.py

결과 (godot/assets/models/people/)
- <id>.glb, thumbs/<id>.png(256px 투명), people.json(id, 파일, 크기, 삼각형, 노드, 엉덩이 높이)

규격
- 1 단위 = 1m, 원점 = 바닥 중앙, 정면(얼굴·발끝) = Godot -Z(Blender +Y).
- 노드: Body(몸통, 팔, 머리, 소지품), LegL, LegR. 다리 노드의 원점은 엉덩이 높이(hip_m)에 있어서
  Godot에서 rotation.x를 앞뒤로 흔들면 걷는 것처럼 보인다. 왼쪽 다리(LegL)는 사람 기준 왼쪽(-X)이다.
- 텍스처 없이 무광 단색. 삼각형은 모델당 MAX_TRIS 이하.
"""

import os
import sys

sys.dont_write_bytecode = True  # tools/blender에 __pycache__를 남기지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (  # noqa: E402
    GODOT_ASSETS, Part, cli_args, export_glb, godot_size, materials, render_thumbnail, reset_scene, tri_count,
    write_catalog,
)

OUT_DIR = os.path.join(GODOT_ASSETS, "models", "people")
RES_DIR = "res://assets/models/people"
MAX_TRIS = 400
HIP = 0.90                         # 어른 엉덩이(다리 회전축) 높이(m)


# ---------------------------------------------------------------- 색 (sRGB hex)

BASE = {"skin": "E7C9A9", "hair": "3F3A36", "shoe": "2E3238"}
PALETTE = {
    "ped_suit": {"top": "4B5563", "pants": "374151", "shirt": "F3F4F6", "tie": "3B5B8C", "bag": "5B4636"},
    "ped_casual": {"top": "8FB3D9", "pants": "C8B79E", "shoe": "F3F4F6", "bag": "6B7280"},
    "ped_kid": {"top": "F2C14E", "pants": "5B7DB1", "bag": "E07A5F", "hair": "4A3F35"},
    "ped_umbrella": {"top": "A3B1C2", "pants": "4B5563", "umbrella": "7FA6C9", "stick": "3A3F47"},
}


# ---------------------------------------------------------------- 사람 골격


def stick(p, mat, a, b, r):
    """두 점 a, b를 잇는 굵기 2r의 막대(볼록 껍질)."""
    p.hull(mat, [(c[0] + dx, c[1] + dy, c[2] + dz) for c in (a, b) for dx in (-r, r) for dy in (-r, r) for dz in (-r, r)])


def person(col, m, s=1.0, head_r=0.105, raise_right=False):
    """서 있는 사람. s는 키 비율(어른 1.0 ≈ 1.72m). 돌려주는 값: (Body Part, [LegL, LegR] 오브젝트, 엉덩이 높이)."""
    hip = HIP * s
    legs = []
    for name, sx in (("LegL", -1), ("LegR", 1)):
        leg = Part(name)
        x = sx * 0.095 * s
        leg.box(m["pants"], x - 0.068 * s, x + 0.068 * s, -0.075 * s, 0.075 * s, 0.07 * s, hip)
        leg.box(m["shoe"], x - 0.07 * s, x + 0.07 * s, -0.08 * s, 0.15 * s, 0, 0.08 * s)
        legs.append(leg.build(col, origin=(x, 0, hip)))
    body = Part("Body")
    sh = 1.42 * s                                   # 어깨 높이
    body.hull(m["top"], [(x, y, hip - 0.06 * s) for x in (-0.17 * s, 0.17 * s) for y in (-0.10 * s, 0.10 * s)]
              + [(x, y, sh) for x in (-0.21 * s, 0.21 * s) for y in (-0.11 * s, 0.11 * s)])
    body.box(m["skin"], -0.045 * s, 0.045 * s, -0.045 * s, 0.045 * s, sh, sh + 0.09 * s)
    hz = sh + 0.09 * s + head_r * 0.9
    body.sphere(m["skin"], 0, 0, hz, head_r, subdivisions=2)
    body.sphere(m["hair"], 0, -0.03 * s, hz + 0.035 * s, head_r * 1.06, subdivisions=2, squash=0.78)
    for sx in (-1, 1):
        x = sx * 0.255 * s
        if sx > 0 and raise_right:
            # 오른팔을 굽혀 가슴 앞으로 든다(우산 손잡이)
            stick(body, m["top"], (x, 0, sh - 0.04 * s), (x, 0.02 * s, sh - 0.30 * s), 0.045 * s)
            stick(body, m["top"], (x, 0.02 * s, sh - 0.30 * s), (0.10 * s, 0.22 * s, sh - 0.14 * s), 0.04 * s)
            body.box(m["skin"], 0.06 * s, 0.14 * s, 0.20 * s, 0.28 * s, sh - 0.18 * s, sh - 0.10 * s)
        else:
            body.box(m["top"], x - 0.045 * s, x + 0.045 * s, -0.055 * s, 0.055 * s, 0.86 * s, sh - 0.02 * s)
            body.box(m["skin"], x - 0.04 * s, x + 0.04 * s, -0.045 * s, 0.045 * s, 0.78 * s, 0.86 * s)
    return body, legs, hip, sh


def make_suit(col, m):
    """정장: 짙은 회색 정장, 흰 셔츠와 넥타이, 오른손 서류 가방."""
    body, legs, hip, sh = person(col, m)
    body.box(m["shirt"], -0.06, 0.06, 0.09, 0.115, sh - 0.24, sh)
    body.box(m["tie"], -0.02, 0.02, 0.11, 0.125, sh - 0.22, sh - 0.02)
    body.box(m["bag"], 0.235, 0.29, -0.16, 0.16, 0.52, 0.78)
    return body, legs, hip


def make_casual(col, m):
    """캐주얼: 하늘색 후드, 베이지 바지, 흰 운동화, 등 뒤 배낭."""
    body, legs, hip, sh = person(col, m)
    body.box(m["bag"], -0.15, 0.15, -0.22, -0.10, 1.00, 1.38)
    return body, legs, hip


def make_kid(col, m):
    """아이: 키 약 1.2m, 노란 윗옷, 청바지, 주황 책가방."""
    body, legs, hip, sh = person(col, m, s=0.68, head_r=0.095)
    body.box(m["bag"], -0.13, 0.13, -0.17, -0.07, 0.62, 0.90)
    return body, legs, hip


def make_umbrella(col, m):
    """우산 든 사람: 회색 비옷, 오른손으로 든 파란 우산(머리 위 가운데)."""
    body, legs, hip, sh = person(col, m, raise_right=True)
    top = 1.98
    stick(body, m["stick"], (0.10, 0.24, sh - 0.14), (0.0, 0.02, top + 0.2), 0.015)
    body.hull(m["umbrella"], [(0.55 * x, 0.02 + 0.55 * y, top) for x, y in
                              ((1, 0), (0.81, 0.59), (0.31, 0.95), (-0.31, 0.95), (-0.81, 0.59),
                               (-1, 0), (-0.81, -0.59), (-0.31, -0.95), (0.31, -0.95), (0.81, -0.59))]
              + [(0, 0.02, top + 0.26)])
    return body, legs, hip


# (id, 표시 이름, 만드는 함수)
PEOPLE = [
    ("ped_suit", "정장", make_suit),
    ("ped_casual", "캐주얼", make_casual),
    ("ped_kid", "아이", make_kid),
    ("ped_umbrella", "우산 든 사람", make_umbrella),
]


def export(pid, builder, out_dir):
    col = reset_scene()
    body, legs, hip = builder(col, materials(pid, {**BASE, **PALETTE[pid]}))
    objs = [body.build(col)] + legs
    tris = tri_count(objs)
    if tris > MAX_TRIS:
        raise SystemExit(f"{pid}: {tris} triangles > {MAX_TRIS}")
    export_glb(os.path.join(out_dir, f"{pid}.glb"))
    render_thumbnail(objs, os.path.join(out_dir, "thumbs", f"{pid}.png"))
    size = godot_size(objs)
    print(f"[make_people] {pid}: {tris} tris, W x H x D {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m, hip {hip:.2f}")
    return {"tris": tris, "size_m": size, "hip_m": round(hip, 3)}


def main():
    out_dir, only = cli_args(OUT_DIR)
    entries = {}
    for pid, label, builder in PEOPLE:
        entry = {"label": label, "glb": f"{RES_DIR}/{pid}.glb", "thumb": f"{RES_DIR}/thumbs/{pid}.png",
                 "max_tris": MAX_TRIS, "nodes": ["Body", "LegL", "LegR"], "anchor": "center",
                 "front_material": f"{pid}_shoe"}
        if not only or pid in only:
            entry.update(export(pid, builder, out_dir))
        entries[pid] = entry
    write_catalog(os.path.join(out_dir, "people.json"), entries)


if __name__ == "__main__":
    main()
