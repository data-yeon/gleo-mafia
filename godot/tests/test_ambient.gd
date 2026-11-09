## 주행 소리 층(AmbientFx) 헤드리스 테스트.
##   godot --headless --path godot --script res://tests/test_ambient.gd
## - 속도에 따라 커지고, 정차 중엔 거의 사라진다
## - 터널 안은 울림(wet)이 걸리고 웅웅이 커진다
## - 음성이 나오면 낮아졌다가 끝나면 돌아온다
## - 효과음 끄기(M)를 따른다, 켜기 `enabled=false`도 마찬가지
## - 방향지시등은 좌·우회전이 가까울 때만(직진·정차·먼 회전은 꺼짐)
## - 잡음 루프 이음매가 튀지 않는다
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
	var sfx := Sfx.new()
	root.add_child(sfx)
	var fx := AmbientFx.new()
	fx.sfx = sfx
	root.add_child(fx)
	await process_frame

	# 정차 중: 거의 안 들린다
	fx.update(1.0, 0.0, false, true, "", 0.0, 3.0)
	_check(fx._rumble.volume_db < -45.0, "정차 중 웅웅이 작다(%.1fdB)" % fx._rumble.volume_db)
	# 60km/h: 만점 크기
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	_check(absf(fx._rumble.volume_db - AmbientFx.RUMBLE_MAX_DB) < 0.5, "60km/h 웅웅 크기(%.1fdB)" % fx._rumble.volume_db)
	_check(absf(fx._hiss.volume_db - AmbientFx.HISS_MAX_DB) < 0.5, "60km/h 쉬익 크기(%.1fdB)" % fx._hiss.volume_db)
	var full_db: float = fx._rumble.volume_db
	var slow_db := _db_at(fx, 20.0)
	_check(slow_db < full_db - 3.0, "느릴수록 작다(20km/h %.1fdB, 60km/h %.1fdB)" % [slow_db, full_db])
	# 재생 중인지
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	_check(fx._rumble.playing and fx._hiss.playing, "달리는 중에는 두 겹 모두 재생")

	# 터널: 웅웅 +3dB, 울림 켜짐
	var open_db := fx._rumble.volume_db
	fx.update(1.0, 60.0, true, false, "", 0.0, 3.0)
	_check(fx._rumble.volume_db > open_db + 2.0, "터널 안 웅웅이 커진다")
	var rv := AudioServer.get_bus_effect(AudioServer.get_bus_index(AmbientFx.BUS), 0) as AudioEffectReverb
	_check(rv != null and rv.wet > 0.3, "터널 안 울림(wet %.2f)" % (rv.wet if rv != null else -1.0))
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	_check(rv.wet < 0.05, "터널을 나오면 울림이 사라진다")

	# 덕킹: 음성이 나오면 낮아지고, 끝나면 돌아온다
	var before := fx._rumble.volume_db
	fx.duck(2.0)
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	_check(fx._rumble.volume_db < before - 6.0, "음성이 나오면 낮아진다(%.1f → %.1f)" % [before, fx._rumble.volume_db])
	fx._clock += 3.0
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	_check(absf(fx._rumble.volume_db - before) < 1.0, "음성이 끝나면 돌아온다")

	# 방향지시등
	fx.update(0.1, 40.0, false, false, "turn_left", 50.0, 3.0)
	_check(fx._blink, "왼쪽 회전 50m 앞이면 켜진다")
	fx.update(0.1, 40.0, false, false, "turn_right", 50.0, 3.0)
	_check(fx._blink, "오른쪽 회전도 켜진다")
	fx.update(0.1, 40.0, false, false, "straight", 50.0, 3.0)
	_check(not fx._blink, "직진이면 꺼진다")
	fx.update(0.1, 40.0, false, false, "turn_left", 900.0, 3.0)
	_check(not fx._blink, "회전이 멀면 꺼진다")
	fx.update(0.1, 40.0, false, true, "turn_left", 50.0, 3.0)
	_check(not fx._blink, "정차 중이면 꺼진다")
	fx.update(0.1, 40.0, false, false, "flag", 50.0, 3.0)
	_check(not fx._blink, "도착 안내(flag)에는 안 켜진다")

	# 효과음 끄기(M)
	sfx.set_muted(true)
	fx.update(1.0, 60.0, false, false, "turn_left", 50.0, 3.0)
	_check(fx._rumble.volume_db < -65.0 and not fx._blink, "효과음을 끄면 조용하고 지시등도 꺼진다")
	sfx.set_muted(false)
	fx.enabled = false
	fx.update(1.0, 60.0, false, false, "", 0.0, 3.0)
	_check(fx._rumble.volume_db < -65.0, "enabled=false면 조용")
	fx.enabled = true

	# 루프 이음매: 끝과 처음 샘플 차이가 크지 않다
	for pair in [["웅웅", AmbientFx._s_rumble], ["쉬익", AmbientFx._s_hiss]]:
		var d: PackedByteArray = (pair[1] as AudioStreamWAV).data
		var n := d.size() / 2
		var first := d.decode_s16(0)
		var last := d.decode_s16((n - 1) * 2)
		# 이음매(끝→처음) 차이가 평소 이웃 샘플 차이의 4배를 넘지 않으면 튀지 않는 것
		var sum_adj := 0.0
		var cnt := 0
		for i in range(1, n, 7):
			sum_adj += absf(float(d.decode_s16(i * 2) - d.decode_s16((i - 1) * 2)))
			cnt += 1
		var mean_adj := sum_adj / cnt
		_check(absi(first - last) < mean_adj * 4.0, "%s 루프 이음매(차이 %d, 평소 이웃 차이 %.0f)" % [pair[0], absi(first - last), mean_adj])
	print("소리 층 확인 %d개, 실패 %d개" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _db_at(fx: AmbientFx, kmh: float) -> float:
	fx.update(1.0, kmh, false, false, "", 0.0, 3.0)
	return fx._rumble.volume_db
