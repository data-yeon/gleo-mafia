## 코드로 그리는 단순 벡터 아이콘. 외부 아이콘 파일 없이 쓴다.
## icon: turn_left, turn_right, straight, uturn, home, nav, music, phone, gleo, apps, settings,
##       fan, seat, compass, plus, minus, route, mic, warning, flag, signal, wifi, battery, wheel, phone_call, police,
##       person(용의자 실루엣), sms(문자 말풍선)
class_name PleosIcon
extends Control

@export var icon := "nav":
	set(v):
		icon = v
		queue_redraw()
@export var color := PleosTheme.TEXT:
	set(v):
		color = v
		queue_redraw()
@export var stroke := 4.0
var _t := 0.0


static func make(name: String, px: float, col: Color) -> PleosIcon:
	var i := PleosIcon.new()
	i.icon = name
	i.color = col
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _process(delta: float) -> void:
	if icon == "gleo":
		_t += delta
		queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size / 2.0
	var u := s / 24.0                       # 24단위 격자 기준
	var w := maxf(1.5, stroke * s / 40.0)
	match icon:
		"turn_right", "turn_left":
			var k := 1.0 if icon == "turn_right" else -1.0
			var pts := PackedVector2Array([c + Vector2(-4 * k, 10) * u, c + Vector2(-4 * k, -1) * u,
					c + Vector2(6 * k, -1) * u])
			draw_polyline(pts, color, w * 1.6, true)
			_arrow_head(c + Vector2(9 * k, -1) * u, Vector2(k, 0), u * 5.5)
		"straight":
			draw_line(c + Vector2(0, 10) * u, c + Vector2(0, -4) * u, color, w * 1.6, true)
			_arrow_head(c + Vector2(0, -9) * u, Vector2(0, -1), u * 5.5)
		"uturn":
			draw_arc(c + Vector2(0, -2) * u, 5 * u, PI, TAU, 16, color, w * 1.6, true)
			draw_line(c + Vector2(5, -2) * u, c + Vector2(5, 9) * u, color, w * 1.6, true)
			draw_line(c + Vector2(-5, -2) * u, c + Vector2(-5, 4) * u, color, w * 1.6, true)
			_arrow_head(c + Vector2(-5, 9) * u, Vector2(0, 1), u * 5.0)
		"home":
			draw_polyline(PackedVector2Array([c + Vector2(-8, -1) * u, c + Vector2(0, -8) * u,
					c + Vector2(8, -1) * u]), color, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-6, -2) * u, c + Vector2(-6, 8) * u,
					c + Vector2(6, 8) * u, c + Vector2(6, -2) * u]), color, w, true)
		"nav":
			var tri := PackedVector2Array([c + Vector2(0, -9) * u, c + Vector2(7, 8) * u,
					c + Vector2(0, 4) * u, c + Vector2(-7, 8) * u])
			draw_colored_polygon(tri, color)
		"music":
			draw_circle(c + Vector2(-4, 6) * u, 3 * u, color)
			draw_line(c + Vector2(-1.2, 6) * u, c + Vector2(-1.2, -8) * u, color, w, true)
			draw_line(c + Vector2(-1.2, -8) * u, c + Vector2(6, -5) * u, color, w, true)
		"phone", "phone_call":
			draw_arc(c, 8 * u, PI * 0.65, PI * 1.6, 20, color, w * 1.4, true)
			draw_circle(c + Vector2(-6.2, 5.2) * u, 2.2 * u, color)
			draw_circle(c + Vector2(-1.6, -7.8) * u, 2.2 * u, color)
		"gleo":
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(c, 10 * u, Color(0.42, 0.55, 1.0, 0.25 + 0.15 * pulse))
			draw_circle(c, 7.5 * u, Color(0.36, 0.48, 1.0, 0.55))
			draw_circle(c + Vector2(-1.5, -1.5) * u, 5 * u, Color(0.55, 0.85, 1.0, 0.9))
			draw_circle(c + Vector2(1.8, 1.5) * u, 3.8 * u, Color(0.7, 0.55, 1.0, 0.75))
		"apps":
			for ix in range(3):
				for iy in range(3):
					draw_circle(c + Vector2((ix - 1) * 6, (iy - 1) * 6) * u, 1.9 * u, color)
		"settings":
			for k2 in range(8):
				var a := k2 * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 6 * u, c + Vector2(cos(a), sin(a)) * 9.5 * u,
						color, w * 1.4, true)
			draw_arc(c, 6 * u, 0, TAU, 24, color, w, true)
			draw_arc(c, 2.5 * u, 0, TAU, 16, color, w, true)
		"fan":
			for k3 in range(3):
				var a2 := k3 * TAU / 3.0 - PI / 2.0
				var p := c + Vector2(cos(a2), sin(a2)) * 4.5 * u
				draw_circle(p, 3.6 * u, color)
			draw_circle(c, 2 * u, PleosTheme.SURFACE)
		"seat":
			draw_polyline(PackedVector2Array([c + Vector2(-3, -9) * u, c + Vector2(-5, 3) * u,
					c + Vector2(6, 3) * u, c + Vector2(7, 8) * u]), color, w * 1.4, true)
			draw_line(c + Vector2(-5, 3) * u, c + Vector2(-5, 8) * u, color, w * 1.4, true)
		"compass":
			draw_arc(c, 9 * u, 0, TAU, 32, color, w, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7) * u, c + Vector2(3, 1) * u,
					c + Vector2(-3, 1) * u]), PleosTheme.DANGER)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 7) * u, c + Vector2(3, 1) * u,
					c + Vector2(-3, 1) * u]), color)
		"plus":
			draw_line(c + Vector2(-7, 0) * u, c + Vector2(7, 0) * u, color, w * 1.3, true)
			draw_line(c + Vector2(0, -7) * u, c + Vector2(0, 7) * u, color, w * 1.3, true)
		"minus":
			draw_line(c + Vector2(-7, 0) * u, c + Vector2(7, 0) * u, color, w * 1.3, true)
		"route":
			draw_polyline(PackedVector2Array([c + Vector2(-6, 8) * u, c + Vector2(-6, 0) * u,
					c + Vector2(6, -2) * u, c + Vector2(6, -8) * u]), color, w * 1.2, true)
			draw_circle(c + Vector2(-6, 8) * u, 2.5 * u, color)
			draw_circle(c + Vector2(6, -8) * u, 2.5 * u, color)
		"mic":
			var r := Rect2(c + Vector2(-3.5, -9) * u, Vector2(7, 12) * u)
			draw_rect(r, color)
			draw_circle(c + Vector2(0, -9) * u, 3.5 * u, color)
			draw_circle(c + Vector2(0, 3) * u, 3.5 * u, color)
			draw_arc(c + Vector2(0, 0) * u, 7 * u, 0.15, PI - 0.15, 16, color, w, true)
			draw_line(c + Vector2(0, 7) * u, c + Vector2(0, 10) * u, color, w, true)
		"warning":
			var tri2 := PackedVector2Array([c + Vector2(0, -9) * u, c + Vector2(10, 8) * u,
					c + Vector2(-10, 8) * u])
			draw_colored_polygon(tri2, color)
			draw_line(c + Vector2(0, -3) * u, c + Vector2(0, 3) * u, PleosTheme.SURFACE, w * 1.2, true)
			draw_circle(c + Vector2(0, 5.6) * u, 1.2 * u, PleosTheme.SURFACE)
		"flag":
			draw_line(c + Vector2(-6, -9) * u, c + Vector2(-6, 10) * u, color, w * 1.2, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -9) * u, c + Vector2(8, -5) * u,
					c + Vector2(-6, 0) * u]), color)
		"signal":
			for k4 in range(4):
				var h := (k4 + 1) * 4.0
				draw_rect(Rect2(c + Vector2(-8 + k4 * 4.5, 9 - h) * u, Vector2(3, h) * u), color)
		"wifi":
			for k5 in range(3):
				draw_arc(c + Vector2(0, 7) * u, (4 + k5 * 4.5) * u, PI * 1.25, PI * 1.75, 12, color, w, true)
			draw_circle(c + Vector2(0, 7) * u, 1.6 * u, color)
		"battery":
			draw_rect(Rect2(c + Vector2(-10, -5) * u, Vector2(18, 10) * u), color, false, w)
			draw_rect(Rect2(c + Vector2(-8, -3) * u, Vector2(12, 6) * u), color)
			draw_rect(Rect2(c + Vector2(8.5, -2) * u, Vector2(2, 4) * u), color)
		"wheel":
			draw_arc(c, 9 * u, 0, TAU, 32, color, w * 1.2, true)
			draw_circle(c, 2.5 * u, color)
			draw_line(c + Vector2(-9, 0) * u, c + Vector2(-2.5, 0) * u, color, w * 1.2, true)
			draw_line(c + Vector2(9, 0) * u, c + Vector2(2.5, 0) * u, color, w * 1.2, true)
			draw_line(c + Vector2(0, 2.5) * u, c + Vector2(0, 9) * u, color, w * 1.2, true)
		"police":
			draw_rect(Rect2(c + Vector2(-9, -1) * u, Vector2(18, 7) * u), color)
			draw_rect(Rect2(c + Vector2(-5, -5) * u, Vector2(10, 4) * u), color)
			draw_rect(Rect2(c + Vector2(-5, -8) * u, Vector2(5, 3) * u), PleosTheme.SIREN_RED)
			draw_rect(Rect2(c + Vector2(0, -8) * u, Vector2(5, 3) * u), PleosTheme.SIREN_BLUE)
			draw_circle(c + Vector2(-5, 7) * u, 2.2 * u, PleosTheme.TEXT)
			draw_circle(c + Vector2(5, 7) * u, 2.2 * u, PleosTheme.TEXT)
		"person":
			draw_circle(c + Vector2(0, -4.5) * u, 4.6 * u, color)
			var body := PackedVector2Array()
			for i in 17:
				var a := PI + PI * float(i) / 16.0
				body.append(c + Vector2(cos(a) * 9.0, 10.5 + sin(a) * 9.5) * u)
			draw_colored_polygon(body, color)
		"sms":
			draw_rect(Rect2(c + Vector2(-9, -7) * u, Vector2(18, 12) * u), color, false, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 5) * u, c + Vector2(-1, 5) * u,
					c + Vector2(-6, 9) * u]), color)
			for k in 3:
				draw_circle(c + Vector2(-4.5 + k * 4.5, -1) * u, 1.3 * u, color)
		_:
			draw_circle(c, 6 * u, color)


func _arrow_head(tip: Vector2, dir: Vector2, length: float) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * length + n * length * 0.75,
			tip - dir * length - n * length * 0.75]), color)
