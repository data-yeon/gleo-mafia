## 퍼즐 팩 JSON(스키마 v2) 하나를 읽어서 사건 진행 규칙을 제공한다. 룰 v1(내비 Dupery).
## prototype/puzzle/game.py 와 같은 규칙이다. 형식: docs/puzzle-pack-schema.md
## 시간: 차량 진행률(set_trip_progress)이 들어오면 그것을 쓰고, 없으면 통화·출동 시간으로 시계를 돌린다.
##
## JSON 숫자는 Godot에서 float로 읽히므로 id 비교는 항상 int()로 바꿔서 한다.
class_name PuzzleCase
extends RefCounted

signal statement_heard(place_id: int, stmt: Dictionary, is_stakeout: bool)
signal stakeout_offered(place_id: int)
signal stakeout_missed(place_id: int)
signal stakeout_reserved(place_id: int)
signal stakeout_cancelled(place_id: int)    # 경로가 바뀌어 예약한 잠복을 못 하게 됨
signal raided(place_id: int, hit: bool, actual_role: String)
signal final_phase_started(raids_left: int)
signal ended(status: String)

var data: Dictionary = {}
var observed: Dictionary = {}          # place_id(int) -> 잠복 여부(bool)
var revealed: Array[int] = []
var caught: Array[int] = []
var memos: Dictionary = {}             # place_id -> "의심" / "무고"
var reputation: int = 5
var used: int = 0
var final_raids_left: int = -1         # -1이면 아직 최종 단계 아님
var status: String = "playing"         # playing | won | fired | escaped
var trip_progress: float = 0.0         # 차량 경로 진행률 0..1. 경로 재생기가 넣는다
var obscured: Array[int] = []          # 터널 안에서 통화해 직업을 못 들은 장소 (데모 규칙)
var bonus_calls := 0                   # 신호 대기 보너스 통화 (예산을 쓰지 않음, 데모 규칙)
var bonus_granted := 0
var clock: float = 0.0                 # 차량이 없을 때 쓰는 통화·출동 시계
# 경로 거리 모드(데모 규칙, 경유지 재탐색 대응): 잠복 창을 진행률 대신 "지금 경로" 위 거리(m)로 본다.
# 처음 경로에서는 routePos 창과 같고, 경로가 바뀌면 길가 장소가 새 경로의 어디를 지나는지로 다시 잰다.
var route_mode := false
var trip_s := 0.0                      # 지금 경로 위 내 차 위치(m)
var place_route_s := {}                # 길가 장소 id → 지금 경로에서 그 장소를 지나는 지점(m). 경로에서 벗어난 곳은 없음
var stakeout_look_m := 0.0
var stakeout_pass_m := 0.0
# 경유지 잠복(데모 규칙): 길가가 아닌 장소 한 곳을 경유지로 들러 잠복한다. 통화 1번, 판당 1번.
var waypoint_id := -1
var waypoint_arrived := false
# 잠복 예약(데모 규칙): 잠복 창 안에서 예약해 두면, 그 장소 옆을 실제로 지날 때 확실한 말을 듣는다.
const DELIVER_AHEAD_M := 30.0          # 장소 옆 지점 이만큼 앞에서 들려준다
var reserved: Array[int] = []
var _use_trip := false
var _offered: Array[int] = []
var _missed: Array[int] = []


static func load_from(path: String) -> PuzzleCase:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("퍼즐 JSON을 읽지 못했어요: %s" % path)
		return null
	var c := PuzzleCase.new()
	c.data = parsed
	c.reputation = int(parsed["rules"]["startReputation"])
	return c


# ---------------------------------------------------------------- 조회

func place_count() -> int:
	return data["places"].size()


func place(id: int) -> Dictionary:
	return data["places"][id - 1]


func place_label(id: int) -> String:
	return "%s %s" % [circled(id), place(id)["name"]]


static func circled(id: int) -> String:
	return "①②③④⑤⑥⑦⑧⑨⑩⑪⑫".substr(id - 1, 1)


