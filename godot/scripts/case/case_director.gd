## 사건 모드 진행: 주행 중 제안(카드) → 브리핑(카드 3장) → 탐문·잠복·출동 → 최종 단계 → 결과
## → (도착까지 빨리 감기) → 도착 카드에서 [다음 사건].
## Pleos 셸의 부품(지도, 오른쪽 목록, 도착 카드, 경고 카드, 장소 카드, 사건 카드, Gleo 바, 자율주행 패널)을 그대로 쓴다.
## 데모 규칙(Python 통계에는 없음):
## - 터널 안 통화는 직업을 못 듣는다(은폐). 신호 대기 중 보너스 통화(판당 2번, 신호가 바뀌면 소멸).
## - 잠복 예약: 길가 장소는 잠복 창 안에서 예약해 두고, 그 장소 옆을 실제로 지날 때 확실한 말을 듣는다.
## - 경유지 잠복: 길가가 아닌 장소를 경유지로 추가하면(통화 1번, 판당 1번) 경로를 다시 찾아 그 앞에 서서 잠복한다.
##   그 때문에 못 하게 되는 길가 잠복은 추가하기 전에 알린다.
## - 장소까지 거리와 잠복 창은 "지금 경로" 위 거리(m)로 잰다. 진술 속 구간·편은 처음 경로 기준 그대로다.
## Gleo 바: 진술은 몇 초 동안 다른 안내로 덮지 않는다(안내는 줄을 선다). 지나갈 장소는 Gleo가 먼저 권하고,
## 도착 12분·8분 전에는 남은 통화를 알려 준다. 들은 말은 [노트] 카드에 쌓인다.
class_name CaseDirector
extends Node

signal state_changed(state: String)

const OFFER_AFTER_S := 35.0       # 출발 후 게임 시간 몇 초 뒤에 사건을 제안할지
const POLICE_TRAVEL_S := 2.2      # 출동 연출: 기동대가 가는 시간(실시간 초)
const ENTRY_S := 1.2              # 출동 연출: 현장 진입(실시간 초) 뒤에 결과
const ENDING_INSET_S := 2.6       # 결말: 먼저 현장 3D 확대도(ATM에서 달아나는 범인 / 검거 완료)
const ENDING_S := 2.6 + 2.4       # 결말: 확대도 → 지도 위 정체 공개·도주 연출 → 결말 카드(실시간 초)
const FINAL_ETA_S := 300.0        # 도착 5분 전
const MAX_BONUS := 2              # 신호 대기 보너스 통화 판당 최대
const STATEMENT_HOLD_S := 6.0     # 진술을 다른 안내로 덮지 않는 시간(실제 초)
const QUEUED_HOLD_S := 3.5        # 줄 서 있던 안내 하나를 보여 주는 시간(실제 초)
const QUEUE_MAX_AGE_S := 8.0      # 이보다 오래 기다린 안내는 버린다(이미 지난 일)
const NUDGE_GAP_S := 45.0         # Gleo 권유 사이 최소 간격(게임 초)
const NUDGE_FROM := 150.0         # 다가오는 장소 권유 거리(m)
const NUDGE_TO := 750.0
const IDLE_NUDGE_S := 100.0       # 이만큼(게임 초) 아무것도 안 하면 가장 가까운 안 들은 곳을 권한다
const NUDGE_ACTIONS_S := 14.0     # 권유 버튼이 남아 있는 시간(실제 초)
const REMIND_MIN := [12, 8]       # 도착 N분 전 남은 통화 알림
const DEFAULT_ACTIONS := [["노트", "summary"], ["힌트", "hint"]]
const MAX_CHIPS := 6              # 용의 장소 검색 카드에 보이는 진술 칩 수(넘치면 "+N · 노트")
const CALL_DIAL_S := 1.2          # 회신 전화 연결음(실제 초)
const CALL_HANG_S := 1.0          # 말이 다 나온 뒤 끊을 때까지

var state := "idle"               # idle | offered | briefing | playing | final | result
var auto_offer := true
var instant_raid := false         # 테스트·자동 실행: 출동 연출 없이 바로 결과
var instant_fx := false           # 테스트: 회신 전화 연출 없이 바로 듣는다
var offer_after := OFFER_AFTER_S  # 튜토리얼은 더 일찍 제안한다
var tips_enabled := true          # 처음 겪는 규칙 팁(발표 데모·자동 실행에서는 끈다)
var tutorial: Tutorial            # 튜토리얼 판이면 단계 진행(그 밖에는 null)
var coach: CoachMark
var case: PuzzleCase
var overlay := CaseOverlay.new()
var puzzle_path := ""
var selected := -1

var shell: Control
var nav_map: NavMap
var rail: NavCards.SideRail
var eta: NavCards.EtaCard
var alert: NavCards.AlertCard
var poi: PoiCard
var case_card: CaseCard
var call_pill: CallPill
var inset: SceneInset              # 현장 3D 확대도(지도 가운데)
var suspect: SuspectCard
var action_card: ActionCard
var deduction: CaseDeduction       # 용의 장소 검색 판정기(진술 칩 믿음 → 조건에 맞는 경우)
var story: StoryBook               # 이야기 층(첩보·인물·문구). 정답은 보지 않는다
var gleo: GleoBar
var sfx: Sfx
var edge_map: EdgeFx               # 지도 가장자리 연출(사이렌, 최종 단계)
var edge_left: EdgeFx              # 주행 패널 가장자리 연출(사이렌, 현장 확인 뷰파인더)
var adas: AdasView
var sim: VehicleSim
var plan: RoutePlan
var result_card: ResultCard
var result_dim: ColorRect
var tbt: NavCards.TbtCard

var _pending: PuzzleCase          # 제안할 때 미리 읽어 둔 사건
var _card_mode := ""              # 사건 카드에 지금 무엇이 떠 있나: offer | brief | notes
var _brief_page := 0
var _raid_armed := -1
var _wp_armed := -1
var _pending_raid := {}
var _ui_t := 0.0
var _alert_id := -1
var _missed_until := 0.0
var _clock := 0.0
var _router: CityRouter
var _base_len := 0.0                 # 처음 경로 길이(잠복 창 크기 기준)
var _rerouted := false
var _place_s := {}                   # 장소 id → 지금 경로에서 그 장소 옆을 지나는 지점(m)
var _wp_cache := {}                  # 장소 id → {plan, mins, lost, s} 경유지 후보(차가 조금 움직이면 다시 계산)
var _hold_until := 0.0               # 이 시각(실제)까지는 진술을 덮지 않는다
var _say_queue: Array = []           # 기다리는 안내 [[글, 화자, 버튼, 넣은 시각, 종류], ...]
var _nudged := {}                    # 권유한 장소
var _last_nudge_t := -999.0          # 마지막 권유(게임 시간)
var _last_action_t := 0.0            # 플레이어의 마지막 행동(게임 시간)
var _nudge_until := 0.0              # 권유 버튼을 거둘 시각(실제)
var _reminded := {}
var _heard_order: Array[int] = []    # 진술을 들은 순서(노트)
var _hint_notes: Array[String] = []
var _page := 0                       # 용의 장소 검색 카드 페이지(3곳씩)
var _last_count := -1                # 직전 조건에 맞는 경우 수(바뀌면 Gleo가 알려 준다)
var _ending := ""                    # "fast"면 사건이 끝나고 도착까지 빨리 가는 중
var _deadline := ""                  # 인출(마감) 시각 글자 "9:13"
var _pinged := 0                     # 브리핑에서 핀이 떨어질 때 핑 소리를 낸 수
var _call := {}                      # 진행 중인 회신 전화 {id, phase(dialing|talking), t, stmt, dur}
var _deferred := []                  # 통화 중에 들어온 다른 말(현장 확인) — 통화가 끝나면 보여 준다
var _final_pending := -1             # 통화 중에 최종 단계가 되면 통화가 끝난 뒤 알린다
var _flash_id := -1                  # 방금 들은 말 칩(검색 카드에서 반짝)
var _dup_seen := {}                  # 알린 "같은 직업 두 명"(역할 키)
var _dup_pair: Array[int] = []       # 지도에 빨간 점선으로 잇는 같은 직업 두 곳
var _dup_label := ""
var _ending_data := {}               # StoryBook.ending() 결과(결말 카드)
var _ending_wait := -1.0             # 결말 카드를 띄우기까지 남은 시간
var _last_tick := -1                 # 마지막 30초 째깍 소리
var _flash_until := 0.0


func setup(refs: Dictionary, path: String) -> void:
	shell = refs["shell"]
	nav_map = refs["nav_map"]
	rail = refs["rail"]
	eta = refs["eta"]
	alert = refs["alert"]
	poi = refs["poi"]
	case_card = refs["case_card"]
	call_pill = refs["call_pill"]
	inset = refs["inset"]
	coach = refs["coach"]
	var m3: MapView3D = refs.get("map3d")
	if m3 != null:
		m3.case_overlay = overlay
		overlay.upright = true
	suspect = refs["suspect"]
	action_card = refs["action_card"]
	gleo = refs["gleo"]
	sfx = refs["sfx"]
	edge_map = refs["edge_map"]
	edge_left = refs["edge_left"]
	adas = refs["adas"]
	sim = refs["sim"]
	plan = refs["plan"]
	result_card = refs["result_card"]
	result_dim = refs["result_dim"]
	tbt = refs["tbt"]
	puzzle_path = path
	nav_map.overlay_drawer = overlay.draw
	nav_map.tapped.connect(_on_map_tapped)
	rail.item_pressed.connect(_on_rail_item)
	poi.action.connect(_on_poi_action)
	case_card.action.connect(_on_gleo_action)
	suspect.chip_pressed.connect(toggle_trust)
	suspect.row_pressed.connect(func(id: int):
		if _gate("select", id):
			select(id))
	suspect.next_page.connect(next_page)
	suspect.more_chips.connect(summary)
	action_card.action.connect(_on_poi_action)
	alert.pressed.connect(_on_alert_pressed)
	gleo.action.connect(_on_gleo_action)
	result_card.restart.connect(func(): shell.get_tree().reload_current_scene())
	result_card.fast_forward.connect(fast_to_arrival)
	result_card.next_case.connect(_next_case)
	sim.tunnel_entered.connect(_on_tunnel_entered)
	sim.stopped.connect(_on_stopped)
	sim.resumed.connect(_on_resumed)
	sim.arrived.connect(_on_arrived)


