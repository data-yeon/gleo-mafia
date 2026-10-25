## 내비 지도 위 사건 오버레이: 장소 핀 9개, 들은 단서 도형, 힌트, 잠복 강조, 출동 경찰 아이콘, 최종 단계 붉은 톤.
## NavMap.overlay_drawer에 draw를 넣어 쓴다. 좌표 변환은 NavMap이 한다.
class_name CaseOverlay
extends RefCounted

const PIN_R := 28.0                 # 핀 반지름(가까이 볼 때). 멀리 볼수록 PIN_R_FAR까지 줄인다
const PIN_R_FAR := 21.0
const COL_CLUE := Color("2f6bff")
const COL_STAKEOUT := Color("e8930c")
const COL_NAVY := Color("1f2937")

var case: PuzzleCase
var selected := -1
var focus := {}                     # {"id": int, "stakeout": bool} 진하게 그릴 진술
var hint_pair: Array[int] = []
var stakeout_hot := -1              # 지금 잠복 가능한 장소
var police := {}                    # {"from": Vector2, "to": Vector2, "t": 0..1}
var reveal_t := 1.0                 # 핀이 하나씩 떨어지는 연출 진행 0..1
var final_tint := 0.0
var time := 0.0
var pin_r := PIN_R                  # 지금 배율의 핀 반지름 (draw에서 정한다)
var excluded: Array[int] = []       # 용의 장소 검색에서 빠진 곳(흐리게)
var page_ids: Array[int] = []       # 용의 장소 검색 카드에 지금 보이는 3곳(보라 테두리)
const COL_SEARCH := Color("7c4dff")
var pending: Array[int] = []        # 회신 전화 연출 중(아직 화면에 안 나온 말): 단서 도형을 그리지 않는다
## 수사망: 남은 후보 핀을 감싸는 그물. 후보가 바뀌면 옛 그물이 사라지며 새 그물이 겹쳐 나타난다.
var net_ids: Array[int] = []
var net_tight := false              # 남은 경우가 1가지면 붉게 조인다
var _net_prev: Array[int] = []
var _net_t0 := -99.0                # 그물이 바뀐 시각(time)
## 의심의 순간: 두 핀 사이 빨간 점선과 이름표(같은 직업 두 명 / 말이 안 맞음)
var conflict_pair: Array[int] = []
var conflict_label := ""
var entry := {}                     # 현장 진입 {id, t0}: 핀 둘레 고리가 조여든다
var stamps: Array = []              # 도장 [{id, text, color, t0}] 찍히고 잠시 뒤 사라진다
## 결말: 핀이 차례로 뒤집히며 정체 이름표가 붙고, 놓친 범인은 점선으로 지도 밖으로 달아난다.
## {t0, tags: {id: [글, 색]}, escape: [id...]}
var ending := {}
var _drawn_pins: Array[Dictionary] = []   # 이번 프레임에 그린 핀 {id, pos, r} (이름 자리 고르기용)
## 기울인 지도: 바닥(지도 텍스처)에는 핀 대신 상태 고리만 그리고, 랜드마크 모델은 3D로 서고,
## 번호 배지·이름은 화면 좌표로 투영해 draw_upright()가 그린다.
var upright := false


func place_world(id: int) -> Vector2:
	var p := case.place(id)
	return Vector2(float(p["x"]), float(p["y"]))


## 화면 좌표 sp에서 가장 가까운 핀 id (반경 안에 없으면 -1).
func pick(map: NavMap, sp: Vector2) -> int:
	if case == null:
		return -1
	var best := -1
	var best_d := pin_r * 1.7
	for k in range(case.place_count()):
		var d := map.to_screen(place_world(k + 1)).distance_to(sp)
		if d < best_d:
			best_d = d
			best = k + 1
	return best


