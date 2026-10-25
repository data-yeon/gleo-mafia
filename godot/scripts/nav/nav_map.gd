## 밝은 내비 지도. 팩의 가상 도시(블록, 공원, 강, 도로 등급, 다리)와 도로 이름, 경로, 회전 화살표,
## 내 위치 화살표, 목적지를 그린다.
## 도시 데이터(`city`)가 없는 예전 팩은 경로 주변에 절차적으로 만든 가짜 도시를 쓴다.
## 보기: "follow"(내 차 따라가기, 진행 방향이 위) / "overview"(경로 전체, 북쪽이 위)
class_name NavMap
extends Control

signal tapped(world_pos: Vector2, screen_pos: Vector2)

const ROAD_CLASSES := ["local", "arterial", "bridge"]
const LABEL_GAP := {"local": 1300.0, "arterial": 1700.0, "bridge": 0.0, "water": 2600.0}
const LOCAL_LABEL_SCALE := 0.22          # 이 배율(px/m)부터 이면도로 이름을 보인다
const COL_WAYPOINT := Color("7c4dff")     # 경유지 배지 색(경로 파랑과 구별)
const TURN_ARROW_SCALE := 0.16           # 이 배율부터 경로 위 회전 화살표를 그린다
const LABEL_REPEAT_PX := 460.0           # 같은 이름을 다시 쓰려면 이만큼 떨어져야 한다
const OUTSKIRT_COLS := 18                # 도시 바깥으로 이어 그릴 열 수(한쪽)
const OUTSKIRT_ROWS := 10                # 도시 바깥으로 이어 그릴 행 수(한쪽)
const BLOCK_INSET_M := 19.6              # 블록을 도로 중심선에서 띄우는 거리 (퍼즐 공장과 같게)
const OUTSKIRT_NAMES := ["테헤란로", "강남대로", "도산대로", "봉은사로", "논현로", "삼성로", "압구정로",
		"남부순환로", "개포로", "헌릉로", "천호대로", "아차산로", "광나루로", "왕십리로", "고산자로", "동일로"]

var route := PackedVector2Array()        # 월드 좌표(m, x=동, y=북)
var progress := 0.0                      # 내 차 진행률 0..1
var view_mode := "follow"
var follow_scale := 0.32                 # px/m
var overlay_drawer: Callable             # 사건 오버레이 그리기 (E 단계): func(map: NavMap)
var heading_target := Vector2.ZERO       # 따라가기 보기의 진행 방향(월드). 주행 시뮬레이션이 넣는다
var tunnel_spans: Array[Vector2] = []    # 터널 구간 (시작 진행률, 끝 진행률)
var stop_points: Array[float] = []       # 아직 안 지난 신호 대기 지점 진행률
var turn_marks: Array[Vector2] = []      # 회전 안내 (진행률, -1 좌회전 / +1 우회전)
var dest_name := ""
var view_insets := Vector4.ZERO          # 전체 보기에서 카드가 가리는 여백(왼, 위, 오른, 아래 px)
var _insets := Vector4.ZERO              # 실제로 쓰는 여백. view_insets를 부드럽게 따라간다
var _insets_ready := false
var extra_points: Array[Vector2] = []    # 전체 보기에 함께 담을 지점(사건 장소 등)
## 기울인 지도(MapView3D)에서 쓴다: 이 노드는 화면이 아니라 3D 판에 붙일 텍스처에 그린다.
## fit_rect(이 노드 px)가 있으면 전체 보기는 그 안에 맞추고, follow_anchor가 있으면 내 차를 그 자리에 둔다.
var fit_rect := Rect2()
var follow_anchor := Vector2(-1, -1)
var city_data: Dictionary = {}           # set_city로 받은 도시(기울인 지도가 블록 건물을 세울 때 쓴다)
## 경유지 표시: [{p: 진행률, label: "⑤ 전통시장"}]. 지나가면 회색.
var waypoint_marks: Array[Dictionary] = []
## 처음 경로. 진술 속 "경로 오른편", "③~⑥ 구간"은 경로가 바뀌어도 이 경로 기준이다(단서 그리기용).
var base_route := PackedVector2Array()
var _base_cum := PackedFloat32Array()
var _old_route := PackedVector2Array()   # 재탐색 연출: 흐려지며 사라지는 옛 경로
var _reroute_t := 1.0                    # 재탐색 연출 진행 0..1 (새 경로가 출발점부터 그려진다)
var _rot := 0.0
var _rot_ready := false

var _cum := PackedFloat32Array()
var _xf := Transform2D.IDENTITY          # 월드(y 뒤집힘) → 화면
var _scale := 1.0
var _time := 0.0
var _view_box := Rect2()                 # 화면에 보이는 월드 영역(여유 포함)
var _dest_style: StyleBoxFlat
var _city_layer: Control                 # 도시 바탕 층 (이 노드 뒤에 그린다)
var _ci: CanvasItem                      # 도시 그리기 함수들이 그릴 대상(= _city_layer)
var _city_xf := Transform2D.IDENTITY     # 도시 층을 마지막으로 그린 보기
var _city_size := Vector2(-1, -1)

# 팩의 가상 도시
var _has_city := false
var _area_mesh: ArrayMesh                # 블록·공원·강 (y 뒤집힌 월드 좌표, 한 번에 그린다)
var _chains := {}                        # 등급 → [{pts, box}] 같은 이름 도로를 이어 붙인 선
var _labels := {}                        # 등급 → [{pos, dir, text}] 이름 자리(월드 좌표로 고정)

