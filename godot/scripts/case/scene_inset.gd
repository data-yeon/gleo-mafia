## 현장 3D 확대도: 지도 가운데에 띄우는 작은 3D 장면(실제 내비의 교차로 확대도 문법).
## - 회신 전화(중간 크기): 장소 건물만 보이다가(따르릉) 연결되면 제보자가 건물 앞에 나타나 통화한다.
##   제보자는 '자칭 직업' 모습이다(진짜 정체와 무관). 익명은 어두운 실루엣, 터널은 화면 잡음.
## - 출동(크게): 경찰차가 들어와 서고 경광등이 깜빡인다 → 현장 진입(카메라가 다가간다) →
##   검거(수갑 찬 범인 + "검거") / 헛걸음(제보자 그대로 + "?").
## - 결말(크게): 놓친 범인은 ATM 앞에서 돈 가방을 들고 달아나고, 다 잡았으면 범인이 경찰차 옆에 선다.
## 인물·소품은 assets/models/figures(Blender 세션: 자칭 직업 8종 + 익명, 범인 2자세, ATM·수갑·폴리스 라인·돈 가방)를 쓰고,
## 없으면 보행자 모델과 단순 도형으로 대신한다.
class_name SceneInset
extends PanelContainer

const SIZE_CALL := Vector2i(640, 340)
const SIZE_BIG := Vector2i(960, 520)
## Blender 인물이 없을 때 대신 쓰는 보행자 모델(자칭 직업 → 보행자)
const FALLBACK := {"COP": "ped_suit", "GUARD": "ped_suit", "TAXI": "ped_suit", "VENDOR": "ped_casual",
		"DRONE": "ped_casual", "RIDER": "ped_casual", "LOCAL": "ped_umbrella", "GOSSIP": "ped_umbrella",
		"ANON": "ped_casual", "CULPRIT_RUN": "ped_casual", "CULPRIT_CUFFED": "ped_casual"}
const COL_GROUND := Color("d6dbe3")
const COL_ROAD := Color("aab1bc")
const COL_WALK := Color("eceef2")
const COL_SKY := Color("e6ebf3")

var mode := ""                    # call | raid | ending | ""
var phase := ""                   # dialing | talking | go | entry | hit | miss | caught | escape
var big := false

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _title: Label
var _sub: Label
var _noise: ColorRect
var _figure: Node3D
var _figure_pos := Vector3(2.6, 0, 1.4)
var _police: Node3D
var _runner: Node3D
var _mark: Label3D
var _bars: Array[MeshInstance3D] = []
var _t := 0.0
var _phase_t := 0.0
var _go_s := 2.2
var _cam_a: Array = [Vector3.ZERO, Vector3.ZERO]    # [위치, 바라볼 곳]
var _cam_b: Array = [Vector3.ZERO, Vector3.ZERO]
var _cam_k := 1.0
var _cam_dur := 1.0
var _close_in := -1.0
var _bld_h := 8.0
var _bld_w := 12.0


func _ready() -> void:
	add_theme_stylebox_override("panel", PleosTheme.box(Color("1f2633"), 22, 6, true))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	var frame := Control.new()
	frame.clip_contents = true
	col.add_child(frame)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(cont)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	cont.add_child(_vp)
	_noise = ColorRect.new()
	_noise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = h(floor(UV * vec2(200.0, 110.0)) + floor(TIME * 24.0));
	float line = step(0.96, h(vec2(floor(UV.y * 60.0), floor(TIME * 10.0))));
	COLOR = vec4(vec3(n), 0.16 + line * 0.3);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_noise.material = mat
	_noise.visible = false
	frame.add_child(_noise)
	var cap := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		cap.add_theme_constant_override(side, 18)
	for side2 in ["margin_top", "margin_bottom"]:
		cap.add_theme_constant_override(side2, 10)
	col.add_child(cap)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	cap.add_child(row)
	_title = PleosTheme.label("", "BodyStrong")
	_title.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(_title)
	_sub = PleosTheme.label("", "Small")
	_sub.add_theme_color_override("font_color", Color("aab3c5"))
	row.add_child(_sub)
	_apply_size(false)
	visible = false


func _apply_size(is_big: bool) -> void:
	big = is_big
	var s := SIZE_BIG if is_big else SIZE_CALL
	_vp.size = s
	var frame: Control = _vp.get_parent().get_parent()
	frame.custom_minimum_size = Vector2(s)
	_title.add_theme_font_size_override("font_size", 26 if is_big else 22)
	reset_size()


# ---------------------------------------------------------------- 장면

