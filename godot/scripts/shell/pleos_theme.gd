## Pleos 차량 화면 느낌의 밝은 테마: 색, 폰트, 카드·버튼 스타일.
## 영상(42dot 자율주행)에서 본 밝은 테마를 기준으로 잡았다. 세부 수치는 실제 화면 캡처를 받으면 맞춘다.
class_name PleosTheme
extends RefCounted

# 화면
const BG := Color("eef1f5")
const SURFACE := Color("ffffff")
const SURFACE_2 := Color("f4f6f9")
const LINE := Color("e2e6ec")
const TEXT := Color("111827")
const TEXT_2 := Color("5b6472")
const TEXT_3 := Color("9aa3af")
const ACCENT := Color("2f6bff")
const ACCENT_SOFT := Color("e9f0ff")
const OK := Color("16a34a")
const WARN := Color("f59e0b")
const WARN_SOFT := Color("fff4dc")
const DANGER := Color("ef4444")
# 게임 요소에만 쓰는 경광등 색
const SIREN_RED := Color("ff3b4e")
const SIREN_BLUE := Color("2f6bff")
# 지도
const MAP_LAND := Color("eceff3")
const MAP_ROAD := Color("ffffff")
const MAP_ROAD_CASE := Color("d6dce3")
const MAP_MAJOR := Color("fff1d2")
const MAP_MAJOR_CASE := Color("e8c983")
const MAP_PARK := Color("d5eac9")
const MAP_WATER := Color("bcd9f2")
const MAP_ROUTE := Color("2f7bff")
const MAP_ROUTE_DONE := Color("a9b4c2")
const MAP_BLOCK := Color("e2e6eb")
const MAP_BRIDGE_CASE := Color("9aa6b4")
const MAP_LABEL := Color("4b5563")
const MAP_LABEL_MINOR := Color("8a94a3")
const MAP_LABEL_WATER := Color("4f86bd")
# 자율주행 패널
const ADAS_BG := Color("f2f4f7")
const ADAS_ROAD := Color("cdd3db")
const ADAS_LANE := Color("ffffff")
const ADAS_PATH := Color(0.2, 0.45, 1.0, 0.35)

const FONT_NAMES := ["Pretendard", "Apple SD Gothic Neo", "Noto Sans KR", "Noto Sans CJK KR",
		"Malgun Gothic", "sans-serif"]

static var _regular: SystemFont
static var _bold: SystemFont


static func font(bold := false) -> Font:
	if _regular == null:
		_regular = _make_font(400)
		_bold = _make_font(700)
	return _bold if bold else _regular


static func _make_font(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_NAMES)
	f.font_weight = weight
	return f


## 둥근 카드 배경. shadow=true면 떠 있는 카드처럼 그림자를 준다.
static func box(color: Color, radius: int, margin: int = 16, shadow := false,
		border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0.07, 0.1, 0.16, 0.10)
		sb.shadow_size = 18
		sb.shadow_offset = Vector2(0, 6)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 24
	t.set_color("font_color", "Label", TEXT)

	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(SURFACE, 24, 22, true))
	t.set_type_variation("FlatCard", "PanelContainer")
	t.set_stylebox("panel", "FlatCard", box(SURFACE_2, 18, 14))
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(ACCENT_SOFT, 999, 8))

	_label_var(t, "Display", 58, TEXT, true)
	_label_var(t, "Title", 30, TEXT, true)
	_label_var(t, "Body", 24, TEXT, false)
	_label_var(t, "BodyStrong", 24, TEXT, true)
	_label_var(t, "Caption", 20, TEXT_2, false)
	_label_var(t, "Small", 17, TEXT_3, false)
	_label_var(t, "AccentLabel", 22, ACCENT, true)

	t.set_stylebox("normal", "Button", box(SURFACE_2, 18, 14))
	t.set_stylebox("hover", "Button", box(Color("eceff4"), 18, 14))
	t.set_stylebox("pressed", "Button", box(ACCENT_SOFT, 18, 14))
	t.set_stylebox("disabled", "Button", box(SURFACE_2, 18, 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_3)
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 24)

	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(ACCENT, 18, 14))
	t.set_stylebox("hover", "PrimaryButton", box(ACCENT.lightened(0.08), 18, 14))
	t.set_stylebox("pressed", "PrimaryButton", box(ACCENT.darkened(0.12), 18, 14))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "PrimaryButton", Color.WHITE)

	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", box(Color("fdecec"), 18, 14))
	t.set_stylebox("hover", "DangerButton", box(Color("fbdede"), 18, 14))
	t.set_stylebox("pressed", "DangerButton", box(Color("f8caca"), 18, 14))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "DangerButton", DANGER)

	t.set_type_variation("RoundButton", "Button")
	t.set_stylebox("normal", "RoundButton", box(SURFACE, 999, 10, true))
	t.set_stylebox("hover", "RoundButton", box(SURFACE_2, 999, 10, true))
	t.set_stylebox("pressed", "RoundButton", box(ACCENT_SOFT, 999, 10, true))
	return t


static func _label_var(t: Theme, type_name: String, size: int, color: Color, bold: bool) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, color)
	t.set_font("font", type_name, font(bold))


## 라벨 하나 만들기 도우미.
static func label(text: String, variation := "Body") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l
