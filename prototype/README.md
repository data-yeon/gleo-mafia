# 퍼즐 엔진 프로토타입 (Python)

[concept-v0](../docs/concept-v0.md)의 공통 규칙(12개 역할, 단서 7종, 잠복, 오염)을 구현한 퍼즐 생성기와 솔버다.
Godot 데모에는 여기서 검증한 퍼즐을 JSON으로 내보내서 쓴다.
결과 분석은 [docs/prototype-report.md](../docs/prototype-report.md)에 있다.

Python 3.9 이상, 표준 라이브러리만 쓴다(3.12 권장). 모든 명령은 이 폴더(`prototype/`)에서 실행한다.
난이도: `easy`, `normal`, `hard`, `phishing`(보이스피싱 사업부: 사칭범, 익명 제보). 규칙은 룰 v1(내비 Dupery)이다.

## 직접 플레이
```bash
python3 play.py
```
```bash
python3 play.py --preset phishing --seed 3
```
`t 3` 탐문(통화), `s 4` 잠복(지나가는 동안만), `r 6` 출동, `l` 정리, `h` 힌트, `m 3 의심` 메모, `map` 지도, `q` 포기.
`--cmds "t 1; s 4; l"`처럼 명령을 미리 넣으면 그대로 재생한다(같은 seed면 같은 사건).

## 대량 통계
```bash
python3 batch.py --n 200
```
난이도별로 200개를 생성해서 최소 탐문 수, 봇 해결률, 오급습 수를 요약한다. 결과는 `out/`에 저장된다.

## Godot용 퍼즐 팩 내보내기
```bash
python3 export_pack.py --per-preset 10 --out out/pack
```
형식은 [docs/puzzle-pack-schema.md](../docs/puzzle-pack-schema.md)에 있다. Godot 데모용으로는 `--out ../godot/data/puzzles`로 내보낸다.

## 튜토리얼 '수습 첫날' 팩
```bash
python3 tutorial_pack.py
```
장소 6곳, 행동대원 1명, 말썽꾼 없음, 통화 5번이다. 다음 순서가 반드시 나오는 시드를 골라 `../godot/data/puzzles/tutorial-<seed>.json`으로 내보낸다.
1. 첫 통화로 경우가 준다.
2. 같은 직업 두 명의 말을 다 믿으면 0가지가 된다.
3. 길가 현장 확인이 가짜를 가린다.
4. 가짜 말을 빼면 1가지가 남는다.

팩에는 `"tutorial": {first, pair, stakeout}` 대본이 붙고, 팩 목록(index.json)에는 넣지 않는다. 설명은 [docs/tutorial-and-map-plan.md](../docs/tutorial-and-map-plan.md)에 있다.

## 테스트
```bash
python3 -m unittest discover -s tests
```

## 구조
| 파일 | 내용 |
|---|---|
| `puzzle/model.py` | 역할, 단서, 장소 |
| `puzzle/city.py` | 가상 도시(도로 그래프, 강·다리, 공원, 블록), A* 경로(이동 시간 + 회전 벌점, 유턴 금지), 경유지 경로, 경로 계획(회전 안내, 신호, 지하차도) |
| `puzzle/board.py` | 경로형 보드(번호 = 지나가는 순서, 왼편/오른편, 길가 2~3곳, 최소 간격 700m). 기본은 가상 도시 위 A* 경로(`make_city_board`), 테스트용 합성 곡선 경로(`make_board`)도 남아 있다 |
| `puzzle/rules.py` | 난이도 구성, 오염 규칙 |
| `puzzle/generator.py` | 진실 배정 → 진술 생성 → 답이 하나인지 검증 |
| `puzzle/solver.py` | 가능한 세계를 모두 대입하는 솔버, 최소 탐문 수, 모순 쌍 |
| `puzzle/bot.py` | 자동 플레이 봇(smart / random) |
| `puzzle/game.py` | 한 판의 진행 규칙(탐문, 잠복, 급습, 힌트, 최종 단계) |
| `puzzle/text.py` | 진술 문장과 대사 템플릿 |