func is_active() -> bool:
	return state in ["briefing", "playing", "final"]


## 셸이 Gleo 바·목록을 직접 쓰면 안 되는 상태(사건 진행 중)
func owns_ui() -> bool:
	return state != "idle"


func _set_state(s: String) -> void:
	state = s
	state_changed.emit(s)


# ---------------------------------------------------------------- Gleo 말하기

## kind: statement(진술·결과, 몇 초 동안 덮지 않음) / reply(플레이어 행동에 대한 답, 바로) /
##       info(주행 이벤트·권유, 진술을 덮지 않게 줄을 선다. 8초 넘게 기다리면 버린다)
##       search(용의 장소 검색 결과: 진술 바로 다음 차례로 끼어들고 버리지 않는다. 새 결과가 옛 결과를 바꾼다)
##       moment(의심의 순간: search보다도 앞에 서고 버리지 않는다)
## actions: 이 말과 함께 띄울 권유 버튼(줄을 서면 말이 나올 때 함께 뜬다).
func _say(text: String, who := "Gleo", kind := "info", actions := []) -> void:
	if kind == "moment" and _clock < _hold_until:
		var at := 0
		while at < _say_queue.size() and String(_say_queue[at][4]) == "moment":
			at += 1
		_say_queue.insert(at, [text, who, actions, _clock, "moment"])
		return
	if kind == "search" and _clock < _hold_until:
		for i in range(_say_queue.size() - 1, -1, -1):
			if String(_say_queue[i][4]) == "search":
				_say_queue.remove_at(i)
		var at2 := 0
		while at2 < _say_queue.size() and String(_say_queue[at2][4]) == "moment":
			at2 += 1
		_say_queue.insert(at2, [text, who, actions, _clock, "search"])
		return
	if kind == "info" and _clock < _hold_until:
		_say_queue.append([text, who, actions, _clock, "info"])
		if _say_queue.size() > 3:
			_say_queue.remove_at(1 if String(_say_queue[0][4]) == "search" else 0)
		return
	gleo.show_speaking(text, who)
	if not actions.is_empty():
		_set_actions(actions, true)
	if kind == "statement":
		_hold_until = _clock + maxf(STATEMENT_HOLD_S, text.length() / GleoBar.CPS + 3.0)
	elif kind == "search" or kind == "moment":
		_hold_until = _clock + QUEUED_HOLD_S + (1.0 if kind == "moment" else 0.0)


func _set_actions(items: Array, nudge := false) -> void:
	gleo.set_actions(items)
	_nudge_until = _clock + NUDGE_ACTIONS_S if nudge else 0.0


# ---------------------------------------------------------------- 사건 카드

func _show_card(mode: String, d: Dictionary) -> void:
	_card_mode = mode
	poi.visible = false
	suspect.hide_card()
	action_card.hide_card()
	selected = -1
	overlay.selected = -1
	case_card.show_card(d)
	shell.call_deferred("_layout")


func _hide_card() -> void:
	_card_mode = ""
	case_card.hide_card()
	if case != null and deduction != null:
		_refresh()
	shell.call_deferred("_layout")


func _evil_labels(c: PuzzleCase) -> String:
	var out := PackedStringArray()
	for r in c.data["preset"]["evil"]:
		out.append(c.role_label(String(r)))
	return ", ".join(out)


# ---------------------------------------------------------------- 흐름

func offer() -> void:
	if state != "idle" or sim.finished:
		return
	var c := PuzzleCase.load_from(puzzle_path)
	if c == null:
		return
	_pending = c
	_set_state("offered")
	story = StoryBook.for_pack(c.data)
	_deadline = shell.clock_hm(sim.eta_seconds())
	var o := story.offer(_story_args())
	var btns := [["수사 시작", "accept", "PrimaryButton"], ["나중에", "decline"]]
	if Tutorial.is_tutorial_pack(c.data):
		btns = [["시작하기", "accept", "PrimaryButton"], ["건너뛰기", "skip_tutorial"]]
	_show_card("offer", {"kicker": o["kicker"], "title": o["title"], "lines": o["lines"], "buttons": btns})
	_say(String(o["say"]), String(o["kicker"]), "reply")
	sfx.play("alert")
	_set_actions(btns)


## 이야기 문구에 넣는 시간 값: 마감(인출) 시각, 피해금 이체 시각, 남은 분.
func _story_args() -> Dictionary:
	var hold := int(story.s.get("hold_min", 30)) if story != null else 30
	return {"deadline": _deadline, "sent": shell.clock_hm(sim.eta_seconds() - hold * 60.0),
			"mins": ceili(sim.eta_seconds() / 60.0)}


func decline() -> void:
	if state != "offered":
		return
	_set_state("idle")
	_pending = null
	auto_offer = false
	_hide_card()
	_set_actions([])
	gleo.show_idle("필요하면 \"사건 줘\"라고 말해 주세요")


func accept() -> void:
	if state != "offered":
		return
	case = _pending if _pending != null else PuzzleCase.load_from(puzzle_path)
	_pending = null
	if case == null:
		return
	if story == null:
		story = StoryBook.for_pack(case.data)
		_deadline = shell.clock_hm(sim.eta_seconds())
	shell.demo_slow(true)
	case.statement_heard.connect(_on_statement_heard)
	case.stakeout_offered.connect(_on_stakeout_offered)
	case.stakeout_missed.connect(_on_stakeout_missed)
	case.stakeout_cancelled.connect(_on_stakeout_cancelled)
	case.raided.connect(_on_raided)
	case.final_phase_started.connect(_on_final_phase)
	case.ended.connect(_on_ended)
	case.set_trip_progress(sim.progress())
	_base_len = plan.length
	var city: Dictionary = case.data.get("city", {})
	_router = CityRouter.from_city(city) if city.has("roads") else null
	_measure_places()
	deduction = CaseDeduction.new(case)
	if Tutorial.is_tutorial_pack(case.data):
		tutorial = Tutorial.new(self, coach)
		tutorial.begin(case)
	_last_count = -1
	_page = 0
	overlay.case = case
	overlay.reveal_t = 0.0
	_pinged = 0
	nav_map.extra_points.clear()
	for pl in case.data["places"]:
		nav_map.extra_points.append(Vector2(float(pl["x"]), float(pl["y"])))
	adas.set_landmarks(case.data["places"], plan.length)
	nav_map.view_mode = "overview"
	rail.set_compact(true)
	tbt.set_compact(true)
	_set_state("briefing")
	_brief_page = 0
	_show_briefing()
	_refresh()


## 브리핑 카드 3장(이야기 층): 제보 9통 / 사건 파일 / 놈들의 수법. 누를 때만 넘어간다.
func _briefing_pages() -> Array:
	var pages := story.briefing(_story_args())
	for i in pages.size():
		pages[i]["button"] = "수사 시작" if i == pages.size() - 1 else "다음"
	return pages


func _show_briefing() -> void:
	var pages := _briefing_pages()
	var pg: Dictionary = pages[_brief_page]
	var btn := String(pg["button"])
	_show_card("brief", {"kicker": pg["kicker"], "title": pg["title"], "lines": pg["lines"],
			"stamp": pg.get("stamp", ""), "suspects": story.suspects(),
			"buttons": [[btn, "brief_next", "PrimaryButton"]], "font_size": 20})
	_say(String(pg["say"]), "Gleo · 사건 브리핑", "reply")
	_set_actions([[btn, "brief_next", "PrimaryButton"]])


func next_briefing() -> void:
	if state != "briefing":
		return
	_brief_page += 1
	if _brief_page >= _briefing_pages().size():
		start_play()
	else:
		_show_briefing()


func start_play() -> void:
	if state != "briefing":
		return
	overlay.reveal_t = 1.0
	_hide_card()
	shell.demo_slow(false)
	_set_state("playing")
	_last_action_t = sim.game_time
	_last_nudge_t = sim.game_time
	_set_actions(DEFAULT_ACTIONS)
	_say(story.start_say(), "Gleo", "reply")
	_refresh()
	if tutorial != null:
		shell._set_playback(1.0)          # 튜토리얼은 천천히(현장 확인 때만 빠르게)
		tutorial.on_start()


# ---------------------------------------------------------------- 행동

func select(id: int) -> void:
	if case == null or not state in ["playing", "final"]:
		return
	if _card_mode != "":
		_card_mode = ""
		case_card.hide_card()
	selected = id
	_raid_armed = -1
	if _wp_armed != id:
		_wp_armed = -1
	overlay.selected = id
	_show_poi()
	shell.call_deferred("_layout")
	if tutorial != null:
		tutorial.on_selected(id)


func _acted() -> void:
	_last_action_t = sim.game_time
	if _nudge_until > 0.0:
		_set_actions(DEFAULT_ACTIONS)


## 연출이 돌고 있나(회신 전화·출동). 자동 실행의 waitfx가 기다린다.
func fx_busy() -> bool:
	return not _call.is_empty() or not _pending_raid.is_empty()


## 회신 전화(탐문). 규칙(통화 사용)은 바로 적용하고, 말은 연결음 → 연결 → 자막 순서로 보여 준다.
## 그동안 그 말은 판정기에서 빼 두어, 경우의 수는 통화가 끝나야 바뀐다.
func call_place(id: int) -> void:
	if not is_active() or case == null or not _call.is_empty() or not _gate("call", id):
		return
	if state == "briefing":
		start_play()
	if case.observed.has(id) or case.is_final_phase() or case.calls_left() <= 0 or instant_fx:
		select(id)
	if case.observed.has(id):
		_say("이미 이야기를 들은 곳이에요.", "Gleo", "reply")
		return
	if case.is_final_phase():
		_say("놈들이 눈치챘어요. 이제는 출동만 할 수 있어요.", "Gleo", "reply")
		return
	if case.calls_left() <= 0:
		_say("남은 회신 전화가 없어요.", "Gleo", "reply")
		return
	_acted()
	var obscure := not sim.in_tunnel().is_empty()
	if instant_fx:
		case.investigate(id, obscure)
		_refresh()
		return
	_call = {"id": id, "phase": "dialing", "t": 0.0, "stmt": {}, "dur": 0.0}
	var pend: Array[int] = [id]
	deduction.pending = pend
	case.investigate(id, obscure)
	_start_call(id)
	_refresh()


