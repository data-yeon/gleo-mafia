## 사건 장소 랜드마크 11종(assets/models/landmarks) 미리보기와 규격 검사.
##
## 실행 인자 (godot 인자 뒤에 -- 를 붙이고 넘긴다):
##   --view=grid             grid(11종을 격자로, 기본) | road(자율주행 패널 크기로 길가 배치) | thumbs(PNG 썸네일 카드)
##   --screenshot=/path.png  몇 프레임 그린 뒤 저장하고 종료. road는 패널 크기(552×880) 그림만 저장한다
##   --check                 규격 검사만 하고 종료 (--headless 가능). 실패하면 종료 코드 1
##
## 예:
##   godot --path godot res://tests/landmark_preview.tscn -- --view=road --screenshot=/tmp/road.png
##   godot --headless --path godot res://tests/landmark_preview.tscn -- --check
extends Node3D

const INDEX := "res://assets/models/landmarks/landmarks.json"
const PUZZLE_DIR := "res://data/puzzles/"
const MAX_TRIS := 1500
const THUMB_PX := 256
const PANEL_SIZE := Vector2i(552, 880)
const LANE_W := 3.5
const FONT_NAMES := ["Pretendard", "Apple SD Gothic Neo", "Noto Sans KR", "Noto Sans CJK KR", "sans-serif"]
# 자율주행 패널(pleos_theme.gd)과 같은 색
const ADAS_BG := Color("f2f4f7")
const ADAS_ROAD := Color("cdd3db")
const ADAS_LANE := Color("ffffff")
const ADAS_PATH := Color(0.2, 0.45, 1.0, 0.35)
# 격자 보기 배치: 앞줄(카메라 쪽)부터. 키 큰 모델은 뒷줄
const GRID_ROWS := [
	["cafe", "park", "plaza", "station"],
	["market", "museum", "gym", "gov_office"],
	["clock_tower", "old_station", "observation_tower"],
]
# 길가 배치: [id, 편(1=오른편, -1=왼편), z]
const ROADSIDE := [
	["park", -1, -6.0], ["cafe", 1, -10.0], ["clock_tower", -1, -34.0], ["station", 1, -36.0],
	["observation_tower", -1, -66.0], ["gov_office", 1, -64.0], ["market", 1, -96.0], ["museum", -1, -96.0],
]

@onready var camera: Camera3D = $Camera3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var args := {}
var index := {}
var _font: SystemFont


func _ready() -> void:
	args = _parse_args()
	index = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(FONT_NAMES)
	if args.has("check"):
		get_tree().quit(0 if _check() else 1)
		return
	var target: Viewport = get_viewport()
	match String(args.get("view", "grid")):
		"road":
			target = _build_road_view()
		"thumbs":
			_build_thumbs_view()
		_:
			_build_grid_view()
	if args.has("screenshot"):
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := target.get_texture().get_image()
		img.save_png(String(args["screenshot"]))
		print("screenshot saved: ", args["screenshot"])
		get_tree().quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		if eq == -1:
			out[s] = true
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


func _model(id: String) -> Node3D:
	return (load(String(index["models"][id]["glb"])) as PackedScene).instantiate()


func _size(id: String) -> Vector3:
	var s: Array = index["models"][id]["size_m"]
	return Vector3(s[0], s[1], s[2])


# ---------------------------------------------------------------- 격자 보기

func _build_grid_view() -> void:
	_add_box(Vector3(140, 0.02, 120), Vector3(0, -0.011, 0), ADAS_BG.darkened(0.03), self)
	for r in GRID_ROWS.size():
		var row: Array = GRID_ROWS[r]
		for c in row.size():
			var id: String = row[c]
			var pos := Vector3((c - (row.size() - 1) / 2.0) * 28.0, 0, -30.0 + r * 30.0)
			var node := _model(id)
			node.position = pos
			add_child(node)
			var label := Label3D.new()
			label.text = String(index["models"][id]["label"])
			label.font = _font
			label.font_size = 96
			label.pixel_size = 0.03
			label.modulate = Color("374151")
			label.outline_size = 0
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = pos + Vector3(0, 1.0, -_size(id).z / 2.0 - 2.5)
			add_child(label)
	sun.rotation_degrees = Vector3(-55, 215, 0)  # 카메라(정면) 쪽에서 비춘다
	camera.fov = 34.0
	camera.position = Vector3(12, 100, -118)
	camera.look_at(Vector3(0, 0, -3))


# ---------------------------------------------------------------- 길가 보기 (자율주행 패널 흉내)

