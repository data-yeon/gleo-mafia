## 자율주행 패널의 3D 도시. 퍼즐 팩의 가상 도시 중 경로 둘레(약 300m)만 3D로 만든다.
## - 도로: 등급별 폭과 차선(간선·다리 편도 3차로, 이면도로 편도 1차로), 교차로 바닥, 중앙선·차선·가장자리선
## - 보도, 다리 난간, 강·공원 바닥, 가로수·가로등(MultiMesh), 버스 정류장
## - 경로가 지나는 신호 교차로: 차량 신호등, 보행 신호등, 횡단보도, 정지선
## - 지하차도 벽
## 보이는 거리 밖은 그리지 않도록 250m 덩어리로 나눈다(visibility range).
## 좌표: 팩은 (x=동, y=북) m, 3D는 (x, 높이, -y). 경로 위 위치는 누적 거리 s와 옆 거리(진행 방향 오른쪽 +)로 쓴다.
class_name AdasWorld
extends Node3D

const LANE_W := 3.5
const SIDEWALK_W := 4.5
const CORRIDOR_M := 300.0          # 경로에서 이 거리 안의 도로만 만든다
const CELL := 100.0                # 경로 둘레 판정 격자
const CHUNK := 250.0               # 그리기 덩어리
const VIEW_M := 330.0              # 덩어리를 그리는 거리
const PIECE := 50.0                # 긴 도로를 덩어리에 나눠 담는 조각 길이
const TREE_GAP := 13.0
const LIGHT_GAP := 34.0
const CROSSWALK_D := 3.0           # 횡단보도 폭(진행 방향)
# 바닥 색은 조명을 받으면 약 7% 밝아지므로 화면에서 원하는 색보다 조금 어둡게 둔다
const COL_ROAD := Color("c0c6ce")          # 화면에서 PleosTheme.ADAS_ROAD 정도
const COL_SIDEWALK := Color("d9dce1")
const COL_LINE := Color("ffffff")
const COL_CENTER := Color("eccb7e")
const COL_WATER := Color("cfe1f1")
const COL_PARK := Color("d8e9d1")
const COL_RAIL := Color("c3cad3")
const COL_WALL := Color("8b95a2")

var plan: RoutePlan
var nodes := PackedVector2Array()
## 경로가 지나는 신호 교차로. {node, s_node, p, fin, fout, half_in, half_out, jr, stop(인덱스 또는 -1),
##  line_s(우리 정지선), far_line_s(맞은편 정지선), near, far(횡단보도 {c, f, half}), cross({dir, half} 또는 {}),
##  light, ped_lights, green}
var signals: Array[Dictionary] = []
var props: Array[Node3D] = []      # 가로수·가로등·정류장 (터널 안에서 숨긴다)

var _roads: Array[Dictionary] = []
var _edge_of := {}                 # 간선 key → 도로 인덱스
var _adj := {}                     # 노드 → [도로 인덱스]
var _corr := {}                    # 경로 둘레 격자 칸
var _jr := {}                      # 노드 → 교차로 여유(m): 차선·보도가 끊기는 거리
var _route_nodes: Array[int] = []
var _route_s: Array[float] = []
var _route_edge := {}              # 간선 key → 경로상 순번 k (route_nodes[k] → [k+1])
var _chunks := {}                  # Vector2i → {flat_v, flat_c, solid_v, solid_n, solid_c, props}
var _reserved: Array[Vector3] = [] # 가로수를 비울 자리 (x, y, 반지름): 정류장, 랜드마크 앞
## 길가 사건 장소의 3D 자리: id → {pos, yaw}. 실제 위치(도로에서 40~55m)는 카메라 시야 밖이라
## 3D에서는 보도 바로 뒤로 당겨 세운다(지도 위치는 그대로).
var landmark_spots := {}
var _mat: StandardMaterial3D


static func v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, -p.y)


static func lanes_of(cls: String) -> int:
	return 1 if cls == "local" else 3


static func half_of(cls: String) -> float:
	return LANE_W + 0.2 if cls == "local" else 3.0 * LANE_W + 0.4


static func _key(a: int, b: int) -> int:
	return mini(a, b) * 100000 + maxi(a, b)


## 2D 방향 v를 정면(-Z)이 보게 하는 y 회전.
static func yaw_facing(v: Vector2) -> float:
	return atan2(-v.x, v.y)


## 2D 방향 u로 모델의 +X(가로등·신호등 팔)가 향하게 하는 y 회전.
static func yaw_x_to(u: Vector2) -> float:
	return atan2(u.y, u.x)


