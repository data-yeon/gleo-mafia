## 자율주행 패널 3D 도시·주변 차 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_adas_world.gd
## 팩의 모든 도시로 AdasWorld를 만들어 신호 교차로, 정지선, 랜드마크 자리를 보고,
## 사건 몇 개는 처음부터 끝까지 달리며 주변 차가 빨간불 정지선을 넘지 않는지, 보행자가 쌓이지 않는지 본다.
extends SceneTree

const PUZZLE_DIR := "res://data/puzzles/"
const EGO_HALF_LEN := 2.4
const DRIVE_CASES := 3

var _fails := 0
var _checks := 0


func _initialize() -> void:
	var count := 0
	for f in DirAccess.get_files_at(PUZZLE_DIR):
		if not f.ends_with(".json") or f == "index.json":
			continue
		_test(PUZZLE_DIR + f, count < DRIVE_CASES)
		count += 1
	print("도시 %d개, 확인 %d개, 실패 %d개" % [count, _checks, _fails])
	quit(1 if _fails > 0 or count == 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("실패: " + msg)


func _test(path: String, drive: bool) -> void:
	var name := path.get_file()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var plan := RoutePlan.from_pack(data)
	var world := AdasWorld.new()
	root.add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build(data, plan)
	var ms := Time.get_ticks_msec() - t0
	_check(ms < 1500, name + " 도시 만들기 1.5초 안 (%dms)" % ms)
	var meshes := 0
	for c in world.get_children():
		if c is MeshInstance3D:
			meshes += 1
	_check(meshes > 20, name + " 도로 덩어리 메시 (%d)" % meshes)
	var trees := 0
	for p in world.props:
		trees += (p as MultiMeshInstance3D).multimesh.instance_count
	_check(trees > 500, name + " 가로수·가로등 (%d)" % trees)

	# 신호 대기 지점마다 신호 교차로가 있고, 내 차는 정지선 바로 뒤에 선다
	for i in range(plan.stops.size()):
		var sig := {}
		for sg in world.signals:
			if int(sg["stop"]) == i:
				sig = sg
		_check(not sig.is_empty(), name + " 신호 대기 %d의 신호등" % i)
		if sig.is_empty():
			continue
		var stop_s := float(plan.stops[i]["s"])
		var line_s := float(sig["line_s"])
		_check(stop_s + EGO_HALF_LEN <= line_s + 0.3, name + " 내 차 앞범퍼가 정지선 뒤 (%.1f / %.1f)" % [stop_s + EGO_HALF_LEN, line_s])
		_check(line_s - stop_s < 12.0, name + " 정지선에서 너무 멀리 서지 않음 (%.1fm)" % (line_s - stop_s))
		_check(line_s < float(sig["s_node"]) and float(sig["s_node"]) < float(sig["far_line_s"]),
				name + " 정지선 < 교차로 < 맞은편 정지선")
		_check(sig["light"] != null and (sig["ped_lights"] as Array).size() == 2, name + " 차량·보행 신호등")

	# 길가 랜드마크 자리는 도로·보도 밖
	for id in world.landmark_spots:
		var pos: Vector2 = world.landmark_spots[id]["pos"]
		var s := world.s_of(pos, plan.length * 0.5)
		var best := INF
		for k in range(1, plan.points.size()):
			var q := Geometry2D.get_closest_point_to_segment(pos, plan.points[k - 1], plan.points[k])
			best = minf(best, q.distance_to(pos))
		_check(best > world.half_at(s) + AdasWorld.SIDEWALK_W + 2.0, name + " 랜드마크 %d가 보도 밖 (%.1fm)" % [int(id), best])

	if drive:
		_drive(name, data, plan, world)
	world.queue_free()


## 처음부터 끝까지 달린다. AdasView처럼 빨간불 교차로를 골라 주변 차에 넘긴다.
func _drive(name: String, data: Dictionary, plan: RoutePlan, world: AdasWorld) -> void:
	var traffic := AdasTraffic.new()
	root.add_child(traffic)
	traffic.setup(world, 0.0, int(data["seed"]))
	var sim := VehicleSim.new()
	sim.setup(plan, 20.0, 0.0)
	var crossed := 0
	var bad_lane := 0
	var max_crossings := 0
	var steps := 0
	var was_before := {}
	while not sim.finished and steps < 6000:
		sim.step(0.5)
		steps += 1
		var s := sim.s
		var red := {}
		for sig in world.signals:
			var st := int(sig["stop"])
			if st < 0:
				continue
			var stop_s := float(plan.stops[st]["s"])
			var is_red := s < stop_s - 0.3 or (sim.is_stopped() and absf(s - stop_s) < 1.0)
			world.set_signal_green(sig, not is_red)
			if is_red and red.is_empty() and float(sig["s_node"]) - s < 280.0:
				red = sig
		traffic.update(s, sim.speed_kmh, red, 0.5, 0.5 / 3.0)
		max_crossings = maxi(max_crossings, traffic._crossings.size())
		for c in traffic._cars:
			if not bool(c["active"]) or bool(c["lead"]):
				continue
			var cs := float(c["s"])
			if int(c["lane"]) > world.lanes_at(cs) or int(c["lane"]) < 1:
				bad_lane += 1
			# 빨간불일 때 앞범퍼가 정지선 앞에 있던 차가 다음 순간 넘어가면 안 된다(다시 배치된 차는 제외)
			var key: int = c["node"].get_instance_id()
			if not red.is_empty():
				var line := float(red["line_s"]) if int(c["dir"]) > 0 else float(red["far_line_s"])
				var front := cs + float(c["len"]) / 2.0 * int(c["dir"])
				var before: bool = front < line if int(c["dir"]) > 0 else front > line
				if was_before.get(key, false) and not before and absf(cs - line) < 20.0:
					crossed += 1
				was_before[key] = before
			else:
				was_before.erase(key)
	_check(sim.finished, name + " 끝까지 달림")
	_check(crossed == 0, name + " 빨간불 정지선을 넘은 주변 차 없음 (%d)" % crossed)
	_check(bad_lane == 0, name + " 차로 번호가 도로 차로 수 안 (%d)" % bad_lane)
	_check(max_crossings <= 4, name + " 횡단보도 보행자 무리가 쌓이지 않음 (최대 %d)" % max_crossings)
	sim.free()
	traffic.queue_free()
