# Dupery 분석: 1인 마피아는 어떻게 성립하는가

> 조사 시점: 2026-10-20
> 근거: Steam 스토어 페이지, 팬 위키(miraheze), 프리뷰·출시 기사.
> 유튜브 영상은 찾았지만 본문과 자막을 도구로 추출할 수 없어서 직접 분석하지 못했다(영상 목록은 맨 아래).

## 1. 개요
- **정식 제목:** *Dupery: A Game of Solo Deduction*
- **제작:** Gilded Rune Games(영국 브리스톨, 3인 스튜디오). 퍼블리셔는 Yogscast Games(PlateUp! 퍼블리셔)다.
- **출시:** 2026-10-15 Steam(Windows/macOS), 한국어 지원, ₩18,500
- **평가:** 조사 시점 기준 Very Positive(리뷰 446개 중 84% 긍정)
- **장르:** 혼자 하는 마피아(소셜 디덕션) + 로그라이트
  - 배경은 범죄 조직에 잠식된 누아르 도시이고, 플레이어는 형사다.
- **원형:** *Blood on the Clocktower*(BotC)를 바탕으로 했다.
  - 역할 4분류가 BotC의 Townsfolk / Outsider / Minion / Demon과 1:1로 대응한다.
  - Empath, Mathematician, Poisoner, Drunkard 같은 역할 이름도 BotC에서 왔다.
- **개발 의도:** "서류 작업의 지루함 없이 진짜 형사가 된 느낌"을 주는 것이다.
  - 사람의 표정과 태도를 읽는 기존 마피아의 추리를, **진술들 사이의 논리적 모순을 찾는 구조 분석**으로 옮겼다.
  - 프리뷰 기사는 *Papers, Please*와 *Return of the Obra Dinn*에 비유했다.

## 2. 한 판(케이스)의 진행
1. **보드:** 3x3 격자에서 시작하고, 진행하면서 4x4로 커진다. 칸마다 주소가 있고, 각 주소의 문 뒤에 역할 한 명이 산다.
2. **용의자 목록과 비율:** 어떤 역할이 이번 판에 있을 수 있는지(suspected), 그리고 진영별 인원 상한이 표시된다.
   - 상한 예시: Meddler 최대 4, Underling 최대 4, Traitor 1
3. **조사(Investigate):** 주소를 길게 눌러 문을 연다.
   - 게임 내 시간이 **2시간** 흐른다.
   - 역할의 정체가 공개되고, 그 역할이 정보를 말하거나(announce) 능력을 쓰게 해준다.
4. **진술의 형태:** 자유로운 대화가 아니라 **능력의 출력값**이다. 숫자, 주소, 개수 같은 것이다.
   - Teacher: 인접한 열에 있는 악역 수
   - Mathematician: 악역 주소의 합
   - Wife: 무고한 파트너의 주소
   - Priest: "나는 Priest다"(스스로 신원을 증명)
5. **체포(Arrest):** 체포하면 정체가 공개된다.
   - 선한 역할을 체포하면 **평판 -2**, 악역을 체포하면 손해가 없다.
6. **종료 조건:** 악역을 모두 체포, 사망, 전향시키면 해결이다. 평판이 0이 되면 해고되고 런이 끝난다.
7. **시간 압박:**
   - 시계탑이 무작위 시점에 종을 울린다.
   - Judge는 의사봉을 친 직후 즉시 체포하지 않으면 평판이 깎인다.
   - Ticking Clock 같은 quirk는 24시에 해결하면 페널티를 준다.

## 3. 마피아를 1인용으로 바꾼 장치
| 원래 마피아 요소 | Dupery의 대체 장치 |
|---|---|
| 사람이 하는 거짓말과 연기 | **규칙으로 정해진 거짓말** 4종 (아래 표) |
| 사회자 | 게임 시스템 자체 |
| 밤의 살해 | Serial Killer(선한 역할만 살해), Sawbones(평판이 나쁘면 무작위로 살해) 같은 역할 능력 |
| 낮 투표와 처형 | 체포. 오판하면 평판이라는 비용을 치른다 |
| 다른 사람에게서 오는 사회적 압박 | 시간 비용(조사 1회 = 2시간)과 Judge 의사봉 같은 강제 이벤트 |
| 매판 다른 사람과 하는 변화 | 역할 200개 이상 × 무작위 배치 × quirk 조합 |

### 규칙으로 정해진 거짓말 4종
| 장치 | 내용 |
|---|---|
| **Lying(거짓 진술)** | 악역의 진술은 틀린 값이다. 다만 오차 범위가 정해져 있어서 추론할 수 있다(예: 거짓말하는 Mathematician의 오차 범위). |
| **Pretend(신분 위장)** | 악역이 다른 역할인 척한다. 위장할 수 있는 대상은 역할마다 다르다(판에 있는 역할 / 없는 역할 / 의심 목록의 역할). |
| **Taint(오염)** | Poisoner 같은 악역이 **선한 역할을 강제로 거짓말하게** 만든다. 착한 사람도 믿을 수 없게 된다. |
| **Obscure(은폐)** | Jinx, Spectre가 정체 자체를 가린다. |

- **Meddler(선하지만 말썽꾼):** 선한 편이라 체포하면 평판이 깎이지만, 훼방을 놓는다.
  - 예: Drunkard는 자신이 다른 선한 역할이라고 믿는다.
  - 이 역할이 "수상하지만 무고한 사람"이라는 마피아 특유의 긴장을 만든다.
- 본질적으로는 **지뢰찾기와 스도쿠 같은 논리 퍼즐에 마피아 스킨과 서사를 입힌 구조**다.
  - 격자, 인접 칸 개수 정보, 확정 정보로 연쇄 추론하는 방식이 그렇다.

