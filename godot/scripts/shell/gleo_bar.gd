## Gleo 음성 바: 지도 아래쪽 가운데에 떠 있는 알약 모양. 오브 + 자막 + 버튼.
## 상태: idle(안내 문구) / listening(듣는 중) / speaking(말하는 중)
## 버튼(set_actions)은 사건 제안 수락, 정리, 힌트처럼 Gleo에게 하는 말을 대신한다. 음성 인식은 단계 F.
class_name GleoBar
extends PanelContainer

signal pressed
signal action(id: String)
signal spoke                     # 새로 말할 때마다 (지도 위 가장자리 빛남 연출)
signal line_shown                # 자막이 끝까지 다 나왔을 때

const CPS := 45.0                # 자막 타자 속도(글자/초)
const WHO_COLORS := [["★", Color("b45309")], ["본부", Color("b42318")], ["현장", Color("b42318")]]

var state := "idle"
var _orb: PleosIcon
var _who: Label
var _text: Label
var _mic: PleosIcon
var _actions: HBoxContainer
var items := []                  # 지금 떠 있는 버튼 [[라벨, id, 변형], ...]
var instant := false             # 테스트·자동 실행: 타자 효과 없이 바로
var typing := false
var _shown := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.SURFACE, 999, 14, true))
	custom_minimum_size = Vector2(480, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	_orb = PleosIcon.make("gleo", 52, PleosTheme.ACCENT)
	row.add_child(_orb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_who = PleosTheme.label("Gleo", "AccentLabel")
	_who.add_theme_font_size_override("font_size", 17)
	col.add_child(_who)
	_text = PleosTheme.label("", "Body")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(340, 0)
	col.add_child(_text)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_actions)
	_mic = PleosIcon.make("mic", 34, PleosTheme.TEXT_3)
	_mic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_mic)
	show_idle()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if typing:
			finish()            # 타자 중에 누르면 자막을 끝까지
		else:
			pressed.emit()


func _process(delta: float) -> void:
	if not typing:
		return
	_shown += delta * CPS
	if int(_shown) >= _text.get_total_character_count():
		finish()
	else:
		_text.visible_characters = int(_shown)


## 자막을 끝까지 보여 준다.
func finish() -> void:
	if not typing:
		return
	typing = false
	_text.visible_characters = -1
	line_shown.emit()


func show_idle(hint := "\"글레오\"라고 부르거나 눌러서 말해 보세요") -> void:
	state = "idle"
	typing = false
	_text.visible_characters = -1
	_who.remove_theme_color_override("font_color")
	_who.text = "Gleo"
	_text.text = hint
	_text.theme_type_variation = "Caption"
	_mic.color = PleosTheme.TEXT_3


func show_listening(partial := "듣고 있어요…") -> void:
	state = "listening"
	_who.text = "듣는 중"
	_text.text = partial
	_text.theme_type_variation = "Body"
	_mic.color = PleosTheme.ACCENT


## who: 말하는 사람(Gleo, 제보자 이름 등)
func show_speaking(text: String, who := "Gleo") -> void:
	var fresh := text != _text.text
	if fresh:
		spoke.emit()
	state = "speaking"
	_who.text = who
	# 화자 색: 본부 무전·현장은 빨강, 현장 확인(★)은 주황, 제보자(①…)는 회색, Gleo는 파랑
	var col: Variant = null
	for kc in WHO_COLORS:
		if who.contains(String(kc[0])):
			col = kc[1]
			break
	if col == null and not who.begins_with("Gleo"):
		col = PleosTheme.TEXT_2
	if col == null:
		_who.remove_theme_color_override("font_color")
	else:
		_who.add_theme_color_override("font_color", col)
	_text.text = text
	if fresh and not instant:
		typing = true
		_shown = 0.0
		_text.visible_characters = 0
	elif fresh:
		typing = false
		_text.visible_characters = -1
	_text.theme_type_variation = "Body"
	_mic.color = PleosTheme.TEXT_3


func last_text() -> String:
	return _text.text


## 버튼 목록: [[라벨, id, 변형("PrimaryButton" 등, 생략 가능)], ...]. 빈 배열이면 숨긴다.
func set_actions(list: Array) -> void:
	items = list
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for it in list:
		var b := Button.new()
		b.text = String(it[0])
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = String(it[2]) if it.size() > 2 else "Button"
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 20)
		var id := String(it[1])
		b.pressed.connect(func(): action.emit(id))
		_actions.add_child(b)
