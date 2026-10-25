## 데모 메인 화면: 퍼즐 팩 하나를 읽어 지도, 진술, 행동 버튼을 보여준다.
##
## 실행 인자 (godot 인자 뒤에 -- 를 붙이고 넘긴다):
##   --puzzle=normal-101     시작할 사건 id
##   --mute                  TTS 끄기
##   --speed=0               차량 진행 배속 (0이면 멈춤)
##   --autoplay=t3,s4,r6     자동 실행: t탐문 s잠복 r급습 h힌트 m메모 sel선택 p진행률(p0.5)
##   --screenshot=/path.png  자동 실행 뒤 화면을 저장하고 종료
extends Control

const PUZZLE_DIR := "res://data/puzzles/"
const TRIP_MINUTES := 20.0          # 화면에 보여줄 이동 시간
const TRIP_SECONDS := 300.0         # 1배속에서 실제로 걸리는 시간
const FINAL_PHASE_MINUTES := 5.0
const SPEEDS := [1.0, 4.0, 0.0]
const SPEED_LABELS := ["▶ 1배속", "▶▶ 4배속", "❚❚ 멈춤"]

var case: PuzzleCase
var voice: GleoVoice
var map_view: MapView
var trip_progress := 0.0
var speed_idx := 0
var speed_override := -1.0
var selected := -1
var raid_armed := -1
var investigate_armed := -1
var puzzle_ids: Array[String] = []
var current_id := ""
var args := {}
var _hud_timer := 0.0

var lbl_eta: Label
var lbl_budget: Label
var lbl_rep: Label
var lbl_left: Label
var opt_puzzle: OptionButton
var btn_speed: Button
var btn_hint: Button
var lbl_place: Label
var lbl_place_sub: Label
var btn_investigate: Button
var btn_stakeout: Button
var btn_raid: Button
var btn_sus: Button
var btn_ok: Button
var list_box: VBoxContainer
var lbl_dups: Label
var lbl_speaker: Label
var lbl_line: Label
var lbl_gleo: Label
var overlay: Control
var lbl_result: Label


func _ready() -> void:
	args = _parse_args()
	theme = _make_theme()
	voice = GleoVoice.new()
	add_child(voice)
	if args.has("mute"):
		voice.enabled = false
	if args.has("speed"):
		speed_override = float(args["speed"])
	_build_ui()
	_load_index()
	if puzzle_ids.is_empty():
		lbl_line.text = "퍼즐 팩이 없어요. prototype/export_pack.py로 data/puzzles를 채워 주세요."
		return
	_start(String(args.get("puzzle", puzzle_ids[0])))
	if args.has("autoplay") or args.has("screenshot"):
		_run_script()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		if eq == -1:
			out[s] = true
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


# ---------------------------------------------------------------- 사건 시작

func _load_index() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PUZZLE_DIR + "index.json"))
	puzzle_ids.clear()
	opt_puzzle.clear()
	if typeof(parsed) != TYPE_ARRAY:
		return
	for e in parsed:
		puzzle_ids.append(String(e["id"]))
		opt_puzzle.add_item("%s · 최소 탐문 %d" % [e["id"], int(e["minInvestigations"])])


func _start(id: String) -> void:
	var c := PuzzleCase.load_from(PUZZLE_DIR + id + ".json")
	if c == null:
		return
	case = c
	current_id = id
	opt_puzzle.select(puzzle_ids.find(id))
	trip_progress = 0.0
	selected = -1
	raid_armed = -1
	investigate_armed = -1
	case.statement_heard.connect(_on_statement_heard)
	case.stakeout_offered.connect(_on_stakeout_offered)
	case.stakeout_missed.connect(func(id): _gleo("%s 지나쳤어요. 잠복 기회가 사라졌어요." % _josa(case.place_label(id), "을", "를")))
	case.raided.connect(_on_raided)
	case.final_phase_started.connect(_on_final_phase)
	case.ended.connect(_on_ended)
	map_view.set_case(case)
	for ch in list_box.get_children():
		ch.queue_free()
	overlay.visible = false
	lbl_speaker.text = "Gleo · 사건 브리핑"
	lbl_line.text = _briefing()
	lbl_gleo.text = ""
	voice.say(lbl_line.text)
	case.set_trip_progress(0.0)
	_refresh()


