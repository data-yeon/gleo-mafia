## Pleos 차량 화면 셸: 상태바 / (왼쪽 자율주행 패널 | 내비 지도 + 카드) / 앱 독 / Gleo 음성 바.
## 게임(사건 모드)은 이 화면 위에 얹는다(E 단계). 지금은 주행 화면 재현(C) + 주행 시뮬레이션(D).
##
## 실행 인자 (godot 인자 뒤에 -- 를 붙인다):
##   --puzzle=phishing-1000   경로를 가져올 퍼즐 팩 사건 (경로 데이터가 생기기 전 임시)
##   --speed=3                배속 (1, 3, 10, 0=멈춤). 기본 3배속
##   --start=0.18             출발 진행률 (--progress와 같다)
##   --seek=stop|tunnel|arrive  해당 장면 직전으로 건너뛰기 (스크린샷 확인용)
##   --simulate=60            시작 전에 게임 시간 N초를 미리 진행
##   --view=overview          지도 보기(follow | overview)
##   --showcase               사건 모드 카드(경고, 장소 카드, 장소 목록)까지 한 화면에 보여주기
##   --screenshot=/path.png   잠시 뒤 화면을 저장하고 종료 (--autoplay가 있으면 그 뒤에)
##   --no-case                사건 제안을 하지 않음 (주행만)
##   --autoplay=offer,accept,start,t2,ff0.3,s,r5,w3   자동 실행 (아래 _exec 참고)
##
## 단축키: 1=실시간, 2=3배속, 3=10배속, Space=일시정지, R=처음부터
##         C=사건 제안, Y=수락·시작, N=나중에, T=선택한 곳 탐문, S=잠복(경고 카드), X=선택한 곳 출동,
##         H=힌트, G=정리
class_name PleosShell
extends Control

const PUZZLE_DIR := "res://data/puzzles/"
const TRIP_MINUTES := 20.0
const UI_HZ := 8.0
var DEST_NAME := "해커톤 행사장"

var status_bar: PleosStatusBar
var dock: PleosDock
var adas: AdasView
var nav_map: NavMap
var map3d: MapView3D                   # 기울인 지도(하이브리드). --flat-map이면 없음(평평한 지도)
var coach: CoachMark                   # 튜토리얼 코치 마크·처음 겪는 규칙 팁(화면 맨 위)
var tap_fx: TapFx                      # 자동 실행(click=…)이 누른 곳 표시(시연 영상용)
var overlay: Control
var tbt: NavCards.TbtCard
var eta: NavCards.EtaCard
var rail: NavCards.SideRail
var alert: NavCards.AlertCard
var poi: PoiCard
var case_card: CaseCard
var suspect: SuspectCard
var call_pill: CallPill
var inset: SceneInset
var edge_map: EdgeFx
var edge_left: EdgeFx
var action_card: ActionCard
var _glow: TextureRect                # Gleo가 말할 때 지도 위쪽 가장자리가 빛난다
var _glow_t := 0.0
var gleo: GleoBar
var sfx: Sfx
var args := {}
var puzzle: Dictionary = {}
var plan: RoutePlan
var sim: VehicleSim
var director: CaseDirector
var result_card: ResultCard
var result_dim: ColorRect
var _puzzle_id := ""
var case_mode := false                # 사건 모드면 목록·도착 칩·경고·장소 카드는 사건 쪽이 관리한다
var _route_pts := PackedVector2Array()
var _start_unix := 0.0
var _ui_timer := 0.0
var _state: Dictionary = {}
var _resume_playback := 3.0
var _ff_prev := -1.0                  # 도착까지 빨리 감기 전 배속
static var _next_puzzle_id := ""      # [다음 사건]으로 다시 열 때 쓸 사건 (장면을 다시 불러도 남는다)


func _ready() -> void:
	args = _parse_args()
	Tutorial.persist = not args.has("autoplay")       # 자동 실행·녹화는 튜토리얼 통과·팁을 저장하지 않는다
	theme = PleosTheme.build()
	_build()
	var pid := String(args.get("puzzle", ""))
	if _next_puzzle_id != "":
		pid = _next_puzzle_id
		_next_puzzle_id = ""
	elif pid == "" and _wants_tutorial():
		pid = tutorial_id()
	_load_puzzle(pid)
	_start_drive()
	if args.has("showcase"):
		case_mode = true
		director.auto_offer = false
		sim.playback = 0.0
		_show_case_showcase()
	call_deferred("_layout")
	_run_autoplay_and_screenshot()
	_check_vehicle_door()


# Pleos 차량 SDK 연결 확인: 앞좌석 왼쪽 문 위치를 한 번 읽어 로그에 남긴다 (안드로이드 빌드에서만 동작)
func _check_vehicle_door() -> void:
	if not Engine.has_singleton("PleosVehicle"):
		print("[PleosVehicle] plugin not available (desktop run or plugin missing)")
		return
	var pleos = Engine.get_singleton("PleosVehicle")
	pleos.door_position_result.connect(func(pos): print("[PleosVehicle] door position: %d" % pos))
	pleos.door_position_failed.connect(func(msg): print("[PleosVehicle] door query failed: %s" % msg))
	pleos.initializeVehicle()
	# 차량 서비스 연결은 비동기라서, 첫 조회 전에 잠깐 기다린다
	await get_tree().create_timer(3.0).timeout
	pleos.getCurrentDoorPosition()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		if eq == -1:
			out[s] = true
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