# ---------------------------------------------------------------- 경로 조회

## [위치, 진행 방향] (2D 월드)
func route_pose(s: float) -> Array:
	var pts := plan.points
	var cum := plan.cum
	var x := clampf(s, 0.0, plan.length)
	var lo := 1
	var hi := pts.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if cum[mid] < x:
			lo = mid + 1
		else:
			hi = mid
	var seg := cum[lo] - cum[lo - 1]
	var t := 0.0 if seg <= 0.0 else (x - cum[lo - 1]) / seg
	return [pts[lo - 1].lerp(pts[lo], t), (pts[lo] - pts[lo - 1]).normalized()]


## 부드러운 진행 방향(앞뒤 span m를 이은 방향). 폴리라인 꼭짓점에서 튀지 않는다.
func heading(s: float, span := 4.0) -> Vector2:
	var a: Vector2 = route_pose(s - span)[0]
	var b: Vector2 = route_pose(s + span)[0]
	if a.distance_to(b) < 0.5:
		return route_pose(s)[1]
	return (b - a).normalized()


func cls_at(s: float) -> String:
	if plan.segments.is_empty():
		return "arterial"
	var c := String(plan.segment_at(clampf(s, 0.0, plan.length)).get("cls", ""))
	return c if c != "" else "arterial"


func lanes_at(s: float) -> int:
	return lanes_of(cls_at(s))


func half_at(s: float) -> float:
	return half_of(cls_at(s))


## 경로 s에서 진행 방향 오른쪽으로 lat m 떨어진 점(2D).
func place(s: float, lat: float) -> Vector2:
	var d := heading(s)
	return (route_pose(s)[0] as Vector2) + Vector2(d.y, -d.x) * lat


## 경로 s, 옆 거리 lat의 3D 변환. backward면 거꾸로(마주 오는 차) 본다.
func xform(s: float, lat: float, backward := false, y := 0.0) -> Transform3D:
	var d := heading(s)
	var p := (route_pose(s)[0] as Vector2) + Vector2(d.y, -d.x) * lat
	var f := -d if backward else d
	return Transform3D(Basis(Vector3.UP, yaw_facing(f)), v3(p, y))


## 점 p를 경로에 투영한 누적 거리. hint 근처(±150m)에서 찾는다.
func s_of(p: Vector2, hint: float) -> float:
	var pts := plan.points
	var cum := plan.cum
	var best := INF
	var out := hint
	for i in range(1, pts.size()):
		if cum[i] < hint - 150.0 or cum[i - 1] > hint + 150.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
		var d := q.distance_to(p)
		if d < best:
			best = d
			out = cum[i - 1] + q.distance_to(pts[i - 1])
	return out


func in_tunnel(s: float, margin := 0.0) -> bool:
	for t in plan.tunnels:
		if s >= float(t["from"]) - margin and s <= float(t["to"]) + margin:
			return true
	return false


# ---------------------------------------------------------------- 만들기

func build(data: Dictionary, p: RoutePlan) -> void:
	plan = p
	for c in get_children():
		c.queue_free()
	signals.clear()
	props.clear()
	_roads.clear()
	_edge_of.clear()
	_adj.clear()
	_corr.clear()
	_jr.clear()
	_route_nodes.clear()
	_route_s.clear()
	_route_edge.clear()
	_chunks.clear()
	_reserved.clear()
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 1.0
	_mat.metallic_specular = 0.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var city: Dictionary = data.get("city", {})
	var rp: Dictionary = data.get("routePlan", {})
	if city.has("roads") and rp.has("nodes"):
		_load_city(city, rp)
	else:
		_load_route_only()
	_mark_corridor()
	_measure_junctions()
	_find_signals()
	_reserve_bus_stops()
	_place_landmark_spots(data.get("places", []))
	for i in range(_roads.size()):
		if _edge_in_corridor(i):
			_build_edge(i)
	for n in _adj:
		_build_pad(int(n))
	_build_signal_marks()
	_build_tunnels()
	_finish_chunks()
	_build_ground_polys(city)
	_place_signal_props()
	_place_destination()


func _load_city(city: Dictionary, rp: Dictionary) -> void:
	for n in city["nodes"]:
		nodes.append(Vector2(float(n[0]), float(n[1])))
	for r in city["roads"]:
		_add_road(int(r["a"]), int(r["b"]), String(r["cls"]))
	# 경유지 재탐색 뒤에는 계획의 노드(새 경로)를 쓴다
	if not plan.nodes.is_empty() and plan.nodes.size() == plan.node_s.size():
		_route_nodes.assign(plan.nodes)
		_route_s.assign(plan.node_s)
		return
	for v in rp["nodes"]:
		_route_nodes.append(int(v))
	for v2 in rp["nodeS"]:
		_route_s.append(float(v2))


