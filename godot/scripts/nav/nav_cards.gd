## 내비 카드 모음: 회전 안내(TBT), 도착 정보(ETA), 오른쪽 목록, 경고 카드.
## 사건 모드(E 단계)에서는 같은 카드에 사건 정보를 얹는다.
class_name NavCards
extends RefCounted


## 왼쪽 위 회전 안내 카드.
class TbtCard extends PanelContainer:
	var _icon: PleosIcon
	var _dist: Label
	var _unit: Label
	var _road: Label
	var _next_icon: PleosIcon
	var _next: Label
	var _next_row: HBoxContainer
	var _sep: HSeparator
	var _note: PanelContainer
	var _note_label: Label
	var _compact := false

	func _ready() -> void:
		theme_type_variation = "Card"
		custom_minimum_size = Vector2(380, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 12)
		add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		col.add_child(row)
		var icon_box := PanelContainer.new()
		icon_box.add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.ACCENT, 20, 10))
		_icon = PleosIcon.make("turn_right", 64, Color.WHITE)
		icon_box.add_child(_icon)
		row.add_child(icon_box)
		var txt := VBoxContainer.new()
		txt.add_theme_constant_override("separation", 0)
		txt.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(txt)
		var dist_row := HBoxContainer.new()
		dist_row.add_theme_constant_override("separation", 4)
		txt.add_child(dist_row)
		_dist = PleosTheme.label("350", "Display")
		dist_row.add_child(_dist)
		_unit = PleosTheme.label("m", "Title")
		_unit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		dist_row.add_child(_unit)
		_road = PleosTheme.label("", "Caption")
		txt.add_child(_road)
		_sep = HSeparator.new()
		col.add_child(_sep)
		_next_row = HBoxContainer.new()
		_next_row.add_theme_constant_override("separation", 10)
		col.add_child(_next_row)
		_next_row.add_child(PleosTheme.label("그다음", "Small"))
		_next_icon = PleosIcon.make("straight", 26, PleosTheme.TEXT_2)
		_next_row.add_child(_next_icon)
		_next = PleosTheme.label("", "Caption")
		_next_row.add_child(_next)
		_note = PanelContainer.new()
		_note_label = PleosTheme.label("", "Caption")
		_note.add_child(_note_label)
		_note.visible = false
		col.add_child(_note)

	## 터널·신호 대기 같은 상황 안내 줄. 빈 문자열이면 숨긴다.
	func set_note(text: String, color := PleosTheme.TEXT_2) -> void:
		_note.visible = text != ""
		_note_label.text = text
		_note_label.add_theme_color_override("font_color", color.darkened(0.1))
		_note.add_theme_stylebox_override("panel", PleosTheme.box(Color(color, 0.12), 12, 8))

	## 사건 모드: 한 줄짜리로 줄여 지도 공간을 넓힌다.
	func set_compact(on: bool) -> void:
		_icon.custom_minimum_size = Vector2(40, 40) if on else Vector2(64, 64)
		_dist.add_theme_font_size_override("font_size", 40 if on else 58)
		_compact = on
		_sep.visible = not on
		_next_row.visible = not on

	func set_arrived(dest: String) -> void:
		_icon.icon = "flag"
		_dist.text = "도착"
		_unit.text = ""
		_road.text = dest
		_next_row.visible = false
		_sep.visible = false
		set_note("")

	func set_maneuver(icon: String, distance_m: float, road: String, next_icon := "", next_text := "") -> void:
		_icon.icon = icon
		if distance_m >= 1000.0:
			_dist.text = "%.1f" % (distance_m / 1000.0)
			_unit.text = "km"
		else:
			_dist.text = str(int(round(distance_m / 10.0) * 10))
			_unit.text = "m"
		_road.text = road
		_sep.visible = not _compact
		_next_row.visible = next_icon != "" and not _compact
		_next_icon.icon = next_icon if next_icon != "" else "straight"
		_next.text = next_text