# ---------------------------------------------------------------- 레이아웃

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = PleosTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	status_bar = PleosStatusBar.new()
	root.add_child(status_bar)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# 왼쪽 30%: 자율주행 패널 (둥근 모서리 안쪽 여백)
	var left := MarginContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 3.0
	for side in ["margin_left", "margin_top", "margin_bottom"]:
		left.add_theme_constant_override(side, 16)
	left.add_theme_constant_override("margin_right", 8)
	body.add_child(left)
	var left_panel := PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.ADAS_BG, 28, 0))
	left_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	left.add_child(left_panel)
	adas = AdasView.new()
	left_panel.add_child(adas)
	edge_left = EdgeFx.new()
	left_panel.add_child(edge_left)

	# 오른쪽 70%: 지도 + 카드
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 7.0
	for side in ["margin_right", "margin_top", "margin_bottom"]:
		right.add_theme_constant_override(side, 16)
	right.add_theme_constant_override("margin_left", 8)
	body.add_child(right)
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel", PleosTheme.box(PleosTheme.MAP_LAND, 28, 0))
	map_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	right.add_child(map_panel)
	var map_stack := Control.new()
	map_stack.resized.connect(_layout)
	map_panel.add_child(map_stack)
	nav_map = NavMap.new()
	if args.has("flat-map"):
		nav_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		map_stack.add_child(nav_map)
	else:
		# 기울인 지도: NavMap은 텍스처로 그리고, 3D 판·랜드마크·블록 건물 위에서 본다
		map3d = MapView3D.new(nav_map)
		map3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		map_stack.add_child(map3d)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_stack.add_child(overlay)

	tbt = NavCards.TbtCard.new()
	eta = NavCards.EtaCard.new()
	rail = NavCards.SideRail.new()
	alert = NavCards.AlertCard.new()
	poi = PoiCard.new()
	case_card = CaseCard.new()
	suspect = SuspectCard.new()
	action_card = ActionCard.new()
	call_pill = CallPill.new()
	inset = SceneInset.new()
	gleo = GleoBar.new()
	# Gleo 빛: 지도 위쪽 가장자리의 보라·파랑 띠 (카드보다 뒤)
	_glow = TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.49, 0.30, 1.0, 0.55))
	grad.set_color(1, Color(0.18, 0.42, 1.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 64
	_glow.texture = gt
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.anchor_right = 1.0
	_glow.offset_bottom = 56.0
	_glow.modulate.a = 0.0
	overlay.add_child(_glow)
	edge_map = EdgeFx.new()
	overlay.add_child(edge_map)
	gleo.spoke.connect(func(): _glow_t = 1.6)
	for c in [tbt, eta, rail, alert, poi, case_card, suspect, action_card, call_pill, inset, gleo]:
		overlay.add_child(c)
		(c as Control).resized.connect(_layout)
		(c as Control).minimum_size_changed.connect(_queue_layout)
	alert.visibility_changed.connect(_queue_layout)
	poi.visibility_changed.connect(_queue_layout)
	case_card.visibility_changed.connect(_queue_layout)
	suspect.visibility_changed.connect(_queue_layout)
	action_card.visibility_changed.connect(_queue_layout)
	inset.visibility_changed.connect(_queue_layout)
	alert.visible = false
	poi.visible = false
	case_card.visible = false
	suspect.visible = false
	action_card.visible = false
	result_dim = ColorRect.new()
	result_dim.color = Color(0.07, 0.1, 0.16, 0.28)
	result_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_dim.visible = false
	overlay.add_child(result_dim)
	result_card = ResultCard.new()
	result_card.visible = false
	result_card.resized.connect(_layout)
	result_dim.add_child(result_card)

	dock = PleosDock.new()
	root.add_child(dock)
	coach = CoachMark.new()
	add_child(coach)
	tap_fx = TapFx.new()
	add_child(tap_fx)


var _layout_queued := false


func _queue_layout() -> void:
	if not _layout_queued:
		_layout_queued = true
		_layout.call_deferred()


## 카드 위치: TBT 왼쪽 위, 경고는 TBT 아래, ETA 왼쪽 아래, 목록 오른쪽 위,
## 장소 카드 목록 왼쪽, 음성 바 아래쪽 가운데.
func _layout() -> void:
	_layout_queued = false
	if overlay == null:
		return
	var w := overlay.size.x
	var h := overlay.size.y
	var m := 24.0
	for c in [tbt, eta, rail, alert, poi, case_card, suspect, action_card, call_pill, gleo]:
		(c as Control).reset_size()
	tbt.position = Vector2(m, m)
	eta.position = Vector2(m, h - eta.size.y - m)
	rail.position = Vector2(w - rail.size.x - m, m)
	alert.position = Vector2(m, tbt.position.y + tbt.size.y + 14.0)     # TBT 카드 바로 아래 (내비 경고 위치)
	alert.size.x = tbt.size.x
	poi.position = Vector2(w - poi.size.x - m, m)                      # 오른쪽 목록 자리 (열리면 목록을 덮는다)
	case_card.position = Vector2(w - case_card.size.x - m, m)          # 사건 제안·브리핑·노트도 같은 자리
	suspect.position = Vector2(w - suspect.size.x - m, m)              # 용의 장소 검색(Gleo 결과 카드)
	action_card.position = Vector2(w - action_card.size.x - m, m)      # 고른 장소의 행동 옵션
	rail.visible = not (poi.visible or case_card.visible or suspect.visible or action_card.visible)
	# 음성 바: 도착 카드 오른쪽, 목록과 겹치지 않게
	var gx := eta.position.x + eta.size.x + 16.0
	gleo.position = Vector2(gx, h - gleo.size.y - m)
	# 전체 보기 지도는 카드가 가리지 않는 가운데 영역에 맞춘다
	# 경고 카드가 떠 있을 때만 그 아래까지 비운다. 지도는 새 여백으로 부드럽게 옮겨 간다(NavMap).
	var top := tbt.position.y + tbt.size.y + 12.0
	if alert.visible:
		top = alert.position.y + alert.size.y + 12.0
	var right_w := maxf(maxf(rail.size.x, poi.size.x), maxf(case_card.size.x, maxf(suspect.size.x, action_card.size.x)))
	# 회신 전화 알약: 음성 바 바로 위(통화 화면 + 자막이 한 자리에)
	call_pill.position = Vector2(gleo.position.x + 24.0, gleo.position.y - call_pill.size.y - 12.0)
	# 현장 3D 확대도: 크게(출동·결말)는 지도 가운데, 중간(회신 전화)은 왼쪽 카드와 오른쪽 카드 사이 빈 곳 가운데
	inset.reset_size()
	if inset.big:
		inset.position = Vector2((w - inset.size.x) / 2.0, maxf(m, (h - inset.size.y) / 2.0 - 40.0))
	else:
		var fx0 := tbt.position.x + tbt.size.x + 16.0
		var fx1 := w - right_w - m * 2.0
		var fy0 := tbt.position.y + tbt.size.y + 16.0
		var fy1 := call_pill.position.y - 12.0
		inset.position = Vector2(clampf((fx0 + fx1 - inset.size.x) / 2.0, m, w - inset.size.x - m),
				clampf((fy0 + fy1 - inset.size.y) / 2.0, m, h - inset.size.y - m))
	nav_map.view_insets = Vector4(m, top, right_w + m * 2.0,
			h - minf(eta.position.y, gleo.position.y) + 12.0)
	if result_card != null:
		result_card.reset_size()
		result_card.position = (Vector2(w, h) - result_card.size) / 2.0 - Vector2(0, 40)


# ---------------------------------------------------------------- 내용

func _load_puzzle(id: String) -> void:
	if id == "":
		var idx = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + "index.json"))
		if typeof(idx) == TYPE_ARRAY and not idx.is_empty():
			id = String(idx[0]["id"])
			for e in idx:
				if String(e["preset"]) == "phishing":
					id = String(e["id"])
					break
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + id + ".json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("퍼즐을 읽지 못했어요: " + id)
		return
	_puzzle_id = id
	puzzle = parsed
	print("사건 팩: ", id)
	_route_pts = PackedVector2Array()
	for p in puzzle["route"]:
		_route_pts.append(Vector2(float(p[0]), float(p[1])))
	# 팩 v3: 퍼즐 공장이 만든 가상 도시를 그린다 (없으면 가짜 도시)
	var rp: Dictionary = puzzle.get("routePlan", {})
	nav_map.set_city(puzzle.get("city", {}), rp.get("nodes", []), int(puzzle.get("seed", 7)))
	nav_map.set_route(_route_pts, int(puzzle.get("seed", 7)))


