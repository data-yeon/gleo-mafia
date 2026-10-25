## 이야기 층(StoryBook) 헤드리스 테스트: 팩 16개 전부.
##   godot --headless --path godot --script res://tests/test_story.gd
## - 정답 누설 없음: 정답·잠복 진술을 바꾼 팩으로 만든 플레이 중 문구가 원래와 같다
## - 같은 시드면 같은 이름, 한 판 안에서 같은 자칭 직업끼리 이름이 겹치지 않는다
## - 문구 틀이 다 채워지고({…} 없음), 글자 수 한도를 지킨다
extends SceneTree

const ARGS := {"deadline": "9:13", "sent": "8:43", "mins": 20}
const MAX_TITLE := 18
const MAX_LINE := 24
const MAX_SMS := 60
const MAX_SAY := 64
const MAX_STATEMENT := 80

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
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles/index.json"))
	for e in idx:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles/" + String(e["file"])))
		var pid := String(e["id"])
		var sb := StoryBook.for_pack(data)
		_check(not sb.s.is_empty() and sb.s.has("offer"), "%s: 이야기가 있다" % pid)
		# 누설 없음: 정답·힌트·분석·잠복 진술을 엉뚱하게 바꿔도 플레이 중 문구가 같다
		var fake := _perturbed(data)
		var sb2 := StoryBook.for_pack(fake)
		_check(_play_text(sb) == _play_text(sb2), "%s: 정답을 바꿔도 플레이 중 문구가 같다" % pid)
		# 같은 시드면 같은 이름
		var sb3 := StoryBook.for_pack(data)
		_check(_play_text(sb) == _play_text(sb3), "%s: 같은 팩이면 같은 문구" % pid)
		# 같은 자칭 직업끼리 이름이 겹치지 않는다
		var seen := {}
		for id in range(1, sb.place_count() + 1):
			var p := sb.persona(id)
			if bool(p["anon"]):
				continue
			var key := "%s|%s" % [p["role"], p["name"]]
			_check(not seen.has(key), "%s: %d번 이름 %s가 겹치지 않는다" % [pid, id, p["name"]])
			_check(String(p["name"]) != "", "%s: %d번 이름이 있다" % [pid, id])
			seen[key] = true
		# 문구: 틀이 다 채워지고 글자 수 한도
		var o := sb.offer(ARGS)
		_check_text(pid + " 제안 제목", String(o["title"]), MAX_TITLE)
		_check_text(pid + " 제안 말", String(o["say"]), MAX_SAY)
		for ln in o["lines"]:
			_check_text(pid + " 제안 줄", String(ln[1]), MAX_LINE + 6)
		var pages := sb.briefing(ARGS)
		_check(pages.size() == 3, "%s: 브리핑 3장" % pid)
		for pg in pages:
			_check_text(pid + " 브리핑 제목", String(pg["title"]), MAX_TITLE)
			_check_text(pid + " 브리핑 말", String(pg["say"]), MAX_SAY)
			for ln in pg["lines"]:
				if String(ln[0]) == "suspects":
					continue
				var limit := MAX_SMS if String(ln[0]) == "sms" else MAX_LINE + 4
				_check_text(pid + " 브리핑 줄", String(ln[1]), limit)
		for id2 in range(1, sb.place_count() + 1):
			_check_text(pid + " 진술 %d" % id2, sb.line(id2), MAX_STATEMENT)
			var st: Dictionary = data["statements"][id2 - 1]
			if st["stakeout"] != null:
				_check_text(pid + " 현장 확인 %d" % id2, sb.stakeout_line(id2, st["stakeout"]["clue"]), MAX_STATEMENT)
		_check_text(pid + " 최종(시간)", sb.final_say("time", 2), MAX_SAY + 10)
		_check_text(pid + " 최종(통화)", sb.final_say("calls", 2), MAX_SAY + 10)
		_check_text(pid + " 무전", sb.beat("remind", {"m": 8, "calls": 3, "left": ""}), MAX_SAY)
		_check(sb.suspects().size() == sb.n_evil(), "%s: 용의자 칸 수" % pid)
	print("이야기 팩 %d개, 확인 %d개, 실패 %d개" % [idx.size(), _checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check_text(what: String, t: String, limit: int) -> void:
	_check(t != "" and not t.contains("{"), "%s: 틀이 다 채워짐 (%s)" % [what, t])
	_check(t.length() <= limit, "%s: %d자 이하 (%d자: %s)" % [what, limit, t.length(), t])


## 플레이 중 화면에 나올 수 있는 이야기 문구 전부(정답과 무관해야 한다).
func _play_text(sb: StoryBook) -> String:
	var parts := PackedStringArray()
	parts.append(str(sb.offer(ARGS)))
	parts.append(str(sb.briefing(ARGS)))
	parts.append(str(sb.suspects()))
	for id in range(1, sb.place_count() + 1):
		parts.append(str(sb.persona(id)))
		parts.append(sb.speaker(id))
		parts.append(sb.speaker(id, true))
		parts.append(sb.line(id))
	parts.append(sb.final_say("time", 2) + sb.final_say("calls", 1) + sb.start_say())
	return "\n".join(parts)


## 정답을 엉뚱하게 바꾼 사본: 숨은 곳, 실제 역할, 잠복 진술, 힌트·분석.
func _perturbed(data: Dictionary) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	var n: int = d["places"].size()
	d["truth"]["hidden"] = [1, n]
	var roles: Array = d["truth"]["roles"]
	roles.reverse()
	d["hints"] = {"contradictions": []}
	d["analysis"] = {}
	for st in d["statements"]:
		if st["stakeout"] != null:
			st["stakeout"]["line"] = "바뀐 잠복 진술"
			st["stakeout"]["clue"]["count"] = 9
	return d