func _start_call(id: int) -> void:
	selected = -1
	overlay.selected = -1
	_raid_armed = -1
	_wp_armed = -1
	poi.visible = false
	action_card.hide_card()
	call_pill.show_call({"initial": PuzzleCase.circled(id), "color": Color("4a5466"),
			"name": "%s 제보자" % case.place_label(id), "sub": "회신 전화 연결 중…"})
	sfx.play("ring", -3.0)
	inset.show_call(case.place(id), case.place_label(id))
	_hold_until = _clock + 999.0          # 통화 중엔 다른 안내가 끼어들지 않게 줄을 세운다
	gleo.show_speaking("%s 제보자에게 회신 전화를 걸고 있어요…" % case.place_label(id), "Gleo · 회신 전화")
	shell.call_deferred("_layout")


func _advance_call(delta: float) -> void:
	_call["t"] = float(_call["t"]) + delta
	var id := int(_call["id"])
	if String(_call["phase"]) == "dialing":
		if float(_call["t"]) < CALL_DIAL_S:
			return
		_call["phase"] = "talking"
		_call["t"] = 0.0
		var obscured := case.obscured.has(id)
		sfx.play("static" if obscured else "click")
		var ps := story.persona(id, obscured)
		var sub := ""
		if bool(ps["obscured"]):
			sub = "잡음으로 직업 못 들음 · %s" % case.place_label(id)
		elif bool(ps["anon"]):
			sub = "음성 변조 · %s" % case.place_label(id)
		else:
			sub = "자칭 %s · %s" % [ps["role"], case.place_label(id)]
		call_pill.connect_to({"initial": ps["initial"], "color": ps["color"], "name": ps["name"], "sub": sub})
		inset.connect_call(case.shown_role(id), "%s · %s" % [ps["name"], sub], obscured)
		var text := _statement_text(id, _call["stmt"], false)
		gleo.show_speaking(text, story.speaker(id, obscured))
		_call["dur"] = text.length() / GleoBar.CPS + CALL_HANG_S
	elif float(_call["t"]) >= float(_call["dur"]) and not gleo.typing:
		sfx.play("hangup", -6.0)
		call_pill.set_phase("ended")
		_end_call()


func _end_call() -> void:
	var id := int(_call["id"])
	_call = {}
	inset.close(0.5)
	deduction.pending.clear()
	_hold_until = _clock + 2.0            # 다 들은 말은 잠깐 그대로 두고, 그다음 경우의 수 안내
	_board_statement(id, false)
	_refresh()
	var later := _deferred.duplicate()
	_deferred.clear()
	for d in later:
		_on_statement_heard(int(d[0]), d[1], bool(d[2]))
	if _final_pending >= 0:
		var k := _final_pending
		_final_pending = -1
		_announce_final(k)


## 길가 장소 잠복. 경로 거리 모드에서는 예약해 두고 그 장소 옆을 지날 때 듣는다.
func stakeout(id: int) -> void:
	if not is_active() or case == null or not _call.is_empty() or not _gate("stakeout", id):
		return
	if state == "briefing":
		start_play()
	select(id)
	if case.route_mode:
		if case.reserve_stakeout(id):
			_acted()
			if tutorial != null:
				tutorial.on_reserved(id)
			if not case.observed.has(id):
				_say("%s 현장 확인을 예약했어요. 옆을 지날 때 차량 카메라로 제보 내용을 볼게요." % case.place_label(id),
						"Gleo", "reply")
		elif not case.observed.has(id):
			_say("지금은 거기서 현장 확인을 할 수 없어요.", "Gleo", "reply")
	elif case.stakeout(id).is_empty():
		_say("지금은 거기서 현장 확인을 할 수 없어요.", "Gleo", "reply")
	else:
		_acted()
	_refresh()


func raid(id: int) -> void:
	if not is_active() or case == null or case.revealed.has(id) or not _pending_raid.is_empty() or not _call.is_empty() \
			or not _gate("raid", id):
		return
	if state == "briefing":
		start_play()
	if _raid_armed != id and not instant_raid:
		select(id)
		_raid_armed = id
		_show_poi()
		_say("%s 기동대를 보낼까요? 헛걸음이면 본부 신뢰가 %d 떨어져요. 한 번 더 누르면 출동해요." % [
				_josa(case.place_label(id), "으로", "로"), int(case.data["rules"]["wrongRaidCost"])], "Gleo", "reply")
		return
	_raid_armed = -1
	_acted()
	if instant_raid:
		case.raid(id)
		_refresh()
		return
	# 출동 지령(무전) → 기동대 이동(사이렌) → 현장 진입(심장 소리) → 결과(도장)
	_pending_raid = {"id": id, "t": 0.0, "phase": "go"}
	overlay.police = {"from": nav_map.route_point(sim.progress())[0], "to": overlay.place_world(id), "t": 0.0}
	adas.play_police_pass()
	sfx.play("radio")
	sfx.loop("siren", true, -14.0)
	var raid_role := "" if case.obscured.has(id) else case.shown_role(id)
	inset.show_raid(case.place(id), case.place_label(id), raid_role, POLICE_TRAVEL_S)
	edge_map.siren = true
	edge_left.siren = true
	_say("본부, 기동대 %s 출동!" % _josa(case.place_label(id), "으로", "로"), "Gleo · 출동 지령", "reply")
	_show_poi()


## 경유지 잠복: 이 장소를 경유지로 추가하고 경로를 다시 찾는다(통화 1번, 판당 1번, 길가가 아닌 곳만).
## 한 번 누르면 늦어지는 시간과 사라지는 잠복 기회를 알려 주고, 한 번 더 누르면(또는 confirmed) 경로를 바꾼다.
func add_waypoint(id: int, confirmed := false) -> void:
	if not is_active() or case == null or not _call.is_empty() or not _gate("waypoint", id):
		return
	if state == "briefing":
		start_play()
	select(id)
	if not case.can_add_waypoint(id):
		_say("지금은 그 장소에 들를 수 없어요.", "Gleo", "reply")
		return
	var cand := _waypoint_candidate(id)
	if cand.is_empty():
		_say("그 장소를 들르는 길을 찾지 못했어요.", "Gleo", "reply")
		return
	var lost: Array = cand["lost"]
	if not confirmed and _wp_armed != id:
		_wp_armed = id
		_show_poi()
		var lost_text := ""
		if not lost.is_empty():
			lost_text = " 대신 %s 현장 확인 기회는 사라져요." % _circles(lost)
		_say("%s 들러 현장을 확인할까요? 도착이 %d분 늦어지고 회신 전화 1통을 써요.%s 한 번 더 누르면 경로를 바꿔요." % [
				_josa(case.place_label(id), "을", "를"), int(cand["mins"]), lost_text], "Gleo · 들러서 확인", "reply")
		return
	_wp_armed = -1
	_acted()
	case.add_waypoint(id)
	shell.apply_reroute(cand["plan"])
	_rerouted = true
	_wp_cache.clear()
	_measure_places()
	_say("경로를 바꿨어요. %s 앞에 잠깐 서서 현장을 확인할게요. 본부가 지급정지를 걸어 %d분 벌었어요." % [
			case.place_label(id), int(cand["mins"])], "Gleo · 들러서 확인", "reply")
	_refresh()


## 경유지 후보 경로, 늦어지는 시간(분), 사라지는 길가 잠복(lost). 차가 120m 넘게 움직였거나 경로가 바뀌면 다시 계산한다.
func _waypoint_candidate(id: int) -> Dictionary:
	if _router == null or sim.finished:
		return {}
	var c: Dictionary = _wp_cache.get(id, {})
	if not c.is_empty() and absf(float(c["s"]) - sim.s) < 120.0 and c["base"] == plan:
		return c
	var p := case.place(id)
	var r := _router.reroute(plan, sim.s, Vector2(float(p["x"]), float(p["y"])), id, case.place_label(id))
	if r.is_empty():
		_wp_cache[id] = {}
		return {}
	var np: RoutePlan = r["plan"]
	var extra := sim.eta_with(np) - sim.eta_seconds()
	# 아직 잠복할 수 있는(또는 예약한) 길가 장소 중 새 경로에서 멀어지는 곳
	var lost: Array[int] = []
	for k in case.place_route_s:
		var lid := int(k)
		if case.observed.has(lid) or float(case.place_route_s[k]) + case.stakeout_pass_m < sim.s:
			continue
		var pl := case.place(lid)
		var pos := Vector2(float(pl["x"]), float(pl["y"]))
		var ns := CityRouter.plan_s_of(np, pos, 0.0, np.length)
		if (np.point_at(ns)[0] as Vector2).distance_to(pos) >= 120.0:
			lost.append(lid)
	c = {"plan": np, "mins": maxi(1, ceili(extra / 60.0)), "lost": lost, "s": sim.s, "base": plan}
	_wp_cache[id] = c
	return c


## 장소마다 지금 경로 위 지점을 잰다. 처음 경로에서는 팩의 routePos 그대로(Python 규칙과 같게),
## 경로가 바뀐 뒤에는 새 경로에 투영한다. 길가 장소 중 새 경로 가까이(120m) 남은 곳만 잠복 창을 둔다.
func _measure_places() -> void:
	_place_s.clear()
	var roadside := {}
	for pl in case.data["places"]:
		var id := int(pl["id"])
		var ps := float(pl["routePos"]) * plan.length
		var near := true
		if _rerouted:
			var pos := Vector2(float(pl["x"]), float(pl["y"]))
			ps = CityRouter.plan_s_of(plan, pos, 0.0, plan.length)
			near = (plan.point_at(ps)[0] as Vector2).distance_to(pos) < 120.0
		_place_s[id] = ps
		if bool(pl["roadside"]) and near:
			roadside[id] = ps
	case.set_route_positions(roadside, case.rule("stakeoutLookahead") * _base_len,
			case.rule("stakeoutPass") * _base_len)


