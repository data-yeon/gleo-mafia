## 위쪽 상태바: 왼쪽은 속도·자율주행 상태, 오른쪽은 통신·배터리·시각.
class_name PleosStatusBar
extends PanelContainer

signal playback_pressed

var _speed: Label
var _mode_chip: PanelContainer
var _mode_label: Label
var _clock: Label
var _speed_label_x2: Button
var _timer := 0.0
var _clock_unix := -1.0               # 0 이상이면 이 시각(게임 시계)을 보여준다


func _ready() -> void:
	custom_minimum_size = Vector2(0, 64)
	add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.BG, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	row.add_child(_spacer(28))

	_speed = PleosTheme.label("0", "Title")
	_speed.add_theme_font_size_override("font_size", 34)
	row.add_child(_speed)
	var unit := PleosTheme.label("km/h", "Caption")
	unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(unit)

	_mode_chip = PanelContainer.new()
	_mode_chip.theme_type_variation = "Chip"
	_mode_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	_mode_chip.add_child(chip_row)
	chip_row.add_child(PleosIcon.make("wheel", 22, PleosTheme.ACCENT))
	_mode_label = PleosTheme.label("자율주행", "AccentLabel")
	_mode_label.add_theme_font_size_override("font_size", 19)
	chip_row.add_child(_mode_label)
	row.add_child(_mode_chip)

	_speed_label_x2 = Button.new()
	_speed_label_x2.flat = true
	_speed_label_x2.focus_mode = Control.FOCUS_NONE
	_speed_label_x2.add_theme_font_override("font", PleosTheme.font(false))
	_speed_label_x2.add_theme_font_size_override("font_size", 18)
	_speed_label_x2.add_theme_color_override("font_color", PleosTheme.TEXT_3)
	_speed_label_x2.pressed.connect(func(): playback_pressed.emit())
	row.add_child(_speed_label_x2)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)

	for ic in ["signal", "wifi"]:
		row.add_child(PleosIcon.make(ic, 26, PleosTheme.TEXT_2))
	row.add_child(PleosIcon.make("battery", 30, PleosTheme.TEXT_2))
	var pct := PleosTheme.label("82%", "Caption")
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)
	_clock = PleosTheme.label("", "BodyStrong")
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_clock)
	row.add_child(_spacer(28))
	_update_clock()


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


func set_speed(kmh: float) -> void:
	_speed.text = str(roundi(kmh))


func set_autonomous(on: bool) -> void:
	_mode_chip.visible = on


## "3x Speed"처럼 데모 배속 표시. 빈 문자열이면 숨김.
func set_playback_label(text: String) -> void:
	_speed_label_x2.text = text


## 게임 시계(유닉스 시각, 지역 시간대 보정 전)를 보여준다. 음수면 시스템 시각.
func set_clock_unix(unix: float) -> void:
	_clock_unix = unix
	_update_clock()


func _process(delta: float) -> void:
	_timer += delta
	if _timer > 5.0:
		_timer = 0.0
		_update_clock()


func _update_clock() -> void:
	var t := Time.get_datetime_dict_from_system()
	if _clock_unix >= 0.0:
		var bias: float = Time.get_time_zone_from_system()["bias"]
		t = Time.get_datetime_dict_from_unix_time(int(_clock_unix + bias * 60.0))
	var h := int(t["hour"])
	var ampm := "오전" if h < 12 else "오후"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	_clock.text = "%s %d:%02d" % [ampm, h12, int(t["minute"])]
