## 제보자 음성(ElevenLabs로 만든 mp3) 찾기.
## 파일: assets/voice/<팩 id>/<장소 번호>.mp3, 목록: assets/voice/manifest.json
##   {"<팩 id>": {"<장소 번호>": {"text": 게임 대사, "voice": 목소리 이름}}}
## 대사가 바뀌었는데 음성이 옛것이면 어긋나므로, 목록의 text가 지금 대사와 같을 때만 쓴다(다르면 null, 자막만 나온다).
class_name VoiceBank
extends RefCounted

const DIR := "res://assets/voice/"

static var _manifest := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := DIR + "manifest.json"
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) == TYPE_DICTIONARY:
		_manifest = d


## 팩 id·장소 번호·지금 대사로 음성을 찾는다. 없거나 대사가 다르면 null.
static func stream_for(pack_id: String, place_id: int, line: String) -> AudioStream:
	_load()
	var pack: Dictionary = _manifest.get(pack_id, {})
	var item: Dictionary = pack.get(str(place_id), {})
	if item.is_empty() or String(item.get("text", "")) != line:
		return null
	var path := "%s%s/%d.mp3" % [DIR, pack_id, place_id]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## 이 팩에 음성이 있는지(테스트·확인용).
static func has_pack(pack_id: String) -> bool:
	_load()
	return _manifest.has(pack_id)
