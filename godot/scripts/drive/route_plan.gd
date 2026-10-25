## 경로 계획: 폴리라인 + 도로 구간(이름, 순항 속도) + 회전 안내 + 터널 + 신호 대기 지점.
## 거리는 모두 경로 시작부터의 누적 거리(m)다.
## 퍼즐 팩 v3에 경로 계획(가상 도시 A* 경로)이 있으면 from_pack으로 그대로 읽고, 없으면 합성 경로에서 만든다(synthetic).
## 실제 지도(OSM/OSRM)도 같은 구조로 채우면 된다.
class_name RoutePlan
extends RefCounted

const ROAD_NAMES := ["강변북로", "테헤란로", "강남대로", "도산대로", "영동대로", "봉은사로",
		"언주로", "논현로", "삼성로", "선릉로"]
const TUNNEL_NAMES := ["남산1호 터널", "금화 터널", "구룡 터널", "홍지문 터널", "북악 터널"]
const TURN_SLIGHT_DEG := 12.0
const TURN_SHARP_DEG := 45.0

var points := PackedVector2Array()      # 월드 좌표(m, x=동, y=북)
var cum := PackedFloat32Array()
var length := 0.0
var segments: Array[Dictionary] = []    # {name, from, to, cruise(km/h)}
var maneuvers: Array[Dictionary] = []   # {s, icon, verb, road}
var tunnels: Array[Dictionary] = []     # {from, to, name}
var stops: Array[Dictionary] = []       # {s, dwell(초)}
var dest_name := "목적지"
var origin_name := "출발지"
var waypoints: Array[int] = []          # 경유지 노드 (가상 도시 그래프 기준)
var nodes: Array[int] = []              # 지나는 교차로 (가상 도시 그래프). 합성 경로면 비어 있다
var node_s: Array[float] = []           # 교차로까지 누적 거리(m)
var waypoint_place := -1                # 경유지 잠복으로 들르는 사건 장소 id (없으면 -1)
var waypoint_s := -1.0                  # 경유지에서 서는 지점(m)


## 퍼즐 팩에서 경로 계획을 읽는다. routePlan이 없으면(예전 팩) 합성 경로 계획을 만든다.
static func from_pack(data: Dictionary) -> RoutePlan:
	var pts := PackedVector2Array()
	for q in data["route"]:
		pts.append(Vector2(float(q[0]), float(q[1])))
	if not data.has("routePlan"):
		return synthetic(pts, int(data.get("seed", 7)))
	var rp: Dictionary = data["routePlan"]
	var p := RoutePlan.new()
	p._set_points(pts)
	for sg in rp["segments"]:
		p.segments.append({"name": String(sg["name"]), "cls": String(sg.get("cls", "")),
				"from": float(sg["from"]), "to": float(sg["to"]), "cruise": float(sg["cruise"])})
	for m in rp["maneuvers"]:
		p.maneuvers.append({"s": minf(float(m["s"]), p.length), "icon": String(m["icon"]),
				"verb": String(m["verb"]), "road": String(m["road"]), "at": String(m.get("at", "")),
				"waypoint": bool(m.get("waypoint", false))})
	for t in rp["tunnels"]:
		p.tunnels.append({"from": float(t["from"]), "to": float(t["to"]), "name": String(t["name"])})
	for st in rp["stops"]:
		p.stops.append({"s": float(st["s"]), "dwell": float(st["dwell"]), "node": int(st.get("node", -1))})
	for w in rp.get("waypoints", []):
		p.waypoints.append(int(w))
	for n in rp.get("nodes", []):
		p.nodes.append(int(n))
	for v in rp.get("nodeS", []):
		p.node_s.append(float(v))
	p.dest_name = String(rp.get("destName", "목적지"))
	p.origin_name = String(rp.get("originName", "출발지"))
	return p


