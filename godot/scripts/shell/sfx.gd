## 효과음: 시작할 때 코드로 합성한다(AudioStreamWAV 16bit 22kHz). 소리 파일·임포트가 없고 헤드리스에서도 안전하다.
## res://assets/sfx/<이름>.wav가 있으면 그 파일을 대신 쓴다(나중에 실제 소리로 바꾸기 쉽게).
## 이름: alert(첩보 알림) ping(핀) ring(연결음) click(연결) hangup(통화 종료) static(잡음) radio(무전)
##       siren(사이렌, 반복) stamp(도장) doubt(의심) win fail tick(째깍) heart(심장, 반복) shutter(카메라) alarm(경보)
class_name Sfx
extends Node

const RATE := 22050
const VOICES := 6

var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _loops := {}                  # 이름 → 반복 재생 중인 플레이어


func _ready() -> void:
	_build()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if muted or not _streams.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## 반복 소리(사이렌, 심장) 켜고 끄기
func loop(name: String, on: bool, vol_db := -4.0) -> void:
	if on:
		if _loops.has(name) or muted or not _streams.has(name):
			return
		var p := AudioStreamPlayer.new()
		p.stream = _streams[name]
		p.volume_db = vol_db
		add_child(p)
		p.play()
		_loops[name] = p
	elif _loops.has(name):
		var p2: AudioStreamPlayer = _loops[name]
		_loops.erase(name)
		p2.stop()
		p2.queue_free()


func is_looping(name: String) -> bool:
	return _loops.has(name)


func set_muted(m: bool) -> void:
	muted = m
	if m:
		for k in _loops.keys():
			loop(String(k), false)
		for p in _players:
			p.stop()


# ---------------------------------------------------------------- 합성

