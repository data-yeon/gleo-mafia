## 왼쪽 자율주행 시각화 패널(3D). 내 차가 퍼즐 팩 가상 도시의 A* 경로를 실제로 달리고, 카메라가 뒤에서 따라간다.
## 교차로 회전, 다리, 지하차도가 내비 지도와 같은 자리에서 나온다.
## - 도시(AdasWorld): 도로·차선·보도·가로수·가로등·신호등·횡단보도
## - 움직이는 것(AdasTraffic): 주변 차(차종 7가지), 마주 오는 차, 교차 차량, 보행자, 출동 경찰차
## - 사건 장소 랜드마크(RoadsideLandmarks): 9곳 건물, 수락 뒤 번호 표지
## 밝은 배경에 회색 도로의 미니멀 톤. 일반 건물은 넣지 않는다.
class_name AdasView
extends SubViewportContainer

const LANE_W := AdasWorld.LANE_W
const CAM_OFFSET := Vector3(0, 10.0, 14.0)
const CAM_PITCH_DEG := -32.0
const TUNNEL_BG := Color("4f5866")
const PATH_AHEAD := 34.0
# 빛 세기: Blender 미리보기(model_preview)와 같게. 이 값이면 그림자 안 받는 바닥이 제 색(알베도)에 가깝다
const AMBIENT := 0.3
const SUN := 0.18
const GROUND := Color("e2e5e9")            # 화면에서 PleosTheme.ADAS_BG 정도

var speed_kmh := 0.0
var route_s := 0.0                # 경로 위 내 차 위치(m)
var dwelling := false             # 신호 대기 중
var time_scale := 3.0             # 게임 시간 배속(주변 차·보행자 움직임)
var curve := 0.0                  # 예전 호환용(쓰지 않음)
var stop_distance := -1.0         # 예전 호환용(쓰지 않음)

var city: AdasWorld
var traffic: AdasTraffic
var _landmarks: RoadsideLandmarks
var _vp: SubViewport
var _root: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D
var _ego: Node3D
var _ground: MeshInstance3D
var _path_mesh: ImmediateMesh
var _ready_world := false
var _lat := 0.0
var _last_s := -1.0
var _yaw := 0.0
var _yaw_ready := false
var _tunnel_k := 0.0
var _tunnel_target := 0.0
var _labels_wanted := false
var _seed := 7


func _ready() -> void:
	stretch = true
	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.own_world_3d = true
	add_child(_vp)
	_root = Node3D.new()
	_vp.add_child(_root)
	_build()


func _build() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = PleosTheme.ADAS_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = AMBIENT
	e.fog_enabled = true
	e.fog_light_color = PleosTheme.ADAS_BG
	e.fog_density = 0.0055
	env.environment = e
	_env = e
	_root.add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-62, 28, 0)
	_sun.light_energy = SUN
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 110.0
	_sun.shadow_opacity = 0.55
	_root.add_child(_sun)

	_cam = Camera3D.new()
	# 패널이 세로로 길어서 가로 시야를 기준으로 맞춘다
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 56
	_cam.near = 0.8
	_cam.far = 240
	_root.add_child(_cam)

	# 끝없는 바닥(내 차를 따라다닌다)
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	_ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = GROUND
	gm.roughness = 1.0
	gm.metallic_specular = 0.0
	_ground.material_override = gm
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(_ground)

	city = AdasWorld.new()
	_root.add_child(city)
	traffic = AdasTraffic.new()
	_root.add_child(traffic)
	_landmarks = RoadsideLandmarks.new()
	_root.add_child(_landmarks)

	# 파란 주행 경로 띠 (앞 34m, 빨간불이면 정지선까지)
	_path_mesh = ImmediateMesh.new()
	var path := MeshInstance3D.new()
	path.mesh = _path_mesh
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = PleosTheme.ADAS_PATH
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	path.material_override = pmat
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(path)

	_ego = AdasAssets.instance("ego_car")
	if _ego == null:
		_ego = AdasAssets.box_vehicle(Color("fbfcfd"))
	_root.add_child(_ego)


## 퍼즐 팩(v3)과 경로 계획으로 도시를 만들고 주변 차·보행자·랜드마크를 놓는다. ego_s는 시작 위치(m).
func setup(data: Dictionary, plan: RoutePlan, ego_s: float) -> void:
	route_s = ego_s
	_seed = int(data.get("seed", 7))
	city.build(data, plan)
	traffic.setup(city, ego_s, _seed)
	_landmarks.build(data.get("places", []), city)
	_landmarks.labels_on = _labels_wanted
	_last_s = -1.0
	_yaw_ready = false
	_ready_world = true


## 터널 안이면 화면을 어둡게 한다(벽은 도시에 실제 위치로 서 있다).
func set_tunnel(on: bool) -> void:
	_tunnel_target = 1.0 if on else 0.0


## 사건을 수락하면 장소 번호 표지를 켠다. (건물은 처음부터 서 있다)
func set_landmarks(_places: Array, _route_length: float) -> void:
	_labels_wanted = true
	_landmarks.labels_on = true


