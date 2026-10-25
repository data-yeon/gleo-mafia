## 사건 안내 카드 (내비 경로 옵션 카드 형식). 오른쪽 목록 자리에 뜬다(장소 카드와 같은 자리).
## 사건 제안, 브리핑 3장, 수사 노트에 쓴다.
## show_card({kicker, title, title_color?, lines: [[아이콘, 글, 색?], ...], buttons: [[라벨, id, 변형?], ...],
##            stamp?: "긴급"(오른쪽 위 빨간 도장), suspects?: [{slot, tag, label}, ...]})
## 줄 아이콘이 "sms"면 문자 말풍선, "suspects"면 용의자 실루엣 줄(suspects 목록)로 그린다(사건 파일).
class_name CaseCard
extends PanelContainer

signal action(id: String)

var _kicker: Label
var _stamp: Label
var _title: Label
var _lines: VBoxContainer
var _buttons: HBoxContainer
var _key := ""


func _ready() -> void:
	theme_type_variation = "Card"
	custom_minimum_size = Vector2(440, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_kicker = PleosTheme.label("", "AccentLabel")
	_kicker.add_theme_font_size_override("font_size", 18)
	_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_kicker)
	# 사건 파일 도장: 빨간 테두리 글자, 살짝 기울임
	_stamp = PleosTheme.label("", "BodyStrong")
	_stamp.add_theme_font_size_override("font_size", 22)
	_stamp.add_theme_color_override("font_color", PleosTheme.DANGER)
	_stamp.add_theme_stylebox_override("normal", PleosTheme.box(Color(PleosTheme.DANGER, 0.06), 6, 6, false,
			PleosTheme.DANGER))
	_stamp.rotation_degrees = -8.0
	_stamp.visible = false
	head.add_child(_stamp)
	_title = PleosTheme.label("", "Title")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(390, 0)
	col.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 8)
	col.add_child(_lines)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	col.add_child(_buttons)


func show_card(d: Dictionary) -> void:
	var key := str(d)
	if key == _key and visible:
		return
	_key = key
	_kicker.text = String(d.get("kicker", ""))
	_kicker.visible = _kicker.text != ""
	_stamp.text = String(d.get("stamp", ""))
	_stamp.visible = _stamp.text != ""
	_stamp.pivot_offset = _stamp.get_minimum_size() / 2.0
	_title.text = String(d.get("title", ""))
	_title.add_theme_color_override("font_color", d.get("title_color", PleosTheme.TEXT))
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	var fs := int(d.get("font_size", 21))
	for ln in d.get("lines", []):
		if String(ln[0]) == "sms":
			_lines.add_child(_sms(String(ln[1]), fs))
			continue
		if String(ln[0]) == "suspects":
			_lines.add_child(_suspects(d.get("suspects", []), fs))
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var col: Color = ln[2] if ln.size() > 2 else PleosTheme.TEXT_2
		var icon := PleosIcon.make(String(ln[0]), 26, col)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var l := PleosTheme.label(String(ln[1]), "Body")
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", PleosTheme.TEXT if ln.size() <= 2 else col.darkened(0.15))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(350, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_lines.add_child(row)
	for c2 in _buttons.get_children():
		_buttons.remove_child(c2)
		c2.queue_free()
	for b in d.get("buttons", []):
		var btn := Button.new()
		btn.text = String(b[0])
		btn.theme_type_variation = String(b[2]) if b.size() > 2 else "Button"
		btn.custom_minimum_size = Vector2(0, 60)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var id := String(b[1])
		btn.pressed.connect(func(): action.emit(id))
		_buttons.add_child(btn)
	_buttons.visible = _buttons.get_child_count() > 0
	visible = true


## 사기 문자 말풍선(회색 둥근 상자, 위에 "문자")
func _sms(text: String, fs: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PleosTheme.box(Color("eef1f6"), 18, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 6)
	cap.add_child(PleosIcon.make("sms", 20, PleosTheme.TEXT_3))
	cap.add_child(PleosTheme.label("피해자가 받은 문자", "Small"))
	v.add_child(cap)
	var l := PleosTheme.label(text, "Body")
	l.add_theme_font_size_override("font_size", fs - 2)
	l.add_theme_color_override("font_color", PleosTheme.TEXT_2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	v.add_child(l)
	return p


## 용의자 칸: 어두운 실루엣 칩 "A · 경찰 사칭"
func _suspects(list: Array, fs: int) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for sp in list:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", PleosTheme.box(Color("2b3240"), 12, 8))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		p.add_child(h)
		h.add_child(PleosIcon.make("person", 30, Color("8a93a6")))
		var l := PleosTheme.label("용의자 %s · %s" % [sp["slot"], sp["tag"]], "Body")
		l.add_theme_font_size_override("font_size", fs - 2)
		l.add_theme_color_override("font_color", Color.WHITE)
		h.add_child(l)
		row.add_child(p)
	return row


func hide_card() -> void:
	visible = false
	_key = ""