## 왼쪽 아래 도착 정보 카드. 아래쪽 extra 줄은 사건 모드에서 쓴다.
class EtaCard extends PanelContainer:
	var _via_row: HBoxContainer
	var _via: Label
	var _arrive: Label
	var _remain: Label
	var _dest: Label
	var _extra: HFlowContainer

	func _ready() -> void:
		theme_type_variation = "Card"
		custom_minimum_size = Vector2(380, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		add_child(col)
		# 경유지가 있으면 맨 위에 "경유 오후 2:31 · 3.2km" 줄
		_via_row = HBoxContainer.new()
		_via_row.add_theme_constant_override("separation", 10)
		_via_row.visible = false
		col.add_child(_via_row)
		_via_row.add_child(PleosIcon.make("flag", 24, NavMap.COL_WAYPOINT))
		_via = PleosTheme.label("", "BodyStrong")
		_via.add_theme_color_override("font_color", NavMap.COL_WAYPOINT.darkened(0.1))
		_via_row.add_child(_via)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		row.add_child(PleosIcon.make("flag", 30, PleosTheme.ACCENT))
		_arrive = PleosTheme.label("", "Title")
		row.add_child(_arrive)
		_remain = PleosTheme.label("", "Caption")
		col.add_child(_remain)
		_dest = PleosTheme.label("", "Small")
		col.add_child(_dest)
		_extra = HFlowContainer.new()
		_extra.add_theme_constant_override("h_separation", 10)
		_extra.add_theme_constant_override("v_separation", 8)
		_extra.visible = false
		col.add_child(_extra)

	func set_eta(arrive_text: String, remain_km: float, remain_min: int, dest: String) -> void:
		_arrive.text = arrive_text + " 도착"
		_remain.text = "%.1fkm · %d분 남음" % [remain_km, remain_min]
		_dest.text = dest

	## 경유지 줄. 빈 문자열이면 숨긴다.
	func set_waypoint(text: String) -> void:
		_via_row.visible = text != ""
		_via.text = text

	func set_arrived(arrive_text: String, dest: String) -> void:
		_via_row.visible = false
		_arrive.text = arrive_text + " 도착 완료"
		_remain.text = "안내를 마쳤어요"
		_dest.text = dest

	## 사건 정보 칩 줄. items: [[텍스트, 색], ...]. 비우면 숨긴다.
	var _extra_key := ""

	func set_extra(items: Array) -> void:
		var key := str(items)
		if key == _extra_key:
			return
		_extra_key = key
		for c in _extra.get_children():
			_extra.remove_child(c)
			c.queue_free()
		_extra.visible = not items.is_empty()
		for it in items:
			var chip := PanelContainer.new()
			var col: Color = it[1]
			chip.add_theme_stylebox_override("panel", PleosTheme.box(Color(col, 0.12), 999, 8))
			var l := PleosTheme.label(String(it[0]), "Caption")
			l.add_theme_color_override("font_color", col)
			chip.add_child(l)
			_extra.add_child(chip)


## 오른쪽 가장자리: 다음 안내 목록 카드 + 둥근 버튼 열.
## 주행 중에는 다가오는 회전 목록, 사건 모드에서는 '지나갈 장소 목록'으로 바뀐다.
class SideRail extends VBoxContainer:
	signal item_pressed(index: int)
	signal button_pressed(action: String)

	var _title: Label
	var _list: VBoxContainer
	var _card: PanelContainer
	var _buttons: VBoxContainer
	var _row_h := 58.0

	func _ready() -> void:
		add_theme_constant_override("separation", 14)
		_card = PanelContainer.new()
		_card.theme_type_variation = "Card"
		_card.custom_minimum_size = Vector2(300, 0)
		add_child(_card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_card.add_child(col)
		_title = PleosTheme.label("다음 안내", "Small")
		col.add_child(_title)
		_list = VBoxContainer.new()
		_list.add_theme_constant_override("separation", 2)
		col.add_child(_list)
		# 둥근 버튼은 오른쪽 가장자리에 세로로
		_buttons = VBoxContainer.new()
		_buttons.add_theme_constant_override("separation", 12)
		_buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
		add_child(_buttons)
		for b in [["compass", "north"], ["route", "overview"], ["plus", "zoom_in"], ["minus", "zoom_out"]]:
			_buttons.add_child(_round(b[0], b[1]))

	## 목록이 길 때(사건 모드) 줄 높이를 줄이고 둥근 버튼을 숨긴다.
	func set_compact(on: bool) -> void:
		_row_h = 50.0 if on else 58.0
		_buttons.visible = not on

	func _round(icon: String, action: String) -> Button:
		var btn := Button.new()
		btn.theme_type_variation = "RoundButton"
		btn.custom_minimum_size = Vector2(64, 64)
		btn.pressed.connect(func(): button_pressed.emit(action))
		var ic := PleosIcon.make(icon, 34, PleosTheme.TEXT_2)
		ic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		btn.add_child(ic)
		return btn

	## items: [{icon, title, sub, tag, tag_color, dim}], 위에서부터 가까운 순
	var _items_key := ""

	func set_items(title: String, items: Array) -> void:
		var key := title + str(items) + str(_row_h)
		if key == _items_key:
			return
		_items_key = key
		_title.text = title
		for c in _list.get_children():
			_list.remove_child(c)
			c.queue_free()
		for i in range(items.size()):
			_list.add_child(_row(i, items[i]))

	func _row(index: int, it: Dictionary) -> Control:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, _row_h)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				item_pressed.emit(index))
		var dim: bool = it.get("dim", false)
		var thumb: Texture2D = it.get("thumb")
		if thumb != null:
			# 사건 장소: 아이콘 대신 건물 썸네일. 지나온 곳은 흐리게
			var tr := TextureRect.new()
			tr.texture = thumb
			tr.custom_minimum_size = Vector2(_row_h - 2.0, _row_h - 2.0)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tr.modulate.a = 0.4 if dim else 1.0
			row.add_child(tr)
		else:
			var ic := PleosIcon.make(String(it.get("icon", "straight")), 32,
					PleosTheme.TEXT_3 if dim else PleosTheme.ACCENT)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(ic)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var t := PleosTheme.label(String(it.get("title", "")), "BodyStrong")
		t.add_theme_font_size_override("font_size", 21)
		if dim:
			t.add_theme_color_override("font_color", PleosTheme.TEXT_3)
		col.add_child(t)
		var s := PleosTheme.label(String(it.get("sub", "")), "Small")
		col.add_child(s)
		var tag := String(it.get("tag", ""))
		if tag != "":
			var chip := PanelContainer.new()
			var tc: Color = it.get("tag_color", PleosTheme.ACCENT)
			chip.add_theme_stylebox_override("panel", PleosTheme.box(Color(tc, 0.13), 999, 6))
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var tl := PleosTheme.label(tag, "Small")
			tl.add_theme_color_override("font_color", tc)
			chip.add_child(tl)
			row.add_child(chip)
		return row