func draw(map: NavMap) -> void:
	if case == null:
		return
	pin_r = lerpf(PIN_R_FAR, PIN_R, clampf((map.px_per_m() - 0.06) / 0.08, 0.0, 1.0))
	var font := map.get_theme_default_font()
	if final_tint > 0.0:
		map.draw_rect(Rect2(Vector2.ZERO, map.size), Color(PleosTheme.DANGER, 0.07 * final_tint))
	_net(map, font)
	var fid := int(focus.get("id", -1))
	for k in case.observed.keys():
		var id := int(k)
		if id != fid and not pending.has(id):
			_clue(map, font, id, bool(case.observed[k]), false)
	if fid != -1 and case.observed.has(fid) and not pending.has(fid):
		_clue(map, font, fid, bool(case.observed[fid]), true)
	_conflict(map, font)
	_drawn_pins.clear()
	for k2 in range(case.place_count()):
		_pin(map, font, k2 + 1, k2)
	if not upright:
		_pin_labels(map, font)
	if not police.is_empty():
		_police(map)
	if not entry.is_empty():
		_entry(map, font)
	if not ending.is_empty():
		_ending(map, font)
	_stamps(map)


# ---------------------------------------------------------------- 핀

## 장소 핀: 둥근 랜드마크 썸네일(건물 모양) + 왼쪽 위 번호 배지 + 아래 이름.
## 상태는 테두리와 배지 색으로 보인다: 들음(남색, 잠복이면 주황 테두리), 검거(빨강), 허탕(흐리게).
func _pin(map: NavMap, font: Font, id: int, order: int) -> void:
	var appear := clampf(reveal_t * case.place_count() - order, 0.0, 1.0)
	if appear <= 0.0:
		return
	var p := case.place(id)
	var pos := map.to_screen(place_world(id)) + Vector2(0, -18.0 * (1.0 - appear))
	var r := pin_r * (0.6 + 0.4 * appear)
	var fill := Color.WHITE
	var badge := Color.WHITE
	var num_col := COL_NAVY
	var ring := Color(COL_NAVY, 0.22)
	var ring_w := 2.0
	var img_mod := Color.WHITE
	if case.caught.has(id):
		fill = Color("fde8e8")
		badge = PleosTheme.DANGER
		num_col = Color.WHITE
		ring = PleosTheme.DANGER
		ring_w = 4.0
	elif case.revealed.has(id) or excluded.has(id):
		fill = Color("f1f3f6")
		badge = Color("b8c0ca")
		num_col = Color.WHITE
		img_mod = Color(1, 1, 1, 0.35)
		r *= 0.82
	elif case.observed.has(id) and not pending.has(id):
		badge = COL_NAVY
		num_col = Color.WHITE
		ring = COL_STAKEOUT if case.observed[id] else COL_NAVY
		ring_w = 3.5
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	if id == stakeout_hot:
		map.draw_arc(pos, r + 12.0 + 4.0 * pulse, 0, TAU, 48, Color(COL_STAKEOUT, 0.5 + 0.5 * pulse), 4.0, true)
	if hint_pair.has(id):
		map.draw_arc(pos, r + 16.0, 0, TAU, 48, Color(PleosTheme.DANGER, 0.4 + 0.6 * pulse), 4.0, true)
	if page_ids.has(id) and id != selected:
		map.draw_arc(pos, r + 7.0, 0, TAU, 48, Color(COL_SEARCH, 0.85), 3.5, true)
	if id == selected:
		map.draw_arc(pos, r + 8.0 + 2.0 * pulse, 0, TAU, 48, PleosTheme.ACCENT, 4.0, true)
	if upright:
		# 바닥 자리: 랜드마크 모델 아래 상태 고리(눕혀 보이면 타원)
		map.draw_circle(pos, r + 2.0, Color(ring, 0.12), true, -1.0, true)
		map.draw_arc(pos, r + 2.0, 0, TAU, 48, ring if ring_w > 2.0 else Color(COL_NAVY, 0.35), ring_w, true)
		_drawn_pins.append({"id": id, "pos": pos, "r": r + 3.0})
		return
	map.draw_circle(pos + Vector2(0, 4), r + 3.0, Color(0, 0, 0, 0.14), true, -1.0, true)
	map.draw_circle(pos, r + 3.0, Color.WHITE, true, -1.0, true)
	map.draw_circle(pos, r, fill, true, -1.0, true)
	var tex := _thumb(p)
	if tex != null:
		var s := r * 1.86
		map.draw_texture_rect(tex, Rect2(pos - Vector2(s, s) / 2.0 + Vector2(0, -1), Vector2(s, s)), false, img_mod)
	else:
		map.draw_string(font, pos + Vector2(-r, 8), str(id), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 22, COL_NAVY)
	map.draw_arc(pos, r + 1.0, 0, TAU, 48, ring, ring_w, true)
	var memo: String = case.memos.get(id, "")
	if memo != "":
		map.draw_arc(pos, r + 6.0, 0, TAU, 48, PleosTheme.DANGER if memo == "의심" else PleosTheme.OK, 4.0, true)
	# 번호 배지 (지나가는 순서)
	var bp := pos + Vector2(-r * 0.78, -r * 0.78)
	var br := clampf(r * 0.47, 11.0, 13.0) * (0.6 + 0.4 * appear)
	var bfs := 17 if br >= 12.5 else 15
	map.draw_circle(bp, br + 2.5, Color.WHITE, true, -1.0, true)
	map.draw_circle(bp, br, badge, true, -1.0, true)
	if badge == Color.WHITE:
		map.draw_arc(bp, br, 0, TAU, 32, Color(COL_NAVY, 0.5), 1.5, true)
	map.draw_string(PleosTheme.font(true), bp + Vector2(-br, bfs * 0.36), str(id), HORIZONTAL_ALIGNMENT_CENTER,
			br * 2.0, bfs, num_col)
	if bool(p["roadside"]):
		var rp := pos + Vector2(r * 0.8, -r * 0.8)
		map.draw_circle(rp, 8.0, Color.WHITE, true, -1.0, true)
		map.draw_circle(rp, 6.0, COL_STAKEOUT, true, -1.0, true)
	if case.is_anonymous(id) and not case.observed.has(id):
		var qp := pos + Vector2(r * 0.8, r * 0.8)
		map.draw_circle(qp, 11.0, Color.WHITE, true, -1.0, true)
		map.draw_circle(qp, 9.0, PleosTheme.TEXT_2, true, -1.0, true)
		map.draw_string(PleosTheme.font(true), qp + Vector2(-9, 5.5), "?", HORIZONTAL_ALIGNMENT_CENTER, 18, 15,
				Color.WHITE)
	_drawn_pins.append({"id": id, "pos": pos, "r": r + 3.0})


