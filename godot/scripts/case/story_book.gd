## 이야기 층: 퍼즐(규칙·진실)은 그대로 두고, 그 위에 사건 이야기(첩보, 인물, 문구)를 얹는다.
## 설정("가짜 제보")과 규칙별 이야기 이유는 docs/story-bible.md.
## 이야기는 data/story/<preset.key>.json에 있고, 없으면 default.json을 쓴다.
## **정답 누설 금지:** 플레이 중 함수는 공개 정보(장소, 자칭 직업, 진술, 시드)만 본다.
## 그래서 팩에서 정답(truth·hints·analysis)과 잠복 진술을 뺀 사본(pub)만 들고 있다.
## 진실이 필요한 결말 함수는 PuzzleCase를 인자로 받는다(끝난 뒤에만 부른다).
class_name StoryBook
extends RefCounted

const DIR := "res://data/story/"
## 자칭 직업별 프로필 색(진짜 정체와 무관)
const ROLE_COLORS := {
	"VENDOR": Color("e8833a"), "TAXI": Color("d4a017"), "DRONE": Color("3a8fd8"), "LOCAL": Color("8a6d3b"),
	"RIDER": Color("2fa36b"), "GUARD": Color("5b6b8a"), "COP": Color("2f5bd8"), "GOSSIP": Color("c2588f"),
}
const ANON_COLOR := Color("6b7280")

var s: Dictionary = {}            # 이야기 JSON
var pub: Dictionary = {}          # 정답을 뺀 팩 사본
var _names := {}                  # 장소 id → 제보자 이름(자칭 직업 기준)


static func for_pack(data: Dictionary) -> StoryBook:
	return StoryBook.new(data)


func _init(data: Dictionary) -> void:
	pub = public_view(data)
	var key := String((pub.get("preset", {}) as Dictionary).get("key", ""))
	s = _load(DIR + key + ".json")
	if s.is_empty():
		s = _load(DIR + "default.json")
	_assign_names()


## 팩에서 플레이 중에 알 수 없는 것을 뺀 사본: 정답, 힌트 표, 분석, 장소별 잠복 진술.
static func public_view(data: Dictionary) -> Dictionary:
	var p := data.duplicate()
	for k in ["truth", "hints", "analysis"]:
		p.erase(k)
	var sts := []
	for st in data.get("statements", []):
		var c: Dictionary = (st as Dictionary).duplicate()
		c.erase("stakeout")
		sts.append(c)
	p["statements"] = sts
	return p


static func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## 같은 자칭 직업이 여럿이면 이름이 겹치지 않게, 시드와 장소 순서로만 정한다.
func _assign_names() -> void:
	var seed := int(pub.get("seed", 0))
	var count := {}
	var pools: Dictionary = s.get("names", {})
	for st in pub.get("statements", []):
		var id := int(st["placeId"])
		var r = st["shownRole"]
		var pool: Array = pools.get(String(r), []) if r != null else []
		if pool.is_empty():
			_names[id] = ""
			continue
		var j := int(count.get(r, 0))
		count[r] = j + 1
		var base := _hash("%d:%s" % [seed, r]) % pool.size()
		_names[id] = String(pool[(base + j) % pool.size()])


static func _hash(t: String) -> int:
	var h := 5381
	for i in t.length():
		h = (h * 33 + t.unicode_at(i)) % 1000003
	return h


# ---------------------------------------------------------------- 공개 정보 조회

func place_count() -> int:
	return (pub.get("places", []) as Array).size()


func place_label(id: int) -> String:
	return "%s %s" % [PuzzleCase.circled(id), pub["places"][id - 1]["name"]]


## 붙여 쓰는 짧은 이름: "②분수광장"
func place_tight(id: int) -> String:
	return "%s%s" % [PuzzleCase.circled(id), pub["places"][id - 1]["name"]]


func shown_role(id: int) -> String:
	var r = pub["statements"][id - 1]["shownRole"]
	return "" if r == null else String(r)


func role_label(key: String) -> String:
	return String(pub["roles"][key]["label"]) if pub.get("roles", {}).has(key) else key


func is_anonymous(id: int) -> bool:
	return bool(pub["places"][id - 1].get("anonymous", false))