func _build() -> void:
	var alert := _buf(0.62)
	for i in 3:
		_tone(alert, [740.0, 988.0, 1318.0][i], 0.06 + i * 0.12, 0.26, 0.32, 0.004, 6.0)
	_add("alert", alert)

	var ping := _buf(0.3)
	_tone(ping, 1568.0, 0.0, 0.28, 0.25, 0.002, 14.0)
	_tone(ping, 3136.0, 0.0, 0.12, 0.06, 0.002, 20.0)
	_add("ping", ping)

	# 연결음(뚜르르): 440+480Hz, 0.9초
	var ring := _buf(1.1)
	_tone(ring, 440.0, 0.0, 0.9, 0.16, 0.02, 0.0)
	_tone(ring, 480.0, 0.0, 0.9, 0.16, 0.02, 0.0)
	_add("ring", ring)

	var click := _buf(0.12)
	_noise(click, 0.0, 0.012, 0.35)
	_tone(click, 2000.0, 0.012, 0.05, 0.18, 0.002, 40.0)
	_add("click", click)

	# 통화 종료(뚜뚜)
	var hang := _buf(0.62)
	for k in 2:
		_tone(hang, 480.0, k * 0.3, 0.17, 0.14, 0.005, 0.0)
		_tone(hang, 620.0, k * 0.3, 0.17, 0.14, 0.005, 0.0)
	_add("hangup", hang)

	var stat := _buf(0.7)
	_noise(stat, 0.0, 0.7, 0.22, true)
	_add("static", stat)

	var radio := _buf(0.42)
	_noise(radio, 0.0, 0.07, 0.3)
	_tone(radio, 1250.0, 0.07, 0.09, 0.2, 0.003, 4.0)
	_noise(radio, 0.18, 0.22, 0.12, true)
	_add("radio", radio)

	# 사이렌: 650 → 1250 → 650Hz 1.2초, 반복
	var siren := _buf(1.2)
	var ph := 0.0
	for i in siren.size():
		var t := float(i) / RATE
		var f := 650.0 + 600.0 * (0.5 - 0.5 * cos(TAU * t / 1.2))
		ph += TAU * f / RATE
		siren[i] += (sin(ph) + 0.3 * sin(ph * 3.0)) * 0.13
	_add("siren", siren, true)

	# 도장(쿵): 120 → 45Hz로 떨어지는 낮은 소리 + 딱
	var stamp := _buf(0.42)
	var ph2 := 0.0
	for i2 in stamp.size():
		var t2 := float(i2) / RATE
		var f2 := 45.0 + 75.0 * exp(-t2 * 18.0)
		ph2 += TAU * f2 / RATE
		stamp[i2] += sin(ph2) * 0.9 * exp(-t2 * 9.0)
	_noise(stamp, 0.0, 0.025, 0.5)
	_add("stamp", stamp)

	var doubt := _buf(0.6)
	_tone(doubt, 466.0, 0.0, 0.5, 0.2, 0.01, 3.0, true)
	_tone(doubt, 494.0, 0.0, 0.5, 0.2, 0.01, 3.0, true)
	_add("doubt", doubt)

	var win := _buf(0.95)
	for j in 4:
		_tone(win, [523.0, 659.0, 784.0, 1046.0][j], j * 0.1, 0.55 - j * 0.05, 0.22, 0.005, 4.0)
	_add("win", win)

	var fail := _buf(1.0)
	for j2 in 3:
		_tone(fail, [392.0, 330.0, 262.0][j2], j2 * 0.2, 0.5, 0.22, 0.01, 3.0, true)
	_add("fail", fail)

	var tick := _buf(0.06)
	_tone(tick, 2500.0, 0.0, 0.03, 0.22, 0.001, 60.0)
	_add("tick", tick)

	# 심장(쿵쿵), 0.9초 반복
	var heart := _buf(0.9)
	_thump(heart, 0.0, 58.0, 0.7)
	_thump(heart, 0.2, 52.0, 0.55)
	_add("heart", heart, true)

	var shutter := _buf(0.16)
	_noise(shutter, 0.0, 0.03, 0.4)
	_noise(shutter, 0.07, 0.04, 0.3)
	_add("shutter", shutter)

	var alarm := _buf(1.0)
	for k2 in 4:
		_tone(alarm, 880.0 if k2 % 2 == 0 else 660.0, k2 * 0.25, 0.22, 0.16, 0.005, 0.0, true)
	_add("alarm", alarm)


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	b.fill(0.0)
	return b


## 사인파(또는 삼각파) 한 음: start초부터 dur초, 짧은 어택 + 지수 감쇠(decay=0이면 일정, 끝에 짧은 릴리스)
func _tone(b: PackedFloat32Array, freq: float, start: float, dur: float, amp: float, attack: float, decay: float,
		tri := false) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / maxf(attack, 0.0005)) * (exp(-t * decay) if decay > 0.0 else 1.0)
		env *= minf(1.0, (dur - t) / 0.01)
		var x := freq * t
		var v := (4.0 * absf(x - floorf(x + 0.5)) - 1.0) if tri else sin(TAU * x)
		b[i0 + i] += v * amp * env


func _noise(b: PackedFloat32Array, start: float, dur: float, amp: float, crackle := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var i0 := int(start * RATE)
	var n := mini(int(dur * RATE), b.size() - i0)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var env := minf(1.0, (dur - t) / 0.02)
		if crackle:
			env *= 0.4 + 0.6 * absf(sin(t * 37.0) * sin(t * 11.0))
		b[i0 + i] += lp * amp * env


func _thump(b: PackedFloat32Array, start: float, freq: float, amp: float) -> void:
	var i0 := int(start * RATE)
	var n := mini(int(0.16 * RATE), b.size() - i0)
	for i in n:
		var t := float(i) / RATE
		b[i0 + i] += sin(TAU * freq * t) * amp * exp(-t * 22.0) * minf(1.0, t / 0.004)


func _add(name: String, b: PackedFloat32Array, looped := false) -> void:
	var path := "res://assets/sfx/%s.wav" % name
	if ResourceLoader.exists(path):
		_streams[name] = load(path)
		return
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = b.size()
	_streams[name] = w
