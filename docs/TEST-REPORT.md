# 검수 보고서

판정은 `통과 / 실패 / 미검증` 중 하나만 씁니다. 자동 검사로 확인한 것과 확인하지 못한 것을 구분합니다.

# 1단계 3/5: 실험실 화면·분석 도구 통합 (v0.1.0-dev)

## 1. 대상 기록

| 항목 | 기록 |
| --- | --- |
| 검수 일시 / 담당 | 2026-10-07 / 제작 AI(Claude Code) — 워크트리 5개(SlimeGeo·MapView·InfoPanel·LabMain·분석 도구)를 main 에 병합 |
| 엔진 | Godot 4.4.1-stable, Compatibility(GL) 렌더러 |
| 실행 환경 | 클라우드 리눅스 컨테이너 4코어. 화면은 가상 디스플레이(xvfb) + **llvmpipe**(Mesa 25.2, CPU 소프트웨어 GL) — 실제 GPU 아님 |
| 범위 | `scripts/view/*`, `scripts/ui/*`, `scenes/lab.tscn`, `config/ui.json`, `tests/view/*`, `tests/*_capture.gd`, `tests/ui_driver.gd`, `tests/perf_capture.gd`, `tools/analyze.py` |

## 2. 검사 결과

```
godot --headless --path . --script res://tests/run_tests.gd                  RESULT: 150 checks passed, 0 failed
godot --headless --path . --script res://tests/run_tests.gd -- --skip-slow   RESULT: 150 checks passed, 0 failed
godot --headless --path . --script res://tests/run_view_tests.gd             RESULT: 262 passed, 0 failed (view)
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd
                                                                             RESULT: 29 passed, 0 failed (ui)   (1280×720 도 29/0)
python3 -m unittest discover -s tools -p "test_*.py"                         Ran 22 tests … OK
```

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| V01 | 화면을 거쳐 진행해도 역사 해시가 헤드리스와 같음(프레임 구동 480틱, 실제 `_process` 64배 약 800틱, 지도 검사 150틱) | 통과 | smoke_checks, map_checks, lab_checks, ui_driver |
| V02 | 실제 MapView·SlimeGeo·InfoPanel 로 지도 클릭(실제 마우스 입력) → `pick_slime` → 정보 창 같은 id | 통과 | ui_driver |
| V03 | 메시 예산(슬라임 398·식물 112·열매 80·저장고 312·밭 148·고리 288 삼각형), 닫힌 슬라임 곡면 | 통과 | geo_checks |
| V04 | 실험을 바꿔도 앞 세계의 저장고·밭이 남지 않음 | 통과(통합 때 고침) | map_checks — 고치기 전 64배 장면(새 기본 세계, 문명 없음)에 fast_civ 의 저장고 4·밭 3 이 남아 보였음 |
| V05 | 화면 갱신 없이 세계만 진행한 뒤 `focus_on` 이 낡은 그린 위치가 아니라 지금 칸으로 | 통과(통합 때 고침) | map_checks |
| V06 | F 키 따라가기 ↔ 정보 창 "따라가기" 단추 상태 일치 | 통과(통합 때 연결) | lab_checks |
| V07 | 1600×900 에서 보통 개체(자식 두 줄 이하)의 정보 창이 스크롤 없이 두뇌 범례까지 들어감 | 통과(통합 때 간격 조정) | 정보 창 내용 높이 879 → 796px(보이는 높이 797px). `info.heatmap_cell` 16 → 14 등 |
| V08 | 캡처: 전경·농사 낮(저장고·밭 옆 개체)·같은 자리 밤·64배, 지도 3장, 정보 창 2장, 메시 모음 | 통과(눈으로 확인) | `docs/screenshots/v0.1/` (3D 장면은 JPG 품질 0.85, 100~160KB) |

## 3. 성능 실측

`tests/perf_capture.gd` (VIEW-API "성능 측정").

**① 헤드리스 미세 측정** — MapView `before_steps + update_view`, 프레임 600개(60fps 가정):