## place: 팩의 장소 사전(name, kind). 장소 건물과 바닥·길을 새로 깐다.
func _build(place: Dictionary) -> void:
	if _world != null:
		_world.queue_free()
	_figure = null
	_police = null
	_runner = null
	_mark = null
	_bars.clear()
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_light_color = COL_SKY
	env.fog_density = 0.005
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.34
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.5
	sun.rotation_degrees = Vector3(-52, 32, 0)
	_world.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_world.add_child(_cam)
	_box(Vector3(160, 0.02, 160), Vector3(0, -0.01, 0), COL_GROUND)
	_box(Vector3(160, 0.06, 9.0), Vector3(0, 0.0, 7.5), COL_ROAD)
	_box(Vector3(160, 0.14, 3.0), Vector3(0, 0.05, 1.6), COL_WALK)
	for i in range(-8, 9):
		_box(Vector3(2.4, 0.07, 0.18), Vector3(i * 5.0, 0.01, 7.5), Color.WHITE)
	# 장소 건물: 정면(-Z)이 카메라(+Z) 쪽을 보게 돌리고, 정면이 z=0에 오게 놓는다
	var id := Landmarks.id_for(String(place.get("name", "")), String(place.get("kind", "")))
	var w := 12.0
	_bld_h = 8.0
	if id != "":
		var bld := Landmarks.instantiate(id)
		if bld != null:
			var sz := Landmarks.size_of(id)
			w = sz.x
			_bld_h = sz.y
			bld.rotation_degrees.y = 180.0
			bld.position = Vector3(0, 0, -sz.z / 2.0)
			_world.add_child(bld)
	else:
		_box(Vector3(12, 8, 10), Vector3(0, 4, -5), Color("dfe3ea"))
	_bld_w = w
	_figure_pos = Vector3(minf(w * 0.32, 4.0) + 1.0, 0.08, 2.4)


## 건물과 사람이 함께 들어오게 맞춘 카메라 [위치, 바라볼 곳]. wide면 길(경찰차)까지 넓게.
func _frame(wide: bool) -> Array:
	var h := minf(_bld_h, 14.0)
	if not wide:
		# 회신 전화·결말: 사람이 크게, 건물은 뒤에 걸치게
		var t2 := Vector3(_figure_pos.x * 0.7, 1.3 + h * 0.16, _figure_pos.z * 0.5)
		var d2 := clampf(maxf(_bld_w * 0.62, h * 0.85), 7.0, 14.0)
		return [t2 + Vector3(0.32, 0.3, 1.0).normalized() * d2, t2]
	var target := Vector3(_figure_pos.x * 0.45, h * 0.32 + 0.6, 2.6)
	var dist := clampf(maxf(_bld_w * 0.95, h * 1.25), 9.0, 22.0) * 1.45
	var dir := Vector3(0.36, 0.34, 1.0).normalized()
	return [target + dir * dist, target]


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mi.material_override = m
	mi.position = pos
	_world.add_child(mi)
	return mi


## 인물: Blender 인물(figures)이 있으면 그것, 없으면 보행자 모델. dark면 어두운 실루엣.
func _person(key: String, dark := false) -> Node3D:
	var n: Node3D = AdasAssets.instance(key)
	if n == null:
		n = AdasAssets.instance(String(FALLBACK.get(key, "ped_casual")))
	if n == null:
		n = Node3D.new()
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.7
		mi.mesh = cm
		mi.position.y = 0.85
		n.add_child(mi)
	if dark or (key == "ANON" and not AdasAssets.has("ANON")):
		_tint(n, Color("2b3240"))
	return n


func _tint(root: Node, col: Color) -> void:
	if root is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		(root as MeshInstance3D).material_override = m
	for c in root.get_children():
		_tint(c, col)


func _label3d(text: String, col: Color, pos: Vector3, size := 72) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = PleosTheme.font(true)
	l.font_size = size
	l.outline_size = 18
	l.modulate = col
	l.outline_modulate = Color.WHITE
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.012
	l.position = pos
	_world.add_child(l)
	return l


func _set_cam(pos: Vector3, look: Vector3, dur := 0.0) -> void:
	_cam_a = [_cam.position, _cam_look()] if dur > 0.0 else [pos, look]
	_cam_b = [pos, look]
	_cam_k = 0.0 if dur > 0.0 else 1.0
	_cam_dur = maxf(dur, 0.01)
	_apply_cam()


func _cam_look() -> Vector3:
	return _cam.position - _cam.global_transform.basis.z * 10.0 if _cam.is_inside_tree() else Vector3.ZERO


func _apply_cam() -> void:
	var k := ease(_cam_k, -2.0)
	var p: Vector3 = (_cam_a[0] as Vector3).lerp(_cam_b[0], k)
	var lk: Vector3 = (_cam_a[1] as Vector3).lerp(_cam_b[1], k)
	_cam.position = p
	if p.distance_to(lk) > 0.01:
		_cam.look_at_from_position(p, lk, Vector3.UP)


