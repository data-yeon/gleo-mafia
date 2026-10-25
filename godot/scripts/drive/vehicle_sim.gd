## 주행 시뮬레이션: 경로 계획을 따라 차를 움직이고 속도, ETA, 터널·신호 대기 이벤트를 낸다.
## 게임 시간(초) 기준으로 이동 전체가 trip_minutes(기본 20분)에 끝나도록 순항 속도를 맞춘다.
## playback은 배속이다(1, 3, 10, 0=일시정지). 영상의 "3x Speed"처럼 기본 3배속.
class_name VehicleSim
extends Node

signal ticked(state: Dictionary)
signal tunnel_entered(tunnel: Dictionary)
signal tunnel_exited(tunnel: Dictionary)
signal stopped(stop: Dictionary)
signal resumed(stop: Dictionary)
signal arrived

const SAMPLE_M := 10.0
const DECEL := 1.3            # 신호·도착 앞 감속(m/s²)
const MIN_KMH := 4.0
const START_KMH := 14.0       # 출발 직후 최저 속도

var plan: RoutePlan
var trip_seconds := 1200.0
var playback := 3.0
var s := 0.0                  # 경로 누적 거리(m)
var game_time := 0.0          # 출발 후 흐른 게임 시간(초)
var dwell_left := 0.0
var speed_kmh := 0.0
var finished := false

var _scale := 1.0
var _t_from := PackedFloat32Array()      # 샘플 i에서 도착까지 남은 시간(대기 포함)
var _stops_done := {}
var _tunnel: Dictionary = {}
var _current_stop: Dictionary = {}


func setup(p: RoutePlan, trip_minutes := 20.0, start_progress := 0.0) -> void:
	plan = p
	trip_seconds = trip_minutes * 60.0
	_fit_speed_scale()
	_build_eta_table()
	s = clampf(start_progress, 0.0, 1.0) * plan.length
	game_time = trip_seconds - eta_seconds()
	dwell_left = 0.0
	finished = s >= plan.length
	_stops_done.clear()
	for i in range(plan.stops.size()):
		if float(plan.stops[i]["s"]) < s:
			_stops_done[i] = true
	_tunnel = plan.tunnel_at(s)
	speed_kmh = target_kmh(s)


# ---------------------------------------------------------------- 속도 모델

func cruise_kmh(x: float) -> float:
	var v := float(plan.segment_at(x)["cruise"])
	if not plan.tunnel_at(x).is_empty():
		v += 8.0
	return v * _scale


## x 지점의 목표 속도(km/h). 신호 대기 지점과 도착 지점 앞에서 감속한다.
func target_kmh(x: float) -> float:
	var v := cruise_kmh(x)
	for st in plan.stops:
		var d := absf(x - float(st["s"]))
		v = minf(v, maxf(sqrt(2.0 * DECEL * d) * 3.6, MIN_KMH))
	v = minf(v, maxf(sqrt(2.0 * DECEL * maxf(plan.length - x, 0.0)) * 3.6, MIN_KMH))
	v = minf(v, maxf(sqrt(2.0 * DECEL * x) * 3.6, START_KMH))
	return v


func _total_dwell() -> float:
	var t := 0.0
	for st in plan.stops:
		t += float(st["dwell"])
	return t


func _travel_seconds() -> float:
	var t := 0.0
	var x := 0.0
	while x < plan.length:
		var step := minf(SAMPLE_M, plan.length - x)
		t += step / (target_kmh(x + step * 0.5) / 3.6)
		x += step
	return t


## 순항 속도 배율을 조절해 전체 이동 시간(주행 + 신호 대기)을 trip_seconds에 맞춘다.
func _fit_speed_scale() -> void:
	_scale = 1.0
	var want := maxf(trip_seconds - _total_dwell(), 60.0)
	for _i in range(8):
		var have := _travel_seconds()
		_scale *= have / want
		_scale = clampf(_scale, 0.2, 5.0)


func _build_eta_table() -> void:
	# 샘플 i에서 도착까지의 순수 주행 시간. 신호 대기 시간은 eta_seconds()에서 따로 더한다
	var n := int(ceil(plan.length / SAMPLE_M)) + 1
	_t_from.resize(n)
	_t_from[n - 1] = 0.0
	for i in range(n - 2, -1, -1):
		var x0 := i * SAMPLE_M
		var x1 := minf((i + 1) * SAMPLE_M, plan.length)
		_t_from[i] = _t_from[i + 1] + (x1 - x0) / (target_kmh((x0 + x1) * 0.5) / 3.6)