## 핀 이름: 아래 → 오른쪽 → 왼쪽 → 위 순서로 다른 핀·이름과 겹치지 않는 자리를 찾는다.
## 자리가 없으면 이름을 숨긴다(번호와 목록으로 알 수 있다). 고른 핀과 잠복 찬스 핀이 먼저 자리를 잡는다.
## 기울인 지도: 장소 번호 배지와 이름을 화면 좌표로 그린다. proj(id) → {ok, top(배지 자리), base(모델 바닥), appear}
func draw_upright(layer: Control, proj: Callable) -> void:
	if case == null:
		return
	var bold := PleosTheme.font(true)
	var font := PleosTheme.font(false)
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	var placed: Array[Rect2] = []
	var ids: Array = range(1, case.place_count() + 1)
	ids.sort_custom(func(a, b): return _label_rank(int(a)) < _label_rank(int(b)))
	for idv in ids:
		var id := int(idv)
		var pj: Dictionary = proj.call(id)
		if not bool(pj.get("ok", false)):
			continue
		var a := float(pj.get("appear", 1.0))
		var top: Vector2 = pj["top"]
		var badge := Color.WHITE
		var num_col := COL_NAVY
		if case.caught.has(id):
			badge = PleosTheme.DANGER
			num_col = Color.WHITE
		elif case.revealed.has(id) or excluded.has(id):
			badge = Color("b8c0ca")
			num_col = Color.WHITE
		elif case.observed.has(id) and not pending.has(id):
			badge = COL_NAVY
			num_col = Color.WHITE
		var br := 14.0 * (0.6 + 0.4 * a)
		if id == selected:
			layer.draw_arc(top, br + 7.0 + 2.0 * pulse, 0, TAU, 40, PleosTheme.ACCENT, 3.5, true)
		elif page_ids.has(id):
			layer.draw_arc(top, br + 6.0, 0, TAU, 40, Color(COL_SEARCH, 0.9), 3.0, true)
		layer.draw_circle(top + Vector2(0, 2), br + 3.0, Color(0, 0, 0, 0.18 * a), true, -1.0, true)
		layer.draw_circle(top, br + 2.5, Color(1, 1, 1, a), true, -1.0, true)
		layer.draw_circle(top, br, Color(badge, a), true, -1.0, true)
		if badge == Color.WHITE:
			layer.draw_arc(top, br, 0, TAU, 32, Color(COL_NAVY, 0.5 * a), 1.5, true)
		layer.draw_string(bold, top + Vector2(-br, 6.5), str(id), HORIZONTAL_ALIGNMENT_CENTER, br * 2.0, 18,
				Color(num_col, a))
		var p := case.place(id)
		if bool(p["roadside"]):
			layer.draw_circle(top + Vector2(br * 0.85, -br * 0.85), 6.0, Color.WHITE, true, -1.0, true)
			layer.draw_circle(top + Vector2(br * 0.85, -br * 0.85), 4.5, COL_STAKEOUT, true, -1.0, true)
		if case.is_anonymous(id) and not case.observed.has(id):
			var qp := top + Vector2(br * 0.9, br * 0.9)
			layer.draw_circle(qp, 9.0, Color.WHITE, true, -1.0, true)
			layer.draw_circle(qp, 7.5, PleosTheme.TEXT_2, true, -1.0, true)
			layer.draw_string(bold, qp + Vector2(-8, 5), "?", HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color.WHITE)
		# 이름: 배지 오른쪽, 겹치면 생략(고른 곳·잠복 찬스는 그래도 쓴다)
		var name := String(p["name"])
		var fs := 16
		var sz := Vector2(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0, 22.0)
		var rect := Rect2(top + Vector2(br + 6.0, -sz.y / 2.0), sz)
		var free := true
		for q in placed:
			if q.intersects(rect):
				free = false
				break
		if not free and _label_rank(id) > 1:
			continue
		placed.append(rect)
		var at := rect.position + Vector2(4.0, 16.0)
		layer.draw_string_outline(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(1, 1, 1, 0.92 * a))
		layer.draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(COL_NAVY, a))