func _route_length_m() -> float:
	var r: Array = puzzle.get("route", [])
	var total := 0.0
	for i in range(1, r.size()):
		total += Vector2(float(r[i][0]), float(r[i][1])).distance_to(Vector2(float(r[i - 1][0]), float(r[i - 1][1])))
	return total


## 지금으로부터 offset_s(게임 초) 뒤 시각 "9:13" (사건 이야기의 인출 시각 등)
func clock_hm(offset_s := 0.0) -> String:
	var bias: float = Time.get_time_zone_from_system()["bias"]
	var d := Time.get_datetime_dict_from_unix_time(int(_start_unix + sim.game_time + offset_s + bias * 60.0))
	return "%d:%02d" % [int(d["hour"]), int(d["minute"])]


func _clock_text(unix: float) -> String:
	var bias: float = Time.get_time_zone_from_system()["bias"]
	var d := Time.get_datetime_dict_from_unix_time(int(unix + bias * 60.0))
	var h := int(d["hour"])
	return "%s %d:%02d" % ["오전" if h < 12 else "오후", 12 if h % 12 == 0 else h % 12, int(d["minute"])]


func _dist_text(m: float) -> String:
	if m >= 1000.0:
		return "%.1fkm" % (m / 1000.0)
	return "%dm" % int(round(m / 10.0) * 10)


# ---------------------------------------------------------------- 주행 (D 단계)

func _start_drive() -> void:
	plan = RoutePlan.from_pack(puzzle)
	DEST_NAME = plan.dest_name if plan.dest_name != "목적지" else DEST_NAME
	sim = VehicleSim.new()
	add_child(sim)
	var start := float(args.get("start", args.get("progress", 0.0)))
	sim.setup(plan, TRIP_MINUTES, start)
	adas.setup(puzzle, plan, sim.s)
	sim.playback = float(args.get("speed", 3.0))
	_resume_playback = sim.playback if sim.playback > 0.0 else 3.0
	sim.ticked.connect(_on_tick)
	sim.tunnel_entered.connect(_on_tunnel_entered)
	sim.tunnel_exited.connect(_on_tunnel_exited)
	sim.stopped.connect(_on_stopped)
	sim.resumed.connect(_on_resumed)
	sim.arrived.connect(_on_arrived)
	status_bar.playback_pressed.connect(_cycle_playback)
	nav_map.view_mode = String(args.get("view", "follow"))
	_apply_plan_to_map()
	_start_unix = Time.get_unix_time_from_system() - sim.game_time
	status_bar.set_autonomous(true)
	gleo.show_idle()
	sfx = Sfx.new()
	add_child(sfx)
	director = CaseDirector.new()
	add_child(director)
	director.setup({"shell": self, "sfx": sfx, "nav_map": nav_map, "rail": rail, "eta": eta, "alert": alert, "poi": poi,
			"case_card": case_card, "suspect": suspect, "action_card": action_card, "call_pill": call_pill,
			"edge_map": edge_map, "edge_left": edge_left, "inset": inset, "map3d": map3d, "coach": coach,
			"gleo": gleo, "adas": adas, "sim": sim, "plan": plan, "result_card": result_card, "tbt": tbt,
			"result_dim": result_dim}, PUZZLE_DIR + _puzzle_id + ".json")
	director.auto_offer = not args.has("no-case")
	director.tips_enabled = String(args.get("mode", "")) != "demo" and not args.has("autoplay") \
			and not args.has("screenshot")
	if Tutorial.is_tutorial_pack(puzzle):
		director.offer_after = 6.0
	if args.has("seek"):
		_seek(String(args["seek"]))
	var pre := float(args.get("simulate", 0.0))
	while pre > 0.0 and not sim.finished:
		sim.step(0.25)
		pre -= 0.25
	if sim.is_stopped():
		_on_stopped({})
	if not sim.in_tunnel().is_empty():
		_on_tunnel_entered(sim.in_tunnel())
	sim.emit_state()
	if sim.finished:
		_on_arrived()
	_refresh_drive_ui()