# 가짜 도시 (예전 팩)
var _streets: Array[PackedVector2Array] = []
var _majors: Array[PackedVector2Array] = []
var _parks: Array[PackedVector2Array] = []
var _water: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	# 핀 썸네일을 작게 줄여 그리므로 밉맵을 쓴다
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_city_layer = Control.new()
	_city_layer.show_behind_parent = true
	_city_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_city_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_city_layer.draw.connect(_on_city_layer_draw)
	add_child(_city_layer)
	_ci = _city_layer


## 도시 층을 다음 프레임에 다시 그리게 한다(데이터가 바뀌었을 때).
func _invalidate_city() -> void:
	_city_size = Vector2(-1, -1)
	queue_redraw()


func set_route(points: PackedVector2Array, seed_value := 7) -> void:
	route = points
	_cum = _cumulate(route)
	if base_route.is_empty():
		base_route = points
		_base_cum = _cum
	if not _has_city:
		_build_fake_city(seed_value)
	else:
		_measure_labels()
	_invalidate_city()


## 경유지 재탐색: 새 경로로 바꾸고, 옛 경로는 흐려지며 사라지고 새 경로가 출발점부터 그려진다.
func reroute(points: PackedVector2Array) -> void:
	_old_route = route.duplicate()
	set_route(points)
	_reroute_t = 0.0


