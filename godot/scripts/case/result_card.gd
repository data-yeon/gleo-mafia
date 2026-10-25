## 사건 결말 카드 (내비 도착 카드 형식): 결말 제목·한 줄, 되짚기(결정적 단서 / 속은 말), 정답 공개(제보자 이름).
## 문구는 StoryBook.ending()이 만든다. 도착 전에 끝나면 [도착까지 빨리 가기], 도착했으면 [다음 사건]. 둘 다 [다시 하기].
class_name ResultCard
extends PanelContainer

signal restart
signal fast_forward
signal next_case

var _title: Label
var _sub: Label
var _list: VBoxContainer
var _debrief: VBoxContainer
var _debrief_cap: Label
var _truth_cap: Label
var _primary: Button
var _primary_id := ""


func _ready() -> void:
	theme_type_variation = "Card"
	custom_minimum_size = Vector2(620, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	head.add_child(PleosIcon.make("police", 56, PleosTheme.TEXT))
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 0)
	head.add_child(tcol)
	_title = PleosTheme.label("", "Title")
	_title.add_theme_font_size_override("font_size", 36)
	tcol.add_child(_title)
	_sub = PleosTheme.label("", "Caption")
	tcol.add_child(_sub)
	col.add_child(HSeparator.new())
	_debrief_cap = PleosTheme.label("되짚기", "Small")
	col.add_child(_debrief_cap)
	_debrief = VBoxContainer.new()
	_debrief.add_theme_constant_override("separation", 6)
	col.add_child(_debrief)
	_truth_cap = PleosTheme.label("정답", "Small")
	col.add_child(_truth_cap)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	col.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_primary = Button.new()
	_primary.theme_type_variation = "PrimaryButton"
	_primary.custom_minimum_size = Vector2(0, 60)
	_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary.pressed.connect(func(): fast_forward.emit() if _primary_id == "fast" else next_case.emit())
	row.add_child(_primary)
	var again := Button.new()
	again.text = "다시 하기"
	again.custom_minimum_size = Vector2(0, 60)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func(): restart.emit())
	row.add_child(again)


## arrived: 목적지에 도착했는지. 도착 전이면 [도착까지 빨리 가기], 도착했으면 [다음 사건].
## e: StoryBook.ending() 결과 {title, sub, color, debrief, rows}. 비어 있으면 예전 모양.
func show_result(c: PuzzleCase, arrived := true, e := {}) -> void:
	var titles := {"won": "사건 해결!", "fired": "해임됐어요", "escaped": "조직원이 도주했어요"}
	var title := String(e.get("title", titles.get(c.status, c.status)))
	_title.text = ("목적지 도착 · " if arrived else "") + title
	_primary_id = "next" if arrived else "fast"
	_primary.text = "다음 사건" if arrived else "도착까지 빨리 가기"
	if e.has("primary"):
		_primary_id = String(e["primary"][0])
		_primary.text = String(e["primary"][1])
	_title.add_theme_color_override("font_color", e.get("color", PleosTheme.OK if c.status == "won" else PleosTheme.DANGER))
	var stats := "검거 %d/%d · 본부 신뢰 %d · 회신 전화 %d/%d · 현장 확인 %d" % [
			c.caught.size(), c.n_evil(), maxi(c.reputation, 0), c.used, c.budget(), _stakeouts(c)]
	_sub.text = (String(e["sub"]) + "\n" + stats) if e.has("sub") and String(e["sub"]) != "" else stats
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	for d in _debrief.get_children():
		_debrief.remove_child(d)
		d.queue_free()
	for ln in e.get("debrief", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var col: Color = ln[2] if ln.size() > 2 else PleosTheme.TEXT_2
		var icon := PleosIcon.make(String(ln[0]), 24, col)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var dl := PleosTheme.label(String(ln[1]), "Body")
		dl.add_theme_font_size_override("font_size", 21)
		dl.add_theme_color_override("font_color", col.darkened(0.1))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(540, 0)
		row.add_child(dl)
		_debrief.add_child(row)
	_truth_cap.text = "정답 · %d통의 제보" % c.place_count() if e.has("rows") else "정답"
	_debrief.visible = _debrief.get_child_count() > 0
	_debrief_cap.visible = _debrief.visible
	if e.has("rows"):
		for rw in e["rows"]:
			var rl := PleosTheme.label(String(rw["text"]), "Body")
			rl.add_theme_font_size_override("font_size", 18)
			rl.add_theme_color_override("font_color", rw["color"])
			_list.add_child(rl)
		visible = true
		return
	for id in range(1, c.place_count() + 1):
		var actual := c.actual_role(id)
		var shown := c.true_shown_role(id)
		var line := "%s — %s" % [c.place_label(id), c.role_label(actual)]
		if actual != shown:
			line += " (겉으로는 %s)" % c.role_label(shown)
		var notes := PackedStringArray()
		if c.is_hidden(id):
			notes.append("숨은 곳")
		if c.is_anonymous(id):
			notes.append("익명 제보")
		if PuzzleCase._has_id(c.data["truth"]["tainted"], id):
			notes.append("협박당함")
		if not notes.is_empty():
			line += " · " + " · ".join(notes)
		var l := PleosTheme.label(line, "Body")
		l.add_theme_font_size_override("font_size", 20)
		if c.is_hidden(id):
			l.add_theme_color_override("font_color", PleosTheme.DANGER)
		_list.add_child(l)
	visible = true


func _stakeouts(c: PuzzleCase) -> int:
	var n := 0
	for k in c.observed.keys():
		if c.observed[k]:
			n += 1
	return n