## 도시 데이터가 없는 예전 팩: 경로 폴리라인을 간선도로 하나로 본다.
func _load_route_only() -> void:
	nodes = plan.points.duplicate()
	for i in range(nodes.size()):
		_route_nodes.append(i)
		_route_s.append(plan.cum[i])
		if i > 0:
			_add_road(i - 1, i, "arterial")


func _add_road(a: int, b: int, cls: String) -> void:
	var i := _roads.size()
	_roads.append({"a": a, "b": b, "cls": cls})
	_edge_of[_key(a, b)] = i
	_adj.get_or_add(a, []).append(i)
	_adj.get_or_add(b, []).append(i)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _near_route(p: Vector2) -> bool:
	return _corr.has(_cell(p))


func _mark_corridor() -> void:
	for k in range(_route_nodes.size() - 1):
		_route_edge[_key(_route_nodes[k], _route_nodes[k + 1])] = k
	var r := int(ceil(CORRIDOR_M / CELL))
	var s := 0.0
	while s <= plan.length + 25.0:
		var c := _cell(route_pose(s)[0])
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r:
					_corr[c + Vector2i(dx, dy)] = true
		s += 25.0


func _edge_in_corridor(i: int) -> bool:
	var a := nodes[int(_roads[i]["a"])]
	var b := nodes[int(_roads[i]["b"])]
	var n := maxi(1, int(a.distance_to(b) / 50.0))
	for k in range(n + 1):
		if _near_route(a.lerp(b, float(k) / n)):
			return true
	return false


## 교차로 여유: 셋 이상 만나거나 꺾이는 노드는 만나는 길 중 가장 넓은 반폭. 곧게 이어지는 노드는 0.
func _measure_junctions() -> void:
	for n in _adj:
		var inc: Array = _adj[n]
		var hmax := 0.0
		for i in inc:
			hmax = maxf(hmax, half_of(String(_roads[i]["cls"])))
		var junction := inc.size() >= 3
		if inc.size() == 2:
			var d0 := _out_dir(int(n), int(inc[0]))
			var d1 := _out_dir(int(n), int(inc[1]))
			junction = d0.dot(d1) > -0.87          # 30° 넘게 꺾이면 교차로처럼 다룬다
		_jr[n] = hmax if junction else 0.0


func _out_dir(n: int, road: int) -> Vector2:
	var r := _roads[road]
	var other := int(r["b"]) if int(r["a"]) == n else int(r["a"])
	return (nodes[other] - nodes[n]).normalized()


func _jr_of(n: int) -> float:
	return float(_jr.get(n, 0.0))


## 경로가 지나는 신호 교차로: 신호 대기 지점이거나, 셋 이상 만나고 간선도로가 낀 교차로.
func _find_signals() -> void:
	for k in range(1, _route_nodes.size() - 1):
		var nd := _route_nodes[k]
		var inc: Array = _adj.get(nd, [])
		var arterial := false
		for i in inc:
			if String(_roads[i]["cls"]) != "local":
				arterial = true
		var stop_i := -1
		for j in range(plan.stops.size()):
			if int(plan.stops[j].get("node", -1)) == nd:
				stop_i = j
		if stop_i == -1 and (inc.size() < 3 or not arterial):
			continue
		var p := nodes[nd]
		var prev := _route_nodes[k - 1]
		var nxt := _route_nodes[k + 1]
		var fin := (p - nodes[prev]).normalized()
		var fout := (nodes[nxt] - p).normalized()
		var half_in := half_of(String(_roads[_edge_of[_key(prev, nd)]]["cls"]))
		var half_out := half_of(String(_roads[_edge_of[_key(nd, nxt)]]["cls"]))
		var jr := maxf(_jr_of(nd), maxf(half_in, half_out))
		var sn := _route_s[k]
		var sig := {"node": nd, "k": k, "s_node": sn, "p": p, "fin": fin, "fout": fout,
				"half_in": half_in, "half_out": half_out, "jr": jr, "stop": stop_i, "green": null,
				"light": null, "ped_lights": []}
		sig["line_s"] = s_of(p - fin * (jr + 3.9), sn - jr)
		sig["far_line_s"] = s_of(p + fout * (jr + 3.9), sn + jr)
		sig["near"] = {"c": p - fin * (jr + 0.4 + CROSSWALK_D / 2.0), "f": fin, "half": half_in}
		sig["far"] = {"c": p + fout * (jr + 0.4 + CROSSWALK_D / 2.0), "f": fout, "half": half_out}
		# 곧게 지나는 교차로면 가로지르는 길(좌우가 이어진 길)로 교차 차량을 보낸다
		sig["cross"] = {}
		if fin.dot(fout) > 0.9:
			var dirs: Array[Vector2] = []
			var halves: Array[float] = []
			for i2 in inc:
				var r := _roads[i2]
				var other := int(r["b"]) if int(r["a"]) == nd else int(r["a"])
				if other == prev or other == nxt:
					continue
				dirs.append((nodes[other] - p).normalized())
				halves.append(half_of(String(r["cls"])))
			for a in range(dirs.size()):
				for b in range(a + 1, dirs.size()):
					if dirs[a].dot(dirs[b]) < -0.8:
						sig["cross"] = {"dir": dirs[a], "half": maxf(halves[a], halves[b]),
								"lanes": 1 if maxf(halves[a], halves[b]) < 5.0 else 3}
		signals.append(sig)