## 사건이 끝난 뒤 도착 장면까지 빨리 간다(데모 마무리). on=false면 원래 배속으로.
## 브리핑을 읽는 동안은 1배속으로 늦춘다(3배속이면 첫 신호·현장 확인을 놓친다). 멈춰 있으면 그대로.
var _slow_prev := -1.0


func demo_slow(on: bool) -> void:
	if on and sim.playback > 1.0 and _slow_prev < 0.0:
		_slow_prev = sim.playback
		_set_playback(1.0)
	elif not on and _slow_prev >= 0.0:
		if sim.playback == 1.0:
			_set_playback(_slow_prev)
		_slow_prev = -1.0


func demo_fast_forward(on: bool) -> void:
	if on:
		_ff_prev = sim.playback
		_set_playback(10.0)
	elif _ff_prev >= 0.0:
		_set_playback(_ff_prev if _ff_prev > 0.0 else 3.0)
		_ff_prev = -1.0


## [다음 사건]: 팩 목록에서 다음 사건으로 처음부터 다시 연다.
## 튜토리얼을 열지: --tutorial이면 늘, 아니면 처음 켰을 때(통과 전)만.
## 발표(--mode=demo), 사건 지정(--puzzle), 자동 실행·스크린샷, 헤드리스(테스트)에서는 열지 않는다.
func _wants_tutorial() -> bool:
	if args.has("tutorial"):
		return true
	if String(args.get("mode", "")) == "demo" or args.has("autoplay") or args.has("screenshot") \
			or args.has("showcase") or DisplayServer.get_name() == "headless":
		return false
	return not Tutorial.done() and tutorial_id() != ""


static func tutorial_id() -> String:
	for f in DirAccess.get_files_at(PUZZLE_DIR):
		if f.begins_with("tutorial-") and f.ends_with(".json"):
			return f.trim_suffix(".json")
	return ""


## 기본 사건(발표 데모 판): 팩 목록의 첫 보이스피싱 사건
static func default_case_id() -> String:
	var idx = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + "index.json"))
	if typeof(idx) != TYPE_ARRAY or idx.is_empty():
		return ""
	for e in idx:
		if String(e["preset"]) == "phishing":
			return String(e["id"])
	return String(idx[0]["id"])


func start_case(id: String) -> void:
	_next_puzzle_id = id
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- 코치 마크가 가리킬 곳(화면 좌표)

func control_rect(c: Control) -> Rect2:
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()


## 장소 핀(기울인 지도면 랜드마크 + 배지)
func pin_rect(id: int) -> Rect2:
	if director.case == null:
		return Rect2()
	if map3d != null:
		var pj: Dictionary = map3d._project(id)
		if not bool(pj.get("ok", false)):
			return Rect2()
		var xf := map3d.get_global_transform()
		var top: Vector2 = xf * (pj["top"] as Vector2)
		var base: Vector2 = xf * (pj["base"] as Vector2)
		return Rect2(top, Vector2.ZERO).expand(base).grow_individual(30, 26, 30, 12)
	var p := nav_map.get_global_transform() * nav_map.to_screen(director.overlay.place_world(id))
	return Rect2(p - Vector2(34, 34), Vector2(68, 68))


func pair_rect(a: int, b: int) -> Rect2:
	var ra := pin_rect(a)
	var rb := pin_rect(b)
	if ra.size == Vector2.ZERO:
		return rb
	if rb.size == Vector2.ZERO:
		return ra
	return ra.merge(rb)


func start_next_case() -> void:
	var idx = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + "index.json"))
	if typeof(idx) == TYPE_ARRAY and not idx.is_empty():
		var at := 0
		for i in range(idx.size()):
			if String(idx[i]["id"]) == _puzzle_id:
				at = i
		_next_puzzle_id = String(idx[(at + 1) % idx.size()]["id"])
	get_tree().reload_current_scene()


## 경로 계획의 터널·회전·경유지·목적지 표시를 지도에 넣는다(처음과 재탐색 뒤).
func _apply_plan_to_map() -> void:
	nav_map.tunnel_spans.clear()
	for t in plan.tunnels:
		nav_map.tunnel_spans.append(Vector2(plan.progress_of(float(t["from"])), plan.progress_of(float(t["to"]))))
	nav_map.turn_marks.clear()
	for m in plan.maneuvers:
		var icon := String(m["icon"])
		if icon.begins_with("turn"):
			nav_map.turn_marks.append(Vector2(plan.progress_of(float(m["s"])), -1.0 if icon == "turn_left" else 1.0))
	nav_map.waypoint_marks.clear()
	for m2 in plan.maneuvers:
		if bool(m2.get("waypoint", false)):
			nav_map.waypoint_marks.append({"p": plan.progress_of(float(m2["s"])), "label": String(m2["road"])})
	nav_map.dest_name = DEST_NAME


