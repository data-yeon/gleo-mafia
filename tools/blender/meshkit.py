"""make_cars.py와 make_landmarks.py가 함께 쓰는 Blender 도우미: 머티리얼, 메시 쌓기, 내보내기.

좌표: Blender에서 +Y = 앞, +Z = 위. glTF(+Y up)로 내보내면 Godot에서 앞 = -Z가 된다.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

GODOT_ASSETS = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "assets")
)
SHARP_ANGLE = math.radians(35)
THUMB_PX = 256


# ---------------------------------------------------------------- 머티리얼


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, hex_color, roughness=0.85):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    rgb = [srgb_to_linear(int(hex_color[i:i + 2], 16) / 255.0) for i in (0, 2, 4)]
    mat.diffuse_color = (*rgb, 1.0)
    if not mat.node_tree:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def materials(prefix, palette):
    """{부위: hex} → {부위: 머티리얼}. 머티리얼 이름은 <prefix>_<부위>."""
    return {k: make_material(f"{prefix}_{k}", v) for k, v in palette.items()}


# ---------------------------------------------------------------- 메시 도우미


def hull_bm(points):
    """점들의 볼록 껍질 bmesh. 같은 평면의 삼각형은 사각형/다각형 면으로 합친다."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1), verts=bm.verts[:], edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def cylinder_bm(radius, depth, segments=14, axis="Z", radius_top=None):
    """원점 중심의 원기둥(radius_top을 주면 원뿔대). axis는 기둥 방향."""
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments,
        radius1=radius, radius2=radius if radius_top is None else radius_top, depth=depth,
    )
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts[:], cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts[:], cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "X"))
    return bm


def ring(cx, cy, z, radius, segments, rx=None, ry=None):
    """수평 원(또는 타원) 위의 점들."""
    rx = radius if rx is None else rx
    ry = radius if ry is None else ry
    return [(cx + rx * math.cos(2 * math.pi * i / segments), cy + ry * math.sin(2 * math.pi * i / segments), z)
            for i in range(segments)]