## 버스 정류장: 경로의 긴 간선도로 구간 몇 곳의 오른쪽 보도.
func _reserve_bus_stops() -> void:
	for k in range(_route_nodes.size() - 1):
		if k % 3 != 1:
			continue
		var i: int = _edge_of.get(_key(_route_nodes[k], _route_nodes[k + 1]), -1)
		if i < 0 or String(_roads[i]["cls"]) != "arterial":
			continue
		var a := nodes[_route_nodes[k]]
		var b := nodes[_route_nodes[k + 1]]
		if a.distance_to(b) < 300.0:
			continue
		var d := (b - a).normalized()
		var right := Vector2(d.y, -d.x)
		var pos := a.lerp(b, 0.55) + right * (half_of("arterial") + 2.6)
		if in_tunnel(_route_s[k] + a.distance_to(b) * 0.55, 40.0):
			continue
		_reserved.append(Vector3(pos.x, pos.y, 0.0))
		_prop("bus_stop", pos, yaw_facing(-right), 1.0)


# ---------------------------------------------------------------- 도로 하나

func _build_edge(i: int) -> void:
	var r := _roads[i]
	var na := int(r["a"])
	var nb := int(r["b"])
	var a := nodes[na]
	var b := nodes[nb]
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var d := (b - a) / length
	var n := Vector2(-d.y, d.x)
	var cls := String(r["cls"])
	var half := half_of(cls)
	var lanes := lanes_of(cls)
	var t0 := _jr_of(na)
	var t1 := length - _jr_of(nb)
	var road_col := COL_ROAD
	_band(a, d, n, 0.0, length, -half, half, road_col, 0.0)
	# 차선 (교차로 안은 비운다)
	var m0 := t0 + 1.0
	var m1 := t1 - 1.0
	if m1 > m0:
		if lanes == 1:
			_band(a, d, n, m0, m1, -0.08, 0.08, COL_CENTER, 0.02)
		else:
			for side: float in [-1.0, 1.0]:
				_band(a, d, n, m0, m1, side * 0.13, side * 0.27, COL_CENTER, 0.02)
				for k in range(1, lanes):
					_dashes(a, d, n, m0, m1, side * k * LANE_W, 0.15, 3.0, 6.0)
		for side2: float in [-1.0, 1.0]:
			var ex: float = side2 * lanes * LANE_W
			_band(a, d, n, m0, m1, ex - 0.08, ex + 0.08, COL_LINE, 0.02)
	if cls == "bridge":
		for side3: float in [-1.0, 1.0]:
			_rail(a + n * side3 * (half + 0.25), b + n * side3 * (half + 0.25), 0.9, COL_RAIL)
		return
	# 보도 (지하차도 구간은 비운다)
	var ts := t0
	while ts < t1 - 0.5:
		var te := minf(ts + PIECE, t1)
		if not _in_tunnel_at(i, (ts + te) / 2.0):
			for side4: float in [-1.0, 1.0]:
				var l0: float = half if side4 > 0.0 else -half - SIDEWALK_W
				var l1: float = half + SIDEWALK_W if side4 > 0.0 else -half
				_band(a, d, n, ts, te, l0, l1, COL_SIDEWALK, 0.05)
		ts = te
	# 가로수 (경로 둘레만)
	var t := t0 + 7.0
	var k2 := 0
	while t < t1 - 7.0:
		for side5: float in [-1.0, 1.0]:
			var jt := t + (fposmod(float(i * 31 + k2 * 17) * 0.37, 1.0) - 0.5) * 3.0
			var pos := a + d * jt + n * side5 * (half + 3.3)
			if not _near_route(pos) or _in_tunnel_at(i, jt) or _reserved_near(pos, 8.0):
				continue
			var tid := "tree_cone" if (k2 + int(side5 > 0.0) + i) % 4 == 0 else "tree_round"
			var sc := 0.82 + 0.22 * fposmod(float(i * 13 + k2 * 7) * 0.61, 1.0)
			_prop(tid, pos, float(k2 * 47 + i * 13) * 0.11, sc)
		t += TREE_GAP
		k2 += 1
	# 가로등: 양쪽 엇갈려, 팔은 도로 쪽
	var t2 := t0 + 10.0
	var k3 := 0
	while t2 < t1 - 6.0:
		var side6 := 1.0 if k3 % 2 == 0 else -1.0
		var pos2 := a + d * t2 + n * side6 * (half + 0.7)
		if _near_route(pos2) and not _in_tunnel_at(i, t2) and not _reserved_near(pos2, 6.0):
			_prop("street_light", pos2, yaw_x_to(-n * side6), 1.0)
		t2 += LIGHT_GAP / 2.0
		k3 += 1