func _briefing() -> String:
	var p: Dictionary = case.data["preset"]
	var evil := PackedStringArray()
	for r in p["evil"]:
		evil.append(case.role_label(String(r)))
	var text := "형사님, 경로 주변 %d곳 중 %d곳에 조직원(%s)이 숨어 있어요. " % [
			case.place_count(), case.n_evil(), ", ".join(evil)]
	if int(p["meddlers"]) > 0:
		text += "말썽꾼도 %d명 섞여 있어요. " % int(p["meddlers"])
	text += "정직한 직업은 7개 중 %d개, 탐문은 %d번이에요." % [int(case.data["nHonest"]), case.budget()]
	return text


# ---------------------------------------------------------------- 진행

func _process(delta: float) -> void:
	if case == null or case.status != "playing":
		return
	var sp: float = speed_override if speed_override >= 0.0 else SPEEDS[speed_idx]
	if sp > 0.0:
		trip_progress = minf(1.0, trip_progress + delta * sp / TRIP_SECONDS)
		case.set_trip_progress(trip_progress)
	_check_trip()
	_hud_timer += delta
	if _hud_timer > 0.25:
		_hud_timer = 0.0
		_refresh_hud()
		map_view.queue_redraw()


func _eta_minutes() -> float:
	return (1.0 - trip_progress) * TRIP_MINUTES


## 도착 5분 전이면 최종 단계, 도착하면 사건 종료.
func _check_trip() -> void:
	if case.status != "playing":
		return
	if _eta_minutes() <= FINAL_PHASE_MINUTES:
		case.enter_final_phase()
	if trip_progress >= 1.0:
		case.arrive()


# ---------------------------------------------------------------- 사건 신호

func _on_statement_heard(id: int, stmt: Dictionary, is_stakeout: bool) -> void:
	map_view.note_heard(id, is_stakeout)
	map_view.hint_pair = []
	lbl_gleo.text = ""
	var role := case.shown_label(id)
	lbl_speaker.text = "%s · %s%s" % [case.place_label(id), role, "   ★ 잠복 · 확실한 말" if is_stakeout else ""]
	lbl_line.text = "\"%s\"" % stmt["line"]
	voice.say(String(stmt["line"]))
	_add_statement_row(id, stmt, is_stakeout)


func _on_stakeout_offered(id: int) -> void:
	_gleo("곧 %s 옆을 지나가요. 잠복할까요?" % case.place_label(id))


func _on_raided(id: int, hit: bool, actual: String) -> void:
	var label := case.place_label(id)
	if hit:
		_gleo("검거! %s %s 위장한 %s." % [_josa(label, "은", "는"),
				_euro(case.role_label(case.true_shown_role(id))), _was(case.role_label(actual))])
	else:
		_gleo("오급습이에요… %s의 제보자는 %s. 신뢰도 -%d" % [label, _was(case.role_label(actual)),
				int(case.data["rules"]["wrongRaidCost"])])


func _on_final_phase(raids_left: int) -> void:
	_gleo("도착 5분 전이에요. 조직이 눈치챘어요! 이제 급습만 할 수 있어요. 급습 기회 %d번." % raids_left)


func _on_ended(status: String) -> void:
	var titles := {"won": "사건 해결!", "fired": "신뢰도가 바닥나 해임됐어요…", "escaped": "도착했어요. 남은 조직원은 도주했어요."}
	var title: String = titles.get(status, status)
	var lines := PackedStringArray([title, "신뢰도 %d · 탐문 %d/%d · 검거 %d/%d" % [
			case.reputation, case.used, case.budget(), case.caught.size(), case.n_evil()], "", "정답"])
	for id in range(1, case.place_count() + 1):
		var actual := case.actual_role(id)
		var shown := case.true_shown_role(id)
		var t := "%s: %s" % [case.place_label(id), case.role_label(actual)]
		if actual != shown:
			t += " (겉으로는 %s)" % case.role_label(shown)
		if case.is_hidden(id):
			t += " — 숨은 곳"
		if PuzzleCase._has_id(case.data["truth"]["tainted"], id):
			t += " — 협박당함"
		lines.append(t)
	lbl_result.text = "\n".join(lines)
	overlay.visible = true
	_gleo(title)
	_refresh()


