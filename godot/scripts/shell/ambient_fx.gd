## 주행 소리 층. 코드로 합성하므로 소리 파일이 없다(Sfx와 같은 방식). 효과음 끄기(M)를 따른다.
## - 길·바람 소음 두 겹: 낮은 웅웅(rumble)과 중간 음역 쉬익(hiss). 속도가 오르면 커지고, 멈추면 거의 사라진다.
## - 터널 안: 울림(리버브)이 걸리고 웅웅이 커진다.
## - 회전 앞: 방향지시등 틱-톡(좌·우회전만). 켜는 거리는 배속을 반영해 실제 약 4초 전이다.
## - 제보자 음성이 나오는 동안 전체를 낮춰(덕킹) 말이 묻히지 않게 한다.
## 소리가 크거나 작으면 BASE_DB(전체)나 RUMBLE_MAX_DB·HISS_MAX_DB를 고친다.
class_name AmbientFx
extends Node

const RATE := 22050
const BUS := "Ambient"
const BASE_DB := 0.0
const RUMBLE_MAX_DB := -27.0      # 60km/h 이상일 때 웅웅 크기(만점 0dB 기준)
const HISS_MAX_DB := -33.0        # 60km/h 이상일 때 쉬익 크기
const SILENT_DB := -70.0
const DUCK_DB := -9.0             # 음성이 나올 때 낮추는 양
const BLINK_GAP_S := 0.34         # 틱과 톡 사이(실제 초)
const BLINK_DB := -20.0

var enabled := true
var sfx: Sfx                      # 효과음 끄기 상태를 따라간다

var _rumble: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _tick: AudioStreamPlayer
var _tock: AudioStreamPlayer
var _bus := -1
var _rumble_db := SILENT_DB
var _hiss_db := SILENT_DB
var _target_rumble := SILENT_DB
var _target_hiss := SILENT_DB
var _duck := 0.0                  # 0이면 그대로, 1이면 DUCK_DB만큼 낮춤
var _duck_target := 0.0
var _duck_until := 0.0
var _tunnel_k := 0.0
var _tunnel_target := 0.0
var _blink := false
var _blink_t := 0.0
var _blink_phase := false
var _clock := 0.0


static var _s_rumble: AudioStreamWAV     # 합성은 프로세스당 한 번만(셸을 다시 만들어도 재사용)
static var _s_hiss: AudioStreamWAV
static var _s_tick: AudioStreamWAV
static var _s_tock: AudioStreamWAV


func _ready() -> void:
	_setup_bus()
	if _s_rumble == null:
		_s_rumble = _loop_noise(6.0, 0.0, 70.0, 1.0)
		_s_hiss = _loop_noise(6.0, 260.0, 1100.0, 0.9)
		_s_tick = _click(2100.0)
		_s_tock = _click(1500.0)
	_rumble = _make_player(_s_rumble, -80.0)
	_hiss = _make_player(_s_hiss, -80.0)
	_tick = _make_player(_s_tick, BLINK_DB, "Master")
	_tock = _make_player(_s_tock, BLINK_DB - 2.0, "Master")


## 한 프레임마다 부른다. speed_kmh 현재 속도, in_tunnel 터널 안인지, stopped 정차 중인지,
## turn_icon·turn_dist 다음 회전(없으면 ""), playback 배속
func update(delta: float, speed_kmh: float, in_tunnel: bool, stopped: bool, turn_icon: String,
		turn_dist: float, playback: float) -> void:
	_clock += delta
	var run := 0.0 if stopped else clampf(speed_kmh / 60.0, 0.0, 1.0)
	var on := enabled and not (sfx != null and sfx.muted)
	_target_rumble = lerpf(-50.0, RUMBLE_MAX_DB, run) + (3.0 if in_tunnel else 0.0) if on else SILENT_DB
	_target_hiss = lerpf(-58.0, HISS_MAX_DB, pow(run, 1.3)) + (2.0 if in_tunnel else 0.0) if on else SILENT_DB
	if stopped and on:
		_target_rumble = -52.0
		_target_hiss = -66.0
	_tunnel_target = 1.0 if in_tunnel else 0.0
	# 방향지시등: 회전 앞 약 4초(실제), 60~300m. 정차 중이거나 직진이면 끈다
	var mps := speed_kmh / 3.6 * maxf(playback, 0.0)
	var reach := clampf(mps * 4.0, 60.0, 300.0)
	_blink = on and not stopped and (turn_icon == "turn_left" or turn_icon == "turn_right") \
			and turn_dist > 0.0 and turn_dist < reach
	if _duck_until > 0.0 and _clock >= _duck_until:
		_duck_until = 0.0
		_duck_target = 0.0
	_apply(delta)


