## 장소 상세 카드 (내비 POI 카드 형식). 사건 모드에서 장소를 고르면 뜬다.
## 버튼: 탐문(통화) / 잠복 / 출동, 태그: 의심 / 무고
class_name PoiCard
extends PanelContainer

signal action(name: String, place_id: int)

var place_id := -1
var _num: Label
var _name: Label
var _sub: Label
var _chips: HBoxContainer
var _status: Label
var _thumb: TextureRect
var _btn_call: Button
var _btn_stakeout: Button
var _btn_raid: Button
var _btn_sus: Button
var _btn_ok: Button
var _btn_waypoint: Button


func _ready() -> void:
	theme_type_variation = "Card"
	custom_minimum_size = Vector2(420, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.TEXT, 999, 8))
	badge.custom_minimum_size = Vector2(52, 52)
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
	# 장소 건물 썸네일 (assets/models/landmarks/thumbs)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(88, 88)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_thumb)
	var close := Button.new()
	close.text = "목록"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 48)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 19)
	close.pressed.connect(func(): action.emit("close", place_id))
	head.add_child(close)

	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	col.add_child(_chips)
	_status = PleosTheme.label("", "Body")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_btn_call = _button("탐문", "PrimaryButton", "call", row)
	_btn_stakeout = _button("잠복", "Button", "stakeout", row)
	_btn_raid = _button("출동", "DangerButton", "raid", row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	col.add_child(row2)
	_btn_sus = _button("의심", "Button", "tag_suspicious", row2)
	_btn_ok = _button("무고", "Button", "tag_clean", row2)
	# 경유지 잠복(길가가 아닌 장소): "경유지로 추가 · +N분 · 통화 1번"
	_btn_waypoint = _button("경유지로 추가", "Button", "waypoint", col)
	var wcol := NavMap.COL_WAYPOINT
	_btn_waypoint.add_theme_stylebox_override("normal", PleosTheme.box(Color(wcol, 0.12), 18, 14))
	_btn_waypoint.add_theme_stylebox_override("hover", PleosTheme.box(Color(wcol, 0.18), 18, 14))
	_btn_waypoint.add_theme_stylebox_override("pressed", PleosTheme.box(Color(wcol, 0.26), 18, 14))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_btn_waypoint.add_theme_color_override(k, wcol.darkened(0.15))
	_btn_waypoint.visible = false


func _button(text: String, variation: String, act: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): action.emit(act, place_id))
	parent.add_child(b)
	return b


## 출동 버튼을 한 번 누르면 "정말 출동?"으로 바뀐다(두 번 눌러야 출동).
func set_raid_armed(on: bool) -> void:
	_btn_raid.text = "정말 출동?" if on else "출동"


## info: {id, name, kind, side, distance_m, roadside, status, chips:[[text, color]],
##        can_call, can_stakeout, can_raid}
var _info_key := ""


func show_place(info: Dictionary) -> void:
	var key := str(info)
	if key == _info_key and visible:
		return
	_info_key = key
	place_id = int(info.get("id", -1))
	_num.text = str(place_id)
	_name.text = String(info.get("name", ""))
	_thumb.texture = Landmarks.thumb(_name.text, String(info.get("kind", "")))
	_thumb.visible = _thumb.texture != null
	var dist :=float(info.get("distance_m", 0.0))
	var dist_text := ("%.1fkm 앞" % (dist / 1000.0)) if dist >= 0.0 else "지나옴"
	_sub.text = "%s · %s · %s" % [info.get("kind", ""), dist_text, info.get("side", "")]
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	var chips: Array = info.get("chips", [])
	if bool(info.get("roadside", false)):
		chips = [["길가 · 지나가는 동안 잠복 가능", PleosTheme.WARN]] + chips
	for ch in chips:
		var p := PanelContainer.new()
		var col: Color = ch[1]
		p.add_theme_stylebox_override("panel", PleosTheme.box(Color(col, 0.13), 999, 7))
		var l := PleosTheme.label(String(ch[0]), "Small")
		l.add_theme_color_override("font_color", col.darkened(0.15))
		p.add_child(l)
		_chips.add_child(p)
	_status.text = String(info.get("status", ""))
	_status.visible = _status.text != ""
	_btn_call.disabled = not bool(info.get("can_call", true))
	_btn_stakeout.disabled = not bool(info.get("can_stakeout", false))
	_btn_stakeout.text = String(info.get("stakeout_text", "잠복"))
	_btn_raid.disabled = not bool(info.get("can_raid", true))
	set_raid_armed(bool(info.get("raid_armed", false)))
	var wp := String(info.get("waypoint_text", ""))
	_btn_waypoint.visible = wp != ""
	_btn_waypoint.text = wp
	_btn_sus.disabled = not bool(info.get("can_tag", true))
	_btn_ok.disabled = not bool(info.get("can_tag", true))
	visible = true
