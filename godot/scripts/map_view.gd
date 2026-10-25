## 사건 지도: 경로, 장소 핀, 차량, 단서 도형을 그린다.
## 좌표는 퍼즐 팩의 미터 단위(x=동, y=북)를 화면에 같은 비율로 맞춘다.
class_name MapView
extends Control

signal place_clicked(place_id: int)

const COLOR_BG := Color("0b0f17")
const COLOR_GRID := Color(0.35, 0.45, 0.6, 0.07)
const COLOR_ROUTE := Color("2f4b74")
const COLOR_ROUTE_DONE := Color("6fa8ff")
const COLOR_PIN := Color("3a4558")
const COLOR_PIN_HEARD := Color("e8edf5")
const COLOR_STAKEOUT := Color("ffc94a")
const COLOR_CAUGHT := Color("ff3b4e")
const COLOR_WRONG := Color("5b6270")
const COLOR_CLUE := Color("4fd1ff")
const COLOR_SUSPICIOUS := Color("ff5d6c")
const COLOR_CLEAN := Color("3ddc97")
const COLOR_SELECT := Color("ffffff")
const PIN_RADIUS := 24.0
const PAD_M := 600.0

var case: PuzzleCase
var selected_id := -1
## 지도에 진하게 그릴 진술. {"id": int, "stakeout": bool}. 비어 있으면 가장 최근 진술
var focus := {}
## 힌트로 짚은 모순 쌍
var hint_pair: Array[int] = []

var _min := Vector2.ZERO
var _max := Vector2.ONE
var _scale := 1.0
var _offset := Vector2.ZERO
var _route: PackedVector2Array = PackedVector2Array()
var _route_cum: PackedFloat32Array = PackedFloat32Array()
var _heard_order: Array[int] = []
var _time := 0.0


func set_case(c: PuzzleCase) -> void:
	case = c
	selected_id = -1
	focus = {}
	hint_pair = []
	_heard_order.clear()
	_route = PackedVector2Array()
	for p in case.data["route"]:
		_route.append(Vector2(float(p[0]), float(p[1])))
	_route_cum = PackedFloat32Array([0.0])
	for i in range(1, _route.size()):
		_route_cum.append(_route_cum[i - 1] + _route[i].distance_to(_route[i - 1]))
	_min = _route[0]
	_max = _route[0]
	for v in _route:
		_min = _min.min(v)
		_max = _max.max(v)
	for pl in case.data["places"]:
		var v := Vector2(float(pl["x"]), float(pl["y"]))
		_min = _min.min(v)
		_max = _max.max(v)
	_min -= Vector2(PAD_M, PAD_M)
	_max += Vector2(PAD_M, PAD_M)
	queue_redraw()


func note_heard(id: int, is_stakeout: bool) -> void:
	_heard_order.append(id)
	focus = {"id": id, "stakeout": is_stakeout}
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if selected_id != -1 or not hint_pair.is_empty():
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# ---------------------------------------------------------------- 좌표

func _fit() -> void:
	var world := _max - _min
	_scale = minf(size.x / world.x, size.y / world.y)
	_offset = (size - world * _scale) / 2.0


func w2s(v: Vector2) -> Vector2:
	return _offset + Vector2((v.x - _min.x) * _scale, (_max.y - v.y) * _scale)


func place_pos(id: int) -> Vector2:
	var pl: Dictionary = case.place(id)
	return w2s(Vector2(float(pl["x"]), float(pl["y"])))


func route_point(frac: float) -> Array:
	## [위치(월드), 진행 방향 단위벡터(월드)]
	var target := clampf(frac, 0.0, 1.0) * _route_cum[_route_cum.size() - 1]
	for i in range(1, _route.size()):
		if _route_cum[i] >= target:
			var seg := _route_cum[i] - _route_cum[i - 1]
			var t := 0.0 if seg == 0.0 else (target - _route_cum[i - 1]) / seg
			return [_route[i - 1].lerp(_route[i], t), (_route[i] - _route[i - 1]).normalized()]
	return [_route[_route.size() - 1], (_route[_route.size() - 1] - _route[_route.size() - 2]).normalized()]


