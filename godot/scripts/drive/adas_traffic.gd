## 자율주행 패널의 움직이는 것들: 주변 차, 마주 오는 차, 교차로를 가로지르는 차, 보행자, 출동 경찰차.
## 모두 경로 누적 거리 s와 옆 거리(진행 방향 오른쪽 +)로 움직인다(교차 차량만 직선).
## 시간은 게임 시간(실제 시간 × 배속)으로 흐른다. 내 차 속도와 같은 시간 축이다.
## - 같은 방향: 내 차로 앞 "앞차" 1대 + 옆 차로 차들. 빨간불이면 정지선 앞에 줄을 선다(앞차는 그 전에 지나간다).
## - 마주 오는 차: 왼쪽 차로. 빨간불이면 맞은편 정지선에 선다.
## - 신호 대기 중에는 가로지르는 길로 차가 지나가고, 보행자가 횡단보도를 건넌다.
class_name AdasTraffic
extends Node3D

const LANE_W := AdasWorld.LANE_W
const AHEAD := 185.0               # 이만큼 앞(안개 속)에서 나타난다
const BEHIND := 30.0               # 이만큼 뒤로 처지면 다시 배치한다
const GAP := 2.8                   # 줄 선 차 사이 간격(m)
const N_SIDE := 5
const N_ONCOMING := 6
const N_WALKERS := 8
const RING_COLOR := Color(0.25, 0.5, 1.0, 0.55)
const KINDS := [["traffic_sedan", 30], ["traffic_suv", 20], ["compact", 12], ["taxi", 14], ["truck", 10],
		["bus", 8], ["scooter", 6]]

var world: AdasWorld
var ego_lane := 0                      # 내 차 차로(0이면 도로 차로 수로 정함). 경유지 앞에서 바깥 차로로 바뀐다
var _rng := RandomNumberGenerator.new()
var _cars: Array[Dictionary] = []      # {node, kind, len, s, lane, dir, rel, lead, lat, active}
var _cross: Array[Dictionary] = []     # {node, pos, vel, left}
var _crossings := {}                   # 신호 인덱스 → {peds: [...]}
var _walkers: Array[Dictionary] = []   # {node, s, side, dir, speed, phase, legs}
var _police: Dictionary = {}
var _ref_v := 14.0                     # 주변 차 기준 속도(m/s). 내 차 순항 속도를 따라간다
var _cross_timer := 0.0
var _blink := 0.0
var _ring_mat: StandardMaterial3D


func setup(w: AdasWorld, ego_s: float, seed_value: int) -> void:
	world = w
	_rng.seed = seed_value
	for c in get_children():
		c.queue_free()
	_cars.clear()
	_cross.clear()
	_crossings.clear()
	_walkers.clear()
	_police = {}
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = RING_COLOR
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 앞차
	_cars.append(_new_car(_pick_kind(false), 1, true))
	_cars[0]["s"] = ego_s + 26.0
	for _i in range(N_SIDE):
		var c := _new_car(_pick_kind(true), 1, false)
		_respawn(c, ego_s, true, ego_s + _rng.randf_range(-15.0, 150.0))
		_cars.append(c)
	for _j in range(N_ONCOMING):
		var c2 := _new_car(_pick_kind(true), -1, false)
		_respawn(c2, ego_s, true, ego_s + _rng.randf_range(0.0, AHEAD))
		_cars.append(c2)
	for _k in range(N_WALKERS):
		var w2 := _new_walker()
		_respawn_walker(w2, ego_s, ego_s + _rng.randf_range(-10.0, 170.0))
		_walkers.append(w2)


func _pick_kind(any: bool) -> String:
	var total := 0
	for k in KINDS:
		if any or not (k[0] in ["bus", "scooter"]):
			total += int(k[1])
	var r := _rng.randi_range(0, total - 1)
	for k2 in KINDS:
		if not any and k2[0] in ["bus", "scooter"]:
			continue
		r -= int(k2[1])
		if r < 0:
			return String(k2[0])
	return "traffic_sedan"


func _new_car(kind: String, dir: int, lead: bool) -> Dictionary:
	var node := AdasAssets.instance(kind)
	if node == null:
		node = AdasAssets.box_vehicle(Color("bcc3cc"))
	if kind == "taxi":
		AdasAssets.set_lamp(node, "TaxiSign", true)
	add_child(node)
	return {"node": node, "kind": kind, "len": AdasAssets.size_of(kind).z, "s": 0.0, "lane": 1, "dir": dir,
			"rel": _rng.randf_range(-0.1, 0.14), "lead": lead, "lat": 0.0, "active": true, "snap": true, "qlim": null}


