# 퍼즐 팩 JSON 스키마 (`gleo-mafia.puzzle/3`)

## v3에서 추가된 것 (가상 도시 + A* 경로)
- **`city`:** 데모용 가상 도시.
  - `grid`: `{cols, rows, river}`
    - `nodes`는 행 우선 순서다(`j * cols + i`).
    - 강은 `river`행과 `river+1`행 사이에 있다.
    - Godot이 도시 바깥 외곽(그림만)을 이어 그릴 때 쓴다.
  - `nodes`: 교차로 좌표 `[[x, y], ...]`
  - `roads`: `{a, b, cls(arterial/local/bridge), name, lanes}`
  - `water`, `parks`, `blocks`: 폴리곤 목록
- **`routePlan`:** A* 경로 계획.
  - `nodes`: 지나는 교차로
  - `nodeS`: 교차로까지의 거리(m)
  - `segments`: `{name, cls, from, to, cruise}`
  - `maneuvers`: `{s, icon, verb, road, at?, waypoint?}`
  - `stops`: `{s, dwell, node}`
  - `tunnels`: 지하차도 `{from, to, name}`
  - `waypoints`, `originName`, `destName`
- **`route`:** `routePlan`의 둥근 모서리 폴리라인이다. 원점은 출발 교차로다.
- **`places[].landmark`:** 랜드마크 모델 id. `godot/assets/models/landmarks/landmarks.json`에서 이름을 먼저 찾고, 없으면 업종으로 찾는다.
- **`statements[].stakeout`:** 이제 모든 장소에 있다(경유지 잠복 대비). 솔버·봇은 길가 장소의 잠복만 쓴다.
- **`hints.contradictions`:** 모든 장소의 잠복 진술 조합을 포함한다.
- **Godot:** `RoutePlan.from_pack(data)`가 `routePlan`을 그대로 읽는다. `routePlan`이 없는 예전 팩은 합성 경로 계획으로 대신한다.

---

아래는 v2 기준 설명이고, 위 추가분 말고는 그대로다.

Python 퍼즐 공장(`prototype/`)이 만들고, Godot 데모가 읽는 사건 파일 형식이다. 룰 v1(내비 Dupery) 기준이다.
파일 하나 = 사건 하나. `index.json`에는 팩 안의 사건 목록이 있다.

```bash
cd prototype
python3 export_pack.py --per-preset 4 --out ../godot/data/puzzles
```

## v1(`puzzle/1`)에서 바뀐 점
- **단서 교체:** `HALF`, `NEAR`를 없애고 `SPAN`(경로 구간), `SIDE`(경로 왼편/오른편), `NEIGHBOR`(지나가는 순서상 앞뒤)를 추가했다.
- **장소 필드 추가:** `side`, `routeDistM`, `anonymous`. `splits`는 없어졌다.
- **시간 규칙 추가(`rules`):** `finalPhaseStart`, `callTime`, `raidTime`, `stakeoutPass`
  - 잠복은 다가갈 때부터 지나칠 때까지만 할 수 있다.
- **역할 추가:** 사칭범 `IMPOSTER`(보이스피싱 사업부)
- **익명 제보:** 익명 제보 장소는 `statements[].shownRole`이 `null`이다. 결과 화면용 실제 위장 직업은 `truth.shownRoles`에 있다.
- **역할 표:** `roles[key].clue`가 `clues`(배열)로 바뀌었다. 택시기사는 `SPAN` 또는 `ROAD`를 쓴다.

## 공통 규칙
- **장소 번호(id):** 1부터 시작하고, **지나가는 순서**와 같다. 화면과 음성에서도 이 번호를 쓴다.
- **좌표:** 미터 단위다. `x`는 동쪽, `y`는 북쪽이고, 원점은 경로 출발점이다.
  - Godot 2D로 옮길 때는 `Vector2(x, -y) * scale`처럼 y를 뒤집는다.
- **숫자:** Godot `JSON.parse_string`은 숫자를 float로 읽는다. id를 비교할 때는 `int()`로 바꾼다.
- **역할 키:** `VENDOR, TAXI, DRONE, LOCAL, RIDER, GUARD, COP, GOSSIP, DRUNK, THUG, IMPOSTER, BLACKMAILER, BOSS`.
  - 화면에 보일 이름은 `roles[key].label`에 있다.

