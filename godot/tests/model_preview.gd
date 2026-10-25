## 3D 에셋 미리보기와 규격 검사: 주행 화면(차량 9종, 보행자 4종, 길거리 소품 6종),
## 현장 확대도(제보자·범인 인물 11종, 소품 4종).
## 목록은 assets/models/vehicles.json, people/people.json, props/props.json, figures/figures.json
## (tools/blender/make_*.py가 만든다).
##
## 실행 인자 (godot 인자 뒤에 -- 를 붙이고 넘긴다):
##   --view=chase            chase(차 4종 뒤 위, 기본) | front(앞) | adas(차선 위 배치)
##                           | lineup(모든 에셋을 줄 세움) | street(자율주행 패널 크기 552×880로 교차로 장면)
##                           | scene(현장 확대도 960×540: 광장 앞 제보자 9종, 경찰차, 폴리스 라인)
##   --screenshot=/path.png  몇 프레임 그린 뒤 저장하고 종료. street·scene은 그 크기 그림만 저장한다
##   --check                 세 목록의 모든 모델 규격 검사만 하고 종료 (--headless 가능). 실패하면 종료 코드 1
##
## 예:
##   godot --path godot res://tests/model_preview.tscn -- --view=street --screenshot=/tmp/street.png
##   godot --headless --path godot res://tests/model_preview.tscn -- --check
extends Node3D

const LANE := 3.5
const LANES := 4
const FLASH_PERIOD := 0.35
const CATALOGS := ["res://assets/models/vehicles.json", "res://assets/models/people/people.json",
		"res://assets/models/props/props.json", "res://assets/models/figures/figures.json"]
const SCENE_SIZE := Vector2i(960, 540)
const THUMB_PX := 256
const PANEL_SIZE := Vector2i(552, 880)
const FONT_NAMES := ["Pretendard", "Apple SD Gothic Neo", "Noto Sans KR", "Noto Sans CJK KR", "sans-serif"]
# 자율주행 패널(pleos_theme.gd)과 같은 색
const ADAS_BG := Color("f2f4f7")
const ADAS_ROAD := Color("cdd3db")
const SIDEWALK := Color("e4e8ed")
const RING_COLOR := Color(0.35, 0.6, 1.0, 0.55)
const ROAD_COLOR := Color("dcdfe4")
const LINE_COLOR := Color("ffffff")
const PATH_COLOR := Color(0.24, 0.48, 1.0, 0.55)

@onready var camera: Camera3D = $Camera3D
@onready var models: Node3D = $Models
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var args := {}
var _flash_t := 0.0
var _flash_red := true
var _bar_red: MeshInstance3D
var _bar_blue: MeshInstance3D
var _path_band: MeshInstance3D


func _ready() -> void:
	args = _parse_args()
	if args.has("check"):
		get_tree().quit(0 if _check_models() else 1)
		return
	var view := String(args.get("view", "chase"))
	var target: Viewport = get_viewport()
	if view == "lineup":
		_build_lineup()
	elif view == "street":
		target = _build_street()
	elif view == "scene":
		target = _build_scene()
	else:
		_build_road()
		_apply_view(view)
		_setup_flash()
	if args.has("screenshot"):
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := target.get_texture().get_image()
		img.save_png(String(args["screenshot"]))
		print("screenshot saved: ", args["screenshot"])
		get_tree().quit()


func _process(delta: float) -> void:
	if _bar_red == null:
		return
	_flash_t += delta
	if _flash_t >= FLASH_PERIOD:
		_flash_t = 0.0
		_flash_red = not _flash_red
		_set_bar_lit(_bar_red, _flash_red)
		_set_bar_lit(_bar_blue, not _flash_red)


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


# ---------------------------------------------------------------- 배치