func _ego_lane(s: float) -> int:
	var lanes := world.lanes_at(s)
	if ego_lane > 0:
		return mini(ego_lane, lanes)
	return 2 if lanes >= 3 else 1


func _lane_lat(c: Dictionary) -> float:
	return float(c["dir"]) * (float(c["lane"]) - 0.5) * LANE_W


## 차를 다시 배치한다. 앞(안개 속)이나 뒤(화면 밖)에서, 같은 차로 차와 겹치지 않게.
func _respawn(c: Dictionary, ego_s: float, ahead: bool, at := -1.0) -> void:
	for _try in range(6):
		var s := at if at >= 0.0 else (ego_s + _rng.randf_range(AHEAD - 30.0, AHEAD) if ahead
				else ego_s - BEHIND + _rng.randf_range(0.0, 4.0))
		at = -1.0
		if _try >= 3:
			s = ego_s + _rng.randf_range(-BEHIND, AHEAD)    # 경로 끝 근처면 앞뒤 아무 데나
		if s < 5.0 or s > world.plan.length - 5.0:
			continue
		if world.in_tunnel(s, 30.0) and _rng.randf() < 0.5:
			continue
		var lanes := world.lanes_at(s)
		var choices: Array[int] = []
		for l in range(1, lanes + 1):
			if int(c["dir"]) > 0 and l == _ego_lane(s):
				continue
			if String(c["kind"]) in ["bus", "scooter"] and l != lanes:
				continue
			choices.append(l)
		if choices.is_empty():
			continue
		var lane: int = choices[_rng.randi_range(0, choices.size() - 1)]
		var clear := true
		for o in _cars:
			if o != c and bool(o["active"]) and int(o["dir"]) == int(c["dir"]) and int(o["lane"]) == lane \
					and absf(float(o["s"]) - s) < (float(o["len"]) + float(c["len"])) / 2.0 + 8.0:
				clear = false
				break
		if not clear:
			continue
		c["s"] = s
		c["lane"] = lane
		c["active"] = true
		c["snap"] = true
		(c["node"] as Node3D).visible = true
		return
	c["active"] = false
	(c["node"] as Node3D).visible = false


# ---------------------------------------------------------------- 매 프레임

## ego_s·ego_kmh: 내 차. red: 지금 빨간불인 우리 앞 신호(없으면 {}). dt: 게임 시간.
func update(ego_s: float, ego_kmh: float, red: Dictionary, dt: float, real_dt: float) -> void:
	if world == null:
		return
	var ego_v := ego_kmh / 3.6
	if ego_v > 4.0:
		_ref_v = lerpf(_ref_v, ego_v, clampf(dt * 0.3, 0.0, 1.0))
	_update_cars(ego_s, ego_v, red, dt)
	_update_cross(ego_s, red, dt)
	_update_crossings(ego_s, dt)
	_update_walkers(ego_s, dt)
	_update_police(ego_s, ego_v, dt, real_dt)