| 세계 · 배속 | 개체 | 화면 µs/프레임 평균(중앙 / 95%) | 틱 있는 프레임 / 없는 프레임 | 시뮬레이션 µs/프레임 |
| --- | --- | --- | --- | --- |
| 기본·250마리 · 1배 | 250 | **381** (326 / 924) | 654 / 350 | 333 |
| 기본·250마리 · 4배 | 174 | 429 (329 / 1,050) | 605 / 311 | 1,108 |
| 기본·250마리 · 64배 | 170 | 1,164 (1,153 / 1,678) | 1,164 / — | 19,054 |
| fast_civ 1,760틱 · 1배 | 170 | 274 (232 / 820) | 559 / 242 | 282 |
| fast_civ 1,760틱 · 64배 | 209 | 1,120 (1,109 / 1,377) | 1,120 / — | 21,869 |

**② 실험실 실측(xvfb + llvmpipe, 1600×900, 지도 MSAA 2×)** — 기본·씨앗 1 을 2,132틱(개체 200)까지 진행한 뒤 개체 하나를 골라 둔 채 각 10초:

| 배속 | 평균 FPS | 프레임 시간 중앙 | 우리 스크립트(`advance_frame`) | 그중 시뮬레이션 / 화면·UI | 실제 배속 | 개체 평균 | 그리기 호출 · 기본 도형 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1배 | **8.4** | 117.8ms | **3.84ms** | 2.71 / 1.13ms | 1.0배 | 236 | 176 · 40.6만 |
| 64배 | **8.7** | 112.5ms | **12.41ms** | 11.03 / 1.37ms | 7.4배 | 160 | 174 · 37.3만 |

- llvmpipe 는 CPU 로 그리므로 프레임 시간(중앙 112~118ms) 가운데 우리 스크립트 몫을 뺀 100ms 넘게가 그리기다. 우리 스크립트 몫은 1배 3.8ms·64배 12.4ms 로, 실제 GPU 에서 그리기가 수 ms 라면 1배는 60FPS 안, 64배는 시뮬레이션 예산(10ms)이 프레임을 정한다. MSAA 를 끄면 llvmpipe 1배 10.6FPS(참고).
- 64배의 실제 배속은 시뮬레이션 비용(200마리 근처에서 틱당 약 3~4ms)과 프레임당 예산 10ms 로 정해진다(헤드리스 지도 뼈대로 28~33배, llvmpipe 에서는 프레임이 느려 7~10배). 표시는 "목표 64배 / 실제 M배" 를 경고 색으로 정직하게 보인다.
- 기본 도형의 대부분은 식물(약 2,500포기 × 112삼각형). 실제 GPU 에서는 문제없는 양이지만, 느린 기기 대응이 필요하면 멀리서 식물 메시를 낮은 단계로 바꾸는 것이 첫 후보.

## 4. 미검증

| ID | 내용 | 이유 |
| --- | --- | --- |
| U02′ | 실제 GPU 에서 200마리 60FPS | 이 환경에는 GPU 가 없어 llvmpipe 로만 쟀음(위 ②). 우리 스크립트 몫(1배 3.8ms)만 확인 |
| U03 | Windows·macOS 에서 화면 실행 | 리눅스뿐 |

# 1단계 2/5: 시뮬레이션 핵심·헤드리스 실행기 (v0.1.0-dev)

## 1. 대상 기록

| 항목 | 기록 |
| --- | --- |
| 검수 일시 / 담당 | 2026-10-07 / 제작 AI(Claude Code) |
| 엔진 | Godot 4.4.1-stable (official 49a5bc7b6), GDScript, 헤드리스 |
| 실행 환경 | 클라우드 리눅스 컨테이너, 4코어. 화면 없음 |
| 범위 | `scripts/sim/*`, `config/*.json`, `tests/run_tests.gd`, `tests/run_experiment.gd`. 실험실 화면은 아직 없음 |

## 2. 검사 결과

