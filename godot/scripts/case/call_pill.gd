## 회신 전화 알약(지도 위쪽 가운데, 폰 통화 화면 모양): 연결 중(뚜르르) → 통화 중 → 통화 종료.
## 통화 중에는 제보자 프로필(성씨 원, 자칭 직업 색), 이름, "자칭 직업 · 장소", 통화 시간, 말소리 막대를 보여 준다.
## 진술 자막은 Gleo 바에 나온다(CaseDirector가 연결이 되면 말한다).
class_name CallPill
extends PanelContainer

const BG := Color("1f2633")
const CIRCLE_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR.a *= smoothstep(0.5, 0.475, length(UV - vec2(0.5)));\n}\n"

var phase := ""                   # dialing | talking | ended | ""
var _t := 0.0
var _talk_t := 0.0
var _avatar: PanelContainer
var _portrait: TextureRect        # 제보자 얼굴(있을 때만). 없으면 이니셜 원
var _initial: Label
var _name: Label
var _sub: Label
var _time: Label
var _bars: Control
var _color := Color.GRAY


func _ready() -> void:
	add_theme_stylebox_override("panel", PleosTheme.box(BG, 999, 12, true))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(400, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	_avatar = PanelContainer.new()
	_avatar.custom_minimum_size = Vector2(76, 76)
	row.add_child(_avatar)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false
	var sh := Shader.new()                                           # 얼굴 그림을 동그랗게 보이게 한다
	sh.code = CIRCLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_portrait.material = mat
	_avatar.add_child(_portrait)
	_initial = PleosTheme.label("", "BodyStrong")
	_initial.add_theme_color_override("font_color", Color.WHITE)
	_initial.add_theme_font_size_override("font_size", 26)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar.add_child(_initial)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_name = PleosTheme.label("", "BodyStrong")
	_name.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(_name)
	_sub = PleosTheme.label("", "Small")
	_sub.add_theme_color_override("font_color", Color("aab3c5"))
	col.add_child(_sub)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(46, 40)
	_bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bars.draw.connect(_draw_bars)
	row.add_child(_bars)
	_time = PleosTheme.label("", "Caption")
	_time.add_theme_color_override("font_color", Color("7ee2a8"))
	_time.custom_minimum_size = Vector2(56, 0)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time)
	visible = false


## 프로필(색 원 + 이니셜, 있으면 얼굴 그림)과 이름·부제를 채운다. p: {initial, color, name, sub, portrait(선택)}
func _apply_profile(p: Dictionary) -> void:
	_color = p.get("color", Color.GRAY)
	var tex = p.get("portrait", null)
	if tex != null:      # 얼굴 그림은 색 원 없이 그림 자체가 동그랗게 보인다
		_avatar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		_avatar.add_theme_stylebox_override("panel", PleosTheme.box(_color, 999, 0))
	_initial.text = String(p.get("initial", "?"))
	_name.text = String(p.get("name", ""))
	_sub.text = String(p.get("sub", ""))
	_portrait.texture = tex as Texture2D
	_portrait.visible = tex != null
	_initial.visible = tex == null


## p: {initial, color, name, sub, portrait(선택)}
func show_call(p: Dictionary) -> void:
	_apply_profile(p)
	_t = 0.0
	_talk_t = 0.0
	set_phase("dialing")
	visible = true
	modulate.a = 1.0


## 연결되면 받은 사람(제보자)을 보여 주고 통화 중으로
func connect_to(p: Dictionary) -> void:
	_apply_profile(p)
	set_phase("talking")


func set_phase(ph: String) -> void:
	phase = ph
	match ph:
		"dialing":
			_time.text = "연결 중"
			_time.add_theme_color_override("font_color", Color("aab3c5"))
		"talking":
			_talk_t = 0.0
			_time.add_theme_color_override("font_color", Color("7ee2a8"))
		"ended":
			_time.text = "통화 종료"
			_time.add_theme_color_override("font_color", Color("ff8a8a"))
	_bars.queue_redraw()


func hide_call() -> void:
	phase = ""
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	match phase:
		"dialing":
			# 프로필이 숨 쉬듯 깜빡인다
			_avatar.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 7.0))
		"talking":
			_avatar.modulate.a = 1.0
			_talk_t += delta
			# 실제 통화처럼 시간이 빨리 간다(게임 시간 느낌)
			var sec := int(_talk_t * 4.0) + 3
			_time.text = "%d:%02d" % [sec / 60, sec % 60]
		"ended":
			modulate.a = maxf(0.0, modulate.a - delta * 1.2)
			if modulate.a <= 0.0:
				hide_call()
	_bars.queue_redraw()


func _draw_bars() -> void:
	var n := 5
	var w := 5.0
	var gap := (_bars.size.x - n * w) / float(n - 1)
	for i in n:
		var h := 6.0
		if phase == "talking":
			h = 8.0 + 24.0 * absf(sin(_t * (5.0 + i * 1.7) + i))
		var x := i * (w + gap)
		var y := (_bars.size.y - h) / 2.0
		_bars.draw_rect(Rect2(x, y, w, h), Color(_color, 0.95) if phase == "talking" else Color("4a5466"))