func n_evil() -> int:
	return (pub["preset"]["evil"] as Array).size()


func term(key: String) -> String:
	return String(s.get(key, ""))


# ---------------------------------------------------------------- 인물

## 제보자 프로필: {name, role(자칭 직업 이름), initial, color, anon, obscured}
func persona(id: int, obscured := false) -> Dictionary:
	if obscured:
		return {"name": "???", "role": "직업 못 들음", "initial": "?", "color": ANON_COLOR, "anon": false, "obscured": true}
	var r := shown_role(id)
	if r == "":
		return {"name": "익명 제보자", "role": "음성 변조", "initial": "?", "color": ANON_COLOR, "anon": true,
				"obscured": false}
	var nm := String(_names.get(id, ""))
	return {"name": nm, "role": role_label(r), "initial": nm.substr(0, 1) if nm != "" else "?",
			"color": ROLE_COLORS.get(r, ANON_COLOR), "anon": false, "obscured": false}


## "자칭 노점상 박 사장" / "익명 제보자 · 음성 변조" / "??? · 직업 못 들음(잡음)"
func who(id: int, obscured := false) -> String:
	var p := persona(id, obscured)
	if bool(p["obscured"]):
		return "??? · 직업 못 들음(잡음)"
	if bool(p["anon"]):
		return "익명 제보자 · 음성 변조"
	return ("자칭 %s %s" % [p["role"], p["name"]]).strip_edges()


## Gleo 바 화자 줄: "② 분수광장 · 자칭 노점상 박 사장"
func speaker(id: int, obscured := false) -> String:
	return "%s · %s" % [place_label(id), who(id, obscured)]


## 회신 전화로 들은 말. 익명 제보는 소문 말투로 다시 쓴다.
func line(id: int) -> String:
	var st: Dictionary = pub["statements"][id - 1]
	if st["shownRole"] == null:
		return "(음성 변조) 이름은 못 밝혀요. 들은 얘긴데요, %s." % _dae(claim(st["clue"]))
	return String(st["line"])


## 현장 확인(잠복) 문장: 사람이 아니라 제보 내용을 차량 카메라로 확인한 결과.
func stakeout_line(id: int, clue: Dictionary) -> String:
	return "%s 제보 내용을 카메라로 확인했어요. %s." % [place_label(id), _yo(claim(clue))]


## 단서를 자연스러운 평서문으로("…수상한 데가 한 곳 있다"). 끝은 늘 "다".
func claim(clue: Dictionary) -> String:
	var t := String(clue["type"])
	var cnt := _count_phrase(int(clue.get("count", 0)))
	match t:
		"RADIUS":
			return "%s에서 %s 안에 수상한 데가 %s" % [place_tight(int(clue["center"])), _km(float(clue["radiusM"])), cnt]
		"SPAN":
			return "%s부터 %s까지 가는 길에 수상한 데가 %s" % [place_tight(int(clue["from"])), place_tight(int(clue["to"])), cnt]
		"SIDE":
			return "가는 길 %s에 수상한 데가 %s" % [clue["side"], cnt]
		"NEIGHBOR":
			var mem := PackedStringArray()
			for m in clue["members"]:
				mem.append(place_tight(int(m)))
			return "%s 앞뒤 %s 중에 수상한 데가 %s" % [PuzzleCase.circled(int(clue["center"])), "·".join(mem), cnt]
		"KIND":
			return "%s 쪽에 수상한 데가 %s" % [clue["kind"], cnt]
		"ROAD":
			return "바로 길가에 있는 곳 중에 수상한 데가 %s" % cnt
		"VOUCH":
			var tg := place_tight(int(clue["target"]))
			return ("%s 쪽이 수상하다" % tg) if String(clue["claim"]) == "suspicious" else ("%s 쪽은 깨끗하다" % tg)
		"REVEAL":
			var tg2 := place_tight(int(clue["target"]))
			return ("%s 제보자는 신분을 속이고 있다" % tg2) if String(clue["claim"]) == "disguised" \
					else ("%s 제보자는 겉과 속이 같다" % tg2)
	return "아무것도 모른다"


