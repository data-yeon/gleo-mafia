## 행동 옵션 카드: Gleo 경로 옵션 카드처럼, 고른 장소에서 할 일을 작은 카드로 쌓아 두고 하나 고른 뒤 실행한다.
## 옵션: 탐문(통화 1번) / 잠복 예약(지날 때) / 경유지 잠복(+N분 · 통화 1번). 아래에 [실행]과 [출동](두 번 눌러 확인).
## show_actions({id, name, sub, thumb, quote, chips: [[글, 색]], options: [{key, title, value, desc, enabled}],
##               primary: {key: 라벨}, can_raid, raid_armed})
class_name ActionCard
extends PanelContainer

signal action(act: String, place_id: int)   # call / stakeout / waypoint / raid / close

var place_id := -1
var _selected := ""
var _data := {}
var _key := ""
var _num: Label
var _name: Label
var _sub: Label
var _thumb: TextureRect
var _chips: HFlowContainer
var _quote: Label
var _opts: VBoxContainer
var _primary: Button
var _raid: Button


func _ready() -> void:
	theme_type_variation = "Card"
	custom_minimum_size = Vector2(460, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.TEXT, 999, 8))
	badge.custom_minimum_size = Vector2(48, 48)
	_num = PleosTheme.label("", "Title")
	_num.add_theme_color_override("font_color", Color.WHITE)
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(_num)
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_name = PleosTheme.label("", "Title")
	titles.add_child(_name)
	_sub = PleosTheme.label("", "Caption")
	titles.add_child(_sub)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(72, 72)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_thumb)
	var close := Button.new()
	close.text = "목록"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 46)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 19)
	close.pressed.connect(func(): action.emit("close", place_id))
	head.add_child(close)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 8)
	_chips.add_theme_constant_override("v_separation", 6)
	col.add_child(_chips)
	_quote = PleosTheme.label("", "Body")
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.custom_minimum_size = Vector2(400, 0)
	col.add_child(_quote)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 8)
	col.add_child(_opts)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_primary = Button.new()
	_primary.theme_type_variation = "PrimaryButton"
	_primary.custom_minimum_size = Vector2(0, 62)
	_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary.size_flags_stretch_ratio = 2.0
	_primary.focus_mode = Control.FOCUS_NONE
	_primary.pressed.connect(func():
		if _selected != "":
			action.emit(_selected, place_id))
	row.add_child(_primary)
	_raid = Button.new()
	_raid.theme_type_variation = "DangerButton"
	_raid.custom_minimum_size = Vector2(0, 62)
	_raid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_raid.focus_mode = Control.FOCUS_NONE
	_raid.pressed.connect(func(): action.emit("raid", place_id))
	row.add_child(_raid)


func show_actions(d: Dictionary) -> void:
	if int(d.get("id", -1)) != place_id:
		_selected = ""
	_data = d
	place_id = int(d.get("id", -1))
	# 고른 옵션이 더는 안 되면 첫 번째로 되는 옵션
	var keys: Array[String] = []
	for o in d.get("options", []):
		if bool(o["enabled"]):
			keys.append(String(o["key"]))
	if not keys.has(_selected):
		_selected = keys[0] if not keys.is_empty() else ""
	var key := str(d) + _selected
	if key == _key and visible:
		return
	_key = key
	_num.text = str(place_id)
	_name.text = String(d.get("name", ""))
	_sub.text = String(d.get("sub", ""))
	_thumb.texture = d.get("thumb")
	_thumb.visible = _thumb.texture != null
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	for ch in d.get("chips", []):
		var p := PanelContainer.new()
		var col: Color = ch[1]
		p.add_theme_stylebox_override("panel", PleosTheme.box(Color(col, 0.13), 999, 7))
		var l := PleosTheme.label(String(ch[0]), "Small")
		l.add_theme_color_override("font_color", col.darkened(0.15))
		p.add_child(l)
		_chips.add_child(p)
	_chips.visible = _chips.get_child_count() > 0
	_quote.text = String(d.get("quote", ""))
	_quote.visible = _quote.text != ""
	for c2 in _opts.get_children():
		_opts.remove_child(c2)
		c2.queue_free()
	for o2 in d.get("options", []):
		_opts.add_child(_option(o2))
	var prim: Dictionary = d.get("primary", {})
	_primary.text = String(prim.get(_selected, "할 수 있는 게 없어요"))
	_primary.disabled = _selected == ""
	_raid.text = "정말 출동?" if bool(d.get("raid_armed", false)) else "출동"
	_raid.disabled = not bool(d.get("can_raid", true))
	visible = true


func hide_card() -> void:
	visible = false
	_key = ""


## 지금 고른 옵션(call / stakeout / waypoint, 없으면 "").
func selected_option() -> String:
	return _selected


func _option(o: Dictionary) -> Control:
	var k := String(o["key"])
	var enabled := bool(o["enabled"])
	var sel := k == _selected
	var p := PanelContainer.new()
	var bg := PleosTheme.ACCENT_SOFT if sel else PleosTheme.SURFACE_2
	var sb := PleosTheme.box(bg, 14, 12, false, PleosTheme.ACCENT if sel else PleosTheme.LINE)
	if sel:
		sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := PleosTheme.label(String(o["title"]), "BodyStrong")
	var dsc := PleosTheme.label(String(o["desc"]), "Small")
	dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dsc.custom_minimum_size = Vector2(250, 0)
	var val := PleosTheme.label(String(o["value"]), "BodyStrong")
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not enabled:
		t.add_theme_color_override("font_color", PleosTheme.TEXT_3)
		val.add_theme_color_override("font_color", PleosTheme.TEXT_3)
	elif sel:
		val.add_theme_color_override("font_color", PleosTheme.ACCENT)
	v.add_child(t)
	v.add_child(dsc)
	h.add_child(val)
	for c in [t, dsc, val]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if enabled:
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_selected = k
				_key = ""
				show_actions.call_deferred(_data))
	return p