func _apply_view(view: String) -> void:
	var ego: Node3D = models.get_node("ego_car")
	var sedan: Node3D = models.get_node("traffic_sedan")
	var suv: Node3D = models.get_node("traffic_suv")
	var police: Node3D = models.get_node("police_car")
	match view:
		"front":
			camera.fov = 32.0
			camera.position = Vector3(-4.0, 4.2, -21.0)
			camera.look_at(Vector3(0.0, 0.7, 0.0))
		"adas":
			# 내 차는 오른쪽에서 둘째 차로. 앞에 세단, 오른쪽 앞에 SUV, 왼쪽 차로로 경찰차가 추월 중.
			ego.position = Vector3(LANE * 0.5, 0, 0)
			sedan.position = Vector3(LANE * 0.5, 0, -15.0)
			suv.position = Vector3(LANE * 1.5, 0, -8.0)
			police.position = Vector3(-LANE * 0.5, 0, -2.5)
			_path_band.visible = true
			_path_band.position = Vector3(LANE * 0.5, 0.012, -14.0)
			camera.fov = 50.0
			camera.position = Vector3(LANE * 0.5, 6.5, 10.5)
			camera.look_at(Vector3(LANE * 0.5, 0.0, -9.0))
		_:
			camera.fov = 32.0
			camera.position = Vector3(3.0, 6.5, 19.0)
			camera.look_at(Vector3(0.0, 0.6, 0.0))


func _build_road() -> void:
	var half := LANE * LANES * 0.5
	_add_box(Vector3(LANE * LANES + 1.0, 0.02, 120.0), Vector3(0, -0.01, -30.0), ROAD_COLOR)
	for i in LANES + 1:
		var x := -half + LANE * i
		if i == 0 or i == LANES:
			_add_box(Vector3(0.15, 0.01, 120.0), Vector3(x, 0.006, -30.0), LINE_COLOR)
		else:
			for k in 20:
				_add_box(Vector3(0.15, 0.01, 3.0), Vector3(x, 0.006, 25.0 - k * 6.0), LINE_COLOR)
	_path_band = _add_box(Vector3(2.4, 0.004, 32.0), Vector3.ZERO, PATH_COLOR)
	_path_band.visible = false