func _update_cars(ego_s: float, ego_v: float, red: Dictionary, dt: float) -> void:
	var line_s := float(red.get("line_s", INF))
	var far_s := float(red.get("far_line_s", -INF))
	# 빨간불 줄서기: 차로마다 정지선에 가까운 차부터 설 자리(qlim)를 정한다
	for c0 in _cars:
		c0["qlim"] = null
	if not red.is_empty():
		for dir in [1, -1]:
			var lanes_q := {}
			for c in _cars:
				if not bool(c["active"]) or bool(c["lead"]) or int(c["dir"]) != dir:
					continue
				# 앞범퍼가 아직 정지선 앞이면 줄을 선다(이미 넘었으면 그대로 지나간다)
				var front: float = float(c["s"]) + float(c["len"]) / 2.0 * dir
				var before: bool = front < line_s if dir > 0 else front > far_s
				if before and absf(float(c["s"]) - float(red["s_node"])) < 220.0:
					lanes_q.get_or_add(int(c["lane"]), []).append(c)
			for lane in lanes_q:
				var list: Array = lanes_q[lane]
				if dir > 0:
					list.sort_custom(func(a, b): return float(a["s"]) > float(b["s"]))
				else:
					list.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
				var edge: float = line_s - 0.8 if dir > 0 else far_s + 0.8
				for c2 in list:
					var half_len := float(c2["len"]) / 2.0
					c2["qlim"] = edge - half_len if dir > 0 else edge + half_len
					edge = edge - (float(c2["len"]) + GAP) if dir > 0 else edge + float(c2["len"]) + GAP
	for c in _cars:
		if not bool(c["active"]):
			if _rng.randf() < 0.05:
				_respawn(c, ego_s, true)
			continue
		var s := float(c["s"])
		var dir := int(c["dir"])
		var v := _ref_v * (1.0 + float(c["rel"]))
		if bool(c["lead"]):
			# 앞차: 내 차 앞 22~30m를 유지한다. 빨간불 앞이면 미리 지나가 버리고, 지나갔으면 제 속도로 간다.
			var want := ego_s + 24.0 + float(c["rel"]) * 30.0
			if not red.is_empty() and s < line_s + 6.0 and line_s - ego_s < 200.0:
				v = maxf(_ref_v, ego_v) * 1.45
			elif not red.is_empty() and s >= line_s + 6.0:
				v = _ref_v
			elif ego_v < 0.5:
				v = _ref_v                            # 내 차가 (경유지 등에) 서면 앞차는 제 갈 길을 간다
			elif s > want + 30.0:
				v = ego_v * 0.85                      # 멀리 앞(안개 속)에서는 천천히 따라잡히게
			else:
				v = maxf(ego_v + (want - s) * 0.6, 0.0)
			c["lane"] = _ego_lane(s)
		var ns := s + v * dt * dir
		# 내 차와 같은 차로의 옆 차는 내 차와 겹치지 않는다(경유지 앞 차로 바꿈)
		if dir > 0 and not bool(c["lead"]) and int(c["lane"]) == _ego_lane(ego_s):
			var gap := float(c["len"]) / 2.0 + 2.4 + 2.5
			if s <= ego_s:
				ns = minf(ns, maxf(s, ego_s - gap))
			elif ns < ego_s + gap:
				ns = ego_s + gap
		if c["qlim"] != null:
			var lim := float(c["qlim"])
			ns = minf(ns, maxf(lim, s)) if dir > 0 else maxf(ns, minf(lim, s))
		c["s"] = ns
		# 차로가 줄면 바깥 차로 차는 안쪽으로 합류(내 차 옆이면 다시 배치)
		var lanes := world.lanes_at(ns)
		if int(c["lane"]) > lanes:
			if dir > 0 and absf(ns - ego_s) < 16.0:
				_respawn(c, ego_s, true)
				continue
			c["lane"] = lanes
		# 범위를 벗어나면 다시 배치
		if ns < ego_s - BEHIND or ns > ego_s + AHEAD + 15.0 or ns >= world.plan.length - 2.0:
			if bool(c["lead"]):
				c["s"] = ego_s + AHEAD
				c["snap"] = true
			else:
				var slow := ns < ego_s
				_respawn(c, ego_s, slow or dir < 0)
			continue
		# 옆 거리는 이동 거리에 비례해 부드럽게 맞춘다(차로 바뀜·합류)
		var target := _lane_lat(c)
		if bool(c["snap"]):
			c["lat"] = target
			c["snap"] = false
		else:
			c["lat"] = lerpf(float(c["lat"]), target, clampf(absf(ns - s) / 22.0, 0.0, 1.0))
		(c["node"] as Node3D).transform = world.xform(ns, float(c["lat"]), dir < 0)


