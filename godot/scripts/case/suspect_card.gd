## 용의 장소 검색 카드: 실제 Gleo 검색 결과 카드처럼 지도 위에 떠 있는 보라 카드.
## 머리줄(후보 수 · 조건에 맞는 경우의 수) / 진술 칩(눌러서 믿음 ↔ 못 믿음) / 결과 3줄(지나가는 순서) / [다음 페이지].
## show_search({head, chips: [{id, text, kind(on|off|lock|soft|fact|more), bad, flash}], rows: [{id, num, name, dist, desc, out, sel}],
##              page_text})   flash: 방금 들은 말 칩(통화가 끝나면 튀어나오며 반짝인다)
class_name SuspectCard
extends PanelContainer

signal chip_pressed(place_id: int)
signal row_pressed(place_id: int)
signal next_page
signal more_chips

const BG := Color(0.945, 0.941, 0.996, 0.97)
const BORDER := Color("afa9ec")
const INK := Color("26215c")
const INK_2 := Color("534ab7")
const INK_3 := Color("8f88e0")
const ROW_SEL := Color("dedbfa")
const BTN := Color("d9d5fb")

var _head: RichTextLabel
var _slots: HBoxContainer
var _chips: HFlowContainer
var _rows: VBoxContainer
var _next: Button
var _key := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", PleosTheme.box(BG, 22, 16, true, BORDER))
	custom_minimum_size = Vector2(460, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	col.add_child(title)
	title.add_child(PleosIcon.make("gleo", 22, INK_2))
	_head = _rich(19)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(_head)
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 6)
	col.add_child(_slots)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	col.add_child(_chips)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)
	_next = Button.new()
	_next.focus_mode = Control.FOCUS_NONE
	_next.custom_minimum_size = Vector2(0, 52)
	_next.add_theme_stylebox_override("normal", PleosTheme.box(BTN, 14, 10))
	_next.add_theme_stylebox_override("hover", PleosTheme.box(BTN.darkened(0.04), 14, 10))
	_next.add_theme_stylebox_override("pressed", PleosTheme.box(BTN.darkened(0.08), 14, 10))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_next.add_theme_color_override(k, INK_2)
	_next.add_theme_font_size_override("font_size", 20)
	_next.pressed.connect(func(): next_page.emit())
	col.add_child(_next)


func _rich(fs: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", PleosTheme.font(false))
	r.add_theme_font_override("bold_font", PleosTheme.font(true))
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_font_size_override("bold_font_size", fs)
	r.add_theme_color_override("default_color", INK)
	return r


func show_search(d: Dictionary) -> void:
	var key := str(d)
	if key == _key and visible:
		return
	_key = key
	_head.text = String(d.get("head", ""))
	for c0 in _slots.get_children():
		_slots.remove_child(c0)
		c0.queue_free()
	for sl in d.get("slots", []):
		_slots.add_child(_slot(sl))
	_slots.visible = _slots.get_child_count() > 0
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	for ch in d.get("chips", []):
		var cp := _chip(ch)
		cp.set_meta("place_id", int(ch.get("id", -1)))
		_chips.add_child(cp)
		if bool(ch.get("flash", false)):
			_flash(cp)
	_chips.visible = _chips.get_child_count() > 0
	for c2 in _rows.get_children():
		_rows.remove_child(c2)
		c2.queue_free()
	for rw in d.get("rows", []):
		_rows.add_child(_row(rw))
	_next.text = String(d.get("page_text", "다음 페이지"))
	_next.visible = _next.text != ""
	visible = true


## 그 장소 진술 칩(코치 마크가 가리킬 곳). 없으면 null.
func chip_control(place_id: int) -> Control:
	for c in _chips.get_children():
		if c.has_meta("place_id") and int(c.get_meta("place_id")) == place_id:
			return c
	return null


func hide_card() -> void:
	visible = false
	_key = ""


func _chip(ch: Dictionary) -> Control:
	var kind := String(ch.get("kind", "on"))
	var bad := bool(ch.get("bad", false))
	var bg := Color.WHITE
	var border := BORDER
	var ink := INK
	match kind:
		"off":
			bg = Color(1, 1, 1, 0.0)
			ink = INK_3
		"lock":
			bg = Color("faeeda")
			border = Color("ef9f27")
			ink = Color("633806")
		"soft", "more":
			bg = Color(1, 1, 1, 0.0)
			ink = INK_2
		"fact":
			bg = Color("eef1f5")
			border = Color("c7cdd6")
			ink = PleosTheme.TEXT_2
	if bad:
		bg = Color("fcebeb")
		border = Color("e24b4a")
		ink = Color("791f1f")
	var p := PanelContainer.new()
	var sb := PleosTheme.box(bg, 999, 6, false, border)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	p.add_theme_stylebox_override("panel", sb)
	var r := _rich(17)
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_color_override("default_color", ink)
	var text := String(ch.get("text", ""))
	r.text = "[s]%s[/s]" % text if kind == "off" else text
	p.add_child(r)
	var id := int(ch.get("id", -1))
	if kind in ["on", "off", "more"]:
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if kind == "more":
					more_chips.emit()
				else:
					chip_pressed.emit(id))
	return p


## 용의자 칸: 어두운 실루엣 "A 경찰 사칭 ?" → 잡으면 빨간 "A 경찰 사칭 · ⑦ 숲공원 검거"
func _slot(sl: Dictionary) -> Control:
	var filled := String(sl.get("filled", ""))
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.DANGER if filled != "" else Color("2b3240"), 10, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	h.add_child(PleosIcon.make("person", 20, Color.WHITE if filled != "" else Color("8a93a6")))
	var l := PleosTheme.label("%s %s · %s" % [sl["slot"], sl["tag"], filled if filled != "" else "?"], "Small")
	l.add_theme_color_override("font_color", Color.WHITE)
	h.add_child(l)
	return p


## 새 칩: 커졌다가 제자리로, 보라 테두리가 잠깐 빛난다.
func _flash(p: PanelContainer) -> void:
	p.modulate = Color(1, 1, 1, 0)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate", Color(1.15, 1.1, 1.3, 1.0), 0.25)
	tw.tween_property(p, "modulate", Color.WHITE, 0.9)
	(func():
		p.pivot_offset = p.size / 2.0
		p.scale = Vector2(1.25, 1.25)
		p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	).call_deferred()


func _row(rw: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sel := bool(rw.get("sel", false))
	p.add_theme_stylebox_override("panel", PleosTheme.box(ROW_SEL if sel else Color(1, 1, 1, 0.0), 12, 8))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var id := int(rw.get("id", -1))
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			row_pressed.emit(id))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var num := PleosTheme.label(String(rw.get("num", "")), "BodyStrong")
	num.add_theme_color_override("font_color", INK_2)
	num.custom_minimum_size = Vector2(26, 0)
	num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(num)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var out := bool(rw.get("out", false))
	var name_r := _rich(22)
	var nm := "[b]%s[/b]" % String(rw.get("name", ""))
	if out:
		nm = "[s]%s[/s]" % nm
		name_r.add_theme_color_override("default_color", INK_3)
	name_r.text = nm
	v.add_child(name_r)
	var sub := _rich(17)
	sub.text = "[b]%s[/b]  [color=#%s]%s[/color]" % [String(rw.get("dist", "")), INK_2.to_html(false),
			String(rw.get("desc", ""))]
	v.add_child(sub)
	return p