func _pin_labels(map: NavMap, font: Font) -> void:
	var fs := 17
	var order := _drawn_pins.duplicate()
	order.sort_custom(func(a, b): return _label_rank(int(a["id"])) < _label_rank(int(b["id"])))
	var placed: Array[Rect2] = []
	for pin in order:
		var id := int(pin["id"])
		var pos: Vector2 = pin["pos"]
		var r: float = pin["r"]
		var name := String(case.place(id)["name"])
		var sz := Vector2(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0, 22.0)
		var spots: Array[Rect2] = [
			Rect2(pos + Vector2(-sz.x / 2.0, r + 3.0), sz),
			Rect2(pos + Vector2(r + 4.0, -sz.y / 2.0), sz),
			Rect2(pos + Vector2(-r - 4.0 - sz.x, -sz.y / 2.0), sz),
			Rect2(pos + Vector2(-sz.x / 2.0, -r - 5.0 - sz.y), sz),
		]
		var chosen := Rect2()
		var found := false
		for rect in spots:
			if _label_free(rect, id, placed):
				chosen = rect
				found = true
				break
		if not found:
			if _label_rank(id) > 1:
				continue
			chosen = spots[0]
		placed.append(chosen)
		var at := chosen.position + Vector2(4.0, 17.0)
		map.draw_string_outline(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(1, 1, 1, 0.92))
		map.draw_string(font, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_NAVY)


func _label_rank(id: int) -> int:
	if id == selected:
		return 0
	if id == stakeout_hot:
		return 1
	return 2 + id


func _label_free(rect: Rect2, own: int, placed: Array[Rect2]) -> bool:
	for q in placed:
		if q.intersects(rect):
			return false
	for pin in _drawn_pins:
		if int(pin["id"]) == own:
			continue
		var c: Vector2 = pin["pos"]
		var nearest := c.clamp(rect.position, rect.end)
		if nearest.distance_to(c) < float(pin["r"]):
			return false
	return true


## 장소의 랜드마크 썸네일. 팩의 `landmark`를 먼저 쓰고, 없으면 이름·업종으로 찾는다.
func _thumb(p: Dictionary) -> Texture2D:
	var lm := String(p.get("landmark", ""))
	if lm == "":
		lm = Landmarks.id_for(String(p["name"]), String(p.get("kind", "")))
	return Landmarks.pin_thumb(lm)


# ---------------------------------------------------------------- 단서