func _build_road_view() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = PANEL_SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)

	var env := WorldEnvironment.new()
	env.environment = world_env.environment.duplicate()
	env.environment.background_color = ADAS_BG
	env.environment.fog_enabled = true
	env.environment.fog_light_color = ADAS_BG
	env.environment.fog_density = 0.007
	root.add_child(env)
	var light := sun.duplicate() as DirectionalLight3D
	root.add_child(light)

	# adas_view.gd와 같은 카메라
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.position = Vector3(0, 10.0, 14.0)
	cam.rotation_degrees = Vector3(-32, 0, 0)
	cam.fov = 56
	cam.far = 220
	root.add_child(cam)

	_add_box(Vector3(LANE_W * 3 + 2.0, 0.02, 200), Vector3(0, -0.01, -80), ADAS_ROAD, root, true)
	for x in [-LANE_W * 1.5, LANE_W * 1.5]:
		_add_box(Vector3(0.2, 0.02, 200), Vector3(x, 0.01, -80), ADAS_LANE, root, true)
	var z := 20.0
	while z > -180.0:
		for x2 in [-LANE_W * 0.5, LANE_W * 0.5]:
			_add_box(Vector3(0.18, 0.02, 3.0), Vector3(x2, 0.012, z), ADAS_LANE, root, true)
		z -= 9.0
	_add_box(Vector3(2.2, 0.02, 30.0), Vector3(0, 0.03, -18.0), ADAS_PATH, root, true)

	var ego := (load("res://assets/models/ego_car.glb") as PackedScene).instantiate() as Node3D
	root.add_child(ego)
	var sedan := (load("res://assets/models/traffic_sedan.glb") as PackedScene).instantiate() as Node3D
	sedan.position = Vector3(-LANE_W, 0, -16)
	root.add_child(sedan)

	# 랜드마크는 정면(-Z)이 도로를 보게 돌린다: 오른편은 +90°, 왼편은 -90°.
	var road_edge := LANE_W * 1.5 + 1.0
	for item in ROADSIDE:
		var id: String = item[0]
		var side: int = item[1]
		var node := _model(id)
		node.rotation_degrees.y = 90.0 * side
		node.position = Vector3(side * (road_edge + 1.2 + _size(id).z / 2.0), 0, item[2])
		root.add_child(node)
	return vp


# ---------------------------------------------------------------- 썸네일 카드 보기

func _build_thumbs_view() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("eef1f5")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	center.add_child(grid)
	for id in index["models"]:
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.set_corner_radius_all(20)
		sb.set_content_margin_all(14)
		card.add_theme_stylebox_override("panel", sb)
		var box := VBoxContainer.new()
		card.add_child(box)
		var tex := TextureRect.new()
		tex.texture = load(String(index["models"][id]["thumb"]))
		tex.custom_minimum_size = Vector2(190, 190)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(tex)
		for t in [[String(index["models"][id]["label"]), 22, Color("111827")], [id, 15, Color("6b7280")]]:
			var label := Label.new()
			label.text = t[0]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_override("font", _font)
			label.add_theme_font_size_override("font_size", t[1])
			label.add_theme_color_override("font_color", t[2])
			box.add_child(label)
		grid.add_child(card)


func _add_box(size: Vector3, pos: Vector3, color: Color, parent: Node, unshaded := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- 규격 검사

func _check() -> bool:
	var ok := true
	for id in index["models"]:
		var info: Dictionary = index["models"][id]
		var problems: Array[String] = []
		if not ResourceLoader.exists(String(info["glb"])):
			print("%-18s FAIL: %s 없음" % [id, info["glb"]])
			ok = false
			continue
		var node := _model(id)
		var tris := 0
		var aabb := AABB()
		var first := true
		var front_z := []
		for c in node.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx = arrays[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else verts.size()) / 3
				var mat := mi.mesh.surface_get_material(s)
				var is_front: bool = mat != null and mat.resource_name == id + "_front"
				for v in verts:
					var p: Vector3 = mi.transform * v
					aabb = AABB(p, Vector3.ZERO) if first else aabb.expand(p)
					first = false
					if is_front:
						front_z.append(p.z)
		node.free()
		var center := aabb.get_center()
		if tris > MAX_TRIS:
			problems.append("삼각형 %d개 > %d" % [tris, MAX_TRIS])
		if absf(aabb.position.y) > 0.005:
			problems.append("바닥 높이 %.3f" % aabb.position.y)
		if absf(center.x) > 0.05 or absf(center.z) > 0.05:
			problems.append("원점이 가운데가 아님 (%.2f, %.2f)" % [center.x, center.z])
		if front_z.is_empty() or _avg(front_z) >= center.z:
			problems.append("정면(%s_front)이 -Z 쪽이 아님" % id)
		if (aabb.size - _size(id)).length() > 0.05:
			problems.append("landmarks.json 크기 불일치 %s" % aabb.size)
		var tex := load(String(info["thumb"])) as Texture2D
		if tex == null or tex.get_size() != Vector2(THUMB_PX, THUMB_PX):
			problems.append("썸네일 없음 또는 크기 다름")
		print("%-18s tris=%4d  size(WxHxD)=%5.1f x %4.1f x %4.1f m  %s" % [
			id, tris, aabb.size.x, aabb.size.y, aabb.size.z,
			"OK" if problems.is_empty() else "FAIL: " + ", ".join(problems)])
		ok = ok and problems.is_empty()
	ok = _check_places() and ok
	print("landmark check: ", "OK" if ok else "FAIL")
	return ok


## 퍼즐 팩의 모든 장소가 이름이나 업종으로 모델을 찾는지 본다.
func _check_places() -> bool:
	var missing := {}
	var count := 0
	for f in DirAccess.get_files_at(PUZZLE_DIR):
		if not f.ends_with(".json") or f == "index.json":
			continue
		var pack = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + f))
		for place in pack.get("places", []):
			count += 1
			var id = index["by_name"].get(place["name"], index["by_kind"].get(place["kind"]))
			if id == null or not index["models"].has(id):
				missing["%s/%s" % [place["kind"], place["name"]]] = true
	print("places: %d개 중 모델 없는 장소 %d종 %s" % [count, missing.size(), missing.keys()])
	return missing.is_empty()


func _avg(xs: Array) -> float:
	var t := 0.0
	for x in xs:
		t += x
	return t / maxf(xs.size(), 1)
