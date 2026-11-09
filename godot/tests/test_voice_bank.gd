## 제보자 음성(VoiceBank) 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_voice_bank.gd
## - 목록(manifest.json)의 모든 팩에 대해: 장소 9곳 모두 음성 파일이 있고 불러와지며 1초 이상이다
## - 목록의 text가 지금 게임 대사(StoryBook.line)와 같다(대사를 고치고 음성을 안 바꾸면 여기서 걸린다)
## - 대사가 다르거나 없는 팩이면 null(자막만 나온다)
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
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voice/manifest.json"))
	_check(typeof(man) == TYPE_DICTIONARY and not (man as Dictionary).is_empty(), "목록이 있다")
	for pack_id in man:
		var path := "res://data/puzzles/%s.json" % pack_id
		_check(FileAccess.file_exists(path), "%s: 팩 파일이 있다" % pack_id)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var sb := StoryBook.for_pack(data)
		var n_places := (data["places"] as Array).size()
		_check((man[pack_id] as Dictionary).size() == n_places, "%s: 장소 %d곳 모두 음성이 있다" % [pack_id, n_places])
		for pid in range(1, n_places + 1):
			var line := sb.line(pid)
			var s := VoiceBank.stream_for(pack_id, pid, line)
			_check(s != null, "%s/%d: 지금 대사로 음성을 찾는다" % [pack_id, pid])
			if s != null:
				_check(s.get_length() >= 1.0, "%s/%d: 1초 이상(%.1fs)" % [pack_id, pid, s.get_length()])
			_check(VoiceBank.stream_for(pack_id, pid, line + " (고친 대사)") == null, "%s/%d: 대사가 다르면 null" % [pack_id, pid])
	_check(VoiceBank.stream_for("no-such-pack", 1, "x") == null, "없는 팩이면 null")
	_check(VoiceBank.has_pack("phishing-1000"), "데모 팩(phishing-1000)에 음성이 있다")
	print("음성 확인 %d개, 실패 %d개" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
