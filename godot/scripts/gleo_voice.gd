## Gleo 음성 출력 자리. 데모에서는 OS TTS(DisplayServer.tts_speak)를 쓴다.
## 실제 Gleo SDK(음성 인식, TTS, LLM)를 붙일 때 이 클래스만 바꾸면 된다.
class_name GleoVoice
extends Node

var enabled := true
var _voice_id := ""


func _ready() -> void:
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		enabled = false
		return
	var voices := DisplayServer.tts_get_voices_for_language("ko")
	if voices.is_empty():
		enabled = false
		return
	_voice_id = voices[0]


func say(text: String) -> void:
	if not enabled or _voice_id == "":
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, _voice_id)