func _caption(title: String, sub: String) -> void:
	_title.text = title
	_sub.text = sub
	_sub.visible = sub != ""


func _open(is_big: bool) -> void:
	_apply_size(is_big)
	_close_in = -1.0
	_t = 0.0
	_phase_t = 0.0
	if not visible:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.22)
	visible = true


## sec초 뒤에 닫는다(0이면 바로).
func close(sec := 0.0) -> void:
	if not visible:
		return
	if sec <= 0.0:
		_hide_now()
	else:
		_close_in = sec


func _hide_now() -> void:
	visible = false
	mode = ""
	phase = ""
	_noise.visible = false
	if _world != null:
		_world.queue_free()
		_world = null


# ---------------------------------------------------------------- 회신 전화

## 연결 중: 건물만 보이고 "따르릉".
func show_call(place: Dictionary, label: String) -> void:
	mode = "call"
	phase = "dialing"
	_build(place)
	_open(false)
	_noise.visible = false
	_mark = _label3d("따르릉…", Color("4a5466"), _figure_pos + Vector3(0, 2.4, 0), 56)
	var fr := _frame(false)
	_set_cam(fr[0], fr[1])
	_caption("%s · 회신 전화" % label, "연결 중…")


## 연결됨: 제보자(자칭 직업 모습)가 건물 앞에 나타나 통화한다. role: 자칭 직업 키, ""=익명, obscured=잡음.
func connect_call(role: String, who: String, obscured: bool) -> void:
	if mode != "call" or _world == null:
		return
	phase = "talking"
	_phase_t = 0.0
	var key := "ANON" if role == "" or obscured else role
	_figure = _person(key, obscured)
	_figure.position = _figure_pos
	_figure.rotation_degrees.y = 160.0
	_world.add_child(_figure)
	if _mark != null:
		_mark.text = "…"
		_mark.modulate = Color("2f6bff")
	_noise.visible = obscured
	_sub.text = who


# ---------------------------------------------------------------- 출동

## 출동: 제보자(자칭 직업)가 서 있는 장소로 경찰차가 들어온다(go_s초).
func show_raid(place: Dictionary, label: String, role: String, go_s: float) -> void:
	mode = "raid"
	phase = "go"
	_go_s = go_s
	_build(place)
	_open(true)
	_figure = _person(role if role != "" else "ANON")
	_figure.position = _figure_pos
	_figure.rotation_degrees.y = 180.0
	_world.add_child(_figure)
	_police = AdasAssets.instance("police_car")
	if _police == null:
		_police = AdasAssets.box_vehicle(Color.WHITE)
	_police.rotation_degrees.y = -90.0
	_police.position = Vector3(-34.0, 0, 7.0)
	_world.add_child(_police)
	_setup_bars(_police)
	var fr := _frame(true)
	_set_cam(fr[0], fr[1])
	_caption("%s · 출동" % label, "기동대가 가는 중…")


## 현장 진입: 카메라가 사람 쪽으로 천천히 다가간다.
func enter() -> void:
	if mode != "raid":
		return
	phase = "entry"
	_phase_t = 0.0
	var fp := _figure_pos
	_set_cam(fp + Vector3(3.2, 1.9, 6.2), fp + Vector3(-0.6, 1.1, 0), 1.1)
	_sub.text = "현장 진입…"


## 결과: 검거면 수갑 찬 범인 + "검거", 헛걸음이면 "?". truth: 밝혀진 정체 문구("사칭범", "진짜 노점상")
func result(hit: bool, truth: String) -> void:
	if mode != "raid" or _world == null:
		return
	phase = "hit" if hit else "miss"
	_phase_t = 0.0
	if hit:
		var cuffed := _person("CULPRIT_CUFFED")
		cuffed.position = _figure.position
		cuffed.rotation_degrees.y = 180.0
		if not AdasAssets.has("CULPRIT_CUFFED"):
			cuffed.rotation_degrees.x = 10.0
			_tint(cuffed, Color("3a3f4b"))
		_figure.queue_free()
		_figure = cuffed
		_world.add_child(_figure)
		_label3d("검거", PleosTheme.DANGER, _figure_pos + Vector3(0, 2.6, 0), 96)
		# 폴리스 라인: 사람 앞을 가로지른다
		var tape := AdasAssets.instance("police_tape")
		if tape != null:
			tape.position = _figure_pos + Vector3(-0.6, 0, 1.6)
			tape.rotation_degrees.y = 8.0
			_world.add_child(tape)
		_sub.text = "검거 · %s" % truth
	else:
		_label3d("?", Color("6b7280"), _figure_pos + Vector3(0, 2.5, 0), 110)
		_sub.text = "헛걸음 · %s" % truth
	close(2.2)


# ---------------------------------------------------------------- 결말