# ---------------------------------------------------------------- 행동

func _on_place_clicked(id: int) -> void:
	_select(id)


func _select(id: int) -> void:
	selected = id
	raid_armed = -1
	if investigate_armed != id:
		investigate_armed = -1
	map_view.selected_id = id
	_refresh()


func _on_investigate() -> void:
	if selected == -1 or case.status != "playing":
		return
	if case.is_final_phase():
		_gleo("조직이 눈치챘어요. 이제는 급습만 할 수 있어요.")
		return
	if case.observed.has(selected):
		_gleo("이미 이야기를 들은 곳이에요.")
		return
	if bool(case.place(selected)["roadside"]) and investigate_armed != selected:
		investigate_armed = selected
		if case.stakeout_available().has(selected):
			_gleo("지금 잠복할 수 있어요. 잠복하면 예산도 안 쓰고 확실한 말을 들어요. 그래도 탐문하려면 한 번 더 누르세요.")
		else:
			_gleo("곧 지나갈 길가 장소예요. 기다렸다 잠복하면 공짜고 확실해요. 그래도 지금 물어보려면 한 번 더 누르세요.")
		_refresh()
		return
	investigate_armed = -1
	case.investigate(selected)
	_refresh()


func _on_stakeout() -> void:
	if selected == -1 or case.status != "playing":
		return
	if case.stakeout(selected).is_empty():
		if not bool(case.place(selected)["roadside"]):
			_gleo("잠복은 길가 장소에서만 할 수 있어요.")
		elif case.observed.has(selected):
			_gleo("이미 이야기를 들은 곳이에요.")
		else:
			_gleo("아직 그 근처를 지나지 않았어요.")
	_refresh()


func _on_raid() -> void:
	if selected == -1 or case.status != "playing" or case.revealed.has(selected):
		return
	if raid_armed != selected:
		raid_armed = selected
		_gleo("%s 급습할까요? 틀리면 신뢰도가 %d 떨어져요. 한 번 더 누르면 출동해요." % [
				_josa(case.place_label(selected), "을", "를"), int(case.data["rules"]["wrongRaidCost"])])
		_refresh()
		return
	raid_armed = -1
	case.raid(selected)
	_refresh()


func _on_memo(tag: String) -> void:
	if selected == -1:
		return
	case.set_memo(selected, "" if case.memos.get(selected, "") == tag else tag)
	_refresh()


func _on_hint() -> void:
	if case.status != "playing":
		return
	var pair := case.hint()
	if pair.is_empty():
		_gleo("지금까지 들은 말 중엔 서로 부딪히는 게 없어요. 더 탐문해 보세요.")
	else:
		map_view.hint_pair = pair
		_gleo("%d번과 %d번의 말은 동시에 참일 수 없어요. 둘 중 적어도 한 명은 거짓말을 해요. (신뢰도 -%d)" % [
				pair[0], pair[1], int(case.data["rules"]["hintCost"])])
	_refresh()


func _on_speed() -> void:
	speed_override = -1.0
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	_refresh_hud()


func _on_puzzle_selected(index: int) -> void:
	_start(puzzle_ids[index])


func _gleo(text: String) -> void:
	lbl_gleo.text = "Gleo: " + text
	voice.say(text)


# ---------------------------------------------------------------- 화면 갱신

