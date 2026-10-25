## 튜토리얼 '수습 첫날': 손으로 고른 6곳 판(tutorial-<seed>.json)에서 한 번에 하나씩 배운다.
## 1 회신 전화 → 2 칩과 경우의 수 → 3·4 같은 직업 두 명 → 5 말이 안 맞음 → 6 현장 확인 → 7 못 믿을 말 빼기 → 8 출동.
## 단계마다 코치 마크(스포트라이트)가 누를 곳을 밝히고, 그 단계에 맞는 행동만 받는다(allows).
## 문구는 data/story/tutorial.json의 coach. 대본(누를 곳)은 팩의 "tutorial": {first, pair, stakeout}.
## 그 밖의 판에서는 '처음 겪는 규칙' 팁(tip_once)만 쓴다. 본 팁과 튜토리얼 통과는 user://progress.cfg에 남는다.
class_name Tutorial
extends RefCounted

const PROGRESS := "user://progress.cfg"
const RUSH := 30.0                # 현장 확인 장소까지 빠르게 갈 배속

var director: CaseDirector
var coach: CoachMark
var step := ""                    # call_first | count | call_a | call_b | conflict | stakeout | rush | drop | raid | done
var first := -1
var a := -1                       # 같은 직업 두 명(지나가는 순서)
var b := -1
var r := -1                       # 현장 확인할 길가 장소
var fake := -1                    # 가짜 제보(놈) — 현장 확인 뒤에 코치 문구로만 쓴다
var _coach_text := {}
static var persist := true        # 진행 저장(자동 실행·녹화에서는 끈다)
var _rush := false


static func is_tutorial_pack(data: Dictionary) -> bool:
	return data.has("tutorial")


func _init(d: CaseDirector, c: CoachMark) -> void:
	director = d
	coach = c
	coach.next.connect(_on_next)


## 사건을 수락할 때(브리핑 전) 부른다.
func begin(case: PuzzleCase) -> void:
	var t: Dictionary = case.data["tutorial"]
	first = int(t["first"])
	a = int(t["pair"][0])
	b = int(t["pair"][1])
	r = int(t["stakeout"])
	fake = int(case.data["truth"]["hidden"][0])
	_coach_text = director.story.s.get("coach", {})
	step = ""


## 수사 시작(브리핑이 끝남)
func on_start() -> void:
	_go("call_first")


# ---------------------------------------------------------------- 문구

func _args() -> Dictionary:
	var c := director.case
	var role := c.role_label(c.shown_role(a)) if c.shown_role(a) != "" else ""
	var lab := func(id: int) -> String: return c.place_label(id)
	return {
		"f": lab.call(first), "f_eul": CaseDirector._josa(lab.call(first), "을", "를"),
		"a": lab.call(a), "b": lab.call(b), "r": lab.call(r), "r_eun": CaseDirector._josa(lab.call(r), "은", "는"),
		"fake": lab.call(fake), "fake_eul": CaseDirector._josa(lab.call(fake), "을", "를"),
		"fake_c": PuzzleCase.circled(fake), "role": role,
		"n": director.deduction.live_sets().size(),
	}


func _line(key: String, field: String) -> String:
	var d: Dictionary = _coach_text.get(key, {})
	return String(d.get(field, "")).format(_args())


# ---------------------------------------------------------------- 단계

func _go(s: String) -> void:
	step = s
	var say := _line(s, "say")
	if say != "":
		director.gleo.show_speaking(say, "Gleo · 수습 첫날")
	_show()


## 지금 단계의 코치 마크. 장소를 골랐으면 그 카드의 버튼을 가리킨다.
func _show() -> void:
	var sh := director.shell
	match step:
		"call_first", "call_a", "call_b":
			var id := _want_id()
			if director.selected == id and director.action_card.visible:
				coach.show_step(func(): return sh.control_rect(director.action_card._primary),
						_line("call_first_go", "text"), "", func(): return sh.control_rect(director.action_card))
			else:
				coach.show_step(func(): return sh.pin_rect(id), _line(step, "text"))
		"count":
			coach.show_step(func(): return sh.control_rect(director.suspect._head), _line("count", "text"), "알겠어요",
					func(): return sh.control_rect(director.suspect))
		"conflict":
			coach.show_step(func(): return sh.pair_rect(a, b), _line("conflict", "text"), "다음")
		"stakeout":
			if director.selected == r and director.action_card.visible:
				coach.show_step(func(): return sh.control_rect(director.action_card._opts).merge(
						sh.control_rect(director.action_card._primary)), _line("stakeout_go", "text"), "",
						func(): return sh.control_rect(director.action_card))
			else:
				coach.show_step(func(): return sh.pin_rect(r), _line("stakeout", "text"))
		"rush":
			coach.show_step(func(): return sh.pin_rect(r), _line("rush", "text"))
		"drop":
			coach.show_step(func(): return sh.control_rect(director.suspect.chip_control(fake)), _line("drop", "text"), "",
					func(): return sh.control_rect(director.suspect))
		"raid":
			if director.selected == fake and director.action_card.visible:
				coach.show_step(func(): return sh.control_rect(director.action_card._raid), _line("raid_go", "text"), "",
						func(): return sh.control_rect(director.action_card))
			else:
				coach.show_step(func(): return sh.pin_rect(fake), _line("raid", "text"))
		_:
			coach.clear()


