## 튜토리얼 '수습 첫날' 헤드리스 테스트: 단계를 순서대로 밟아 수습 통과까지, 단계에 맞지 않는 행동은 막힌다.
##   godot --headless --path godot --script res://tests/test_tutorial.gd
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


func _run() -> void:
	var tid := PleosShell.tutorial_id()
	_check(tid != "", "튜토리얼 팩이 있다")
	PleosShell._next_puzzle_id = tid
	var shell: PleosShell = load("res://scenes/pleos_shell.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	shell.sim.playback = 0.0
	var d: CaseDirector = shell.director
	d.instant_raid = true
	d.instant_fx = true
	_check(d.offer_after < CaseDirector.OFFER_AFTER_S, "튜토리얼은 일찍 제안한다")
	d.offer()
	_check(d._card_mode == "offer" and _has_action(d, "skip_tutorial"), "제안 카드에 [건너뛰기]")
	d.accept()
	_check(d.tutorial != null and d.case.place_count() == 6 and d.case.n_evil() == 1, "6곳 · 숨은 곳 1곳")
	_check(d.deduction.live_sets().size() == 6, "처음 6가지")
	var tut := d.tutorial
	while d.state == "briefing":
		d.next_briefing()
	_check(tut.step == "call_first" and shell.coach.visible, "첫 단계: 회신 전화 코치 마크")
	_check(shell.sim.playback == 1.0, "튜토리얼은 1배속")

	# 1) 다른 곳은 막힌다
	d.call_place(tut.a)
	_check(not d.case.observed.has(tut.a), "지금 단계가 아닌 곳에는 전화할 수 없다")
	d.raid(tut.fake)
	_check(not d.case.revealed.has(tut.fake), "출동도 막힌다")
	d.select(tut.first)
	_check(d.action_card.visible and shell.coach.visible, "고르면 행동 카드 · 버튼을 가리킨다")
	d.call_place(tut.first)
	_check(d.case.observed.has(tut.first) and tut.step == "count", "첫 통화 → 경우의 수 설명 (%s)" % tut.step)
	var n1 := d.deduction.live_sets().size()
	_check(n1 >= 2 and n1 <= 4, "첫 말을 믿으면 6 → %d가지" % n1)
	shell.coach.next.emit()
	_check(tut.step == "call_a", "다음: 같은 직업 첫째")
	d.call_place(tut.a)
	_check(tut.step == "call_b", "다음: 같은 직업 둘째")
	d.call_place(tut.b)
	_check(tut.step == "conflict" and d.deduction.live_sets().is_empty(), "같은 직업 둘 → 말이 안 맞음(0가지)")
	_check(d.case.duplicate_claims().size() == 1, "같은 직업 두 명")

	# 2) 현장 확인: 창이 열릴 때까지 빠르게 → 예약 → 지날 때 확인
	shell.coach.next.emit()
	_check(tut.step == "stakeout", "다음: 현장 확인")
	var guard := 0
	while not d.case.stakeout_available().has(tut.r) and guard < 4000:
		shell.sim.step(0.5)
		d.sync_trip()
		tut.process()
		guard += 1
	_check(d.case.stakeout_available().has(tut.r), "현장 확인 창이 열린다")
	d.stakeout(tut.r)
	_check(tut.step == "rush" and d.case.is_reserved(tut.r), "예약하면 빠르게 간다")
	guard = 0
	while not d.case.observed.has(tut.r) and guard < 4000:
		shell.sim.step(0.5)
		d.sync_trip()
		guard += 1
	_check(d.case.observed.get(tut.r, false) == true and tut.step == "drop", "지날 때 확인 → 빼기 단계")
	_check(shell.sim.playback == 0.0, "고르는 동안 차를 세운다")
	_check(not d.action_card.visible and d.suspect.chip_control(tut.fake) != null, "칩이 보인다(행동 카드를 열지 않음)")

	# 3) 빼기 → 출동
	d.toggle_trust(tut.a if tut.a != tut.fake else tut.b)
	_check(tut.step == "drop", "가짜가 아닌 칩은 뺄 수 없다")
	d.toggle_trust(tut.fake)
	_check(d.deduction.live_sets().size() == 1 and tut.step == "raid", "가짜 말을 빼면 1가지 → 출동 단계")
	d.raid(tut.fake)
	_check(d.case.status == "won" and tut.step == "done", "출동 → 검거 → 수습 통과")
	await process_frame
	_check(d.result_card.visible and d.result_card._primary_id == "next"
			and d.result_card._primary.text == "진짜 사건 맡기", "결과 카드: [진짜 사건 맡기]")
	shell.queue_free()
	await process_frame
	PleosShell._next_puzzle_id = ""
	print("튜토리얼 확인 %d개, 실패 %d개" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _has_action(d: CaseDirector, id: String) -> bool:
	for it in d.gleo.items:
		if String(it[1]) == id:
			return true
	return false
