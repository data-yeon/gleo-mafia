## 가상 도시 길찾기(Godot 쪽): A*와 경로 계획, 그리고 주행 중 경유지 재탐색.
## 비용·회전 규칙·모서리 깎기·회전 안내는 prototype/puzzle/city.py와 같다(같은 경로가 나오는지 테스트로 본다).
## - A*: 상태 = (노드, 직전 노드). 비용 = 이동 시간 + 회전 벌점(좌 15초, 우 5초), 유턴 금지.
## - 재탐색: 내 차 앞 첫 교차로(60m 넘게 앞)에서 갈라져 경유지 도로를 지나 목적지로 간다.
##   이미 지나온 앞부분 폴리라인은 그대로 두어 누적 거리(s)가 이어진다.
class_name CityRouter
extends RefCounted

const SPEED_KMH := {"arterial": 60.0, "local": 40.0, "bridge": 65.0}
const CRUISE_KMH := {"arterial": 62.0, "local": 38.0, "bridge": 68.0}
const TURN_LEFT_S := 15.0
const TURN_RIGHT_S := 5.0
const TURN_DEG := 30.0
const SHARP_DEG := 60.0
const FILLET_M := 18.0
const STOP_BEFORE_NODE := 18.0         # 신호 대기 지점: 교차로 18m 앞 (city.py와 같게)
const BRANCH_MARGIN := 60.0            # 내 차보다 이만큼 넘게 앞인 교차로에서 갈라진다
const CUT_BEFORE := 46.0               # 갈라지는 교차로 46m 앞까지는 옛 폴리라인을 그대로 쓴다
const WAYPOINT_DWELL_S := 45.0         # 경유지에서 서서 잠복하는 게임 시간(초). 경유지의 대가

var nodes := PackedVector2Array()
var edges: Array[Dictionary] = []      # {a, b, cls, name, len}
var adj: Array = []                    # 노드 → [간선 인덱스]
var _edge_of := {}


static func from_city(city: Dictionary) -> CityRouter:
	var r := CityRouter.new()
	for n in city.get("nodes", []):
		r.nodes.append(Vector2(float(n[0]), float(n[1])))
	r.adj.resize(r.nodes.size())
	for i in range(r.nodes.size()):
		r.adj[i] = []
	for e in city.get("roads", []):
		var a := int(e["a"])
		var b := int(e["b"])
		var i2 := r.edges.size()
		r.edges.append({"a": a, "b": b, "cls": String(e["cls"]), "name": String(e["name"]),
				"len": r.nodes[a].distance_to(r.nodes[b])})
		r.adj[a].append(i2)
		r.adj[b].append(i2)
		r._edge_of[_key(a, b)] = i2
	return r


static func _key(a: int, b: int) -> int:
	return mini(a, b) * 100000 + maxi(a, b)


func edge_between(a: int, b: int) -> int:
	return int(_edge_of.get(_key(a, b), -1))


func other(e: int, n: int) -> int:
	return int(edges[e]["b"]) if int(edges[e]["a"]) == n else int(edges[e]["a"])


## p0→p1→p2에서 꺾이는 각도(도). 양수 = 왼쪽.
static func turn_deg(p0: Vector2, p1: Vector2, p2: Vector2) -> float:
	return rad_to_deg((p1 - p0).angle_to(p2 - p1))


static func turn_penalty(deg: float) -> float:
	if deg > TURN_DEG:
		return TURN_LEFT_S
	if deg < -TURN_DEG:
		return TURN_RIGHT_S
	return 0.0


func edge_seconds(e: int) -> float:
	return float(edges[e]["len"]) / (float(SPEED_KMH[edges[e]["cls"]]) / 3.6)


# ---------------------------------------------------------------- A*

## 이동 시간 + 회전 벌점이 최소인 경로. 상태 = (노드, 직전 노드)라 회전을 계산하고 유턴을 막을 수 있다.
## not_from: 목표 노드에 이 노드에서 들어오는 경로는 받지 않는다(경유 도로를 거꾸로 밟지 않게).
## 돌려주는 것: {path: Array[int], cost: 초, expanded: 펼친 상태 수}. 길이 없으면 path가 비어 있다.
func astar(start: int, goal: int, prev_start := -1, not_from := -1) -> Dictionary:
	var vmax: float = float(SPEED_KMH["bridge"]) / 3.6
	var gp := nodes[goal]
	var start_key := _state(start, prev_start)
	var g := {start_key: 0.0}
	var parent := {start_key: -1}
	var closed := {}
	var heap := MinHeap.new()
	heap.push(nodes[start].distance_to(gp) / vmax, start_key)
	while not heap.is_empty():
		var key: int = heap.pop()
		if closed.has(key):
			continue
		closed[key] = true
		var node := key / 100000
		var prev := key % 100000 - 1
		if node == goal and (not_from < 0 or prev != not_from):
			var path: Array[int] = []
			var k = key
			while k != -1:
				path.append(int(k) / 100000)
				k = parent[k]
			path.reverse()
			return {"path": path, "cost": float(g[key]), "expanded": closed.size()}
		for e in adj[node]:
			var nxt := other(int(e), node)
			if nxt == prev:
				continue                                   # 유턴 금지
			var cost: float = float(g[key]) + edge_seconds(int(e))
			if prev >= 0:
				cost += turn_penalty(turn_deg(nodes[prev], nodes[node], nodes[nxt]))
			var nk := _state(nxt, node)
			if cost < float(g.get(nk, INF)):
				g[nk] = cost
				parent[nk] = key
				heap.push(cost + nodes[nxt].distance_to(gp) / vmax, nk)
	var none: Array[int] = []
	return {"path": none, "cost": INF, "expanded": closed.size()}