func _screen_route() -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in _route:
		out.append(w2s(v))
	return out


# ---------------------------------------------------------------- 입력

func _gui_input(event: InputEvent) -> void:
	if case == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best := -1
		var best_d := PIN_RADIUS * 1.8
		for pl in case.data["places"]:
			var id := int(pl["id"])
			var d := place_pos(id).distance_to(event.position)
			if d < best_d:
				best_d = d
				best = id
		if best != -1:
			place_clicked.emit(best)
			accept_event()


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	if case == null:
		return
	_fit()
	_draw_grid()
	var focus_id := int(focus.get("id", -1))
	for id in observed_ids():
		if id != focus_id:
			_draw_clue(id, bool(case.observed[id]), false)
	_draw_route()
	if focus_id != -1 and case.observed.has(focus_id):
		_draw_clue(focus_id, bool(case.observed[focus_id]), true)
	_draw_pins()
	_draw_car()


func observed_ids() -> Array[int]:
	var out: Array[int] = []
	for k in case.observed.keys():
		out.append(int(k))
	return out


func _draw_grid() -> void:
	var step := 1000.0
	var x := ceilf(_min.x / step) * step
	while x < _max.x:
		draw_line(w2s(Vector2(x, _min.y)), w2s(Vector2(x, _max.y)), COLOR_GRID, 1.0)
		x += step
	var y := ceilf(_min.y / step) * step
	while y < _max.y:
		draw_line(w2s(Vector2(_min.x, y)), w2s(Vector2(_max.x, y)), COLOR_GRID, 1.0)
		y += step


func _draw_route() -> void:
	var pts := _screen_route()
	draw_polyline(pts, COLOR_ROUTE, 7.0, true)
	var done := PackedVector2Array()
	var prog := case.trip_progress
	var target := prog * _route_cum[_route_cum.size() - 1]
	for i in range(_route.size()):
		if _route_cum[i] <= target:
			done.append(pts[i])
	done.append(w2s(route_point(prog)[0]))
	if done.size() >= 2:
		draw_polyline(done, COLOR_ROUTE_DONE, 7.0, true)
	var dest := pts[pts.size() - 1]
	draw_circle(dest, 14.0, COLOR_ROUTE_DONE)
	draw_circle(dest, 7.0, COLOR_BG)


func _draw_car() -> void:
	var rp := route_point(case.trip_progress)
	var p := w2s(rp[0])
	var dir: Vector2 = rp[1]
	var d := Vector2(dir.x, -dir.y)      # 화면은 y가 아래로
	var n := Vector2(-d.y, d.x)
	var tri := PackedVector2Array([p + d * 22.0, p - d * 14.0 + n * 13.0, p - d * 14.0 - n * 13.0])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), COLOR_ROUTE_DONE, 3.0, true)