## 제보자 음성이 나오는 동안(초) 소리 층을 낮춘다.
func duck(seconds: float) -> void:
	_duck_target = 1.0
	_duck_until = _clock + seconds


func _apply(delta: float) -> void:
	var k := clampf(delta * 2.5, 0.0, 1.0)
	_rumble_db = lerpf(_rumble_db, _target_rumble, k)
	_hiss_db = lerpf(_hiss_db, _target_hiss, k)
	_duck = lerpf(_duck, _duck_target, clampf(delta * 6.0, 0.0, 1.0))
	_tunnel_k = lerpf(_tunnel_k, _tunnel_target, clampf(delta * 3.0, 0.0, 1.0))
	var duck_db := DUCK_DB * _duck
	_rumble.volume_db = maxf(_rumble_db + BASE_DB + duck_db, -80.0)
	_hiss.volume_db = maxf(_hiss_db + BASE_DB + duck_db, -80.0)
	_set_playing(_rumble, _rumble_db > -65.0)
	_set_playing(_hiss, _hiss_db > -65.0)
	if _bus >= 0:
		var rv := AudioServer.get_bus_effect(_bus, 0) as AudioEffectReverb
		if rv != null:
			rv.wet = 0.38 * _tunnel_k
			rv.dry = 1.0 - 0.15 * _tunnel_k
	if _blink:
		_blink_t -= delta
		if _blink_t <= 0.0:
			_blink_t = BLINK_GAP_S
			_blink_phase = not _blink_phase
			(_tick if _blink_phase else _tock).play()
	else:
		_blink_t = 0.0
		_blink_phase = false


func _set_playing(p: AudioStreamPlayer, want: bool) -> void:
	if want and not p.playing:
		p.play()
	elif not want and p.playing:
		p.stop()


func _setup_bus() -> void:
	_bus = AudioServer.get_bus_index(BUS)
	if _bus != -1:
		return
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, BUS)
	AudioServer.set_bus_send(_bus, "Master")
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.85
	rv.damping = 0.6
	rv.wet = 0.0
	rv.dry = 1.0
	AudioServer.add_bus_effect(_bus, rv)


func _make_player(stream: AudioStream, db: float, bus := BUS) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = bus
	add_child(p)
	return p


## 이어 붙여도 끊김 없는 잡음 루프. low_hz가 0이면 high_hz 아래 저역만, 아니면 low_hz~high_hz 사이 중역.
## 같은 흰 잡음을 두 번 돌려(두 번째 바퀴만 기록) 끝과 처음의 필터 상태를 맞춘다.
static func _loop_noise(sec: float, low_hz: float, high_hz: float, peak: float) -> AudioStreamWAV:
	var n := int(sec * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + int(high_hz)
	var white := PackedFloat32Array()
	white.resize(n)
	for i in n:
		white[i] = rng.randf_range(-1.0, 1.0)
	var a_hi := 1.0 - exp(-TAU * high_hz / RATE)
	var a_lo := 1.0 - exp(-TAU * maxf(low_hz, 1.0) / RATE)
	var hi1 := 0.0
	var hi2 := 0.0
	var lo1 := 0.0
	var lo2 := 0.0
	var out := PackedFloat32Array()
	out.resize(n)
	for pass_i in 2:
		for j in n:
			hi1 += a_hi * (white[j] - hi1)
			hi2 += a_hi * (hi1 - hi2)
			lo1 += a_lo * (white[j] - lo1)
			lo2 += a_lo * (lo1 - lo2)
			if pass_i == 1:
				out[j] = hi2 if low_hz <= 0.0 else hi2 - lo2
	var mx := 0.0001
	for v in out:
		mx = maxf(mx, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for m in n:
		bytes.encode_s16(m * 2, int(clampf(out[m] / mx * peak, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


## 방향지시등 릴레이 소리: 짧은 딱 + 공명
static func _click(freq: float) -> AudioStreamWAV:
	var n := int(0.07 * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 90.0)
		var v := (sin(TAU * freq * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.25) * env
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
