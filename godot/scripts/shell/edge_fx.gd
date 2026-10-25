## 화면 가장자리 연출(지도·주행 패널 위에 덮는 투명 층, 누름은 통과).
## - siren: 출동 중 빨강·파랑 빛이 가장자리에서 번갈아 은은하게(1.6Hz, 12~16%)
## - final_k: 최종 단계 붉은 테두리가 천천히 숨 쉰다(0..1)
## - viewfinder(): 현장 확인(잠복) 순간 카메라 뷰파인더 모서리 + "● 현장 확인" 1.4초
## 멀미를 생각해 화면 흔들기나 번쩍임은 쓰지 않는다.
class_name EdgeFx
extends Control

var siren := false
var final_k := 0.0
var _t := 0.0
var _vf := 0.0
var _vf_text := ""
var _was_active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func viewfinder(text := "● 현장 확인") -> void:
	_vf = 1.4
	_vf_text = text


func _process(delta: float) -> void:
	_t += delta
	_vf = maxf(0.0, _vf - delta)
	var active := siren or final_k > 0.001 or _vf > 0.0
	if active or _was_active:
		queue_redraw()
	_was_active = active


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if siren:
		var red_left := sin(_t * TAU * 0.8) > 0.0
		_band(r, PleosTheme.SIREN_RED if red_left else PleosTheme.SIREN_BLUE, 0.16, [true, true, false, false])
		_band(r, PleosTheme.SIREN_BLUE if red_left else PleosTheme.SIREN_RED, 0.16, [false, false, true, true])
	if final_k > 0.001:
		var k := final_k * (0.55 + 0.45 * sin(_t * 2.4))
		_band(r, PleosTheme.DANGER, 0.14 * k, [true, true, true, true])
	if _vf > 0.0:
		var a := clampf(_vf / 0.4, 0.0, 1.0)
		var inset := 26.0
		var l := 54.0
		var col := Color(1, 1, 1, 0.9 * a)
		var corners := [r.position + Vector2(inset, inset), Vector2(r.end.x - inset, r.position.y + inset),
				r.end - Vector2(inset, inset), Vector2(r.position.x + inset, r.end.y - inset)]
		var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		for i in 4:
			var c: Vector2 = corners[i]
			var d: Vector2 = dirs[i]
			draw_line(c, c + Vector2(d.x * l, 0), col, 5.0)
			draw_line(c, c + Vector2(0, d.y * l), col, 5.0)
		var font := get_theme_default_font()
		draw_rect(Rect2(r.position + Vector2(inset + 14, inset + 12), Vector2(150, 34)), Color(0, 0, 0, 0.45 * a))
		draw_string(font, r.position + Vector2(inset + 24, inset + 37), _vf_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				Color(1.0, 0.35, 0.35, a))


## 가장자리 안쪽으로 옅어지는 띠. sides: [왼, 위, 오른, 아래]
func _band(r: Rect2, col: Color, alpha: float, sides: Array) -> void:
	var n := 14
	var step := 4.0
	for i in n:
		var a := alpha * (1.0 - float(i) / n)
		var c := Color(col, a)
		var o := i * step
		if sides[0]:
			draw_rect(Rect2(r.position.x + o, r.position.y, step, r.size.y), c)
		if sides[1]:
			draw_rect(Rect2(r.position.x, r.position.y + o, r.size.x, step), c)
		if sides[2]:
			draw_rect(Rect2(r.end.x - o - step, r.position.y, step, r.size.y), c)
		if sides[3]:
			draw_rect(Rect2(r.position.x, r.end.y - o - step, r.size.x, step), c)
