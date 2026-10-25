"""주행 화면용 길거리 소품(가로수 2종, 가로등, 신호등 2종, 버스 정류장)을 .glb, PNG 썸네일, 목록 JSON으로 내보낸다.

실행 (저장소 루트에서):
    blender --background --factory-startup --python tools/blender/make_props.py

결과 (godot/assets/models/props/)
- <id>.glb, thumbs/<id>.png(256px 투명), props.json(id, 파일, 크기, 삼각형, 노드, 원점 기준)

규격
- 1 단위 = 1m, 정면 = Godot -Z(Blender +Y). 텍스처 없이 무광 단색.
- 원점(anchor): "center"는 바닥 중앙, "pole"은 기둥 바닥 중앙이다.
  가로등과 차량 신호등은 기둥에서 팔이 +X로 뻗는다. 도로 오른쪽 가장자리에 세울 때 y축으로 180° 돌리면
  팔이 도로 위(-X)로 뻗고 램프 면이 다가오는 차(+Z)를 본다.
- 가로수는 MultiMesh로 쓸 수 있게 메시 하나(Body)로 만든다.
- 신호등 램프는 따로 노드다: 차량용 LampRed, LampYellow, LampGreen / 보행용 LampRed, LampGreen.
  켜고 끄기는 Godot에서 머티리얼 발광(emission)으로 한다.
"""

import math
import os
import sys

sys.dont_write_bytecode = True  # tools/blender에 __pycache__를 남기지 않는다
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (  # noqa: E402
    GODOT_ASSETS, Part, cli_args, export_glb, godot_size, materials, render_thumbnail, reset_scene, tri_count,
    write_catalog,
)

OUT_DIR = os.path.join(GODOT_ASSETS, "models", "props")
RES_DIR = "res://assets/models/props"


# ---------------------------------------------------------------- 색 (sRGB hex)

PALETTE = {
    "tree_round": {"leaf": "A8D5A0", "leaf2": "94C98B", "trunk": "B49A7E"},
    "tree_cone": {"leaf": "9CCFA2", "leaf2": "88C291", "trunk": "B49A7E"},
    "street_light": {"pole": "B8BFC8", "head": "D6DBE2", "lamp": "FFF3D1"},
    "traffic_light_car": {"pole": "9AA1AB", "housing": "2E3238", "red": "EF4444", "yellow": "F59E0B",
                          "green": "22C55E"},
    "traffic_light_ped": {"pole": "9AA1AB", "housing": "2E3238", "red": "EF4444", "green": "22C55E"},
    "bus_stop": {"floor": "D6DBE2", "front": "F2C14E", "glass": "A9C3D9", "frame": "9AA1AB", "roof": "C9CED6",
                 "bench": "A9B0BA", "sign": "8FB2D6"},
}


# ---------------------------------------------------------------- 소품


def make_tree_round(col, m):
    """둥근 활엽수: 가는 줄기 + 큰 잎 덩어리 + 위쪽 작은 잎 덩어리. 높이 약 5.4m."""
    p = Part("Body")
    p.cylinder(m["trunk"], 0, 0, 0, 0.16, 2.4, segments=6, radius_top=0.12)
    p.sphere(m["leaf"], 0, 0, 3.4, 1.5, subdivisions=2, squash=0.9)
    p.sphere(m["leaf2"], 0, 0, 4.45, 0.95, subdivisions=2)
    return [p.build(col)]


def make_tree_cone(col, m):
    """원뿔 침엽수: 줄기 + 원뿔 2단. 높이 약 4.4m."""
    p = Part("Body")
    p.cylinder(m["trunk"], 0, 0, 0, 0.14, 1.2, segments=6)
    p.cone(m["leaf"], 0, 0, 0.9, 1.25, 2.6, segments=10)
    p.cone(m["leaf2"], 0, 0, 2.3, 0.9, 2.1, segments=10)
    return [p.build(col)]


def make_street_light(col, m):
    """가로등: 기둥 + 도로 쪽(+X)으로 뻗은 팔 + 납작한 등기구(아랫면이 램프). 높이 약 8.2m."""
    p = Part("Body")
    p.cylinder(m["pole"], 0, 0, 0, 0.2, 0.6, segments=8)
    p.cylinder(m["pole"], 0, 0, 0.6, 0.1, 7.4, segments=8, radius_top=0.07)
    p.hull(m["pole"], [(x, y, z) for x, zc in ((0.0, 7.85), (1.7, 8.1)) for y in (-0.05, 0.05)
                       for z in (zc - 0.05, zc + 0.05)])
    p.box(m["head"], 1.45, 2.25, -0.17, 0.17, 7.98, 8.18)
    p.box(m["lamp"], 1.52, 2.18, -0.12, 0.12, 7.95, 7.98)
    return [p.build(col)]


