## RoutePlan + VehicleSim 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_vehicle_sim.gd
## 퍼즐 팩의 모든 합성 경로로: 경로 계획이 말이 되는지, 20분에 도착하는지, ETA가 일관된지, 이벤트가 한 번씩 나는지 본다.
extends SceneTree

const PUZZLE_DIR := "res://data/puzzles/"
const TRIP_MIN := 20.0

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
	var pts := PackedVector2Array()
	for p in data["route"]:
		pts.append(Vector2(float(p[0]), float(p[1])))
	var plan := RoutePlan.from_pack(data)

	# 경로 계획
	_check(plan.length > 5000.0, name + " 경로 길이")
	_check(plan.segments.size() >= 3, name + " 도로 구간 3개 이상")
	if data.has("routePlan"):
		var turns := 0
		for m in plan.maneuvers:
			if String(m["icon"]).begins_with("turn"):
				turns += 1
		_check(turns >= 1, name + " 실제 회전 안내가 있다")
	_check(plan.maneuvers.back()["icon"] == "flag", name + " 마지막 안내는 도착")
	var prev := -1.0
	for m in plan.maneuvers:
		_check(float(m["s"]) > prev, name + " 회전 안내는 거리순")
		prev = float(m["s"])
	_check(plan.tunnels.size() >= 1 and plan.tunnels.size() <= 2, name + " 터널 1~2개")
	_check(plan.stops.size() >= 2 and plan.stops.size() <= 3, name + " 신호 대기 2~3곳")
	for st in plan.stops:
		_check(plan.tunnel_at(float(st["s"])).is_empty(), name + " 신호는 터널 밖")

	# 주행
	var sim := VehicleSim.new()
	sim.setup(plan, TRIP_MIN, 0.0)
	_check(absf(sim.eta_seconds() - TRIP_MIN * 60.0) < 30.0,
			name + " 출발 시 ETA ≈ 20분 (%.0f초)" % sim.eta_seconds())
	var ev := {"stopped": 0, "resumed": 0, "tunnel_in": 0, "tunnel_out": 0, "arrived": 0}
	sim.stopped.connect(func(_st): ev["stopped"] += 1)
	sim.resumed.connect(func(_st): ev["resumed"] += 1)
	sim.tunnel_entered.connect(func(_t): ev["tunnel_in"] += 1)
	sim.tunnel_exited.connect(func(_t): ev["tunnel_out"] += 1)
	sim.arrived.connect(func(): ev["arrived"] += 1)
	var total := sim.game_time + sim.eta_seconds()
	var worst := 0.0
	var last_s := 0.0
	var max_kmh := 0.0
	var steps := 0
	while not sim.finished and steps < 20000:
		sim.step(0.5)
		steps += 1
		worst = maxf(worst, absf(sim.game_time + sim.eta_seconds() - total))
		_check(sim.s >= last_s, name + " 뒤로 가지 않는다") if sim.s < last_s else null
		last_s = sim.s
		max_kmh = maxf(max_kmh, sim.speed_kmh)
	_check(sim.finished and ev["arrived"] == 1, name + " 도착 한 번")
	_check(absf(sim.game_time - TRIP_MIN * 60.0) < 45.0, name + " 20분 안팎에 도착 (%.0f초)" % sim.game_time)
	_check(worst < 25.0, name + " 경과 + ETA가 일정 (최대 오차 %.1f초)" % worst)
	_check(ev["stopped"] == plan.stops.size() and ev["resumed"] == plan.stops.size(),
			name + " 신호마다 한 번 멈췄다 출발")
	_check(ev["tunnel_in"] == plan.tunnels.size() and ev["tunnel_out"] == plan.tunnels.size(),
			name + " 터널마다 한 번 들어갔다 나옴")
	_check(max_kmh > 25.0 and max_kmh < 110.0, name + " 순항 속도 범위 (최고 %.0fkm/h)" % max_kmh)

	# 중간에서 시작
	var sim2 := VehicleSim.new()
	sim2.setup(plan, TRIP_MIN, 0.5)
	_check(absf(sim2.game_time + sim2.eta_seconds() - sim2.trip_seconds) < 1.0, name + " 중간 시작 시계 일관")
	_check(sim2.eta_seconds() < sim.trip_seconds * 0.75, name + " 중간 시작 ETA가 줄어듦")
	var ups := plan.upcoming(sim2.s, 4)
	_check(not ups.is_empty() and float(ups[0]["distance"]) > 0.0, name + " 다가오는 안내")
	sim.free()
	sim2.free()
