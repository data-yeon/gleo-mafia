## NavMap 도시 그리기 데이터 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_nav_map.gd
## 팩의 모든 가상 도시로: 도로 줄 잇기, 외곽 덧붙이기, 이름 자리(경로 위는 빼기), 회전 지점이 말이 되는지 본다.
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
	print("지도 %d개, 확인 %d개, 실패 %d개" % [count, _checks, _fails])
	quit(1 if _fails > 0 or count == 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("실패: " + msg)


func _test(path: String) -> void:
	var name := path.get_file()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var city: Dictionary = data["city"]
	var pts := PackedVector2Array()
	for p in data["route"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var map := NavMap.new()
	map.set_city(city, data["routePlan"]["nodes"], int(data["seed"]))
	map.set_route(pts, int(data["seed"]))

	_check(map._has_city, name + " 도시 사용")
	_check(map._area_mesh != null, name + " 블록·공원·강 메시")
	for cls in NavMap.ROAD_CLASSES:
		_check(not map._chains[cls].is_empty(), name + " 도로 줄 있음: " + cls)
	# 같은 이름 도로를 이어 붙여 그리기 호출이 도로 조각 수보다 훨씬 적다
	var n_chains := 0
	var n_points := 0
	for cls2 in map._chains:
		for ch in map._chains[cls2]:
			n_chains += 1
			n_points += ch["pts"].size()
	_check(n_chains * 3 < n_points, name + " 도로 줄 이어 붙임 (%d줄, %d점)" % [n_chains, n_points])

	# 외곽: 격자 크기만큼 노드가 늘고, 도시 범위 밖까지 도로가 있다
	var g: Dictionary = city["grid"]
	var core := int(g["cols"]) * int(g["rows"])
	_check(core == city["nodes"].size(), name + " grid 크기 = 노드 수")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in city["nodes"]:
		lo = lo.min(Vector2(float(n[0]), float(n[1])))
		hi = hi.max(Vector2(float(n[0]), float(n[1])))
	var box := Rect2(lo, Vector2.ZERO)
	for cls3 in map._chains:
		for ch2 in map._chains[cls3]:
			box = box.merge(ch2["box"])
	_check(box.position.x < lo.x - 5000.0 and box.end.x > hi.x + 5000.0, name + " 외곽이 동서로 5km 넘게")
	_check(box.position.y < lo.y - 3000.0 and box.end.y > hi.y + 3000.0, name + " 외곽이 남북으로 3km 넘게")

	# 이름 자리: 큰길·강 이름이 있고, 경로가 지나는 도로 조각 위에는 없다
	_check(not map._labels["arterial"].is_empty(), name + " 큰길 이름")
	_check(not map._labels["water"].is_empty(), name + " 강 이름")
	var on_route := 0
	for cls4 in map._labels:
		for lb in map._labels[cls4]:
			if float(lb.get("route_d", INF)) < 3.0:
				on_route += 1
	_check(on_route == 0, name + " 경로선 위 이름 없음 (%d개)" % on_route)

	# 회전 지점은 경로 위
	var plan := RoutePlan.from_pack(data)
	for m in plan.maneuvers:
		if String(m["icon"]).begins_with("turn"):
			var at: Vector2 = map.route_point(plan.progress_of(float(m["s"])))[0]
			var want: Vector2 = plan.point_at(float(m["s"]))[0]
			_check(at.distance_to(want) < 5.0, name + " 회전 지점이 경로와 일치")
	map.free()