## 잠복 찬스 중인 장소 id(-1이면 없음). 그 건물의 표지와 바닥 링을 강조한다.
func set_landmark_hot(id: int) -> void:
	_landmarks.hot_id = id


## 출동 연출: 경찰차가 옆 차로로 내 차를 추월해 앞으로 나간다(경광등 깜빡임).
func play_police_pass() -> void:
	if _ready_world:
		traffic.play_police(route_s)


func _process(delta: float) -> void:
	if not _ready_world:
		return
	var s := route_s
	# 장면 건너뛰기·빨리 감기로 크게 옮겨졌으면 주변 차·보행자를 새 위치에 다시 놓는다
	if _last_s >= 0.0 and absf(s - _last_s) > 120.0:
		traffic.setup(city, s, _seed)
	# 내 차: 편도 3차로면 가운데 차로, 1차로면 그 차로. 경유지 200m 앞부터는 바깥 차로로 붙어 선다.
	# 차로가 바뀌면 이동 거리에 맞춰 옮겨 간다.
	var lanes := city.lanes_at(s)
	var lane := 2 if lanes >= 3 else 1
	var to_wp := city.plan.waypoint_s - s
	if city.plan.waypoint_s > 0.0 and to_wp < 200.0 and to_wp > -30.0:
		lane = lanes
	traffic.ego_lane = lane
	var target_lat := (float(lane) - 0.5) * LANE_W
	if _last_s < 0.0 or absf(s - _last_s) > 80.0:
		_lat = target_lat
	else:
		_lat = lerpf(_lat, target_lat, clampf(absf(s - _last_s) / 30.0, 0.0, 1.0))
	_last_s = s
	var xf := city.xform(s, _lat)
	_ego.transform = xf
	# 카메라: 내 차 뒤 위에서, 진행 방향을 부드럽게 따라 돈다
	var yaw := xf.basis.get_euler().y
	if not _yaw_ready:
		_yaw = yaw
		_yaw_ready = true
	else:
		_yaw = lerp_angle(_yaw, yaw, clampf(delta * 3.0, 0.0, 1.0))
	_cam.position = xf.origin + Basis(Vector3.UP, _yaw) * CAM_OFFSET
	_cam.rotation = Vector3(deg_to_rad(CAM_PITCH_DEG), _yaw, 0.0)
	_ground.position = Vector3(xf.origin.x, -0.06, xf.origin.z)

	var red := _update_signals(s)
	traffic.update(s, speed_kmh, red, delta * time_scale, delta)
	_update_path(s, red)
	_landmarks.update(xf.origin, delta)

	# 터널 전환
	_tunnel_k = move_toward(_tunnel_k, _tunnel_target, delta * 1.5)
	_env.background_color = PleosTheme.ADAS_BG.lerp(TUNNEL_BG, _tunnel_k)
	_env.fog_light_color = _env.background_color
	_env.ambient_light_energy = lerpf(AMBIENT, AMBIENT * 0.6, _tunnel_k)
	_sun.light_energy = lerpf(SUN, SUN * 0.2, _tunnel_k)
	(_ground.material_override as StandardMaterial3D).albedo_color = GROUND.lerp(TUNNEL_BG, _tunnel_k)
	var outside := _tunnel_k < 0.5
	for p in city.props:
		p.visible = outside
	_landmarks.visible = outside


## 신호 대기 지점이 있는 교차로: 그 지점을 지나기 전과 대기 중에는 빨간불, 출발하면 초록불.
## 우리 앞 가장 가까운 빨간불 교차로를 돌려준다(주변 차 줄서기, 교차 차량, 보행자 횡단에 쓴다).
func _update_signals(s: float) -> Dictionary:
	var red := {}
	for sig in city.signals:
		var st := int(sig["stop"])
		if st < 0:
			continue
		var stop_s := float(city.plan.stops[st]["s"])
		var is_red := s < stop_s - 0.3 or (dwelling and absf(s - stop_s) < 1.0)
		city.set_signal_green(sig, not is_red)
		if is_red and red.is_empty() and float(sig["s_node"]) - s < 280.0:
			red = sig
	return red


func _update_path(s: float, red: Dictionary) -> void:
	_path_mesh.clear_surfaces()
	var s0 := s + 2.6
	var s1 := minf(s + PATH_AHEAD, city.plan.length)
	if not red.is_empty():
		s1 = minf(s1, float(red["line_s"]) - 0.3)
	if s1 - s0 < 1.0:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := 16
	for k in range(n + 1):
		var ss := lerpf(s0, s1, float(k) / n)
		var d := city.heading(ss)
		var right := Vector2(d.y, -d.x)
		var c := city.place(ss, _lat)
		_path_mesh.surface_add_vertex(AdasWorld.v3(c - right * 1.1, 0.045))
		_path_mesh.surface_add_vertex(AdasWorld.v3(c + right * 1.1, 0.045))
	_path_mesh.surface_end()