func _refresh() -> void:
	if case == null:
		return
	_refresh_hud()
	var playing := case.status == "playing"
	if selected == -1:
		lbl_place.text = "장소를 고르세요"
		lbl_place_sub.text = "지도에서 핀을 누르세요. 노란 테두리는 길가 장소예요. 차가 지나갈 때 잠복할 수 있어요."
		for b in [btn_investigate, btn_stakeout, btn_raid, btn_sus, btn_ok]:
			b.disabled = true
	else:
		var p := case.place(selected)
		lbl_place.text = case.place_label(selected)
		var lines := PackedStringArray()
		lines.append(String(p["kind"]) + " · " + String(p.get("side", "")) + (" · 길가 (지나가는 동안 잠복 가능)" if bool(p["roadside"]) else "") + (" · 익명 제보" if case.is_anonymous(selected) else ""))
		if case.observed.has(selected):
			lines.append("밝힌 직업: %s%s" % [case.shown_label(selected),
					" (잠복)" if case.observed[selected] else ""])
		if case.revealed.has(selected):
			lines.append("정체: %s — %s" % [case.role_label(case.actual_role(selected)),
					"검거" if case.caught.has(selected) else "오급습"])
		var memo: String = case.memos.get(selected, "")
		if memo != "":
			lines.append("메모: " + memo)
		lbl_place_sub.text = "\n".join(lines)
		btn_investigate.disabled = not playing or case.observed.has(selected) or case.is_final_phase()
		btn_investigate.text = "정말 탐문?" if investigate_armed == selected else "탐문"
		btn_stakeout.disabled = not playing or not case.stakeout_available().has(selected)
		btn_raid.disabled = not playing or case.revealed.has(selected)
		btn_raid.text = "정말 급습?" if raid_armed == selected else "급습"
		btn_sus.disabled = not playing
		btn_ok.disabled = not playing
	var dups := case.duplicate_claims()
	var dup_lines := PackedStringArray()
	for r in dups.keys():
		var who := ""
		for id in dups[r]:
			who += PuzzleCase.circled(int(id))
		dup_lines.append("※ %s 밝힌 사람이 %d명: %s" % [_irago(case.role_label(String(r))), dups[r].size(), who])
	lbl_dups.text = "\n".join(dup_lines)
	btn_hint.disabled = not playing
	map_view.queue_redraw()


func _refresh_hud() -> void:
	lbl_eta.text = "도착 %d분" % ceili(_eta_minutes())
	lbl_budget.text = "탐문 %d/%d" % [case.used, case.budget()]
	if case.is_final_phase():
		lbl_budget.text += " · 최종 단계(급습 %d)" % case.final_raids_left
	var rep := maxi(case.reputation, 0)
	lbl_rep.text = "신뢰도 " + "●".repeat(rep) + "○".repeat(maxi(0, 5 - rep))
	lbl_left.text = "남은 조직원 %d" % (case.n_evil() - case.caught.size())
	btn_speed.text = SPEED_LABELS[speed_idx] if speed_override < 0.0 else "배속 %.1f" % speed_override


func _add_statement_row(id: int, stmt: Dictionary, is_stakeout: bool) -> void:
	var b := Button.new()
	b.text = "%s · %s%s\n%s" % [case.place_label(id), case.shown_label(id),
			"  ★잠복" if is_stakeout else "", stmt["fact"]]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(func():
		map_view.focus = {"id": id, "stakeout": is_stakeout}
		_select(id))
	list_box.add_child(b)


# ---------------------------------------------------------------- UI 구성

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _box(Color("0f1520"), 0, 14))
	root.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 32)
	top.add_child(th)
	th.add_child(_label("수사망", 28, Color("6fa8ff")))
	lbl_eta = _label("", 26, Color.WHITE)
	lbl_budget = _label("", 26, Color.WHITE)
	lbl_rep = _label("", 26, Color("ffc94a"))
	lbl_left = _label("", 26, Color("ff5d6c"))
	for l in [lbl_eta, lbl_budget, lbl_rep, lbl_left]:
		th.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(spacer)
	opt_puzzle = OptionButton.new()
	opt_puzzle.item_selected.connect(_on_puzzle_selected)
	th.add_child(opt_puzzle)
	btn_speed = _button("", _on_speed)
	btn_speed.custom_minimum_size = Vector2(150, 48)
	th.add_child(btn_speed)
	btn_hint = _button("힌트 (신뢰도 -1)", _on_hint)
	btn_hint.custom_minimum_size = Vector2(0, 48)
	th.add_child(btn_hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	map_view = MapView.new()
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.place_clicked.connect(_on_place_clicked)
	body.add_child(map_view)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(500, 0)
	side.add_theme_stylebox_override("panel", _box(Color("111722"), 0, 20))
	body.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	side.add_child(sv)
	lbl_place = _label("", 30, Color.WHITE)
	sv.add_child(lbl_place)
	lbl_place_sub = _label("", 19, Color("8b9ab3"))
	lbl_place_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(lbl_place_sub)
	var row1 := HBoxContainer.new()
	sv.add_child(row1)
	btn_investigate = _button("탐문", _on_investigate)
	btn_stakeout = _button("잠복", _on_stakeout)
	btn_raid = _button("급습", _on_raid)
	for b in [btn_investigate, btn_stakeout, btn_raid]:
		row1.add_child(b)
	var row2 := HBoxContainer.new()
	sv.add_child(row2)
	btn_sus = _button("의심 메모", func(): _on_memo("의심"))
	btn_ok = _button("무고 메모", func(): _on_memo("무고"))
	for b in [btn_sus, btn_ok]:
		b.custom_minimum_size = Vector2(0, 48)
		row2.add_child(b)
	sv.add_child(HSeparator.new())
	sv.add_child(_label("들은 진술 (누르면 지도에 강조)", 20, Color("8b9ab3")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	lbl_dups = _label("", 19, Color("ffc94a"))
	lbl_dups.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(lbl_dups)

	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 190)
	bottom.add_theme_stylebox_override("panel", _box(Color("0f1520"), 0, 20))
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)
	lbl_speaker = _label("", 21, Color("4fd1ff"))
	lbl_line = _label("", 30, Color.WHITE)
	lbl_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_gleo = _label("", 22, Color("ffc94a"))
	lbl_gleo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [lbl_speaker, lbl_line, lbl_gleo]:
		bv.add_child(l)

	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color("111722"), 16, 36))
	center.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 18)
	card.add_child(cv)
	lbl_result = _label("", 22, Color.WHITE)
	cv.add_child(lbl_result)
	var again := _button("다시 하기", func(): _start(current_id))
	again.custom_minimum_size = Vector2(0, 60)
	cv.add_child(again)