## 경유지 재탐색 결과를 적용한다: 주행 시뮬레이션, 지도(재탐색 연출), 사건 진행, 3D 도시를 새 경로로.
## 지금 위치 s는 그대로 이어진다(갈라지는 교차로 앞까지 옛 경로와 같다).
func apply_reroute(new_plan: RoutePlan) -> void:
	plan = new_plan
	sim.replan(new_plan)
	director.plan = new_plan
	_route_pts = new_plan.points
	var rp: Dictionary = puzzle.get("routePlan", {})
	if puzzle.has("city") and rp.has("nodes"):
		nav_map.set_city(puzzle["city"], new_plan.nodes, int(puzzle.get("seed", 7)))
	nav_map.reroute(new_plan.points)
	_apply_plan_to_map()
	adas.setup(puzzle, new_plan, sim.s)
	sim.emit_state()
	_refresh_drive_ui()


## 스크린샷 확인용: 장면 바로 앞으로 옮긴다.
func _seek(kind: String) -> void:
	var target := 0.0
	match kind:
		"stop":
			if not plan.stops.is_empty():
				target = float(plan.stops[0]["s"]) - 60.0
		"tunnel":
			if not plan.tunnels.is_empty():
				target = float(plan.tunnels[0]["from"]) + 80.0
		"arrive":
			target = plan.length - 150.0
	sim.setup(plan, TRIP_MINUTES, clampf(target / plan.length, 0.0, 1.0))
	_start_unix = Time.get_unix_time_from_system() - sim.game_time
	if kind == "stop":
		var guard := 0
		while not sim.is_stopped() and guard < 400:
			sim.step(0.25)
			guard += 1
		for _i in range(20):
			sim.step(0.25)
	elif kind == "arrive":
		while not sim.finished:
			sim.step(0.25)


func _on_tick(state: Dictionary) -> void:
	_state = state
	nav_map.set_progress(float(state["progress"]))
	nav_map.heading_target = plan.heading_dir(float(state["s"]))
	adas.speed_kmh = float(state["speed_kmh"])
	adas.route_s = float(state["s"])
	adas.dwelling = sim.is_stopped()
	adas.time_scale = sim.playback


func _process(delta: float) -> void:
	_glow_t = maxf(_glow_t - delta, 0.0)
	_glow.modulate.a = clampf(_glow_t / 0.8, 0.0, 1.0)
	_ui_timer += delta
	if _ui_timer >= 1.0 / UI_HZ:
		_ui_timer = 0.0
		_refresh_drive_ui()


## 카드·상태바 갱신(초당 8번). 지도와 3D 패널은 매 프레임 _on_tick에서 갱신한다.
func _refresh_drive_ui() -> void:
	if sim == null or _state.is_empty():
		return
	var s := float(_state["s"])
	var eta_s := float(_state["eta_s"])
	var now_unix := _start_unix + float(_state["game_time"])
	status_bar.set_speed(float(_state["speed_kmh"]))
	status_bar.set_clock_unix(now_unix)
	status_bar.set_playback_label(_playback_text())
	# 지도: 아직 안 지난 신호 위치
	var stops: Array[float] = []
	for st in plan.stops:
		if float(st["s"]) > s - 5.0:
			stops.append(plan.progress_of(float(st["s"])))
	nav_map.stop_points = stops

	var ups := plan.upcoming(s, 5)
	if sim.finished:
		tbt.set_arrived(DEST_NAME)
	elif not ups.is_empty():
		var m0: Dictionary = ups[0]
		var road := "목적지" if m0["icon"] == "flag" else "%s · %s 방면" % [m0["verb"], m0["road"]]
		if bool(m0.get("waypoint", false)):
			road = "경유지 · %s" % m0["road"]
		if ups.size() > 1:
			var m1: Dictionary = ups[1]
			tbt.set_maneuver(m0["icon"], float(m0["distance"]), road, m1["icon"],
					"%s %s" % [_dist_text(float(m1["distance"])), m1["road"]])
		else:
			tbt.set_maneuver(m0["icon"], float(m0["distance"]), road)
		var tun := sim.in_tunnel()
		if not tun.is_empty():
			tbt.set_note("터널 구간 · %s · 남은 %s" % [tun["name"], _dist_text(float(tun["to"]) - s)], PleosTheme.TEXT_2)
		elif sim.is_stopped():
			if bool(sim.current_stop().get("waypoint", false)):
				tbt.set_note("경유지 정차 중 · %d초" % ceili(sim.dwell_left), NavMap.COL_WAYPOINT)
			else:
				tbt.set_note("신호 대기 중 · %d초" % ceili(sim.dwell_left), PleosTheme.DANGER)
		else:
			var nst := plan.next_stop(s)
			if not nst.is_empty() and float(nst["s"]) - s < 400.0:
				if bool(nst.get("waypoint", false)):
					tbt.set_note("%s 앞 경유지 · 잠깐 정차" % _dist_text(float(nst["s"]) - s), NavMap.COL_WAYPOINT)
				else:
					tbt.set_note("%s 앞 신호 · 정차 예정" % _dist_text(float(nst["s"]) - s), PleosTheme.WARN)
			else:
				tbt.set_note("")
	if sim.finished:
		eta.set_arrived(_clock_text(now_unix), "목적지 · " + DEST_NAME)
	else:
		eta.set_eta(_clock_text(now_unix + eta_s), (plan.length - s) / 1000.0, ceili(eta_s / 60.0),
				"목적지 · " + DEST_NAME)
		if plan.waypoint_s > s + 1.0:
			eta.set_waypoint("경유 %s · %s" % [_clock_text(now_unix + sim.eta_to(plan.waypoint_s)),
					_dist_text(plan.waypoint_s - s)])
		else:
			eta.set_waypoint("")
	if not case_mode and not director.owns_ui():
		var items := []
		for m in ups.slice(0, 4):
			items.append({"icon": m["icon"], "title": "%s · %s" % [_dist_text(float(m["distance"])), m["road"]],
					"sub": m["verb"]})
		if sim.finished:
			items = [{"icon": "flag", "title": "목적지 도착", "sub": DEST_NAME}]
		rail.set_items("다음 안내", items)


