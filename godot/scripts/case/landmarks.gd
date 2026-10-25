## 사건 장소 랜드마크(assets/models/landmarks) 찾기: 장소 이름·업종 → 모델 id, 3D 모델, 썸네일.
## 목록 파일은 tools/blender/make_landmarks.py가 만드는 landmarks.json이다.
## 이름(by_name)을 먼저 보고, 없으면 업종(by_kind)을 본다.
class_name Landmarks
extends RefCounted

const INDEX := "res://assets/models/landmarks/landmarks.json"

static var _index := {}
static var _thumbs := {}


static func _data() -> Dictionary:
	if _index.is_empty() and FileAccess.file_exists(INDEX):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if typeof(parsed) == TYPE_DICTIONARY:
			_index = parsed
	return _index


## 장소에 맞는 모델 id. 못 찾으면 "".
static func id_for(place_name: String, kind: String) -> String:
	var d := _data()
	if d.is_empty():
		return ""
	var id = d["by_name"].get(place_name, d["by_kind"].get(kind))
	return String(id) if id != null and d["models"].has(id) else ""


## 장소 썸네일(256px, 투명 배경). 없으면 null.
static func thumb(place_name: String, kind: String) -> Texture2D:
	var id := id_for(place_name, kind)
	if id == "":
		return null
	if not _thumbs.has(id):
		_thumbs[id] = load(String(_data()["models"][id]["thumb"]))
	return _thumbs[id]


## 지도 핀용 작은 썸네일(PIN_THUMB_PX, 밉맵 포함). 지도에서 50px 안팎으로 줄여 그려도 거칠지 않게
## 미리 줄여 둔다. 없으면 null.
const PIN_THUMB_PX := 112
static var _pin_thumbs := {}


static func pin_thumb(id: String) -> Texture2D:
	if id == "" or not _data().get("models", {}).has(id):
		return null
	if not _pin_thumbs.has(id):
		var out: Texture2D = null
		var tex := load(String(_data()["models"][id]["thumb"])) as Texture2D
		var img := tex.get_image() if tex != null else null
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.resize(PIN_THUMB_PX, PIN_THUMB_PX, Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			out = ImageTexture.create_from_image(img)
		_pin_thumbs[id] = out
	return _pin_thumbs[id]


## 모델 인스턴스. 원점은 부지 바닥 중앙, 정면(입구)은 -Z.
static func instantiate(id: String) -> Node3D:
	var scene := load(String(_data()["models"][id]["glb"])) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


## 크기(m): x 폭, y 높이, z 깊이(정면에서 뒤까지).
static func size_of(id: String) -> Vector3:
	var s: Array = _data()["models"][id]["size_m"]
	return Vector3(s[0], s[1], s[2])
