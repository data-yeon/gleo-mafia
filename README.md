# 수사망 (Gleo Mafia)

자율주행 중 내비 지도 위 실제 장소 9곳에서 조직원이 숨은 곳을 도착 전에 음성으로 추리하는 1인 게임입니다. 현대자동차그룹 차량용 앱 개발 공모전 출품작입니다.

![Pleos 차량 화면 위의 수사망](docs/images/pleos-shell-case.png)

## 소개

- 이동 1회 = 사건 1판, 도착 시각 = 마감
- 본부 제보 9통 중 2통은 조직이 건 가짜. 가짜 제보가 걸려 온 장소에 조직원이 있음
- Gleo(차량 AI 비서)가 수사 파트너이자 제보자 역할
- 도착 시각·터널·신호 대기·길가 장소 같은 주행 상황이 그대로 게임 규칙이 됨
- 정답이 하나뿐인 퍼즐만 사용(Python 퍼즐 공장이 솔버로 검증)

## APK

- 설치용 APK: [Releases](https://github.com/data-yeon/gleo-mafia/releases)
- 앱 이름 `수사망`, 패키지 `com.gleo.mafia`, 최소 Android 9(API 28)
- 설치: `adb install -r <APK 파일>`

## 폴더 구성

| 폴더 | 내용 |
| --- | --- |
| `godot/` | 게임 앱(Godot 4.7.2, GDScript). 실행 인자·단축키·테스트는 [godot/README.md](godot/README.md) |
| `godot/addons/pleos_vehicle/` | Pleos Vehicle SDK 연결용 플러그인(AAR)과 내보내기 스크립트 |
| `android_plugin/` | 위 플러그인의 소스(Kotlin, Gradle) |
| `prototype/` | 퍼즐 공장(Python): 퍼즐 생성, 솔버 검증, JSON 퍼즐 팩 내보내기 |
| `docs/` | 컨셉, 이야기 설정, 데모 계획, 결과 보고서 |
| `tools/` | 3D 에셋(Blender) 스크립트, 영상 녹화 스크립트 |

## 실행 방법

### 데스크톱에서 실행(Godot 4.7.2)

```bash
godot --path godot
```

주행 화면이 시작되고 잠시 뒤 Gleo가 사건을 제안합니다. 배속·일시정지 같은 단축키는 [godot/README.md](godot/README.md)에 있습니다.

### Android에서 실행

1. [Releases](https://github.com/data-yeon/gleo-mafia/releases)에서 APK를 내려받습니다.
2. `adb install -r <APK 파일>`로 설치합니다.
3. 앱 목록에서 `수사망`을 실행합니다. Pleos Connect 에뮬레이터 준비는 아래 테스트 환경을 참고하세요.

### 직접 빌드(APK)

1. Godot 4.7.2와 같은 버전의 내보내기 템플릿을 설치합니다.
2. Android SDK(플랫폼 34·35, build-tools 35 이상)와 JDK(17 이상, 22에서 확인)를 설치하고 Godot 에디터 설정에 경로를 지정합니다. 디버그 서명용 키스토어도 에디터 설정의 경로에 있어야 합니다.
3. Godot에서 프로젝트 > Android 빌드 템플릿 설치를 실행합니다(`godot/android/`가 만들어지며 저장소에는 포함하지 않음).
4. 내보내기 프리셋 `Android`(Gradle 빌드 사용)로 내보냅니다. 명령줄은 아래와 같습니다.

```bash
godot --headless --path godot --export-debug "Android" ../build/gleo-mafia-debug.apk
```

Vehicle SDK 플러그인을 고쳤다면 `android_plugin/`에서 AAR을 다시 만들어 복사합니다(`local.properties`에 `sdk.dir` 필요).

```bash
cd android_plugin
gradle :plugin:assembleRelease
cp plugin/build/outputs/aar/plugin-release.aar ../godot/addons/pleos_vehicle/PleosVehicle.aar
```

## 테스트 환경과 필요한 설정

- Pleos Connect v2.1.0 에뮬레이터: Automotive, API 34, arm64, RAM 4GB, 콜드 부팅. 설치는 공모전 공식 가이드의 SDK Update Sites 절차를 따릅니다.
- Android 최소 SDK 28, 대상 SDK 35, Gradle 8.10.2, Android Studio 2026.2.1
- 권한: `pleos.car.permission.CAR_DOORS`
- Vehicle SDK `ai.pleos.playground:Vehicle:2.3.2`(Pleos Maven 저장소). 공식 가이드의 2.3.1은 저장소에 없어 2.3.2를 사용했습니다.
- 규칙 테스트: `godot --headless --path godot --script res://tests/test_case_flow.gd` 등(전체 목록은 [godot/README.md](godot/README.md))
- 퍼즐 공장 테스트: `cd prototype && python3 -m unittest discover -s tests`

## 현재 상태

| 항목 | 상태 |
| --- | --- |
| 사건 한 판 전체 흐름(가상 경로) | 동작 |
| Pleos Connect 에뮬레이터 실행 | 확인 |
| Vehicle SDK 연결, 도어 위치 조회 요청 | 연결과 요청 전달 확인, 응답 값 확인 중 |
| NaviHelper·FusedLocation·음성 SDK | 연동 예정(현재 가상 경로, 버튼·템플릿 대사) |

## 문서

- [컨셉](docs/concept-v0.md), [이야기 설정](docs/story-bible.md), [데모 계획](docs/demo-plan.md), [프로토타입 결과](docs/prototype-report.md)

## 라이선스

별도 라이선스를 지정하지 않았습니다(공모전 심사 목적으로 공개).