func _ahead_of(id: int) -> float:
	return float(_place_s.get(id, 0.0)) - sim.s


## 힌트(데모 규칙): 믿는 말 중 거짓말을 하나 짚거나, 못 믿는다고 뺀 말 중 참인 것을 짚는다(신뢰도 -1).
func hint() -> void:
	if not is_active() or case == null or not _call.is_empty() or not _gate("hint"):
		return
	_acted()
	if _heard_order.is_empty():
		_say("아직 들은 말이 없어요. 먼저 회신 전화를 걸어 보세요.", "Gleo · 본부 분석팀", "reply")
		return
	var ht := deduction.hint_target(_heard_order)
	case.spend_hint()
	if ht.is_empty():
		# 이것도 정보라 값을 받는다(공짜면 칩을 바꿔 가며 정답을 맞춰 볼 수 있다).
		_say("본부 분석팀 조회: 지금 믿는 말과 뺀 말은 모두 맞게 골랐어요. (본부 신뢰 -%d)" % int(case.data["rules"]["hintCost"]),
				"Gleo · 본부 분석팀", "statement")
		_refresh()
		return
	var id := int(ht["id"])
	var pair: Array[int] = [id]
	overlay.hint_pair = pair
	if bool(ht["lie"]):
		_say("본부 분석팀 조회: %s의 말은 믿지 않는 게 좋겠어요. (본부 신뢰 -%d)" % [case.place_label(id),
				int(case.data["rules"]["hintCost"])], "Gleo · 본부 분석팀", "statement")
		_set_actions([["%s 빼기" % PuzzleCase.circled(id), "drop:%d" % id, "PrimaryButton"], ["괜찮아요", "dismiss"]], true)
	else:
		_say("본부 분석팀 조회: %s의 말은 믿어도 돼요. (본부 신뢰 -%d)" % [case.place_label(id),
				int(case.data["rules"]["hintCost"])], "Gleo · 본부 분석팀", "statement")
	_refresh()


## [노트]: 들은 말을 쌓아 보여 주는 수사 노트 카드 + 짧은 요약.
func summary() -> void:
	if case == null:
		return
	_show_notes()
	var parts := PackedStringArray()
	parts.append("들은 말 %d개, 남은 회신 전화 %d통" % [case.observed.size(), case.calls_left()])
	var dups := case.duplicate_claims()
	for r in dups.keys():
		parts.append("%s 밝힌 사람이 %d명" % [_irago(case.role_label(String(r))), dups[r].size()])
	_say(". ".join(parts) + ".", "Gleo · 수사 노트", "reply")


func _show_notes() -> void:
	var lines := []
	for id in _heard_order:
		var st := case.statement(id, bool(case.observed[id]))
		var star := "★ " if case.observed[id] else ""
		lines.append(["flag" if case.observed[id] else "phone",
				"%s%s · %s — %s" % [star, case.place_label(id), story.who(id, case.obscured.has(id)), st["fact"]],
				PleosTheme.WARN if case.observed[id] else PleosTheme.TEXT_2])
	if lines.is_empty():
		lines.append(["gleo", "아직 들은 말이 없어요. 장소를 눌러 탐문해 보세요."])
	var dups := case.duplicate_claims()
	for r in dups.keys():
		lines.append(["warning", "%s 밝힌 사람 %d명(%s) · 적어도 한 명은 가짜" % [
				_irago(case.role_label(String(r))), dups[r].size(), _circles(dups[r])], PleosTheme.DANGER])
	for h in _hint_notes:
		lines.append(["warning", "힌트: " + h, PleosTheme.DANGER])
	for id2 in case.revealed:
		lines.append(["police", "%s 출동 — %s" % [case.place_label(id2),
				("검거 (%s)" % case.role_label(case.actual_role(id2))) if case.caught.has(id2)
				else "헛걸음 (%s)" % case.role_label(case.actual_role(id2))],
				PleosTheme.DANGER if case.caught.has(id2) else PleosTheme.TEXT_3])
	var sus := []
	var ok := []
	for k in case.memos.keys():
		(sus if case.memos[k] == "의심" else ok).append(int(k))
	if not sus.is_empty() or not ok.is_empty():
		lines.append(["flag", "메모 · 의심 %s · 무고 %s" % [_circles(sus) if not sus.is_empty() else "-",
				_circles(ok) if not ok.is_empty() else "-"]])
	_show_card("notes", {"kicker": "수사 노트 · 회신 전화 %d/%d · 본부 신뢰 %d" % [case.used, case.budget(),
			maxi(case.reputation, 0)], "title": "들은 말 %d개" % _heard_order.size(), "lines": lines,
			"buttons": [["닫기", "close_card"]], "font_size": 18})


func tag(id: int, t: String) -> void:
	if case == null:
		return
	case.set_memo(id, "" if case.memos.get(id, "") == t else t)
	_show_poi()
	_refresh()


## 사건이 끝난 뒤 [도착까지 빨리 가기]: 결과 카드를 접고 10배속으로 목적지까지.
func fast_to_arrival() -> void:
	if state != "result" or sim.finished:
		return
	result_card.visible = false
	result_dim.visible = false
	_ending = "fast"
	shell.demo_fast_forward(true)
	_set_actions([])
	_say("목적지까지 빠르게 갈게요.", "Gleo", "reply")


# ---------------------------------------------------------------- 신호 처리

func _on_map_tapped(_w: Vector2, sp: Vector2) -> void:
	if not state in ["playing", "final"]:
		return
	var id := overlay.pick(nav_map, sp)
	if id == -1:
		_on_poi_action("close", -1)
	elif _gate("select", id):
		select(id)


func _on_rail_item(index: int) -> void:
	if state in ["playing", "final"] and _gate("select", index + 1):
		select(index + 1)


func _on_poi_action(act: String, id: int) -> void:
	match act:
		"close":
			selected = -1
			overlay.selected = -1
			_raid_armed = -1
			_wp_armed = -1
			poi.visible = false
			action_card.hide_card()
			_refresh()
			shell.call_deferred("_layout")
			if tutorial != null:
				tutorial.on_closed()
		"call":
			call_place(id)
		"stakeout":
			stakeout(id)
		"raid":
			raid(id)
		"waypoint":
			add_waypoint(id)
		"tag_suspicious":
			tag(id, "의심")
		"tag_clean":
			tag(id, "무고")


func _on_alert_pressed() -> void:
	if _alert_id != -1 and case != null and case.stakeout_available().has(_alert_id):
		stakeout(_alert_id)


func _on_gleo_action(id: String) -> void:
	if id.begins_with("call:"):
		call_place(int(id.substr(5)))
		return
	if id.begins_with("drop:"):
		if deduction != null and _gate("toggle", int(id.substr(5))):
			deduction.set_trusted(int(id.substr(5)), false)
			_acted()
			_refresh()
		return
	if id.begins_with("pick:"):
		if _gate("select", int(id.substr(5))):
			select(int(id.substr(5)))
		return
	match id:
		"accept":
			accept()
		"decline":
			decline()
		"start":
			start_play()
		"brief_next":
			next_briefing()
		"summary":
			summary()
		"hint":
			hint()
		"close_card":
			_hide_card()
		"dismiss":
			_set_actions(DEFAULT_ACTIONS)
			_last_action_t = sim.game_time
		"fast":
			fast_to_arrival()
		"next_case":
			_next_case()
		"skip_tutorial":
			Tutorial.mark_done()
			shell.start_case(shell.default_case_id())
		"restart":
			shell.get_tree().reload_current_scene()


func _on_statement_heard(id: int, stmt: Dictionary, is_stakeout: bool) -> void:
	# 회신 전화 연출 중: 그 통화의 말은 연결된 뒤에, 다른 말(현장 확인)은 통화가 끝난 뒤에 보여 준다
	if not _call.is_empty():
		if int(_call["id"]) == id and not is_stakeout and (_call["stmt"] as Dictionary).is_empty():
			_call["stmt"] = stmt
		else:
			_deferred.append([id, stmt, is_stakeout])
		return
	if is_stakeout:
		sfx.play("shutter")
		edge_left.viewfinder()
	var who := ("★ 현장 확인 · %s" % case.place_label(id)) if is_stakeout else story.speaker(id, case.obscured.has(id))
	_say(_statement_text(id, stmt, is_stakeout), who, "statement")
	_board_statement(id, is_stakeout)


## 자막: 회신 전화로 들은 말("…") 또는 현장 확인(차량 카메라로 제보 내용을 확인한 결과, 항상 참)
func _statement_text(id: int, stmt: Dictionary, is_stakeout: bool) -> String:
	if is_stakeout:
		return story.stakeout_line(id, stmt["clue"])
	var line := story.line(id)
	if case.obscured.has(id):
		line = "(지지직…) " + line
	return "\"%s\"" % line


## 들은 말을 지도·검색 카드·노트에 올린다.
func _board_statement(id: int, is_stakeout: bool) -> void:
	overlay.focus = {"id": id, "stakeout": is_stakeout}
	overlay.hint_pair = []
	if not _heard_order.has(id):
		_heard_order.append(id)
	_flash_id = id
	_flash_until = _clock + 2.0
	var dups := case.duplicate_claims()
	for r in dups.keys():
		if _dup_seen.has(r):
			continue
		_dup_seen[r] = true
		var ids: Array = dups[r]
		_dup_pair = [int(ids[0]), int(ids[1])]
		var role := case.role_label(String(r))
		_dup_label = "자칭 %s 둘" % role
		sfx.play("doubt")
		_say("자칭 %s 두 명이에요(%s). 진짜 제보자는 직업이 안 겹쳐요. 둘 중 하나는 가짜예요." % [
				_josa(role, "이", "가"), " · ".join(PackedStringArray(ids.map(func(x): return case.place_label(int(x)))))],
				"Gleo · 의심", "moment")
	# 지나가며 들은 잠복 진술은 그 장소 카드를 열어 보여 준다(튜토리얼은 칩을 보여야 해서 열지 않는다)
	if is_stakeout and selected != id and state in ["playing", "final"] and tutorial == null:
		select(id)
	elif _card_mode == "notes":
		_show_notes()
	else:
		_show_poi()
	if tutorial != null:
		tutorial.on_heard(id, is_stakeout)