func _playback_text() -> String:
	if sim.playback <= 0.0:
		return "❚❚ 일시정지"
	if sim.playback == 1.0:
		return "실시간"
	return "%dx Speed" % int(sim.playback)


func _cycle_playback() -> void:
	var order := [1.0, 3.0, 10.0]
	var i := order.find(sim.playback)
	_set_playback(order[(i + 1) % order.size()])


func _set_playback(v: float) -> void:
	if v > 0.0:
		_resume_playback = v
	sim.playback = v
	_refresh_drive_ui()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match (e as InputEventKey).keycode:
		KEY_1:
			_set_playback(1.0)
		KEY_2:
			_set_playback(3.0)
		KEY_3:
			_set_playback(10.0)
		KEY_SPACE:
			_set_playback(0.0 if sim.playback > 0.0 else _resume_playback)
		KEY_R:
			get_tree().reload_current_scene()
		KEY_C:
			director.offer()
		KEY_Y:
			if director.state == "offered":
				director.accept()
			elif director.state == "briefing":
				director.next_briefing()
			else:
				director.start_play()
		KEY_N:
			director.decline()
		KEY_H:
			director.hint()
		KEY_G:
			director.summary()
		KEY_S:
			director._on_alert_pressed()
		KEY_T:
			if director.selected != -1:
				director.call_place(director.selected)
		KEY_X:
			if director.selected != -1:
				director.raid(director.selected)
		KEY_M:
			sfx.set_muted(not sfx.muted)
		KEY_K:
			gleo.finish()


## 주행 이벤트 안내는 사건 진행 중이 아닐 때만 셸이 말한다(사건 중에는 CaseDirector가 말한다).
func _voice_free() -> bool:
	return director == null or not director.owns_ui()


func _on_tunnel_entered(t: Dictionary) -> void:
	adas.set_tunnel(true)
	if _voice_free():
		gleo.show_speaking("%s에 들어가요. 터널 안에서는 통화 연결이 불안정할 수 있어요." % t.get("name", "터널"))


func _on_tunnel_exited(_t: Dictionary) -> void:
	adas.set_tunnel(false)
	if _voice_free():
		gleo.show_idle()


func _on_stopped(st: Dictionary) -> void:
	if _voice_free():
		if bool(st.get("waypoint", false)):
			gleo.show_speaking("경유지에 도착했어요. 잠깐 섰다 갈게요.")
		else:
			gleo.show_speaking("신호 대기 중이에요. 잠깐 쉬어 갈게요.")


func _on_resumed(st: Dictionary) -> void:
	if _voice_free():
		if bool(st.get("waypoint", false)):
			gleo.show_speaking("다시 목적지로 안내할게요.")
		else:
			gleo.show_idle()


func _on_arrived() -> void:
	tbt.set_arrived(DEST_NAME)
	adas.speed_kmh = 0.0
	if _voice_free():
		gleo.show_speaking("목적지에 도착했어요. 내리실 때 뒤쪽을 확인해 주세요.")
	_refresh_drive_ui()


# ---------------------------------------------------------------- 자동 실행 (스크린샷·리허설)

func _run_autoplay_and_screenshot() -> void:
	if args.has("autoplay"):
		await get_tree().process_frame
		await get_tree().process_frame
		for cmd in String(args["autoplay"]).split(",", false):
			await _exec(cmd.strip_edges())
	if args.has("screenshot"):
		await _screenshot(String(args["screenshot"]))


