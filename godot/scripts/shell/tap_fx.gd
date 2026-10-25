## 누른 곳 표시(시연 영상·자동 실행용): 손가락 점 + 퍼지는 고리. 화면 맨 위에 그리고 누르기는 막지 않는다.
class_name TapFx
extends Control

const LIFE := 0.6

var _taps: Array = []             # [{p, t}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func ripple(global_pos: Vector2) -> void:
	_taps.append({"p": get_global_transform().affine_inverse() * global_pos, "t": 0.0})
	queue_redraw()


func _process(delta: float) -> void:
	if _taps.is_empty():
		return
	for tp in _taps:
		tp["t"] = float(tp["t"]) + delta
	_taps = _taps.filter(func(tp): return float(tp["t"]) < LIFE)
	queue_redraw()


func _draw() -> void:
	for tp in _taps:
		var k := float(tp["t"]) / LIFE
		var p: Vector2 = tp["p"]
		var a := 1.0 - k
		draw_circle(p, 20.0 + 36.0 * k, Color(0.18, 0.42, 1.0, 0.18 * a), true, -1.0, true)
		draw_arc(p, 20.0 + 36.0 * k, 0, TAU, 48, Color(0.18, 0.42, 1.0, 0.85 * a), 3.0, true)
		if k < 0.55:
			draw_circle(p, 13.0, Color(1, 1, 1, 0.9), true, -1.0, true)
			draw_circle(p, 10.0, Color(0.18, 0.42, 1.0, 0.9), true, -1.0, true)