## 최상위 필드
| 필드 | 내용 |
|---|---|
| `schema`, `id`, `seed` | 형식 버전, 사건 id(`phishing-1000`), 생성 시드 |
| `preset` | `key`, `label`, `budget`(통화 수), `evil`(악역 역할 목록), `meddlers`(말썽꾼 수), `meddlerTypes` |
| `nHonest` | 이번 판에 나온 정직 직업 수(7개 중) |
| `rules` | `startReputation`, `wrongRaidCost`, `hintCost`, `roadsideM`, `bossTaintM`, 시간 규칙(아래) |
| `roles` | 역할 키별 `label`, `side`(honest / meddler / evil), 정직 역할은 `clues`(단서 유형 배열) |
| `anonymousLabel` | 익명 제보자 표시 이름("익명 제보") |
| `route` | 경로 폴리라인 `[[x, y], ...]` |
| `places[]` | `id`, `name`, `kind`, `x`, `y`, `side`(왼편/오른편), `roadside`, `routePos`(0..1), `routeDistM`, `anonymous` |
| `statements[]` | 장소별 진술. 아래 표 참고 |
| `truth` | `hidden`(숨은 곳 id), `roles`(실제 역할), `shownRoles`(실제로 밝힌·위장한 직업), `tainted` |
| `hints.contradictions[]` | 동시에 참일 수 없는 진술 쌍 `{a, aStakeout, b, bStakeout}` |
| `analysis` | 최소 탐문 수, 봇 플레이 결과(난이도 참고용) |

### 시간 규칙 (`rules`)
이동 전체를 진행률 0..1로 본다.

| 키 | 뜻 |
|---|---|
| `finalPhaseStart` | 이 진행률(도착 5분 전)부터 최종 단계. 출동만 가능 |
| `callTime` | 차량 진행 정보가 없을 때 통화 1회에 흐르는 진행률 (= `finalPhaseStart ÷ budget`) |
| `raidTime` | 출동 1회에 흐르는 진행률 |
| `stakeoutLookahead`, `stakeoutPass` | 길가 장소는 `routePos - lookahead ≤ 진행률 ≤ routePos + pass`일 때만 잠복할 수 있다. 지나치면 끝 |

Godot 데모처럼 차량 시뮬레이션이 있으면 진행률은 **차량 위치**를 쓴다(`set_trip_progress`).

## `statements[]`
| 필드 | 내용 |
|---|---|
| `placeId` | 장소 id |
| `shownRole` | 탐문했을 때 밝히는 직업. 위장한 경우 실제와 다르다. 익명 제보면 `null` |
| `clue` | 진술 내용. 지도에 그릴 정보가 들어 있다 |
| `fact` | 정리 화면용 중립 문장 |
| `line` | 제보자 대사 템플릿. LLM이 말투를 바꾸지 못하면 이 문장을 TTS로 쓴다 |
| `stakeout` | 잠복 진술(`clue`, `fact`, `line`). 길가 장소만 있고, 나머지는 `null`. **항상 참** |

## `clue` 유형별 필드와 지도 표시 (내비 오버레이 문법)
| `type` | 필드 | 지도에 그릴 것 |
|---|---|---|
| `RADIUS` | `center`, `radiusM`, `members`, `count` | 주변 검색 반경 원 |
| `SPAN` | `from`, `to`(장소 id), `members`, `count` | 경로에서 `from`~`to` 구간 하이라이트 |
| `SIDE` | `side`(왼편/오른편), `members`, `count` | 경로 기준 한쪽 음영 |
| `NEIGHBOR` | `center`, `members`(2곳), `count` | 지나가는 순서상 앞뒤 연결 |
| `KIND` | `kind`, `members`, `count` | 업종 필터 칩, 같은 업종 핀 강조 |
| `ROAD` | `bufferM`, `members`, `count` | 경로를 따라 폭 `bufferM` 띠 |
| `VOUCH` | `target`, `claim`(suspicious / clean) | 화자 → 대상 화살표(빨강 / 초록) |
| `REVEAL` | `target`, `claim`(disguised / genuine) | 대상 핀에 배지 |

- `count` 단서는 "`members` 중 숨은 곳이 `count`곳"이라는 뜻이다.
- `members`는 엔진이 이미 계산해 둔 값이다. Godot에서 다시 계산할 필요가 없다.
- `NEIGHBOR`에서 처음과 마지막 장소는 한쪽 두 곳(①은 ②③, ⑨는 ⑦⑧)을 가리킨다.

## 런타임에서 할 일 (솔버 불필요)
| 기능 | 데이터 |
|---|---|
| 탐문(통화) | `statements[id-1]`을 읽어 대사를 재생하고 `clue`를 그린다. 익명이면 직업 대신 `anonymousLabel` |
| 잠복 찬스 | `places[].roadside`와 시간 규칙의 잠복 창. 지나치면 "놓쳤어요" 알림 |
| 출동 | `truth.hidden`, `truth.roles`, `truth.shownRoles` |
| 힌트 | `hints.contradictions` 중 두 장소를 모두 들었고 잠복 여부도 같은 쌍 |
| 같은 직업 중복 안내 | 들은 진술들의 `shownRole`을 센다(익명, 오지랖 제외) |

Godot 구현: [godot/scripts/puzzle_case.gd](../godot/scripts/puzzle_case.gd). Python 쪽 원본은 [prototype/puzzle/game.py](../prototype/puzzle/game.py)이다.
두 구현이 같은 규칙으로 동작하는지는 `godot/tests/test_puzzle_case.gd`로 확인한다(Godot 4.7.2, 사건 16개 569개 확인 통과).
