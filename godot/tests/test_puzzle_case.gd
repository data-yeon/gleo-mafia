## PuzzleCase 헤드리스 테스트. 퍼즐 팩의 모든 사건에 대해 규칙이 Python(game.py)과 같게 동작하는지 본다.
##   godot --headless --path godot --script res://tests/test_puzzle_case.gd
extends SceneTree

const PUZZLE_DIR := "res://data/puzzles/"

var _fails := 0
var _checks := 0


func _initialize() -> void:
	var files := DirAccess.get_files_at(PUZZLE_DIR)
	var count := 0
	for f in files:
		if not f.ends_with(".json") or f == "index.json":
			continue
		count += 1
		_test_case(PUZZLE_DIR + f)
	print("사건 %d개, 확인 %d개, 실패 %d개" % [count, _checks, _fails])
	quit(1 if _fails > 0 or count == 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("실패: " + msg)


func _hidden(c: PuzzleCase) -> Array[int]:
	var out: Array[int] = []
	for x in c.data["truth"]["hidden"]:
		out.append(int(x))
	return out


func _clean_ids(c: PuzzleCase) -> Array[int]:
	var out: Array[int] = []
	for id in range(1, c.place_count() + 1):
		if not c.is_hidden(id):
			out.append(id)
	return out


func _test_case(path: String) -> void:
	var name := path.get_file()
	var c := PuzzleCase.load_from(path)
	_check(c != null, name + " 로드")
	if c == null:
		return
	var start_rep := int(c.data["rules"]["startReputation"])
	_check(c.reputation == start_rep, name + " 시작 신뢰도")
	_check(c.place_count() == c.data["statements"].size(), name + " 장소 수 = 진술 수")

	# 잠복 찬스: 시작 시점에는 routePos <= lookahead 인 길가 장소만
	_check(c.stakeout_available() == _expected_window(c, 0.0), name + " 시작 잠복 목록")

	# 탐문: 진술이 맞는 장소의 것이고 예산을 쓴다
	var s := c.investigate(1)
	_check(int(s["placeId"]) == 1 and c.used == 1, name + " 탐문")
	_check(c.investigate(1).is_empty() and c.used == 1, name + " 같은 곳 두 번 탐문 불가")

	# 잠복 진술: 팩 v3부터는 모든 장소에 있다(경유지 잠복). 그 전에는 길가 장소만.
	for p in c.data["places"]:
		var has := not c.statement(int(p["id"]), true).is_empty()
		var want := true if c.data.has("routePlan") else bool(p["roadside"])
		_check(has == want, name + " 잠복 진술 유무 %d" % int(p["id"]))

	# 오급습: 신뢰도 -wrongRaidCost
	c = PuzzleCase.load_from(path)
	var clean := _clean_ids(c)
	var r := c.raid(clean[0])
	_check(not r["hit"] and c.reputation == start_rep - int(c.data["rules"]["wrongRaidCost"]),
			name + " 오급습")
	_check(c.raid(clean[0]).is_empty(), name + " 같은 곳 두 번 급습 불가")

	# 승리: 숨은 곳을 모두 급습
	c = PuzzleCase.load_from(path)
	var ended_with := [""]
	c.ended.connect(func(st): ended_with[0] = st)
	for id in _hidden(c):
		_check(c.raid(id)["hit"], name + " 숨은 곳 급습 %d" % id)
	_check(c.status == "won" and ended_with[0] == "won", name + " 승리")

	# 최종 단계: 예산을 다 쓰면 급습만, 기회 = 조직원 수 + 1
	c = PuzzleCase.load_from(path)
	var final_signal := [-1]
	c.final_phase_started.connect(func(n): final_signal[0] = n)
	for id in range(1, c.budget() + 1):
		c.investigate(id)
	_check(c.is_final_phase() and c.final_raids_left == c.n_evil() + 1 and final_signal[0] == c.n_evil() + 1,
			name + " 최종 단계 진입")
	_check(c.investigate(c.budget() + 1).is_empty(), name + " 최종 단계 탐문 불가")
	_check(is_equal_approx(c.progress(), c.rule("finalPhaseStart")), name + " 최종 단계 진행률")
	_check(c.stakeout_available() == _expected_window(c, c.progress()), name + " 최종 단계 잠복 가능 목록")

	# 도주: 최종 단계에서 하나만 남기고 잡은 뒤 기회를 다 쓰면 escaped
	var hidden := _hidden(c)
	for i in range(hidden.size() - 1):
		c.raid(hidden[i])
	clean = _clean_ids(c)
	var k := 0
	while c.status == "playing" and k < clean.size():
		c.raid(clean[k])
		k += 1
	_check(c.status == "escaped" and c.reputation > 0, name + " 도주 (상태 %s, 신뢰도 %d)" % [c.status, c.reputation])

	# 힌트: 모순 쌍을 둘 다 들으면 그 쌍을 알려주고 신뢰도 -hintCost
	c = PuzzleCase.load_from(path)
	_check(c.hint().is_empty() and c.reputation == start_rep, name + " 들은 말 없으면 힌트 없음")
	for pair in c.data["hints"]["contradictions"]:
		if pair["aStakeout"] or pair["bStakeout"]:
			continue
		c.investigate(int(pair["a"]))
		c.investigate(int(pair["b"]))
		var h := c.hint()
		_check(h.size() == 2 and c.reputation == start_rep - int(c.data["rules"]["hintCost"]),
				name + " 힌트 %s" % [h])
		break

	# 차량 진행: 진행률을 끝까지 올리면 길가 장소마다 잠복 찬스를 알리고, 지나치면 놓쳤다고 알린다
	c = PuzzleCase.load_from(path)
	var offered: Array[int] = []
	var missed: Array[int] = []
	c.stakeout_offered.connect(func(id): offered.append(id))
	c.stakeout_missed.connect(func(id): missed.append(id))
	for step in range(0, 21):
		c.set_trip_progress(step / 20.0)
	_check(offered.size() == _count_unobserved_roadside(c), name + " 차량 진행 잠복 알림")
	_check(missed.size() == _count_unobserved_roadside(c), name + " 지나친 잠복 알림")
	for p in c.data["places"]:
		if p["roadside"]:
			c.set_trip_progress(float(p["routePos"]) + c.rule("stakeoutPass") + 0.01)
			_check(not c.stakeout_available().has(int(p["id"])), name + " 지나친 뒤 잠복 불가")
			_check(c.stakeout(int(p["id"])).is_empty(), name + " 지나친 뒤 잠복 실행 불가")

	# 데모 규칙: 터널 은폐와 신호 대기 보너스 통화
	c = PuzzleCase.load_from(path)
	c.investigate(1, true)
	_check(c.obscured.has(1) and c.shown_label(1).begins_with("직업 못 들음"), name + " 터널 은폐")
	_check(c.grant_bonus_call() and not c.grant_bonus_call(), name + " 보너스 통화는 판당 1번")
	var used_before := c.used
	c.investigate(2)
	_check(c.used == used_before and c.bonus_calls == 0, name + " 보너스 통화는 예산을 쓰지 않음")
	c.investigate(3)
	_check(c.used == used_before + 1, name + " 보너스 뒤에는 예산 사용")
	c.grant_bonus_call(2)
	c.revoke_bonus_call()
	_check(c.bonus_calls == 0, name + " 신호가 바뀌면 보너스 소멸")

	# 익명 제보: 직업을 밝히지 않는다
	c = PuzzleCase.load_from(path)
	for p in c.data["places"]:
		var id := int(p["id"])
		if bool(p.get("anonymous", false)):
			_check(c.shown_role(id) == "" and c.shown_label(id) == String(c.data["anonymousLabel"]),
					name + " 익명 표시")
			_check(c.true_shown_role(id) != "", name + " 익명도 진실에는 직업이 있다")
	c.arrive()
	_check(c.status == "escaped", name + " 도착 시 도주")


func _expected_window(c: PuzzleCase, pr: float) -> Array[int]:
	var out: Array[int] = []
	for p in c.data["places"]:
		var pos := float(p["routePos"])
		if p["roadside"] and not c.observed.has(int(p["id"])) \
				and pos - c.rule("stakeoutLookahead") <= pr and pr <= pos + c.rule("stakeoutPass"):
			out.append(int(p["id"]))
	return out


func _count_unobserved_roadside(c: PuzzleCase) -> int:
	var n := 0
	for p in c.data["places"]:
		if p["roadside"] and not c.observed.has(int(p["id"])):
			n += 1
	return n