## 명령: offer / accept / start / decline / tN(탐문) / sN(잠복) / s(경고 카드 잠복) / rN(출동, 연출 포함)
##       ffP(진행률 P까지 빨리 감기) / final(최종 단계까지) / arrive(도착까지) / nextstake(다음 잠복 찬스까지)
##       wS(실시간 S초 기다림)
##       wpN(N번 장소를 경유지로 추가) / towp(경유지에 설 때까지) / nearwp(경유지 120m 앞까지)
##       tostop(다음 신호 대기까지) / totunnel(다음 터널까지) / brief(브리핑 다음 장)
##       wpqN(경유지 추가 첫 누름: 확인만) / fastend(결과 카드의 [도착까지 빨리 가기])
##       xN(N번 진술 칩 믿음 ↔ 못 믿음) / pg(용의 장소 검색 다음 페이지) / cl(행동 카드 닫기 → 검색 카드)
##       waitfx(회신 전화·출동 연출과 자막이 끝날 때까지) / skip(자막 끝까지) / tapN(기울인 지도에서 N번 배지 누르기)
##       click=대상(그 자리를 실제로 누른다 + 누른 곳 표시. 시연 영상용): pinN(장소 배지) / go(행동 카드 실행 버튼) /
##             opt:call|stakeout|waypoint(행동 카드 옵션) / raid(출동 버튼) / close(행동 카드 목록) / chipN(진술 칩) /
##             card(사건 카드 첫 버튼) / coach(코치 말풍선 버튼) / result(결말 카드 첫 버튼) / alert(경고 카드) /
##             page(검색 다음 페이지) / gleo:ID(Gleo 바 버튼, 예: gleo:drop:6)
##       rush=tunnel|stake|stakeopenN|stop|final|arrive|offer|heardN(10배속으로 달리다가 그때가 되면 3배속으로)
##       until=…(배속 그대로 기다림). rush=final@30처럼 @배속을 붙일 수 있다
##       speed=S(배속)
##       shot=이름(지금 화면을 --shotdir 폴더에 이름.png로 저장. 한 판을 이어서 찍을 때)
##       selN / mN(의심 메모) / h(힌트) / g(정리)
func _exec(cmd: String) -> void:
	if cmd == "offer":
		director.offer()
	elif cmd == "accept":
		director.accept()
	elif cmd == "start":
		director.start_play()
	elif cmd == "decline":
		director.decline()
	elif cmd == "h":
		director.hint()
	elif cmd == "g":
		director.summary()
	elif cmd == "s":
		director._on_alert_pressed()
	elif cmd == "final":
		_fast_forward(func(): return director.state == "final" or sim.finished)
	elif cmd == "arrive":
		_fast_forward(func(): return sim.finished)
	elif cmd == "tostop":
		_fast_forward(func(): return sim.finished or sim.is_stopped())
	elif cmd == "totunnel":
		_fast_forward(func(): return sim.finished or not sim.in_tunnel().is_empty())
	elif cmd.begins_with("shot="):
		await _snap(cmd.substr(5))
	elif cmd == "nextstake":
		_fast_forward(func(): return sim.finished or (director.case != null and not director.case.stakeout_available().is_empty()))
	elif cmd.begins_with("ff"):
		var target := float(cmd.substr(2))
		_fast_forward(func(): return sim.progress() >= target)
	elif cmd.begins_with("wpq"):
		director.add_waypoint(int(cmd.substr(3)))
	elif cmd.begins_with("wp"):
		director.add_waypoint(int(cmd.substr(2)), true)
	elif cmd == "fastend":
		director.fast_to_arrival()
	elif cmd == "nextcase":
		start_next_case()
	elif cmd == "brief":
		director.next_briefing()
	elif cmd == "pg":
		director.next_page()
	elif cmd == "cl":
		director._on_poi_action("close", -1)
	elif cmd.begins_with("tap") and map3d != null:
		# 기울인 지도에서 N번 장소 배지를 누른 것처럼(누르기 확인용)
		var pj := map3d._project(int(cmd.substr(3)))
		if bool(pj.get("ok", false)):
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = pj["top"]
			map3d._gui_input(ev)
	elif cmd.begins_with("click="):
		await _click(cmd.substr(6))
	elif cmd.begins_with("rush="):
		await _rush(cmd.substr(5))
	elif cmd.begins_with("until="):
		await _rush(cmd.substr(6), false)
	elif cmd.begins_with("speed="):
		_set_playback(float(cmd.substr(6)))
	elif cmd == "coachnext":
		coach.next.emit()
	elif cmd == "waitfx":
		while director.fx_busy() or gleo.typing:
			await get_tree().process_frame
	elif cmd == "skip":
		gleo.finish()
	elif cmd.begins_with("x"):
		director.toggle_trust(int(cmd.substr(1)))
	elif cmd == "towp":
		_fast_forward(func(): return sim.finished or plan.waypoint_s < 0.0 or sim.s >= plan.waypoint_s - 0.01)
	elif cmd == "nearwp":
		_fast_forward(func(): return sim.finished or plan.waypoint_s < 0.0 or sim.s >= plan.waypoint_s - 120.0)
	elif cmd.begins_with("w"):
		await get_tree().create_timer(float(cmd.substr(1))).timeout
	elif cmd.begins_with("sel"):
		director.select(int(cmd.substr(3)))
	elif cmd.begins_with("t"):
		director.call_place(int(cmd.substr(1)))
	elif cmd.begins_with("s"):
		director.stakeout(int(cmd.substr(1)))
	elif cmd.begins_with("r"):
		var id := int(cmd.substr(1))
		director.raid(id)
		director.raid(id)
	elif cmd.begins_with("m"):
		director.tag(int(cmd.substr(1)), "의심")
	await get_tree().process_frame


## 시연 영상용: 그 자리를 실제로 누른다(마우스 누르기·떼기를 화면에 넣는다). 누른 곳에 고리를 그린다.
func _click(target: String) -> void:
	var p := _click_point(target)
	if p.x < 0.0:
		print("click: 대상을 못 찾음 ", target)
		return
	tap_fx.ripple(p)
	await get_tree().create_timer(0.16).timeout
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = p
	down.global_position = p
	down.pressed = true
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().process_frame


func _click_point(target: String) -> Vector2:
	var none := Vector2(-1, -1)
	var c: Control = null
	if target.begins_with("pin"):
		var id := int(target.substr(3))
		if map3d != null:
			var pj: Dictionary = map3d._project(id)
			return map3d.get_global_transform() * (pj["top"] as Vector2) if bool(pj.get("ok", false)) else none
		return nav_map.get_global_transform() * nav_map.to_screen(director.overlay.place_world(id))
	if target.begins_with("opt:"):
		var keys := ["call", "stakeout", "waypoint"]
		var i := keys.find(target.substr(4))
		if i >= 0 and action_card._opts.get_child_count() > i:
			c = action_card._opts.get_child(i)
	elif target.begins_with("chip"):
		c = suspect.chip_control(int(target.substr(4)))
	elif target.begins_with("gleo:"):
		var gid := target.substr(5)
		for i2 in gleo.items.size():
			if String(gleo.items[i2][1]) == gid and gleo._actions.get_child_count() > i2:
				c = gleo._actions.get_child(i2)
	else:
		match target:
			"go":
				c = action_card._primary
			"raid":
				c = action_card._raid
			"close":
				for b in action_card.find_children("*", "Button", true, false):
					if (b as Button).text == "목록":
						c = b
			"card":
				c = case_card._buttons.get_child(0) if case_card._buttons.get_child_count() > 0 else null
			"coach":
				c = coach._btn
			"result":
				c = result_card._primary
			"alert":
				c = alert
			"page":
				c = suspect._next
	if c == null or not c.is_visible_in_tree():
		return none
	return c.get_global_rect().get_center()