## escape: 놓친 범인이 ATM 앞에서 돈 가방을 들고 달아난다. 아니면 범인이 경찰차 옆에 선다(다 잡음).
func show_ending(place: Dictionary, label: String, escape: bool, sec: float) -> void:
	mode = "ending"
	phase = "escape" if escape else "caught"
	_build(place)
	_open(true)
	if escape:
		var atm := AdasAssets.instance("atm")
		if atm == null:
			atm = Node3D.new()
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.4, 2.2, 1.0)
			b.mesh = bm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("2f6bff")
			b.material_override = m
			b.position.y = 1.1
			atm.add_child(b)
		atm.rotation_degrees.y = 180.0
		atm.position = _figure_pos + Vector3(-3.0, 0, -0.2)
		_world.add_child(atm)
		_label3d("ATM", Color("2f6bff"), atm.position + Vector3(0, 2.9, 0), 54)
		_runner = _person("CULPRIT_RUN", not AdasAssets.has("CULPRIT_RUN"))
		_runner.position = atm.position + Vector3(1.0, 0, 1.2)
		_runner.rotation_degrees.y = -90.0
		_world.add_child(_runner)
		_label3d("₩", Color("e8930c"), _runner.position + Vector3(0, 2.3, 0), 64)
		var fr := _frame(false)
		_set_cam(fr[0], fr[1])
		_caption("인출 완료 · %s" % label, "놈이 돈을 찾아 달아나요")
	else:
		_police = AdasAssets.instance("police_car")
		if _police != null:
			_police.rotation_degrees.y = -90.0
			_police.position = Vector3(-1.5, 0, 6.5)
			_world.add_child(_police)
			_setup_bars(_police)
		_figure = _person("CULPRIT_CUFFED", not AdasAssets.has("CULPRIT_CUFFED"))
		_figure.position = Vector3(3.2, 0.08, 4.4)
		_figure.rotation_degrees.y = 180.0
		_world.add_child(_figure)
		_label3d("검거 완료", PleosTheme.DANGER, _figure.position + Vector3(0, 2.6, 0), 80)
		var fr2 := _frame(true)
		_set_cam(fr2[0], fr2[1])
		_caption("검거 완료 · %s" % label, "수고하셨어요, 형사님")
	close(sec)


# ---------------------------------------------------------------- 경광등

func _setup_bars(car: Node3D) -> void:
	_bars.clear()
	for nm in ["LightBarRed", "LightBarBlue"]:
		var bar := car.find_child(nm, true, false) as MeshInstance3D
		if bar == null or bar.mesh == null:
			continue
		var base := bar.mesh.surface_get_material(0) as StandardMaterial3D
		if base == null:
			continue
		var mat := base.duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = base.albedo_color
		bar.material_override = mat
		bar.set_meta("base_color", base.albedo_color)
		_bars.append(bar)


func _flash_bars() -> void:
	var on := int(_t * 7.0) % 2 == 0
	for i in _bars.size():
		var lit := on if i == 0 else not on
		var mat := _bars[i].material_override as StandardMaterial3D
		var base: Color = _bars[i].get_meta("base_color")
		mat.emission_energy_multiplier = 1.6 if lit else 0.0
		mat.albedo_color = base if lit else base.darkened(0.45)


# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if not visible or _world == null:
		return
	_t += delta
	_phase_t += delta
	if _cam_k < 1.0:
		_cam_k = minf(1.0, _cam_k + delta / _cam_dur)
		_apply_cam()
	if not _bars.is_empty():
		_flash_bars()
	match phase:
		"talking":
			if _figure != null:
				_figure.position.y = _figure_pos.y + 0.03 * absf(sin(_t * 6.0))
				# 자칭 드론 유튜버: 머리 위 드론이 떠서 흔들린다
				var drone := _figure.find_child("Drone", true, false) as Node3D
				if drone != null:
					if not drone.has_meta("y0"):
						drone.set_meta("y0", drone.position.y)
					drone.position.y = float(drone.get_meta("y0")) + 0.12 * sin(_t * 3.0)
					drone.rotation.y = 0.25 * sin(_t * 1.3)
			if _mark != null:
				_mark.text = ["…", "‥", "."][int(_t * 3.0) % 3]
		"dialing":
			if _mark != null:
				_mark.modulate.a = 0.5 + 0.5 * sin(_t * 8.0)
		"go":
			if _police != null:
				var k := clampf(_phase_t / _go_s, 0.0, 1.0)
				_police.position.x = lerpf(-34.0, _figure_pos.x - 6.5, ease(k, 0.35))
		"escape":
			if _runner != null:
				_runner.position.x += delta * 2.4
				_runner.position.y = 0.08 + 0.12 * absf(sin(_t * 12.0))
	if _close_in > 0.0:
		_close_in -= delta
		if _close_in <= 0.0:
			_hide_now()