## 지도 위쪽 가운데 경고 카드 (과속 카메라·사고 안내 같은 형식). 게임에서는 잠복 찬스 경고로 쓴다.
class AlertCard extends PanelContainer:
	signal pressed

	var _icon: PleosIcon
	var _title: Label
	var _body: Label
	var _bar: ProgressBar

	func _ready() -> void:
		var sb := PleosTheme.box(PleosTheme.SURFACE, 22, 18, true)
		sb.border_color = PleosTheme.WARN
		sb.border_width_left = 8
		add_theme_stylebox_override("panel", sb)
		custom_minimum_size = Vector2(380, 0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		_icon = PleosIcon.make("warning", 54, PleosTheme.WARN)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_icon)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		_title = PleosTheme.label("", "Title")
		_title.add_theme_font_size_override("font_size", 26)
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.custom_minimum_size = Vector2(300, 0)
		col.add_child(_title)
		_body = PleosTheme.label("", "Caption")
		_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.custom_minimum_size = Vector2(300, 0)
		col.add_child(_body)
		_bar = ProgressBar.new()
		_bar.show_percentage = false
		_bar.custom_minimum_size = Vector2(0, 8)
		_bar.add_theme_stylebox_override("background", PleosTheme.box(PleosTheme.SURFACE_2, 999, 0))
		_bar.add_theme_stylebox_override("fill", PleosTheme.box(PleosTheme.WARN, 999, 0))
		col.add_child(_bar)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func show_alert(title: String, body: String, icon := "warning", accent := PleosTheme.WARN,
			progress := -1.0) -> void:
		_title.text = title
		_body.text = body
		_icon.icon = icon
		_icon.color = accent
		var sb := PleosTheme.box(PleosTheme.SURFACE, 22, 18, true)
		sb.border_color = accent
		sb.border_width_left = 8
		add_theme_stylebox_override("panel", sb)
		_bar.visible = progress >= 0.0
		_bar.value = clampf(progress, 0.0, 1.0) * 100.0
		visible = true