static func _state(node: int, prev: int) -> int:
	return node * 100000 + prev + 1


## 작은 이진 힙 (우선순위, 값)
class MinHeap:
	var _p: Array[float] = []
	var _v: Array[int] = []

	func is_empty() -> bool:
		return _p.is_empty()

	func push(pri: float, val: int) -> void:
		_p.append(pri)
		_v.append(val)
		var i := _p.size() - 1
		while i > 0:
			var up := (i - 1) / 2
			if _p[up] <= _p[i]:
				break
			_swap(i, up)
			i = up

	func pop() -> int:
		var top := _v[0]
		var last := _p.size() - 1
		_swap(0, last)
		_p.pop_back()
		_v.pop_back()
		var i := 0
		var n := _p.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and _p[l] < _p[m]:
				m = l
			if r < n and _p[r] < _p[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tp := _p[a]
		_p[a] = _p[b]
		_p[b] = tp
		var tv := _v[a]
		_v[a] = _v[b]
		_v[b] = tv


# ---------------------------------------------------------------- 경로 기하

## 노드 경로 → 모서리를 둥글게 깎은 폴리라인과 노드별 누적 거리(city.py plan_route와 같은 방식).
## start_pt를 주면 첫 노드 자리 대신 그 점에서 시작한다(옛 경로 뒤에 이어 붙일 때).
func polyline(path: Array[int], start_pt := Vector2(INF, INF)) -> Dictionary:
	var pts: Array[Vector2] = []
	for n in path:
		pts.append(nodes[n])
	if start_pt.x != INF:
		pts[0] = start_pt
	var poly := PackedVector2Array([pts[0]])
	var ns: Array[float] = [0.0]
	var run := 0.0
	for k in range(1, pts.size() - 1):
		var p0 := pts[k - 1]
		var p1 := pts[k]
		var p2 := pts[k + 1]
		if absf(turn_deg(p0, p1, p2)) < 5.0:
			run += poly[poly.size() - 1].distance_to(p1)
			poly.append(p1)
			ns.append(run)
			continue
		var l0 := p0.distance_to(p1)
		var l1 := p1.distance_to(p2)
		var r := minf(FILLET_M, minf(l0 * 0.4, l1 * 0.4))
		var a := p1 + (p0 - p1) / l0 * r
		var b := p1 + (p2 - p1) / l1 * r
		run += poly[poly.size() - 1].distance_to(a)
		poly.append(a)
		var mid_s := run
		for t in [0.25, 0.5, 0.75]:
			var q: Vector2 = a * (1.0 - t) * (1.0 - t) + p1 * 2.0 * (1.0 - t) * t + b * t * t
			run += poly[poly.size() - 1].distance_to(q)
			poly.append(q)
			if t == 0.5:
				mid_s = run
		run += poly[poly.size() - 1].distance_to(b)
		poly.append(b)
		ns.append(mid_s)
	run += poly[poly.size() - 1].distance_to(pts[pts.size() - 1])
	poly.append(pts[pts.size() - 1])
	ns.append(run)
	return {"points": poly, "node_s": ns, "length": run}


## 도로 구간(이름이 같은 간선 묶음)과 회전 안내. city.py와 같은 규칙.
func segments_and_maneuvers(path: Array[int], ns: Array[float], length: float) -> Dictionary:
	var segs: Array[Dictionary] = []
	var eids: Array[int] = []
	for k in range(path.size() - 1):
		eids.append(edge_between(path[k], path[k + 1]))
	for k2 in range(eids.size()):
		var ed := edges[eids[k2]]
		if not segs.is_empty() and segs[segs.size() - 1]["name"] == ed["name"]:
			segs[segs.size() - 1]["to"] = ns[k2 + 1]
		else:
			segs.append({"name": ed["name"], "cls": ed["cls"], "from": ns[k2], "to": ns[k2 + 1],
					"cruise": float(CRUISE_KMH[ed["cls"]])})
	var mans: Array[Dictionary] = []
	for k3 in range(1, path.size() - 1):
		var deg := turn_deg(nodes[path[k3 - 1]], nodes[path[k3]], nodes[path[k3 + 1]])
		var cur := edges[eids[k3 - 1]]
		var nxt := edges[eids[k3]]
		if absf(deg) >= TURN_DEG:
			var left := deg > 0.0
			var sharp := absf(deg) >= SHARP_DEG
			var verb := ("좌회전" if sharp else "왼쪽 방향") if left else ("우회전" if sharp else "오른쪽 방향")
			mans.append({"s": ns[k3], "icon": "turn_left" if left else "turn_right", "verb": verb,
					"road": nxt["name"], "at": cur["name"], "waypoint": false})
		elif nxt["name"] != cur["name"]:
			mans.append({"s": ns[k3], "icon": "straight", "verb": "직진", "road": nxt["name"], "at": "",
					"waypoint": false})
	mans.append({"s": length, "icon": "flag", "verb": "도착", "road": "목적지", "at": "", "waypoint": false})
	return {"segments": segs, "maneuvers": mans}


# ---------------------------------------------------------------- 경유지 재탐색

## 장소에서 가장 가까운 도로(다리 제외)와 그 위의 정차 지점(도로 20~80% 사이).
func waypoint_edge(place: Vector2) -> Dictionary:
	var best := INF
	var out := {}
	for i in range(edges.size()):
		if String(edges[i]["cls"]) == "bridge":
			continue
		var a := nodes[int(edges[i]["a"])]
		var b := nodes[int(edges[i]["b"])]
		var q := Geometry2D.get_closest_point_to_segment(place, a, b)
		var d := q.distance_to(place)
		if d < best:
			best = d
			var t := clampf((q - a).dot(b - a) / (b - a).length_squared(), 0.2, 0.8)
			out = {"edge": i, "q": a.lerp(b, t), "dist": d}
	return out


## 지금 경로(old)에서 s_car에 있는 차가 place_id 장소를 경유지로 들러 목적지로 가는 새 경로 계획.
## 실패하면 빈 Dictionary. 성공하면 {plan, branch_k, cost_s(새 남은 경로 A* 비용), dist(장소~정차 지점)}.
func reroute(old: RoutePlan, s_car: float, place: Vector2, place_id: int, place_label: String) -> Dictionary:
	if old.nodes.size() < 2 or old.nodes.size() != old.node_s.size():
		return {}
	var kb := -1
	for k in range(1, old.nodes.size()):
		if old.node_s[k] > s_car + BRANCH_MARGIN:
			kb = k
			break
	if kb < 1 or kb >= old.nodes.size() - 1:
		return {}
	var goal := old.nodes[old.nodes.size() - 1]
	var wp := waypoint_edge(place)
	if wp.is_empty():
		return {}
	var e := edges[int(wp["edge"])]
	var best := {}
	# 경유 도로를 어느 쪽으로 지날지: 두 방향 다 해 보고 싼 쪽
	for dir in [[int(e["a"]), int(e["b"])], [int(e["b"]), int(e["a"])]]:
		var u: int = dir[0]
		var v: int = dir[1]
		var p1: Array[int] = [u]
		var first_cost := 0.0
		if old.nodes[kb] != u:
			var first := astar(old.nodes[kb], u, old.nodes[kb - 1], v)
			p1 = first["path"]
			first_cost = float(first["cost"])
		if p1.is_empty():
			continue
		var prev_u := p1[p1.size() - 2] if p1.size() >= 2 else old.nodes[kb - 1]
		if prev_u == v:
			continue
		var turn_in := turn_penalty(turn_deg(nodes[prev_u], nodes[u], nodes[v]))
		var second := astar(v, goal, u)
		if (second["path"] as Array).is_empty():
			continue
		var cost := first_cost + turn_in + edge_seconds(int(wp["edge"])) + float(second["cost"])
		if best.is_empty() or cost < float(best["cost"]):
			var tail: Array[int] = []
			tail.append_array(p1)
			var p2: Array[int] = second["path"]
			tail.append_array(p2)
			best = {"cost": cost, "tail": tail}
	if best.is_empty():
		return {}
	var plan := _splice(old, kb, best["tail"], s_car)
	# 경유지 정차 지점과 안내
	var q: Vector2 = wp["q"]
	var j := -1
	var path := plan.nodes
	for k4 in range(kb, path.size() - 1):
		if edge_between(path[k4], path[k4 + 1]) == int(wp["edge"]):
			j = k4
			break
	if j < 0:
		return {}
	var s_wp := plan_s_of(plan, q, plan.node_s[j], plan.node_s[j + 1])
	plan.waypoint_place = place_id
	plan.waypoint_s = s_wp
	plan.stops.append({"s": s_wp, "dwell": WAYPOINT_DWELL_S, "node": -1, "waypoint": true, "place": place_id})
	plan.stops.sort_custom(func(x, y): return float(x["s"]) < float(y["s"]))
	plan.maneuvers.append({"s": s_wp, "icon": "flag", "verb": "경유지", "road": place_label, "at": "",
			"waypoint": true})
	plan.maneuvers.sort_custom(func(x, y): return float(x["s"]) < float(y["s"]))
	return {"plan": plan, "branch_k": kb, "cost_s": float(best["cost"]), "dist": float(wp["dist"])}


## 옛 경로의 0..kb-1 노드 + 새 꼬리(kb부터)로 새 경로 계획을 만든다.
## 갈라지는 교차로 46m 앞까지는 옛 폴리라인을 그대로 두고, 거기서부터 새로 깎는다.
func _splice(old: RoutePlan, kb: int, tail: Array[int], _s_car: float) -> RoutePlan:
	var cut_s := old.node_s[kb] - CUT_BEFORE
	var pts := PackedVector2Array()
	for i in range(old.points.size()):
		if old.cum[i] < cut_s - 0.01:
			pts.append(old.points[i])
	var cut_pt: Vector2 = old.point_at(cut_s)[0]
	# 새 꼬리 앞에 "자르는 점"을 첫 노드처럼 붙여 깎는다 (첫 노드 자리는 start_pt로 바뀐다)
	var geo_path: Array[int] = [old.nodes[kb - 1]]
	geo_path.append_array(tail)
	var geo := polyline(geo_path, cut_pt)
	var new_pts: PackedVector2Array = geo["points"]
	for i2 in range(new_pts.size()):
		pts.append(new_pts[i2])
	var path: Array[int] = []
	for k in range(kb):
		path.append(old.nodes[k])
	path.append_array(tail)
	var ns: Array[float] = []
	for k2 in range(kb):
		ns.append(old.node_s[k2])
	var gns: Array = geo["node_s"]
	for k3 in range(1, gns.size()):
		ns.append(cut_s + float(gns[k3]))
	var plan := RoutePlan.new()
	plan._set_points(pts)
	plan.nodes = path
	plan.node_s = ns
	var sm := segments_and_maneuvers(path, ns, plan.length)
	plan.segments.assign(sm["segments"])
	plan.maneuvers.assign(sm["maneuvers"])
	plan.dest_name = old.dest_name
	plan.origin_name = old.origin_name
	# 지하차도: 앞부분은 그대로, 뒷부분은 새 경로가 같은 자리를 지나면 옮겨 준다
	for t in old.tunnels:
		if float(t["to"]) <= cut_s:
			plan.tunnels.append(t.duplicate())
			continue
		var pa: Vector2 = old.point_at(float(t["from"]))[0]
		var pb: Vector2 = old.point_at(float(t["to"]))[0]
		var sa := plan_s_of(plan, pa, cut_s, plan.length)
		var sb := plan_s_of(plan, pb, cut_s, plan.length)
		if sb > sa + 50.0 and (plan.point_at(sa)[0] as Vector2).distance_to(pa) < 2.0 \
				and (plan.point_at(sb)[0] as Vector2).distance_to(pb) < 2.0:
			plan.tunnels.append({"from": sa, "to": sb, "name": t["name"]})
	# 신호 대기: 앞부분은 그대로, 뒷부분은 새 경로가 같은 교차로를 지나면 그 교차로 18m 앞
	for st in old.stops:
		if float(st["s"]) < cut_s:
			plan.stops.append(st.duplicate())
			continue
		var nd := int(st.get("node", -1))
		var at := path.find(nd, kb)
		if at > 0 and at < path.size() - 1:
			var st2: Dictionary = st.duplicate()
			st2["s"] = ns[at] - STOP_BEFORE_NODE
			plan.stops.append(st2)
	return plan


## 점 p를 계획의 폴리라인 [s0, s1] 구간에 투영한 누적 거리.
static func plan_s_of(plan: RoutePlan, p: Vector2, s0: float, s1: float) -> float:
	var best := INF
	var out := s0
	for i in range(1, plan.points.size()):
		if plan.cum[i] < s0 - 1.0 or plan.cum[i - 1] > s1 + 1.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, plan.points[i - 1], plan.points[i])
		var d := q.distance_to(p)
		if d < best:
			best = d
			out = plan.cum[i - 1] + q.distance_to(plan.points[i - 1])
	return out