func _draw_pins() -> void:
	var font := get_theme_default_font()
	for pl in case.data["places"]:
		var id := int(pl["id"])
		var pos := place_pos(id)
		var fill := COLOR_PIN
		var ring := Color(1, 1, 1, 0.25)
		var text_col := Color.WHITE
		if case.caught.has(id):
			fill = COLOR_CAUGHT
		elif case.revealed.has(id):
			fill = COLOR_WRONG
			text_col = Color(1, 1, 1, 0.5)
		elif case.observed.has(id):
			fill = COLOR_PIN_HEARD
			text_col = COLOR_BG
			if case.observed[id]:
				ring = COLOR_STAKEOUT
		if bool(pl["roadside"]) and not case.observed.has(id):
			ring = Color(COLOR_STAKEOUT, 0.6)
		if hint_pair.has(id):
			var pulse := 0.5 + 0.5 * sin(_time * 6.0)
			draw_arc(pos, PIN_RADIUS + 14.0, 0, TAU, 48, Color(COLOR_SUSPICIOUS, 0.4 + 0.6 * pulse), 4.0, true)
		if id == selected_id:
			var pulse2 := 0.5 + 0.5 * sin(_time * 4.0)
			draw_arc(pos, PIN_RADIUS + 9.0 + 3.0 * pulse2, 0, TAU, 48, COLOR_SELECT, 3.0, true)
		draw_circle(pos, PIN_RADIUS, fill)
		draw_arc(pos, PIN_RADIUS, 0, TAU, 48, ring, 3.0, true)
		var memo: String = case.memos.get(id, "")
		if memo != "":
			var mc := COLOR_SUSPICIOUS if memo == "의심" else COLOR_CLEAN
			draw_arc(pos, PIN_RADIUS + 5.0, 0, TAU, 48, mc, 4.0, true)
		draw_string(font, pos + Vector2(-PIN_RADIUS, 9), str(id), HORIZONTAL_ALIGNMENT_CENTER,
				PIN_RADIUS * 2.0, 26, text_col)
		if case.caught.has(id):
			draw_line(pos + Vector2(-14, -14), pos + Vector2(14, 14), Color.WHITE, 3.0)
			draw_line(pos + Vector2(14, -14), pos + Vector2(-14, 14), Color.WHITE, 3.0)
		var pname: String = pl["name"]
		draw_string(font, pos + Vector2(-90, PIN_RADIUS + 26), pname, HORIZONTAL_ALIGNMENT_CENTER,
				180, 19, Color(0.85, 0.9, 1.0, 0.85))
		var sub := String(pl["kind"]) + ("·길가" if bool(pl["roadside"]) else "")
		draw_string(font, pos + Vector2(-90, PIN_RADIUS + 48), sub, HORIZONTAL_ALIGNMENT_CENTER,
				180, 15, Color(0.6, 0.68, 0.8, 0.7))