## 시연 영상용: 10배속으로 달리다가 조건이 되면 3배속으로 돌아온다(장면이 끊기지 않게 빨리 감기).
func _rush(what: String, fast := true) -> void:
	var speed := 10.0
	if what.contains("@"):
		speed = float(what.get_slice("@", 1))
		what = what.get_slice("@", 0)
	var cond: Callable
	match what:
		"tunnel":
			cond = func(): return not sim.in_tunnel().is_empty()
		"stake":
			cond = func(): return director.case != null and not director.case.stakeout_available().is_empty()
		"stop":
			cond = func(): return sim.is_stopped()
		"final":
			cond = func(): return director.state == "final"
		"arrive":
			cond = func(): return sim.finished
		"offer":
			cond = func(): return director.state == "offered"
		_:
			if what.begins_with("stakeopen"):
				var sid := int(what.substr(9))
				cond = func(): return director.case != null and director.case.stakeout_available().has(sid)
			elif what.begins_with("heard"):
				var hid := int(what.substr(5))
				cond = func(): return director.case != null and director.case.observed.has(hid)
			else:
				return
	if fast:
		_set_playback(speed)
	var guard := 0.0
	while not cond.call() and not sim.finished and guard < 180.0:
		await get_tree().process_frame
		guard += get_process_delta_time()
	if fast:
		_set_playback(3.0)


## 게임 시간을 빨리 감는다. 사건 쪽 시계도 함께 맞춘다.
func _fast_forward(done: Callable) -> void:
	var guard := 0
	while not done.call() and guard < 20000:
		sim.step(0.5)
		director.sync_trip()
		guard += 1
	_refresh_drive_ui()


## 사건 모드 카드 견본: 경고(잠복 찬스), 장소 카드, 장소 목록, 사건 정보 칩, Gleo 대사.
func _show_case_showcase() -> void:
	nav_map.view_mode = String(args.get("view", "overview"))
	var places: Array = puzzle.get("places", [])
	var items := []
	var prog := nav_map.progress
	for p in places:
		var id := int(p["id"])
		var ahead := (float(p["routePos"]) - prog) * _route_length_m()
		items.append({
			"icon": "nav" if ahead >= 0 else "flag",
			"thumb": Landmarks.thumb(String(p["name"]), String(p["kind"])),
			"title": "%s %s" % [PuzzleCase.circled(id), p["name"]],
			"sub": ("%.1fkm 앞 · %s" % [ahead / 1000.0, p["side"]]) if ahead >= 0 else "지나옴 · %s" % p["side"],
			"tag": "길가" if p["roadside"] else "",
			"tag_color": PleosTheme.WARN,
			"dim": ahead < 0,
		})
	rail.set_compact(true)
	rail.set_items("사건 장소 · 지나가는 순서", items)
	adas.set_landmarks(places, plan.length)
	eta.set_extra([["통화 2/6", PleosTheme.ACCENT], ["신뢰도 ●●●●●", PleosTheme.WARN], ["남은 조직원 2", PleosTheme.DANGER]])
	alert.show_alert("300m 앞 오른편 · 잠복 가능", "③ 근처를 지나가요. 지금 잠복하면 확실한 말을 들을 수 있어요.",
			"warning", PleosTheme.WARN, 0.6)
	if places.size() >= 2:
		var p2: Dictionary = places[1]
		poi.show_place({
			"id": int(p2["id"]), "name": p2["name"], "kind": p2["kind"], "side": p2["side"],
			"distance_m": (float(p2["routePos"]) - prog) * _route_length_m(), "roadside": p2["roadside"],
			"chips": [["밝힌 직업: 순찰 경관", PleosTheme.ACCENT]],
			"status": "\"③ 루프탑 카페에 있는 사람은 겉과 속이 같아요.\"",
			"can_call": false, "can_stakeout": false, "can_raid": true,
		})
	gleo.show_speaking("경관이라고 밝힌 사람이 두 명이에요. 한 명은 가짜일 수 있어요.")


## 한 판 이어 찍기: 지금 화면을 저장하고 게임 시각·위치·사건 상태를 출력한다.
func _snap(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := String(args.get("shotdir", "user://shots"))
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(shot_name + ".png"))
	var gt := sim.game_time
	var c := director.case
	var info := "" if c == null else " | 통화 %d/%d · 신뢰도 %d · 검거 %d" % [c.used, c.budget(), c.reputation, c.caught.size()]
	print("shot %s | 실제 %d초 | 게임 %d:%02d | %.2fkm / %.2fkm | 도착까지 %d분 | 사건 %s%s" % [shot_name,
			Time.get_ticks_msec() / 1000, int(gt) / 60, int(gt) % 60, sim.s / 1000.0, plan.length / 1000.0,
			ceili(sim.eta_seconds() / 60.0), director.state, info])


func _screenshot(path: String) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("screenshot saved: %s (%d fps)" % [path, Engine.get_frames_per_second()])
	get_tree().quit()