class Part:
    """bmesh 하나에 머티리얼 슬롯을 이름으로 붙여 가며 도형을 쌓는다. build()로 오브젝트 하나가 된다."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.materials = []

    def slot(self, mat):
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def box(self, mat, x0, x1, y0, y1, z0, z1):
        self.add(hull_bm([(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]), mat)

    def hull(self, mat, points):
        self.add(hull_bm(points), mat)

    def cylinder(self, mat, x, y, z0, radius, height, segments=12, radius_top=None):
        """바닥 중심 (x, y, z0)에 세운 원기둥/원뿔대."""
        bm = cylinder_bm(radius, height, segments, "Z", radius_top)
        bmesh.ops.translate(bm, vec=(x, y, z0 + height / 2), verts=bm.verts[:])
        self.add(bm, mat)

    def stick(self, mat, a, b, r):
        """두 점 a, b를 잇는 굵기 2r의 네모 막대(방향을 따라 돌린 상자, 삼각형 12개). 팔, 지팡이, 글자 획 등."""
        a, b = Vector(a), Vector(b)
        d = (b - a).normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        u = d.cross(ref).normalized() * r
        v = d.cross(u).normalized() * r
        self.hull(mat, [tuple(c + su * u + sv * v) for c in (a, b) for su in (-1, 1) for sv in (-1, 1)])

    def cone(self, mat, x, y, z0, radius, height, segments=10):
        self.hull(mat, ring(x, y, z0, radius, segments) + [(x, y, z0 + height)])

    def sphere(self, mat, x, y, z, radius, subdivisions=1, squash=1.0):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
        bmesh.ops.scale(bm, vec=(1, 1, squash), verts=bm.verts[:])
        bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts[:])
        self.add(bm, mat)

    def disc(self, mat, x, y, z, radius, thickness, axis, segments=16):
        """얇은 원판(시계 판 등). axis는 판이 바라보는 방향 축."""
        bm = cylinder_bm(radius, thickness, segments, axis)
        bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts[:])
        self.add(bm, mat)

    def add(self, src, mats):
        """다른 bmesh를 이 Part로 복사한다(src는 해제된다). mats는 머티리얼 하나 또는 src 슬롯 순서 목록."""
        if not isinstance(mats, list):
            mats = [mats]
        remap = [self.slot(m) for m in mats]
        mesh = bpy.data.meshes.new("_tmp")
        src.to_mesh(mesh)
        src.free()
        offset = len(self.bm.faces)
        self.bm.from_mesh(mesh)
        self.bm.faces.ensure_lookup_table()
        for f in self.bm.faces[offset:]:
            f.material_index = remap[min(f.material_index, len(remap) - 1)]
        bpy.data.meshes.remove(mesh)

    def build(self, collection, origin=None):
        """오브젝트 하나로 만든다. origin을 주면 그 점이 오브젝트 원점(회전축)이 된다(보행자 다리 등)."""
        bm = self.bm
        if origin is not None:
            bmesh.ops.translate(bm, vec=Vector(origin) * -1, verts=bm.verts[:])
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            if len(e.link_faces) != 2 or e.calc_face_angle(math.pi) > SHARP_ANGLE:
                e.smooth = False
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.materials:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        if origin is not None:
            obj.location = origin
        collection.objects.link(obj)
        return obj


# ---------------------------------------------------------------- 장면, 내보내기


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene.collection


def tri_count(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def bounds(objs):
    """(최소, 최대) 월드 좌표. 오브젝트의 이동·회전(예: 자세를 잡은 다리 노드)까지 반영한다."""
    bpy.context.view_layer.update()
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = tuple(min(v[i] for v in vs) for i in range(3))
    hi = tuple(max(v[i] for v in vs) for i in range(3))
    return lo, hi


def godot_size(objs):
    """Godot 축(x 폭, y 높이, z 깊이)으로 잰 크기(m)."""
    lo, hi = bounds(objs)
    return [round(hi[0] - lo[0], 2), round(hi[2] - lo[2], 2), round(hi[1] - lo[1], 2)]


def export_glb(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_yup=True, export_apply=True,
        export_texcoords=False, export_tangents=False, export_cameras=False, export_lights=False,
    )


def cli_args(default_out):
    """`-- [이름 ...] [--out 폴더]` 를 읽어 (출력 폴더, 고른 이름 목록)을 돌려준다."""
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = default_out
    only = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out_dir = os.path.abspath(argv[i + 1])
            i += 2
        else:
            only.append(argv[i])
            i += 1
    os.makedirs(out_dir, exist_ok=True)
    return out_dir, only


def render_thumbnail(objs, path, px=THUMB_PX):
    """앞 오른쪽 위(방위 30°, 고도 30°)에서 본 직교 투영 썸네일. 배경은 투명."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = px
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.eevee.taa_render_samples = 32

    world = bpy.data.worlds.new("thumb_world")
    if not world.node_tree:
        world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (1, 1, 1, 1)
    bg.inputs["Strength"].default_value = 0.75
    scene.world = world

    sun = bpy.data.objects.new("thumb_sun", bpy.data.lights.new("thumb_sun", "SUN"))
    sun.data.energy = 2.2
    sun.data.angle = math.radians(10)
    sun.rotation_euler = Vector((-0.45, 0.8, 1.3)).to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(sun)

    lo, hi = bounds(objs)
    corners = [Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    az, el = math.radians(30), math.radians(30)
    back = Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)))
    rot = (-back).to_track_quat("-Z", "Y")
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    rs = [c.dot(right) for c in corners]
    us = [c.dot(up) for c in corners]
    center = right * (min(rs) + max(rs)) / 2 + up * (min(us) + max(us)) / 2

    cam = bpy.data.objects.new("thumb_cam", bpy.data.cameras.new("thumb_cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(max(rs) - min(rs), max(us) - min(us)) * 1.08
    cam.data.clip_end = 500
    cam.location = center + back * 200
    cam.rotation_euler = rot.to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam

    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def write_catalog(path, entries):
    """에셋 목록 JSON({"models": {id: {...}}})을 쓴다.

    entries는 {id: 항목} 순서대로 전부 넘긴다. 이번에 만들지 않은 모델(tris가 없는 항목)은 기존 파일의 잰 값을 남긴다.
    """
    old = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            old = json.load(f).get("models", {})
    models = {}
    for mid, entry in entries.items():
        if "tris" not in entry:
            entry = {**old.get(mid, {}), **entry}
        models[mid] = entry
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"models": models}, f, ensure_ascii=False, indent=2)
        f.write("\n")
