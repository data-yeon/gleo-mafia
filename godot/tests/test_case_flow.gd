## 사건 모드 한 판 흐름 헤드리스 테스트 (Pleos 셸 + CaseDirector + 주행 시뮬레이션).
##   godot --headless --path godot --script res://tests/test_case_flow.gd
## 1) 제안 → 수락 → 브리핑 → 탐문 → 정답 출동 → 승리
## 2) 아무도 못 잡고 도착 → 도주(결과 화면)
## 3) 터널 안 통화 → 직업 못 들음(은폐)
## 4) 신호 대기 → 보너스 통화(예산 안 씀), 신호가 바뀌면 소멸
## 5) 경유지 잠복 → 경로 재탐색 → 경유지에 서서 잠복 → 도착
## 6~10) 제안 카드·브리핑 3장, 잠복 예약 → 지날 때 진술, Gleo 권유, 수사 노트, 도착까지 빨리 가기 → 다음 사건
extends SceneTree

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("실패: " + msg)


## Gleo가 이 버튼을 띄웠거나(지금) 띄울 차례인지(줄 선 말).
func _offers(d: CaseDirector, id: String) -> bool:
	var lists := [d.gleo.items]
	for q in d._say_queue:
		lists.append(q[2])
	for list in lists:
		for it in list:
			if String(it[1]) == id:
				return true
	return false


## 연출을 실제 시간 없이 돌린다(감독·Gleo 바·통화 알약의 _process).
func _pump(d: CaseDirector, sec: float) -> void:
	var t := 0.0
	while t < sec:
		d._process(0.05)
		d.gleo._process(0.05)
		d.call_pill._process(0.05)
		d.inset._process(0.05)
		t += 0.05
		if not d.fx_busy() and t > 0.5 and sec > 5.0:
			break


func _pump_raid(d: CaseDirector, sec: float) -> void:
	var t := 0.0
	while t < sec:
		d._process(0.05)
		d.inset._process(0.05)
		t += 0.05