static func _km(m: float) -> String:
	return ("%dkm" % int(m / 1000.0)) if fmod(m, 1000.0) == 0.0 else ("%.1fkm" % (m / 1000.0))


static func _count_phrase(n: int) -> String:
	return {0: "한 곳도 없다", 1: "한 곳 있다", 2: "두 곳 있다", 3: "세 곳 있다"}.get(n, "%d곳 있다" % n)


## "…있다" → "…있대요" (들은 말 전하기)
static func _dae(t: String) -> String:
	return t.substr(0, t.length() - 1) + "대요" if t.ends_with("다") else t


## "…있다/없다/하다/같다" → 해요체
static func _yo(t: String) -> String:
	for pair in [["없다", "없어요"], ["있다", "있어요"], ["하다", "해요"], ["같다", "같아요"]]:
		if t.ends_with(pair[0]):
			return t.substr(0, t.length() - String(pair[0]).length()) + String(pair[1])
	return t


# ---------------------------------------------------------------- 문구

## 문구 틀 채우기. args에 시간처럼 바뀌는 값({deadline}, {sent}, {mins} 등)을 넣는다.
func fmt(template: String, args := {}) -> String:
	var a := _base_args()
	a.merge(args, true)
	return template.format(a)


func _base_args() -> Dictionary:
	var v: Dictionary = s.get("victim", {})
	return {
		"org": s.get("org", ""), "crime": s.get("crime", ""), "who": s.get("who", "조직원"),
		"n": n_evil(), "places": place_count(), "calls": int(pub["preset"]["budget"]),
		"victim_name": v.get("name", ""), "victim_age": int(v.get("age", 0)), "victim_what": v.get("what", ""),
		"victim_amount": v.get("amount", ""), "sms": s.get("sms", ""), "hold": int(s.get("hold_min", 30)),
		"wrong": int(pub["rules"]["wrongRaidCost"]), "hint": int(pub["rules"]["hintCost"]),
	}


## 카드 줄 하나: [아이콘, 글, 색 이름?] → [아이콘, 글, Color?]
func _line(ln: Array, args := {}) -> Array:
	var out := [String(ln[0]), fmt(String(ln[1]), args)]
	if ln.size() > 2:
		out.append(color_of(String(ln[2])))
	return out


static func color_of(name: String) -> Color:
	return {"accent": PleosTheme.ACCENT, "danger": PleosTheme.DANGER, "warn": PleosTheme.WARN,
			"ok": PleosTheme.OK}.get(name, PleosTheme.TEXT_2)


## 제안 카드 {kicker, title, lines, say}
func offer(args: Dictionary) -> Dictionary:
	var o: Dictionary = s["offer"]
	var lines := []
	for ln in o["lines"]:
		lines.append(_line(ln, args))
	return {"kicker": fmt(o["kicker"], args), "title": fmt(o["title"], args), "lines": lines, "say": fmt(o["say"], args)}


## 용의자 칸: 프리셋 조직원 순서대로 A, B, C. [{slot, key, label, tag, how}]
func suspects() -> Array:
	var out := []
	var info: Dictionary = s.get("suspects", {})
	var i := 0
	for r in pub["preset"]["evil"]:
		var k := String(r)
		var d: Dictionary = info.get(k, {})
		out.append({"slot": "ABCDE".substr(i, 1), "key": k, "label": role_label(k),
				"tag": String(d.get("tag", role_label(k))), "how": String(d.get("how", ""))})
		i += 1
	return out


## 브리핑 3장 [{kicker, title, lines, say, stamp?}]. 3장은 이 판의 수법(조직원·말썽꾼·익명) + 우리 수단.
func briefing(args: Dictionary) -> Array:
	var pages := []
	for pg in s["brief"]:
		var lines := []
		for ln in pg["lines"]:
			lines.append(_line(ln, args))
		var d := {"kicker": fmt(pg["kicker"], args), "title": fmt(pg["title"], args), "lines": lines,
				"say": fmt(pg["say"], args)}
		if pg.has("stamp"):
			d["stamp"] = pg["stamp"]
		pages.append(d)
	var last: Dictionary = pages[pages.size() - 1]
	if (last["lines"] as Array).is_empty():
		last["lines"] = modus_lines(args)
	return pages