## 신호 대기 중: 가로지르는 길로 차가 양쪽에서 지나간다.
func _update_cross(ego_s: float, red: Dictionary, dt: float) -> void:
	var cross: Dictionary = red.get("cross", {})
	if not cross.is_empty() and absf(float(red["s_node"]) - ego_s) < 140.0:
		_cross_timer -= dt
		if _cross_timer <= 0.0:
			_cross_timer = _rng.randf_range(2.2, 4.5)
			var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
			var d: Vector2 = (cross["dir"] as Vector2) * sgn
			var right := Vector2(d.y, -d.x)
			var lane := _rng.randi_range(1, int(cross["lanes"]))
			var kind := _pick_kind(false)
			var node := AdasAssets.instance(kind)
			if node == null:
				node = AdasAssets.box_vehicle(Color("bcc3cc"))
			add_child(node)
			var start: Vector2 = (red["p"] as Vector2) - d * 110.0 + right * (lane - 0.5) * LANE_W
			_cross.append({"node": node, "pos": start, "vel": d * _rng.randf_range(10.0, 14.0), "left": 220.0})
	for i in range(_cross.size() - 1, -1, -1):
		var c: Dictionary = _cross[i]
		var step: Vector2 = (c["vel"] as Vector2) * dt
		c["pos"] = (c["pos"] as Vector2) + step
		c["left"] = float(c["left"]) - step.length()
		var node: Node3D = c["node"]
		node.position = AdasWorld.v3(c["pos"])
		node.rotation.y = AdasWorld.yaw_facing(c["vel"])
		if float(c["left"]) <= 0.0:
			node.queue_free()
			_cross.remove_at(i)


# ---------------------------------------------------------------- 보행자

func _new_person() -> Node3D:
	var ids := ["ped_suit", "ped_casual", "ped_kid", "ped_umbrella"]
	var w := [32, 38, 14, 16]
	var r := _rng.randi_range(0, 99)
	var id := "ped_casual"
	for i in range(ids.size()):
		r -= w[i]
		if r < 0:
			id = ids[i]
			break
	var node := AdasAssets.instance(id)
	if node == null:
		node = Node3D.new()
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.25
		cap.height = 1.7
		mi.mesh = cap
		mi.position.y = 0.85
		node.add_child(mi)
	# 보행자 인식 링
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.64
	ring.mesh = torus
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.06
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)
	add_child(node)
	return node


static func _stride(node: Node3D, angle: float) -> void:
	var l := node.find_child("LegL", true, false) as Node3D
	var r := node.find_child("LegR", true, false) as Node3D
	if l != null:
		l.rotation.x = angle
	if r != null:
		r.rotation.x = -angle


## 신호 교차로 횡단보도의 보행자: 230m 앞부터 세우고, 보행 신호(우리 빨간불)면 건넌다. 지나가면 치운다.
func _update_crossings(ego_s: float, dt: float) -> void:
	for i in range(world.signals.size()):
		var sig: Dictionary = world.signals[i]
		var ds := float(sig["s_node"]) - ego_s
		var near := ds < 230.0 and ds > -70.0
		if near and not _crossings.has(i):
			_crossings[i] = _spawn_crossing(sig)
		elif not near and _crossings.has(i):
			for p in _crossings[i]:
				(p["node"] as Node3D).queue_free()
			_crossings.erase(i)
	for i2 in _crossings:
		var sig2: Dictionary = world.signals[i2]
		# 보행 신호(우리 빨간불)이고 내 차가 정지선 가까이 왔을 때 건너기 시작한다
		var walk := sig2["green"] is bool and not bool(sig2["green"]) and float(sig2["line_s"]) - ego_s < 45.0
		for p2 in _crossings[i2]:
			var node: Node3D = p2["node"]
			var to: Vector2 = p2["to"]
			var pos: Vector2 = p2["pos"]
			if walk and float(p2["delay"]) > 0.0:
				p2["delay"] = float(p2["delay"]) - dt
			if walk and float(p2["delay"]) <= 0.0 and pos.distance_to(to) > 0.05:
				var step := minf(float(p2["speed"]) * dt, pos.distance_to(to))
				pos += (to - pos).normalized() * step
				p2["pos"] = pos
				p2["phase"] = float(p2["phase"]) + step * 3.2
				_stride(node, sin(float(p2["phase"])) * 0.42)
				node.rotation.y = AdasWorld.yaw_facing(to - pos) if pos.distance_to(to) > 0.05 else node.rotation.y
			else:
				_stride(node, 0.0)
			node.position = AdasWorld.v3(pos, 0.05)