```
godot --headless --path . --script res://tests/run_tests.gd
RESULT: 150 checks passed, 0 failed
```

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| S01 | 설정: 기본값·예설정 5종 검증, 알 수 없는 키·종류·범위·JSON 비왕복 값 거부 | 통과 | test_config |
| S02 | 시뮬레이션 코드에 매직 넘버 없음(상수 선언 밖 숫자는 0·1·2·0.5 만), 금지 수학 함수(sin·cos·exp·log·pow·tanh·randfn 등) 없음 | 통과 | test_static_rules (소스 정적 검사) |
| S03 | 난수: 같은 씨앗 같은 수열, 상태 문자열 저장·복원, 정규 근사 평균·분산 | 통과 | test_rng |
| S04 | 지형: 씨앗별 결정적, 통과 가능 영역 하나로 연결(씨앗 5개), 땅 비율 | 통과 | test_terrain |
| S05 | 두뇌: 12-8-8·유전자 163, 손으로 계산한 순전파 값, 기억 2 → 14-8-10·195 | 통과 | test_brain_layout_forward |
| S06 | 유전: 교차가 뉴런 덩어리를 깨지 않음, 돌연변이 0 → 그대로, 범위 자르기, float32 저장 | 통과 | test_brain_genetics |
| S07 | 세계 안 펼친 계산(순전파·영역 감지·정책 가중치) = 기준 함수, 비트 단위 | 통과 | test_world_think_matches |
| S08 | 밤 성장 0, 자원 0 → 먹이 0, 낮밤·계절 계산 | 통과 | test_plants_light_resources |
| S09 | 에너지 장부: 600틱 동안 (현재 합) − (처음 + 먹음 − 소비 − 번식 손실 − 죽을 때 남은 양) 오차 < 1e-6 | 통과 | test_energy_ledger |
| S10 | 굶주림·노화 사망과 기록, 번식(에너지 전달·부모·세대·쿨다운·미성숙·짝 반경·분열 선택), 개체 수 상한 | 통과 | test_death_causes, test_reproduction, test_population_cap |
| S11 | 발견: 발견 전 행동은 효과 없이 시도만 셈, 임계에서 정확히 한 번, 순서 강제, 저장고 위치·간격, 저장분 썩지 않음, 바닥 먹이 썩음, 싹, 심기 → 밭, 버려진 밭 복귀 | 통과 | test_discovery_*, test_storehouse_rules, test_farm_rules |
| **S12** | **같은 씨앗 → 같은 역사 해시·같은 시계열 CSV·같은 유전체, 다른 씨앗·다른 파라미터 → 다른 해시** | 통과 | test_determinism (1,500틱 × 4회) |
| **S13** | **저장·복원 왕복: 직렬화 → 복원 → 재직렬화 글자 일치, 복원 후 400틱 이어 돌린 해시 = 끊김 없이 돌린 해시**(기억 뉴런 켠 세계 포함). 버전·형식·유전체 길이·설정 불일치·깨진 JSON 거부, 깨진 파일 → .bak 복구·.broken 보관 | 통과 | test_snapshot_roundtrip, test_snapshot_files |
| **S14** | **자원량 0 → 최대 수명 안에 멸종**, 연대기에 기록 | 통과 | test_extinction_no_resources |
| **S15** | **평균 100세대 안에 농사(3단계)에 도달하는 파라미터 조합이 있음** | 통과 | test_farm_reachable: 예설정 `fast_civ`, 씨앗 1 → 평균 21.7세대에 농사 |
| S16 | 실행기: 인자 오류 거부, 결과 파일 5종·열 이름·행 수, 요약에 실제 설정, 설정 오류 코드 2 | 통과 | test_runner |
| S17 | 실행기 이어 돌리기(`--resume`) 해시 = 끊김 없이 돌린 해시 | 통과(수동) | 씨앗 42: 30세대(t=2,155) → 이어서 40세대 = 바로 40세대, 둘 다 t=2,940·개체 184·해시 165b2c158266 |
| S19 | GitHub Actions(ubuntu-latest): 검사 통과, 씨앗 1·100세대 해시 `713cea4dea1d` = 이 컨테이너의 해시(다른 리눅스 x86_64 기계 사이 결정성) | 통과 | [실행 37576513679](https://github.com/kyusang4657/slime-lab/actions/runs/37576513679) |
| S18 | 성능 기록: 개체·틱당 µs | 통과(기록) | test_performance: 평균 142마리, 17.8µs |

## 3. 1,000세대 실측

```
godot --headless --path . --script res://tests/run_experiment.gd -- --seed=1 --generations=1000 --out=results/g1000
RESULT: seed=1 generations=1000.0 ticks=109604 pop=250 civ=3(농사) hash=78891cb07b26 time=443.7s reason=generations
```

| 항목 | 값 |
| --- | --- |
| 걸린 시간 | **443.7초(7.4분)**, 평균 247틱/초, 개체·틱당 약 16µs. 실행 중 일부 구간은 검사(run_tests)와 CPU 를 나눠 씀 |
| 목표 | 설계 13절 "수 분, 목표 5분 이내" → **5분 목표는 실패**(7.4분). "수 분"에는 들어옴 |
| 틱·세대 | 109,604틱, 세대당 평균 약 110틱(초반 약 70틱, 후반 약 130틱 — 크기가 작아지는 진화와 함께 길어짐) |
| 출생·사망 | 132,456 / 132,406, 개체 수는 대부분 상한 250 |
| 발견 | 채집 t=2,737(평균 40.5세대) → 저장 t=3,573(54.9세대, 저장고 4개) → 농사 t=9,440(140.7세대). 끝날 때 밭 209칸 |
| 특성 변화 | 크기 1.00 → 0.63, 감지 반경 3 → 1(둘 다 하한 근처까지 줄어듦 — 대사 비용 압력), 평균 에너지 24 → 19 |
| 결과 파일 | summary 3KB, timeseries 720KB, chronicle 1.4KB, lineage 8.3MB(132,706행), final.snapshot 7.0MB |

5분 안에 넣는 방법(다음 단계에서 결정): ① 상한 250 → 200(약 1.25배), ② 시뮬레이션 핵심을 C#/GDExtension 으로(SIM-API 경계). 지금은 수치를 더 비틀지 않고 실측을 그대로 둡니다.

## 4. 미검증

| ID | 내용 | 이유 |
| --- | --- | --- |
| U01 | Windows·macOS 에서 같은 역사 해시 | 이 환경은 리눅스뿐. 설계상 사칙연산·sqrt·정수 난수만 써서 같아야 하지만 확인하지 못함 |
| U02 | 화면(200마리 60FPS, 64배속) | 화면 단계 전 |

## 5. 구현 중 바꾼 설계·수치 (근거)

| 항목 | 초안 → 지금 | 이유 / 확인 |
| --- | --- | --- |
| 행동 고르기 | argmax → 확률적 정책 `(1 + softsign(o))^4` 비례 (`brain.policy`, `brain.sharpness`) | 무작위 두뇌 127마리 중 "이동+먹기"를 섞는 개체가 1마리뿐(나머지는 한 행동만 반복)이라 첫 세대가 씨앗 3개 모두 240틱 안에 멸종 |
| 짝 찾기 | 같은 칸·4이웃 → 반경 2칸 정사각형 (`repro.mate_radius`) | 짝을 만나지 못해 번식이 거의 없음 |
| 계절 | 4일·겨울 0.1 → 2일·겨울 0.3 | 겨울(240틱)이 수명 한 번만큼 길어 매해 겨울 끝에 멸종. 혹독한 겨울은 예설정 `harsh_winter` 로 남김 |
| 에너지·번식 | 한입 2 → 3, 기본 대사 0.12 → 0.06, 성장 0.06 → 0.12, 번식 에너지 0.55 → 0.35, 몫 0.35 → 0.3, 쿨다운 20 → 10 | 첫 세대가 자기 수를 잇지 못함(씨앗 3개 × 조합 6가지 시험) |
| 세대 시간 | 성숙 40 → 30, 최대 나이 240 → 200, 상한 400 → 250, 초기 120 → 200 | 1,000세대를 수 분 안에(세대당 약 120틱 → 약 80틱). 성숙 30·나이 180 은 씨앗 1 이 멸종해 버림 |
| 판단 간격 | 성능이 모자라면 2 | 2 로 하면 씨앗 3개 모두 멸종(먹기·돌기 반복 낭비) → 1 유지 |
| 스냅숏 실수 | JSON 숫자(full_precision) → 비트 문자열 | Godot 4.4.1 `JSON.stringify(full_precision=true)` 가 0.1+0.2 → "0.3", 1e-300 → "0.0" (직접 확인) |
| 저장 발견 집계 | 모든 내려놓기 → 채집 발견 뒤의 내려놓기만 | 발견 순서 강제를 규칙으로도 보장 |
