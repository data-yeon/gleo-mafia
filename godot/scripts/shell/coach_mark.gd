## 코치 마크: 화면을 어둡게 하고 눌러야 할 곳만 밝게 뚫는다(스포트라이트) + 화살표 + 말풍선.
## 누르기는 막지 않는다(그 아래 화면이 그대로 받는다). 다른 행동을 막는 것은 Tutorial이 한다.
## - show_step(target, text, button): target은 화면(전역) 좌표 Rect2를 돌려주는 Callable(매 프레임 다시 잰다).
##   button이 있으면 말풍선에 [다음] 같은 버튼이 붙고 눌리면 next를 낸다.
## - tip(text, target): 어둡게 하지 않는 작은 말풍선(처음 겪는 규칙 한 번 알림), 몇 초 뒤 사라진다.
class_name CoachMark
extends Control

signal next

const DIM := Color(0.06, 0.08, 0.12, 0.5)
const RING := Color("ffb020")

var active := false
var _target: Callable
var _beside: Callable             # 있으면 말풍선을 이 사각형(카드) 왼쪽에 둔다(카드 내용을 가리지 않게)
var _hole := Rect2()
var _t := 0.0
var _bubble: PanelContainer
var _label: Label
var _btn: Button
var _tip_until := 0.0
var _is_tip := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", PleosTheme.box(Color("1f2633"), 18, 16, true))
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bubble)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_bubble.add_child(col)
	_label = PleosTheme.label("", "BodyStrong")
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(360, 0)
	col.add_child(_label)
	_btn = Button.new()
	_btn.theme_type_variation = "PrimaryButton"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.custom_minimum_size = Vector2(0, 50)
	_btn.pressed.connect(func(): next.emit())
	col.add_child(_btn)
	visible = false


func show_step(target: Callable, text: String, button := "", beside := Callable()) -> void:
	active = true
	_is_tip = false
	_target = target
	_beside = beside
	_label.text = text
	_btn.text = button
	_btn.visible = button != ""
	_t = 0.0
	visible = true
	_bubble.reset_size()
	queue_redraw()


func tip(text: String, target: Callable, sec := 5.0) -> void:
	if active and not _is_tip:
		return
	active = true
	_is_tip = true
	_target = target
	_beside = Callable()
	_label.text = text
	_btn.visible = false
	_tip_until = sec
	visible = true
	_bubble.reset_size()


func clear() -> void:
	active = false
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _is_tip:
		_tip_until -= delta
		if _tip_until <= 0.0:
			clear()
			return
	var r: Variant = _target.call() if _target.is_valid() else null
	_hole = (r as Rect2) if r is Rect2 else Rect2()
	if _hole.size != Vector2.ZERO:
		var gx := get_global_transform().affine_inverse()
		_hole = gx * _hole
		_hole = _hole.grow(10.0)
	_place_bubble()
	queue_redraw()


## 말풍선: 구멍 아래 → 위 → 왼쪽 → 오른쪽 중 화면 안에 들어가는 곳. 구멍이 없으면 화면 가운데 위.
func _place_bubble() -> void:
	_bubble.reset_size()
	var bs := _bubble.size
	var scr := Rect2(Vector2.ZERO, size).grow(-16.0)
	if _hole.size == Vector2.ZERO:
		_bubble.position = Vector2((size.x - bs.x) / 2.0, size.y * 0.18)
		return
	var c := _hole.get_center()
	if _beside.is_valid():
		var br: Variant = _beside.call()
		if br is Rect2 and (br as Rect2).size != Vector2.ZERO:
			var card := get_global_transform().affine_inverse() * (br as Rect2)
			_bubble.position = Vector2(maxf(scr.position.x, card.position.x - bs.x - 28.0),
					clampf(c.y - bs.y / 2.0, scr.position.y, scr.end.y - bs.y))
			return
	var spots := [
		Vector2(c.x - bs.x / 2.0, _hole.end.y + 26.0),
		Vector2(c.x - bs.x / 2.0, _hole.position.y - bs.y - 26.0),
		Vector2(_hole.position.x - bs.x - 26.0, c.y - bs.y / 2.0),
		Vector2(_hole.end.x + 26.0, c.y - bs.y / 2.0),
	]
	for p in spots:
		var rect := Rect2(p, bs)
		if scr.encloses(rect):
			_bubble.position = p
			return
	var p0: Vector2 = spots[0]
	_bubble.position = Vector2(clampf(p0.x, scr.position.x, scr.end.x - bs.x), clampf(p0.y, scr.position.y,
			scr.end.y - bs.y))


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	if _is_tip:
		if _hole.size != Vector2.ZERO:
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			draw_rect(_hole, Color(RING, 0.6 + 0.4 * pulse), false, 3.0)
		_arrow()
		return
	if _hole.size == Vector2.ZERO:
		draw_rect(full, DIM)
		return
	var h := _hole.intersection(full)
	# 구멍 둘레 네 조각만 어둡게
	draw_rect(Rect2(0, 0, size.x, h.position.y), DIM)
	draw_rect(Rect2(0, h.end.y, size.x, size.y - h.end.y), DIM)
	draw_rect(Rect2(0, h.position.y, h.position.x, h.size.y), DIM)
	draw_rect(Rect2(h.end.x, h.position.y, size.x - h.end.x, h.size.y), DIM)
	var pulse2 := 0.5 + 0.5 * sin(_t * 5.0)
	draw_rect(h.grow(2.0 + 3.0 * pulse2), Color(RING, 0.65 + 0.35 * pulse2), false, 4.0)
	_arrow()


## 말풍선에서 구멍 쪽으로 향하는 짧은 화살표
func _arrow() -> void:
	if _hole.size == Vector2.ZERO:
		return
	var b := Rect2(_bubble.position, _bubble.size)
	var from := b.get_center()
	var to := _hole.get_center()
	var d := (to - from).normalized()
	# 말풍선 테두리와 구멍 테두리 사이
	var start := _edge(b, from, d)
	var end := _edge(_hole, to, -d)
	if start.distance_to(end) < 12.0:
		return
	draw_line(start, end, RING, 4.0, true)
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([end, end - d * 16.0 + n * 9.0, end - d * 16.0 - n * 9.0]), RING)


static func _edge(r: Rect2, c: Vector2, d: Vector2) -> Vector2:
	var tx := INF if absf(d.x) < 0.0001 else (r.size.x / 2.0) / absf(d.x)
	var ty := INF if absf(d.y) < 0.0001 else (r.size.y / 2.0) / absf(d.y)
	return c + d * minf(tx, ty)
