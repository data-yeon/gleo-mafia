## 제보자 초상화(PortraitBank) 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_portrait_bank.gd
## - 직업·이름 → 초상화 키(경관은 이름마다 다른 얼굴, 동네 토박이는 이름의 할머니/할아버지로)
## - 확정한 그림 12장은 정사각 텍스처로 불러와진다
## - 모든 퍼즐 팩의 제보자가 키를 얻는다(그림이 없는 직업은 이니셜 원으로 대신하므로 null도 허용)
## - 모든 팩의 제보자 중 그림이 없는 사람이 없어야 한다(익명 포함 12종 전부 그림 있음)
extends SceneTree

const READY_KEYS := ["cop_han", "cop_seo", "cop_do", "drone", "guard", "rider", "grandma", "grandpa", "gossip", "anon",
		"vendor", "taxi"]

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
	var cases := [
		["COP", "한 경장", false, "cop_han"], ["COP", "서 경장", false, "cop_seo"], ["COP", "도 순경", false, "cop_do"],
		["LOCAL", "송 할아버지", false, "grandpa"], ["LOCAL", "조 할머니", false, "grandma"],
		["DRONE", "탁 씨", false, "drone"], ["RIDER", "류 씨", false, "rider"], ["GUARD", "이 반장", false, "guard"],
		["GOSSIP", "추 여사", false, "gossip"], ["VENDOR", "문 사장", false, "vendor"], ["TAXI", "양 기사", false, "taxi"],
		["", "", false, "anon"], ["COP", "한 경장", true, "anon"], ["DRUNK", "", false, ""],
	]
	for c in cases:
		_check(PortraitBank.key_for(c[0], c[1], c[2]) == c[3], "키 %s %s → %s" % [c[0], c[1], c[3]])
	for k in READY_KEYS:
		var t := PortraitBank.texture_for(k)
		_check(t != null, "%s: 그림을 불러온다" % k)
		if t != null:
			_check(t.get_width() == t.get_height() and t.get_width() >= 400, "%s: 정사각형(%dx%d)" % [k, t.get_width(), t.get_height()])
		var f := PortraitBank.full_for(k)
		_check(f != null and f.get_width() == 512 and f.get_height() == 768, "%s: 원본 세로 그림 512x768" % k)
	_check(PortraitBank.full_for_persona("COP", "서 경장") == PortraitBank.full_for("cop_seo"), "직업·이름으로 원본 그림")
	_check(PortraitBank.texture_for("") == null, "빈 키는 null")
	_check(PortraitBank.texture_for("no_such") == null, "없는 키는 null")

	# 모든 팩: 제보자마다 키가 나오고, 그림이 있는 비율을 센다
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles/index.json"))
	var total := 0
	var with_face := 0
	var missing := {}
	for e in idx:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/puzzles/" + String(e["file"])))
		var sb := StoryBook.for_pack(data)
		for st in sb.pub["statements"]:
			var id := int(st["placeId"])
			var p := sb.persona(id, false)
			var role := "" if st["shownRole"] == null else String(st["shownRole"])
			var key := PortraitBank.key_for(role, String(p["name"]), bool(p["anon"]))
			total += 1
			if PortraitBank.texture_for(key) != null:
				with_face += 1
			else:
				missing[role if role != "" else "(익명)"] = true
	print("제보자 %d명 중 얼굴 그림 있음 %d명, 없는 직업: %s" % [total, with_face, ", ".join(missing.keys())])
	_check(with_face == total, "모든 제보자가 얼굴 그림이 있다(%d/%d, 없는 직업: %s)" % [with_face, total, ", ".join(missing.keys())])
	print("초상화 확인 %d개, 실패 %d개" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