func _spawn_crossing(sig: Dictionary) -> Array:
	var out := []
	var is_stop := int(sig["stop"]) >= 0
	for key in ["near", "far"]:
		var cw: Dictionary = sig[key]
		var c: Vector2 = cw["c"]
		var f: Vector2 = cw["f"]
		var right := Vector2(f.y, -f.x)
		var edge := float(cw["half"]) + 1.4
		var n := _rng.randi_range(2, 4) if is_stop else _rng.randi_range(0, 2)
		for k in range(n):
			var side := 1.0 if k % 2 == 0 else -1.0
			var along := _rng.randf_range(-1.1, 1.1)
			var from := c + right * side * (edge + _rng.randf_range(0.0, 1.2)) + f * along
			var to := c - right * side * (edge + _rng.randf_range(0.0, 1.0)) + f * along * 0.6
			var node := _new_person()
			node.rotation.y = AdasWorld.yaw_facing(to - from)
			out.append({"node": node, "pos": from, "to": to, "speed": _rng.randf_range(1.1, 1.5),
					"delay": _rng.randf_range(0.0, 3.0), "phase": _rng.randf_range(0.0, TAU)})
	return out


## 보도를 걷는 사람들: 경로 양쪽 보도(다리·지하차도 제외)에서 앞뒤로 걷는다.
func _new_walker() -> Dictionary:
	return {"node": _new_person(), "s": 0.0, "side": 1.0, "dir": 1.0, "speed": 1.3,
			"phase": _rng.randf_range(0.0, TAU), "off": 0.0}


func _respawn_walker(w: Dictionary, ego_s: float, at := -1.0) -> void:
	for _try in range(8):
		var s := at if at >= 0.0 else ego_s + _rng.randf_range(AHEAD - 60.0, AHEAD - 10.0)
		at = -1.0
		if _try >= 4:
			s = ego_s + _rng.randf_range(-BEHIND, AHEAD)    # 경로 끝 근처면 앞뒤 아무 데나
		if s < 5.0 or s > world.plan.length - 5.0:
			continue
		if world.cls_at(s) == "bridge" or world.in_tunnel(s, 30.0):
			continue
		w["s"] = s
		w["side"] = 1.0 if _rng.randf() < 0.6 else -1.0
		w["dir"] = 1.0 if _rng.randf() < 0.5 else -1.0
		w["speed"] = _rng.randf_range(1.0, 1.5)
		w["off"] = _rng.randf_range(1.0, 2.0)
		(w["node"] as Node3D).visible = true
		return
	(w["node"] as Node3D).visible = false


func _update_walkers(ego_s: float, dt: float) -> void:
	for w in _walkers:
		var s := float(w["s"]) + float(w["speed"]) * float(w["dir"]) * dt
		w["s"] = s
		if s < ego_s - BEHIND or s > ego_s + AHEAD or world.cls_at(s) == "bridge" or world.in_tunnel(s, 30.0):
			_respawn_walker(w, ego_s)
			s = float(w["s"])
		var node: Node3D = w["node"]
		var lat := float(w["side"]) * (world.half_at(s) + float(w["off"]))
		node.transform = world.xform(s, lat, float(w["dir"]) < 0.0, 0.05)
		w["phase"] = float(w["phase"]) + float(w["speed"]) * dt * 3.2
		_stride(node, sin(float(w["phase"])) * 0.42)


# ---------------------------------------------------------------- 출동

func play_police(ego_s: float) -> void:
	if not _police.is_empty():
		(_police["node"] as Node3D).queue_free()
	var node := AdasAssets.instance("police_car")
	if node == null:
		node = AdasAssets.box_vehicle(Color("f2f4f8"))
	add_child(node)
	_police = {"node": node, "s": ego_s - 18.0, "lat": 0.0, "t": 0.0}


func _update_police(ego_s: float, ego_v: float, dt: float, real_dt: float) -> void:
	if _police.is_empty():
		return
	var s := float(_police["s"]) + (maxf(ego_v, 8.0) + 10.0) * dt
	_police["s"] = s
	_police["t"] = float(_police["t"]) + real_dt
	# 내 차 왼쪽 차로로 추월 (편도 1차로면 중앙선 넘어)
	var lane := _ego_lane(s) - 1
	var lat := (float(lane) - 0.5) * LANE_W if lane >= 1 else -0.5 * LANE_W
	(_police["node"] as Node3D).transform = world.xform(s, lat)
	_blink += real_dt
	var on := int(_blink * 7.0) % 2 == 0
	AdasAssets.set_lamp(_police["node"], "LightBarRed", on)
	AdasAssets.set_lamp(_police["node"], "LightBarBlue", not on)
	if s > ego_s + AHEAD + 20.0 or float(_police["t"]) > 14.0:
		(_police["node"] as Node3D).queue_free()
		_police = {}
