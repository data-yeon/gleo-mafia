## 기울인 지도(하이브리드): 2D 내비 지도(NavMap)를 텍스처로 그려 3D 바닥 판에 붙이고, 원근 카메라로 비스듬히 본다.
## - 바닥(텍스처): 땅·블록·공원·강·도로·이름·경로·회전 화살표·단서 도형·수사망 — 지금 NavMap 그림 그대로.
## - 판 위(3D): 사건 장소 랜드마크 glb(지도에서 보이게 크게 키움)와 도시 블록 건물(높이를 세운 상자).
## - 화면(2D): 장소 번호 배지·이름은 글자가 기울지 않게 투영해서 그린다(CaseOverlay.draw_upright).
## 주행(따라가기)은 55°, 전체 보기는 26° 기운다. 누르기는 화면 → 카메라 광선 → 판 → NavMap px → 월드로 바꿔
## NavMap.tapped를 그대로 낸다(사건 쪽 코드는 평평한 지도와 같다).
class_name MapView3D
extends Control

const K := 0.01                   # 지도 텍스처 1px = 3D 0.01
const FOV := 38.0
const TILT_FOLLOW := 55.0
const TILT_OVERVIEW := 26.0
const FAR_PX := 1700.0            # 판(텍스처)을 앞쪽으로 이만큼(px)까지만 그린다. 그 너머는 안개
const TEX_MAX := Vector2(3000, 3000)
const LANDMARK_PX := 70.0         # 랜드마크가 화면에서 대략 이 크기(px)로 보이게 키운다
const BLOCK_EXAG := 1.0           # 블록 건물 높이 배율
const TEX_RES := 0.8              # 바닥 텍스처 해상도 배율(1 = 화면과 같은 선명도)

var nav_map: NavMap
var case_overlay: CaseOverlay
var tilt := TILT_FOLLOW
var _map_vp: SubViewport
var _world_vp: SubViewport
var _cont: SubViewportContainer
var _cam: Camera3D
var _ground: MeshInstance3D
var _ground_mesh: PlaneMesh
var _root: Node3D                 # 월드 좌표(x 동, y 높이, z 남) → 판 좌표. NavMap 보기에 맞춰 매 프레임 바뀐다
var _blocks: MeshInstance3D
var _marks := {}                  # 장소 id → {node, h, w, base_scale}
var _built_for: PuzzleCase
var _blocks_for: Dictionary = {}
var _badges: Control
var _tex := Vector2(1600, 1600)
var _cz := 0.0                    # 판 가운데의 3D z
var _layout_key := ""
var _gray: StandardMaterial3D