## 경로 위 도로라면 그 지점의 누적 거리로 지하차도 안인지 본다.
func _in_tunnel_at(road: int, t: float) -> bool:
	var r := _roads[road]
	var k: int = _route_edge.get(_key(int(r["a"]), int(r["b"])), -1)
	if k < 0:
		return false
	var length := nodes[int(r["a"])].distance_to(nodes[int(r["b"])])
	var forward := int(r["a"]) == _route_nodes[k]
	var s := _route_s[k] + (t if forward else length - t)
	return in_tunnel(s, 25.0)


func _reserved_near(p: Vector2, dist: float) -> bool:
	for q in _reserved:
		if Vector2(q.x, q.y).distance_to(p) < maxf(dist, q.z):
			return true
	return false


## 길가 사건 장소를 보도 바로 뒤로 당겨 세울 자리를 정하고, 그 앞 보도의 가로수를 비운다.
## 교차로에 걸리면 실제 위치를 그대로 쓴다.
func _place_landmark_spots(places: Array) -> void:
	landmark_spots.clear()
	for p in places:
		if not bool(p.get("roadside", false)):
			continue
		var lid := String(p.get("landmark", ""))
		if lid == "":
			lid = Landmarks.id_for(String(p["name"]), String(p.get("kind", "")))
		if lid == "":
			continue
		var size := Landmarks.size_of(lid)
		var real := Vector2(float(p["x"]), float(p["y"]))
		var s := s_of(real, float(p.get("routePos", 0.0)) * plan.length)
		var near_junction := false
		for k in range(_route_nodes.size()):
			var jr := _jr_of(_route_nodes[k])
			if jr > 0.0 and absf(s - _route_s[k]) < jr + size.x / 2.0 + SIDEWALK_W + 4.0:
				near_junction = true
		if near_junction or in_tunnel(s, 30.0) or cls_at(s) == "bridge":
			continue
		var d := heading(s)
		var right := Vector2(d.y, -d.x)
		var side := 1.0 if (real - (route_pose(s)[0] as Vector2)).dot(right) >= 0.0 else -1.0
		var lat := half_at(s) + SIDEWALK_W + 2.0 + size.z / 2.0
		var pos := place(s, side * lat)
		landmark_spots[int(p["id"])] = {"pos": pos, "yaw": yaw_facing(-right * side)}
		var front := place(s, side * (half_at(s) + 3.3))
		_reserved.append(Vector3(front.x, front.y, size.x / 2.0 + 3.0))
	# 경유지 잠복 장소: 차가 서는 지점 바로 앞 오른쪽 보도 뒤에 세운다(차는 바깥 차로로 붙어 그 앞에 선다)
	if plan.waypoint_place > 0:
		for p2 in places:
			if int(p2["id"]) != plan.waypoint_place:
				continue
			var lid2 := String(p2.get("landmark", ""))
			if lid2 == "":
				lid2 = Landmarks.id_for(String(p2["name"]), String(p2.get("kind", "")))
			if lid2 == "":
				break
			var size2 := Landmarks.size_of(lid2)
			var s2 := plan.waypoint_s + size2.x / 2.0 + 24.0    # 서 있는 차에서 보이게 조금 앞
			var d2 := heading(s2)
			var right2 := Vector2(d2.y, -d2.x)
			var pos2 := place(s2, half_at(s2) + SIDEWALK_W + 2.0 + size2.z / 2.0)
			landmark_spots[plan.waypoint_place] = {"pos": pos2, "yaw": yaw_facing(-right2)}
			var front2 := place(s2, half_at(s2) + 3.3)
			_reserved.append(Vector3(front2.x, front2.y, size2.x / 2.0 + 3.0))