func _on_stakeout_offered(id: int) -> void:
	if state == "playing" or state == "final":
		_tip("stakeout", "길가 장소는 지나가며 차량 카메라로 제보를 확인해요. 이 말은 늘 맞아요",
				func(): return shell.control_rect(alert))
		var p := case.place(id)
		_say("곧 %s %s 옆을 지나가요. 예약해 두면 지날 때 차량 카메라로 제보 내용을 확인해요." % [p["side"], case.place_label(id)])


func _on_stakeout_missed(id: int) -> void:
	if state == "playing" or state == "final":
		alert.show_alert("%s 지나쳤어요" % case.place_label(id), "현장 확인 기회가 사라졌어요.", "warning", PleosTheme.TEXT_3)
		_missed_until = _clock + 3.0


func _on_stakeout_cancelled(id: int) -> void:
	_say("경로가 바뀌어 %s 현장 확인 예약이 취소됐어요." % case.place_label(id))


func _advance_raid(delta: float) -> void:
	var id := int(_pending_raid["id"])
	if String(_pending_raid["phase"]) == "go":
		_pending_raid["t"] = float(_pending_raid["t"]) + delta / POLICE_TRAVEL_S
		overlay.police["t"] = minf(1.0, float(_pending_raid["t"]))
		if float(_pending_raid["t"]) >= 1.0:
			_pending_raid["phase"] = "entry"
			_pending_raid["t"] = 0.0
			overlay.police = {}
			overlay.entry = {"id": id, "t0": overlay.time}
			sfx.loop("siren", false)
			sfx.loop("heart", true, -3.0)
			edge_map.siren = false
			edge_left.siren = false
			inset.enter()
			gleo.show_speaking("%s 현장 진입…" % case.place_label(id), "Gleo · 현장")
		return
	_pending_raid["t"] = float(_pending_raid["t"]) + delta
	if float(_pending_raid["t"]) >= ENTRY_S:
		_pending_raid = {}
		overlay.entry = {}
		sfx.loop("heart", false)
		case.raid(id)


func _on_raided(id: int, hit: bool, actual: String) -> void:
	if tutorial != null:
		tutorial.on_raided(id, hit)
	overlay.add_stamp(id, "검거" if hit else "헛걸음", PleosTheme.DANGER if hit else PleosTheme.TEXT_3)
	if inset.mode == "raid":
		inset.result(hit, case.role_label(actual) if hit
				else ("그냥 %s" if actual in ["DRUNK", "GOSSIP"] else "진짜 %s") % case.role_label(actual))
	sfx.play("stamp")
	if not hit:
		sfx.play("fail", -8.0)
	var label := case.place_label(id)
	var ps := story.persona(id, case.obscured.has(id))
	if hit:
		var who := "익명 제보자" if bool(ps["anon"]) else ("제보자" if bool(ps["obscured"]) else "자칭 %s %s" % [ps["role"], ps["name"]])
		_say("검거! %s의 %s, 사실은 %s." % [label, who, _was(case.role_label(actual))], "Gleo · 현장", "statement")
		if case.caught.size() == 1 and case.n_evil() > 1:
			_say(story.beat("first_catch", {"k": case.n_evil() - case.caught.size()}), "Gleo · 본부 무전")
	else:
		var nm := "그 제보자" if bool(ps["anon"]) or bool(ps["obscured"]) else String(ps["name"])
		var truth := ("그냥 %s" if actual in ["DRUNK", "GOSSIP"] else "진짜 %s") % case.role_label(actual)
		_say("헛걸음이에요… %s %s. 본부 신뢰 -%d" % [_josa(nm, "은", "는"), _was(truth),
				int(case.data["rules"]["wrongRaidCost"])], "Gleo · 현장", "statement")
	if selected == id:
		selected = -1
		overlay.selected = -1
		_raid_armed = -1
		action_card.hide_card()
		shell.call_deferred("_layout")
	_refresh()


func _on_final_phase(raids_left: int) -> void:
	_set_state("final")
	_set_actions(DEFAULT_ACTIONS)
	if not _call.is_empty():
		_final_pending = raids_left
		return
	_announce_final(raids_left)


func _announce_final(raids_left: int) -> void:
	sfx.play("alarm", -6.0)
	_tip("final", "최종 단계: 이제 전화는 못 하고 출동만 할 수 있어요", func(): return shell.control_rect(eta))
	var by := "calls" if case.used >= case.budget() else "time"
	_say(story.final_say(by, raids_left), "Gleo · 본부 무전", "statement")
	_refresh()


func _on_ended(_status: String) -> void:
	if inset.mode == "call":
		inset.close()
	sfx.loop("siren", false)
	sfx.loop("heart", false)
	edge_map.siren = false
	edge_left.siren = false
	if not _call.is_empty():
		_call = {}
		deduction.pending.clear()
		call_pill.hide_call()
		_hold_until = 0.0
	_set_state("result")
	_ending_data = story.ending(case, deduction, _heard_order)
	_start_ending_fx()
	overlay.police = {}
	overlay.stakeout_hot = -1
	adas.set_landmark_hot(-1)
	alert.visible = false
	poi.visible = false
	suspect.hide_card()
	action_card.hide_card()
	var no_ids: Array[int] = []
	overlay.page_ids = no_ids
	_card_mode = ""
	case_card.hide_card()
	var won := case.status == "won"
	eta.set_extra([["검거 %d/%d" % [case.caught.size(), case.n_evil()], PleosTheme.OK if won else PleosTheme.DANGER],
			["본부 신뢰 %d" % maxi(case.reputation, 0), PleosTheme.WARN],
			["회신 전화 %d/%d" % [case.used, case.budget()], PleosTheme.ACCENT]])
	if instant_fx:
		_show_result()
	else:
		_ending_wait = ENDING_S


## 결말 지도 연출: 9곳 정체 이름표(숨은 곳 빨강, 거짓말한 곳 주황, 진짜 회색), 놓친 범인은 지도 밖으로 달아난다.
func _start_ending_fx() -> void:
	var tags := {}
	for id in range(1, case.place_count() + 1):
		var actual := case.actual_role(id)
		if case.is_hidden(id):
			tags[id] = ["%s · %s" % [case.role_label(actual), "검거" if case.caught.has(id) else "도주"],
					PleosTheme.DANGER]
		elif not StoryBook.statement_true(case, id):
			var why := case.role_label(actual) if actual in ["DRUNK", "GOSSIP"] else "협박당함"
			tags[id] = ["거짓 · %s" % why, PleosTheme.WARN]
		else:
			tags[id] = ["진짜", Color("6b7a8f")]
	var esc := []
	for x in case.data["truth"]["hidden"]:
		if not case.caught.has(int(x)):
			esc.append(int(x))
	# 먼저 현장 3D 확대도(놓친 범인이 ATM에서 달아남 / 검거 완료), 그다음 지도 위 정체 공개
	var delay := 0.0
	if not instant_fx:
		var pid := int(esc[0]) if not esc.is_empty() else (case.caught[case.caught.size() - 1] if not case.caught.is_empty() else -1)
		if pid != -1:
			var who := "%s의 %s" % [case.place_label(pid), case.role_label(case.actual_role(pid))]
			inset.show_ending(case.place(pid), who, not esc.is_empty(), ENDING_INSET_S)
			delay = ENDING_INSET_S
	overlay.ending = {"t0": overlay.time + delay, "tags": tags, "escape": esc}
	overlay.focus = {}
	overlay.hint_pair = []
	var none: Array[int] = []
	overlay.conflict_pair = none
	overlay.set_net(none, false)
	var kind := String(_ending_data["kind"])
	if kind == "won":
		sfx.play("win")
		_say("%s! %s." % [_ending_data["title"], _ending_data["sub"]], "Gleo · 본부 무전", "statement")
	elif kind == "fired":
		sfx.play("fail")
		_say("%s. %s." % [_ending_data["title"], _ending_data["sub"]], "Gleo · 본부 무전", "statement")
	else:
		sfx.play("alarm")
		_say("%s! %s." % [story.beat("escape_alarm"), _ending_data["sub"]], "Gleo · 본부 무전", "statement")


## 결과 카드. 도착 전이면 [도착까지 빨리 가기], 도착했으면 [다음 사건].
func _show_result() -> void:
	var arrived := sim.finished
	inset.close()
	if _ending_data.is_empty():
		_ending_data = story.ending(case, deduction, _heard_order)
	if tutorial != null and case.status == "won":
		_ending_data["primary"] = ["next", "진짜 사건 맡기"]
	result_card.show_result(case, arrived, _ending_data)
	result_dim.visible = true
	if tutorial != null and case.status == "won":
		_set_actions([["진짜 사건 맡기", "next_case", "PrimaryButton"], ["다시 하기", "restart"]])
		_say("수습 통과! 이제 진짜 사건을 맡아도 되겠어요, 형사님.", "Gleo · 수습 첫날", "reply")
		return
	var record := "검거 %d/%d, 본부 신뢰 %d" % [case.caught.size(), case.n_evil(), maxi(case.reputation, 0)]
	if arrived:
		_set_actions([["다음 사건", "next_case", "PrimaryButton"], ["다시 하기", "restart"]])
		_say("목적지에 도착했어요. 이번 사건은 %s · %s. 다음 사건도 맡아 주실래요?" % [_ending_data["title"], record],
				"Gleo", "reply")
	else:
		_set_actions([["도착까지 빨리 가기", "fast", "PrimaryButton"], ["다시 하기", "restart"]])
		var msg := {"won": "수고하셨어요, 형사님.", "fired": "본부가 사건을 넘겼어요.", "partial": "한 명은 놓쳤어요.",
				"escaped": "이번엔 놓쳤어요."}
		_say("%s 목적지까지는 %d분 남았어요." % [msg.get(String(_ending_data["kind"]), ""), ceili(sim.eta_seconds() / 60.0)],
				"Gleo", "reply")