## 4. 런(로그라이트) 구조
- **리드 선택:** 시작할 때 리드 3개 중 하나를 고른다. 리드가 정하는 것:
  - 지역
  - 격자 크기
  - 케이스 수(Standard 6~8, Challenge 8~10)
  - 고정 Prime Suspect 5명
- **케이스 사이 보상:** 케이스를 해결할 때마다 관할 확장(격자 확대)이나 단서 3개 중 하나를 고른다.
  - 단서 종류: quirk, 평판 회복, 케이스 추가, 특정 역할을 반드시 등장 또는 미등장으로 고정
- **마지막 케이스:** 반드시 Traitor가 있다.
- **지역과 해금:** 지역은 3개(Office / Casino / Docks)이고, 지역마다 고유 역할과 규칙이 있으며 끝에 조직 간부가 나온다.
  - 역할과 quirk 티어 9개를 모두 해금하면 최종 보스 런이 열린다.

## 5. 재미 포인트
1. **"아하" 모먼트:** 진술 사이의 모순을 찾아내는 순간이 핵심이다.
   - 언제나 논리적으로 풀 수 있게 만들어져 있어서, 틀려도 납득할 수 있다.
2. **불완전한 정보 속 리스크 관리:**
   - 더 조사하면 시간이 들고 나쁜 이벤트가 생길 위험이 있다.
   - 지금 체포하면 오판 위험이 있다.
   - 평판은 실수를 몇 번까지 허용하는 생명력 역할을 한다.
3. **조합에서 오는 다양성:** 역할 수가 많고, 역할끼리 상호작용하고, quirk가 붙으면서 매판 다른 퍼즐이 된다.
4. **직접 만드는 수사 보드:** 펜, 핀, 실로 플레이어가 직접 정리하기 때문에 "내가 풀었다"는 소유감이 생긴다.
5. **짧은 단위의 반복:** 1케이스는 짧고, 여러 케이스가 모여 1런이 된다. "한 판만 더"를 부르는 구조다.

## 6. 우리 게임(차량 + Gleo)에 주는 시사점
### 그대로 가져올 것
- **진실은 엔진이 쥔다:** 거짓말을 규칙으로 생성해야 퍼즐이 공정하다.
- **짧은 케이스 + 이어지는 런 구조.**
- **평판 같은 실수 허용 장치.**
- **역할 4분류 체계.** 정직, 말썽꾼, 조직원, 보스로 구성한다.

### 차량에 맞게 바꿀 것
| Dupery | 차량 / Gleo 버전 |
|---|---|
| 마우스로 격자 클릭, 화면을 오래 보며 판단 | 음성으로 조사하고, 화면은 흘깃 확인하는 용도로만 쓴다 |
| 숫자와 좌표 위주의 진술 | 지도 위 공간 관계형 진술. 들은 단서가 지도에 도형으로 남는다 |
| 정해진 대사 | LLM이 캐릭터 말투로 표현한다. 내용은 엔진이 만든다 |
| 펜, 핀, 실로 만드는 수사 보드 | 지도 레이어 + Gleo 요약 |
| 게임 내 시계 | 실제 남은 이동 시간(ETA) + 실제 주행 이벤트 |

→ 구체적인 설계는 [concept-v0.md](../concept-v0.md)에 있다.

### 주의
- 메커니즘은 참고해도 괜찮지만, 역할 이름, 텍스트, 아트, 누아르 콘셉트를 그대로 가져오지 않는다.

## 출처
- [Steam: Dupery](https://store.steampowered.com/app/3845070/)
- [Steam: Dupery Demo](https://store.steampowered.com/app/4111760/Dupery_Demo/)
- [DuperyWiki: Main Page](https://dupery.miraheze.org/wiki/Main_Page)
- [DuperyWiki: Dupery](https://dupery.miraheze.org/wiki/Dupery)
- [DuperyWiki: Demo](https://dupery.miraheze.org/wiki/Demo)
- [DuperyWiki: Quick Tips](https://dupery.miraheze.org/wiki/Quick_Tips)
- [DuperyWiki: Investigate](https://dupery.miraheze.org/wiki/Investigate)
- [DuperyWiki: Arrest](https://dupery.miraheze.org/wiki/Arrest)
- [DuperyWiki: Pretend](https://dupery.miraheze.org/wiki/Pretend)
- [DuperyWiki: Tainted](https://dupery.miraheze.org/wiki/Tainted)
- [DuperyWiki: Role](https://dupery.miraheze.org/wiki/Role)
- [indiegame.com 프리뷰](https://indiegame.com/en/archives/34769)
- [Rogueliker 출시 기사](https://rogueliker.com/dupery-game-out-now/)
- [CogConnected 출시일 기사](https://cogconnected.com/2026/10/dupery-a-game-of-solo-deduction-is-launching-on-steam-on-15th-october/)

### 참고 유튜브 영상
- [Can You Figure Out Which Suspect Is Evil? - Dupery](https://www.youtube.com/watch?v=8qxIam_Wcrc)
- [20 Minutes of … Dupery](https://www.youtube.com/watch?v=oxBMJQ9zBE8)
- [A SOLO DEDUCTION ROGUELITE THAT WILL DEVOUR YOUR TIME](https://www.youtube.com/watch?v=GAPB-oW5XW8)
- [I'm Solving Crimes in this Detective Roguelike](https://www.youtube.com/watch?v=_EBBFxIMlBw)
- [Official Playtest Trailer](https://www.youtube.com/watch?v=a8fivbWA9Js)