## 교차로 바닥: 만나는 길들의 폭을 덮는 볼록 다각형(모서리 빈틈을 메운다).
func _build_pad(n: int) -> void:
	var jr := _jr_of(n)
	if jr <= 0.0:
		return
	var p := nodes[n]
	if not _near_route(p):
		return
	var pts := PackedVector2Array()
	for i in _adj[n]:
		var d := _out_dir(n, int(i))
		var nn := Vector2(-d.y, d.x)
		var h := half_of(String(_roads[i]["cls"]))
		for sx in [-1.0, 1.0]:
			pts.append(p + d * jr * sx + nn * h)
			pts.append(p + d * jr * sx - nn * h)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() < 4:
		return
	for k in range(1, hull.size() - 2):
		_tri(hull[0], hull[k], hull[k + 1], COL_ROAD, 0.003)


func _build_signal_marks() -> void:
	for sig in signals:
		for key in ["near", "far"]:
			var cw: Dictionary = sig[key]
			_crosswalk(cw["c"], cw["f"], float(cw["half"]))
		# 정지선: 우리 쪽 차로(오른쪽 절반)만
		var fin: Vector2 = sig["fin"]
		var right := Vector2(fin.y, -fin.x)
		var c: Vector2 = (sig["p"] as Vector2) - fin * (float(sig["jr"]) + 3.9)
		var h := float(sig["half_in"])
		_quad(c + right * 0.2 - fin * 0.22, c + right * 0.2 + fin * 0.22, c + right * (h - 0.4) + fin * 0.22,
				c + right * (h - 0.4) - fin * 0.22, COL_LINE, 0.022)


func _crosswalk(c: Vector2, f: Vector2, half: float) -> void:
	var right := Vector2(f.y, -f.x)
	var x := -half + 0.7
	while x < half - 0.5:
		var p0 := c + right * x
		_quad(p0 - f * CROSSWALK_D / 2.0, p0 + f * CROSSWALK_D / 2.0, p0 + right * 0.5 + f * CROSSWALK_D / 2.0,
				p0 + right * 0.5 - f * CROSSWALK_D / 2.0, COL_LINE, 0.022)
		x += 1.0


## 신호등은 램프를 켜고 끄므로 MultiMesh가 아니라 하나씩 둔다.
func _place_signal_props() -> void:
	for sig in signals:
		var p: Vector2 = sig["p"]
		var fin: Vector2 = sig["fin"]
		var right := Vector2(fin.y, -fin.x)
		var jr := float(sig["jr"])
		var h := float(sig["half_in"])
		var tl: Node3D = AdasAssets.instance("traffic_light_car")
		if tl != null:
			# 건너편 오른쪽 모퉁이에서 팔을 도로 위로, 램프는 다가오는 차를 본다
			tl.position = v3(p + fin * (jr + 1.2) + right * (h + 1.0))
			tl.rotation.y = yaw_facing(-fin)
			add_child(tl)
			sig["light"] = tl
		var cw: Dictionary = sig["near"]
		for side: float in [-1.0, 1.0]:
			var pl: Node3D = AdasAssets.instance("traffic_light_ped")
			if pl == null:
				continue
			pl.position = v3((cw["c"] as Vector2) + right * side * (h + 0.8) - fin * 1.0, 0.05)
			pl.rotation.y = yaw_facing(-right * side)
			add_child(pl)
			sig["ped_lights"].append(pl)
		set_signal_green(sig, int(sig["stop"]) < 0)