static func synthetic(pts: PackedVector2Array, seed_value: int) -> RoutePlan:
	var p := RoutePlan.new()
	p._set_points(pts)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var names: Array = ROAD_NAMES.duplicate()
	_shuffle(names, rng)

	# 도로 구간 4~5개
	var n_seg := 4 + rng.randi() % 2
	var bounds: Array[float] = [0.0]
	for k in range(1, n_seg):
		bounds.append(p.length * (float(k) / n_seg + rng.randf_range(-0.05, 0.05)))
	bounds.append(p.length)
	for k in range(n_seg):
		p.segments.append({"name": names[k], "from": bounds[k], "to": bounds[k + 1],
				"cruise": rng.randf_range(50.0, 72.0)})

	# 구간 경계마다 회전 안내. 진행 방향 변화로 아이콘과 문구를 정한다
	for k in range(1, n_seg):
		var s: float = bounds[k]
		var d := p.turn_angle(s)
		var icon := "straight"
		var verb := "직진"
		if d > TURN_SLIGHT_DEG:
			icon = "turn_left"
			verb = "좌회전" if d > TURN_SHARP_DEG else "왼쪽 방향"
		elif d < -TURN_SLIGHT_DEG:
			icon = "turn_right"
			verb = "우회전" if d < -TURN_SHARP_DEG else "오른쪽 방향"
		p.maneuvers.append({"s": s, "icon": icon, "verb": verb, "road": names[k]})
	p.maneuvers.append({"s": p.length, "icon": "flag", "verb": "도착", "road": "목적지"})

	# 터널 1~2개 (출발·도착 근처는 피한다)
	var tnames: Array = TUNNEL_NAMES.duplicate()
	_shuffle(tnames, rng)
	var t_count := 1 + rng.randi() % 2
	for k in range(t_count):
		var c := p.length * rng.randf_range(0.22 + k * 0.38, 0.36 + k * 0.38)
		var half := rng.randf_range(220.0, 380.0)
		p.tunnels.append({"from": c - half, "to": c + half, "name": tnames[k]})

	# 신호 대기 2~3곳: 회전 직전 교차로를 우선, 터널 안은 피한다
	var cands: Array[float] = []
	for m in p.maneuvers:
		if m["icon"] != "flag":
			cands.append(float(m["s"]) - 30.0)
	while cands.size() < 4:
		cands.append(p.length * rng.randf_range(0.1, 0.9))
	_shuffle(cands, rng)
	var want_stops := 2 + rng.randi() % 2
	for c2 in cands:
		if p.stops.size() >= want_stops:
			break
		if not p.tunnel_at(c2).is_empty() or c2 < 300.0 or c2 > p.length - 300.0:
			continue
		var close := false
		for st in p.stops:
			if absf(float(st["s"]) - c2) < 600.0:
				close = true
		if not close:
			p.stops.append({"s": c2, "dwell": rng.randf_range(25.0, 45.0)})
	p.stops.sort_custom(func(a, b): return float(a["s"]) < float(b["s"]))
	return p


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _set_points(pts: PackedVector2Array) -> void:
	points = pts
	cum = PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		cum.append(cum[i - 1] + points[i].distance_to(points[i - 1]))
	length = cum[cum.size() - 1]


# ---------------------------------------------------------------- 조회

func progress_of(s: float) -> float:
	return clampf(s / length, 0.0, 1.0) if length > 0.0 else 0.0


## [위치, 진행 방향 단위벡터] (월드 좌표)
func point_at(s: float) -> Array:
	var target := clampf(s, 0.0, length)
	for i in range(1, points.size()):
		if cum[i] >= target:
			var seg := cum[i] - cum[i - 1]
			var t := 0.0 if seg == 0.0 else (target - cum[i - 1]) / seg
			return [points[i - 1].lerp(points[i], t), (points[i] - points[i - 1]).normalized()]
	var n := points.size()
	return [points[n - 1], (points[n - 1] - points[n - 2]).normalized()]


## s에서 look 미터 앞을 향하는 방향(부드러운 진행 방향).
func heading_dir(s: float, look := 150.0) -> Vector2:
	var a: Vector2 = point_at(s)[0]
	var b: Vector2 = point_at(minf(s + look, length))[0]
	if a.distance_to(b) < 1.0:
		return point_at(s)[1]
	return (b - a).normalized()


## s 지점의 회전 각도(도). 양수 = 왼쪽(반시계).
func turn_angle(s: float, span := 150.0) -> float:
	var p0: Vector2 = point_at(maxf(s - span, 0.0))[0]
	var p1: Vector2 = point_at(s)[0]
	var p2: Vector2 = point_at(minf(s + span, length))[0]
	if p0.distance_to(p1) < 1.0 or p1.distance_to(p2) < 1.0:
		return 0.0
	return rad_to_deg((p1 - p0).angle_to(p2 - p1))


func segment_at(s: float) -> Dictionary:
	for seg in segments:
		if s < float(seg["to"]):
			return seg
	return segments[segments.size() - 1]


func tunnel_at(s: float) -> Dictionary:
	for t in tunnels:
		if s >= float(t["from"]) and s <= float(t["to"]):
			return t
	return {}


## s 이후의 회전 안내 count개. 각 항목에 distance(m)를 붙여 돌려준다.
func upcoming(s: float, count := 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in maneuvers:
		if float(m["s"]) > s + 1.0:
			var d := m.duplicate()
			d["distance"] = float(m["s"]) - s
			out.append(d)
			if out.size() >= count:
				break
	return out


## s 이후 가장 가까운 신호 대기 지점. 없으면 빈 Dictionary.
func next_stop(s: float) -> Dictionary:
	for st in stops:
		if float(st["s"]) >= s - 0.5:
			return st
	return {}