func _make_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Apple SD Gothic Neo", "Noto Sans CJK KR", "Noto Sans KR",
			"Malgun Gothic", "sans-serif"])
	t.default_font = f
	t.default_font_size = 22
	t.set_stylebox("normal", "Button", _box(Color("1b2433"), 10, 12))
	t.set_stylebox("hover", "Button", _box(Color("26324a"), 10, 12))
	t.set_stylebox("pressed", "Button", _box(Color("33476b"), 10, 12))
	t.set_stylebox("disabled", "Button", _box(Color("131923"), 10, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.28))
	return t


func _box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_pressed)
	return b


# ---------------------------------------------------------------- 한국어 조사

static func _batchim(word: String) -> int:
	## 받침 번호(0이면 받침 없음). 한글이 아니면 0
	if word.is_empty():
		return 0
	var code := word.unicode_at(word.length() - 1)
	if code >= 0xAC00 and code <= 0xD7A3:
		return (code - 0xAC00) % 28
	return 0


static func _josa(word: String, with_batchim: String, without: String) -> String:
	return word + (with_batchim if _batchim(word) != 0 else without)


static func _euro(word: String) -> String:
	var b := _batchim(word)
	return word + ("로" if b == 0 or b == 8 else "으로")


static func _was(word: String) -> String:
	return word + ("이었어요" if _batchim(word) != 0 else "였어요")


static func _irago(word: String) -> String:
	return word + ("이라고" if _batchim(word) != 0 else "라고")


# ---------------------------------------------------------------- 자동 실행 (테스트, 스크린샷)

func _run_script() -> void:
	for _i in range(3):
		await get_tree().process_frame
	for cmd in String(args.get("autoplay", "")).split(",", false):
		_exec(cmd.strip_edges())
		await get_tree().process_frame
	if args.has("screenshot"):
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(String(args["screenshot"]))
		print("screenshot saved: ", args["screenshot"])
		get_tree().quit()


func _exec(cmd: String) -> void:
	if cmd == "h":
		_on_hint()
		return
	if cmd.begins_with("p"):
		trip_progress = float(cmd.substr(1))
		case.set_trip_progress(trip_progress)
		_check_trip()
		_refresh()
		return
	var op := cmd.substr(0, 3) if cmd.begins_with("sel") else cmd.substr(0, 1)
	var id := int(cmd.substr(op.length()))
	if id < 1 or id > case.place_count():
		push_warning("자동 실행 명령을 이해하지 못했어요: " + cmd)
		return
	_select(id)
	match op:
		"t":
			case.investigate(id)
		"s":
			case.stakeout(id)
		"r":
			case.raid(id)
		"m":
			case.set_memo(id, "의심")
	_refresh()