func modus_lines(args := {}) -> Array:
	var m: Dictionary = s["modus"]
	var lines := [_line(m["base"], args)]
	var evil: Array = pub["preset"]["evil"]
	for k in ["IMPOSTER", "BLACKMAILER", "BOSS", "THUG"]:
		if k in evil and m.has(k):
			lines.append(_line(m[k], args))
	lines.append(_line(m["dup"], args))
	if int(pub["preset"].get("meddlers", 0)) > 0:
		lines.append(_line(m["meddler"], args))
	for pl in pub["places"]:
		if bool(pl.get("anonymous", false)):
			var a := args.duplicate()
			a["place_eun"] = CaseDirector._josa(place_label(int(pl["id"])), "은", "는")
			lines.append(_line(m["anon"], a))
	for ln in m["means"]:
		lines.append(_line(ln, args))
	return lines


func start_say() -> String:
	return fmt(String(s.get("start_say", "")))


## 최종 단계 문구. by: "time"(마감 5분 전) | "calls"(회신 전화를 다 씀)
func final_say(by: String, raids_left: int) -> String:
	return fmt(String(s["final"].get(by, s["final"]["time"])), {"k": raids_left})


func beat(key: String, args := {}) -> String:
	return fmt(String(s.get("beats", {}).get(key, "")), args)


# ---------------------------------------------------------------- 결말 (끝난 뒤에만: 진실을 본다)

const EVIL := ["THUG", "IMPOSTER", "BLACKMAILER", "BOSS"]


## 결말 종류: won(다 잡음) | partial(일부 검거) | escaped(놓침) | fired(수사 제외)
static func ending_kind(c: PuzzleCase) -> String:
	if c.status == "won":
		return "won"
	if c.status == "fired":
		return "fired"
	return "partial" if c.caught.size() > 0 else "escaped"


## 회신 전화로 들은(들었을) 말이 사실이었나.
static func statement_true(c: PuzzleCase, id: int) -> bool:
	var clue: Dictionary = c.statement(id, false)["clue"]
	var hidden: Array = c.data["truth"]["hidden"]
	var is_h := func(x) -> bool: return PuzzleCase._has_id(hidden, int(x))
	if clue.has("count"):
		var n := 0
		for m in clue.get("members", []):
			if is_h.call(m):
				n += 1
		return n == int(clue["count"])
	var t := int(clue["target"])
	if String(clue["type"]) == "VOUCH":
		return is_h.call(t) == (String(clue["claim"]) == "suspicious")
	var disguised := c.actual_role(t) != c.true_shown_role(t)
	return disguised == (String(clue["claim"]) == "disguised")


## 그 말이 왜 틀렸나(진짜 정체 기준).
func lie_reason(c: PuzzleCase, id: int) -> String:
	var actual := c.actual_role(id)
	if actual in EVIL:
		return "%s 꾸민 말이었어요" % CaseDirector._josa(role_label(actual), "이", "가")
	if actual == "DRUNK":
		return "취객이 직업을 착각하고 한 말이었어요"
	if actual == "GOSSIP":
		return "오지랖 주민이 숫자를 부풀렸어요"
	if PuzzleCase._has_id(c.data["truth"]["tainted"], id):
		return "협박당한 진짜 %s의 거짓말이었어요" % role_label(actual)
	return "틀린 말이었어요"


## 장소 정답 한 줄: "⑧ 시청역 · 서 경장(자칭 순찰 경관) → 사칭범 · 숨은 곳"
func reveal(c: PuzzleCase, id: int) -> Dictionary:
	var shown := c.true_shown_role(id)
	var actual := c.actual_role(id)
	var who_txt := ""
	if is_anonymous(id):
		who_txt = "익명 제보자"
	else:
		who_txt = "%s(자칭 %s)" % [_names.get(id, ""), role_label(shown)]
	var notes := PackedStringArray()
	var col := PleosTheme.TEXT
	var verdict := role_label(actual)
	if c.is_hidden(id):
		notes.append("검거" if c.caught.has(id) else "도주")
		col = PleosTheme.DANGER
	elif actual == "DRUNK" or actual == "GOSSIP":
		col = PleosTheme.WARN
	elif PuzzleCase._has_id(c.data["truth"]["tainted"], id):
		notes.append("협박당함")
		col = PleosTheme.WARN
	elif actual == shown:
		verdict = "진짜"
		col = PleosTheme.TEXT_2
	if not statement_true(c, id):
		notes.append("거짓말")
	var text := "%s · %s → %s" % [place_label(id), who_txt, verdict]
	if not notes.is_empty():
		text += " · " + " · ".join(notes)
	return {"text": text, "color": col, "liar": not statement_true(c, id), "hidden": c.is_hidden(id)}