func _init(map: NavMap) -> void:
	nav_map = map


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_map_vp = SubViewport.new()
	_map_vp.disable_3d = true
	_map_vp.transparent_bg = false
	_map_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_vp.size = Vector2i(_tex)
	add_child(_map_vp)
	_map_vp.add_child(nav_map)
	nav_map.position = Vector2.ZERO
	nav_map.size = _tex
	nav_map.theme = _find_theme()
	nav_map.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cont = SubViewportContainer.new()
	_cont.stretch = true
	_cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cont)
	_world_vp = SubViewport.new()
	_world_vp.own_world_3d = true
	_world_vp.msaa_3d = Viewport.MSAA_2X
	_cont.add_child(_world_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("e9eef6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_light_color = Color("e9eef6")
	env.fog_density = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.3
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.35
	_world_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.far = 400.0
	_world_vp.add_child(_cam)
	_ground = MeshInstance3D.new()
	_ground_mesh = PlaneMesh.new()
	_ground.mesh = _ground_mesh
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = _map_vp.get_texture()
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_ground.material_override = gm
	_world_vp.add_child(_ground)
	_root = Node3D.new()
	_world_vp.add_child(_root)
	_gray = StandardMaterial3D.new()
	_gray.albedo_color = Color("c9ced6")
	_gray.roughness = 0.9

	_badges = Control.new()
	_badges.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.draw.connect(_draw_badges)
	add_child(_badges)


func _find_theme() -> Theme:
	var n: Node = self
	while n != null:
		if n is Control and (n as Control).theme != null:
			return (n as Control).theme
		n = n.get_parent()
	return null


# ---------------------------------------------------------------- 카메라·판 배치

## 화면 크기가 바뀌면 카메라 거리와 텍스처 크기를 다시 정한다(가장 많이 기운 따라가기 기준으로 화면을 다 덮게).
func _relayout() -> void:
	var sz := size
	if sz.x < 10.0 or sz.y < 10.0:
		return
	var key := "%d,%d" % [int(sz.x), int(sz.y)]
	if key == _layout_key:
		return
	_layout_key = key
	if nav_map.theme == null:
		nav_map.theme = _find_theme()
	# 가장 많이 기운 보기의 발자국(화면 네 귀퉁이가 판에 닿는 곳)을 덮는 텍스처
	_place_camera(TILT_FOLLOW)
	var pts := []
	for sp in [Vector2(0, 0), Vector2(sz.x, 0), Vector2(0, sz.y), Vector2(sz.x, sz.y), Vector2(sz.x / 2.0, 0)]:
		pts.append(_ray_plane(sp, true))
	var xmin := INF
	var xmax := -INF
	var zmin := INF
	var zmax := -INF
	for p in pts:
		var v: Vector3 = p
		xmin = minf(xmin, v.x)
		xmax = maxf(xmax, v.x)
		zmin = minf(zmin, v.z)
		zmax = maxf(zmax, v.z)
	zmin = maxf(zmin, zmax - FAR_PX * K)
	var w := minf((xmax - xmin) / K + 80.0, TEX_MAX.x)
	var h := minf((zmax - zmin) / K + 80.0, TEX_MAX.y)
	_tex = Vector2(ceilf(w / 8.0) * 8.0, ceilf(h / 8.0) * 8.0)
	_cz = (zmin + zmax) / 2.0
	# 바닥 텍스처는 좌표는 그대로 두고 TEX_RES 배율로 낮춰 그린다(2D를 매 프레임 크게 그리는 비용 줄이기)
	_map_vp.size = Vector2i(_tex * TEX_RES)
	_map_vp.size_2d_override = Vector2i(_tex)
	_map_vp.size_2d_override_stretch = true
	nav_map.size = _tex
	_ground_mesh.size = _tex * K
	_ground.position = Vector3(0, 0, _cz)
	# 먼 곳(판 끝)은 하늘색으로 흐려지게: 깊이 안개
	var env: Environment = (_world_vp.get_child(0) as WorldEnvironment).environment
	var d := sz.y * K / (2.0 * tan(deg_to_rad(FOV) / 2.0))
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = d * 1.45
	env.fog_depth_end = FAR_PX * K * 1.05
	env.fog_density = 1.0


## 카메라: 화면 1px ≈ 지도 1px이 되는 거리에서, 수직으로부터 t도 기울여 판 가운데 근처를 본다.
func _place_camera(t_deg: float) -> void:
	var t := deg_to_rad(t_deg)
	var d := size.y * K / (2.0 * tan(deg_to_rad(FOV) / 2.0))
	var target := Vector3(0, 0, -size.y * K * 0.12 * (t_deg / TILT_FOLLOW))
	_cam.position = target + Vector3(0, cos(t), sin(t)) * d
	_cam.look_at(target, Vector3.FORWARD if t_deg < 1.0 else Vector3.UP)


## 화면 점 → 판(y=0) 위 3D 점. clamp_far면 너무 먼 곳은 FAR_PX 안으로.
func _ray_plane(sp: Vector2, clamp_far := false) -> Vector3:
	var o := _cam.project_ray_origin(sp)
	var n := _cam.project_ray_normal(sp)
	if n.y >= -0.02:
		n.y = -0.02
	var t := -o.y / n.y
	var p := o + n * t
	if clamp_far:
		var foot := Vector3(_cam.position.x, 0, _cam.position.z)
		var far := FAR_PX * K
		if p.distance_to(foot) > far:
			p = foot + (p - foot).normalized() * far
	return p


## 판 3D 점 → NavMap px
func _plane_to_tex(p: Vector3) -> Vector2:
	return Vector2(p.x / K + _tex.x / 2.0, (p.z - _cz) / K + _tex.y / 2.0)


func _tex_to_plane(px: Vector2) -> Vector3:
	return Vector3((px.x - _tex.x / 2.0) * K, 0.0, (px.y - _tex.y / 2.0) * K + _cz)


func _process(delta: float) -> void:
	_relayout()
	if _layout_key == "":
		return
	var want := TILT_OVERVIEW if nav_map.view_mode == "overview" else TILT_FOLLOW
	tilt = move_toward(tilt, want, delta * 40.0)
	_place_camera(tilt)
	_sync_navmap()
	_sync_root()
	_sync_blocks()
	_sync_landmarks()
	_badges.queue_redraw()


## 화면에서 보이는 부분에 맞춰 NavMap의 내 차 자리와 전체 보기 맞춤 영역을 정한다.
func _sync_navmap() -> void:
	var sz := size
	nav_map.follow_anchor = _plane_to_tex(_ray_plane(Vector2(sz.x * 0.5, sz.y * 0.74)))
	# 카드가 가리지 않는 화면 영역(view_insets: 화면 px)의 네 귀퉁이 → 텍스처. 안쪽 직사각형에 맞춘다
	var ins := nav_map.view_insets
	var r := Rect2(Vector2(ins.x, ins.y), sz - Vector2(ins.x + ins.z, ins.y + ins.w))
	if r.size.x < 200.0 or r.size.y < 200.0:
		r = Rect2(Vector2.ZERO, sz)
	var tl := _plane_to_tex(_ray_plane(r.position, true))
	var tr := _plane_to_tex(_ray_plane(Vector2(r.end.x, r.position.y), true))
	var bl := _plane_to_tex(_ray_plane(Vector2(r.position.x, r.end.y), true))
	var br := _plane_to_tex(_ray_plane(r.end, true))
	var x0 := maxf(tl.x, bl.x)
	var x1 := minf(tr.x, br.x)
	var y0 := maxf(tl.y, tr.y)
	var y1 := minf(bl.y, br.y)
	nav_map.fit_rect = Rect2(x0, y0, maxf(x1 - x0, 10.0), maxf(y1 - y0, 10.0))


## 월드 → 판: NavMap 변환(월드 (x, -y) → px)과 텍스처 → 판 배치를 이어 붙인다.
func _sync_root() -> void:
	var xf := nav_map.view_xform()
	var s := nav_map.px_per_m()
	var col_x := Vector3(xf.x.x, 0, xf.x.y) * K
	var col_z := Vector3(xf.y.x, 0, xf.y.y) * K
	var col_y := Vector3(0, s * K, 0)
	var origin := _tex_to_plane(xf.origin)
	_root.transform = Transform3D(Basis(col_x, col_y, col_z), origin)


# ---------------------------------------------------------------- 랜드마크·블록

func _sync_landmarks() -> void:
	var c := case_overlay.case if case_overlay != null else null
	if c != _built_for:
		_build_landmarks(c)
	if c == null:
		return
	var s := maxf(nav_map.px_per_m(), 0.0001)
	for k in _marks.keys():
		var id := int(k)
		var mk: Dictionary = _marks[id]
		var node: Node3D = mk["node"]
		var appear := clampf(case_overlay.reveal_t * c.place_count() - (id - 1), 0.0, 1.0)
		var dim := c.revealed.has(id) and not c.caught.has(id) or case_overlay.excluded.has(id)
		# 화면에서 LANDMARK_PX 정도로 보이게 키운다(가까이 보면 실제 크기 쪽으로)
		var f := maxf(1.0, LANDMARK_PX / (float(mk["size"]) * s))
		var sc := f * (0.82 if dim else 1.0) * (0.3 + 0.7 * appear)
		node.scale = Vector3(sc, sc, sc)
		node.position.y = (1.0 - appear) * 30.0 / s
		node.visible = appear > 0.0
		if bool(mk.get("dim", false)) != dim:
			mk["dim"] = dim
			_tint(node, _gray if dim else null)


func _build_landmarks(c: PuzzleCase) -> void:
	for k in _marks.keys():
		(_marks[k]["node"] as Node3D).queue_free()
	_marks.clear()
	_built_for = c
	if c == null:
		return
	for pl in c.data["places"]:
		var id := int(pl["id"])
		var mid := Landmarks.id_for(String(pl["name"]), String(pl["kind"]))
		if mid == "":
			continue
		var node := Landmarks.instantiate(mid)
		if node == null:
			continue
		var holder := Node3D.new()
		holder.add_child(node)
		var wx := float(pl["x"])
		var wy := float(pl["y"])
		holder.position = Vector3(wx, 0, -wy)
		# 정면(-Z)이 경로 쪽을 보게
		var near := _nearest_route(Vector2(wx, wy))
		var dx := near.x - wx
		var dz := -(near.y - wy)
		if absf(dx) + absf(dz) > 0.1:
			node.rotation.y = atan2(-dx, -dz)
		_root.add_child(holder)
		var sz := Landmarks.size_of(mid)
		_marks[id] = {"node": holder, "size": maxf(maxf(sz.x, sz.z), sz.y), "h": sz.y, "dim": false}


func _nearest_route(p: Vector2) -> Vector2:
	var best := p
	var bd := INF
	var r := nav_map.route
	for i in range(1, r.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, r[i - 1], r[i])
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best


## 블록 건물: 도시가 바뀌면 다시 세운다. 가까이 볼 때(따라가기)만 보이고, 멀리 보면(전체 보기) 낮아지며 사라진다
## (추리 화면은 바닥 지도가 잘 보여야 한다).
func _sync_blocks() -> void:
	if not is_same(nav_map.city_data, _blocks_for):     # 같은 사전인지(내용 비교는 매 프레임 너무 비싸다)
		_blocks_for = nav_map.city_data
		if _blocks != null:
			_blocks.queue_free()
			_blocks = null
		_build_blocks(_blocks_for)
	if _blocks == null:
		return
	var k := clampf((nav_map.px_per_m() - 0.1) / 0.12, 0.0, 1.0)
	_blocks.visible = k > 0.02
	_blocks.scale = Vector3(1.0, maxf(k, 0.02), 1.0)


## 도시 블록을 높이만큼 세운 밝은 상자들(메시 하나). 높이는 블록 번호로 정한다(같은 팩이면 같은 모양).
func _build_blocks(city: Dictionary) -> void:
	var blocks: Array = city.get("blocks", [])
	if blocks.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := 0
	for b in blocks:
		idx += 1
		var poly := PackedVector2Array()
		for q in b:
			poly.append(Vector2(float(q[0]), -float(q[1])))     # (x, z=남)
		if poly.size() < 3:
			continue
		var hgt := (6.0 + float((idx * 7919) % 13) * 1.2) * BLOCK_EXAG
		# 블록 안쪽으로 조금 들인 몸체(블록 땅이 테두리로 보이게)
		var inset := Geometry2D.offset_polygon(poly, -7.0)
		if inset.is_empty():
			continue
		var body: PackedVector2Array = inset[0]
		var tris := Geometry2D.triangulate_polygon(body)
		var roof := Color("e9ecf1")
		for ti in range(0, tris.size(), 3):
			var a: Vector2 = body[tris[ti]]
			var bb: Vector2 = body[tris[ti + 1]]
			var c: Vector2 = body[tris[ti + 2]]
			_tri(st, Vector3(a.x, hgt, a.y), Vector3(bb.x, hgt, bb.y), Vector3(c.x, hgt, c.y), Vector3.UP, roof)
		for i in body.size():
			var p0: Vector2 = body[i]
			var p1: Vector2 = body[(i + 1) % body.size()]
			var e := p1 - p0
			var n2 := Vector2(e.y, -e.x).normalized()
			if Geometry2D.is_point_in_polygon((p0 + p1) / 2.0 + n2 * 0.5, body):
				n2 = -n2                  # 바깥쪽을 보게
			var nrm := Vector3(n2.x, 0, n2.y)
			var wall := Color("d3d8e0")
			var a0 := Vector3(p0.x, 0, p0.y)
			var a1 := Vector3(p1.x, 0, p1.y)
			var b0 := Vector3(p0.x, hgt, p0.y)
			var b1 := Vector3(p1.x, hgt, p1.y)
			_tri(st, a0, a1, b1, nrm, wall)
			_tri(st, a0, b1, b0, nrm, wall)
	# 반투명: 건물 뒤로 지나는 경로선과 내 차가 가려지지 않게(실제 내비 3D 보기처럼)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.58)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_blocks = MeshInstance3D.new()
	_blocks.mesh = st.commit()
	_blocks.material_override = m
	_root.add_child(_blocks)


## 삼각형 하나: 바깥 법선 n 쪽에서 볼 때 앞면이 되게(Godot은 시계 방향이 앞면) 순서를 맞춘다.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (c - a).cross(b - a).dot(n) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _tint(root: Node, mat: Material) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = mat
	for ch in root.get_children():
		_tint(ch, mat)


# ---------------------------------------------------------------- 배지(화면 2D)

func _project(id: int) -> Dictionary:
	if not _marks.has(id) or _cam == null:
		return {"ok": false}
	var mk: Dictionary = _marks[id]
	var node: Node3D = mk["node"]
	if not node.visible:
		return {"ok": false}
	var base := node.global_position
	var top := base + Vector3(0, float(mk["h"]) * node.scale.y * nav_map.px_per_m() * K, 0)
	if _cam.is_position_behind(base):
		return {"ok": false}
	var c := case_overlay.case
	var appear := clampf(case_overlay.reveal_t * c.place_count() - (id - 1), 0.0, 1.0)
	return {"ok": true, "top": _cam.unproject_position(top) - Vector2(0, 16), "base": _cam.unproject_position(base),
			"appear": appear}


func _draw_badges() -> void:
	if case_overlay != null and case_overlay.case != null and case_overlay.upright:
		case_overlay.draw_upright(_badges, _project)


# ---------------------------------------------------------------- 누르기

func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	var sp: Vector2 = (e as InputEventMouseButton).position
	# 랜드마크(배지·몸체)를 먼저 본다
	var best := -1
	var bd := 44.0
	for k in _marks.keys():
		var pj := _project(int(k))
		if not bool(pj.get("ok", false)):
			continue
		var top: Vector2 = pj["top"]
		var base: Vector2 = pj["base"]
		var d := minf(sp.distance_to(top), sp.distance_to((top + base) / 2.0))
		if d < bd:
			bd = d
			best = int(k)
	var tex := Vector2.ZERO
	var world := Vector2.ZERO
	if best != -1:
		var pl := case_overlay.case.place(best)
		world = Vector2(float(pl["x"]), float(pl["y"]))
		tex = nav_map.to_screen(world)
	else:
		tex = _plane_to_tex(_ray_plane(sp))
		var w := nav_map.view_xform().affine_inverse() * tex
		world = Vector2(w.x, -w.y)
	nav_map.tapped.emit(world, tex)