## 도착까지 남은 게임 시간(초) = 남은 주행 시간 + 아직 안 거친 신호 대기 + 지금 대기 중인 남은 시간.
func eta_seconds() -> float:
	if plan == null:
		return 0.0
	var f := s / SAMPLE_M
	var i := mini(int(floor(f)), _t_from.size() - 2)
	var t := lerpf(_t_from[i], _t_from[i + 1], clampf(f - i, 0.0, 1.0))
	for k in range(plan.stops.size()):
		if not _stops_done.has(k) and float(plan.stops[k]["s"]) >= s:
			t += float(plan.stops[k]["dwell"])
	return maxf(t, 0.0) + dwell_left


func progress() -> float:
	return plan.progress_of(s)


## 경로가 바뀌었다(경유지 재탐색). 지금 위치 s와 게임 시간은 그대로, 속도 배율도 그대로 두고
## ETA 표만 새로 만든다. 그래서 늘어난 거리만큼 도착이 늦어진다.
func replan(p: RoutePlan) -> void:
	plan = p
	_build_eta_table()
	_stops_done.clear()
	for i in range(plan.stops.size()):
		if float(plan.stops[i]["s"]) < s - 0.01:
			_stops_done[i] = true
	trip_seconds = game_time + eta_seconds()
	_tunnel = plan.tunnel_at(s)
	finished = s >= plan.length


## 다른 계획으로 갔을 때 지금 위치에서 도착까지 걸릴 게임 시간(초). 상태는 바꾸지 않는다.
func eta_with(p: RoutePlan) -> float:
	var t := VehicleSim.new()
	t.plan = p
	t._scale = _scale
	t._build_eta_table()
	t.s = s
	for i in range(p.stops.size()):
		if float(p.stops[i]["s"]) < s - 0.01:
			t._stops_done[i] = true
	var out := t.eta_seconds() + dwell_left
	t.free()
	return out


## 지금 위치에서 경로 위 target 지점까지 걸릴 게임 시간(초). 그 사이 신호 대기 시간도 더한다(target의 대기는 빼고).
func eta_to(target: float) -> float:
	if target <= s:
		return 0.0
	var t := _t_at(s) - _t_at(target)
	for k in range(plan.stops.size()):
		var ss := float(plan.stops[k]["s"])
		if not _stops_done.has(k) and ss >= s and ss < target - 0.5:
			t += float(plan.stops[k]["dwell"])
	return maxf(t, 0.0) + dwell_left


func _t_at(x: float) -> float:
	var f := x / SAMPLE_M
	var i := mini(int(floor(f)), _t_from.size() - 2)
	return lerpf(_t_from[i], _t_from[i + 1], clampf(f - i, 0.0, 1.0))


# ---------------------------------------------------------------- 진행

func _process(delta: float) -> void:
	if plan != null and playback > 0.0:
		step(delta * playback)


## 게임 시간 dt초만큼 진행한다. 테스트에서는 직접 부른다.
func step(dt: float) -> void:
	if finished or plan == null:
		return
	game_time += dt
	if dwell_left > 0.0:
		dwell_left -= dt
		speed_kmh = 0.0
		if dwell_left <= 0.0:
			dwell_left = 0.0
			resumed.emit(_current_stop)
		_emit()
		return
	speed_kmh = target_kmh(s)
	var mid := target_kmh(s + speed_kmh / 3.6 * dt * 0.5)
	var ns := s + mid / 3.6 * dt
	for i in range(plan.stops.size()):
		var ss := float(plan.stops[i]["s"])
		if not _stops_done.has(i) and s < ss and ss <= ns:
			ns = ss
			_stops_done[i] = true
			_current_stop = plan.stops[i]
			dwell_left = float(plan.stops[i]["dwell"])
			speed_kmh = 0.0
			stopped.emit(_current_stop)
			break
	s = minf(ns, plan.length)
	var t := plan.tunnel_at(s)
	if t != _tunnel:
		if not _tunnel.is_empty():
			tunnel_exited.emit(_tunnel)
		if not t.is_empty():
			tunnel_entered.emit(t)
		_tunnel = t
	if s >= plan.length:
		finished = true
		speed_kmh = 0.0
		_emit()
		arrived.emit()
		return
	_emit()


func in_tunnel() -> Dictionary:
	return _tunnel


func is_stopped() -> bool:
	return dwell_left > 0.0


## 지금(또는 마지막으로) 선 지점. 경유지면 "waypoint"가 true다.
func current_stop() -> Dictionary:
	return _current_stop


## 지금 상태로 ticked 신호를 한 번 낸다(화면 초기화용).
func emit_state() -> void:
	_emit()


func _emit() -> void:
	ticked.emit({
		"s": s, "progress": progress(), "speed_kmh": speed_kmh, "eta_s": eta_seconds(),
		"game_time": game_time, "tunnel": _tunnel, "stopped": dwell_left > 0.0,
		"dwell_left": dwell_left,
	})
