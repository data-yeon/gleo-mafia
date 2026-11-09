## 제보자 초상화 찾기. 원본: assets/portraits/<키>.jpg (512×768 세로 그림, Grok으로 만든 것).
## 통화 카드의 동그란 프로필에는 얼굴이 가운데 오게 미리 자른 정사각형 <키>_face.jpg(512×512)를 쓴다.
## (자르기: sips -c 512 512 --cropOffset 50 0 <키>.jpg --out <키>_face.jpg)
## 그림이 없는 인물(노점상, 택시기사 등)은 null → 호출하는 쪽이 이니셜 원을 그대로 쓴다.
class_name PortraitBank
extends RefCounted

const DIR := "res://assets/portraits/"

static var _cache := {}


## 자칭 직업 코드(StoryBook.shown_role)와 이름으로 키를 정한다. 경관은 이름마다 얼굴이 정해져 있다.
## 직업이 비어 있으면(익명 제보) "anon". 모르는 직업이면 "".
static func key_for(role: String, name: String, anon := false) -> String:
	if anon or role == "":
		return "anon"
	match role:
		"COP":
			if name.begins_with("서"):
				return "cop_seo"
			if name.begins_with("도"):
				return "cop_do"
			return "cop_han"
		"VENDOR":
			return "vendor"
		"TAXI":
			return "taxi"
		"DRONE":
			return "drone"
		"LOCAL":
			return "grandpa" if name.contains("할아버지") else "grandma"
		"RIDER":
			return "rider"
		"GUARD":
			return "guard"
		"GOSSIP":
			return "gossip"
	return ""


## 키로 정사각 얼굴 텍스처(<키>_face.jpg, 원본 <키>.jpg에서 얼굴이 가운데 오게 미리 잘라 둔 것). 그림 파일이 없으면 null.
static func texture_for(key: String) -> Texture2D:
	if key == "":
		return null
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var path := "%s%s_face.jpg" % [DIR, key]
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[key] = tex
	return tex


## 키로 통화 카드용 그림(<키>_card.jpg, 512×563: 머리 위 여백부터 어깨선까지). 없으면 null.
## (자르기: sips -c 563 512 --cropOffset 20 0 <키>.jpg --out <키>_card.jpg)
static func card_for(key: String) -> Texture2D:
	if key == "":
		return null
	var ck := key + "#card"
	if _cache.has(ck):
		return _cache[ck]
	var tex: Texture2D = null
	var path := "%s%s_card.jpg" % [DIR, key]
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[ck] = tex
	return tex


static func card_for_persona(role: String, name: String, anon := false) -> Texture2D:
	return card_for(key_for(role, name, anon))


## 키로 원본 2:3 세로 그림(512×768). 통화 화면에 얼굴을 크게 보여 줄 때 쓴다. 없으면 null.
static func full_for(key: String) -> Texture2D:
	if key == "":
		return null
	var ck := key + "#full"
	if _cache.has(ck):
		return _cache[ck]
	var tex: Texture2D = null
	var path := "%s%s.jpg" % [DIR, key]
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[ck] = tex
	return tex


## 직업·이름으로 원본 세로 그림(편의 함수).
static func full_for_persona(role: String, name: String, anon := false) -> Texture2D:
	return full_for(key_for(role, name, anon))


## 직업·이름으로 바로 텍스처(편의 함수).
static func texture_for_persona(role: String, name: String, anon := false) -> Texture2D:
	return texture_for(key_for(role, name, anon))