func _members(clue: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for m in clue.get("members", []):
		out.append(int(m))
	return out


func _draw_clue(id: int, is_stakeout: bool, strong: bool) -> void:
	var stmt := case.statement(id, is_stakeout)
	if stmt.is_empty():
		return
	var clue: Dictionary = stmt["clue"]
	var col := COLOR_STAKEOUT if is_stakeout else COLOR_CLUE
	var a := 1.0 if strong else 0.28
	var font := get_theme_default_font()
	var speaker := place_pos(id)
	# 숫자 단서 태그는 핀 오른쪽, 화살표 단서 태그는 화살표 가운데
	var label_pos := speaker + Vector2(PIN_RADIUS + 12, 0)
	var centered := false
	match String(clue["type"]):
		"RADIUS":
			var c := place_pos(int(clue["center"]))
			var r := float(clue["radiusM"]) * _scale
			draw_circle(c, r, Color(col, 0.10 * a))
			draw_arc(c, r, 0, TAU, 128, Color(col, 0.8 * a), 3.0 if strong else 2.0, true)
		"SPAN":
			# 경로상 from~to 구간을 굵게 칠한다
			var p_from := float(case.place(int(clue["from"]))["routePos"])
			var p_to := float(case.place(int(clue["to"]))["routePos"])
			draw_polyline(_route_slice(p_from, p_to), Color(col, 0.55 * a), 16.0 if strong else 9.0, true)
		"SIDE":
			# 경로 기준 한쪽(왼편/오른편) 1.6km 띠
			var band := _side_band(String(clue["side"]) == "왼편", 1600.0)
			if band.size() >= 3:
				draw_colored_polygon(band, Color(col, 0.08 * a))
		"NEIGHBOR":
			var c2 := place_pos(int(clue["center"]))
			for m in _members(clue):
				draw_line(c2, place_pos(m), Color(col, 0.85 * a), 4.0 if strong else 2.0, true)
		"KIND":
			pass
		"ROAD":
			var buf := float(clue.get("bufferM", 300.0)) * _scale * 2.0
			draw_polyline(_screen_route(), Color(col, 0.18 * a), maxf(buf, 10.0), true)
		"VOUCH":
			var tgt := place_pos(int(clue["target"]))
			var vc := COLOR_SUSPICIOUS if String(clue["claim"]) == "suspicious" else COLOR_CLEAN
			_draw_arrow(speaker, tgt, Color(vc, 0.9 * a), 4.0 if strong else 2.0)
			label_pos = speaker.lerp(tgt, 0.5)
			centered = true
		"REVEAL":
			var tgt2 := place_pos(int(clue["target"]))
			var rc := COLOR_SUSPICIOUS if String(clue["claim"]) == "disguised" else COLOR_CLEAN
			_draw_arrow(speaker, tgt2, Color(rc, 0.9 * a), 4.0 if strong else 2.0)
			draw_arc(tgt2, PIN_RADIUS + 18.0, 0, TAU, 48, Color(rc, 0.9 * a), 3.0, true)
			label_pos = speaker.lerp(tgt2, 0.5)
			centered = true
	# 숫자 단서: 대상 장소 강조와 개수 표시
	if clue.has("count"):
		for m in _members(clue):
			draw_arc(place_pos(m), PIN_RADIUS + 10.0, 0, TAU, 40, Color(col, 0.75 * a), 3.0 if strong else 1.5, true)
		if strong:
			var txt := "숨은 곳 %d" % int(clue["count"])
			_draw_tag(font, label_pos, txt, col, centered)
	elif strong:
		var claim_txt := {"suspicious": "수상", "clean": "깨끗", "disguised": "위장", "genuine": "진짜"}
		_draw_tag(font, label_pos, "%s %s" % [PuzzleCase.circled(int(clue["target"])), claim_txt.get(String(clue["claim"]), "")], col, centered)


func _draw_arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var dir := (to - from).normalized()
	var start := from + dir * (PIN_RADIUS + 4.0)
	var end := to - dir * (PIN_RADIUS + 8.0)
	draw_line(start, end, color, width, true)
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([end + dir * 14.0, end - dir * 4.0 + n * 9.0, end - dir * 4.0 - n * 9.0]), color)


## anchor: centered면 태그 중심, 아니면 태그 왼쪽 가운데
func _draw_tag(font: Font, anchor: Vector2, text: String, color: Color, centered: bool) -> void:
	var fs := 20
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var left := anchor.x - w / 2.0 if centered else anchor.x
	var rect := Rect2(Vector2(left, anchor.y - 16), Vector2(w, 32))
	draw_rect(rect, Color(COLOR_BG, 0.85))
	draw_rect(rect, color, false, 2.0)
	draw_string(font, rect.position + Vector2(10, 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

## 경로상 진행률 a~b 구간의 화면 좌표.
func _route_slice(a: float, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var lo := minf(a, b)
	var hi := maxf(a, b)
	for k in range(25):
		out.append(w2s(route_point(lerpf(lo, hi, k / 24.0))[0]))
	return out


## 경로 한쪽 띠 다각형(화면 좌표). left=true면 진행 방향 왼편.
func _side_band(left: bool, width_m: float) -> PackedVector2Array:
	var near := PackedVector2Array()
	var far := PackedVector2Array()
	var sign := 1.0 if left else -1.0
	for k in range(41):
		var rp := route_point(k / 40.0)
		var p: Vector2 = rp[0]
		var d: Vector2 = rp[1]
		var n := Vector2(-d.y, d.x) * sign       # 월드 좌표(y=북)에서 왼쪽 법선
		near.append(w2s(p))
		far.append(w2s(p + n * width_m))
	far.reverse()
	return near + far
