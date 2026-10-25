## Godot 길찾기(CityRouter) 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_city_router.gd
## 1) Godot A*·경로 기하·회전 안내가 퍼즐 공장(Python)이 만든 팩의 경로와 같은지
## 2) 주행 중 경유지 재탐색: 지나온 앞부분이 그대로인지, 길이 이어지는지(유턴 없음), 경유지에 서는지
extends SceneTree

const PUZZLE_DIR := "res://data/puzzles/"

var _fails := 0
var _checks := 0


func _initialize() -> void:
	var count := 0
	for f in DirAccess.get_files_at(PUZZLE_DIR):
		if not f.ends_with(".json") or f == "index.json":
			continue
		count += 1
		_test(PUZZLE_DIR + f)
	print("경로 %d개, 확인 %d개, 실패 %d개" % [count, _checks, _fails])
	quit(1 if _fails > 0 or count == 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("실패: " + msg)


func _test(path: String) -> void:
	var name := path.get_file()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var router := CityRouter.from_city(data["city"])
	var plan := RoutePlan.from_pack(data)
	var want: Array[int] = plan.nodes

	# 1) Python과 같은 경로
	var t0 := Time.get_ticks_usec()
	var res := router.astar(want[0], want[want.size() - 1])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(res["path"] == want, name + " A* 경로가 팩과 같다")
	_check(ms < 200.0, name + " A* 200ms 안 (%.1fms)" % ms)
	var geo := router.polyline(want)
	var pts: PackedVector2Array = geo["points"]
	var same_pts := pts.size() == plan.points.size()
	if same_pts:
		for i in range(pts.size()):
			if pts[i].distance_to(plan.points[i]) > 0.2:
				same_pts = false
	_check(same_pts, name + " 둥근 모서리 폴리라인이 팩과 같다")
	var ns: Array = geo["node_s"]
	var same_s := ns.size() == plan.node_s.size()
	if same_s:
		for k in range(ns.size()):
			if absf(float(ns[k]) - plan.node_s[k]) > 1.0:
				same_s = false
	_check(same_s, name + " 교차로 누적 거리가 팩과 같다")
	var sm := router.segments_and_maneuvers(want, plan.node_s, plan.length)
	var mans: Array = sm["maneuvers"]
	var same_m := mans.size() == plan.maneuvers.size()
	if same_m:
		for k2 in range(mans.size()):
			if mans[k2]["icon"] != plan.maneuvers[k2]["icon"] or absf(float(mans[k2]["s"]) - float(plan.maneuvers[k2]["s"])) > 1.0:
				same_m = false
	_check(same_m, name + " 회전 안내가 팩과 같다")

	# 2) 경유지 재탐색: 길가가 아닌 장소 두 곳, 출발 900m 지점에서
	var tried := 0
	for p in data["places"]:
		if bool(p["roadside"]) or tried >= 2:
			continue
		tried += 1
		var id := int(p["id"])
		var pos := Vector2(float(p["x"]), float(p["y"]))
		var s_car := 900.0
		var r := router.reroute(plan, s_car, pos, id, "%d" % id)
		_check(not r.is_empty(), name + " 장소 %d 경유 경로를 찾음" % id)
		if r.is_empty():
			continue
		var np: RoutePlan = r["plan"]
		# 지나온 앞부분(내 차 위치까지)은 그대로
		var same_prefix := true
		for i2 in range(plan.points.size()):
			if plan.cum[i2] > s_car + 10.0:
				break
			if i2 >= np.points.size() or np.points[i2].distance_to(plan.points[i2]) > 0.001:
				same_prefix = false
		_check(same_prefix, name + " 장소 %d: 지나온 앞부분이 그대로" % id)
		_check((np.point_at(s_car)[0] as Vector2).distance_to(plan.point_at(s_car)[0]) < 0.01,
				name + " 장소 %d: 내 차 위치 s가 이어진다" % id)
		# 길이 이어지고 유턴이 없다
		var ok_edges := true
		var no_uturn := true
		for k3 in range(np.nodes.size() - 1):
			if router.edge_between(np.nodes[k3], np.nodes[k3 + 1]) < 0:
				ok_edges = false
			if k3 >= 1 and np.nodes[k3 + 1] == np.nodes[k3 - 1]:
				no_uturn = false
		_check(ok_edges, name + " 장소 %d: 노드가 도로로 이어진다" % id)
		_check(no_uturn, name + " 장소 %d: 유턴 없음" % id)
		_check(np.nodes[np.nodes.size() - 1] == want[want.size() - 1], name + " 장소 %d: 목적지 같음" % id)
		# 경유지 정차와 안내
		_check(np.waypoint_place == id and np.waypoint_s > s_car and np.waypoint_s < np.length,
				name + " 장소 %d: 경유지 정차 지점" % id)
		var wp_stop := false
		for st in np.stops:
			if bool(st.get("waypoint", false)) and absf(float(st["s"]) - np.waypoint_s) < 0.01:
				wp_stop = true
		_check(wp_stop, name + " 장소 %d: 경유지 정차가 신호 대기 목록에 있다" % id)
		var wp_man := false
		var sorted_ok := true
		for k4 in range(np.maneuvers.size()):
			if bool(np.maneuvers[k4].get("waypoint", false)):
				wp_man = true
			if k4 > 0 and float(np.maneuvers[k4]["s"]) < float(np.maneuvers[k4 - 1]["s"]):
				sorted_ok = false
		_check(wp_man and sorted_ok and np.maneuvers.back()["icon"] == "flag", name + " 장소 %d: 경유지 안내, 거리순" % id)
		var d := (np.point_at(np.waypoint_s)[0] as Vector2).distance_to(pos)
		_check(d < 330.0, name + " 장소 %d: 경유지가 장소에서 330m 안 (%.0fm)" % [id, d])
		for st2 in np.stops:
			if not bool(st2.get("waypoint", false)) and float(st2["s"]) > s_car:
				_check(np.nodes.has(int(st2["node"])), name + " 장소 %d: 남은 신호 대기 교차로가 새 경로 위" % id)