func _add_box(size: Vector3, pos: Vector3, color: Color, parent: Node = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if color.a < 1.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- 경광등 깜빡임 (adas_view.gd에서 쓸 방식의 예)

func _setup_flash() -> void:
	var police: Node3D = models.get_node("police_car")
	_bar_red = police.find_child("LightBarRed", true, false)
	_bar_blue = police.find_child("LightBarBlue", true, false)
	for bar in [_bar_red, _bar_blue]:
		var mat: StandardMaterial3D = bar.mesh.surface_get_material(0).duplicate()
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		bar.material_override = mat
		bar.set_meta("base_color", mat.albedo_color)
	_set_bar_lit(_bar_red, true)
	_set_bar_lit(_bar_blue, false)


func _set_bar_lit(bar: MeshInstance3D, lit: bool) -> void:
	var mat: StandardMaterial3D = bar.material_override
	var base: Color = bar.get_meta("base_color")
	mat.emission_energy_multiplier = 1.2 if lit else 0.0
	mat.albedo_color = base if lit else base.darkened(0.45)


# ---------------------------------------------------------------- 목록과 모델

func _catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.get("models", {}) if typeof(parsed) == TYPE_DICTIONARY else {}


func _asset(id: String) -> Node3D:
	for cat in CATALOGS:
		var d := _catalog(cat)
		if d.has(id):
			return (load(String(d[id]["glb"])) as PackedScene).instantiate() as Node3D
	push_error("목록에 없는 에셋: " + id)
	return Node3D.new()


func _place(id: String, pos: Vector3, yaw_deg := 0.0, parent: Node = self) -> Node3D:
	var n := _asset(id)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	parent.add_child(n)
	return n


## 램프 노드를 켜거나(발광) 어둡게 한다. 신호등 램프, 택시 표시등에 쓴다.
func _set_lamp(root: Node, lamp_name: String, lit: bool) -> void:
	var mi := root.find_child(lamp_name, true, false) as MeshInstance3D
	if mi == null:
		return
	var mat := (mi.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	if lit:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 1.5
	else:
		mat.albedo_color = mat.albedo_color.darkened(0.55)
	mi.material_override = mat


## 보행자 걷기 자세: 다리 노드(LegL, LegR)를 엉덩이 축으로 앞뒤로 벌린다.
func _stride(person: Node, angle_deg: float) -> void:
	(person.find_child("LegL", true, false) as Node3D).rotation_degrees.x = angle_deg
	(person.find_child("LegR", true, false) as Node3D).rotation_degrees.x = -angle_deg


# ---------------------------------------------------------------- 줄 세우기 보기

func _build_lineup() -> void:
	models.visible = false
	_add_box(Vector3(110, 0.02, 90), Vector3(0, -0.011, -8), ADAS_BG.darkened(0.03))
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	# 뒤에서 앞으로: 소품, 차량, 보행자 (카메라는 앞쪽 -Z에 있다)
	# [목록, z, 간격, 종류(figures.json의 kind로 나눔)]
	var rows := [[CATALOGS[2], 13.0, 4.0, ""], [CATALOGS[0], 0.0, 1.8, ""], [CATALOGS[1], -10.0, 3.2, ""],
			[CATALOGS[3], -18.0, 2.4, "figure"], [CATALOGS[3], -25.0, 3.0, "prop"]]
	for row in rows:
		var d := _catalog(row[0])
		if String(row[3]) != "":
			var only := {}
			for id in d:
				if String(d[id].get("kind", "")) == String(row[3]):
					only[id] = d[id]
			d = only
		var widths := []
		var total := 0.0
		for id in d:
			var w: float = float(d[id]["size_m"][0])
			widths.append(w)
			total += w
		total += float(row[2]) * (d.size() - 1)
		var x := total / 2.0
		var i := 0
		for id in d:
			# 카메라(앞)에서 보면 +X가 오른쪽이 되도록 -X쪽부터 채운다
			var w: float = widths[i]
			var cx := x - w / 2.0
			var info: Dictionary = d[id]
			var node := _place(String(id), Vector3(-cx, 0, float(row[1])))
			if String(info.get("anchor", "center")) == "pole":
				node.position.x += float(info["size_m"][0]) / 2.0 - 0.3
			if node.find_child("LegL", true, false) != null:
				_stride(node, 18.0 if i % 2 == 0 else -18.0)
			for lamp in ["LampRed", "LampGreen", "TaxiSign"]:
				_set_lamp(node, lamp, true)
			var label := Label3D.new()
			label.text = String(info["label"])
			label.font = font
			label.font_size = 64
			label.pixel_size = 0.008
			label.modulate = Color("374151")
			label.outline_size = 0
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = Vector3(-cx, 0.3, float(row[1]) - float(info["size_m"][2]) / 2.0 - 0.9)
			add_child(label)
			x -= w + float(row[2])
			i += 1
	sun.rotation_degrees = Vector3(-55, 215, 0)  # 카메라(정면) 쪽에서 비춘다
	camera.fov = 33.0
	camera.position = Vector3(0, 38, -58)
	camera.look_at(Vector3(0, 0.5, -6.0))


# ---------------------------------------------------------------- 현장 확대도 보기

## 현장 3D 확대도 견본(960×540): 광장 랜드마크 앞에 제보자 9종이 서 있고,
## 경찰차가 들어와 서고, 앞쪽에 폴리스 라인이 쳐져 있다.
func _build_scene() -> SubViewport:
	models.visible = false
	var vp := SubViewport.new()
	vp.size = SCENE_SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = world_env.environment.duplicate()
	root.add_child(env)
	var light := sun.duplicate() as DirectionalLight3D
	light.rotation_degrees = Vector3(-55, 215, 0)   # 카메라(정면) 쪽에서 비춘다
	root.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(1.5, 7.0, -25.0)
	root.add_child(cam)
	cam.look_at(Vector3(0.5, 1.6, -7.0))

	_add_box(Vector3(60, 0.02, 50), Vector3(0, -0.011, -5), ADAS_BG.darkened(0.03), root)
	var plaza := (load("res://assets/models/landmarks/plaza.glb") as PackedScene).instantiate() as Node3D
	root.add_child(plaza)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	var cat := _catalog(CATALOGS[3])
	var ids := ["VENDOR", "TAXI", "DRONE", "LOCAL", "RIDER", "GUARD", "COP", "GOSSIP", "ANON"]
	for i in ids.size():
		var id: String = ids[i]
		var x := -7.2 + i * 1.8
		var z := -10.2 - 0.6 * absf(i - 4.0) / 4.0
		var fig := _place(id, Vector3(x, 0, z), 0, root)
		if fig.find_child("LegL", true, false) != null and i % 3 == 1:
			_stride(fig, 12.0)
		var label := Label3D.new()
		label.text = String(cat[id]["label"])
		label.font = font
		label.font_size = 48
		label.pixel_size = 0.0075
		label.modulate = Color("374151")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(x, 0.05, z - (0.8 if i % 2 == 0 else 1.35))   # 이웃 이름이 겹치지 않게 엇갈린다
		root.add_child(label)
	var police := _place("police_car", Vector3(10.0, 0, -11.5), -35, root)
	var bars := [police.find_child("LightBarRed", true, false), police.find_child("LightBarBlue", true, false)]
	for bar in bars:
		var mat := ((bar as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 1.2
		(bar as MeshInstance3D).material_override = mat
	_place("police_tape", Vector3(-3.6, 0, -13.6), 8, root)
	return vp


# ---------------------------------------------------------------- 교차로 보기 (자율주행 패널 흉내)

## 4차로(양방향 2차로) 교차로 앞. 내 차는 신호 대기, 횡단보도를 보행자가 건넌다.
## 가로수·가로등·신호등·버스 정류장·차량 다양화를 패널 카메라(adas_view.gd와 같음)로 본다.
func _build_street() -> SubViewport:
	models.visible = false
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
	root.add_child(sun.duplicate())

	var ego_x := LANE * 0.5
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.position = Vector3(ego_x, 10.0, 14.0)
	cam.rotation_degrees = Vector3(-32, 0, 0)
	cam.fov = 56
	cam.far = 220
	root.add_child(cam)

	# 도로(양방향 2차로), 보도, 차선, 정지선, 횡단보도
	var stop_z := -13.5
	var cross := Vector2(-19.5, -15.0)      # 횡단보도 z 범위
	_add_box(Vector3(LANE * 4, 0.02, 220), Vector3(0, -0.01, -80), ADAS_ROAD, root)
	for sx in [-1, 1]:
		_add_box(Vector3(4.5, 0.15, 220), Vector3(sx * (LANE * 2 + 2.25), 0.065, -80), SIDEWALK, root)
		_add_box(Vector3(0.15, 0.02, 220), Vector3(sx * LANE * 2 - sx * 0.2, 0.012, -80), Color.WHITE, root)
		_add_box(Vector3(0.12, 0.02, 220), Vector3(sx * 0.12, 0.012, -80), Color("f2d38a"), root)
		var z := 20.0
		while z > -180.0:
			if z < cross.x - 1.0 or z > stop_z + 1.0:
				_add_box(Vector3(0.15, 0.02, 3.0), Vector3(sx * LANE, 0.012, z), Color.WHITE, root)
			z -= 9.0
	_add_box(Vector3(LANE * 2, 0.02, 0.45), Vector3(LANE, 0.014, stop_z), Color.WHITE, root)
	var x := -LANE * 2 + 0.6
	while x < LANE * 2 - 0.3:
		_add_box(Vector3(0.5, 0.02, cross.y - cross.x), Vector3(x, 0.014, (cross.x + cross.y) / 2.0), Color.WHITE, root)
		x += 1.0
	# 파란 주행 경로 띠(정지선까지)
	_add_box(Vector3(2.2, 0.01, 11.0), Vector3(ego_x, 0.03, -2.5 - 5.5), Color(0.2, 0.45, 1.0, 0.35), root)

	# 차량: 우리 방향(-Z로 진행)은 x>0, 반대 방향은 x<0이고 180° 돌린다
	_place("ego_car", Vector3(ego_x, 0, 0), 0, root)
	_set_lamp(_place("taxi", Vector3(ego_x, 0, -10.5), 0, root), "TaxiSign", true)
	_place("bus", Vector3(LANE * 1.5, 0, -7.4), 0, root)
	_place("scooter", Vector3(LANE * 1.5, 0, 1.5), 0, root)
	_place("truck", Vector3(-LANE * 0.5, 0, -27.0), 180, root)
	_place("traffic_sedan", Vector3(-LANE * 1.5, 0, -34.0), 180, root)
	_place("compact", Vector3(-LANE * 0.5, 0, -40.0), 180, root)
	_place("traffic_suv", Vector3(LANE * 0.5, 0, -48.0), 0, root)

	# 신호등: 우리 쪽은 길 건너 오른쪽 보도에서 팔이 도로 위로(180° 돌림), 빨간불
	var tl := _place("traffic_light_car", Vector3(LANE * 2 + 0.6, 0.14, cross.x - 2.5), 180, root)
	_set_lamp(tl, "LampRed", true)
	for lamp in ["LampYellow", "LampGreen"]:
		_set_lamp(tl, lamp, false)
	var tl2 := _place("traffic_light_car", Vector3(-LANE * 2 - 0.6, 0.14, stop_z + 1.0), 0, root)
	_set_lamp(tl2, "LampRed", true)
	# 보행 신호등: 횡단보도 양 끝, 길 건너편을 본다. 초록불
	for side in [-1, 1]:
		var ps := _place("traffic_light_ped", Vector3(side * (LANE * 2 + 0.8), 0.14, cross.y + 0.6), 90.0 * side, root)
		_set_lamp(ps, "LampGreen", true)
		_set_lamp(ps, "LampRed", false)

	# 보행자: 횡단보도를 건너는 중(정면이 걷는 방향) + 인식 링
	var walkers := [["ped_suit", -4.6, 1], ["ped_umbrella", -1.2, -1], ["ped_casual", 2.4, -1], ["ped_kid", 4.4, 1]]
	for i in walkers.size():
		var w: Array = walkers[i]
		var dir: int = w[2]
		var z := (cross.x + cross.y) / 2.0 + (0.8 if i % 2 == 0 else -0.6)
		var p := _place(String(w[0]), Vector3(float(w[1]), 0.02, z), -90.0 * dir, root)
		_stride(p, 20.0 if i % 2 == 0 else -20.0)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.68
		ring.mesh = torus
		ring.scale = Vector3(1, 0.05, 1)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = RING_COLOR
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = rm
		ring.position = Vector3(float(w[1]), 0.05, z)
		root.add_child(ring)
	_place("ped_casual", Vector3(LANE * 2 + 1.6, 0.14, cross.y + 1.6), 90, root)

	# 보도: 가로수(12m 간격, 교차로 비움), 가로등(30m 간격), 버스 정류장
	var z2 := 10.0
	var k := 0
	while z2 > -170.0:
		var near_cross := z2 > cross.x - 6.0 and z2 < stop_z + 4.0
		var near_stop := z2 > -66.0 and z2 < -54.0
		if not near_cross:
			for side in [-1, 1]:
				if side == 1 and near_stop:
					continue
				var tid := "tree_round" if (k + (1 if side > 0 else 0)) % 3 != 0 else "tree_cone"
				var t := _place(tid, Vector3(side * (LANE * 2 + 3.3), 0.14, z2), k * 37.0, root)
				t.scale = Vector3.ONE * (0.85 + 0.1 * float((k * 7) % 3))
		k += 1
		z2 -= 12.0
	var z3 := -4.0
	while z3 > -170.0:
		_place("street_light", Vector3(LANE * 2 + 0.7, 0.14, z3), 180, root)
		_place("street_light", Vector3(-LANE * 2 - 0.7, 0.14, z3 - 15.0), 0, root)
		z3 -= 30.0
	_place("bus_stop", Vector3(LANE * 2 + 2.4, 0.14, -60.0), 90, root)
	return vp


# ---------------------------------------------------------------- 규격 검사

func _check_models() -> bool:
	var ok := true
	for cat in CATALOGS:
		var d := _catalog(cat)
		print("== %s (%d종)" % [cat.get_file(), d.size()])
		if d.is_empty():
			print("FAIL: 목록이 없거나 비었음")
			ok = false
		for id in d:
			ok = _check_one(String(id), d[id]) and ok
	print("model check: ", "OK" if ok else "FAIL")
	return ok


func _check_one(id: String, info: Dictionary) -> bool:
	var problems: Array[String] = []
	var scene := load(String(info["glb"])) as PackedScene
	if scene == null:
		print("%-18s FAIL: %s 없음" % [id, info["glb"]])
		return false
	var root := scene.instantiate() as Node3D
	add_child(root)
	var tris := 0
	var aabb := AABB()
	var first := true
	var front_z := []
	var front_mat := String(info["front_material"]) if info.get("front_material") != null else ""
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else verts.size()) / 3
			var mat := mi.mesh.surface_get_material(s)
			var is_front: bool = mat != null and front_mat != "" and mat.resource_name == front_mat
			for v in verts:
				var p: Vector3 = xf * v
				aabb = AABB(p, Vector3.ZERO) if first else aabb.expand(p)
				first = false
				if is_front:
					front_z.append(p.z)
	var center := aabb.get_center()
	var max_tris := int(info["max_tris"])
	if tris > max_tris:
		problems.append("삼각형 %d개 > %d" % [tris, max_tris])
	if tris != int(info.get("tris", -1)):
		problems.append("목록의 삼각형 수(%s)와 다름" % info.get("tris"))
	if absf(aabb.position.y) > 0.005:
		problems.append("바닥 높이 %.3f" % aabb.position.y)
	if String(info.get("anchor", "center")) == "center":
		if absf(center.x) > 0.05 or absf(center.z) > 0.05:
			problems.append("원점이 가운데가 아님 (%.2f, %.2f)" % [center.x, center.z])
	elif not (aabb.position.x <= 0.0 and aabb.end.x >= 0.0 and aabb.position.z <= 0.0 and aabb.end.z >= 0.0):
		problems.append("원점(기둥)이 모델 밖에 있음")
	var size: Array = info.get("size_m", [0, 0, 0])
	if (aabb.size - Vector3(size[0], size[1], size[2])).length() > 0.05:
		problems.append("목록 크기 %s와 다름" % str(size))
	# 정면 기준: 다리가 곧은 인물은 엉덩이 축(다리 노드 위치), 나머지는 모델 가운데.
	# (손수레·드론처럼 앞에 든 물건이 있으면 모델 가운데가 앞으로 쏠리기 때문)
	var ref_z := center.z
	if info.has("hip_m"):
		var legs_z := []
		for leg_name in ["LegL", "LegR"]:
			var leg := root.find_child(leg_name, true, false) as Node3D
			if leg != null:
				legs_z.append((root.global_transform.affine_inverse() * leg.global_transform).origin.z)
		if not legs_z.is_empty():
			ref_z = _avg(legs_z)
	if front_mat != "" and (front_z.is_empty() or _avg(front_z) >= ref_z - 0.01):
		problems.append("정면(%s)이 -Z 쪽이 아님" % front_mat)
	for n in info.get("nodes", []):
		if root.find_child(String(n), true, false) == null:
			problems.append("%s 노드 없음" % n)
	if info.has("hip_m"):
		problems.append_array(_check_legs(root, float(info["hip_m"])))
	var tex := load(String(info["thumb"])) as Texture2D
	if tex == null or tex.get_size() != Vector2(THUMB_PX, THUMB_PX):
		problems.append("썸네일 없음 또는 크기 다름")
	root.free()
	print("%-18s tris=%4d/%4d  size(WxHxD)=%5.2f x %5.2f x %5.2f m  %s" % [
		id, tris, max_tris, aabb.size.x, aabb.size.y, aabb.size.z,
		"OK" if problems.is_empty() else "FAIL: " + ", ".join(problems)])
	return problems.is_empty()


## 보행자 다리: 노드 원점이 엉덩이 높이이고, 다리 메시가 거기서 바닥까지 내려오며, 왼다리가 -X 쪽인지.
func _check_legs(root: Node3D, hip: float) -> Array[String]:
	var out: Array[String] = []
	var xs := {}
	for leg_name in ["LegL", "LegR"]:
		var leg := root.find_child(leg_name, true, false) as MeshInstance3D
		if leg == null:
			continue
		xs[leg_name] = leg.position.x
		if absf(leg.position.y - hip) > 0.01:
			out.append("%s 축 높이 %.2f (엉덩이 %.2f)" % [leg_name, leg.position.y, hip])
		var lo := INF
		var hi := -INF
		for s in leg.mesh.get_surface_count():
			for v in leg.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
		if absf(leg.position.y + lo) > 0.005 or hi > 0.01:
			out.append("%s 메시가 엉덩이~바닥이 아님" % leg_name)
	if xs.size() == 2 and not (float(xs["LegL"]) < 0.0 and float(xs["LegR"]) > 0.0):
		out.append("LegL이 -X(왼쪽)가 아님")
	return out


func _avg(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var t := 0.0
	for x in xs:
		t += x
	return t / xs.size()