## 도착 지점 표시: 경로 끝 오른쪽 보도에 내비 목적지 핀 모양(빨간 기둥 + 흰 점이 있는 빨간 원판).
func _place_destination() -> void:
	# 차가 서는 경로 끝에서 14m 앞, 오른쪽 길가(카메라 시야 안)
	var s := plan.length
	var d := heading(s - 4.0)
	var pos := (route_pose(s)[0] as Vector2) + d * 14.0 + Vector2(d.y, -d.x) * (half_at(s) - 0.6)
	var root := Node3D.new()
	root.position = v3(pos)
	var red := StandardMaterial3D.new()
	red.albedo_color = PleosTheme.DANGER
	red.roughness = 0.8
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 4.2
	pole.mesh = cyl
	pole.material_override = red
	pole.position.y = 2.1
	root.add_child(pole)
	var head := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.3
	disc.bottom_radius = 1.3
	disc.height = 0.3
	head.mesh = disc
	head.material_override = red
	head.position.y = 5.3
	head.rotation.x = PI / 2.0
	root.add_child(head)
	var dot := MeshInstance3D.new()
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.5
	dot_mesh.bottom_radius = 0.5
	dot_mesh.height = 0.34
	dot.mesh = dot_mesh
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material_override = white
	dot.position.y = 5.3
	dot.rotation.x = PI / 2.0
	root.add_child(dot)
	# 원판이 다가오는 차를 보게
	root.rotation.y = yaw_facing(-d)
	add_child(root)


## 우리 방향 신호. green이면 차량 초록·보행 빨강, 아니면 차량 빨강·보행 초록.
func set_signal_green(sig: Dictionary, green: bool) -> void:
	if sig["green"] is bool and bool(sig["green"]) == green:
		return
	sig["green"] = green
	var tl = sig["light"]
	if tl != null:
		AdasAssets.set_lamp(tl, "LampGreen", green)
		AdasAssets.set_lamp(tl, "LampRed", not green)
		AdasAssets.set_lamp(tl, "LampYellow", false)
	for pl in sig["ped_lights"]:
		AdasAssets.set_lamp(pl, "LampGreen", not green)
		AdasAssets.set_lamp(pl, "LampRed", green)


## 지하차도: 경로를 따라 양쪽 벽과 입구·출구 보.
func _build_tunnels() -> void:
	for t in plan.tunnels:
		var s0 := float(t["from"])
		var s1 := float(t["to"])
		var s := s0
		var prev_l := Vector2.ZERO
		var prev_r := Vector2.ZERO
		var first := true
		while true:
			var h := half_at(s) + 0.6
			var l := place(s, -h)
			var r := place(s, h)
			if not first:
				_rail(prev_l, l, 5.2, COL_WALL)
				_rail(prev_r, r, 5.2, COL_WALL)
			prev_l = l
			prev_r = r
			first = false
			if s >= s1:
				break
			s = minf(s + 8.0, s1)
		for se in [s0, s1]:
			var h2 := half_at(se) + 0.6
			_lintel(place(se, -h2), place(se, h2), 4.6, 5.6)


# ---------------------------------------------------------------- 바닥 (강, 공원)

func _build_ground_polys(city: Dictionary) -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for layer in [["water", COL_WATER, -0.03], ["parks", COL_PARK, -0.025]]:
		for poly_data in city.get(layer[0], []):
			var poly := PackedVector2Array()
			for q in poly_data:
				poly.append(Vector2(float(q[0]), float(q[1])))
			var tri := Geometry2D.triangulate_polygon(poly)
			for k in range(0, tri.size() - 2, 3):
				var a := poly[tri[k]]
				var b := poly[tri[k + 1]]
				var c := poly[tri[k + 2]]
				# 위에서 볼 때 앞면이 되게 (_tri와 같은 규칙)
				for p in ([a, b, c] if (b - a).cross(c - a) < 0.0 else [a, c, b]):
					verts.append(v3(p, layer[2]))
					cols.append(layer[1])
					norms.append(Vector3.UP)
	if verts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(verts, norms, cols)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- 덩어리에 담기

func _chunk(p: Vector2) -> Dictionary:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	if not _chunks.has(key):
		_chunks[key] = {"o": (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK, "flat_v": [], "flat_c": [],
				"solid_v": [], "solid_n": [], "solid_c": [], "props": {}}
	return _chunks[key]


## 도로 a에서 방향 d, 옆 방향 n(왼쪽)으로 [t0,t1] × [l0,l1] 띠. 덩어리 경계에 맞게 조각낸다.
func _band(a: Vector2, d: Vector2, n: Vector2, t0: float, t1: float, l0: float, l1: float, col: Color,
		y: float) -> void:
	var t := t0
	while t < t1 - 0.01:
		var te := minf(t + PIECE, t1)
		_quad(a + d * t + n * l0, a + d * te + n * l0, a + d * te + n * l1, a + d * t + n * l1, col, y)
		t = te


func _dashes(a: Vector2, d: Vector2, n: Vector2, t0: float, t1: float, lat: float, w: float, dash: float,
		gap: float) -> void:
	var t := t0 + gap * 0.5
	while t + dash < t1:
		_quad(a + d * t + n * (lat - w / 2.0), a + d * (t + dash) + n * (lat - w / 2.0),
				a + d * (t + dash) + n * (lat + w / 2.0), a + d * t + n * (lat + w / 2.0), COL_LINE, 0.02)
		t += dash + gap


func _quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color, y: float) -> void:
	_tri(p0, p1, p2, col, y)
	_tri(p0, p2, p3, col, y)