## 결말 카드 {kind, title, sub, color, debrief: [[아이콘, 글, 색]], rows: [{text, color}]}
func ending(c: PuzzleCase, ded: CaseDeduction, heard: Array) -> Dictionary:
	var kind := ending_kind(c)
	var e: Dictionary = s.get("ending", {}).get(kind, {"title": kind, "sub": ""})
	var escaper := ""
	for x in c.data["truth"]["hidden"]:
		if not c.caught.has(int(x)):
			escaper = CaseDirector._josa("%s의 %s" % [place_label(int(x)), role_label(c.actual_role(int(x)))], "이", "가")
			break
	var args := {"caught": c.caught.size(), "left": c.n_evil() - c.caught.size(), "escaper": escaper}
	var rows := []
	for id in range(1, c.place_count() + 1):
		rows.append(reveal(c, id))
	return {"kind": kind, "title": fmt(String(e["title"]), args), "sub": fmt(String(e["sub"]), args),
			"color": PleosTheme.OK if kind == "won" else PleosTheme.DANGER,
			"debrief": debrief(c, ded, heard, kind), "rows": rows}


## 되짚기 3줄 이하. 해결: 결정적 단서 + 간파한 거짓말. 그 밖: 속은 말 + 헛걸음 + 놓친 기회.
func debrief(c: PuzzleCase, ded: CaseDeduction, heard: Array, kind: String) -> Array:
	var out := []
	var see_through := []
	var fooled := []
	for id in heard:
		var k := ded.kind_of(int(id))
		var ok := statement_true(c, int(id))
		if k == "off" and not ok:
			see_through.append(int(id))
		elif k == "on" and not ok:
			fooled.append(int(id))
	if kind == "won":
		var ess := ded.essential(heard)
		if not ess.is_empty():
			var names := PackedStringArray()
			for id2 in ess.slice(0, 2):
				names.append(_short_who(int(id2)))
			out.append(["flag", "결정적 단서: %s의 말" % " · ".join(names), PleosTheme.OK])
		for id3 in see_through.slice(0, 1):
			out.append(["police", "%s 말을 뺀 판단이 맞았어요. %s" % [_short_who(id3), lie_reason(c, id3)], PleosTheme.OK])
		if out.is_empty():
			out.append(["gleo", "증거보다 감이 앞섰지만, 결과는 검거예요", PleosTheme.TEXT_2])
		return out.slice(0, 3)
	for id4 in fooled.slice(0, 2):
		out.append(["warning", "속은 말: %s → %s" % [_short_who(id4), lie_reason(c, id4)], PleosTheme.DANGER])
	for r in c.revealed:
		if not c.caught.has(r) and out.size() < 3:
			out.append(["police", "%s 출동은 헛걸음이었어요" % place_label(r), PleosTheme.TEXT_2])
	for x in c.data["truth"]["hidden"]:
		var hid := int(x)
		if out.size() < 3 and not c.caught.has(hid) and not c.observed.has(hid):
			out.append(["phone", "놓친 기회: %s에는 한 번도 전화하지 않았어요" % place_label(hid), PleosTheme.TEXT_2])
	if out.is_empty():
		out.append(["gleo", "말은 맞게 골랐는데 출동이 늦었어요", PleosTheme.TEXT_2])
	return out.slice(0, 3)


## "⑥ 정 군" / "⑦ 익명 제보자"
func _short_who(id: int) -> String:
	var nm := String(_names.get(id, ""))
	return "%s %s" % [PuzzleCase.circled(id), nm if nm != "" else "익명 제보자"]