func _new_shell() -> Control:
	var shell: Control = load("res://scenes/pleos_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	shell.sim.playback = 0.0
	shell.director.auto_offer = false
	shell.director.instant_raid = true
	shell.director.instant_fx = true
	return shell


func _start_case(shell: Control) -> CaseDirector:
	var d: CaseDirector = shell.director
	d.offer()
	_check(d.state == "offered", "제안 상태")
	d.accept()
	_check(d.state == "briefing" and d.case != null, "수락하면 브리핑")
	_check(shell.nav_map.view_mode == "overview", "브리핑에서 지도 전체 보기")
	d.start_play()
	_check(d.state == "playing", "시작하면 진행")
	return d


func _run() -> void:
	# 1) 이기는 판
	var shell := await _new_shell()
	var d := _start_case(shell)
	var c := d.case
	d.call_place(2)
	_check(c.used == 1 and c.observed.has(2), "탐문하면 통화 1회 사용")
	_check(d.overlay.focus.get("id", -1) == 2, "들은 진술이 지도에 강조")
	_check(shell.rail.get_child_count() > 0, "오른쪽 목록 있음")
	for x in c.data["truth"]["hidden"]:
		d.raid(int(x))
	_check(c.status == "won" and d.state == "result", "숨은 곳을 다 잡으면 승리")
	_check(shell.result_card.visible and shell.result_dim.visible, "결과 카드 표시")
	shell.queue_free()
	await process_frame

	# 2) 도착하면 도주
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	d.call_place(1)
	shell._fast_forward(func(): return shell.sim.finished)
	_check(c.status == "escaped" and d.state == "result", "아무도 못 잡고 도착하면 도주 (%s)" % c.status)
	_check(c.is_final_phase(), "도착 전에 최종 단계를 거침")
	shell.queue_free()
	await process_frame

	# 3) 터널 은폐
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	if shell.plan.tunnels.is_empty():
		_check(false, "터널이 있어야 함")
	else:
		shell._fast_forward(func(): return not shell.sim.in_tunnel().is_empty())
		var free_id := -1
		for k in range(1, c.place_count() + 1):
			if not c.observed.has(k):
				free_id = k
				break
		if d.state == "playing":
			d.call_place(free_id)
			_check(c.obscured.has(free_id), "터널 안 통화는 직업을 못 들음")
			_check(c.shown_label(free_id).begins_with("직업 못 들음"), "직업 표시가 가려짐")
	shell.queue_free()
	await process_frame

	# 4) 신호 대기 보너스 통화
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	shell._fast_forward(func(): return shell.sim.is_stopped() or shell.sim.finished)
	if d.state == "playing" and shell.sim.is_stopped():
		_check(c.bonus_calls == 1, "신호 대기 중 보너스 통화 1번")
		var used_before := c.used
		var free2 := -1
		for k2 in range(1, c.place_count() + 1):
			if not c.observed.has(k2):
				free2 = k2
				break
		d.call_place(free2)
		_check(c.used == used_before and c.bonus_calls == 0, "보너스 통화는 예산을 쓰지 않음")
		c.grant_bonus_call(2)
		shell._fast_forward(func(): return not shell.sim.is_stopped())
		_check(c.bonus_calls == 0, "신호가 바뀌면 남은 보너스 소멸")
	else:
		_check(false, "첫 신호 대기 전에 최종 단계가 되면 안 됨 (%s)" % d.state)
	shell.queue_free()
	await process_frame

	# 5) 경유지 잠복: 길가가 아닌 장소를 경유지로 → 경로 재탐색 → 그 앞에 서서 잠복 → 목적지 도착
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	var wp_id := -1
	var other_id := -1
	for pl in c.data["places"]:
		if bool(pl["roadside"]):
			continue
		if wp_id == -1 and float(pl["routePos"]) * shell.plan.length > shell.sim.s + 2000.0:
			wp_id = int(pl["id"])
		elif other_id == -1:
			other_id = int(pl["id"])
	_check(wp_id != -1, "경유지로 고를 장소가 있음")
	var old_plan: RoutePlan = shell.plan
	var old_eta: float = shell.sim.eta_seconds()
	var old_s: float = shell.sim.s
	var used0 := c.used
	_check(c.can_add_waypoint(wp_id), "길가가 아닌 장소는 경유지로 추가할 수 있음")
	d.add_waypoint(wp_id)
	_check(c.waypoint_id == -1 and c.used == used0, "경유지는 한 번 누르면 확인만 묻는다")
	d.add_waypoint(wp_id)
	_check(c.waypoint_id == wp_id and c.used == used0 + 1, "경유지 추가에 통화 1번")
	_check(shell.plan != old_plan and shell.plan.waypoint_place == wp_id, "경로를 다시 찾음")
	_check(d.plan == shell.plan and shell.sim.plan == shell.plan, "사건·주행이 새 경로를 씀")
	_check(absf(shell.sim.s - old_s) < 0.01, "내 차 위치는 그대로")
	_check(shell.sim.eta_seconds() > old_eta, "도착이 늦어짐 (%.0f → %.0f초)" % [old_eta, shell.sim.eta_seconds()])
	_check(shell.nav_map.waypoint_marks.size() == 1, "지도에 경유지 표시")
	_check(other_id == -1 or not c.can_add_waypoint(other_id), "경유지는 판당 1번")
	shell._fast_forward(func(): return shell.sim.finished or (shell.sim.is_stopped()
			and bool(shell.sim.current_stop().get("waypoint", false))))
	_check(shell.sim.is_stopped() and bool(shell.sim.current_stop().get("waypoint", false)), "경유지에 선다")
	_check(c.observed.get(wp_id, false) == true, "경유지에 서면 잠복 진술(항상 참)을 듣는다")
	_check(c.bonus_calls == 0, "경유지 정차는 신호 보너스 통화를 주지 않음")
	shell._fast_forward(func(): return shell.sim.finished)
	_check(shell.sim.finished and c.status != "playing", "경유지를 지나 목적지 도착 (%s)" % c.status)
	shell.queue_free()
	await process_frame

	# 6) 인입: 제안 카드 → 브리핑 3장(누를 때만 넘어감) → 진행
	shell = await _new_shell()
	d = shell.director
	d.offer()
	_check(shell.case_card.visible and d._card_mode == "offer", "제안은 카드로 뜬다")
	d.accept()
	_check(d.state == "briefing" and d._card_mode == "brief" and d._brief_page == 0, "브리핑 1/3")
	d.next_briefing()
	d.next_briefing()
	_check(d.state == "briefing" and d._brief_page == 2, "브리핑은 누를 때만 넘어간다(3/3)")
	d.next_briefing()
	_check(d.state == "playing" and not shell.case_card.visible, "마지막 장에서 수사 시작")
	c = d.case

	# 7) 잠복 예약: 잠복 창에서 예약 → 그 장소 옆을 지날 때 확실한 말
	shell._fast_forward(func(): return shell.sim.finished or not c.stakeout_available().is_empty())
	var sid := -1 if c.stakeout_available().is_empty() else c.stakeout_available()[0]
	_check(sid != -1, "길가 장소 잠복 창이 열린다")
	if sid != -1:
		var ps := float(c.place_route_s[sid])
		_check(ps - shell.sim.s > 500.0, "잠복 창은 장소보다 한참 앞에서 열린다 (%.0fm)" % (ps - shell.sim.s))
		d.stakeout(sid)
		_check(c.is_reserved(sid) and not c.observed.has(sid), "예약만 하고 아직 듣지 않는다")
		shell._fast_forward(func(): return shell.sim.finished or c.observed.has(sid))
		_check(c.observed.get(sid, false) == true, "옆을 지날 때 확실한 말을 듣는다")
		_check(absf(shell.sim.s - ps) < 60.0, "장소 옆에서 들었다 (%.0fm 차이)" % (shell.sim.s - ps))
		_check(d._heard_order.has(sid), "들은 말이 노트에 쌓인다")

	# 8) 가운데 채우기: 다가오는 안 들은 장소를 Gleo가 먼저 권한다
	d._hold_until = 0.0
	d._last_nudge_t = -999.0
	var before_nudges: int = d._nudged.size()
	shell._fast_forward(func():
		return shell.sim.finished or d._suggest_place(true) != -1)
	d._maybe_nudge()
	_check(d._nudged.size() > before_nudges or c.calls_left() == 0, "다가오는 장소를 Gleo가 권한다")

	# 9) 수사 노트
	d.summary()
	_check(shell.case_card.visible and d._card_mode == "notes", "노트 카드가 열린다")

	# 10) 마무리: 도착 전에 끝나면 도착까지 빨리 가고, 도착 카드에서 다음 사건
	for x2 in c.data["truth"]["hidden"]:
		d.raid(int(x2))
	_check(c.status == "won" and not shell.sim.finished, "도착 전에 사건 해결")
	_check(shell.result_card.visible and shell.result_card._primary_id == "fast", "결과 카드에 [도착까지 빨리 가기]")
	d.fast_to_arrival()
	_check(not shell.result_card.visible and shell.sim.playback == 10.0, "결과 카드를 접고 10배속")
	shell._fast_forward(func(): return shell.sim.finished)
	_check(shell.result_card.visible and shell.result_card._primary_id == "next", "도착하면 결과 카드에 [다음 사건]")
	_check(shell.sim.playback != 10.0, "도착하면 원래 배속으로")
	shell.queue_free()
	await process_frame

	# 11) 용의 장소 검색: 진술 칩 믿음 → 조건에 맞는 경우가 줄고, 어긋나면 0 → 한 명을 빼면 1
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	var ded := d.deduction
	_check(shell.suspect.visible and not shell.action_card.visible, "수사를 시작하면 용의 장소 검색 카드")
	_check(not shell.rail.visible, "검색 카드가 뜨면 오른쪽 목록은 접힌다")
	_check(ded.live_sets().size() == 36, "처음엔 9곳 중 2곳 = 36가지 (%d)" % ded.live_sets().size())
	_check(shell.suspect._rows.get_child_count() == 3, "결과는 3줄씩")
	d.call_place(2)
	_check(shell.action_card.visible and not shell.suspect.visible, "장소를 고르면 행동 옵션 카드로 바뀐다")
	_check(ded.live_sets().size() == 21, "② 믿으면 21가지 (%d)" % ded.live_sets().size())
	d._on_poi_action("close", -1)
	_check(shell.suspect.visible and not shell.action_card.visible, "닫으면 검색 카드로 돌아온다")
	d.call_place(6)
	_check(ded.live_sets().size() == 10, "⑥까지 믿으면 10가지 (%d)" % ded.live_sets().size())
	d.call_place(9)
	_check(ded.live_sets().is_empty(), "⑨까지 믿으면 맞는 경우 없음")
	var fixes := ded.conflict_fixes(d._heard_order)
	_check(fixes.has(6) and fixes.has(9), "빼면 풀리는 말은 ⑥·⑨ (%s)" % str(fixes))
	_check(_offers(d, "drop:6"), "Gleo가 [⑥ 빼기]를 권한다")
	_check(d.overlay.excluded.is_empty(), "말끼리 부딪히면 지도에서 아무 곳도 빼지 않는다")
	_check(d.overlay.conflict_pair.has(6) and d.overlay.conflict_pair.has(9), "부딪힌 두 말이 지도에 빨간 점선")
	_check(d.overlay.net_ids.is_empty(), "맞는 경우가 없으면 수사망을 걷는다")
	var rep0 := c.reputation
	d.hint()
	_check(c.reputation == rep0 - int(c.data["rules"]["hintCost"]), "힌트는 신뢰도를 쓴다")
	_check(Array(d.overlay.hint_pair) == [6] and _offers(d, "drop:6"), "힌트는 거짓말한 ⑥을 짚는다")
	d._on_poi_action("close", -1)
	var data: Dictionary = d._search_data(ded.live_sets(), ded.candidates(), [], 1)
	var bad_ids := []
	for ch in data["chips"]:
		if bool(ch.get("bad", false)):
			bad_ids.append(int(ch["id"]))
	_check(bad_ids.has(6) and bad_ids.has(9), "어긋난 칩이 빨갛게 표시 (%s)" % str(bad_ids))
	d.toggle_trust(6)
	_check(ded.kind_of(6) == "off", "칩을 누르면 못 믿음")
	var only := ded.live_sets()
	_check(only.size() == 1 and only[0] == [7, 8], "⑥을 빼면 남은 경우 {7,8} (%s)" % str(only))
	_check(Array(ded.candidates()) == [7, 8], "후보 2곳 (%s)" % str(ded.candidates()))
	_check(d.overlay.excluded.size() == 7, "지도에서 나머지 7곳은 흐리게")
	_check(Array(d.overlay.net_ids) == [7, 8] and d.overlay.net_tight, "수사망이 ⑦⑧로 붉게 조여진다")
	_check(d.overlay.conflict_pair.is_empty(), "풀리면 빨간 점선이 사라진다")
	_check(_offers(d, "pick:7"), "Gleo가 [⑦ 보기]를 권한다")
	d.toggle_trust(6)
	_check(ded.kind_of(6) == "on" and ded.live_sets().is_empty(), "다시 누르면 믿음으로 돌아온다")
	d.toggle_trust(6)
	d.next_page()
	_check(d._page == 1, "다음 페이지")
	d.select(7)
	_check(shell.action_card.visible and shell.action_card.selected_option() == "call", "행동 카드 기본 선택은 탐문")
	for x3 in c.data["truth"]["hidden"]:
		d.raid(int(x3))
	_check(c.status == "won", "남은 경우대로 출동하면 승리 (%s)" % c.status)
	var deb: Array = d._ending_data.get("debrief", [])
	_check(not deb.is_empty() and String(deb[0][1]).contains("결정적 단서") and String(deb[0][1]).contains("⑨"),
			"해결 되짚기: 결정적 단서는 ⑨ (%s)" % str(deb))
	_check(deb.size() > 1 and String(deb[1][1]).contains("⑥") and String(deb[1][1]).contains("취객"),
			"⑥을 뺀 판단이 맞았다(취객)")
	_check(shell.result_card.visible and String(shell.result_card._title.text).contains("검거"), "결말 카드 제목")
	_check(not shell.suspect.visible and not shell.action_card.visible, "결과에서는 두 카드 모두 접힌다")
	shell.queue_free()
	await process_frame

	# 13) 의심의 순간: 같은 직업(자칭 순찰 경관)이 두 명이면 두 핀을 잇고, 한쪽을 빼면 걷는다
	shell = await _new_shell()
	d = _start_case(shell)
	d.call_place(1)
	d.call_place(8)
	d._refresh()
	_check(Array(d.overlay.conflict_pair) == [1, 8] and d.overlay.conflict_label.contains("순찰 경관"),
			"같은 직업 두 명을 잇는다 (%s)" % str(d.overlay.conflict_pair))
	_check(d.sfx != null and Array(d._suspect_slots().map(func(x): return x["slot"])) == ["A", "B"], "용의자 칸 A·B")
	d.toggle_trust(1)
	_check(d.overlay.conflict_pair.is_empty(), "한쪽을 못 믿음으로 빼면 점선을 걷는다")
	shell.queue_free()
	await process_frame

	# 14) 출동 연출: 지령 → 기동대 이동(사이렌) → 현장 진입 → 결과(도장). 약 3.4초 뒤에 정체가 드러난다
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	d.instant_raid = false
	d.raid(7)
	_check(not d.fx_busy() and d._raid_armed == 7, "출동은 한 번 누르면 확인만")
	d.raid(7)
	_check(d.fx_busy() and shell.edge_map.siren and d.sfx.is_looping("siren"), "두 번 누르면 출동 · 사이렌")
	_check(shell.inset.visible and shell.inset.big and shell.inset.phase == "go" and shell.inset._police != null,
			"출동 확대도(크게): 경찰차가 들어온다")
	_pump_raid(d, 1.0)
	_check(not c.revealed.has(7), "기동대가 가는 중에는 결과를 모른다")
	_pump_raid(d, 1.6)
	_check(not d.overlay.entry.is_empty() and d.sfx.is_looping("heart") and not shell.edge_map.siren, "현장 진입 · 심장 소리")
	_check(shell.inset.phase == "entry", "확대도 카메라가 다가간다")
	_pump_raid(d, 1.5)
	_check(c.revealed.has(7) and c.caught.has(7) and not d.fx_busy(), "진입 뒤 검거")
	_check(not d.overlay.stamps.is_empty() and String(d.overlay.stamps[0]["text"]) == "검거", "검거 도장")
	_check(shell.inset.phase == "hit" and String(shell.inset._sub.text).contains("협박꾼"), "확대도: 검거 · 협박꾼")
	_pump_raid(d, 2.5)
	_check(not shell.inset.visible, "결과를 보여 준 뒤 확대도를 접는다")
	_check(not d.sfx.is_looping("heart"), "결과가 나오면 심장 소리가 멎는다")
	var filled := ""
	for sl in d._suspect_slots():
		if sl.has("filled"):
			filled = String(sl["slot"])
	_check(filled == "B", "잡은 협박꾼이 용의자 B 칸을 채운다 (%s)" % filled)
	shell.queue_free()
	await process_frame

	# 15) 최종 단계 문구: 회신 전화를 다 쓰면 "눈치챘어요", 시간이 되면 "ATM으로"
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	for k in [1, 2, 3, 4, 5, 6]:
		d.call_place(k)
	_check(c.is_final_phase() and String(d.gleo._text.text).contains("너무 많았어요"), "통화를 다 쓰면 눈치챘다는 말")
	shell.queue_free()
	await process_frame
	shell = await _new_shell()
	d = _start_case(shell)
	shell._fast_forward(func(): return d.state == "final" or shell.sim.finished)
	_check(d.state == "final" and String(d.gleo._text.text).contains("ATM"), "시간이 되면 ATM으로 움직인다는 말 (%s)" % d.gleo._text.text)
	shell.queue_free()
	await process_frame

	# 16) 놓친 결말: ⑥(거짓말)을 믿은 채 도착하면 "속은 말"에 ⑥, 놓친 기회에 ⑦⑧
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	d.call_place(6)
	shell._fast_forward(func(): return shell.sim.finished)
	_check(c.status == "escaped", "아무도 못 잡고 도착 (%s)" % c.status)
	var deb2: Array = d._ending_data.get("debrief", [])
	_check(not deb2.is_empty() and String(deb2[0][1]).contains("속은 말") and String(deb2[0][1]).contains("⑥"),
			"속은 말에 ⑥ (%s)" % str(deb2))
	var missed := false
	for ln in deb2:
		if String(ln[1]).contains("놓친 기회"):
			missed = true
	_check(missed, "놓친 기회: 숨은 곳에 전화하지 않았다")
	_check(String(d._ending_data["kind"]) == "escaped" and not d.overlay.ending.is_empty(), "지도 위 결말 연출")
	_check(Array(d.overlay.ending["escape"]) == [7, 8], "놓친 둘이 달아난다")
	shell.queue_free()
	await process_frame

	# 17) 기울인 지도: 장소 랜드마크가 판 위에 서고, 배지를 누르면 그 장소를 고른다
	shell = await _new_shell()
	d = _start_case(shell)
	_check(shell.map3d != null and d.overlay.upright, "기본 지도는 기울인 지도(배지는 화면 좌표)")
	for i in 30:
		await process_frame
	var pj: Dictionary = shell.map3d._project(4)
	_check(bool(pj.get("ok", false)) and shell.map3d._marks.size() == 9, "장소 9곳 랜드마크가 서고 ④가 화면에 투영된다")
	if bool(pj.get("ok", false)):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = pj["top"]
		shell.map3d._gui_input(ev)
		_check(d.selected == 4 and shell.action_card.visible, "배지를 누르면 ④ 행동 카드 (%d)" % d.selected)
	shell.queue_free()
	await process_frame

	# 12) 회신 전화 연출: 통화는 바로 쓰고, 말과 경우의 수는 연결 → 자막 → 끊은 뒤에 바뀐다
	shell = await _new_shell()
	d = _start_case(shell)
	c = d.case
	d.instant_fx = false
	d.call_place(2)
	_check(c.used == 1 and c.observed.has(2), "회신 전화는 규칙상 바로 쓴다")
	_check(d.fx_busy() and shell.call_pill.visible and shell.call_pill.phase == "dialing", "연결 중 알약")
	_check(shell.inset.visible and shell.inset.mode == "call" and not shell.inset.big, "현장 3D 확대도(중간 크기)가 뜬다")
	_check(d.deduction.live_sets().size() == 36 and not d._heard_order.has(2), "끊기 전엔 경우의 수가 그대로")
	d.call_place(4)
	_check(not c.observed.has(4), "통화 중엔 다른 곳에 걸 수 없다")
	_pump(d, 1.5)
	_check(shell.call_pill.phase == "talking" and String(d.gleo._text.text).contains("장사"), "연결되면 제보자 말이 자막으로")
	_check(shell.inset.phase == "talking" and shell.inset._figure != null, "확대도에 제보자가 나타난다")
	_pump(d, 12.0)
	_check(not d.fx_busy() and d._heard_order.has(2), "통화가 끝나면 말이 노트에 오른다")
	_check(d.deduction.live_sets().size() == 21, "끊은 뒤 경우의 수 21 (%d)" % d.deduction.live_sets().size())
	_check(shell.suspect.visible and not shell.action_card.visible, "통화가 끝나면 검색 카드")
	_pump(d, 1.0)
	_check(not shell.inset.visible, "통화가 끝나면 확대도를 접는다")
	shell.queue_free()
	await process_frame

	print("사건 흐름 확인 %d개, 실패 %d개" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