func _on_tunnel_entered(t: Dictionary) -> void:
	if state == "playing":
		_say("%s에 들어가요. 터널 안에서 전화하면 잡음에 제보자 자기소개가 끊길 수 있어요." % t.get("name", "터널"))
		_tip("tunnel", "터널 안에서 전화하면 잡음에 제보자 직업이 끊겨요", func(): return shell.control_rect(tbt))


func _on_stopped(st: Dictionary) -> void:
	if bool(st.get("waypoint", false)):
		# 경유지 도착: 그 장소에서 잠복한다(통화는 추가할 때 이미 냈다)
		if case != null and is_active() and case.arrive_waypoint().is_empty():
			_say("들를 곳에 도착했어요.")
		return
	if state == "playing" and tutorial == null and case.grant_bonus_call(MAX_BONUS):
		var sug := _suggest_place(false)
		var acts := []
		if sug != -1:
			acts = [["%s 전화" % PuzzleCase.circled(sug), "call:%d" % sug, "PrimaryButton"], ["괜찮아요", "dismiss"]]
		_tip("bonus", "신호 대기 중엔 회신 전화 한 통을 더 걸 수 있어요(출발하면 사라져요)",
				func(): return shell.control_rect(eta))
		_say("신호 대기 중이에요. 정차한 틈에 회신 전화 한 통을 더 걸 수 있어요." +
				(" %s 어때요?" % case.place_label(sug) if sug != -1 else ""), "Gleo", "reply", acts)
		_refresh()


func _on_resumed(st: Dictionary) -> void:
	if bool(st.get("waypoint", false)):
		if is_active():
			_say("다시 목적지로 안내할게요.")
		return
	if case != null and case.bonus_calls > 0:
		case.revoke_bonus_call()
		if is_active():
			_say("출발했어요. 한 통 더 걸 틈은 지나갔어요.")
			_set_actions(DEFAULT_ACTIONS)
		_refresh()


func _on_arrived() -> void:
	if case != null and case.status == "playing":
		case.arrive()
	elif state == "result":
		# 사건이 끝나고 빨리 가던 중 도착: 원래 배속으로 돌리고 도착 결과 카드
		if _ending == "fast":
			shell.demo_fast_forward(false)
		_ending = ""
		_show_result()


# ---------------------------------------------------------------- 권유·알림 (가운데 채우기)

## 권할 장소: 아직 안 들은(예약·경유지·출동 안 한) 곳 중 다가오는 곳. 길가 장소는 잠복 안내가 따로 있어 뺀다.
## near_only면 150~750m 앞만, 아니면 앞쪽에서 가장 가까운 곳(없으면 아무 곳).
func _suggest_place(near_only: bool) -> int:
	var best := -1
	var best_d := INF
	var any := -1
	for pl in case.data["places"]:
		var id := int(pl["id"])
		if case.observed.has(id) or case.revealed.has(id) or case.is_reserved(id) or case.waypoint_id == id \
				or case.place_route_s.has(id):
			continue
		if any == -1:
			any = id
		var ahead := _ahead_of(id)
		if near_only and (ahead < NUDGE_FROM or ahead > NUDGE_TO or _nudged.has(id)):
			continue
		if ahead > 0.0 and ahead < best_d:
			best_d = ahead
			best = id
	if best == -1 and not near_only:
		return any
	return best


func _maybe_nudge() -> void:
	if tutorial != null:
		return
	if state != "playing" or case == null or not _pending_raid.is_empty() or _clock < _hold_until:
		return
	# 도착 N분 전 알림
	for m in REMIND_MIN:
		if not _reminded.has(m) and sim.eta_seconds() <= m * 60.0 and sim.eta_seconds() > FINAL_ETA_S:
			_reminded[m] = true
			var left := PackedStringArray()
			for pl in case.data["places"]:
				var id := int(pl["id"])
				if not case.observed.has(id) and not case.revealed.has(id):
					left.append(PuzzleCase.circled(id))
			_say(story.beat("remind", {"m": m, "calls": case.calls_left(),
					"left": (" 아직 안 들은 곳 " + "".join(left) + ".") if not left.is_empty() else ""}), "Gleo · 본부 무전")
			return
	if case.calls_left() <= 0 or not case.stakeout_available().is_empty():
		return
	var gt := sim.game_time
	if gt - _last_nudge_t < NUDGE_GAP_S:
		return
	var id2 := _suggest_place(true)
	var idle := gt - _last_action_t > IDLE_NUDGE_S
	if id2 == -1 and idle:
		id2 = _suggest_place(false)
	if id2 == -1:
		return
	_nudged[id2] = true
	_last_nudge_t = gt
	var p := case.place(id2)
	var ahead := _ahead_of(id2)
	var where := ("%s %s 앞" % [p["side"], _dist(ahead)]) if ahead > 0.0 else "이미 지나온 곳"
	var text := ("곧 %s 근처를 지나요(%s). 제보자에게 회신 전화를 걸어 볼까요? 남은 %d통." if ahead > 0.0
			else "%s 제보는 아직 못 들었어요(%s). 회신 전화를 걸어 볼까요? 남은 %d통.") % [
			case.place_label(id2), where, case.calls_left()]
	_say(text, "Gleo", "info",
			[["%s 전화" % PuzzleCase.circled(id2), "call:%d" % id2, "PrimaryButton"], ["괜찮아요", "dismiss"]])


# ---------------------------------------------------------------- 매 프레임

## 사건 쪽 진행률을 차량 위치에 맞추고, 도착 5분 전이면 최종 단계로 넘긴다.
func sync_trip() -> void:
	if case != null and is_active():
		case.set_trip_progress(sim.progress())
		case.set_trip_s(sim.s)
		if sim.eta_seconds() <= FINAL_ETA_S:
			case.enter_final_phase()


func _process(delta: float) -> void:
	_clock += delta
	overlay.time += delta
	if tutorial != null:
		tutorial.process()
	if state == "idle" and auto_offer and sim != null and sim.game_time >= offer_after and not sim.finished:
		offer()
	if state == "briefing":
		overlay.reveal_t = minf(1.0, overlay.reveal_t + delta / 1.8)
		# 제보 9통이 지도에 하나씩 떨어질 때마다 핑
		var dropped := int(overlay.reveal_t * case.place_count() + 0.05)
		while _pinged < mini(dropped, case.place_count()):
			_pinged += 1
			sfx.play("ping", -6.0, 0.9 + 0.04 * _pinged)
	sync_trip()
	if not _call.is_empty():
		_advance_call(delta)
	if _ending_wait > 0.0:
		_ending_wait -= delta
		if _ending_wait <= 0.0:
			_show_result()
	overlay.final_tint = move_toward(overlay.final_tint, 1.0 if state == "final" else 0.0, delta * 2.0)
	edge_map.final_k = overlay.final_tint
	edge_left.final_k = overlay.final_tint * 0.7
	# 최종 단계 마지막 30초: 째깍 + 심장 소리
	if state == "final" and sim.eta_seconds() <= 30.0:
		var sec := int(sim.eta_seconds())
		if sec != _last_tick:
			_last_tick = sec
			sfx.play("tick", -4.0)
		if _pending_raid.is_empty():
			sfx.loop("heart", true, -8.0)
	elif state != "final" and _last_tick != -1:
		_last_tick = -1
		sfx.loop("heart", false)
	if not _pending_raid.is_empty():
		_advance_raid(delta)
	# 기다리던 안내 (너무 오래 기다린 것은 이미 지난 일이라 버린다)
	while not _say_queue.is_empty() and not String(_say_queue[0][4]) in ["search", "moment"] \
			and _clock - float(_say_queue[0][3]) > QUEUE_MAX_AGE_S:
		_say_queue.pop_front()
	if not _say_queue.is_empty() and _clock >= _hold_until:
		var it: Array = _say_queue.pop_front()
		gleo.show_speaking(String(it[0]), String(it[1]))
		if not (it[2] as Array).is_empty():
			_set_actions(it[2], true)
		_hold_until = _clock + QUEUED_HOLD_S
	if _nudge_until > 0.0 and _clock > _nudge_until and state in ["playing", "final"]:
		_set_actions(DEFAULT_ACTIONS)
	_maybe_nudge()
	_ui_t += delta
	if _ui_t > 0.15:
		_ui_t = 0.0
		if is_active():
			_refresh()