func _members(clue: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for m in clue.get("members", []):
		out.append(int(m))
	return out


func _clue(map: NavMap, font: Font, id: int, is_stakeout: bool, strong: bool) -> void:
	var stmt := case.statement(id, is_stakeout)
	if stmt.is_empty():
		return
	var clue: Dictionary = stmt["clue"]
	var col := COL_STAKEOUT if is_stakeout else COL_CLUE
	var a := 1.0 if strong else 0.3
	var speaker := map.to_screen(place_world(id))
	var tag_pos := speaker + Vector2(pin_r + 14, -pin_r - 6)
	match String(clue["type"]):
		"RADIUS":
			var c := map.to_screen(place_world(int(clue["center"])))
			var r := float(clue["radiusM"]) * map.px_per_m()
			map.draw_circle(c, r, Color(col, 0.08 * a))
			map.draw_arc(c, r, 0, TAU, 96, Color(col, 0.85 * a), 3.0 if strong else 2.0, true)
		"SPAN":
			var f0 := float(case.place(int(clue["from"]))["routePos"])
			var f1 := float(case.place(int(clue["to"]))["routePos"])
			map.draw_polyline(map.base_slice(f0, f1), Color(col, 0.45 * a), 22.0 if strong else 12.0, true)
		"SIDE":
			# 경로가 굽으면 띠가 꼬일 수 있어 조각(사각형)마다 그린다
			var band := _side_band(map, String(clue["side"]) == "왼편", 1700.0)
			var half := band.size() / 2
			for k in range(half - 1):
				var quad := PackedVector2Array([band[k], band[k + 1], band[band.size() - 2 - k], band[band.size() - 1 - k]])
				if not Geometry2D.triangulate_polygon(quad).is_empty():
					map.draw_colored_polygon(quad, Color(col, 0.08 * a))
		"NEIGHBOR":
			var c2 := map.to_screen(place_world(int(clue["center"])))
			for m in _members(clue):
				map.draw_line(c2, map.to_screen(place_world(m)), Color(col, 0.8 * a), 4.0 if strong else 2.0, true)
		"ROAD":
			var w := float(clue.get("bufferM", 300.0)) * 2.0 * map.px_per_m()
			map.draw_polyline(map.base_slice(0.0, 1.0, 60), Color(col, 0.16 * a), maxf(w, 10.0), true)
		"VOUCH", "REVEAL":
			var tgt := map.to_screen(place_world(int(clue["target"])))
			var bad := String(clue["claim"]) in ["suspicious", "disguised"]
			var vc := PleosTheme.DANGER if bad else PleosTheme.OK
			_arrow(map, speaker, tgt, Color(vc, 0.9 * a), 4.0 if strong else 2.0)
			tag_pos = speaker.lerp(tgt, 0.5)
	if clue.has("count"):
		for m2 in _members(clue):
			map.draw_arc(map.to_screen(place_world(m2)), pin_r + 9.0, 0, TAU, 32, Color(col, 0.8 * a),
					3.0 if strong else 1.5, true)
		if strong:
			_tag(map, font, tag_pos, "숨은 곳 %d" % int(clue["count"]), col)
	elif strong:
		var words := {"suspicious": "수상", "clean": "깨끗", "disguised": "위장", "genuine": "진짜"}
		_tag(map, font, tag_pos, "%s %s" % [PuzzleCase.circled(int(clue["target"])),
				words.get(String(clue["claim"]), "")], col)


func _side_band(map: NavMap, left: bool, width_m: float) -> PackedVector2Array:
	var near := PackedVector2Array()
	var far := PackedVector2Array()
	var sgn := 1.0 if left else -1.0
	for k in range(41):
		var rp := map.base_point(k / 40.0)
		var p: Vector2 = rp[0]
		var d: Vector2 = rp[1]
		near.append(map.to_screen(p))
		far.append(map.to_screen(p + Vector2(-d.y, d.x) * sgn * width_m))
	far.reverse()
	return near + far


func _arrow(map: NavMap, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var dir := (to - from).normalized()
	var start := from + dir * (pin_r + 4.0)
	var end := to - dir * (pin_r + 8.0)
	map.draw_line(start, end, color, width, true)
	var n := Vector2(-dir.y, dir.x)
	map.draw_colored_polygon(PackedVector2Array([end + dir * 14.0, end - dir * 4.0 + n * 9.0,
			end - dir * 4.0 - n * 9.0]), color)


func _tag(map: NavMap, font: Font, anchor: Vector2, text: String, color: Color) -> void:
	var fs := 19
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0
	var rect := Rect2(anchor - Vector2(0, 16), Vector2(w, 32))
	map.draw_rect(rect, Color.WHITE)
	map.draw_rect(rect, color, false, 2.0)
	map.draw_string(font, rect.position + Vector2(10, 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


# ---------------------------------------------------------------- 수사망 · 의심

## 후보가 바뀌면 부른다. ids가 같으면 그대로.
func set_net(ids: Array[int], tight: bool) -> void:
	if ids == net_ids and tight == net_tight:
		return
	_net_prev = net_ids
	net_ids = ids
	net_tight = tight
	_net_t0 = time


func _net(map: NavMap, font: Font) -> void:
	var t := clampf((time - _net_t0) / 0.7, 0.0, 1.0)
	if not _net_prev.is_empty() and t < 1.0:
		_net_shape(map, font, _net_prev, 1.0 - t, false, false)
	if not net_ids.is_empty():
		_net_shape(map, font, net_ids, t, net_tight, true)


## 후보 핀들을 감싸는 둥근 그물(볼록 껍질을 핀 반지름만큼 넓힌 모양). 점선 테두리 + 옅은 채움 + "수사망 N곳".
func _net_shape(map: NavMap, font: Font, ids: Array[int], a: float, tight: bool, label: bool) -> void:
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(map.to_screen(place_world(id)))
	if pts.size() == 1:
		pts.append(pts[0] + Vector2(1, 0))
	if pts.size() == 2:
		var d := (pts[1] - pts[0]).normalized().orthogonal()
		pts = PackedVector2Array([pts[0] + d, pts[1] + d, pts[1] - d, pts[0] - d])
	var hull := Geometry2D.convex_hull(pts)
	var grown := Geometry2D.offset_polygon(hull, pin_r + (16.0 if tight else 24.0), Geometry2D.JOIN_ROUND)
	if grown.is_empty():
		return
	var poly: PackedVector2Array = grown[0]
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	var col := PleosTheme.DANGER if tight else COL_SEARCH
	map.draw_colored_polygon(poly, Color(col, (0.07 if tight else 0.045) * a))
	var w := (4.0 + 1.5 * pulse) if tight else 2.5
	for i in poly.size():
		map.draw_dashed_line(poly[i], poly[(i + 1) % poly.size()], Color(col, 0.75 * a), w, 10.0)
	if label and a > 0.5:
		var top := poly[0]
		for q in poly:
			if q.y < top.y:
				top = q
		var text := ("수사망 · %d곳" % ids.size())
		var fs := 17
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0
		var rect := Rect2(top + Vector2(-tw / 2.0, -30.0), Vector2(tw, 26.0))
		map.draw_rect(rect, Color(col, 0.92 * a))
		map.draw_string(font, rect.position + Vector2(9, 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))


func _conflict(map: NavMap, font: Font) -> void:
	if conflict_pair.size() < 2:
		return
	var a := map.to_screen(place_world(conflict_pair[0]))
	var b := map.to_screen(place_world(conflict_pair[1]))
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	map.draw_dashed_line(a, b, Color(PleosTheme.DANGER, 0.6 + 0.4 * pulse), 4.0, 12.0)
	for p in [a, b]:
		map.draw_arc(p, pin_r + 11.0, 0, TAU, 40, Color(PleosTheme.DANGER, 0.5 + 0.5 * pulse), 3.5, true)
	if conflict_label != "":
		_tag(map, font, a.lerp(b, 0.5) + Vector2(-40, 0), conflict_label, PleosTheme.DANGER)


# ---------------------------------------------------------------- 출동

func _ending(map: NavMap, font: Font) -> void:
	var t := time - float(ending["t0"])
	var tags: Dictionary = ending["tags"]
	for k in range(case.place_count()):
		var id := k + 1
		if t < k * 0.14 or not tags.has(id):
			continue
		var pos := map.to_screen(place_world(id))
		var tg: Array = tags[id]
		var col: Color = tg[1]
		map.draw_arc(pos, pin_r + 6.0, 0, TAU, 40, Color(col, 0.9), 3.5, true)
		var fs := 16
		var text := String(tg[0])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
		var rect := Rect2(pos + Vector2(-tw / 2.0, pin_r + 6.0), Vector2(tw, 24))
		map.draw_rect(rect, Color(col, 0.92))
		map.draw_string(font, rect.position + Vector2(7, 18), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# 도주: 지도 가운데에서 먼 쪽으로 점선이 뻗어 나가고, 끝에 빨간 점이 달린다
	var center := map.size / 2.0
	for x in ending.get("escape", []):
		var p := clampf((t - 1.0) / 1.6, 0.0, 1.0)
		if p <= 0.0:
			continue
		var a := map.to_screen(place_world(int(x)))
		var dir := (a - center).normalized() if a.distance_to(center) > 1.0 else Vector2.RIGHT
		var b := a + dir * 1100.0 * ease(p, 0.6)
		map.draw_dashed_line(a, b, Color(PleosTheme.DANGER, 0.85), 4.0, 14.0)
		var blink := int(time * 6.0) % 2 == 0
		map.draw_circle(b, 9.0, Color.WHITE)
		map.draw_circle(b, 7.0, PleosTheme.DANGER if blink else Color("7f1d1d"))
		map.draw_arc(a, pin_r + 12.0, 0, TAU, 40, Color(PleosTheme.DANGER, 0.5 + 0.5 * float(blink)), 4.0, true)


func add_stamp(id: int, text: String, color: Color) -> void:
	stamps.append({"id": id, "text": text, "color": color, "t0": time})


## 현장 진입: 핀 둘레 고리가 바깥에서 조여든다.
func _entry(map: NavMap, font: Font) -> void:
	var id := int(entry["id"])
	var pos := map.to_screen(place_world(id))
	var k := fmod((time - float(entry["t0"])) / 0.55, 1.0)
	for j in 2:
		var kk := fmod(k + j * 0.5, 1.0)
		var rr := lerpf(pin_r + 70.0, pin_r + 6.0, kk)
		map.draw_arc(pos, rr, 0, TAU, 56, Color(PleosTheme.DANGER, 0.85 * (1.0 - kk * 0.6)), 4.0, true)
	_tag(map, font, pos + Vector2(pin_r + 14, pin_r + 6), "현장 진입", PleosTheme.DANGER)


## 도장: 크게 찍혔다가(0.18초) 제자리, 1.8초 뒤부터 옅어진다. 핀 위쪽, 살짝 기울임.
func _stamps(map: NavMap) -> void:
	var keep := []
	var font := PleosTheme.font(true)
	for st in stamps:
		var age := time - float(st["t0"])
		if age > 2.8:
			continue
		keep.append(st)
		var sc := 1.0 + 1.3 * maxf(0.0, 1.0 - age / 0.18)
		var a := clampf((2.8 - age) / 1.0, 0.0, 1.0) * minf(1.0, age / 0.06 + 0.3)
		var col: Color = st["color"]
		var text := String(st["text"])
		var fs := 30
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := map.to_screen(place_world(int(st["id"]))) + Vector2(0, -pin_r - 36)
		map.draw_set_transform(pos, -0.2, Vector2(sc, sc))
		var rect := Rect2(Vector2(-tw / 2.0 - 14, -24), Vector2(tw + 28, 46))
		map.draw_rect(rect, Color(1, 1, 1, 0.85 * a))
		map.draw_rect(rect, Color(col, a), false, 4.0)
		map.draw_string(font, Vector2(-tw / 2.0, 10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
		map.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	stamps = keep

func _police(map: NavMap) -> void:
	var from: Vector2 = police["from"]
	var to: Vector2 = police["to"]
	var t := float(police["t"])
	var a := map.to_screen(from)
	var b := map.to_screen(to)
	map.draw_dashed_line(a, b, Color(COL_NAVY, 0.5), 3.0, 12.0)
	var p := a.lerp(b, ease(t, -1.8))
	var blink := int(time * 8.0) % 2 == 0
	map.draw_circle(p, 17.0, Color.WHITE)
	map.draw_circle(p, 14.0, COL_NAVY)
	map.draw_circle(p + Vector2(-5, 0), 5.0, PleosTheme.SIREN_RED if blink else PleosTheme.SIREN_BLUE)
	map.draw_circle(p + Vector2(5, 0), 5.0, PleosTheme.SIREN_BLUE if blink else PleosTheme.SIREN_RED)