func budget() -> int:
	return int(data["preset"]["budget"])


func n_evil() -> int:
	return data["preset"]["evil"].size()


## 이동 진행률 0..1. 차량 진행률이 들어오면 그것, 아니면 통화·출동 시계.
func progress() -> float:
	return trip_progress if _use_trip else minf(1.0, clock)


func rule(key: String) -> float:
	return float(data["rules"][key])


func is_final_phase() -> bool:
	return final_raids_left >= 0


func role_label(role_key: String) -> String:
	return data["roles"][role_key]["label"]


## 밝힌 직업 키. 익명 제보면 빈 문자열.
func shown_role(id: int) -> String:
	var r = data["statements"][id - 1]["shownRole"]
	return "" if r == null else String(r)


func is_anonymous(id: int) -> bool:
	return bool(place(id).get("anonymous", false))


## 화면에 보일 직업 이름. 익명이면 "익명 제보", 터널 잡음으로 못 들었으면 "직업 못 들음".
func shown_label(id: int) -> String:
	if obscured.has(id):
		return "직업 못 들음(터널 잡음)"
	var r := shown_role(id)
	return String(data.get("anonymousLabel", "익명 제보")) if r == "" else role_label(r)


## 결과 화면용: 실제로 밝힌(위장한) 직업. 익명 제보자도 진실에는 들어 있다.
func true_shown_role(id: int) -> String:
	return data["truth"]["shownRoles"][id - 1]


## use_stakeout=true면 잠복 진술(항상 참). 길가 장소가 아니면 빈 Dictionary.
func statement(id: int, use_stakeout: bool) -> Dictionary:
	var s: Dictionary = data["statements"][id - 1]
	if use_stakeout:
		return s["stakeout"] if s["stakeout"] != null else {}
	return s


func is_hidden(id: int) -> bool:
	return _has_id(data["truth"]["hidden"], id)


func actual_role(id: int) -> String:
	return data["truth"]["roles"][id - 1]


## 길가 장소에 다가갈 때(routePos - lookahead)부터 지나칠 때(routePos + pass)까지만 잠복 가능.
## 경로 거리 모드면 같은 창을 m로 잰다. 경유지에 도착했으면 경유지 장소도 잠복할 수 있다.
func stakeout_available() -> Array[int]:
	var out: Array[int] = []
	if route_mode:
		for id in place_route_s:
			var ps := float(place_route_s[id])
			if not observed.has(int(id)) and not reserved.has(int(id)) \
					and ps - stakeout_look_m <= trip_s and trip_s <= ps + stakeout_pass_m:
				out.append(int(id))
		if waypoint_arrived and waypoint_id != -1 and not observed.has(waypoint_id):
			out.append(waypoint_id)
		return out
	var pr := progress()
	for p in data["places"]:
		var id := int(p["id"])
		var pos := float(p["routePos"])
		if p["roadside"] and not observed.has(id) \
				and pos - rule("stakeoutLookahead") <= pr and pr <= pos + rule("stakeoutPass"):
			out.append(id)
	return out


## 잠복하지 못하고 지나친 길가 장소.
func stakeout_passed() -> Array[int]:
	var out: Array[int] = []
	if route_mode:
		for id in place_route_s:
			if not observed.has(int(id)) and not reserved.has(int(id)) \
					and trip_s > float(place_route_s[id]) + stakeout_pass_m:
				out.append(int(id))
		return out
	for p in data["places"]:
		var id := int(p["id"])
		if p["roadside"] and not observed.has(id) and progress() > float(p["routePos"]) + rule("stakeoutPass"):
			out.append(id)
	return out


## 경유지로 들를 수 있는 장소: 진행 중, 최종 단계 전, 아직 안 썼음, 통화가 남음, 길가가 아니고 아직 안 들은 곳.
func can_add_waypoint(id: int) -> bool:
	return status == "playing" and not is_final_phase() and waypoint_id == -1 and calls_left() > 0 \
			and not observed.has(id) and not revealed.has(id) and not bool(place(id)["roadside"])