## 용의 장소 검색 카드(오른쪽 위), 도착 카드 칩, 잠복 경고, 행동 옵션 카드 갱신.
func _refresh() -> void:
	if case == null:
		return
	var sets := deduction.live_sets()
	_count_feedback(sets)
	var cands := deduction.candidates()
	if sets.is_empty():
		# 믿는 말끼리 부딪히면 어디도 뺄 수 없다: 지도·목록은 그대로 두고 머리줄만 빨갛게
		for i0 in range(1, case.place_count() + 1):
			cands.append(i0)
	var order := _search_order(cands)
	var pages := maxi(1, ceili(order.size() / 3.0))
	_page = clampi(_page, 0, pages - 1)
	var page_ids: Array[int] = []
	for i in range(_page * 3, mini(_page * 3 + 3, order.size())):
		page_ids.append(order[i])
	# 지도: 빠진 곳은 흐리게, 카드에 보이는 3곳은 보라 테두리
	var excluded: Array[int] = []
	for i2 in range(1, case.place_count() + 1):
		if not cands.has(i2):
			excluded.append(i2)
	overlay.excluded = excluded
	overlay.pending = deduction.pending
	# 수사망: 조건에 맞는 경우가 있을 때 남은 후보(잡은 곳 빼고)를 감싼다. 1가지면 붉게 조인다
	var net: Array[int] = []
	if state in ["playing", "final"] and not sets.is_empty():
		for x in deduction.candidates():
			if not case.caught.has(x):
				net.append(x)
	overlay.set_net(net, sets.size() == 1)
	# 의심의 순간: 말이 안 맞으면 빼면 풀리는 두 말, 아니면 같은 직업 두 명
	var pair: Array[int] = []
	var plabel := ""
	if sets.is_empty() and state in ["playing", "final"]:
		var fx := deduction.conflict_fixes(_heard_order)
		if fx.size() >= 2:
			pair = [fx[1], fx[0]]
			plabel = "말이 안 맞아요"
	elif state in ["playing", "final"] and _dup_pair.size() == 2 and not case.revealed.has(_dup_pair[0]) \
			and not case.revealed.has(_dup_pair[1]) \
			and deduction.kind_of(_dup_pair[0]) != "off" and deduction.kind_of(_dup_pair[1]) != "off":
		pair = _dup_pair
		plabel = _dup_label
	overlay.conflict_pair = pair
	overlay.conflict_label = plabel
	var show_search := state in ["playing", "final"] and _card_mode == "" and selected == -1
	var no_ids: Array[int] = []
	overlay.page_ids = page_ids if show_search else no_ids
	if show_search:
		suspect.show_search(_search_data(sets, cands, page_ids, pages))
		shell.call_deferred("_layout")
	var rep := maxi(case.reputation, 0)
	var left_s := maxf(sim.eta_seconds(), 0.0)
	var chips := [["%s까지 %d:%02d" % [story.term("deadline_word"), int(left_s) / 60, int(left_s) % 60],
			PleosTheme.DANGER if case.is_final_phase() else PleosTheme.TEXT_2],
			["회신 전화 %d/%d" % [case.used, case.budget()], PleosTheme.ACCENT],
			["본부 신뢰 " + "●".repeat(rep) + "○".repeat(maxi(0, 5 - rep)), PleosTheme.WARN],
			["남은 %s %d" % [story.term("who"), case.n_evil() - case.caught.size()], PleosTheme.DANGER]]
	if case.bonus_calls > 0:
		chips.insert(2, ["정차 중 한 통 더", PleosTheme.OK])
	if case.is_final_phase() and case.status == "playing":
		chips = [chips[0], ["남은 기동대 %d팀" % case.final_raids_left, PleosTheme.DANGER]] + chips.slice(2)
	eta.set_extra(chips)
	_update_alert()
	if _card_mode == "notes":
		_show_notes()
	if action_card.visible and selected != -1:
		_show_poi()


## 결과 순서: 남은 후보를 지나가는 순서(앞쪽 가까운 곳부터, 지나온 곳은 뒤), 그다음 빠진 곳.
func _search_order(cands: Array[int]) -> Array[int]:
	var ahead_ids: Array[int] = []
	var behind_ids: Array[int] = []
	var out_ids: Array[int] = []
	for i in range(1, case.place_count() + 1):
		if not cands.has(i):
			out_ids.append(i)
		elif _ahead_of(i) > 0.0:
			ahead_ids.append(i)
		else:
			behind_ids.append(i)
	ahead_ids.sort_custom(func(a, b): return _ahead_of(a) < _ahead_of(b))
	var order: Array[int] = []
	order.append_array(ahead_ids)
	order.append_array(behind_ids)
	order.append_array(out_ids)
	return order


func _search_data(sets: Array, cands: Array[int], page_ids: Array[int], pages: int) -> Dictionary:
	var head := ""
	if sets.is_empty():
		head = "[color=#a32d2d][b]조건에 맞는 경우 없음[/b] · 누군가 거짓말해요[/color]"
	elif sets.size() == 1:
		head = "[color=#3b6d11][b]남은 경우 1가지[/b] · %s[/color]" % _circles(sets[0])
	else:
		head = "용의 장소 · 후보 [b]%d곳[/b] · 조건에 맞는 경우 [b]%d가지[/b]" % [cands.size(), sets.size()]
	var fixes: Array[int] = []
	if sets.is_empty():
		fixes = deduction.conflict_fixes(_heard_order)
	var chips := []
	for id in _heard_order:
		var kind := deduction.kind_of(id)
		var st := case.statement(id, bool(case.observed[id]))
		var prefix := ""
		if kind == "lock":
			prefix = "★ "
		elif kind == "soft":
			prefix = "? "
		var text := "%s%s %s: %s" % [prefix, PuzzleCase.circled(id), _who_short(id), _short_fact(st["clue"])]
		chips.append({"id": id, "text": text, "kind": kind, "bad": fixes.has(id),
				"flash": id == _flash_id and _clock < _flash_until})
	for r in case.revealed:
		chips.append({"id": r, "kind": "fact", "text": "%s %s" % [PuzzleCase.circled(r),
				"검거" if case.caught.has(r) else "헛걸음"]})
	if chips.size() > MAX_CHIPS:
		var keep := MAX_CHIPS - 1
		var hidden_n := chips.size() - keep
		chips = [{"id": -1, "kind": "more", "text": "+%d · 노트" % hidden_n}] + chips.slice(chips.size() - keep)
	var rows := []
	for id2 in page_ids:
		var pl := case.place(id2)
		var ahead := _ahead_of(id2)
		var desc := ""
		if case.caught.has(id2):
			desc = "검거 · %s" % case.role_label(case.actual_role(id2))
		elif case.revealed.has(id2):
			desc = "헛걸음 · %s" % case.role_label(case.actual_role(id2))
		elif deduction.pending.has(id2):
			desc = "회신 전화 중…"
		elif not cands.has(id2):
			desc = "제외 · 조건상 숨을 수 없음"
		elif case.observed.has(id2):
			desc = "%s · %s" % [_who_short(id2), _short_fact(case.statement(id2, bool(case.observed[id2]))["clue"])]
		else:
			desc = "%s · %s · 아직 안 들음" % [pl["side"], pl["kind"]]
		if case.is_reserved(id2):
			desc = "잠복 예약 · " + desc
		elif case.waypoint_id == id2 and not case.observed.has(id2):
			desc = "경유지 · " + desc
		rows.append({"id": id2, "num": PuzzleCase.circled(id2), "name": String(pl["name"]),
				"dist": ("%s 앞" % _dist(ahead)) if ahead > 0.0 else "지나옴", "desc": desc,
				"out": not cands.has(id2), "sel": id2 == selected})
	return {"head": head, "chips": chips, "rows": rows, "slots": _suspect_slots(),
			"page_text": ("다음 페이지 (%d/%d)" % [_page + 1, pages]) if pages > 1 else ""}


## 용의자 칸 A·B…: 잡으면 그 칸을 채운다(잡힌 사람의 진짜 역할 = 칸의 역할).
func _suspect_slots() -> Array:
	var slots := story.suspects()
	for cid in case.caught:
		var role := case.actual_role(cid)
		for sl in slots:
			if String(sl["key"]) == role and not sl.has("filled"):
				sl["filled"] = "%s 검거" % case.place_label(cid)
				break
	return slots


## 제보자 짧은 이름: 밝힌 직업, 익명, 직업 못 들음.
func _who_short(id: int) -> String:
	if case.obscured.has(id):
		return "직업 못 들음"
	return case.shown_label(id)


## 경우의 수가 바뀌면 Gleo가 알려 준다. 0이면 누구 말을 뺄지, 1이면 출동을 권한다.
func _count_feedback(sets: Array) -> void:
	var n := sets.size()
	if _last_count < 0:
		_last_count = n
		return
	if n == _last_count:
		return
	var before := _last_count
	_last_count = n
	if n == 0:
		_tip("conflict", "믿는 말끼리 안 맞아요. 칩을 눌러 못 믿을 말을 빼 보세요",
				func(): return shell.control_rect(suspect._chips))
		var fixes := deduction.conflict_fixes(_heard_order)
		sfx.play("doubt")
		if fixes.size() >= 2:
			_say("%s %s 둘 다 믿으면 맞는 경우가 없어요. 누군가 거짓말해요. 누구 말을 뺄까요?" % [
					_josa(case.place_label(fixes[1]), "과", "와"), _josa(case.place_label(fixes[0]), "을", "를")],
					"Gleo · 용의 장소 검색", "search",
					[["%s 빼기" % PuzzleCase.circled(fixes[1]), "drop:%d" % fixes[1]],
					["%s 빼기" % PuzzleCase.circled(fixes[0]), "drop:%d" % fixes[0]]])
		elif fixes.size() == 1:
			_say("이 말들을 다 믿으면 맞는 경우가 없어요. %s의 말을 빼면 맞아요." % case.place_label(fixes[0]),
					"Gleo · 용의 장소 검색", "search", [["%s 빼기" % PuzzleCase.circled(fixes[0]), "drop:%d" % fixes[0]]])
		else:
			_say("믿는 말 중 거짓말이 둘 이상이에요. 칩을 눌러 못 믿을 말을 빼 보세요.", "Gleo · 용의 장소 검색", "search")
	elif n == 1:
		var h: Array = sets[0]
		var names := PackedStringArray()
		var acts := []
		for x in h:
			names.append(case.place_label(int(x)))
			acts.append(["%s 보기" % PuzzleCase.circled(int(x)), "pick:%d" % int(x)])
		sfx.play("ping", -2.0, 0.7)
		_say("남은 경우는 하나예요. 수사망이 %s 좁혀졌어요. 출동할까요?" % _josa(" · ".join(names), "으로", "로"),
				"Gleo · 수사망", "search", acts)
	elif n < before:
		_say("수사망이 좁혀졌어요. 용의 장소 %d곳 · 맞는 경우 %d → %d가지." % [deduction.candidates().size(), before, n],
				"Gleo · 수사망", "search")
	else:
		_say("말 하나를 빼서 경우가 %d가지로 늘었어요. 용의 장소 %d곳." % [n, deduction.candidates().size()],
				"Gleo · 수사망", "search")


## 진술 칩을 눌러 믿음 ↔ 못 믿음.
func toggle_trust(id: int) -> void:
	if deduction == null or not state in ["playing", "final"] or not _gate("toggle", id):
		return
	deduction.toggle(id)
	_acted()
	_refresh()
	if tutorial != null:
		tutorial.on_toggled(id)


## 튜토리얼이면 지금 단계에 맞는 행동만 받는다.
func _gate(action: String, id := -1) -> bool:
	return tutorial == null or tutorial.allows(action, id)


## 결말 카드의 다음: 튜토리얼이면 진짜 사건, 아니면 팩의 다음 사건.
func _next_case() -> void:
	if tutorial != null:
		shell.start_case(shell.default_case_id())
	else:
		shell.start_next_case()