def make_traffic_light_car(col, m):
    """차량 신호등(가로형): 기둥 + 도로 위로 뻗은 팔 + 가로 신호기. 램프(빨강·노랑·초록)는 따로 노드.

    다가오는 차에서 보면 왼쪽(팔 끝)부터 빨강, 노랑, 초록이다(한국 가로형 3색).
    """
    p = Part("Body")
    p.cylinder(m["pole"], 0, 0, 0, 0.25, 0.4, segments=10)
    p.cylinder(m["pole"], 0, 0, 0.4, 0.13, 5.8, segments=10, radius_top=0.11)
    p.box(m["pole"], 0, 5.4, -0.07, 0.07, 5.75, 5.9)
    p.box(m["housing"], 3.55, 5.25, -0.14, 0.14, 5.25, 5.75)
    objs = [p.build(col)]
    for name, key, x in (("LampRed", "red", 4.95), ("LampYellow", "yellow", 4.40), ("LampGreen", "green", 3.85)):
        lamp = Part(name)
        lamp.disc(m[key], x, 0.16, 5.5, 0.17, 0.04, "Y", segments=12)
        objs.append(lamp.build(col))
    return objs


def make_traffic_light_ped(col, m):
    """보행 신호등: 기둥 + 신호기. 위가 빨강(서 있는 사람), 아래가 초록(걷는 사람). 램프는 따로 노드."""
    p = Part("Body")
    p.cylinder(m["pole"], 0, 0, 0, 0.16, 0.3, segments=8)
    p.cylinder(m["pole"], 0, 0, 0.3, 0.07, 1.75, segments=8)
    p.box(m["housing"], -0.18, 0.18, -0.10, 0.12, 2.0, 2.75)
    objs = [p.build(col)]
    for name, key, z0 in (("LampRed", "red", 2.42), ("LampGreen", "green", 2.08)):
        lamp = Part(name)
        lamp.box(m[key], -0.12, 0.12, 0.12, 0.15, z0, z0 + 0.24)
        objs.append(lamp.build(col))
    return objs


def make_bus_stop(col, m):
    """버스 정류장: 바닥(앞쪽 노란 점자 블록), 뒤·옆 유리, 지붕, 의자, 노선 안내판. 열린 쪽이 정면."""
    p = Part("Body")
    p.box(m["floor"], -2.1, 2.1, -0.8, 0.8, 0, 0.1)
    p.box(m["front"], -2.1, 2.1, 0.55, 0.8, 0.1, 0.11)
    p.box(m["glass"], -1.95, 1.95, -0.78, -0.72, 0.1, 2.3)
    p.box(m["glass"], 1.92, 1.98, -0.75, 0.2, 0.1, 2.3)
    for x in (-2.0, 2.0):
        for y in (-0.75, 0.45):
            p.box(m["frame"], x - 0.05, x + 0.05, y - 0.05, y + 0.05, 0.1, 2.32)
    p.hull(m["roof"], [(x, y, z) for x in (-2.2, 2.2) for y, z in ((-0.95, 2.3), (0.95, 2.3), (-0.95, 2.48), (0.95, 2.42))])
    p.box(m["bench"], -1.2, 1.2, -0.62, -0.25, 0.1, 0.5)
    p.box(m["sign"], -1.98, -1.92, -0.6, 0.4, 1.0, 2.2)
    return [p.build(col)]


# (id, 표시 이름, 만드는 함수, 삼각형 상한, 노드, 원점 기준, 정면 표시 머티리얼 부위)
PROPS = [
    ("tree_round", "가로수(둥근 활엽수)", make_tree_round, 400, ["Body"], "center", None),
    ("tree_cone", "가로수(원뿔 침엽수)", make_tree_cone, 400, ["Body"], "center", None),
    ("street_light", "가로등", make_street_light, 600, ["Body"], "pole", None),
    ("traffic_light_car", "차량 신호등(가로형)", make_traffic_light_car, 800,
     ["Body", "LampRed", "LampYellow", "LampGreen"], "pole", "red"),
    ("traffic_light_ped", "보행 신호등", make_traffic_light_ped, 400, ["Body", "LampRed", "LampGreen"], "center", "red"),
    ("bus_stop", "버스 정류장", make_bus_stop, 800, ["Body"], "center", "front"),
]


def export(pid, builder, max_tris, out_dir):
    objs = builder(reset_scene(), materials(pid, PALETTE[pid]))
    tris = tri_count(objs)
    if tris > max_tris:
        raise SystemExit(f"{pid}: {tris} triangles > {max_tris}")
    export_glb(os.path.join(out_dir, f"{pid}.glb"))
    render_thumbnail(objs, os.path.join(out_dir, "thumbs", f"{pid}.png"))
    size = godot_size(objs)
    print(f"[make_props] {pid}: {tris} tris, W x H x D {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} m, "
          f"nodes {[o.name for o in objs]}")
    return {"tris": tris, "size_m": size}


def main():
    out_dir, only = cli_args(OUT_DIR)
    entries = {}
    for pid, label, builder, max_tris, nodes, anchor, front in PROPS:
        entry = {"label": label, "glb": f"{RES_DIR}/{pid}.glb", "thumb": f"{RES_DIR}/thumbs/{pid}.png",
                 "max_tris": max_tris, "nodes": nodes, "anchor": anchor,
                 "front_material": f"{pid}_{front}" if front else None}
        if not only or pid in only:
            entry.update(export(pid, builder, max_tris, out_dir))
        entries[pid] = entry
    write_catalog(os.path.join(out_dir, "props.json"), entries)


if __name__ == "__main__":
    main()