## 경유지 잠복 신청: 통화 1번을 쓴다. 도착하면 arrive_waypoint()로 잠복한다.
func add_waypoint(id: int) -> bool:
	if not can_add_waypoint(id):
		return false
	waypoint_id = id
	if bonus_calls > 0:
		bonus_calls -= 1
	else:
		used += 1
	clock = used * rule("callTime")
	_after_action()
	return true


## 경유지에 도착: 그 장소에서 잠복한다(진술은 항상 참). 최종 단계여도 이미 낸 통화라 들을 수 있다.
func arrive_waypoint() -> Dictionary:
	if waypoint_id == -1 or observed.has(waypoint_id) or status != "playing":
		return {}
	waypoint_arrived = true
	return stakeout(waypoint_id)


## 경로 거리 모드 켜기. positions: 길가 장소 id → 지금 경로 위 지점(m). 경로가 바뀌면 다시 부른다.
## 새 경로에서 벗어난 장소의 잠복 예약은 취소된다.
func set_route_positions(positions: Dictionary, look_m: float, pass_m: float) -> void:
	route_mode = true
	place_route_s = positions
	stakeout_look_m = look_m
	stakeout_pass_m = pass_m
	for id in reserved.duplicate():
		if not place_route_s.has(id):
			reserved.erase(id)
			stakeout_cancelled.emit(id)
	_deliver_reserved()
	_offer_stakeouts()


## 경로 거리 모드에서 매 프레임 내 차 위치(m)를 넣는다.
func set_trip_s(s: float) -> void:
	trip_s = s
	_deliver_reserved()
	_offer_stakeouts()


## 잠복 예약(경로 거리 모드): 잠복 창이 열린 길가 장소를 예약한다. 이미 옆을 지나는 중이면 바로 듣는다.
func reserve_stakeout(id: int) -> bool:
	if not route_mode or status != "playing" or not stakeout_available().has(id):
		return false
	reserved.append(id)
	stakeout_reserved.emit(id)
	_deliver_reserved()
	return true


func is_reserved(id: int) -> bool:
	return reserved.has(id)


## 예약한 장소 옆에 오면 잠복 진술을 들려준다(최종 단계여도 이미 예약했으니 듣는다).
func _deliver_reserved() -> void:
	for id in reserved.duplicate():
		if observed.has(id):
			reserved.erase(id)
			continue
		if status == "playing" and place_route_s.has(id) and trip_s >= float(place_route_s[id]) - DELIVER_AHEAD_M:
			reserved.erase(id)
			observed[id] = true
			var s := statement(id, true)
			statement_heard.emit(id, s, true)
			_after_action()


## 같은 직업을 밝힌 사람들. {role_key: [place_id, ...]} 중 2명 이상인 것만.
func duplicate_claims() -> Dictionary:
	var by_role := {}
	for id in observed.keys():
		var r := shown_role(int(id))
		if r == "GOSSIP" or r == "" or obscured.has(int(id)):
			continue
		if not by_role.has(r):
			by_role[r] = []
		by_role[r].append(int(id))
	var out := {}
	for r in by_role.keys():
		if by_role[r].size() > 1:
			out[r] = by_role[r]
	return out


# ---------------------------------------------------------------- 행동

## obscure=true면 터널 잡음으로 직업을 못 듣는다(진술 내용은 들린다).
## 보너스 통화가 있으면 예산 대신 그것을 쓴다.
func investigate(id: int, obscure := false) -> Dictionary:
	if status != "playing" or is_final_phase() or observed.has(id):
		return {}
	observed[id] = false
	if obscure:
		obscured.append(id)
	if bonus_calls > 0:
		bonus_calls -= 1
	else:
		used += 1
	clock = used * rule("callTime")
	var s := statement(id, false)
	statement_heard.emit(id, s, false)
	_after_action()
	return s


