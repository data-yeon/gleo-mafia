## 자율주행 패널의 사건 장소 랜드마크: 9곳의 건물을 도시의 실제 위치에 세운다. 정면(-Z)은 경로 쪽을 본다.
## 사건을 수락하면 건물 위에 장소 번호 표지(내비 카드 모양의 2D 알약)를 띄운다.
## 잠복 찬스 중인 곳은 표지에 주황 테두리, 바닥에 주황 링을 둔다.
## 표지는 3D 안개를 받지 않도록 서브뷰포트의 2D 층에 그리고, 건물이 다가오면 서서히 나타나게 한다.
class_name RoadsideLandmarks
extends Node3D

const SHOW_DIST := 300.0          # 내 차에서 이 거리 안의 건물만 보인다(멀리서는 안개에 묻힌다)
const LABEL_MAX_Y := 12.0         # 표지 높이 상한(전망 타워처럼 높은 건물도 화면 안에 들게)
const LABEL_FADE := 90.0          # 표지가 나타나는 구간(m)
const HOT_TEXT := Color("c2410c")

var hot_id := -1                  # 잠복 찬스 중인 장소 id
var labels_on := false            # 사건을 수락하면 켠다
var _items: Array[Dictionary] = []   # {id, node, pill, text, label_y, ring}
var _canvas: Control              # 표지를 그리는 2D 층(서브뷰포트 화면 좌표)
var _sb_normal: StyleBoxFlat
var _sb_hot: StyleBoxFlat
var _ring_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_sb_normal = _pill_box(Color(0, 0, 0, 0))
	_sb_hot = _pill_box(PleosTheme.WARN)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(PleosTheme.WARN, 0.75)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _pill_box(border: Color) -> StyleBoxFlat:
	var sb := PleosTheme.box(PleosTheme.SURFACE, 999, 6, true)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	return sb


## places: 퍼즐 팩 장소 목록. 모델이 있는 장소를 모두 세운다.
func build(places: Array, world: AdasWorld) -> void:
	for it in _items:
		(it["node"] as Node3D).queue_free()
		(it["pill"] as Control).queue_free()
	_items.clear()
	for p in places:
		var lid := String(p.get("landmark", ""))
		if lid == "":
			lid = Landmarks.id_for(String(p["name"]), String(p["kind"]))
		if lid == "":
			continue
		var node := Landmarks.instantiate(lid)
		if node == null:
			continue
		var pos := Vector2(float(p["x"]), float(p["y"]))
		var spot: Dictionary = world.landmark_spots.get(int(p["id"]), {})
		if not spot.is_empty():
			# 길가 장소: 보도 바로 뒤(AdasWorld가 정한 자리)
			node.position = AdasWorld.v3(spot["pos"])
			node.rotation.y = float(spot["yaw"])
		else:
			# 정면이 경로에서 가장 가까운 점을 본다
			var hint: float = float(p.get("routePos", 0.0)) * world.plan.length
			var q: Vector2 = world.route_pose(world.s_of(pos, hint))[0]
			node.position = AdasWorld.v3(pos)
			node.rotation.y = AdasWorld.yaw_facing(q - pos)
		node.visible = false
		add_child(node)
		var size := Landmarks.size_of(lid)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var rr := maxf(size.x, size.z) / 2.0 + 3.0
		torus.inner_radius = rr
		torus.outer_radius = rr + 1.2
		torus.rings = 48
		ring.mesh = torus
		ring.scale = Vector3(1, 0.04, 1)
		ring.position = Vector3(0, 0.08, 0)
		ring.material_override = _ring_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		node.add_child(ring)
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", _sb_normal)
		var text := Label.new()
		text.text = "%s %s" % [PuzzleCase.circled(int(p["id"])), p["name"]]
		text.add_theme_font_override("font", PleosTheme.font(true))
		text.add_theme_font_size_override("font_size", 20)
		text.add_theme_color_override("font_color", PleosTheme.TEXT)
		pill.add_child(text)
		pill.visible = false
		_canvas.add_child(pill)
		_items.append({"id": int(p["id"]), "node": node, "pill": pill, "text": text, "ring": ring,
				"label_y": minf(size.y, LABEL_MAX_Y) + 2.0})


## 매 프레임: ego는 내 차 3D 위치.
func update(ego: Vector3, delta: float) -> void:
	_t += delta
	_canvas.visible = visible
	var cam := get_viewport().get_camera_3d()
	for it in _items:
		var node: Node3D = it["node"]
		var pill: PanelContainer = it["pill"]
		var dist := Vector2(node.position.x - ego.x, node.position.z - ego.z).length()
		node.visible = dist < SHOW_DIST
		pill.visible = false
		var hot := int(it["id"]) == hot_id
		var ring: MeshInstance3D = it["ring"]
		ring.visible = hot and node.visible
		if ring.visible:
			var k := 1.0 + 0.05 * sin(_t * 4.0)
			ring.scale = Vector3(k, 0.04, k)
		if not node.visible or not labels_on:
			continue
		var anchor := node.global_position + Vector3(0, float(it["label_y"]) + (absf(sin(_t * 4.0)) * 0.8 if hot else 0.0), 0)
		if cam == null or cam.is_position_behind(anchor):
			continue
		pill.visible = true
		pill.add_theme_stylebox_override("panel", _sb_hot if hot else _sb_normal)
		(it["text"] as Label).add_theme_color_override("font_color", HOT_TEXT if hot else PleosTheme.TEXT)
		pill.reset_size()
		# 가까운 건물은 패널 가장자리를 넘어가므로 표지를 패널 안에 붙잡아 둔다
		var pos := cam.unproject_position(anchor) - Vector2(pill.size.x / 2.0, pill.size.y)
		var max_x := get_viewport().get_visible_rect().size.x - pill.size.x - 10.0
		pill.position = Vector2(clampf(pos.x, 10.0, maxf(10.0, max_x)), maxf(pos.y, 10.0)).round()
		pill.modulate.a = clampf((SHOW_DIST - dist) / LABEL_FADE, 0.0, 1.0)