static func _cumulate(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		c.append(c[i - 1] + pts[i].distance_to(pts[i - 1]))
	return c


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()


func route_length() -> float:
	return _cum[_cum.size() - 1] if _cum.size() > 0 else 0.0


func _process(delta: float) -> void:
	_time += delta
	if _reroute_t < 1.0:
		_reroute_t = minf(1.0, _reroute_t + delta / 1.8)
	if route.size() >= 2:
		var dir: Vector2 = heading_target if heading_target != Vector2.ZERO else route_point(progress)[1]
		var target := -PI / 2.0 - Vector2(dir.x, -dir.y).angle()
		if not _rot_ready:
			_rot = target
			_rot_ready = true
		else:
			_rot = lerp_angle(_rot, target, clampf(delta * 2.5, 0.0, 1.0))
	if not _insets_ready or view_mode != "overview":
		_insets = view_insets
		_insets_ready = view_insets != Vector4.ZERO
	elif _insets != view_insets:
		_insets = _insets.lerp(view_insets, clampf(delta * 4.0, 0.0, 1.0))
		# 거의 다 왔으면 맞춰 끝낸다 (보기가 멈춰야 도시 층을 다시 그리지 않는다)
		if (_insets - view_insets).abs().dot(Vector4.ONE) < 0.5:
			_insets = view_insets
	queue_redraw()


# ---------------------------------------------------------------- 좌표

## 월드(m, y=북) → 화면 좌표
func to_screen(w: Vector2) -> Vector2:
	return _xf * Vector2(w.x, -w.y)


func px_per_m() -> float:
	return _scale


## 월드(m, (x, -y)) → 이 노드 px 변환. 기울인 지도가 3D 판 좌표로 옮길 때 쓴다.
func view_xform() -> Transform2D:
	return _xf


func route_point(frac: float) -> Array:
	## [위치, 진행 방향 단위벡터] (월드 좌표)
	return _point_on(route, _cum, frac)


## 처음 경로(단서 기준) 위의 점. frac은 처음 경로의 진행률(장소의 routePos와 같은 기준).
func base_point(frac: float) -> Array:
	return _point_on(base_route, _base_cum, frac)


static func _point_on(pts: PackedVector2Array, cum: PackedFloat32Array, frac: float) -> Array:
	if pts.size() < 2:
		return [Vector2.ZERO, Vector2.RIGHT]
	var target := clampf(frac, 0.0, 1.0) * cum[cum.size() - 1]
	for i in range(1, pts.size()):
		if cum[i] >= target:
			var seg := cum[i] - cum[i - 1]
			var t := 0.0 if seg == 0.0 else (target - cum[i - 1]) / seg
			return [pts[i - 1].lerp(pts[i], t), (pts[i] - pts[i - 1]).normalized()]
	var n := pts.size()
	return [pts[n - 1], (pts[n - 1] - pts[n - 2]).normalized()]


func _update_transform() -> void:
	if route.size() < 2:
		return
	if view_mode == "overview":
		var lo := route[0]
		var hi := route[0]
		for v in route:
			lo = lo.min(v)
			hi = hi.max(v)
		for v2 in extra_points:
			lo = lo.min(v2)
			hi = hi.max(v2)
		var world := (hi - lo).max(Vector2(1000, 1000))
		var avail := Rect2(Vector2(_insets.x, _insets.y),
				size - Vector2(_insets.x + _insets.z, _insets.y + _insets.w))
		if fit_rect.size.x > 0.0:
			avail = fit_rect
		if avail.size.x < 200.0 or avail.size.y < 200.0:
			avail = Rect2(Vector2.ZERO, size)
		# 가장자리 핀과 이름이 카드에 걸리지 않게 화면 여백(px)을 둔다
		avail = avail.grow_individual(-44.0, -40.0, -44.0, -52.0)
		_scale = minf(avail.size.x / world.x, avail.size.y / world.y)
		var center := (lo + hi) / 2.0
		_xf = Transform2D(0.0, Vector2(_scale, _scale), 0.0, avail.get_center()) \
				* Transform2D(0.0, Vector2.ONE, 0.0, -Vector2(center.x, -center.y))
	else:
		var pos: Vector2 = route_point(progress)[0]
		_scale = follow_scale
		var anchor := Vector2(size.x * 0.5, size.y * 0.68) if follow_anchor.x < 0.0 else follow_anchor
		# 진행 방향이 화면 위쪽 (_process에서 부드럽게 따라간다)
		_xf = Transform2D(_rot, Vector2(_scale, _scale), 0.0, anchor) \
				* Transform2D(0.0, Vector2.ONE, 0.0, -Vector2(pos.x, -pos.y))
	# 화면에 보이는 월드 영역 (도시 그리기 범위 줄이기)
	var inv := _xf.affine_inverse()
	var box := Rect2()
	var first := true
	for c in [Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		var w: Vector2 = inv * c
		w.y = -w.y
		if first:
			box = Rect2(w, Vector2.ZERO)
			first = false
		else:
			box = box.expand(w)
	_view_box = box.grow(120.0)


# ---------------------------------------------------------------- 팩의 가상 도시

## 퍼즐 팩 v3의 `city`를 쓴다. route_nodes는 `routePlan.nodes`(경로가 지나는 교차로)로,
## 경로 위 도로에는 이름 라벨을 달지 않는다. 빈 사전이면 가짜 도시로 돌아간다.
func set_city(city: Dictionary, route_nodes: Array = [], seed_value := 7) -> void:
	city_data = city
	_has_city = not city.is_empty() and city.has("roads")
	_chains.clear()
	_labels.clear()
	_area_mesh = null
	if not _has_city:
		if route.size() >= 2:
			_build_fake_city(7)
		_invalidate_city()
		return
	_streets.clear()
	_majors.clear()
	_parks.clear()
	_water = PackedVector2Array()
	var nodes := PackedVector2Array()
	for n in city["nodes"]:
		nodes.append(Vector2(float(n[0]), float(n[1])))
	var layers := {"blocks": _polys(city.get("blocks", [])), "parks": _polys(city.get("parks", [])),
			"water": _polys(city.get("water", []))}
	var roads: Array = city["roads"].duplicate()
	# 도시 바깥 외곽(그림만)을 덧붙인다
	var ring := _outskirts(city, nodes, seed_value)
	if not ring.is_empty():
		nodes = ring["nodes"]
		roads.append_array(ring["roads"])
		for k in layers:
			layers[k].append_array(ring[k])
	var on_route := {}
	for i in range(1, route_nodes.size()):
		on_route[_edge_key(int(route_nodes[i - 1]), int(route_nodes[i]))] = true
	_area_mesh = _build_area_mesh(layers)
	for cls in ROAD_CLASSES:
		_chains[cls] = []
		_labels[cls] = []
	_labels["water"] = []
	_build_chains(roads, nodes, on_route)
	for w in city.get("water", []):
		_build_water_labels(w)
	_measure_labels()
	_invalidate_city()


static func _polys(list: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for poly_data in list:
		var poly := PackedVector2Array()
		for q in poly_data:
			poly.append(Vector2(float(q[0]), float(q[1])))
		out.append(poly)
	return out


## 이름 자리마다 경로선까지 거리(m)를 재 둔다. 그릴 때 글자가 경로선에 걸리면 건너뛴다.
func _measure_labels() -> void:
	for cls in _labels:
		for lb in _labels[cls]:
			var best := INF
			for i in range(1, route.size()):
				var q := Geometry2D.get_closest_point_to_segment(lb["pos"], route[i - 1], route[i])
				best = minf(best, q.distance_to(lb["pos"]))
			lb["route_d"] = best


static func _edge_key(a: int, b: int) -> int:
	return mini(a, b) * 100000 + maxi(a, b)


## layers: {"blocks"/"parks"/"water": 월드 좌표 폴리곤 목록}
func _build_area_mesh(layers: Dictionary) -> ArrayMesh:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	# 아래 층부터: 블록 → 공원 → 강
	for layer in [["blocks", PleosTheme.MAP_BLOCK], ["parks", PleosTheme.MAP_PARK],
			["water", PleosTheme.MAP_WATER]]:
		for world_poly in layers.get(layer[0], []):
			var poly := PackedVector2Array()
			for q in world_poly:
				poly.append(Vector2(q.x, -q.y))
			var tri := Geometry2D.triangulate_polygon(poly)
			if tri.is_empty():
				continue
			var base := verts.size()
			verts.append_array(poly)
			for _k in range(poly.size()):
				cols.append(layer[1])
			for t in tri:
				idx.append(base + t)
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## 같은 등급·이름의 도로 조각을 한 줄로 이어 붙인다(그리기 호출 수를 줄이고 이름 자리를 고르기 위해).
func _build_chains(roads: Array, nodes: PackedVector2Array, on_route: Dictionary) -> void:
	var groups := {}
	for r in roads:
		# 외곽 도로는 이름이 없을 수 있어 줄(행·열)마다 따로 묶는 key를 갖고 온다
		var key := String(r.get("key", "%s|%s" % [r["cls"], r["name"]]))
		groups.get_or_add(key, []).append(r)
	for key in groups:
		var es: Array = groups[key]
		var cls := String(es[0]["cls"])
		var road_name := String(es[0]["name"])
		if not _chains.has(cls):
			continue
		var adj := {}
		for i in range(es.size()):
			adj.get_or_add(int(es[i]["a"]), []).append(i)
			adj.get_or_add(int(es[i]["b"]), []).append(i)
		# 끝점(이어지는 조각이 2개가 아닌 교차로)에서 먼저 출발하고, 고리가 남으면 아무 데서나
		var starts: Array[int] = []
		for n in adj:
			if adj[n].size() != 2:
				starts.append(n)
		for n2 in adj:
			starts.append(n2)
		var used := {}
		for s0 in starts:
			for e0 in adj[s0]:
				if used.has(e0):
					continue
				var pts := PackedVector2Array([nodes[s0]])
				var keys: Array[int] = []
				var cur: int = s0
				var e: int = e0
				while true:
					used[e] = true
					var a := int(es[e]["a"])
					var b := int(es[e]["b"])
					var nxt := b if a == cur else a
					pts.append(nodes[nxt])
					keys.append(_edge_key(a, b))
					cur = nxt
					var cont := -1
					if adj[cur].size() == 2:
						for e2 in adj[cur]:
							if not used.has(e2):
								cont = e2
					if cont == -1:
						break
					e = cont
				_add_chain(cls, road_name, pts, keys, on_route)


func _add_chain(cls: String, road_name: String, pts: PackedVector2Array, keys: Array[int],
		on_route: Dictionary) -> void:
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	_chains[cls].append({"pts": pts, "box": box})
	if road_name == "":
		return
	# 이름 자리: 줄을 따라 일정 간격(다리는 가운데 하나). 경로가 지나는 조각은 건너뛴다.
	var seg_len: Array[float] = []
	var total := 0.0
	for i in range(1, pts.size()):
		seg_len.append(pts[i].distance_to(pts[i - 1]))
		total += seg_len[i - 1]
	var gap: float = LABEL_GAP[cls]
	var marks: Array[float] = []
	if gap <= 0.0 or total < gap:
		if total >= 250.0:
			marks.append(total / 2.0)
	else:
		var d := gap / 2.0
		while d < total:
			marks.append(d)
			d += gap
	for m in marks:
		var acc := 0.0
		for i in range(seg_len.size()):
			if acc + seg_len[i] >= m:
				if not on_route.has(keys[i]):
					var dir := (pts[i + 1] - pts[i]).normalized()
					_labels[cls].append({"pos": pts[i] + dir * (m - acc), "dir": dir, "text": road_name})
				break
			acc += seg_len[i]


## 강 폴리곤(위쪽 기슭 → 아래쪽 기슭 거꾸로)의 가운데 선을 따라 "한강" 이름 자리를 만든다.
func _build_water_labels(poly_data: Array) -> void:
	var n := poly_data.size() / 2
	if n < 2:
		return
	var center := PackedVector2Array()
	for i in range(n):
		var top := Vector2(float(poly_data[i][0]), float(poly_data[i][1]))
		var bottom := Vector2(float(poly_data[poly_data.size() - 1 - i][0]),
				float(poly_data[poly_data.size() - 1 - i][1]))
		center.append((top + bottom) / 2.0)
	var gap: float = LABEL_GAP["water"]
	var acc := 0.0
	var next := gap * 0.35
	for i in range(1, center.size()):
		var seg := center[i].distance_to(center[i - 1])
		while acc + seg >= next:
			var dir := (center[i] - center[i - 1]).normalized()
			_labels["water"].append({"pos": center[i - 1] + dir * (next - acc), "dir": dir, "text": "한강"})
			next += gap
		acc += seg


# ---------------------------------------------------------------- 도시 바깥 외곽 (그림만)

## 팩 도시의 격자 크기. 팩에 `grid`가 없으면 노드 배치(행 우선)와 다리로 짐작한다.
static func _grid_meta(city: Dictionary, nodes: PackedVector2Array) -> Dictionary:
	if city.has("grid"):
		var g: Dictionary = city["grid"]
		return {"cols": int(g["cols"]), "rows": int(g["rows"]), "river": int(g.get("river", -1))}
	if nodes.size() < 4:
		return {}
	var cols := 1
	while cols < nodes.size() and absf(nodes[cols].y - nodes[0].y) < 150.0:
		cols += 1
	if cols < 2 or nodes.size() % cols != 0:
		return {}
	var river := -1
	for r in city["roads"]:
		if String(r["cls"]) == "bridge":
			river = mini(int(r["a"]), int(r["b"])) / cols
			break
	return {"cols": cols, "rows": nodes.size() / cols, "river": river}


## 팩 도시는 경로 둘레만 있어서 전체 보기로 줄이면 가장자리가 비어 보인다.
## 격자선을 바깥으로 곧게 이어 외곽 동네를 덧붙인다(블록, 공원, 강 연장, 도로).
## 경로·퍼즐과는 상관없는 그림이다. 도시 안 행·열은 같은 등급과 이름으로 이어진다.
## 돌려주는 것: {nodes(도시 노드 + 외곽 노드), roads, blocks, parks, water}
func _outskirts(city: Dictionary, nodes: PackedVector2Array, seed_value: int) -> Dictionary:
	var g := _grid_meta(city, nodes)
	if g.is_empty():
		return {}
	var nc: int = g["cols"]
	var nr: int = g["rows"]
	var river: int = g["river"]
	var kx := OUTSKIRT_COLS
	var ky := OUTSKIRT_ROWS
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	# 바깥 칸 간격 누적: [왼쪽, 오른쪽, 아래(남), 위(북)]
	var steps := []
	for k in range(4):
		var acc := [0.0]
		for _n in range(kx if k < 2 else ky):
			acc.append(acc[acc.size() - 1] + rng.randf_range(380.0, 520.0))
		steps.append(acc)
	# 도시 안 행·열의 등급과 이름 (가장자리에서 그대로 이어 간다)
	var row_road := {}
	var col_road := {}
	var used_names := {}
	for r in city["roads"]:
		var a := int(r["a"])
		var b := int(r["b"])
		used_names[String(r["name"])] = true
		if a / nc == b / nc:
			row_road[a / nc] = r
		elif String(r["cls"]) != "bridge":
			col_road[a % nc] = r
	var spare: Array = []
	for nm in OUTSKIRT_NAMES:
		if not used_names.has(nm):
			spare.append(nm)
	# 노드
	var out_nodes := nodes.duplicate()
	var at := {}
	for j in range(-ky, nr + ky):
		for i in range(-kx, nc + kx):
			if i >= 0 and i < nc and j >= 0 and j < nr:
				at[Vector2i(i, j)] = j * nc + i
				continue
			var ic := clampi(i, 0, nc - 1)
			var jc := clampi(j, 0, nr - 1)
			var off := Vector2.ZERO
			if i < 0:
				off.x = -float(steps[0][-i])
			elif i >= nc:
				off.x = float(steps[1][i - nc + 1])
			if j < 0:
				off.y = -float(steps[2][-j])
			elif j >= nr:
				off.y = float(steps[3][j - nr + 1])
			at[Vector2i(i, j)] = out_nodes.size()
			out_nodes.append(nodes[jc * nc + ic] + off
					+ Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0)))
	# 줄마다 등급·이름·묶음 key. 도시 밖 줄은 다섯 줄마다 큰길.
	var lines := {}
	for j in range(-ky, nr + ky):
		lines["r%d" % j] = _outskirt_line(row_road.get(j, {}), j >= 0 and j < nr, posmod(j - 2, 5) == 0,
				"r%d" % j, spare)
	for i in range(-kx, nc + kx):
		lines["c%d" % i] = _outskirt_line(col_road.get(i, {}), i >= 0 and i < nc, posmod(i - 2, 5) == 0,
				"c%d" % i, spare)
	var roads := []
	for j in range(-ky, nr + ky):
		for i in range(-kx, nc + kx):
			var core := i >= 0 and i < nc and j >= 0 and j < nr
			# 가로 (i,j)-(i+1,j)
			if i + 1 < nc + kx and not (core and i + 1 < nc):
				_outskirt_road(roads, lines["r%d" % j], at[Vector2i(i, j)], at[Vector2i(i + 1, j)], rng)
			# 세로 (i,j)-(i,j+1). 강을 건너는 길은 도시 밖에 없다.
			if j + 1 < nr + ky and j != river and not (core and j + 1 < nr):
				_outskirt_road(roads, lines["c%d" % i], at[Vector2i(i, j)], at[Vector2i(i, j + 1)], rng)
	# 블록·공원 (강 칸은 비운다)
	var blocks: Array[PackedVector2Array] = []
	var parks: Array[PackedVector2Array] = []
	for j in range(-ky, nr + ky - 1):
		if j == river:
			continue
		for i in range(-kx, nc + kx - 1):
			if i >= 0 and i < nc - 1 and j >= 0 and j < nr - 1:
				continue
			var corners: Array[Vector2] = [out_nodes[at[Vector2i(i, j)]], out_nodes[at[Vector2i(i + 1, j)]],
					out_nodes[at[Vector2i(i + 1, j + 1)]], out_nodes[at[Vector2i(i, j + 1)]]]
			var c: Vector2 = (corners[0] + corners[1] + corners[2] + corners[3]) / 4.0
			var poly := PackedVector2Array()
			for p in corners:
				poly.append(p + (c - p).normalized() * BLOCK_INSET_M)
			(parks if rng.randf() < 0.06 else blocks).append(poly)
	# 강을 동서로 늘인다
	var water: Array[PackedVector2Array] = []
	var west: float = out_nodes[at[Vector2i(-kx, 0)]].x - 600.0
	var east: float = out_nodes[at[Vector2i(nc + kx - 1, 0)]].x + 600.0
	for w: Array in city.get("water", []):
		var n: int = w.size() / 2
		if n < 2:
			continue
		var t0 := Vector2(float(w[0][0]), float(w[0][1]))
		var b0 := Vector2(float(w[w.size() - 1][0]), float(w[w.size() - 1][1]))
		var t1 := Vector2(float(w[n - 1][0]), float(w[n - 1][1]))
		var b1 := Vector2(float(w[n][0]), float(w[n][1]))
		water.append(PackedVector2Array([Vector2(west, t0.y), t0 + Vector2(1, 0), b0 + Vector2(1, 0),
				Vector2(west, b0.y)]))
		water.append(PackedVector2Array([t1 - Vector2(1, 0), Vector2(east, t1.y), Vector2(east, b1.y),
				b1 - Vector2(1, 0)]))
	return {"nodes": out_nodes, "roads": roads, "blocks": blocks, "parks": parks, "water": water}


## 외곽 줄 하나의 등급·이름·묶음 key. 도시 안 줄을 잇는 경우 도시 쪽과 같은 key라 한 줄로 이어진다.
static func _outskirt_line(core_road: Dictionary, in_city: bool, major: bool, tag: String,
		spare: Array) -> Dictionary:
	if in_city:
		if core_road.is_empty():
			return {"cls": "local", "name": "", "key": "out-" + tag}
		return {"cls": String(core_road["cls"]), "name": String(core_road["name"]),
				"key": "%s|%s" % [core_road["cls"], core_road["name"]]}
	if major:
		return {"cls": "arterial", "name": spare.pop_front() if not spare.is_empty() else "", "key": "out-" + tag}
	return {"cls": "local", "name": "", "key": "out-" + tag}


static func _outskirt_road(roads: Array, line: Dictionary, a: int, b: int, rng: RandomNumberGenerator) -> void:
	# 이면도로는 조금 끊어 격자를 덜 반듯하게
	if line["cls"] == "local" and rng.randf() < 0.08:
		return
	roads.append({"a": a, "b": b, "cls": line["cls"], "name": line["name"], "key": line["key"]})


# ---------------------------------------------------------------- 가짜 도시 (예전 팩)

func _build_fake_city(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_streets.clear()
	_majors.clear()
	_parks.clear()
	var lo := route[0]
	var hi := route[0]
	for v in route:
		lo = lo.min(v)
		hi = hi.max(v)
	lo -= Vector2(5000, 5000)
	hi += Vector2(5000, 5000)
	# 잔도로: 비스듬한 격자
	var ang := rng.randf_range(-0.25, 0.25)
	var ax := Vector2(cos(ang), sin(ang))
	var ay := Vector2(-ax.y, ax.x)
	var span := (hi - lo).length()
	var center := (lo + hi) / 2.0
	var step := 420.0
	var k := -span / 2.0
	while k < span / 2.0:
		for axis in [ax, ay]:
			var other: Vector2 = ay if axis == ax else ax
			var base: Vector2 = center + other * (k + rng.randf_range(-60, 60))
			var line := PackedVector2Array()
			var t := -span / 2.0
			while t <= span / 2.0:
				line.append(base + axis * t + other * rng.randf_range(-25, 25))
				t += 600.0
			_streets.append(line)
		k += step + rng.randf_range(-80, 120)
	# 큰길: 경로와 교차하는 몇 개
	for _i in range(4):
		var p0 := Vector2(rng.randf_range(lo.x, hi.x), lo.y)
		var line2 := PackedVector2Array()
		var yy := lo.y
		var xx := p0.x
		while yy <= hi.y:
			line2.append(Vector2(xx, yy))
			yy += 500.0
			xx += rng.randf_range(-260, 260)
		_majors.append(line2)
	# 강: 경로 북쪽을 가로지르는 띠
	var river_y := hi.y - 5000.0 + rng.randf_range(1800, 2600)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var x := lo.x
	while x <= hi.x:
		var y := river_y + sin(x / 2300.0) * 520.0
		top.append(Vector2(x, y + 260))
		bottom.append(Vector2(x, y - 260))
		x += 300.0
	bottom.reverse()
	_water = top + bottom
	# 공원
	for _j in range(9):
		var pc := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var r := rng.randf_range(180, 520)
		var poly := PackedVector2Array()
		for a in range(14):
			var ang2 := a * TAU / 14.0
			poly.append(pc + Vector2(cos(ang2) * r * rng.randf_range(0.8, 1.2), sin(ang2) * r * 0.7))
		_parks.append(poly)


# ---------------------------------------------------------------- 그리기

func _w(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(to_screen(p))
	return out


## 도시 바탕(땅, 블록, 도로, 이름)은 뒤 층(_city_layer)에 그리고, 지도 보기가 바뀔 때만 다시 그린다.
## 전체 보기처럼 지도가 멈춰 있으면 도로 수백 줄을 매 프레임 다시 그리지 않는다.
## 이 노드는 그 위에 경로, 화살표, 사건 오버레이, 내 차처럼 자주 바뀌는 것만 매 프레임 그린다.
func _draw() -> void:
	if route.size() < 2:
		return
	_update_transform()
	if _xf != _city_xf or size != _city_size:
		_city_xf = _xf
		_city_size = size
		_city_layer.queue_redraw()
	_draw_route()
	_draw_tunnels()
	_draw_turn_arrows()
	_draw_waypoints()
	_draw_stops()
	if overlay_drawer.is_valid():
		overlay_drawer.call(self)
	_draw_destination()
	_draw_car()


## 도로 폭(px). 실제 폭에 가깝게 줄이되 너무 얇거나 두꺼워지지 않게 한다.
func _road_px(cls: String) -> float:
	if cls == "local":
		return clampf(36.0 * _scale, 2.0, 11.0)
	return clampf(64.0 * _scale, 3.5, 19.0)


func _on_city_layer_draw() -> void:
	_ci = _city_layer
	_ci.draw_rect(Rect2(Vector2.ZERO, size), PleosTheme.MAP_LAND)
	if route.size() < 2:
		return
	if _has_city:
		_draw_city()
		_draw_labels()
	else:
		_draw_fake_city()


func _draw_city() -> void:
	if _area_mesh != null:
		_ci.draw_mesh(_area_mesh, null, _xf)
	var lw := _road_px("local")
	var aw := _road_px("arterial")
	# 이면도로 → 다리 → 큰길 순서로 덮는다 (큰길 테두리가 이면도로를 끊어 위계가 보이게,
	# 강변 큰길이 다리 끝을 덮어 다리는 물 위만 보이게)
	_stroke_class("local", PleosTheme.MAP_ROAD_CASE, lw + 2.0, PleosTheme.MAP_ROAD, lw)
	# 다리 난간은 경로선(흰 테두리 포함)보다 넓게 해서 경로가 지나는 다리도 보이게
	_stroke_class("bridge", PleosTheme.MAP_BRIDGE_CASE, aw + maxf(8.0, 52.0 * _scale),
			PleosTheme.MAP_MAJOR, aw, false)
	_stroke_class("arterial", PleosTheme.MAP_MAJOR_CASE, aw + 3.0, PleosTheme.MAP_MAJOR, aw)


func _stroke_class(cls: String, case_col: Color, case_w: float, fill_col: Color, fill_w: float,
		round_caps := true) -> void:
	var lines: Array[PackedVector2Array] = []
	for ch in _chains.get(cls, []):
		if _view_box.intersects(ch["box"]):
			lines.append(_w(ch["pts"]))
	for ps in lines:
		_stroke(ps, case_col, case_w, round_caps)
	for ps2 in lines:
		_stroke(ps2, fill_col, fill_w, round_caps)


## 선 그리기. round_caps면 교차로 모서리가 비지 않게 양 끝에 원을 찍는다(가는 선은 티가 안 나 생략).
func _stroke(ps: PackedVector2Array, color: Color, width: float, round_caps := true) -> void:
	_ci.draw_polyline(ps, color, width, true)
	if round_caps and width >= 6.0:
		_ci.draw_circle(ps[0], width * 0.5, color, true, -1.0, true)
		_ci.draw_circle(ps[ps.size() - 1], width * 0.5, color, true, -1.0, true)


## 도로·다리·강 이름. 월드에 고정된 자리 중 화면 안에 있고 앞서 그린 이름과 겹치지 않는 것만 그린다.
func _draw_labels() -> void:
	var font := PleosTheme.font(false)
	var bold := PleosTheme.font(true)
	var screen := Rect2(Vector2.ZERO, size).grow(-24.0)
	var taken: Array[Rect2] = []
	var drawn := {}                      # 이름 → 이미 그린 화면 위치들 (같은 이름은 멀리 떨어져야 다시 쓴다)
	# 중요한 것부터 자리를 잡는다
	for cls in ["bridge", "arterial", "water", "local"]:
		if cls == "local" and _scale < LOCAL_LABEL_SCALE:
			continue
		var fs := 15 if cls == "local" else (19 if cls == "water" else 17)
		var col := PleosTheme.MAP_LABEL
		if cls == "local":
			col = PleosTheme.MAP_LABEL_MINOR
		elif cls == "water":
			col = PleosTheme.MAP_LABEL_WATER
		var f := bold if cls == "bridge" else font
		for lb in _labels.get(cls, []):
			if not _view_box.has_point(lb["pos"]):
				continue
			var sp := to_screen(lb["pos"])
			if not screen.has_point(sp):
				continue
			var d := to_screen(lb["pos"] + lb["dir"] * 10.0) - sp
			var ang := d.angle()
			if ang > PI / 2.0:
				ang -= PI
			elif ang < -PI / 2.0:
				ang += PI
			var text: String = lb["text"]
			var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var half := Vector2(tw / 2.0 + 8.0, fs * 0.75)
			var ext := Vector2(absf(cos(ang)) * half.x + absf(sin(ang)) * half.y,
					absf(sin(ang)) * half.x + absf(cos(ang)) * half.y)
			if float(lb.get("route_d", INF)) * _scale < half.x + 14.0:
				continue
			var rect := Rect2(sp - ext, ext * 2.0)
			var clash := false
			for t in taken:
				if t.intersects(rect):
					clash = true
					break
			for q in drawn.get(text, []):
				if q.distance_to(sp) < LABEL_REPEAT_PX:
					clash = true
					break
			if clash:
				continue
			taken.append(rect)
			drawn.get_or_add(text, []).append(sp)
			_ci.draw_set_transform(sp, ang)
			var at := Vector2(-tw / 2.0, fs * 0.36)
			_ci.draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(1, 1, 1, 0.92))
			_ci.draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	_ci.draw_set_transform(Vector2.ZERO)


func _draw_fake_city() -> void:
	_ci.draw_colored_polygon(_w(_water), PleosTheme.MAP_WATER)
	for p in _parks:
		_ci.draw_colored_polygon(_w(p), PleosTheme.MAP_PARK)
	var street_w := clampf(90.0 * _scale, 2.0, 14.0)
	for s in _streets:
		var ps := _w(s)
		_ci.draw_polyline(ps, PleosTheme.MAP_ROAD_CASE, street_w + 2.0, true)
	for s in _streets:
		_ci.draw_polyline(_w(s), PleosTheme.MAP_ROAD, street_w, true)
	var major_w := clampf(160.0 * _scale, 4.0, 22.0)
	for m in _majors:
		_ci.draw_polyline(_w(m), PleosTheme.MAP_MAJOR_CASE, major_w + 3.0, true)
	for m in _majors:
		_ci.draw_polyline(_w(m), PleosTheme.MAP_MAJOR, major_w, true)


func _draw_route() -> void:
	var width := clampf(140.0 * _scale, 9.0, 20.0)
	# 재탐색 중: 옛 경로는 흐려지고, 새 경로는 출발점부터 자라난다
	var shown := 1.0
	if _reroute_t < 1.0 and _old_route.size() >= 2:
		var fade := 1.0 - _reroute_t
		var old := _w(_old_route)
		draw_polyline(old, Color(1, 1, 1, 0.8 * fade), width + 8.0, true)
		draw_polyline(old, Color(PleosTheme.MAP_ROUTE_DONE, fade), width, true)
		shown = ease(_reroute_t, 0.6)
	var all := _w(route) if shown >= 1.0 else slice(0.0, shown, 120)
	draw_polyline(all, Color.WHITE, width + 8.0, true)
	draw_polyline(all, PleosTheme.MAP_ROUTE, width, true)
	# 지나온 구간은 회색
	var upto := minf(progress, shown)
	var done := PackedVector2Array()
	var target := upto * _cum[_cum.size() - 1]
	var pts := _w(route)
	for i in range(route.size()):
		if _cum[i] <= target:
			done.append(pts[i])
	done.append(to_screen(route_point(upto)[0]))
	if done.size() >= 2:
		draw_polyline(done, PleosTheme.MAP_ROUTE_DONE, width, true)


## 경유지 배지: 경로 위 정차 지점에 깃발 원 + "경유 · 장소" 말풍선. 지나가면 회색.
func _draw_waypoints() -> void:
	if _reroute_t < 0.8:
		return
	var f := PleosTheme.font(true)
	for m in waypoint_marks:
		var fr := float(m["p"])
		var passed := progress > fr + 0.0005
		var col := PleosTheme.MAP_ROUTE_DONE if passed else COL_WAYPOINT
		var p := to_screen(route_point(fr)[0])
		draw_circle(p + Vector2(0, 2), 17.0, Color(0, 0, 0, 0.14), true, -1.0, true)
		draw_circle(p, 16.0, Color.WHITE, true, -1.0, true)
		draw_circle(p, 13.0, col, true, -1.0, true)
		# 깃발
		draw_line(p + Vector2(-4, 7), p + Vector2(-4, -7), Color.WHITE, 2.0, true)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -7), p + Vector2(6, -4), p + Vector2(-3, -1)]),
				Color.WHITE)
		var text := "경유 · %s" % m.get("label", "")
		var fs := 17
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rect := Rect2(p + Vector2(22.0, -15.0), Vector2(tw + 22.0, 30.0))
		draw_style_box(_dest_box(), rect)
		draw_string(f, rect.position + Vector2(11.0, 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.darkened(0.1))


## 처음 경로(단서 기준) 진행률 a~b 구간의 화면 좌표.
func base_slice(a: float, b: float, samples := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(samples + 1):
		out.append(to_screen(base_point(lerpf(a, b, float(k) / samples))[0]))
	return out


## 경로 진행률 a~b 구간의 화면 좌표.
func slice(a: float, b: float, samples := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(samples + 1):
		out.append(to_screen(route_point(lerpf(a, b, float(k) / samples))[0]))
	return out


func _draw_tunnels() -> void:
	var width := clampf(140.0 * _scale, 9.0, 20.0)
	for span in tunnel_spans:
		var pts := slice(span.x, span.y)
		draw_polyline(pts, Color("6f7a89"), width + 6.0, true)
		draw_polyline(pts, Color("97a2b0"), width - 2.0, true)
		for k in range(0, pts.size() - 1, 2):
			draw_line(pts[k], pts[k + 1], Color(1, 1, 1, 0.8), 2.0, true)


## 아직 안 지난 회전 지점마다 경로선 위에 흰 화살표(꺾이는 모양 그대로)를 얹는다.
func _draw_turn_arrows() -> void:
	if _scale < TURN_ARROW_SCALE or turn_marks.is_empty():
		return
	var total := route_length()
	if total <= 0.0:
		return
	var body := clampf(26.0 * _scale, 5.0, 8.5)
	var screen := Rect2(Vector2.ZERO, size).grow(60.0)
	var outline := PleosTheme.MAP_ROUTE.darkened(0.45)
	# 화면에서 회전 전 70px, 회전 뒤 46px 정도
	var before := minf(70.0 / _scale, 320.0) / total
	var after := minf(46.0 / _scale, 220.0) / total
	for m in turn_marks:
		if m.x * total < progress * total - 8.0:
			continue
		var pts := slice(maxf(m.x - before, progress), minf(m.x + after, 1.0), 18)
		if pts[0].distance_to(pts[pts.size() - 1]) < 20.0:
			continue
		if not screen.has_point(pts[9]):
			continue
		var tip := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		var n := Vector2(-tip.y, tip.x)
		var base := pts[pts.size() - 1]
		var hw := body * 1.45
		var hl := body * 1.7
		var head := PackedVector2Array([base + tip * hl, base + n * hw, base - n * hw])
		var head_o := PackedVector2Array([base + tip * (hl + 3.5), base + n * (hw + 3.0) - tip * 1.8,
				base - n * (hw + 3.0) - tip * 1.8])
		draw_polyline(pts, outline, body + 4.0, true)
		draw_circle(pts[0], (body + 4.0) * 0.5, outline, true, -1.0, true)
		draw_colored_polygon(head_o, outline)
		draw_polyline(pts, Color.WHITE, body, true)
		draw_circle(pts[0], body * 0.5, Color.WHITE, true, -1.0, true)
		draw_colored_polygon(head, Color.WHITE)


func _draw_stops() -> void:
	for f in stop_points:
		var p := to_screen(route_point(f)[0])
		draw_circle(p, 13.0, Color.WHITE)
		draw_circle(p, 13.0, Color(0, 0, 0, 0.08), false, 2.0)
		draw_circle(p, 7.0, PleosTheme.DANGER)


func _draw_destination() -> void:
	var p := to_screen(route[route.size() - 1])
	draw_circle(p + Vector2(0, 3), 20.0, Color(0, 0, 0, 0.12))
	draw_circle(p, 18.0, PleosTheme.DANGER)
	draw_circle(p, 7.0, Color.WHITE)
	if dest_name == "":
		return
	# 목적지 이름 말풍선
	var f := PleosTheme.font(true)
	var fs := 18
	var tw := f.get_string_size(dest_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rect := Rect2(p + Vector2(26.0, -17.0), Vector2(tw + 24.0, 34.0))
	if rect.end.x > size.x - _insets.z - 8.0:
		rect.position.x = p.x - 26.0 - rect.size.x      # 오른쪽 카드에 가리면 왼쪽에
	draw_style_box(_dest_box(), rect)
	draw_string(f, rect.position + Vector2(12.0, 24.0), dest_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			PleosTheme.DANGER.darkened(0.15))


func _dest_box() -> StyleBoxFlat:
	if _dest_style == null:
		_dest_style = PleosTheme.box(Color.WHITE, 17, 0, true)
		_dest_style.shadow_size = 8
		_dest_style.shadow_offset = Vector2(0, 2)
	return _dest_style


func _draw_car() -> void:
	var rp := route_point(progress)
	var p := to_screen(rp[0])
	var dir: Vector2 = rp[1]
	var d := (to_screen(rp[0] + dir * 10.0) - p).normalized()
	var n := Vector2(-d.y, d.x)
	var pulse := 0.5 + 0.5 * sin(_time * 2.5)
	draw_circle(p, 34.0 + 6.0 * pulse, Color(PleosTheme.MAP_ROUTE, 0.12))
	draw_circle(p, 26.0, Color.WHITE)
	var tri := PackedVector2Array([p + d * 18.0, p - d * 12.0 + n * 13.0, p - d * 5.0, p - d * 12.0 - n * 13.0])
	draw_colored_polygon(tri, PleosTheme.MAP_ROUTE)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var sp: Vector2 = (e as InputEventMouseButton).position
		var w: Vector2 = _xf.affine_inverse() * sp
		tapped.emit(Vector2(w.x, -w.y), sp)