func _want_id() -> int:
	match step:
		"call_first":
			return first
		"call_a":
			return a
		"call_b":
			return b
	return -1


func _on_next() -> void:
	if step == "count":
		_go("call_a")
	elif step == "conflict":
		_go("stakeout")
		_ensure_window()


## 현장 확인 창이 아직 안 열렸으면 열릴 때까지 빠르게 간다.
func _ensure_window() -> void:
	if not director.case.stakeout_available().has(r) and not director.case.observed.has(r):
		_set_rush(true)


func _set_rush(on: bool) -> void:
	if on == _rush:
		return
	_rush = on
	director.shell._set_playback(RUSH if on else 1.0)


# ---------------------------------------------------------------- 감독이 알려 주는 것

## 이 행동을 지금 받을지. 막으면 Gleo가 빛나는 곳을 가리킨다.
func allows(action: String, id := -1) -> bool:
	if step == "" or step == "done":
		return true
	var ok := false
	match action:
		"select":
			ok = id == _focus_id()
		"call":
			ok = step in ["call_first", "call_a", "call_b"] and id == _want_id()
		"stakeout":
			ok = step == "stakeout" and id == r
		"toggle":
			ok = step == "drop" and id == fake
		"raid":
			ok = step == "raid" and id == fake
		"close", "summary":
			ok = true
	if not ok:
		director.gleo.show_speaking(_line("wrong", "say"), "Gleo · 수습 첫날")
	return ok


func _focus_id() -> int:
	match step:
		"call_first", "call_a", "call_b":
			return _want_id()
		"stakeout", "rush":
			return r
		"raid", "drop":
			return fake
	return -1


func on_selected(_id: int) -> void:
	_show()


func on_closed() -> void:
	_show()


## 회신 전화가 끝나 말이 보드에 올랐을 때(연출 끝)
func on_heard(id: int, is_stakeout: bool) -> void:
	if step == "call_first" and id == first:
		_go("count")
	elif step == "call_a" and id == a:
		_go("call_b")
	elif step == "call_b" and id == b:
		_go("conflict")
	elif is_stakeout and id == r and step in ["stakeout", "rush"]:
		_set_rush(false)
		director.shell._set_playback(0.0)        # 읽고 고르는 동안 차를 세워 둔다(마감이 오지 않게)
		step = "drop"
		director._on_poi_action("close", -1)     # 행동 카드를 접고 칩(검색 카드)을 보인다
		_go("drop")


func on_reserved(id: int) -> void:
	if step == "stakeout" and id == r and not director.case.observed.has(id):
		_go("rush")
		_set_rush(true)


func on_toggled(id: int) -> void:
	if step == "drop" and id == fake and director.deduction.live_sets().size() == 1:
		_go("raid")


func on_raided(id: int, hit: bool) -> void:
	if hit and id == fake:
		coach.clear()
		step = "done"
		mark_done()


## 매 프레임: 빠르게 가는 중 현장 확인 창이 열리면 멈추고 예약하게 한다.
func process() -> void:
	if step == "stakeout" and _rush and director.case.stakeout_available().has(r):
		_set_rush(false)
		_show()


# ---------------------------------------------------------------- 진행 저장

static func _cfg() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PROGRESS)
	return cf


static func done() -> bool:
	return bool(_cfg().get_value("tutorial", "done", false))


static func mark_done() -> void:
	if DisplayServer.get_name() == "headless" or not persist:
		return
	var cf := _cfg()
	cf.set_value("tutorial", "done", true)
	cf.save(PROGRESS)


## 처음 겪는 규칙 팁: 판마다가 아니라 한 번만. 본 것은 저장한다(헤드리스 테스트에서는 저장하지 않는다).
static var _seen_now := {}


static func tip_once(coach_mark: CoachMark, key: String, text: String, target: Callable) -> void:
	if _seen_now.has(key):
		return
	var cf := _cfg()
	if bool(cf.get_value("tips", key, false)):
		return
	_seen_now[key] = true
	coach_mark.tip(text, target)
	if DisplayServer.get_name() != "headless" and persist:
		cf.set_value("tips", key, true)
		cf.save(PROGRESS)