func stakeout(id: int) -> Dictionary:
	if status != "playing" or not stakeout_available().has(id):
		return {}
	observed[id] = true
	var s := statement(id, true)
	statement_heard.emit(id, s, true)
	_after_action()
	return s


func raid(id: int) -> Dictionary:
	if status != "playing" or revealed.has(id):
		return {}
	revealed.append(id)
	clock += rule("raidTime")
	var hit := is_hidden(id)
	var actual := actual_role(id)
	if hit:
		caught.append(id)
	else:
		reputation -= int(data["rules"]["wrongRaidCost"])
	if is_final_phase():
		final_raids_left -= 1
	raided.emit(id, hit, actual)
	_check_end()
	_offer_stakeouts()
	return {"hit": hit, "actualRole": actual, "shownRole": true_shown_role(id)}


## 들은 진술 중 동시에 참일 수 없는 쌍 하나. 없으면 빈 배열(신뢰도 차감 없음).
func hint() -> Array[int]:
	for c in data["hints"]["contradictions"]:
		var a := int(c["a"])
		var b := int(c["b"])
		if observed.has(a) and observed.has(b) \
				and observed[a] == bool(c["aStakeout"]) and observed[b] == bool(c["bStakeout"]):
			reputation -= int(data["rules"]["hintCost"])
			_check_end()
			var pair: Array[int] = [a, b]
			return pair
	var none: Array[int] = []
	return none


## 데모 힌트(용의 장소 검색)의 비용: 신뢰도를 깎는다. 0이 되면 해임.
func spend_hint() -> void:
	reputation -= int(data["rules"]["hintCost"])
	_check_end()


## 신호 대기 보너스 통화. 판당 max_per_case번까지. 주면 true.
func grant_bonus_call(max_per_case := 1) -> bool:
	if status != "playing" or is_final_phase() or bonus_granted >= max_per_case:
		return false
	bonus_granted += 1
	bonus_calls += 1
	return true


## 신호가 바뀌면 쓰지 않은 보너스 통화는 사라진다.
func revoke_bonus_call() -> void:
	bonus_calls = 0


func calls_left() -> int:
	return budget() - used + bonus_calls


func set_memo(id: int, tag: String) -> void:
	if tag == "":
		memos.erase(id)
	else:
		memos[id] = tag


## 경로 재생기가 매 프레임 넣는다. 새로 지나가는 길가 장소가 있으면 잠복 찬스를 알린다.
func set_trip_progress(p: float) -> void:
	_use_trip = true
	trip_progress = clampf(p, 0.0, 1.0)
	_offer_stakeouts()


## 도착 5분 전. 탐문 예산이 남았어도 최종 단계로 들어간다.
func enter_final_phase() -> void:
	if status == "playing" and not is_final_phase():
		final_raids_left = n_evil() - caught.size() + 1
		final_phase_started.emit(final_raids_left)


## 목적지 도착. 아직 못 잡은 조직원은 도주한다.
func arrive() -> void:
	if status == "playing":
		status = "escaped"
		ended.emit(status)


# ---------------------------------------------------------------- 내부

func _after_action() -> void:
	if used >= budget():
		clock = maxf(clock, rule("finalPhaseStart"))
		enter_final_phase()
	_offer_stakeouts()


func _offer_stakeouts() -> void:
	if status != "playing":
		return
	for id in stakeout_available():
		if not _offered.has(id):
			_offered.append(id)
			stakeout_offered.emit(id)
	for id in stakeout_passed():
		if not _missed.has(id):
			_missed.append(id)
			stakeout_missed.emit(id)


func _check_end() -> void:
	if status != "playing":
		return
	if caught.size() == n_evil():
		status = "won"
	elif reputation <= 0:
		status = "fired"
	elif is_final_phase() and final_raids_left <= 0:
		status = "escaped"
	if status != "playing":
		ended.emit(status)


static func _has_id(arr: Array, id: int) -> bool:
	for x in arr:
		if int(x) == id:
			return true
	return false