## 처음 겪는 규칙 팁(한 번만). target: 화면 좌표 Rect2를 돌려주는 Callable
func _tip(key: String, text: String, target: Callable) -> void:
	if tips_enabled and tutorial == null and coach != null:
		Tutorial.tip_once(coach, key, text, target)


func next_page() -> void:
	_page += 1
	if _page * 3 >= case.place_count():
		_page = 0
	_refresh()


## 경고 카드: 잠복 예약 가능 > 예약한 잠복이 다가옴 > 최종 단계.
func _update_alert() -> void:
	var avail := case.stakeout_available()
	overlay.stakeout_hot = avail[0] if not avail.is_empty() else -1
	var next_res := -1
	for rid in case.reserved:
		if next_res == -1 or float(case.place_route_s.get(rid, INF)) < float(case.place_route_s.get(next_res, INF)):
			next_res = rid
	if overlay.stakeout_hot == -1 and next_res != -1 and _ahead_of(next_res) < 400.0:
		overlay.stakeout_hot = next_res
	# 경유지에 다가가면 그 장소도 강조한다
	if overlay.stakeout_hot == -1 and case.waypoint_id != -1 and not case.observed.has(case.waypoint_id) \
			and plan.waypoint_s - sim.s > 0.0 and plan.waypoint_s - sim.s < 400.0:
		overlay.stakeout_hot = case.waypoint_id
	adas.set_landmark_hot(overlay.stakeout_hot)
	if not avail.is_empty():
		var id: int = avail[0]
		_alert_id = id
		var p := case.place(id)
		var ps := float(case.place_route_s.get(id, _place_s.get(id, 0.0)))
		var ahead := ps - sim.s
		var left := clampf((ps + case.stakeout_pass_m - sim.s) / maxf(case.stakeout_look_m + case.stakeout_pass_m, 1.0),
				0.0, 1.0)
		var title := ("%s 앞 %s · 현장 확인 가능" % [_dist(ahead), p["side"]]) if ahead > 0 else "지금 %s · 현장 확인 가능" % p["side"]
		alert.show_alert(title, "%s · 눌러서 예약하면 지날 때 카메라로 확인해요" % case.place_label(id), "warning",
				PleosTheme.WARN, left)
		return
	_alert_id = -1
	if next_res != -1:
		var ps2 := float(case.place_route_s.get(next_res, 0.0))
		var ahead2 := ps2 - sim.s
		alert.show_alert("%s 현장 확인 예약 · %s 앞" % [case.place_label(next_res), _dist(ahead2)],
				"%s 옆을 지날 때 카메라로 확인해요" % case.place(next_res)["side"], "route", PleosTheme.WARN,
				clampf(ahead2 / maxf(case.stakeout_look_m, 1.0), 0.0, 1.0))
		return
	if _clock < _missed_until:
		return
	if case.is_final_phase() and case.status == "playing":
		alert.show_alert("최종 단계 · 출동만 가능", "남은 기동대 %d팀 · 장소를 눌러 출동하세요" % case.final_raids_left,
				"police", PleosTheme.DANGER)
	else:
		alert.visible = false


## 행동 옵션 카드(고른 장소): 탐문 / 잠복 예약 / 경유지 잠복 + 출동.
func _show_poi() -> void:
	if case == null or selected == -1:
		return
	suspect.hide_card()
	var id := selected
	var p := case.place(id)
	var chips := []
	var quote := ""
	if case.observed.has(id):
		chips.append([story.who(id, case.obscured.has(id)), PleosTheme.ACCENT])
		if case.observed[id]:
			chips.append(["★ 현장 확인 · 확실", PleosTheme.WARN])
		else:
			var kind := deduction.kind_of(id)
			var trust_text := "판단 보류"
			if kind == "on":
				trust_text = "믿음"
			elif kind == "off":
				trust_text = "못 믿음"
			chips.append([trust_text, PleosTheme.ACCENT if kind == "on" else PleosTheme.TEXT_3])
		quote = story.stakeout_line(id, case.statement(id, true)["clue"]) if case.observed[id] \
				else "\"%s\"" % story.line(id)
	elif case.is_anonymous(id):
		chips.append(["익명 제보 · 음성 변조", PleosTheme.TEXT_3])
	if case.revealed.has(id):
		chips.append(["정체: " + case.role_label(case.actual_role(id)) + (" · 검거" if case.caught.has(id) else " · 헛걸음"),
				PleosTheme.DANGER if case.caught.has(id) else PleosTheme.TEXT_3])
	elif not deduction.candidates().has(id):
		chips.append(["제외 · 조건상 숨을 수 없음", PleosTheme.TEXT_3])
	if case.is_reserved(id):
		chips.append(["현장 확인 예약 · 지날 때 확인", PleosTheme.WARN])
	if case.waypoint_id == id and not case.observed.has(id):
		chips.append(["들를 곳 · 도착하면 확인", NavMap.COL_WAYPOINT])
	var playing := case.status == "playing" and _pending_raid.is_empty()
	var ahead := _ahead_of(id)
	# 탐문
	var call_ok := playing and not case.is_final_phase() and not case.observed.has(id) and not case.revealed.has(id) \
			and case.calls_left() > 0
	var call_desc := "남은 %d통 · 더 걸수록 놈들이 눈치채요" % case.calls_left()
	if case.observed.has(id):
		call_desc = "이미 들은 곳"
	elif case.revealed.has(id):
		call_desc = "이미 출동한 곳"
	elif case.is_final_phase():
		call_desc = "놈들이 눈치채서 더 걸 수 없어요"
	elif not sim.in_tunnel().is_empty():
		call_desc = "터널 잡음에 자기소개가 끊길 수 있어요"
	# 잠복 예약
	var st_ok := playing and case.stakeout_available().has(id)
	var st_val := "지날 때 · 무료"
	var st_desc := "%s 옆을 지날 때 카메라로 확인(확실)" % p["side"]
	if case.observed.has(id):
		st_desc = "이미 들은 곳"
	elif case.is_reserved(id):
		st_val = "예약됨"
		st_desc = "%s 앞 · 지날 때 확인해요" % _dist(ahead)
	elif not bool(p["roadside"]):
		st_desc = "길가 장소만 · 이곳은 들러서 확인으로"
	elif not case.place_route_s.has(id):
		st_desc = "경로가 바뀌어 지나가지 않아요"
	elif not st_ok and ahead > case.stakeout_look_m:
		st_desc = "가까워지면(%s 앞부터)" % _dist(case.stakeout_look_m)
	elif not st_ok:
		st_desc = "이미 지나쳤어요"
	# 경유지 잠복
	var wp_ok := false
	var wp_val := "전화 1통"
	var wp_desc := "길가가 아닌 장소만"
	if playing and case.can_add_waypoint(id):
		var cand := _waypoint_candidate(id)
		if not cand.is_empty():
			wp_ok = true
			wp_val = "+%d분 · 전화 1통" % int(cand["mins"])
			var lost: Array = cand["lost"]
			wp_desc = "들러서 카메라로 확인" + ((" · %s 확인 기회 사라짐" % _circles(lost)) if not lost.is_empty() else "")
		else:
			wp_desc = "들르는 길을 찾지 못했어요"
	elif case.waypoint_id != -1:
		wp_desc = "들러서 확인은 한 번만"
	elif case.observed.has(id):
		wp_desc = "이미 들은 곳"
	elif case.is_final_phase():
		wp_desc = "최종 단계라 쓸 수 없어요"
	var sub := "%s · %s · %s" % [p["kind"], ("%s 앞" % _dist(ahead)) if ahead >= 0.0 else "지나옴", p["side"]]
	action_card.show_actions({
		"id": id, "name": String(p["name"]), "sub": sub,
		"thumb": Landmarks.thumb(String(p["name"]), String(p["kind"])),
		"quote": quote, "chips": chips,
		"options": [
			{"key": "call", "title": "회신 전화", "value": "전화 1통", "desc": call_desc, "enabled": call_ok},
			{"key": "stakeout", "title": "현장 확인 예약", "value": st_val, "desc": st_desc, "enabled": st_ok},
			{"key": "waypoint", "title": "들러서 확인", "value": wp_val, "desc": wp_desc, "enabled": wp_ok},
		],
		"primary": {"call": "전화 걸기", "stakeout": "확인 예약하기",
				"waypoint": "정말 경로 바꾸기?" if _wp_armed == id else "경로 바꾸기"},
		"can_raid": playing and not case.revealed.has(id),
		"raid_armed": _raid_armed == id,
	})
	shell.call_deferred("_layout")


# ---------------------------------------------------------------- 문구 도우미

func _short_fact(clue: Dictionary) -> String:
	var t := String(clue["type"])
	if clue.has("count"):
		var who := ""
		for m in clue.get("members", []):
			who += PuzzleCase.circled(int(m))
		return "%s 중 %d곳" % [who, int(clue["count"])]
	var words := {"suspicious": "수상", "clean": "깨끗", "disguised": "위장", "genuine": "진짜"}
	return "%s %s" % [PuzzleCase.circled(int(clue["target"])), words.get(String(clue["claim"]), t)]


static func _circles(ids: Array) -> String:
	var out := ""
	for i in ids:
		out += PuzzleCase.circled(int(i))
	return out


func _dist(m: float) -> String:
	if m >= 1000.0:
		return "%.1fkm" % (m / 1000.0)
	return "%dm" % int(round(maxf(m, 0.0) / 10.0) * 10)


static func _batchim(word: String) -> int:
	if word.is_empty():
		return 0
	var code := word.unicode_at(word.length() - 1)
	return (code - 0xAC00) % 28 if code >= 0xAC00 and code <= 0xD7A3 else 0


static func _josa(word: String, with_b: String, without: String) -> String:
	var b := _batchim(word)
	if with_b == "으로":
		return word + ("로" if b == 0 or b == 8 else "으로")
	return word + (with_b if b != 0 else without)


static func _euro(word: String) -> String:
	return _josa(word, "으로", "로")


static func _was(word: String) -> String:
	return word + ("이었어요" if _batchim(word) != 0 else "였어요")


static func _irago(word: String) -> String:
	return word + ("이라고" if _batchim(word) != 0 else "라고")
