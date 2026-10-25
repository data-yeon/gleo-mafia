## 아래쪽 앱 독: 양 끝은 공조(운전석·조수석 온도), 가운데는 앱 아이콘.
class_name PleosDock
extends PanelContainer

signal app_pressed(app: String)

const APPS := [
	["home", "홈"], ["nav", "내비"], ["music", "미디어"], ["phone", "전화"],
	["gleo", "Gleo"], ["apps", "앱마켓"], ["settings", "설정"],
]

var _active := "nav"
var _buttons := {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 104)
	var sb := PleosTheme.box(PleosTheme.SURFACE, 0, 0)
	sb.border_color = PleosTheme.LINE
	sb.border_width_top = 1
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	row.add_child(_climate("fan", "22.0°", true))
	var left_fill := Control.new()
	left_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_fill)
	var apps := HBoxContainer.new()
	apps.add_theme_constant_override("separation", 22)
	apps.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(apps)
	for a in APPS:
		apps.add_child(_app_button(a[0], a[1]))
	var right_fill := Control.new()
	right_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_fill)
	row.add_child(_climate("seat", "22.0°", false))
	set_active(_active)


func set_active(app: String) -> void:
	_active = app
	for k in _buttons.keys():
		var b: PanelContainer = _buttons[k]
		var on: bool = k == app
		b.add_theme_stylebox_override("panel", PleosTheme.box(
				PleosTheme.ACCENT_SOFT if on else Color(0, 0, 0, 0), 20, 12))


func _app_button(icon: String, label_text: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			app_pressed.emit(icon))
	var ic := PleosIcon.make(icon, 40, PleosTheme.ACCENT if icon == "nav" else PleosTheme.TEXT_2)
	box.add_child(ic)
	col.add_child(box)
	var l := PleosTheme.label(label_text, "Small")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	_buttons[icon] = box
	return col


func _climate(icon: String, temp: String, left: bool) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 36 if left else 0)
	m.add_theme_constant_override("margin_right", 0 if left else 36)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)
	var ic := PleosIcon.make(icon, 34, PleosTheme.TEXT_2)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := PleosTheme.label(temp, "Title")
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if left:
		row.add_child(ic)
		row.add_child(t)
	else:
		row.add_child(t)
		row.add_child(ic)
	return m
