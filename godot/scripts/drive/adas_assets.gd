## 자율주행 패널 에셋(차량·보행자·길거리 소품) 찾기와 만들기.
## 목록은 Blender 세션이 만드는 JSON 세 개다(tools/blender/README.md).
## 규격: 1 단위 = 1m, 정면 -Z, 원점은 바닥 중앙(가로등·차량 신호등은 기둥 바닥).
class_name AdasAssets
extends RefCounted

const CATALOGS := ["res://assets/models/vehicles.json", "res://assets/models/people/people.json",
		"res://assets/models/props/props.json", "res://assets/models/figures/figures.json"]

static var _models := {}        # id → 목록 항목
static var _scenes := {}        # id → PackedScene
static var _parts := {}         # id → [{mesh, xform}]


static func _load() -> void:
	if not _models.is_empty():
		return
	for path in CATALOGS:
		if not FileAccess.file_exists(path):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			var models: Dictionary = d.get("models", {})
			for id in models:
				_models[id] = models[id]


static func has(id: String) -> bool:
	_load()
	return _models.has(id) and ResourceLoader.exists(String(_models[id]["glb"]))


## 크기(m): x 폭, y 높이, z 길이. 모르면 승용차 크기.
static func size_of(id: String) -> Vector3:
	_load()
	if not _models.has(id):
		return Vector3(2.0, 1.5, 4.6)
	var s: Array = _models[id]["size_m"]
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


## 모델 인스턴스. 파일이 없으면 null.
static func instance(id: String) -> Node3D:
	if not has(id):
		return null
	if not _scenes.has(id):
		_scenes[id] = load(String(_models[id]["glb"]))
	var scene := _scenes[id] as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


## MultiMesh용: 모델 안의 메시들과 모델 원점 기준 변환. 파일이 없으면 빈 배열.
static func mesh_parts(id: String) -> Array:
	if _parts.has(id):
		return _parts[id]
	var out := []
	var root := instance(id)
	if root != null:
		_collect(root, root, out)
		root.free()
	_parts[id] = out
	return out


static func _collect(root: Node, node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var xf := (node as Node3D).transform
		var p := node.get_parent()
		while p != null and p != root:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		out.append({"mesh": (node as MeshInstance3D).mesh, "xform": xf})
	for c in node.get_children():
		_collect(root, c, out)


## 램프 켜기·끄기(신호등, 택시 표시등, 경광등). 켜면 발광, 끄면 어둡게.
static func set_lamp(root: Node, lamp_name: String, lit: bool) -> void:
	var mi := root.find_child(lamp_name, true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var key := "lamp_on" if lit else "lamp_off"
	if mi.has_meta(key):
		mi.material_override = mi.get_meta(key)
		return
	var base := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if base == null:
		return
	var mat := base.duplicate() as StandardMaterial3D
	if lit:
		mat.emission_enabled = true
		mat.emission = base.albedo_color
		mat.emission_energy_multiplier = 1.6
	else:
		mat.albedo_color = base.albedo_color.darkened(0.6)
	mi.set_meta(key, mat)
	mi.material_override = mat


## 모델 파일이 없을 때 쓰는 상자 차량.
static func box_vehicle(color: Color, size := Vector3(1.9, 1.4, 4.5)) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y * 0.55, size.z)
	body.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	body.material_override = m
	body.position.y = size.y * 0.3
	root.add_child(body)
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(size.x * 0.86, size.y * 0.42, size.z * 0.55)
	cabin.mesh = cm
	cabin.material_override = m
	cabin.position = Vector3(0, size.y * 0.75, size.z * 0.04)
	root.add_child(cabin)
	return root