## 바닥 삼각형. 위에서 볼 때 앞면이 되도록 감는 방향을 맞춘다
## (뒷면이면 법선이 아래로 뒤집혀 해를 못 받고 어둡게 보인다).
func _tri(p0: Vector2, p1: Vector2, p2: Vector2, col: Color, y: float) -> void:
	var ch := _chunk((p0 + p1 + p2) / 3.0)
	var o: Vector2 = ch["o"]
	var vs: Array = ch["flat_v"]
	var cs: Array = ch["flat_c"]
	var tri := [p0, p1, p2] if (p1 - p0).cross(p2 - p0) < 0.0 else [p0, p2, p1]
	for p in tri:
		vs.append(v3(p - o, y))
		cs.append(col)


## 바닥에서 높이 h까지 서 있는 얇은 벽(난간, 지하차도 벽). 조각 길이에 맞게 나눈다.
func _rail(p0: Vector2, p1: Vector2, h: float, col: Color) -> void:
	var length := p0.distance_to(p1)
	var steps := maxi(1, int(ceil(length / PIECE)))
	for k in range(steps):
		var a := p0.lerp(p1, float(k) / steps)
		var b := p0.lerp(p1, float(k + 1) / steps)
		_wall_quad(a, b, 0.0, h, col)


## 입구 보: 두 점 사이를 가로지르는 띠(높이 y0~y1).
func _lintel(p0: Vector2, p1: Vector2, y0: float, y1: float) -> void:
	_wall_quad(p0, p1, y0, y1, COL_WALL)


func _wall_quad(a: Vector2, b: Vector2, y0: float, y1: float, col: Color) -> void:
	var ch := _chunk((a + b) / 2.0)
	var o: Vector2 = ch["o"]
	var d := (b - a).normalized()
	var nrm := Vector3(-d.y, 0.0, -d.x)
	var vs: Array = ch["solid_v"]
	var ns: Array = ch["solid_n"]
	var cs: Array = ch["solid_c"]
	for v in [v3(a - o, y0), v3(b - o, y0), v3(b - o, y1), v3(a - o, y0), v3(b - o, y1), v3(a - o, y1)]:
		vs.append(v)
		ns.append(nrm)
		cs.append(col)


func _prop(id: String, p: Vector2, yaw: float, sc: float) -> void:
	var ch := _chunk(p)
	var o: Vector2 = ch["o"]
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), v3(p - o))
	(ch["props"] as Dictionary).get_or_add(id, []).append(xf)


func _mesh(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, _mat)
	return m


func _finish_chunks() -> void:
	for key in _chunks:
		var ch: Dictionary = _chunks[key]
		var origin := v3(ch["o"])
		var fv := PackedVector3Array(ch["flat_v"])
		if not fv.is_empty():
			var fn := PackedVector3Array()
			fn.resize(fv.size())
			fn.fill(Vector3.UP)
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh(fv, fn, PackedColorArray(ch["flat_c"]))
			mi.position = origin
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = VIEW_M
			add_child(mi)
		var sv := PackedVector3Array(ch["solid_v"])
		if not sv.is_empty():
			var mi2 := MeshInstance3D.new()
			mi2.mesh = _mesh(sv, PackedVector3Array(ch["solid_n"]), PackedColorArray(ch["solid_c"]))
			mi2.position = origin
			mi2.visibility_range_end = VIEW_M
			add_child(mi2)
		var pr: Dictionary = ch["props"]
		for id in pr:
			var xfs: Array = pr[id]
			for part in AdasAssets.mesh_parts(String(id)):
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = part["mesh"]
				mm.instance_count = xfs.size()
				for k in range(xfs.size()):
					mm.set_instance_transform(k, (xfs[k] as Transform3D) * (part["xform"] as Transform3D))
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.position = origin
				mmi.visibility_range_end = VIEW_M - 50.0
				add_child(mmi)
				props.append(mmi)
	_chunks.clear()
