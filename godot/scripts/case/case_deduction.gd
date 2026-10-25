## 용의 장소 검색의 판정기: 들은 진술 중 "믿는" 것들을 조건으로 걸어, 숨은 곳 조합 중 남는 것을 센다.
## 화면 보조 기능이다(규칙은 그대로). Python 솔버 전체가 아니라, 플레이어가 고른 믿음만 적용한다.
## - 개수 단서(반경·구간·편·앞뒤·업종·길가): members 중 숨은 곳이 정확히 count곳
## - 보증(VOUCH): 수상 = 대상이 숨은 곳, 깨끗 = 숨은 곳 아님
## - 신분(REVEAL): 진짜 = 숨은 곳 아님(조직원은 늘 위장한다). 위장 = 조직원 또는 취객이라 조합을 자르지 않는다(판단 보류)
## - 출동 결과: 검거한 곳은 숨은 곳, 헛걸음은 숨은 곳 아님(확정)
## 칩 종류: on(믿음) / off(못 믿음) / lock(잠복 진술, 항상 참) / soft(판단 보류)
class_name CaseDeduction
extends RefCounted

var case: PuzzleCase
var trust := {}                 # 장소 id → false면 못 믿음 (없으면 믿음)
var pending: Array[int] = []    # 회신 전화 연출 중인 곳: 규칙상 들었지만 아직 화면에 안 나온 말(조건에서 뺀다)
var _cache_key := ""
var _cache: Array = []


func _init(c: PuzzleCase) -> void:
	case = c


## 그 장소 진술 칩의 종류.
func kind_of(id: int) -> String:
	if not case.observed.has(id) or pending.has(id):
		return ""
	if bool(case.observed[id]):
		return "lock"
	var clue: Dictionary = case.statement(id, false)["clue"]
	if String(clue["type"]) == "REVEAL" and String(clue["claim"]) == "disguised":
		return "soft"
	return "off" if trust.get(id, true) == false else "on"


func toggle(id: int) -> void:
	var k := kind_of(id)
	if k == "on":
		trust[id] = false
	elif k == "off":
		trust.erase(id)


func set_trusted(id: int, on: bool) -> void:
	if on:
		trust.erase(id)
	else:
		trust[id] = false


## 조건에 맞는 숨은 곳 조합들 (각 조합은 장소 id 배열).
func live_sets() -> Array:
	var key := "%s|%s|%s|%s|%s" % [str(case.observed), str(trust), str(case.revealed), str(case.caught), str(pending)]
	if key == _cache_key:
		return _cache
	var out := []
	var conds := _conditions(-1)
	for h in _all_sets():
		if _ok(h, conds):
			out.append(h)
	_cache_key = key
	_cache = out
	return out


## 남은 조합에서 한 번이라도 숨은 곳으로 나오는 장소(후보).
func candidates() -> Array[int]:
	var seen := {}
	for h in live_sets():
		for x in h:
			seen[x] = true
	var out: Array[int] = []
	for i in range(1, case.place_count() + 1):
		if seen.has(i):
			out.append(i)
	return out


## 경우가 0일 때: 하나만 빼면 다시 맞는 경우가 생기는 믿음 칩들(나중에 들은 것부터).
func conflict_fixes(order: Array) -> Array[int]:
	var out: Array[int] = []
	if not live_sets().is_empty():
		return out
	var ids := order.duplicate()
	ids.reverse()
	for id in ids:
		if kind_of(int(id)) != "on":
			continue
		var conds := _conditions(int(id))
		for h in _all_sets():
			if _ok(h, conds):
				out.append(int(id))
				break
	return out


## 진술 하나의 조건이 조합 h에서 맞는지(판단 보류면 null).
func _condition(id: int) -> Variant:
	var clue: Dictionary = case.statement(id, bool(case.observed[id]))["clue"]
	var t := String(clue["type"])
	if clue.has("count"):
		var mem: Array[int] = []
		for m in clue.get("members", []):
			mem.append(int(m))
		return {"members": mem, "count": int(clue["count"])}
	if t == "VOUCH":
		return {"target": int(clue["target"]), "hidden": String(clue["claim"]) == "suspicious"}
	if t == "REVEAL" and String(clue["claim"]) == "genuine":
		return {"target": int(clue["target"]), "hidden": false}
	return null


func _conditions(skip: int) -> Array:
	var conds := []
	for k in case.observed.keys():
		var id := int(k)
		if id == skip:
			continue
		var kind := kind_of(id)
		if kind != "on" and kind != "lock":
			continue
		var c = _condition(id)
		if c != null:
			conds.append(c)
	for r in case.revealed:
		conds.append({"target": int(r), "hidden": case.caught.has(r)})
	return conds


static func _ok(h: Array, conds: Array) -> bool:
	for c in conds:
		if c.has("members"):
			var n := 0
			for x in h:
				if (c["members"] as Array).has(x):
					n += 1
			if n != int(c["count"]):
				return false
		elif h.has(int(c["target"])) != bool(c["hidden"]):
			return false
	return true


func _all_sets() -> Array:
	var out := []
	_combine(1, case.place_count(), case.n_evil(), [], out)
	return out


static func _combine(start: int, n: int, k: int, cur: Array, out: Array) -> void:
	if cur.size() == k:
		out.append(cur.duplicate())
		return
	for i in range(start, n + 1):
		cur.append(i)
		_combine(i + 1, n, k, cur, out)
		cur.pop_back()


## 힌트(데모 규칙): 믿는 말 중 실제로 거짓인 것을 하나 짚는다(나중에 들은 것부터). 없으면 못 믿는다고 한 말 중 참인 것.
## 돌려주는 것: {id, lie(bool)} 또는 빈 Dictionary.
func hint_target(order: Array) -> Dictionary:
	var ids := order.duplicate()
	ids.reverse()
	for id in ids:
		if kind_of(int(id)) == "on" and not _is_true(int(id)):
			return {"id": int(id), "lie": true}
	for id2 in ids:
		if kind_of(int(id2)) == "off" and _is_true(int(id2)):
			return {"id": int(id2), "lie": false}
	return {}


func _is_true(id: int) -> bool:
	var hidden: Array[int] = []
	for x in case.data["truth"]["hidden"]:
		hidden.append(int(x))
	var c = _condition(id)
	if c == null:
		return true
	return _ok(hidden, [c])


## 결정적 단서(결말 되짚기): 출동 결과를 빼고 믿은 말만으로 경우가 1가지로 정해졌을 때,
## 그중 하나를 빼면 경우가 늘어나는 말들. 믿은 말만으로 정해지지 않았으면 빈 배열.
func essential(order: Array) -> Array[int]:
	var out: Array[int] = []
	if _count(_belief_conditions(-1)) != 1:
		return out
	for id in order:
		var k := kind_of(int(id))
		if (k == "on" or k == "lock") and _count(_belief_conditions(int(id))) > 1:
			out.append(int(id))
	return out


func _belief_conditions(skip: int) -> Array:
	var conds := []
	for k in case.observed.keys():
		var id := int(k)
		if id == skip:
			continue
		var kind := kind_of(id)
		if kind != "on" and kind != "lock":
			continue
		var c = _condition(id)
		if c != null:
			conds.append(c)
	return conds


func _count(conds: Array) -> int:
	var n := 0
	for h in _all_sets():
		if _ok(h, conds):
			n += 1
	return n
