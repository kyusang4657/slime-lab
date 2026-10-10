# 검수 보고서

판정은 `통과 / 실패 / 미검증` 중 하나만 씁니다. 자동 검사로 확인한 것과 확인하지 못한 것을 구분합니다.

# 1단계 검토 고침: 전체 검토 121개 (v0.1.0)

5단계까지 마친 v0.1.0 을 처음부터 다시 검토해 확인된 문제 121개를 고친 기록입니다. 아래 5단계~2단계 절은 그때의 기록이라 결과를 다시 쓰지 않았고, 이 고침으로 값이 바뀐 곳에는 "(검토 고침 뒤 다시 잼: …)" 처럼 짧게 표시해 이 절로 잇습니다.

## 1. 대상 기록

| 항목 | 기록 |
| --- | --- |
| 검토 대상 | `3a7f2c0`(v0.1.0 — 5단계 마무리, 2026-10-08) |
| 검토·고침 일시 / 담당 | 2026-10-10 / 제작 AI(Claude Code) — 검토는 에이전트 약 280개, 고침은 워크트리 6묶음(g1 시뮬레이션·설정·스냅숏 / g2 실행기·분석 도구 / g3 실험실 / g4 패널 / g5 3D 지도 / g6 빌드·CI) |
| 고친 커밋 | 묶음별 고침(`f51ed39` ~ `e590dc3`) → 병합(`b968a66` ~ `219fac0`) → 병합 정리(`d2dda28`·`13b074d`·`bafa017` — 묶음 사이 넘김 메모 반영, 규칙 고침 뒤 새 역사에 맞춘 화면 검사·캡처) → 수치 다시 재기·캡처·타임랩스·분석 예시(`bf3209a`) → 문서(이 절·README·VIEW-API, DESIGN) → 최종 확인 고침(11절) |
| 엔진 | Godot 4.4.1-stable, Compatibility(GL) 렌더러 |
| 실행 환경 | 클라우드 리눅스 컨테이너 4코어(GPU 없음). 화면은 xvfb + llvmpipe(CPU 소프트웨어 GL), 웹은 헤드리스 Chromium(SwiftShader WebGL2). 오디오 장치 없음(xvfb 실행 로그의 ALSA `ERR_CANT_OPEN` 한 줄은 그 몫 — 스크립트 오류 아님). 여러 에이전트가 CPU 를 나눠 써 시간 수치는 같은 날 같은 조건끼리만 견줌. Windows 내보내기 재현용 wine64 를 설치해 둠 |
| 범위 | 저장소 전체(시뮬레이션·설정·실행기·분석 도구·3D 지도·실험실·패널·검사·빌드·CI·문서). 포트폴리오 저장소(kyusang4657.github.io)의 10개는 이 저장소 밖 |

## 2. 검토 방법

- **1차(12개 영역):** 시뮬레이션 규칙, 데이터 형식·실행기, 3D 지도, 실험실, 패널, 자동 검사 품질, 원칙, 빌드·CI, 문서, 포트폴리오, 동적 퍼징, 실제 화면. 영역마다 검토자 한 명이 코드를 읽고 직접 돌려 봤다.
- **검증:** 발견마다 검증자가 반박을 시도했다 — 중간 이상은 두 명(재현 / 설계·문서와의 대조), 낮음은 한 명. 둘이 갈리면 세 번째가 결판을 냈다.
- **2차(8개 영역):** 1차 결과의 빈틈을 따로 점검해 긴 실행·누수, 웹판 실제 입력, 데스크톱 종단, 설정 키의 뜻, 이전 저장소 원칙, 엑셀·Windows 이식성, 화면 크기·배율, 결과 파일 일관성을 더 봤다.
- **정리:** 발견 156건 가운데 검증을 견딘 148건과 결판 중에 새로 찾은 1건을 같은 원인끼리 합쳐 **121개**(I01~I89·J01~J34, I87·I88 은 합쳐져 빈 번호). 시간 수치는 판단 근거로 쓰지 않았다(비율이나 부하와 무관한 근거만). 2차에서도 새 문제가 나왔으므로 "이제 더 없다" 고 보장하지는 못한다.
- **고침:** 문제마다 원인을 고치고 헤드리스 검사를 더했다. **고친 것마다 그 고침을 잠시 되돌려 새 검사가 실패함을 확인**했다(4절 "고치기 전"). 문서만 고친 것은 "문서".

## 3. 결과 요약

- **최종 판정: 저장소 안의 111개를 고침(코드·검사 95개 + 문서 16개), 그중 I52 는 일부를 까닭과 함께 남김. 최종 독립 확인(11절)에서 일부만 고쳐진 것·새로 찾은 것을 마저 고침. 포트폴리오 10개는 포트폴리오 저장소 몫(이 기록 때 남음). 자동 검사는 이 컨테이너와 Actions 에서 모두 통과, Pages 배포·1,000세대 5분·`fast_civ` 세대 목표는 실패, Windows·실제 GPU 는 미검증**
- 통과 / 실패 / 미검증: 확인 항목 K01~K14 **9 / 3 / 2**(K09 Pages 배포, K10 1,000세대 5분, K11 `fast_civ` 세대 목표 / K13 Windows·플랫폼 간, K14 실제 GPU). 미검증 전체는 9절
- 다음 확인 순서: 저장소 소유자가 Pages 를 켜고 체험판 주소가 열리는지(K09) → Windows 실기에서 zip 실행·역사 해시·사용자 폴더·명령줄 안내(K13) → 실제 GPU 에서 실험실 60FPS·웹 속도(K14) → 1,000세대 5분 방안 결정(K10)

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| K01 | 규칙 검사 전체(느린 검사 포함) | 통과 | 8절 `RESULT: 360 checks passed, 0 failed` |
| K02 | 화면 구성 요소 검사(헤드리스) | 통과 | 8절 `RESULT: 1301 passed, 0 failed (view)`(두 번), 로그에 `SCRIPT ERROR`·`^ERROR:` 없음 |
| K03 | 파이썬 검사(분석 도구·실행기 명령줄·빌드·설정 이름표·저장소 규칙·설계 형식 표) | 통과 | 8절 `Ran 101 tests … OK` |
| K04 | 실제 화면(xvfb 1600×900·1280×720) 동작·캡처 | 통과 | ui_driver 53·52 passed, 캡처 다시 찍음(7절) |
| K05 | 고친 것마다 고침을 되돌리면 새 검사가 실패 | 통과(묶음마다 수동 확인) | 4절 "고치기 전" 열(코드 고침 95개 모두) |
| K06 | 같은 씨앗 → 같은 역사·저장 복원 뒤 이어 돌려도 같음, 이제 밭 단계까지 | 통과 | `test_determinism`·`test_snapshot_roundtrip`(I09·I10), 실행기 `--resume`(test_runner_cli) |
| K07 | GitHub Actions(#12 `bafa017`·#13 `bf3209a`) test·export | 통과 | 10절 |
| K08 | 다른 리눅스 x86_64 기계 사이 결정성 | 통과 | 씨앗 1·100세대 `171a3a4f1a5f` — Actions #12·#13 = 이 컨테이너 |
| K09 | GitHub Pages 체험판 배포 | **실패** | 저장소 Pages 꺼짐(`has_pages = false`), #9~#13 의 pages 잡 모두 실패(#8 은 test 실패로 건너뜀) — 소유자 설정 몫(10절) |
| K10 | 헤드리스 1,000세대 "목표 5분 이내"(설계 13절) | **실패** | 733.8초(12.2분, 기계가 느린 날 — 같은 날 고침 전 코드도 같은 속도, 7절) |
| K11 | `fast_civ` 세대 목표(저장 15~35·농사 30~70 중앙값, TUNING) | **실패** | 규칙 고침 뒤 5.7·14.3세대(고침 전 8.6·15.9). 100세대 안 농사 12/12 는 그대로, 멸종 2/12(6절) |
| K12 | 웹(wasm) ↔ 리눅스 데스크톱 역사 해시 | 통과(수동 탐침) | 검토 때(고침 전 코드) 7경우, 고침 뒤 코드(`bf3209a`)로 다시 8경우 — 시뮬레이션·설정만 담은 탐침을 4.4.1 `web_nothreads_release` 로 내보내 헤드리스 Chromium(SwiftShader)과 리눅스 데스크톱에서 돌려 역사 해시 64자·에너지 합 비트까지 모두 같음(default 11·1500, fast_civ 1·3400(밭 7), default 42·2500, default 7(800틱 멸종), fast_civ 3·3000, default 5·기억 2·1000, harsh_winter 9·800, demo_fast 2·1500(밭 67)). CI 검사는 아님(DESIGN §20) |
| K13 | Windows 실행·Windows/macOS 와 리눅스의 역사 해시 | 미검증 | Windows·macOS 기기 없음(9절) |
| K14 | 실제 GPU 에서 200마리 60FPS | 미검증 | GPU 없음, llvmpipe 로만 잼(7절) |

**문제 수 — 심각도 × 영역:**

| 영역 | 높음 | 중간 | 낮음 | 사소 | 합 | 문제 |
| --- | --- | --- | --- | --- | --- | --- |
| 패널 | — | 4 | 13 | — | 17 | I14·I15·I44·I45·I46·I47·I48·I49·I50·I51·I86·J05·J06·J17·J18·J19·J20 |
| 시뮬레이션 규칙 | — | 3 | 12 | — | 15 | I08·I24·I25·I26·I27·I28·I29·I30·I31·J02·J03·J11·J12·J13·J14 |
| 문서 | — | 1 | 11 | 2 | 14 | I18·I61·I62·I63·I64·I65·I66·I67·I68·I82·J21·J22·J23·J34 |
| 자동 검사 | — | 5 | 8 | — | 13 | I09·I10·I11·I12·I32·I33·I34·I35·I36·I37·I38·I89·J15 |
| 실험실 화면 | — | 2 | 6 | 2 | 10 | I13·I39·I40·I41·I42·I43·J04·J16·J32·J33 |
| 빌드·CI·라이선스 | — | 2 | 5 | 3 | 10 | I16·I17·I56·I57·I58·I59·I60·I79·I80·I81 |
| 포트폴리오 | — | — | 8 | 2 | 10 | I69·I70·I71·I72·I73·I74·I75·I76·I83·I84 |
| 실행기·분석 도구 | — | 3 | 5 | 1 | 9 | I05·I06·I07·I20·I21·I22·I23·J10·J31 |
| 설정 검사 | 1 | 3 | 2 | — | 6 | I01·I02·I03·I85·J01·J09 |
| 3D 지도 | — | — | 4 | — | 4 | I52·I53·I54·I55 |
| 플랫폼·화면 크기 | — | 1 | 3 | — | 4 | J08·J28·J29·J30 |
| 데이터 형식 | — | 1 | 3 | — | 4 | J07·J25·J26·J27 |
| 원칙 | — | — | 3 | — | 3 | I77·I78·J24 |
| 스냅숏 | — | 1 | 1 | — | 2 | I04·I19 |
| **합** | **1** | **26** | **84** | **10** | **121** | |

**동작을 그대로 두고 계약을 고친 것:** I25(저장고 최대 수 — 첫 저장고를 세는 범위 1~100000), I29(저장 발견은 ③ 내려놓을 때 — 주석·문서), J11(빛 곡선 — 낮 비율·황혼의 뜻), J12(바닥 먹이 더미 타이머 — 마지막 내려놓기부터). 코드가 옳다고 보고 이름표·문서·검사를 맞췄다. I35 는 제안한 "모두 굶주림" 이 지금 코드에서도 틀려(노화 사망도 섞임) "대부분 굶주림·마지막 틱 굶주림·모든 죽음에 원인" 으로 검사했다.

## 4. 문제별 고침

"지키는 검사" 의 모듈: run_tests = `tests/run_tests.gd`(규칙), `*_checks` = `tests/view/*_checks.gd`(화면), test_* = `tools/test_*.py`(파이썬). "고치기 전" = 그 고침을 잠시 되돌렸을 때(또는 고치기 전 코드에서) 그 검사가 낸 실패 문장. 묶음이 둘 이상 고친 문제는 주요한 것만 적었다.

| ID | 심각도 | 영역 | 고친 것 | 지키는 검사 | 고치기 전(되돌렸을 때) |
| --- | --- | --- | --- | --- | --- |
| I01 | **높음** | 설정 검사 | sim-labels 의 모든 범위를 `SimConfig.validate` 규칙(`RULES`)으로 — 나눗수 키는 '0 초과', 지도 잡음 칸 1~1024, 감지 반경 0.5~64. 패널은 SimConfig 오류를 그 줄 아래에 | run_tests `test_config_rules`(나눗수 키 0 거부·최솟값에서 NaN 없음·실행기 2), test_sim_labels `test_every_range_is_checked`, param_checks `_advanced_zero`·`_checked_ranges` | 실패: 0 나눗수 키에 0 을 거부(통과한 키: carry.max, plants.max_food … 12개) |
| I02 | **중간** | 설정 검사 | 절 키에 사전을 넣으면 거부, `validate` 첫 단계 `_check_shape`(빠진·모르는 키·값 종류·배열 길이). 실행기는 세계를 만들다 멈추면 설정 오류 2 | run_tests `test_config_rules`, test_runner_cli `test_section_override_is_config_error` | 실패: 절(body)에 사전을 넣으면 거부 / 실행기 `0 != 2` |
| I03 | **중간** | 설정 검사 | 정수 키(기본값 파일에 소수점 없이 적힌 키)는 정수만, 모든 키에 하한(부호), 황혼 ≤ 낮 × 낮 비율 ÷ 2·나이 흔들림 < 최대 나이. 설정 오류는 결과 폴더를 보기 전에 | `test_config_rules`, test_runner_cli `test_bad_values_are_config_errors`·`test_config_error_keeps_previous_results` | 실패: 정수 키 population.initial = 150.7 거부 / metab.base = -1.0 거부 |
| I04 | **중간** | 스냅숏 | `SimSnapshot.validate` 가 하위 키·종류·길이·칸 번호·16진 16자·유한값까지 보고, 깨지면 `.bak` 으로·`.broken` 보관. 실험실은 끊긴 읽기 결과를 실패로(실험 0개 실험실이 되지 않음) | run_tests `test_snapshot_corrupt`(손상 17종 → 최종 확인에서 형식·난수 상태 종류 5종 더해 22종), experiment_checks `_load_results`, lab_checks `_args`·`_toast_rules` | 실패: 구조가 틀린 스냅숏 17종을 오류 문장으로 거부(샌 것: civ.discovery_tick 없음 …) / SCRIPT ERROR |
| I05 | **중간** | 실행기·분석 도구 | `--resume` 과 `--seed`·`--preset`·`--set` 을 함께 주면 인자 오류 2. 이어 돌린 summary.json 은 preset ""·overrides {}·`resumed_from`·`resume_status`, analyze 묶음 이름 snapshot | test_runner_cli `TestResume`(같은 해시·인자 조합), test_analyze `test_snapshot_cell_name` | `AssertionError: 0 != 2 : --seed=9` |
| I06 | **중간** | 실행기·분석 도구 | 이어 돌릴 스냅숏이 깨져 `.bak` 에서 읽으면 경고 줄, summary.json 에 실제로 읽은 파일·`resume_status = backup` | test_runner_cli `test_resume_from_backup_is_reported` | `AssertionError: '경고' not found …` |
| I07 | **중간** | 실행기·분석 도구 | summary.json 은 CSV 를 모두 쓴 뒤 마지막에(임시 이름 → 바꾸기), CSV 하나라도 실패면 쓰지 않음. analyze 이어 돌리기는 실패·덜 쓴 결과를 다시 돌림. 실험실 내보내기도 같은 순서 | run_tests `test_recorder_files`, test_analyze `test_failed_or_incomplete_is_rerun`·`test_incomplete_reason`, test_runner_cli(실제 실행기), experiment_checks `_export_order` | 실패: chronicle.csv 를 못 쓰면 summary.json 이 없음 / `Lists differ: [] != ['--seed=1', …]` |
| I08 | **중간** | 시뮬레이션 규칙 | 처음부터 개체 0 인 세계는 setup 에서 틱 0 멸종(사건 하나), 실험실은 진행하지 않아 실행기와 같은 한 줄 | run_tests `test_empty_start`, experiment_checks `_empty_start` | 실패: 처음부터 개체 0 → 틱 0 멸종·멸종 사건 하나(extinct_tick -1, 사건 0개) |
| I09 | **중간** | 자동 검사 | 밭 단계 기준 실행(demo_fast·씨앗 2·1,000틱, 600틱 스냅숏)으로 왕복 뒤 400틱 이어 돌리기(밭 잃음 포함)·모든 상태 변수 같음 | run_tests `test_snapshot_roundtrip` | `farm_visit` 를 스냅숏에서 빼면: 실패: 밭 단계 스냅숏에서 400틱 이어 돌린 해시·전체 상태 = 끊김 없이 돌린 것 |
| I10 | **중간** | 자동 검사 | 결정성 검사가 밭 단계(첫 밭·밭 잃음 약 28번)까지 두 번 돌려 해시·CSV·전체 상태를 견줌 | run_tests `test_determinism` | 밭 칸에 전역 난수를 섞으면: 실패: 밭 단계: 같은 씨앗 → 같은 역사 해시·시계열 CSV |
| I11 | **중간** | 자동 검사 | 밭·문명 규칙 값 단위 검사: 심기 반경·성장 배수·겨울 하한·방문 갱신, 저장고 수·간격·싹 반경·줍기 조건·운반 상한·죽을 때 내려놓기 | run_tests `test_farm_rule_values`·`test_civ_rule_values` | winter_floor 를 빼면: 실패: 밭은 max(계절 배수, winter_floor 0.4) 로 … 밭 0.0900(기대 0.1200) |
| I12 | **중간** | 자동 검사 | 기억 뉴런 0·2 세계 모두에서 세계 안 순전파 = 기준 함수, 기억 입력·되먹임(softsign), 교차 덩어리, 손 계산 순전파 | run_tests `test_world_think_matches`·`test_brain_genetics`·`test_brain_layout_forward` | 실패: 기억 2: 판단 뒤 기억 값 = softsign(기억 출력)(틀린 값 120) |
| I13 | **중간** | 실험실 화면 | 멸종한 세계는 더 진행하지 않음(실행기의 끝 조건과 같게) — 다시 재생·비교 모드 한쪽 멸종에도 그 틱 그대로, 위쪽 막대 "멸종 · 진행 끝" | experiment_checks `_extinct`·`_extinct_fast`·`_compare_extinct`, lab_checks `_extinction`·`_compare_extinction` | 실패: 멸종 뒤 100틱·10프레임 더 진행시켜도 세계는 멸종한 틱 221 그대로(틱 321, …) |
| I14 | **중간** | 패널 | 씨앗 칸을 실수 SpinBox 에서 글 칸(십진 정수·64비트)으로 — 식·소수·글자 섞임은 줄 아래 오류, Enter·초점 빠짐·단추·실제 클릭이 같은 규칙 | param_checks `_seed_enter`·`_seed_click`·`_bad_text` | 실패: 씨앗 칸 + Enter: "42 f" → 씨앗 42, "2+3" → 씨앗 5 … |
| I15 | **중간** | 패널 | 시점 표시가 마지막 기록 줄 뒤면 가로축을 그 틱까지 넓힘(그 세계가 지난 틱만), 배치 열쇠에 시점 틱 | graph_checks `_cursor_tail_checks`(integration4 ③ 의 세 그래프 `last_cursor` 는 그 장면의 첫 밭 틱이 이미 가로축 안이라 I15 를 잡지 못함 — 최종 확인에서 고침을 되돌려 봐도 통과) | 실패: 마지막 기록 줄(틱 120) 뒤 사건(틱 126) 줄을 누르면 세 그래프 모두 시점 세로선(0개) |
| I16 | **중간** | 빌드·CI·라이선스 | 엔진이 알려 주는 라이선스로 `GODOT-LICENSE.txt`(엔진 MIT·제3자 88개·라이선스 15종)를 만들어 zip·웹 묶음에 고지 파일 넷 | test_build_ci `test_bundles_carry_notices`·`test_license_file_from_engine` | `AssertionError: … 웹 묶음에 고지 파일: ['index.html', …]` |
| I17 | **중간** | 빌드·CI·라이선스 | 워크플로 모든 단계 bash pipefail, RESULT 줄을 `reason=generations$` 까지 맞춤, 올림 파일이 없으면 실패. 실행기 쓰기 실패 = 종료 코드 3 | test_build_ci `test_every_run_step_uses_pipefail`·`TestWorkflowSteps`, test_runner_cli `TestWriteFailures` | 옛 단계: write_failed + 종료 코드 3 인 실행도 단계 종료 코드 0 |
| I18 | **중간** | 문서 | DESIGN 8.3 스냅숏 형식을 실제 `to_dict` 의 절·키로(문서 단계 — DESIGN 담당) | test_design_format `test_snapshot_keys_listed`(문서 마무리 `6a8cead` 에서 더함) | 문서 |
| I19 | 낮음 | 스냅숏 | CSV·JSON 을 쓴 뒤 다시 열어 길이 확인(디스크 가득 = 실패), 검증 실패 `.tmp` 지움, 실패 문장에 파일 이름 | run_tests `test_recorder_files`(16k tmpfs 디스크 가득 재현은 수동) | 실패: 검증 실패 → 임시 파일을 지우고 파일 이름을 담은 실패 문장(`.tmp` 가 남음) |
| I20 | 낮음 | 실행기·분석 도구 | `--max-ticks`·`--snapshot-every`·`--seed`·`--generations` 를 글자 그대로 검사(1e5·10k·abc 거부), 틱 상한 1e9 | test_runner_cli `test_bad_numbers_rejected`·`test_limits_accepted` | `Lists differ: ['--max-ticks=1e5 → 종료 코드 0', …] != []` |
| I21 | 낮음 | 실행기·분석 도구 | 같은 `--out` 을 다시 쓰면 실행기 파일만 지우고 새로, 모르는 파일·하위 폴더면 아무것도 지우지 않고 2, 이어 돌릴 스냅숏이 그 폴더 안이면 2 | test_runner_cli `TestOutDir`·`test_resume_inside_out_dir_refused`·`test_resume_inside_out_dir_by_other_path_refused`(최종 확인) | `Lists differ: [… 'final.snapshot.json.bak', 'lineage.csv' …] != [… 'run.log', 'summary.json', 'timeseries.csv']` |
| I22 | 낮음 | 실행기·분석 도구 | analyze `--generations` 는 실행기가 읽는 꼴만(1_0·inf 거부), `--godot` 상대 경로는 지금 셸 위치 기준 | test_analyze `test_generations_like_runner`·`test_relative_godot_path` | `SystemExit not raised : 1_0` |
| I23 | 낮음 | 실행기·분석 도구 | 이어 돌리자마자 끝나도 같은 틱 줄을 두 번 쓰지 않음(실험실과 같은 한 줄) | test_runner_cli `test_resume_that_ends_at_once_writes_one_row` | `Lists differ: ['70', '70'] != ['70']` |
| I24 | 낮음 | 시뮬레이션 규칙 | 한 틱에 한 번만 짝지음(쿨다운 0 이어도) | run_tests `test_mate_once_per_tick` | 실패: 기본·쿨다운 0·600틱: 한 틱에 두 번 짝지은 부모 76번 |
| I25 | 낮음 | 시뮬레이션 규칙 | 코드는 두고 계약을 고침: `store.max_count` 범위 1~100000(발견 때 짓는 첫 저장고 포함) | run_tests `test_store_max_count` | 실패: 저장고 최대 수 0 거부(빈 오류) |
| I26 | 낮음 | 시뮬레이션 규칙 | `first_farm_tick` 으로 "첫 밭" 사건은 세계마다 한 번(스냅숏 `civ.first_farm_tick`, 옛 스냅숏은 연대기에서) | run_tests `test_first_farm_once`, sound_checks `_first_farm_once` | 실패: 밭을 모두 잃고 다시 심어도 '첫 밭' 사건은 한 번(2번) |
| I27 | 낮음 | 시뮬레이션 규칙 | 저장고를 지을 때 그 칸 바닥 더미를 저장분으로(용량까지), 저장고 칸에서 죽은 개체의 운반분도 저장분으로 — **저장 단계 뒤 역사가 바뀜** | run_tests `test_store_takes_pile` | 실패: 저장고를 짓는 칸의 더미 70 → 저장분 0.0, 바닥 70.0 |
| I28 | 낮음 | 시뮬레이션 규칙 | 자식 에너지 상한 = 자식 최대 에너지, 넘는 몫은 번식 손실(장부 그대로) | run_tests `test_child_energy_cap` | 실패: 가득 찬 두 부모 · 비용 0.6 · 효율 1 → 자식 에너지 = 자식 최대(48.00 / 40.00) |
| I29 | 낮음 | 시뮬레이션 규칙 | 동작은 두고 틱 순서 주석·문서를 실제대로(저장 발견·저장고 짓기는 ③ 내려놓을 때) | run_tests `test_store_built_in_act` | 실패: sim_world.gd 머리의 틱 순서 주석이 실제 순서(저장고는 ③)를 적음 |
| I30 | 낮음 | 시뮬레이션 규칙 | 바닥 먹이가 정확히 `spoil_ticks` 틱 산 뒤 사라짐(한 틱 짧던 것) — **채집 단계 뒤 역사가 바뀜** | run_tests `test_spoil_lifetime` | 실패: 틱 7 에 내려놓은 먹이가 틱 96 에 사라짐 = 수명 89틱(spoil_ticks 90) |
| I31 | 낮음 | 시뮬레이션 규칙 | 지형 연결 요소를 한 번 훑기(칸 수에 비례)로 | run_tests `test_terrain`(예전 계산과 같은 결과)·`test_components_fast` | 실패: 연결 요소 계산 20072 ms < 3000 ms(요소 18432개) |
| I32 | 낮음 | 자동 검사 | 장부 검사에 저장고·운반분 먹기 단위 검사와 밭 단계 기준 실행의 매 틱 오차(지금 2.2e-8) | run_tests `test_energy_ledger` | 실패: 저장고 칸에서 먹은 에너지 2.700 가 장부에 같은 만큼 |
| I33 | 낮음 | 자동 검사 | 검사 함수마다 끝 표시 `done()` — 중간에 스크립트 오류로 끊기면 실패·종료 코드 1 | run_tests `test_runner_guards`(자기 검사 `selftest_abort_midway`) | 실패: … --only=selftest_abort_midway → 종료 코드 0(기대 1) |
| I34 | 낮음 | 자동 검사 | 합격 기준을 기계 속도에서 뗌: 성능 = 기준 일의 배수(< 1,750), 연결 요소 = BFS 한 번의 10배 안, 화면 예산 = 가짜 시계, 그래프 = 묶음에 넣은 줄 수. µs 는 출력만 | run_tests `test_performance`·`test_components_fast`, lab_checks `_budget_rule`, graph_checks `_long_checks` | 느린 기계 흉내(틱마다 11ms)에서 옛 lab_checks 5개 실패 — 새 검사 0개. 예산 규칙을 깨면 새 검사만 실패 |
| I35 | 낮음 | 자동 검사 | 자원 0 멸종의 원인까지: 대부분 굶주림, 마지막 틱도 굶주림, 모든 죽음에 원인(제안한 '모두 굶주림' 은 지금 코드에서도 틀려 약한 조건) | run_tests `test_extinction_no_resources` | 굶주림 규칙을 끄면: 실패: 자원 0 의 죽음은 대부분 굶주림(굶주림 0 · 노화 250) — 옛 검사는 통과 |
| I36 | 낮음 | 자동 검사 | 정적 검사를 허용 목록으로: 숫자는 0·1·2·0.5(1_000·.25·0b·1e6 도 잡음), 전역 함수·메서드 허용 목록, `**`·RandomNumberGenerator 금지 | run_tests `test_static_rules`, test_repo_rules `test_scanner_catches_known_forms` | 실패: 시뮬레이션 코드에 매직 넘버 없음: sim_world.gd:731 1_000, .25, 0b1011 |
| I37 | 낮음 | 자동 검사 | 화면 검사의 임시 파일·내려받기를 프로세스별 폴더(`…-<PID>`)로 두고 끝에 지움, 패널 스냅숏 시작 폴더를 바꿔 낄 수 있게 | lab_checks·web_checks(임시 폴더), param_checks `_snapshot`, chronicle_checks, lab_checks `_command_keys` 의 대화 상자 시작 폴더(최종 확인) | 실패: 내려받기는 이 검사의 임시 폴더에(… 실제 user://downloads 아님) |
| I38 | 낮음 | 자동 검사 | `series_points(graph, …)` = 그 그래프가 그린 점 수(`GraphView.series_point_count`), 종단 검사는 그래프마다 그린 선(`last_lines`)의 계열 | integration4 `_drawn_series`, graph_checks `_gen_compare_checks`·`_long_checks` | 변이(B 계열을 개체 수 그래프에만): 실패: 그래프 세 개가 저마다 계열 둘을 그림 [[0, 1], [0], [0]] — 옛 검사는 통과 |
| I39 | 낮음 | 실험실 화면 | 웹 임시 폴더 이름에 프로세스 번호를 쓰지 않음(웹 엔진에는 `get_process_id` 가 없음). 고친 웹판을 Chromium 에서 눌러 엔진 오류 없음 확인 | web_checks | 실패: 웹 임시 폴더 이름에 프로세스 번호 없음(user://web_export/20727-…) |
| I40 | 낮음 | 실험실 화면 | 웹 묶기 실패 = 알림 하나 + 실패한 파일 이름(비교면 B/…) | web_checks, param_checks `_fake_lab` | 실패: 웹 결과 내려받기 실패 → 오류 알림 하나(2개) |
| I41 | 낮음 | 실험실 화면 | 죽은(기록만 남은) 개체를 고른 채 F → 따라가기를 켜지 않고 "죽은 개체는 따라갈 수 없습니다" | lab_checks `_follow_dead` | 실패: 죽은 개체 #21 를 고른 채 F → … 알림 "따라가기 켬" |
| I42 | 낮음 | 실험실 화면 | 실험실 명령줄 `--seed 5`(띄어 씀)·int64 를 넘는 씨앗은 오류 알림, 알림에 실제로 쓸 값 | lab_checks `_args` | 실패: "--seed 5" → 오류 알림, 기본 씨앗(1) |
| I43 | 낮음 | 실험실 화면 | 설정 오류·첫 밭 문장의 숫자 뒤 조사를 없애고 정수 키는 정수로("설정 time.day_ticks = 1: 범위 2~100000 밖입니다", "첫 밭 — #N, (x, y) 에 심음") | `test_config_rules`, run_tests `test_farm_rules` | 실패: 범위 오류 문장: 설정 time.day_ticks = 1.0 가 범위 [2, 100000] 밖입니다 |
| I44 | 낮음 | 패널 | 두뇌 범례 끝 글을 반올림하지 않음(2.5 → "-2.5"·"+2.5") | param_checks `_brain_legend` | 실패: 두뇌 범례 끝(weight_clamp 2.5) = ["-2.5", "+2.5"] (그린 것 ["-2", "+2"]) |
| I45 | 낮음 | 패널 | 틱 축 비교 값 읽기에서 멸종한 실험은 "멸종 (틱 N)" | graph_checks `_gen_compare_checks`(최종 확인: 기록 간격이 다른 비교의 값 읽기는 `_interval_compare_checks`) | 실패: 틱 축 비교: 멸종한 뒤 틱의 A 줄 = "A 멸종 (틱 221)" (A — (이 틱 기록 없음)) |
| I46 | 낮음 | 패널 | 시점 이름 상자·멸종 이름을 계열 선 뒤(위)에 그림 | graph_checks(그린 순서 `seq`) | 실패: 시점 이름 상자를 계열 선보다 뒤에 그림 — 선 [2, 3, 4] · 이름 [1] |
| I47 | 낮음 | 패널 | 행동 이름 "왼쪽 돌기"·"오른쪽 돌기", 정보 창 운반 값에 단위("먹이 0.6") | run_tests `test_action_names`, info_checks `_labels` | 실패: 왼쪽·오른쪽 행동은 제자리 돌기, 이름도 "왼쪽으로"·"오른쪽으로" / 실패: 운반 값에 단위: "0.6" |
| I48 | 낮음 | 패널 | 멸종 안내가 보이면 클릭 도움말을 숨김 | info_checks `_labels`, lab_checks `_extinction`·`_compare_extinction` | 실패: 멸종 안내 아래에 클릭 도움말이 없음 |
| I49 | 낮음 | 패널 | 정보 창·실험 조건 패널의 자동 줄바꿈 글을 `UiTheme.keep_words` 로 낱말 단위 | info_checks `_wrap_split`, param_checks(`_split_words`) | 실패: 두뇌 없음 안내가 … 낱말 가운데서 끊기지 않음 ["…두뇌를 그", "릴 수 없습니다."] |
| I50 | 낮음 | 패널 | 확인·덮어쓰기·스냅숏 대화 상자를 실험실 모양으로(`style_dialog`), 높이를 글에 맞춤, 틱에 쉼표. 최종 확인에서 엔진 파일 대화 상자 안쪽 창(같은 이름 확인)도 | param_checks `_confirm`·`_engine_overwrite` | 실패: 확인 대화 상자 = 실험실 색(바탕 (0.25, 0.25, 0.25, 1.0) …) |
| I51 | 낮음 | 패널 | 그래프 평균 특성 이름 "감각" → "감지"(정보 창·README 와 같게) | graph_checks `_lab_checks` | 실패: 평균 특성 이름 "감지"(… "틱 600 / 감각 3.00 칸") |
| I52 | 낮음 | 3D 지도 | 땅·풀포기를 64² 칸 덩어리로 나눠 한 프레임에 덩어리 하나씩·바뀐 것만 갱신(256² 식물 약 23 → 1.7ms), 지도 크기 말풍선에 256×256 이하 권장, 최종 확인에서 넘는 실험을 열면 경고 알림. **일부 남김**(아래 "남긴 것") | map_checks `_check_big_map_cost`, lab_checks `_big_map` | 실패: 256×256: 한 프레임에 다시 보는 풀포기 55458·칸 65536 ≤ 덩어리 4096칸 |
| I53 | 낮음 | 3D 지도 | `pick_slime` 이 그린 메시 삼각형과 광선을 교차해 가장 앞 개체(맞지 않으면 예전 반경 고르기) | map_checks `_check_pick_depth` | 실패: 겹친 칸: 앞 개체 몸 위쪽을 누르면 앞 개체(#0 → 1, #1 → 0) |
| I54 | 낮음 | 3D 지도 | 저장고 문(과 문 앞 자리) 방향 = 남·동·서·북 가운데 지나갈 수 있는 첫 이웃, 저장고 메시도 그쪽으로. 최종 확인에서 붐빌 때 호를 막힌 이웃 쪽으로는 펼치지 않음 | map_checks `_check_store_blocked`·`_check_store_doorstep`·`_check_store_crowded` | 실패: 남쪽이 막힌 저장고: 문 앞 개체가 지도 안 지나갈 수 있는 칸 위(#2 칸(1,47) → 몸 가운데 (1.50, 48.10) …) |
| I55 | 낮음 | 3D 지도 | 지도 보기 조정 상수 9개를 ui.json 으로(겹침 둘레 상한 = stack_offset × stack_max_k), 소품 메시 수치를 이름 붙은 상수로 | map_checks `_check_ui_tuning`, geo_checks `_named_numbers` | 실패: map_view.gd 에 보기 조정 상수 없음 ["SIDE_WATER_DARK", …] |
| I56 | 낮음 | 빌드·CI·라이선스 | pages 잡이 main 푸시·"Run workflow" 에서 돎, `enablement` 제거(소유자가 한 번 켬), Pages 묶음 14일 보관 | test_build_ci `test_pages_condition`·`test_pages_steps` | `AssertionError: … Actions 탭 'Run workflow' 도 배포` |
| I57 | 낮음 | 빌드·CI·라이선스 | Windows 실행 파일에 아이콘·판 정보(rcedit v2.0.0 + wine, `LC_ALL=C.UTF-8`), build_dist 가 내보낸 파일의 판 정보를 확인 | test_build_ci `test_windows_preset_writes_version_info`·`test_export_problems_fail`·`test_export_job_order` | PE 정보가 CompanyName 'Godot Engine'·FileVersion '4.4.1' — 이제 build_dist 가 실패로 봄 |
| I58 | 낮음 | 빌드·CI·라이선스 | 판 번호를 project.godot `config/version` 하나에서, 태그 실행은 태그가 v<판> 이어야 | test_build_ci `test_zip_version_not_hardcoded`·`test_tag_must_match_version` | zip 이름에 판 번호를 박음 / v9.0.0 태그가 통과 |
| I59 | 낮음 | 빌드·CI·라이선스 | 액션을 Node 24 판으로(checkout@v5 등), 러너 ubuntu-24.04 고정 | test_build_ci `test_actions_target_node24`·`test_jobs_have_timeout_and_pinned_runner` | `actions/checkout@v4 는 Node 20 대상` / `'ubuntu-latest' != 'ubuntu-24.04'` |
| I60 | 낮음 | 빌드·CI·라이선스 | `tools/fetch_godot.sh`: 해시를 박아 둔 SHA512-SUMS.txt 로 Godot·템플릿을 확인한 뒤에만 풂, 받기 실패면 멈춤 | test_build_ci `TestFetchGodot` | 옛 단계: HTTP 404 에도 단계 종료 코드 0 |
| I61 | 낮음 | 문서 | DESIGN 앞 절의 규칙·API·키 서술을 구현대로(문서 단계 — DESIGN 담당) | — | 문서 |
| I62 | 낮음 | 문서 | 5단계 B12 의 발견 틱을 기록 기준(647·701·1,023)으로 바로잡고, 다시 찍은 타임랩스(씨앗 2: 374·422·812) 표시. 포트폴리오 캡션은 포트폴리오 고침에서 | — (실행기 summary.json `discovery_ticks` 로 확인) | 문서 |
| I63 | 낮음 | 문서 | DESIGN §11·§12: 종료 코드 3, '(검사)' 표시를 실제 검사와 맞춤(문서 단계 — DESIGN 담당). `--resume` 해시 일치는 이제 자동 검사 | test_runner_cli `test_resume_same_hash_and_summary`·`TestWriteFailures` | 문서 |
| I64 | 낮음 | 문서 | README 문서 링크(CONFIG·TUNING)·구조(sim-labels·`tools/test_*.py`·빌드 도구)·타임랩스 산출물(webm·mp4·gif·포스터) | — | 문서 |
| I65 | 낮음 | 문서 | README "바로 해 보기"·빌드 절: 체험판은 아직 배포 안 됨(Pages 를 켜야 함)을 사실대로 | — | 문서 |
| I66 | 낮음 | 문서 | 이 보고서: 3단계 마무리 고침 표를 3단계 절로 옮기고 F3-R1·F3-R2 로, 해결된 U05 표시 | — | 문서 |
| I67 | 낮음 | 문서 | VIEW-API: Experiment "완성(바꾸지 않음)" 지움, 상태 줄 순서, 연대기 검사 고정값(133틱·씨앗 17 의 291틱)·MIN 90(종단 검사 61개는 병합 정리에서) | — | 문서 |
| I68 | 낮음 | 문서 | README 그림 표: 밤 그림을 위 농사 장면(lab-02)과 같은 자리로 짝지음 | — | 문서 |
| I69 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I70 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I71 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I72 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I73 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I74 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I75 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I76 | 낮음 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I77 | 낮음 | 원칙 | 밤 문턱을 설정 키 `time.night_light_threshold`(0.5)로 — 규칙·화면(`LabMain.is_night`)·검사가 같은 키, 옛 스냅숏은 기본값으로 채움 | run_tests `test_night_threshold`·`test_snapshot_corrupt`, lab_checks `_night_threshold` | 0.5 를 다시 박으면: 실패: 문턱 0.9 · 빛 0.8 = 밤(감지 반경 × night_factor) |
| I78 | 낮음 | 원칙 | wasm ↔ 데스크톱 역사 해시 일치를 기록 — 검토 때 7경우, 규칙 고침 뒤 코드로 다시 8경우(K12), README·DESIGN §20 에 범위(수동 탐침·Chromium) | — (자동 검사 없음, 수동 기록) | 문서 |
| I79 | 사소 | 빌드·CI·라이선스 | CREDITS "가져와 고침" 표에 Actions 워크플로 | test_build_ci `test_credits_engine_notice_and_workflow_origin` | `… 가져와 고침 표에 워크플로(위치와 원래 파일)` |
| I80 | 사소 | 빌드·CI·라이선스 | 잡마다 `timeout-minutes`(test 20·export 15·pages 10·release 10) | test_build_ci `test_jobs_have_timeout_and_pinned_runner` | `export: timeout-minutes 없음(기본 360분)` |
| I81 | 사소 | 빌드·CI·라이선스 | `build/.gdignore` 를 저장소에, build_dist 도 만듦 | test_build_ci `test_build_gdignore_tracked` | 실제 가져오기에서 .import 3개 / `build/.gdignore 가 저장소에 없음` |
| I82 | 사소 | 문서 | 예시 보고서를 ANALYSIS 명령 그대로 다시 만듦(결과 폴더 이름) | test_analyze `test_example_reports_match_doc_commands` | `'- 결과 폴더: example-run …' not found` |
| I83 | 사소 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I84 | 사소 | 포트폴리오 | 포트폴리오 저장소(kyusang4657.github.io) — 이 저장소 밖, 포트폴리오 고침 단계에서 | — | — |
| I85 | 낮음 | 설정 검사 | `brain.policy` 는 sample·argmax 만, `seasons.growth` 원소는 0~100 의 수 | `test_config_rules` | 실패: brain.policy = "smaple" 거부 |
| I86 | 낮음 | 패널 | 정보 창 "고른 행동" — 아직 열리지 않은 단계의 줍기·심기는 "(시도 · 발견 전)" 흐린 글, 지도에서도 끄덕이지 않음 | info_checks `_labels`, map_checks `_check_attempt_bob` | 실패: 고른 행동: 단계 전 줍기·심기만 "(시도 · 발견 전)" |
| I89 | **중간** | 자동 검사 | "세계 그대로" 를 역사 해시 대신 스냅숏 모든 절로 견줌(`tests/view/world_compare.gd`, 규칙 검사는 `to_text`) | experiment_checks `_odd_tick`, integration4 `_chronicle_click`·`_snapshot`, web_checks, param_checks `_seed`, run_tests `test_extinction_mean_gen` | 변이(내보낸 뒤 세계 에너지를 바꿈): 실패: 내보내기 뒤 세계(스냅숏 모든 절) 그대로 — 옛 해시 검사는 통과 |
| J01 | **중간** | 설정 검사 | 틱 단위 키 상한 `SimConfig.TICK_MAX`(1e9) — 실행기 `--max-ticks`·`--snapshot-every`·실험실 진행도 그 틱까지 | `test_config_rules`, test_runner_cli `test_bad_numbers_rejected`, experiment_checks `_tick_cap` | 실패: 틱 단위 life.max_age = 3e9 거부 / 실패: 틱 상한 1000000000 에서 멈춤(틱 1000000003) |
| J02 | **중간** | 시뮬레이션 규칙 | 식물 갱신이 덮는 모든 틱의 (빛 × 계절) 합만큼 자람 — `plants.update_every` 는 성능용(성장량 같음). **기본 역사가 바뀜** | run_tests `test_growth_interval` | 실패: 갱신 간격 1·2·4·7·12·20·60 의 420틱 성장 합이 같음(간격 1: 24995.8 … 60: 0.0) |
| J03 | **중간** | 시뮬레이션 규칙 | 밭 버려짐을 성장과 떼어 매 틱 ①에서(성장 배수 0 이어도) — **농사 단계 뒤 역사가 바뀜** | run_tests `test_farm_abandon_any_growth` | 실패: farm.growth_mult 0: 밭이 틱 301 까지 남고 … (버려짐 사건 틱 -1) |
| J04 | **중간** | 실험실 화면 | `_process` 가 엔진이 자른 delta 대신 벽시계 간격을 넘김 — 7.5FPS 아래에서도 "실제 M배" 가 정직 | lab_checks `_slow_process` | 실패: 느린 프레임(400ms): 표시 실제 1.00배 ≈ 틱 ÷ 벽시계 0.33배 |
| J05 | **중간** | 패널 | 비교 중 스냅숏 저장은 실제로 쓸 -A/-B 파일을 보고 덮어쓰기를 물음. 최종 확인에서 엔진 대화 상자는 쓰지 않을 `<이름>.json` 을 묻지 않음(OS 대화 상자는 남김) | param_checks `_compare_save`·`_engine_overwrite` | 실패: 같은 이름으로 다시 저장 → -A/-B 를 적은 덮어쓰기 물음(물음 없이 덮어씀) |
| J06 | **중간** | 패널 | 저장 대화 상자가 떠 있는 동안 멈춤(이름의 틱 = 파일 안 틱) | param_checks `_save_hold` | 실패: 기본 이름의 틱 = 파일 안 틱(…tick12.json / 파일 틱 36) |
| J07 | **중간** | 데이터 형식 | 실행기·실험실·analyze 의 CSV 를 BOM 붙은 UTF-8 로(JSON 은 그대로), analyze 는 BOM 이 있어도 읽음 | run_tests `test_recorder_files`·`test_runner`, test_analyze `test_csv_has_bom`·`test_reads_bom_runner_csv` | 실패: timeseries.csv 는 BOM(EF BB BF) 붙은 UTF-8 |
| J08 | **중간** | 플랫폼·화면 크기 | 배치는 논리 픽셀, 창 `content_scale_factor` 로 화면 배율만큼 UI 를 키움(Windows DPI·macOS·웹 devicePixelRatio, 설정 `ui.lab.ui_scale`) | lab_checks `_screen_fit` | 실패: 배율 2 최소 창: 창 (2560, 1280) · 배율 1.000 → 논리 (2560.0, 1280.0) |
| J09 | 낮음 | 설정 검사 | presets.json 을 못 읽으면 경로를 담은 오류 | run_tests `test_presets_file` | 실패: … 알 수 없는 예설정: default |
| J10 | 낮음 | 실행기·분석 도구 | 중간 스냅숏 쓰기 실패 = 오류 줄·종료 코드 3·`write_failed`, 실패 문장에 파일 이름 | test_runner_cli `test_snapshot_write_failure_exits_3`, run_tests `test_recorder_files` | `'snapshot-20.json(' not found in 'RESULT: …'` |
| J11 | 낮음 | 시뮬레이션 규칙 | 동작은 두고 이름표·문서를 실제 빛 곡선대로(낮 비율 = 빛 > 0 인 몫, 황혼이 하루 빛을 줄임) | run_tests `test_light_curve` | 실패: 이름표: 낮 비율 = 빛이 0 보다 큰 몫 … |
| J12 | 낮음 | 시뮬레이션 규칙 | 동작은 두고 이름표: 칸 더미는 마지막 내려놓기부터 `spoil_ticks` 뒤 한꺼번에 | run_tests `test_spoil_lifetime` | 실패: 이름표: 썩는 시간은 칸 더미의 마지막 내려놓기부터(다시 셈) |
| J13 | 낮음 | 시뮬레이션 규칙 | 가장 많이 놓인 칸이 밭이면 저장고를 짓지 않음 | run_tests `test_store_not_on_farm` | 실패: fast_civ·씨앗 2·밭 반경 12·간격 3: 1,200틱 동안 저장고이자 밭인 칸 17 |
| J14 | 낮음 | 시뮬레이션 규칙 | 지형 씨앗이 64비트 전부를 씀(0~2^32−1 은 그대로) | run_tests `test_terrain` | 실패: 아래 32비트만 같은 씨앗은 다른 지형(같았던 쌍 5개) |
| J15 | 낮음 | 자동 검사 | 규칙·화면 검사 실행기의 `--only` 에 모르는 이름이 있으면 아무것도 돌리지 않고 실패(종료 코드 1) | run_tests `test_runner_guards`, smoke_checks `_only_arg` | 실패: --only=test_policy,test_polcy → 종료 코드 0(기대 1) |
| J16 | 낮음 | 실험실 화면 | Ctrl(Cmd)+N·S·O·E 단축키, 초점이 없을 때 Tab, 단추·고르기 상자 키보드 초점(Tab·Enter) | lab_checks `_command_keys`, param_checks `_keyboard`, graph_checks `_keyboard_checks`, chronicle_checks `_keyboard`, info_checks | 실패: 초점이 없을 때 Tab → 파라미터 패널 첫 칸(없음) / 단추·고르기 상자가 키보드 초점을 받음(못 받음: …) |
| J17 | 낮음 | 패널 | 두뇌 범례·말풍선의 "−"(U+2212) → "-", 글자 범위 검사(화면 글이 나눔고딕 두 굵기에 모두 있음) | param_checks `_font_coverage`·`_brain_legend` | 실패: 화면 글 28파일의 모든 글자가 글꼴 둘에 있음(없음: brain_view.gd U+2212) |
| J18 | 낮음 | 패널 | 씨앗을 실수로 바꾸지 않음 — 칸 글자 = str(씨앗), 64비트 전체 그대로 | param_checks `_big_seeds`·`_seed`·`_seed_range` | 실패: 칸 글자 = 씨앗 9223372036854775807(칸 "9007199254740992") |
| J19 | 낮음 | 패널 | 스냅숏을 열면 알림과 그래프 머리에 "기록은 틱 N 부터" | lab_checks `_args`, graph_checks `_snapshot_note_checks`(README 연대기 줄의 예외는 최종 확인에서 문서로) | 실패: 스냅숏에서 연 실험: 머리에 "기록은 틱 466 부터" (보임 "") |
| J20 | 낮음 | 패널 | 열기 대화 상자가 가장 최근 스냅숏을 골라 둔 채 열리고, 이름을 치면 열기 단추가 켜짐 | param_checks `_open_button` | 실패: 하위 폴더가 있어도 최근 스냅숏()이 골라진 채 열림 |
| J21 | 낮음 | 문서 | README "상태와 한계" 절(확인한 것·미검증·못 맞춘 목표) | — | 문서 |
| J22 | 낮음 | 문서 | harsh_winter 를 "혹독한 겨울(멸종 조건)" 으로, 측정 결과를 예설정 주석·CONFIG 예설정 표·README 에 | test_sim_labels `test_stress_preset_is_marked`, run_tests `test_harsh_winter` | `AssertionError: '멸종' not found in '혹독한 겨울'` |
| J23 | 낮음 | 문서 | README·ANALYSIS 에 Windows(cmd·PowerShell) 안내, analyze 는 따옴표가 붙은 키를 거부·runs.csv command 를 그 OS 셸 따옴표로 | test_analyze `test_quoted_key_rejected`·`test_command_text` | `ValueError not raised : 'mutation.rate=0.08'` |
| J24 | 낮음 | 원칙 | 이 보고서: 단계마다 결과 요약(최종 판정·통과/실패/미검증 수·다음 확인), B07 "기록" → 미검증, 1,000세대 목표를 S20 실패로 | — | 문서 |
| J25 | 낮음 | 데이터 형식 | 결과 CSV 열의 코드북(death_cause·구간/누적 값)(문서 단계 — DESIGN 담당) | test_design_format `test_result_columns_listed`(`6a8cead`) | 문서 |
| J26 | 낮음 | 데이터 형식 | 결과 파일마다 틱 기준(진행 중/진행 뒤)(문서 단계 — DESIGN 담당). 최종 확인에서 이정표 `mean_gen`·실험실 알림 "틱 N" 문장을 실제와 같게 | run_tests `test_tick_basis`(최종 확인에서 더함 — 계통으로 다시 센 시계열·사건 `mean_gen` 기준) | 문서 |
| J27 | 낮음 | 데이터 형식 | lineage·timeseries 값의 뜻(분열 자식 parent_b −1, 유전자 대 반올림 반경, 개체 0 줄)(문서 단계 — DESIGN 담당) | — | 문서 |
| J28 | 낮음 | 플랫폼·화면 크기 | 웹 창이 폭 1280 보다 좁으면 배율을 줄여 잘리지 않음(0.5 까지) | lab_checks `_screen_fit` | 실패: 웹 1024×700: 창 (1024, 700) · 배율 1.000 → 논리 (1024.0, 700.0) |
| J29 | 낮음 | 플랫폼·화면 크기 | 첫 창을 작업 영역에 맞춰 줄이고 가운데(제목 표시줄 화면 안), 최소 창 1280×720 → 1280×640 | lab_checks `_screen_fit`·`_fits_height`·`_compare_layout` | 실패: 768 높이 노트북 창: 창 (1350, 688) · 배율 0.956 → 논리 (1412.0, 720.0) |
| J30 | 낮음 | 플랫폼·화면 크기 | analyze 가 표준 출력·오류를 UTF-8 로 다시 설정(Windows 리디렉트·파이프) | test_analyze `test_output_on_legacy_codepages` | `UnicodeEncodeError: 'cp949' codec can't encode character '—'` |
| J31 | 사소 | 실행기·분석 도구 | 씨앗 표기를 `str()` 로(RESULT 줄·실험 이름·창 제목·파일 이름) | test_runner_cli `test_int64_min_seed`, lab_checks `_args`, param_checks `_big_seeds` | `'RESULT: seed=-9223372036854775808 ' not found in 'RESULT: seed=--9223…'` |
| J32 | 사소 | 실험실 화면 | 끝 줄이 있으면 그 줄을 뽑은 세계 사본으로 요약·스냅숏을 씀(실행기와 같은 파일) | experiment_checks `_odd_tick` | 실패: 배수가 아닌 틱의 final.snapshot.json = 실행기(--max-ticks=407) 결과 |
| J33 | 사소 | 실험실 화면 | 빨리 감기 중 멈추면 "멈춤 · 빨리 감기" | lab_checks `_ff_pause` | 실패: 빨리 감기 중 멈춤 표시: "멈춤 · 목표 8배" |
| J34 | 사소 | 문서 | 2단계 1,000세대 lineage 행 수 132,706 → 132,656(초기 200 + 출생 132,456) | — | 문서 |

## 5. 남긴 것·반영하지 않은 것

**남긴 것(까닭)**

| ID | 남은 것 | 까닭 |
| --- | --- | --- |
| I52 일부 | 큰 지도에서 지도를 붙이는 시간(512² 약 2.5초, 1024² 약 14초 — 검토 탐침 값)·그리는 삼각형(숨긴 풀포기 포함 512² 약 2,600만)·시뮬레이션 한 틱(256² 약 23ms)은 여전히 칸 수에 비례 | 보이는 풀포기만 앞에 모아 자르기·거리별 줄이기(LOD)는 풀포기 번호가 칸에 고정돼야 하는 점유 줄이기·바뀐 것만 쓰기와 맞지 않음. 화면 밖 덩어리는 엔진이 잘라 냄. 지도 크기 말풍선·CONFIG.md·VIEW-API 에 256×256 이하 권장을 적고, 최종 확인에서 칸 수가 `ui.lab.view_map_side_max`²(256×256)를 넘는 실험을 열면 "화면이 느릴 수 있음 — 큰 지도는 헤드리스 실행기로" 경고 알림 |
| 저장고 칸의 풀(최종 확인에서 찾음) | 저장고 칸에도 풀이 자라지만 그 칸의 입력·먹기는 저장분만 봐 줍기로만 꺼냄(칸당 몇 개) | 바꾸면 저장고가 생긴 뒤의 모든 역사가 바뀜(사본에서 잼: 기본 씨앗 1·100세대 `171a3a4f1a5f` → `f500ac4b0527`, `fast_civ` 씨앗 5·1,800틱 끝 개체 51 → 250) — CI·웹 결정성 기록·타임랩스·`fast_civ` 표를 모두 다시 재야 해 DESIGN 1.4 의 규칙으로 두고 `test_store_tile_plants` 로 고정 |
| J05 의 OS 대화 상자 | 비교 중 저장에서 혼자 저장한 `<이름>.json` 이 있으면 운영 체제 파일 대화 상자가 그 파일을 먼저 물음 | OS 동작이라 앱이 막을 수 없음(그 파일은 쓰지 않음). 엔진 대화 상자는 묻지 않고 넘기게 고침 |
| I54 몸 가장자리 | 붐비는 저장고에서도 몸 가운데는 지나갈 수 있는 칸 위지만, 큰 개체(크기 유전자 × 메시 반지름)의 가장자리는 이웃 바위 칸에 조금 걸칠 수 있음(검증 탐침: 실제 저장고 87곳 × 1~6마리에서 몸 가운데 0, 가장자리 3~28) | 호의 한계는 `slime.radius` 기준 — 개체마다 다른 크기까지 보면 붐비는 저장고의 호가 너무 좁아짐 |
| I69~I76·I83·I84 | 포트폴리오 저장소의 그림·캡션·검증 표·글꼴 줄바꿈·색 대비·조사 띄어쓰기 | 이 저장소 밖 — 포트폴리오 고침 단계에서 |

**병합 정리에서 반영하지 않은 넘김 메모(선택 항목·확인만 한 것)**

| 메모 | 까닭 |
| --- | --- |
| 처음부터 멸종인 새 실험에서 재생 상태를 멈춤으로 | 세계가 진행하지 않아 기록은 이미 실행기와 같은 한 줄(experiment_checks `_empty_start`), 멈춤을 더하면 재생 단추 모양만 바뀜. 이미 멸종한 세계(스냅숏·개체 0)는 멈추지 않고 표시만 하는 규칙을 그대로 |
| 앱 안 "정보/라이선스" 창 | 배포판은 고지 파일 넷으로 라이선스를 이미 충족, 새 UI 창은 병합 정리 범위 밖 |
| 웹 페이지 머리에 라이선스 링크 | 웹 캔버스가 창 전체를 덮어 어느 모서리의 링크도 실험실 UI 를 가림. 고지 파일은 `build/web` 의 `index.html` 옆에 있으니 체험판을 싣는 페이지에서 링크하길 권함 |
| UiTheme 에 대화 상자 테두리 | 실험실의 대화 상자는 모두 패널 것이고 이미 `style_dialog` 로 같은 모양 |
| 두뇌 범례 검사를 info_checks 로 옮기기 · 패널이 `SimConfig.int_keys()` 를 쓰게 | 검사 위치·같은 규칙의 다른 구현만 바꾸는 정리 — 문제와 상관없는 정리는 하지 않음 |
| CSV 쓰기 실패를 summary.json 의 `write_failed` 에 | 설계가 "CSV 를 하나라도 못 쓰면 summary.json 을 쓰지 않음(summary.json 이 있으면 다 쓴 것)" — CSV 실패는 실행기 RESULT 줄의 `write_failed` 에 남음 |
| 컨테이너의 wine64 지우기 | 다음 단계의 Windows 내보내기 재현용으로 그대로 둠 |

## 6. 바뀐 역사(규칙 고침)

g1a 의 설정·스냅숏 고침은 역사를 바꾸지 않았다(기본·`fast_civ`·`demo_fast` 해시 그대로). g1b 규칙 고침 가운데 **J02**(식물 갱신이 간격 전체의 빛을 셈)가 기본·씨앗 1 의 역사를 처음부터 바꾸고, **I27**(저장고 칸의 더미를 저장분으로)·**I30**(바닥 먹이 수명 +1틱)·**J03**(밭 버려짐을 매 틱)은 채집·저장·농사 단계에 들어선 뒤의 역사를 바꾼다. I08·I24·I25·I26·I28·I29·J11·J12·J13·J22·I47 은 하나씩 되돌려도 기본·예설정의 씨앗 1·2 해시가 같다. 비교는 고침 전 트리(`3a7f2c0` 을 풀어 같은 실행기 명령)와 `bafa017`. 해시는 앞 12자, 발견은 채집/저장/농사 틱.

| 실행 | 고침 전 | 고침 뒤 |
| --- | --- | --- |
| 기본·씨앗 1·100세대(S19, CI 단계) | `713cea4dea1d` · 6,690틱 · 개체 105 · 저장 단계 · 2,737/3,573/— | `171a3a4f1a5f` · 6,391틱 · 개체 117 · 농사 · 1,665/2,208/3,779 |
| 기본·씨앗 1·1,000세대 | `78891cb07b26` · 109,604틱 · 2,737/3,573/9,440 · 밭 209 | `58e2ef0b38c5` · 112,234틱 · 1,665/2,208/3,779 · 밭 203·저장고 4 |
| 기본·씨앗 1·300틱 / 2,000틱 | `8f779669fb28` / `757a3c62e8c1`(발견 없음) | `de3c4a5b7835`(개체 77) / `41186eb7cb15`(개체 53, 채집 1,665) |
| 기본·씨앗 42·30 → 40세대(S17) | 30세대 t=2,155 → 40세대 t=2,940 · `165b2c158266` · 305/577/874 | 30세대 t=1,984 → 40세대 t=2,472 · `18510b81ad2e` · 169/309/1,936 |
| `fast_civ`·씨앗 1·100세대(S15·G11) | `5c082cae55cd` · 6,468틱 · 2,309/2,502/3,321(농사 49.0세대) | 3,693틱에 멸종(`678cb9c1a9fb`) · 1,573/1,655/2,040(농사 28.5세대) |
| `fast_civ`·씨앗 5·1,800틱(예전 타임랩스) | `061f950b8418` · 개체 250 · 647/701/1,023 | `05e637326a72` · 655/697/1,068 · 1,500틱 무렵 개체 46, 끝 51·밭 18 → 타임랩스를 씨앗 2 로 바꿈 |
| `demo_fast`·씨앗 1·100세대 | `19a9a3fc705e` · 8,027틱 · 422/635/1,636 | `bd37238ca060` · 6,484틱 · 482/597/1,037(첫 밭 1,264) |
| `demo_fast`·씨앗 2·1,500틱 | `0cd47349dee1` · 개체 226 · 100/126/276 | `b0c1f37beeb4` · 개체 207 · 96/133/263 · 밭 67 |

씨앗 1~12 × 100세대(같은 `analyze.py run`, 평균 세대 중앙값 [사분위]):

| 예설정 | 고침 전 | 고침 뒤 |
| --- | --- | --- |
| `fast_civ` | 채집 7.7 [5.4–14.0] · 저장 8.6 [6.3–16.5] · 농사 15.9 [12.3–26.1](12/12, 가장 늦은 74.3) · 멸종 0/12 | 채집 5.0 [2.2–15.9] · 저장 5.7 [2.6–18.4] · 농사 14.3 [8.6–24.9](12/12, 가장 늦은 씨앗 3 의 55.5) · 멸종 2/12(씨앗 1 은 농사 뒤 3,693틱, 씨앗 7 은 1,153틱) |
| `demo_fast` | 농사 2.1 [1.9–4.1](12/12) · 멸종 0/12 | 농사 2.3 [1.9–11.8](12/12) · 멸종 0/12, 씨앗 1 은 13.2세대(1,037틱) |
| `default` | 채집 9.2 · 저장 14.8(11/12) · 농사 38.0 [32.4–81.0](7/12) · 멸종 1/12 | 채집 7.7 · 저장 10.3(11/12) · 농사 26.9 [18.6–56.6](9/12) · 멸종 1/12, 씨앗 1 은 농사 56.6세대(3,779틱) |

기본 씨앗 1~16 의 3,000틱 평균 개체는 167.6 → 155.0(씨앗 1~8 은 낮아지고 9~16 은 높아짐, 멸종 1/16 그대로). `fast_civ` 의 씨앗별 표·목표와 다른 점은 [`TUNING-fast_civ.md`](TUNING-fast_civ.md).

화면 검사·캡처의 고정값도 새 역사로 다시 정했다: 연대기 검사의 실제 연대기 씨앗 1 → 17(291틱 농사 발견 "2.35세대 · 문장 2.3"), 다시 읽은 바로 뒤 틱 126 → 133, 농사 장면 캡처 `demo_fast`·씨앗 1 → 11(씨앗 1 은 밭 3칸이 2,347틱에야 생김), 지도 건물 검사 세계 `demo_fast`·씨앗 2·1,500틱(저장고 4·밭 67), 성능 측정의 농사 세계 씨앗 11·1,760틱. 병합 뒤 실패한 map_checks "문 앞에 그린 개체를 누르면 그 개체" 는 검사 쪽 가정 탓이었다 — 문이 서·동쪽인 저장고(I54)에서는 문 앞 두 마리가 화면에서 앞뒤로 겹쳐 뒤 개체를 누르면 앞 몸이 맞는다(I53 의 옳은 동작). 그래서 가장 앞에 그린 개체를 누르게 고치고 동쪽 문 저장고에서도 같은 고르기 검사를 더했다.

## 7. 다시 잰 수치

모두 2026-10-10, 이 컨테이너. **먼저 기계 속도:** 같은 명령(기본·씨앗 1·`--max-ticks=20000 --no-lineage`)을 고침 전 트리와 고침 뒤 트리로 차례로(다른 일 없이) 돌리니 108.5초 / 110.2초(개체·틱당 27.6 / 29.1µs) — 코드가 느려진 것이 아니라 이 날 기계가 2단계 날(약 16µs)보다 약 1.7배 느렸다(4단계 3절의 "1.7배 느렸던 날" 과 같은 정도). 그래서 아래 시간·FPS 는 이 날의 수치끼리만 견준다.

**헤드리스 1,000세대**(2단계 3절과 같은 명령, 혼자 돌림):

```
godot --headless --path . --script res://tests/run_experiment.gd -- --seed=1 --generations=1000 --out=results/g1000
RESULT: seed=1 generations=1000.0 ticks=112234 pop=250 civ=3(농사) hash=58e2ef0b38c5 time=733.8s reason=generations
```

| 항목 | 값(2단계 값) |
| --- | --- |
| 걸린 시간 | **733.8초(12.2분)**, 평균 153틱/초, 평균 개체 239.1, 개체·틱당 27.3µs(443.7초·247틱/초·약 16µs). 병합 정리 때 같은 실행 725.4초·같은 해시 |
| 목표 | "목표 5분 이내" → **실패**(K10). 2단계 날의 기계 속도라면 7~8분으로 추정(고침 전·뒤 코드 속도가 같음) |
| 틱·세대 | 112,234틱(109,604), 세대당 평균 112틱 — 0~100세대 64틱, 400~500세대 125틱, 900~1,000세대 136틱(크기가 작아지며 길어짐은 그대로) |
| 출생·사망 | 135,678 / 135,628(132,456 / 132,406), 기록 줄의 90% 가 상한 250 |
| 발견 | 채집 t=1,665(평균 23.0세대) → 저장 t=2,208(30.6세대, 저장고 4개) → 농사 t=3,779(56.6세대), 첫 밭 t=3,787. 끝날 때 밭 203칸·저장고 4 |
| 특성 변화 | 크기 1.00 → 0.64, 평균 감지 반경 3.00 → 1.26, 평균 에너지 24.0 → 19.7(평균 나이 19.8 → 102.5) |
| 결과 파일 | summary 3.2KB, timeseries 728KB(5,613줄), chronicle 4.3KB(세대 이정표 줄이 더해짐), lineage 8.3MB(BOM, 135,878행 = 처음 200 + 출생 135,678), final.snapshot 6.9MB |

같은 명령을 씨앗 42 로: `RESULT: seed=42 generations=1000.0 ticks=113250 pop=250 civ=3(농사) hash=e2c5d2ab8a53 time=756.9s reason=generations`(다른 캡처와 CPU 를 일부 나눔).

**검사가 재는 수치:**

| 항목 | 다시 잰 값(예전) |
| --- | --- |
| S15 `fast_civ` 씨앗 1 농사 | 평균 28.5세대(2,040틱 — 규칙 검사 줄 "농사(평균 28.5세대, t=2041)" 의 t 는 발견 다음 틱), 씨앗 1~3 채집 21.7·3.3·25.9세대(49.0세대·3,321틱, 33.9·4.2·23.3). 문서 값 고정 `FAST_CIV_SEED1_FARM_TICK/GEN` |
| S17 이어 돌리기(씨앗 42) | 30세대 t=1,984(개체 63, `c47ce640ae0e`) → `--resume` 40세대 = 바로 40세대: 둘 다 t=2,472·개체 133·`18510b81ad2e`(발견 169/309/1,936틱, 첫 밭 2,401틱). 이제 자동 검사(test_runner_cli `test_resume_same_hash_and_summary`) |
| S18 `test_performance`(기본·씨앗 2, 800틱 뒤 400틱) | 평균 169마리, 개체·틱당 28.8µs(전체 실행)·30.7µs(`--skip-slow`), 합격 기준 = 기준 일(곱셈·더하기)의 배수 721·747번 < 1,750(평균 142마리·17.8µs — 그때는 µs 기준). Actions #12: 23.3µs·644번 |
| S19 씨앗 1·100세대 | `171a3a4f1a5f`(6,391틱, 개체 117, 농사) = Actions #12(`713cea4dea1d`) |
| 규칙 검사 시간 | 전체 113초(농사 도달 검사 15.1초), `--skip-slow` 94초(88초·24.4초) |

**성능 — 헤드리스 미세 측정**(`perf_capture.gd -- --bench`, 600프레임, 다른 일 없이):

| 세계 · 배속 | 개체 | 화면 µs/프레임 평균(중앙 / 95%) | 틱 있는 / 없는 프레임 | 시뮬레이션 µs/프레임 |
| --- | --- | --- | --- | --- |
| 기본·250마리 · 1배 | 250 | 821 (646 / 1,878) | 1,706 / 723 | 575 |
| 기본·250마리 · 4배 | 180 | 932 (648 / 2,047) | 1,385 / 629 | 1,957 |
| 기본·250마리 · 64배 | 203 | 2,643 (2,527 / 4,730) | 2,643 / — | 37,672 |
| `demo_fast`·씨앗 11·1,760틱(농사·밭 28) · 1배 | 250 | 723 (597 / 1,818) | 1,623 / 623 | 645 |
| 같은 세계 · 4배 | 222 | 1,288 (986 / 2,888) | 1,966 / 836 | 2,905 |
| 같은 세계 · 64배 | 248 | 2,781 (2,669 / 4,640) | 2,781 / — | 43,423 |

기본·250마리 줄은 4단계 3절과 같은 장면이다(1배 768 → 821µs, 64배 2,385 → 2,643µs, 시뮬레이션 32,062 → 37,672µs — 기계 몫 안). `demo_fast` 줄은 예전 씨앗 1 이 규칙 고침 뒤 1,760틱에 밭이 거의 없어 씨앗 11 로 바꿔 장면이 달라 직접 견줄 수 없다.

**성능 — 실험실 실측**(xvfb + llvmpipe, 1600×900, 지도 MSAA 2, 각 10초. ㉮ 기본·씨앗 1 을 2,633틱·개체 201 까지(예전 2,132틱·200), ㉯ 10,000틱 기록 5,001줄·개체 250, ㉰ 씨앗 1 | 2 각 5,001줄 — 4단계 3절과 같은 장면 정의):

| 장면 · 배속 | 평균 FPS | 프레임 시간 중앙 | `advance_frame` | 시뮬레이션 / 화면·UI | 그래프 다시 그리기: 번/초 · `_draw` 합 평균(최대) · 프레임당 | UI 2D 그리기 호출 | 실제 배속(10초) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ㉮ 1배 | 4.7 | 205.2ms | 10.92ms | 7.94 / 2.98ms | 0.3 · 2.18(2.76)ms · 0.14ms | 487 | 0.8배 |
| ㉮ 64배 | 4.9 | 202.6ms | 10.69ms | 7.79 / 2.90ms | 0.2 · 1.76(1.77)ms · 0.07ms | 479 | 0.8배(표시 0.7배) |
| ㉮′ 자리 접음 1배 | 4.8 | 208.2ms | 10.73ms | 7.90 / 2.83ms | — | 193 | 0.8배 |
| ㉮′ 자리 접음 64배 | 5.4 | 179.6ms | 8.95ms | 6.60 / 2.35ms | — | 197 | 1.2배(표시 1.8배) |
| ㉯ 5,000줄 1배 | 4.9 | 204.4ms | 10.94ms | 7.92 / 3.02ms | 2.5 · 2.35(3.97)ms · 1.20ms | 457 | 0.8배 |
| ㉯ 5,000줄 64배 | 5.0 | 197.5ms | 9.02ms | 6.60 / 2.43ms | 2.6 · 2.21(3.59)ms · 1.13ms | 456 | 1.0배(표시 1.4배) |
| ㉰ 비교 1배 | 2.9 | 340.6ms | 21.61ms | 16.34 / 5.27ms | 1.5 · 5.33(7.45)ms · 2.67ms | 615 | 0.5배(표시 0.4배) |
| ㉰ 비교 64배 | 2.8 | 353.7ms | 21.67ms | 15.78 / 5.89ms | 1.4 · 4.99(7.05)ms · 2.49ms | 609 | 0.5배 |

- "실제 배속" 열 = 10초 동안 진행한 틱 ÷ 6, 괄호는 화면 표시(마지막 창). 표시는 이제 벽시계로 재므로(J04) 프레임이 아주 느린 이 기계에서 진행과 함께 흔들린다.
- 지도 3D 그리기 호출 8~9(예전 5~9), 기본 도형 39~43만. UI 2D 그리기 호출이 예전보다 약 100 많다(㉮ 390 → 487) — 이번 고침의 화면 변경 몫으로 보이며 따로 가르지 않았다. ㉯ 준비 10,000틱 41.9초, ㉰ 두 세계 10,000틱 107.9초. 3단계의 MSAA 0 비교는 다시 재지 않았다.

**타임랩스**(`tests/timelapse_capture.gd` + `tools/make_timelapse.sh`, I62): 규칙 고침 뒤 예전 씨앗 5 는 1,500틱 무렵 개체가 46 까지 줄어 **빠른 문명·씨앗 2** 로 바꿈 — 32배, 1,800틱(281프레임, 끝 틱 1,798, 9.37초 30fps 1280×720), 채집 374 → 저장 422 → 농사 812틱(실행기 `summary.json` 의 `discovery_ticks` 와 같음), 첫 밭 869틱, 끝 개체 250·밭 약 101칸. 뒤쪽 1/3 은 둘레에 밭이 가장 많은 저장고 근처 개체를 따라감. `timelapse.webm` 1.28MB(VP9), `.mp4` 1.13MB(H.264), `.gif` 2.76MB(720×405 12fps), `timelapse-poster.jpg` 126KB.

**캡처**(`docs/screenshots/v0.1/`, 이름은 모두 그대로): lab-*.jpg 144~233KB, 패널 png 59~138KB(geo-lineup 321KB — 메시 그대로라 바이트까지 예전과 같음), 지도 jpg 113~171KB. ① 전경 기본·씨앗 1·480틱 ② 농사 낮 `demo_fast`·씨앗 11·1,096틱(#997 선택, 저장고 + 밭 2칸) ③ 같은 자리 밤 1,123틱 ④ 64배 실시간 150프레임(152틱) ⑤ 패널 기본·씨앗 1·**2,412틱**(채집·저장 발견 뒤, 연대기 6줄 — 예전 1,200틱은 발견 전이라 연대기가 비었음) ⑥ 비교 `demo_fast` | 기본·1,500틱. 모두 헤드리스 해시와 같음(ui_driver).

## 8. 검사 결과

다 찍은 뒤 차례로 혼자 돌린 값(규칙·화면·파이썬·ui_driver 는 최종 확인 고침(11절) 뒤 다시 돌린 마지막 값, graph_capture·perf_capture 는 다시 찍을 때의 값):

```
godot --headless --path . --script res://tests/run_tests.gd -- --skip-slow   RESULT: 357 checks passed, 0 failed   (95초)
godot --headless --path . --script res://tests/run_tests.gd                  RESULT: 360 checks passed, 0 failed   (검사 합 113초, 농사 도달 검사 15.1초 포함)
godot --headless --path . --script res://tests/run_view_tests.gd             RESULT: 1301 passed, 0 failed (view)   (197초, 다시 204초 — 같은 결과)
    chronicle 90 · experiment 88 · geo 77 · graph 149 · info 65 · integration4 61 · lab 293 · map 100 · param 262 · smoke 23 · sound 61 · web 32
python3 -m unittest discover -s tools -p 'test_*.py'                         Ran 101 tests … OK   (60초)
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd
                                                                             RESULT: 53 passed, 0 failed (ui)
xvfb-run … --resolution 1280x720 --script res://tests/ui_driver.gd           RESULT: 52 passed, 0 failed (ui)
xvfb-run … --script res://tests/graph_capture.gd                             RESULT: 0 failed (graph capture)
godot --headless --path . --script res://tests/perf_capture.gd -- --bench      RESULT: bench ok
xvfb-run … --resolution 1600x900 --script res://tests/perf_capture.gd         RESULT: live ok
```

검사 수는 5단계(171 · 1,064 · 41)에서 규칙 351(`--skip-slow` 348), 화면 1,287, 파이썬 97 로 늘었고, 문서 마무리(`6a8cead`, 파이썬 99)와 최종 확인 고침(11절) 뒤 규칙 360(`--skip-slow` 357), 화면 1,301, 파이썬 101 이다. 새 규칙 검사(예): `test_config_rules`·`test_presets_file`·`test_night_threshold`·`test_components_fast`·`test_snapshot_corrupt`·`test_recorder_files`·`test_empty_start`·`test_mate_once_per_tick`·`test_store_max_count`·`test_first_farm_once`·`test_store_takes_pile`·`test_child_energy_cap`·`test_store_built_in_act`·`test_spoil_lifetime`·`test_growth_interval`·`test_farm_abandon_any_growth`·`test_light_curve`·`test_store_not_on_farm`·`test_action_names`·`test_harsh_winter`·`test_farm_rule_values`·`test_civ_rule_values`·`test_runner_guards`. 새 파이썬 검사 파일: `test_runner_cli.py`(실행기 명령줄 — godot 이 없으면 건너뛰지 않고 실패)·`test_build_ci.py`(워크플로·배포판). 화면 검사 실행기는 `--only` 에 모르는 이름이면 실패(종료 코드 1, `RESULT: 0 passed, 1 failed (view)`). 고치기 전 기준선(병합만 한 `219fac0`)의 화면 검사는 `1256 passed, 15 failed` 였고, 병합 정리에서 모두 풀었다(6절의 고정값·검사 쪽 가정). 화면 전체를 두 번 돌려 같은 결과(64배 예산 평균 5.98ms·95% 9.89ms, 빨리 감기 평균 11.35ms·95% 14.53ms — 예산 14ms).

## 9. 미검증

| ID | 내용 | 이유 |
| --- | --- | --- |
| U01·U03·B04·U08 | Windows·macOS 에서 실행(창·입력·사용자 폴더 `%APPDATA%\slime-lab`)과 Windows/macOS ↔ 리눅스 역사 해시 | 기기 없음. Windows 실행 파일은 아이콘·판 정보(PE 자료)와 wine 헤드리스 실행(주 장면 lab 이 뜨고 종료 코드 0)만 확인. macOS 판은 내보내지 않음 |
| U04·J23 | Windows 의 `analyze.py`(코드 페이지 cp949·cp1252 출력, cmd·PowerShell 따옴표)와 README·ANALYSIS 의 Windows 명령 | 리눅스에서 코드 페이지·따옴표 규칙을 흉내 내 검사만 함 |
| U02′·U02″·B07 | 실제 GPU 에서 200마리 60FPS(혼자·비교)·웹 체험판의 실제 브라우저 속도 | GPU 없음, llvmpipe·SwiftShader 로만 잼 |
| J08·J29 | 실제 Windows 150%·200%·macOS 레티나의 배율·창 맞춤, Windows 최대화, GNOME/KDE 창 관리자의 첫 창 위치 | 검사는 순수 함수 + xvfb/openbox·Chromium 으로만. 지도 3D 는 논리 해상도로 그려 배율 2 에서 약간 흐림(성능은 배율 1 과 같음) |
| U07·J05·J06·J20 | 운영 체제(네이티브) 파일 대화 상자: 비교 중 저장에서 혼자 모드 이름 `<이름>.json` 이 이미 있으면 OS 대화 상자가 먼저 덮어쓸지 물음(OS 동작이라 막을 수 없음 — 그 파일은 쓰지 않고, 패널이 실제 -A/-B 를 따로 물음. 엔진 대화 상자는 최종 확인에서 묻지 않고 넘기게 고침), 저장 중 멈춤이 풀리는 것(`canceled`·`file_selected` 신호)·열기 단추 켜기 | 헤드리스·xvfb 에서는 엔진 대화 상자로만 열림 |
| B08 | 실제 브라우저에서 사람이 누르는 내려받기 창(zip·JSON) | 묶는 바이트·이름·임시 폴더는 web_checks, 고친 웹판의 "결과 내려받기" 는 Chromium 에서 눌러 엔진 오류 없음(I39)까지만 |
| U06 | 효과음을 실제 스피커로 | 오디오 장치 없음, 합성 바이트만 검사 |
| K09·B13 | GitHub Pages 체험판 주소가 열리는지, Release(`v*` 태그) | Pages 꺼짐(소유자 설정), 태그 없음 |
| K12 | wasm ↔ 데스크톱 해시를 CI 에서 늘 견주기, Chromium 밖 브라우저(Firefox·Safari) | 수동 탐침으로 Chromium 에서만 확인 |
| U10 | 같은 지도 크기에서 패널만 숨긴 프레임 시간 대조 | `perf_capture` 에 그 장면이 없음 |
| I19 | 실제 디스크 가득(쓰다 잘린 파일) | 16k tmpfs 에서 손으로 재현해 확인, 자동 검사는 실패를 흉내 낸 경로로 |

**알려진 한계:** 큰 지도는 지도 붙이기·그리는 삼각형·시뮬레이션 한 틱이 칸 수에 비례하고, 화면 갱신은 덩어리 수만큼의 프레임에 걸쳐 퍼진다(256² 약 0.5초 — 5절 I52). 저장고에 개체가 많아 호가 넓어져도 막힌 이웃(바위·물·지도 밖) 쪽으로는 펼치지 않지만(최종 확인), 큰 개체의 몸 가장자리는 이웃 칸에 조금 걸칠 수 있다. 전경에서 덩어리마다 그리기 순서가 달라 풀포기 잎 뿌리 몇 픽셀이 다르게 그려질 수 있다(1280×720 전경에서 10픽셀). 연대기 줄 고르기·그래프 값 읽기는 마우스 전용이다(키보드 초점은 단추·고르기 상자만).

## 10. Actions

| 실행 | 커밋 | test | export | pages | release |
| --- | --- | --- | --- | --- | --- |
| #11 | `3a7f2c0` 검토 대상(5단계 마무리) | 통과 | 통과 | **실패** | 건너뜀(태그 없음) |
| #12 | `bafa017` 검토 고침 병합 정리(3) | 통과 — 규칙 351, 화면 1,287, 씨앗 1·100세대 `171a3a4f1a5f`(= 이 컨테이너), 파이썬 97, `test_performance` 23.3µs·기준 일 644번 | 통과 | **실패** | 건너뜀(태그 없음) |
| #13 | `bf3209a` 다시 찍기(캡처·타임랩스·분석 예시) | 통과 — 규칙 351, 화면 1,287, `171a3a4f1a5f`, 파이썬 97, `test_performance` 27.1µs·721번 | 통과 | **실패** | 건너뜀(태그 없음) |

pages 실패의 까닭은 그대로다: `actions/configure-pages@v6` 가 "Get Pages site failed … Not Found"(저장소 `has_pages = false`). 워크플로에서 `enablement: true` 를 뺐으므로(I56 — 워크플로 토큰은 Pages 를 켤 수 없음) **저장소 소유자가 Settings → Pages → Build and deployment → Source 를 "GitHub Actions" 로 한 번 바꿔야** 한다. 그 뒤 새 main 푸시, main 에서 Actions 탭 "Run workflow", 또는 "Re-run all jobs" 가 배포한다("Re-run failed jobs" 는 Pages 묶음을 14일 보관하므로 그 안에서만). 배포 뒤 주소가 실제로 열리는지는 미검증(K09).

## 11. 최종 확인(독립 검증 뒤 남은 것)

고침을 마친 뒤 독립 검증자 31명이 문제 120개를 처음부터 다시 재현했다: **111개 고쳐짐 · 8개 일부 · 1개 보류**(I62 — 포트폴리오 쪽 다시 찍기와 함께). 검증하며 새 문제도 찾았다. 이 저장소 쪽의 남은 것과 새 문제를 아래처럼 고쳤다(시뮬레이션 역사는 바뀌지 않음 — 기본·씨앗 1·100세대 `171a3a4f1a5f` 그대로). 코드 고침은 고침을 잠시 되돌려 새 검사가 실패함을 확인했다(마지막 열). 포트폴리오 저장소 쪽(1,000세대 시간 줄·웹 속도 단서·카드 "체험판 공개" 이름표·사이트 바닥 링크 대비 등)은 포트폴리오 단계 몫이다.

| 항목 | 검증에서 남은 것 | 고친 것 | 지키는 검사 | 고치기 전(되돌렸을 때) |
| --- | --- | --- | --- | --- |
| I04 일부 | `format`·`rng.world`/`rng.life` 의 종류가 틀리면 SCRIPT ERROR 로 검증을 건너뜀(`format = 1` 이면 통과해 열림) | `validate` 가 종류를 먼저 봄 | run_tests `test_snapshot_corrupt`(22종) | 실패: 구조가 틀린 스냅숏 22종을 오류 문장으로 거부(샌 것: format 숫자, format 사전, rng.world 숫자, rng.life 배열, rng.world null) |
| J05 일부 | 비교 중 저장에서 엔진 대화 상자가 쓰지도 않을 `<이름>.json` 을 먼저 물음(-A/-B 도 있으면 두 번) | 엔진 대화 상자는 비교 중이면 그 물음을 넘김(OS 대화 상자는 OS 동작이라 남김 — 5절) | param_checks `_engine_overwrite` | 실패: 비교 중 같은 이름(same.json 있음) → 쓰지 않을 same.json 을 묻지 않고 -A/-B |
| J19 일부 | README 연대기 줄이 예외 없이 "그 시점 세로선" 을 약속 | 스냅숏에서 연 실험의 앞선 줄은 세로선 없이 머리 알림만(문서) | — | 문서 |
| J26 일부 | DESIGN 8.4 가 이정표 `mean_gen` 을 T+1 상태라 적음(실제는 적힌 틱 T — 9개 중 5개가 한 틱 어긋나게 읽힘), 알림 "틱 N" 을 진행 중 틱에만 둠 | 이정표 = 틱 T 상태, 알림은 사건의 `tick` 그대로(문서) | run_tests `test_tick_basis`(새 — 계통으로 다시 센 시계열·사건 `mean_gen` 기준) | 검사 이빨: 옛 문서대로 읽게 바꾸면 "이정표(틱 197) 1.00 ≠ 줄 198 의 1.05 …", birth ≤ t < death 로 읽으면 "어긋난 줄 399" |
| I37 일부 | lab_checks 가 Ctrl+S·Ctrl+O 로 실제 `user://experiments` 를 만듦 | 검사가 `snapshot_dir` 도 임시 폴더로(새 사용자 폴더에서 돌린 뒤 `logs` 만 남음) | lab_checks `_command_keys` | 실패: Ctrl+S 대화 상자 시작 폴더 = 이 검사의 임시 폴더(…/slime-lab/experiments — 실제 user://experiments 아님) |
| I52 일부 | 큰 지도를 열어도 앱 안에 경고가 없음 | 칸 수가 `ui.lab.view_map_side_max`²(256×256)를 넘는 실험을 열면 경고 알림(붙이는 시간·삼각형은 남김 — 5절) | lab_checks `_big_map` | 실패: 지도 257×256 → 경고 알림 하나: [] |
| I54 일부 | 4마리 이상이면 문 앞 호가 막힌 옆·뒤 이웃(바위·물·지도 밖)으로 다시 돎(원 탐침 4마리 14/348, 6마리 26/522) | 막힌 이웃 쪽으로는 몸이 걸리기 전까지만 펼치고 간격을 줄여 열린 쪽으로(`_arc_limits`) — 검증 탐침(실제 저장고 87곳 × 1~6마리)에서 몸 가운데가 막힌 칸 위 0 | map_checks `_check_store_crowded` | 실패: 붐비는 저장고(막힌 이웃 꼴 11가지 × 4~6마리, 165번 그림) … "4마리 #0 칸(0,0) → 몸 가운데 (-0.02, 0.80)" … |
| I62 보류 | 포트폴리오 캡션·영상이 예전 씨앗 5 | — | — | 포트폴리오 단계 |
| 새 (I43 퇴행) | 설정 오류 문장이 64비트를 넘는 수를 INT64_MIN 으로 적음(`--set=time.day_ticks=1e20`) | 그 크기면 정수로 바꾸지 않고 그대로(`SimConfig.INT_TEXT_MAX`) | run_tests `test_config_rules` | 실패: 큰 수 오류 문장: 설정 time.day_ticks = -9223372036854775808: 범위 2~100000 밖입니다 |
| 새 | 패널 정수 칸의 64비트 넘는 글 → 엔진 `ERROR:` 줄과 INT64_MIN | 씨앗 칸처럼 글자 자릿수를 먼저 보고 그 값 그대로 범위 오류 | param_checks `_seed` | `ERROR: Cannot represent 100000000000000000000 as a 64-bit signed integer` / 실패: 정수 칸의 64비트 밖 글 → … -9223372036854775808.0 … |
| 새 (I27 형제) | 저장고 칸에서 자라는 풀이 그 칸의 입력·먹기에 안 잡힘 | 규칙으로 문서화(DESIGN 1.4 — 바꾸면 역사가 바뀜, 5절) | run_tests `test_store_tile_plants`(규칙 고정) | 문서 |
| 새 (I20 의 분석 도구 쪽) | `analyze.py --max-ticks` 0·음수가 조용히 "상한 없음", 상한 위는 모든 실행이 실패 | 실행기와 같은 1~`TICK_MAX` 정수(`sim_config.gd` 에서 읽음) | test_analyze `test_max_ticks_like_runner` | `AssertionError: SystemExit not raised : 0` |
| 새 (I45 곁) | 기록 간격이 다른 틱 축 비교에서 같은 기준 틱인데 마우스 자리에 따라 B 가 "이 틱 기록 없음" | 다른 실험은 기준 가로 값에 가장 가까운 줄 | graph_checks `_interval_compare_checks` | 실패: … ["552: 기준 0·540, B 줄 틱 600(보임 0)"] |
| 새 | integration4 ③ 이 I15 를 잡지 못함(그 장면의 첫 밭이 이미 가로축 안) | 4절 I15 지키는 검사 칸을 graph_checks `_cursor_tail_checks` 로 바로잡고 검사 주석도 | — | 문서 |
| 새 (I50 곁) | 엔진 파일 대화 상자 안쪽의 같은 이름 확인 창이 기본 회색에 영어 | 안쪽 창 모두 `style_dialog`, 같은 이름 확인은 한국어·기본 초점 취소 | param_checks `_engine_overwrite` | 실패: … (Please Confirm... / File "…/same.json" already exists. … / 바탕 (0.25, 0.25, 0.25, 1.0)) |
| 새 (I21 곁) | `--resume` 스냅숏을 링크(또는 대소문자만 다른 경로)로 결과 폴더 안에서 주면 그 스냅숏을 지움 | 지울 파일 가운데 크기·내용이 같은 것이 있으면 거부(2) | test_runner_cli `test_resume_inside_out_dir_by_other_path_refused` | `AssertionError: 0 != 2 : --resume=…/orig_link/snapshot-35.json --out=…/orig` |
| 새 (I13 곁) | `lab.pause_on_extinction` 을 끄면 멸종한 프레임의 빈 반복을 틱으로 셈(빨리 감기에서 221틱을 3,413틱으로) | 모두 멸종하면 그 프레임의 반복을 멈춤 | lab_checks `_extinction` | 실패: 끈 경우에도 advance_frame 이 센 틱 223 = 실제로 나아간 틱 221 / 센 3413 = 틱 221 |
| 새 (문서) | 파이썬 검사 수 97(실제 99)·`test_design_format` 이 목록에 없음, I18·J25 지키는 검사 "—" | README·ANALYSIS·DESIGN 12절·4절·8절(이제 101) | — | 문서 |
| 새 (문서) | README 첫 줄 "121개 고침" 이 3절(저장소 111개, 포트폴리오 10개 남음)과 어긋남 | README 첫 줄 | — | 문서 |
| I44 곁 | `brain.weight_clamp` 1e-6 아래면 범례 "-0/+0" | 그대로 — 그런 값은 실험 뜻이 없고 고치기 전과 같음 | — | — |

"곁효과 주의" 로 남은 I05·I07·I20·I26·I27·I45·I50·I13·I21·I44 는 위 행으로 고쳤거나(I13·I20·I21·I27·I45·I50) 실제 문제가 아니었다(I05 — 이어 돌린 결과를 다른 예설정 요청과 견주면 mismatch 로 보는 것은 의도한 보수적 동작, I07·I26 — 퇴행 없음, I44 — 위).

# 1단계 5/5: 빌드·배포·마무리 (v0.1.0)

## 1. 대상 기록

| 항목 | 기록 |
| --- | --- |
| 검수 일시 / 담당 | 2026-10-08 / 제작 AI(Claude Code) |
| 엔진·템플릿 | Godot 4.4.1-stable, 공식 내보내기 템플릿(linux_release.x86_64, windows_release_x86_64.exe, web_nothreads_release.zip) |
| 실행 환경 | 클라우드 리눅스 컨테이너(4코어, GPU 없음). 화면은 xvfb + llvmpipe, 웹은 Playwright 헤드리스 Chromium(SwiftShader WebGL2) |
| 범위 | `export_presets.cfg`, `.github/workflows/build.yml`(test → export → pages / release), 웹 체험판 내려받기, 앱 아이콘, 타임랩스, 문서 |

## 2. 결과

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| B01 | Linux 내보내기(실행 파일 하나, pck 포함) | 통과 | `slime-lab.x86_64` 72.2MB |
| B02 | Linux 실행 파일을 띄워 오류 없이 돎 | 통과 | xvfb 1600×900 300프레임, 헤드리스 200프레임: SCRIPT ERROR 없음(ALSA 오류는 이 컨테이너에 음향 장치가 없어서) |
| B03 | Windows 내보내기 | 통과 | `slime-lab.exe` 100.0MB(서명 없음, 아이콘 리소스는 바꾸지 않음 — rcedit 없음)(검토 고침 뒤: rcedit 로 아이콘·판 정보를 씀 — I57, 새 절) |
| B04 | Windows 에서 실행 | **미검증** | Windows 기기 없음 |
| B05 | 웹 내보내기(스레드 없는 판, Compatibility) | 통과 | wasm 43.7MB + pck 2.6MB, 합 45MB |
| B06 | 웹 체험판이 브라우저에서 뜨고 실험이 진행됨 | 통과(헤드리스) | 헤드리스 Chromium + SwiftShader WebGL2: 오류·pageerror 없음, 실험실 전체 화면, 틱 진행 |
| B07 | 웹 체험판 속도 | **미검증** | SwiftShader(소프트웨어 그래픽)에서 64배 목표에 실제 1.1배(이 기록은 7.5FPS 아래에서 엔진이 자른 delta 로 잰 값이라 실제보다 클 수 있음 — 검토 J04). **실제 GPU 브라우저 속도는 미검증** |
| B08 | 웹에서 "CSV 내보내기"·"스냅숏 저장" → 내려받기(zip·JSON), "스냅숏 열기" 숨김 | 통과 | `tests/view/web_checks.gd` 24개(검토 고침 뒤 32개 — 새 절)(4단계 검토 뒤 — zip 안 5개 파일, zip 의 시계열 = 기록기 CSV, 내려받은 스냅숏을 열면 같은 해시, 웹 모드 단추, 임시 폴더·zip 이 남지 않음, 비교 이름에 두 씨앗) — 브라우저의 실제 내려받기 창은 미검증 |
| B09 | 실행 파일에 검사·도구·문서가 들어가지 않음 | 통과 | `exclude_filter`, 실행 파일에서 검사 문장(예: "농사 도달 시도") 0회 |
| B10 | 글꼴 OFL 전문이 배포판에 들어감 | 통과(설정) | 포함 필터 `assets/fonts/OFL-NanumGothic.txt`, Actions zip 에 LICENSE·CREDITS·OFL(검토 고침 뒤: 엔진 라이선스 고지 `GODOT-LICENSE.txt` 도 zip·웹 묶음에 — I16, 새 절) |
| B11 | 앱 아이콘(코드로 렌더링) | 통과 | `assets/icon.png`(`tests/icon_capture.gd`), 웹 파비콘에도 쓰임 |
| B12 | 타임랩스(빠른 문명·씨앗 5, 32배, 1,800틱, 채집 647 → 저장 701 → 농사 1,023틱 — 예전 글의 648·702·1,024 는 한 틱씩 어긋났음, 검토 I62) | 통과 | `docs/media/timelapse.webm` 1.2MB(VP9 — 오픈소스 Chromium 계열도 재생), `.mp4` 1.1MB(H.264), `.gif` 2.9MB(검토 고침 뒤 다시 찍음: 빠른 문명·씨앗 2, 채집 374 → 저장 422 → 농사 812틱 — 새 절 7) |
| B13 | Actions: test → export(세 플랫폼, Linux 헤드리스 실행) → pages(main) / release(태그) | test·export 통과, pages **실패(저장소 설정)** | 아래 3절 |
| B14 | 4단계 최종 점검에서 남은 것(R1~R6) 고침 | 통과 | 아래 4절 |

## 3. Actions 첫 실행

| 실행 | 커밋 | test | export | pages | release |
| --- | --- | --- | --- | --- | --- |
| #8 | 8f5d518 5단계 | **실패** — 효과음 검사가 실제 시계의 최소 간격(`sound.min_interval_s`) 때문에 빠른 CI 기계에서만 실패 | 건너뜀 | 건너뜀 | 건너뜀 |
| #9 | 634bcb5 효과음 검사 고침(`LabSound.reset_rate_limit()`, 간격을 길게 잡으면 옛 검사가 CI 와 같은 메시지로 실패함을 확인) | 통과 | 통과 | **실패** | 건너뜀(태그 없음) |
| #10 | 7119e02 타임랩스 WebM 판 | 통과(규칙·화면·100세대 실행·파이썬) | 통과(세 판 내보내기, Linux 헤드리스 200프레임, zip·Pages 묶음 올림) | **실패** | 건너뜀(태그 없음) |

그 뒤의 #11(이 절의 커밋 `3a7f2c0`)·#12 는 맨 앞 절 10.

pages 실패의 까닭: `actions/configure-pages`(enablement: true)가 "Get Pages site failed: Not Found" 뒤 "Create Pages site failed: Resource not accessible by integration" — 이 저장소에 GitHub Pages 가 아직 켜져 있지 않고, 워크플로의 토큰에는 Pages 사이트를 새로 만들 권한이 없다. **저장소 소유자가 Settings → Pages → Build and deployment → Source 를 "GitHub Actions" 로 한 번 바꾸면** 다음 main 실행(또는 Actions 탭에서 다시 실행)부터 `https://kyusang4657.github.io/slime-lab/` 에 체험판이 올라간다 — 그 뒤 주소가 실제로 열리는지는 **미검증**(검토 I56: 이때 워크플로는 "Run workflow" 로는 pages 를 돌리지 않았고 Pages 묶음을 하루만 보관했음 — 고친 뒤 안내는 맨 앞 절 10). release 는 `v*` 태그를 밀 때만 돈다(아직 태그 없음, 미검증).

## 4. 4단계 최종 점검에서 고친 것(R1~R6)

4단계 검토 고침(G01~G56)을 통합한 뒤의 최종 점검이 남긴 것. **고친 것마다 그 고침을 잠시 되돌려 새 검사가 실패함을 확인**했다(아래 "고치기 전").

| ID | 남은 것 | 고침 | 검사 · 고치기 전 |
| --- | --- | --- | --- |
| R1 | 1280 창 비교 모드에서 씨앗이 같고 값만 다른 두 실험(돌연변이 0.08 / 0.02, 멈춤 표지까지 붙음)의 지도 이름이 둘 다 "… · 씨앗 1 · 돌연…"(고급 키는 "plants.regro…" / "plants.regrow…") | `LabMain.fit_tail`: 꼬리도 넘치면 두 지도를 가르는 첫 몫을 남김 — A·B 씨앗이 같으면 씨앗 대신 A·B 가 다른 첫 바꾼 값, 그것도 길면 값은 두고 이름을 줄임("… · 돌연… 0.08", "… · plants…=0.5") | lab_checks "좁은 비교 지도 이름(씨앗 같고 …)" 2개 + 줄임 규칙 1개 · 고치기 전 두 이름이 같음 |
| R2 | 비교 모드에서 멸종한 쪽이 멸종 뒤에도 개체 0 줄을 계속 쌓아(221, 240, …, 300) 그쪽 `B/timeseries.csv` 가 실행기(221 에서 멈춤)와 다름. 혼자 모드에서도 멸종해 멈춘 뒤 다시 재생하면 같음 | `Experiment.step()` 은 멸종한 틱 뒤로 기록하지 않고, `tail_row()` 는 멸종했으면 `{}` | experiment_checks "멸종한 B/timeseries.csv = 실행기", "멸종 뒤 100틱 더 진행해도 기록 그대로" 등 4개 · 고치기 전 1550 / 1278 글자, 18줄 / 13줄 |
| R3 | (R2 를 고치며 찾음) 한 프레임에 여러 틱을 돌 때 멸종한 틱이 아니라 그 프레임 끝까지 가서 멈춤 — 4단계 검토의 "멸종하는 순간 멈춤" 검사는 프레임 예산에 따라 통과·실패가 갈리던 것(같은 코드로 두 번 돌려 틱 221 / 222) | `LabMain._extinction_stop()`: 이 틱에 모든 실험이 멸종했고(알리지 않은 멸종) `lab.pause_on_extinction` 이면 남은 틱을 버리고 멈춤 | experiment_checks "빨리 감기에서도 멸종한 틱에서 멈춤" · 고치기 전 틱 237 에서 멈춤(멸종 221). 보통 배속 검사는 세 번 돌려 모두 통과 |
| R4 | 이름표의 실수 표기가 입력 칸과 다름(`String.num` — "돌연변이 0.12345678901234" / 칸 "0.123456789012345") | `Experiment.describe_value` → `ParamPanel.format_value`(정수 키는 정수, 실수는 JSON 표기) | experiment_checks 2개 · 고치기 전 "0.12345678901234" |
| R5 | 규칙 검사(`run_tests.gd`)가 실제 사용자 폴더에 `test_snap`·`test_runner`(숨은 `.gdignore` 포함)를 남김 | 프로세스마다 따로인 임시 폴더(`tmp_dir`)를 쓰고 끝에 통째로 지움(`remove_tree`, 숨은 파일까지) | run_tests 2개 · 검사 뒤 사용자 폴더에 `downloads`·`experiments`·`logs`·`shader_cache` 만 남음(확인) |
| R6 | 문서: VIEW-API 범례 문단이 옛 꼬리("· 바꾼 값 K개"), DESIGN §19 의 Experiment 가 멸종 줄·끝 줄 없이 적힘 | VIEW-API(범례·지도 표지·Experiment·멸종)·DESIGN §19·README·W04 를 지금 동작으로 | — |

검사 결과(이 고침 뒤, 같은 기계에서 차례로 — 검토 고침 뒤 다시 잼: 규칙 360·`--skip-slow` 357, 화면 1,301, 파이썬 101, 맨 앞 절 8):

```
godot --headless --path . --script res://tests/run_tests.gd                  RESULT: 171 checks passed, 0 failed   (88초, 농사 도달 검사 24.4초 포함)
godot --headless --path . --script res://tests/run_tests.gd -- --skip-slow   RESULT: 168 checks passed, 0 failed
godot --headless --path . --script res://tests/run_view_tests.gd             RESULT: 1064 passed, 0 failed (view)   (179초, 두 번 돌려 같음)
    chronicle 86 · experiment 63 · geo 76 · graph 119 · info 55 · integration4 59 · lab 234 · map 84 · param 188 · smoke 17 · sound 59 · web 24
python3 -m unittest discover -s tools -p 'test_*.py'                         Ran 41 tests … OK
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd
                                                                             RESULT: 53 passed, 0 failed (ui)
xvfb-run … --resolution 1280x720 --script res://tests/ui_driver.gd           RESULT: 52 passed, 0 failed (ui)
```

검사를 모두 돌린 뒤 사용자 폴더(`~/.local/share/slime-lab`)에는 `downloads`·`experiments`·`logs`·`shader_cache` 만 남았다(R5 와 4단계 G27).

## 5. 결과 요약과 미검증

- **최종 판정: 세 판 빌드·Actions 의 검사·내보내기 통과, Pages 배포는 저장소 설정 때문에 실패, Windows 실행·실제 GPU 속도는 미검증**
- 통과 / 실패 / 미검증: B01~B14 **11 / 1 / 2**(B13 의 pages / B04 Windows 실행, B07 실제 GPU 브라우저 속도)
- 미검증(이 절 기준): B04 Windows 실행, B07 실제 GPU 브라우저 속도, B08 실제 브라우저의 내려받기 창, Pages 주소가 열리는지(3절), Release(태그 없음). 앞 단계의 U01(플랫폼 간 해시)·U02′·U02″(실제 GPU 60FPS)·U06(소리)·U07(OS 파일 대화 상자)·U08(Windows 사용자 폴더)도 그대로 — 검토 고침 뒤의 전체 목록은 맨 앞 절 9
- 다음 확인 순서: 저장소 소유자가 Pages 켜기 → 체험판 주소 확인 → Windows 실기에서 zip 실행(B04·U08) → 실제 GPU 브라우저 속도(B07)

# 1단계 4/5: 실험실 패널 통합 — 파라미터·그래프·연대기·비교·내보내기·소리 (v0.1.0-dev)

## 1. 대상 기록

| 항목 | 기록 |
| --- | --- |
| 검수 일시 / 담당 | 2026-10-08 / 제작 AI(Claude Code) — 워크트리 5개(LabMain 비교 모드·패널 자리, ParamPanel, GraphPanel·GraphView, ChroniclePanel·LabSound, `fast_civ` 다시 맞춤)를 main 에 병합, 이어서 함께 띄웠을 때 드러난 것을 고침(5절) |
| 엔진 | Godot 4.4.1-stable, Compatibility(GL) 렌더러 |
| 실행 환경 | 클라우드 리눅스 컨테이너 4코어, xvfb + **llvmpipe**(Mesa 25.2, CPU 소프트웨어 GL) — 실제 GPU 아님. 오디오 장치 없음(ALSA 실패 → 엔진 더미 드라이버) |
| 범위 | `scripts/ui/*`(lab_main·param_panel·graph_panel·graph_view·chronicle_panel·lab_sound·info_panel·ui_theme), `config/ui.json`·`config/presets.json`·`project.godot`, `tests/view/*`, `tests/*_capture.gd`·`ui_driver.gd`·`perf_capture.gd`, 문서. 시뮬레이션(`scripts/sim`)·지도(`scripts/view`)는 3단계 그대로(diff 없음) |

## 2. 검사 결과

```
godot --headless --path . --script res://tests/run_tests.gd                  RESULT: 159 checks passed, 0 failed   (84초, 농사 도달 검사 23.5초 포함)
godot --headless --path . --script res://tests/run_tests.gd -- --skip-slow   RESULT: 158 checks passed, 0 failed
godot --headless --path . --script res://tests/run_view_tests.gd             RESULT: 819 passed, 0 failed (view)   (131초)
    chronicle 73 · experiment 22 · geo 76 · graph 68 · info 55 · integration4 55 · lab 196 · map 84 · param 119 · smoke 17 · sound 54
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd
                                                                             RESULT: 51 passed, 0 failed (ui)
xvfb-run … --resolution 1280x720 --script res://tests/ui_driver.gd           RESULT: 50 passed, 0 failed (ui)   (V07 은 1600×900 에서만)
xvfb-run … --script res://tests/graph_capture.gd                             RESULT: 0 failed (graph capture)
python3 -m unittest discover -s tools -p "test_*.py"                         Ran 29 tests … OK
```

화면 검사 로그에 `SCRIPT ERROR`·`ERROR:` 줄 없음. 규칙 검사 로그의 `ERROR: Parse JSON failed` 4줄은 깨진 설정·스냅숏을 일부러 읽는 검사의 것이다. 화면 검사는 3단계 352개 → 819개(새 모듈: param·graph·chronicle·sound·experiment·integration4). 위 수는 4단계 통합 때의 것이고, 4단계 검토(G01~G56)를 고친 뒤의 수는 7절(화면 1,047개·규칙 169개).

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| W01 | 파라미터 패널 값(예설정·씨앗·세 주요 값·고급 키) → 새 실험의 `cfg`·씨앗·개체 수, 적용 전에는 지금 실험 그대로, 적용 뒤 "지금 실험과 같음", 범위 밖 값은 줄 아래 오류·단추 꺼짐 | 통과 | integration4 ①, param_checks |
| W02 | 패널로 비교 시작 → 지도 둘, 바꾼 값은 그 칸의 세계에만, 그래프 세 개에 계열 둘(점 수 = 기록 줄 수), 범례 둘, 연대기 A/B 줄 수 = 두 연대기 합, 알림 "A · "/"B · " | 통과 | integration4 ②, lab_checks `_compare`, ui_driver ⑥(검토 I38: 이때 `series_points` 는 그래프를 가리지 않아 "세 그래프" 근거가 공허했음 — 지금은 그래프마다 그린 선의 계열) |
| W03 | 연대기 줄을 실제 마우스로 누름 → 그래프 시점 세로선, 행위자(첫 밭)가 있으면 **그 실험의** 개체 선택(실험 번호 1, 정보 창 이름표 B, 고리는 B 지도에만), 두 세계 그대로 | 통과 | integration4 ③, chronicle_checks(검토 I89: "두 세계 그대로" 를 틱을 진행하지 않은 역사 해시로 봐 실패할 수 없었음 — 지금은 스냅숏 모든 절 비교) |
| W04 | 패널의 CSV 내보내기 → 비교면 `A/`·`B/` 각각의 timeseries.csv·chronicle.csv 가 같은 예설정·바꾼 값·씨앗·틱 수의 헤드리스 실행기 결과와 **글자까지** 같음(한쪽만 멸종했으면 그쪽은 멸종까지의 실행기 결과 — 4단계 최종 점검 R2, 5단계 4절) | 통과 | integration4 ④, experiment_checks |
| W05 | 스냅숏 저장 → 더 진행 → 열기 = 저장한 틱·해시·상태(처음부터 돌린 헤드리스 세계와 비교), 이어 돌려도 같음. 비교 중 저장은 `-A`·`-B` 두 파일 | 통과 | integration4 ⑤ |
| W06 | 화면은 시뮬레이션을 바꾸지 않음: 패널을 모두 붙인 채 실제 프레임(64배)·`step_ticks` 로 진행해도 역사 해시·상태 배열이 헤드리스와 같음(혼자·비교 A·B, 연대기 클릭 뒤에도) | 통과 | integration4 ①②③⑤, lab_checks, chronicle_checks, graph_checks, ui_driver ⑤⑥ |
| W07 | 최소 창 1280×720(검토 고침 뒤 1280×640 — J29, 1280×720 배치도 계속 잼)·자리 모두 펼침에서 배치가 창 안(정보 창 오른쪽 끝 = 창 끝, 아래 자리 = 왼쪽 자리 + 지도), 비교 지도 한 칸 ≥ 320×400, 조작 도움말이 A 칸 안, 가장 긴 위쪽 막대 ≤ 1280 | 통과(통합 때 고침) | lab_checks `_fits_window`·`_compare_layout`·`_docks`, ui_driver 1280 |
| W08 | V07(1600×900 에서 정보 창이 스크롤 없이 두뇌 범례까지) — 패널을 붙여도 | 통과 | ui_driver 1600(정보 창이 세로 전체) |
| W09 | 캡처 장면의 그래프·연대기가 세계와 맞음(그래프 줄 수 = 기록, 마지막 기록 틱이 세계 틱의 `record.every` 안, 연대기 = 세계 연대기) | 통과(통합 때 고침) | ui_driver lab-02 새 검사 |
| W10 | 효과음: 16비트 모노, 길이·최댓값 ≤ 0.8 FS·NaN 없음·첫/끝 샘플 0·같은 입력이면 같은 바이트·음높이 방향, 같은 소리 0.5초 간격, 묶음에서 가장 중요한 소리 하나, 패널 "소리" 상자 ↔ `LabSound.enabled` | 통과(자동) | sound_checks, integration4 ⑥ |
| W11 | 연구용 `fast_civ`: 씨앗 1 이 평균 49.0세대에 농사(검토 고침 뒤 다시 잼: 28.5세대·2,040틱, 새 절 7), 씨앗 1~3 의 채집이 평균 2세대 이후(예전 값이면 실패) | 통과 | run_tests `test_farm_reachable` |
| W12 | 통합에서 고친 것마다 검사가 고치기 전 코드에서 실패 | 통과(수동 확인) — I04 는 4단계 검토 통합 때 검사를 더함(7절 J02) | 고친 것마다 따로(5절): I01·I02 — 연대기 폭 규칙·세 줄 도움말을 되돌리면 lab_checks 4개 실패(정보 창 오른쪽 끝 1326 > 1280 등), 되살리면 통과. I03 — `keep_words` 가 글자를 그대로 돌려주게 하면 integration4 ⑦ 1개 실패("발/견" 에서 줄바꿈), I05 — ui_driver 농사 장면을 예전처럼 세계 `step()` 으로 돌리면 새 검사 1개 실패(그래프 1줄·마지막 틱 0 / 세계 1,696): 둘 다 통합 때가 아니라 4단계 검토(G29) 때 확인. I06 — 검토 때 더한 test_repo_rules `test_user_dir_is_ascii`(설정 줄을 지우거나 이름이 한글이면 실패). I04 — 검토 때까지 자동 검사가 없었고(캡처로만), 검토 병합 뒤 실제로 되풀이됨(1280 창 기술 단계 그래프 "0" 하나) → graph_checks "가로축 이름"(옛 코드로 3개 실패, 7절 J02). 구성 요소별 확인은 각 담당(연대기: 중복 건너뛰기·A/B 순서를 일부러 깨면 8개 실패, fast_civ: 예전 값이면 S15 실패) |
| W13 | 캡처를 1600×900·1280×720 둘 다 눈으로 확인: 전경·농사 낮(선택)·밤·64배·패널·비교, 그래프·연대기·파라미터 패널 | 통과(눈으로 확인) | `docs/screenshots/v0.1/`(lab-*.jpg 150~220KB, png 63~124KB — 검토 고침 뒤 다시 찍음: 144~233KB·59~138KB, 새 절 7). 1280 판은 확인용으로만 찍음 |

## 3. 성능 실측

`tests/perf_capture.gd`(VIEW-API "성능 측정" 4단계 — 검토 고침 뒤 다시 잰 표는 맨 앞 절 7). **먼저 기계 속도:** 지도·시뮬레이션 코드는 3단계와 같은데(diff 없음) 같은 헤드리스 미세 측정이 3단계 보고서보다 약 1.7배 느렸다(기본·250마리 1배 화면 768µs ↔ 446µs, 64배 시뮬레이션 32.1ms ↔ 18.7ms, demo_fast 1배 627 ↔ 340µs). 공유 기계가 그만큼 느렸던 것이므로 **아래 수치는 이 날의 수치끼리만** 견준다.

**실험실 실측(xvfb + llvmpipe, 1600×900, 지도 MSAA 2, 각 10초)** — ㉮ 기본·씨앗 1 을 2,132틱(개체 200)까지, ㉮′ 같은 세계를 자리 둘 다 접고(지도 1260×856 = 3단계 크기), ㉯ 기본·씨앗 1·`record.every` 2 로 10,000틱(기록 5,001줄, 개체 246), ㉰ 같은 조건 씨앗 1 | 2 비교(기록 5,001줄씩). 모두 오래 살 개체 하나를 고른 채(정보 창 갱신 포함):

| 장면 · 배속 | 평균 FPS | 프레임 시간 중앙 | 우리 스크립트(`advance_frame`) | 그중 시뮬레이션 / 화면·UI | 그래프 다시 그리기: 번/초 · 세 그래프 `_draw` 합 평균(최대) · 프레임당 | UI 2D 그리기 호출 | 실제 배속(10초) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ㉮ 1배 | 5.0 | 200.6ms | 9.80ms | 6.87 / 2.93ms | 0.3 · 1.72(1.93)ms · 0.10ms | 390 | 0.8배 |
| ㉮ 64배 | 4.8 | 200.8ms | 10.12ms | 7.03 / 3.08ms | 0.3 · 1.80(2.59)ms · 0.11ms | 397 | 0.8배 |
| ㉮′ 자리 접음 1배 | 4.6 | 216.4ms | 10.12ms | 7.11 / 3.01ms | — (숨김) | 191 | 0.8배 |
| ㉮′ 자리 접음 64배 | 4.9 | 204.3ms | 9.71ms | 6.88 / 2.83ms | — (숨김) | 196 | 0.9배 |
| ㉯ 5,000줄 1배 | 5.0 | 192.2ms | 10.18ms | 7.38 / 2.80ms | 2.6 · 2.37(4.00)ms · 1.21ms | 491 | 0.8배 |
| ㉯ 5,000줄 64배 | 5.1 | 189.8ms | 9.40ms | 6.61 / 2.79ms | 2.5 · 2.44(4.93)ms · 1.20ms | 483 | 0.8배 |
| ㉰ 비교 5,000줄씩 1배 | 3.0 | 319.5ms | 21.17ms | 15.72 / 5.45ms | 1.6 · 5.63(14.91)ms · 2.91ms | 600 | 0.5배 |
| ㉰ 비교 5,000줄씩 64배 | 3.2 | 305.5ms | 18.67ms | 13.64 / 5.03ms | 1.5 · 4.31(7.36)ms · 2.09ms | 582 | 0.5배 |

- **패널 몫은 이 측정으로 따로 가르지 못했다:** 자리를 편 ㉮(5.0 FPS)와 접은 ㉮′(4.6~4.9 FPS)는 비슷하지만 지도 크기가 달라(1000×636 ↔ 1260×856, 픽셀 약 1.7배) 패널만 바꾼 비교가 아니다 — "접으면 커진 3D 지도의 픽셀 채우기가 패널의 2D 그리기 호출(약 200개 더)보다 비싸다"는 풀이는 따로 재지 않은 추정이고, 두 장면 차이는 같은 장면을 다시 잴 때의 흔들림 안이다. 직접 잰 것은 우리 스크립트 몫뿐: `advance_frame` 의 화면·UI 몫이 편 쪽 2.9~3.1ms ↔ 접은 쪽 2.8~3.0ms 로 같고, 그래프 `_draw` 는 프레임당 0.1ms 안팎(그래프 줄 덧붙이기·연대기 덧붙이기는 프레임당 0.1~0.3ms 안쪽). 연대기 `_draw` 와 패널 2D 그리기의 렌더러 몫은 재지 않았다 — 같은 지도 크기에서 패널만 숨긴 대조는 미검증(U10).
- **그래프:** 다시 그리기는 `ui.graph.redraw_hz`(5) 아래(새 줄이 있을 때만, 5FPS 라 프레임 수에 묶임). 5,000줄 세 그래프 합 평균 2.4ms(최대 4.9ms), 비교 5,000줄 × 2 는 평균 4.3~5.6ms, 최대 14.9ms(그 구간에서 가로 범위가 넓어져 묶음을 새로 만든 3번 가운데 하나 — 헤드리스 graph_checks 의 6,000줄 × 2 새로 만들기 약 20ms 와 맞음). 60FPS 라면 초당 최대 5번이므로 프레임당 평균 약 0.2ms(혼자)·0.4ms(비교)로 추정 — **실제 GPU 에서는 미검증**.
- **비교 모드는 시뮬레이션 몫이 두 배:** 이 기계(llvmpipe 가 CPU 를 함께 씀)에서 한 틱이 세계마다 약 7ms 라 두 세계 한 틱(약 14ms)이 이미 예산(10ms)을 넘는다. 예산 규칙은 프레임마다 적어도 한 틱을 돌리므로 프레임당 1틱 = FPS ÷ 6 배속(5FPS 0.8배, 3FPS 0.5배). 위쪽 막대는 "목표 64배 / 실제 0.5배" 를 경고 색으로 정직하게 보인다. 헤드리스 실행기(세계마다 틱당 약 4.5ms)라면 둘이 9ms 로 예산 안.
- **64배는 이 기계 어느 장면에서도 닿지 않는다**(실제 0.5~0.9배). 3단계 보고서와 같은 까닭(예산·느린 프레임)에 기계가 1.7배 느렸던 몫이 더해졌다.
- 그리기 호출은 지도 5~9(비교면 지도 둘 합 9, MultiMesh 설계 그대로), 나머지는 2D UI(정보 창·파라미터 패널·연대기 줄·그래프). 연대기 `_draw` 는 따로 재지 않았다(보이는 줄만 그림, 300줄이어도 노드 9개 — chronicle_checks).

**헤드리스 미세 측정**(MapView `before_steps + update_view`, 600프레임, 이 날 기계):

| 세계 · 배속 | 개체 | 화면 µs/프레임 평균(중앙 / 95%) | 틱 있는 / 없는 프레임 | 시뮬레이션 µs/프레임 |
| --- | --- | --- | --- | --- |
| 기본·250마리 · 1배 | 250 | 768 (577 / 2,114) | 1,771 / 656 | 560 |
| 기본·250마리 · 64배 | 170 | 2,385 (2,341 / 3,933) | 2,385 / — | 32,062 |
| demo_fast 1,760틱 · 1배 | 170 | 627 (414 / 1,840) | 1,658 / 513 | 552 |
| demo_fast 1,760틱 · 64배 | 209 | 2,386 (2,212 / 4,099) | 2,386 / — | 36,964 |

## 4. 미검증

| ID | 내용 | 이유 |
| --- | --- | --- |
| U02″ | 실제 GPU 에서 패널을 모두 편 실험실 60FPS(혼자·비교) | GPU 없음, llvmpipe 로만 잼(위 3절). 우리 스크립트 몫(혼자 약 10ms 중 시뮬레이션 7ms·화면 3ms, 그래프 다시 그리기는 초당 5번 이하)만 확인 |
| U06 | 효과음을 실제 스피커로 듣기 | 컨테이너에 오디오 장치 없음. 합성 바이트(형식·길이·최댓값·NaN·포락선·음높이 방향)는 자동 검사, 파형·스펙트로그램 그림은 연대기·소리 담당이 확인(`tools/render_sounds.gd` 로 WAV 를 만들어 들을 수 있음) |
| U07 | 운영 체제 파일 대화 상자(`use_native_dialog`) | 헤드리스·xvfb 에서는 엔진 대화 상자로만 열림(안의 엔진 글은 영어). Windows·macOS·포털 있는 Linux 미확인 |
| U08 | Windows 의 사용자 폴더 `%APPDATA%\slime-lab` | 리눅스에서 `~/.local/share/slime-lab` 만 확인 |
| U03 | Windows·macOS 화면 실행 | 리눅스뿐 |
| ~~U05~~ | 바뀐 CI(로그의 `SCRIPT ERROR` 로 실패) | **해결**: 이 CI 는 Actions #5(`a54d4d0`, 3단계 마무리)부터 그대로 돌아 test 통과(#6·#7, 5단계 3절의 #9·#10 도). 이 표를 쓸 때 "아직 돌지 않음" 은 이미 사실이 아니었음(검토 I66) |
| ~~U09~~ | I04: 좁은 그래프(1280 창 아래 자리)의 가로축 이름이 둘 이상·서로 겹치지 않음 | **해결**(4단계 검토 통합 때): GraphView `last_x_labels` 기록 + graph_checks "가로축 이름"(폭 4가지 × 틱 범위 6가지 × 틱·세대 축) — 7절 J02 |
| U10 | 패널의 실제 그리기 몫(같은 지도 크기에서 패널만 숨긴 프레임 시간 대조) | perf_capture 에 그 장면이 없음 — 3절의 편·접은 비교는 지도 크기가 달라 패널 몫을 가르지 못함 |

## 5. 통합에서 고친 것

| ID | 고친 것 | 검사 |
| --- | --- | --- |
| I01 | 최소 창 1280×720 에서 아래 자리 최소 폭(연대기 420 + 그래프 최소 540 + 간격·여백 = 986px)이 자리(940px)를 넘어 **정보 창과 위쪽 막대 오른쪽 끝이 창 밖으로 46px** 밀림(구성 요소 검사로는 보이지 않음 — 각자 따로 띄움). 연대기 폭을 창 폭에 맞춤: (창 − 정보 창 − 여백) × `chronicle.dock_frac`(0.36)를 [`chronicle.min_width` 320, `chronicle.width` 420]로 자르고 그래프 최소 폭을 보장 → 1600 창 420, 1280 창 331 | lab_checks `_fits_window`(혼자·비교), 1600 창이면 420. 고치기 전 실패 확인 |
| I02 | 1280 창 비교 모드에서 두 줄 조작 도움말이 A·B 지도 사이를 걸침 → 키 줄을 나눈 세 줄 단계, 비교 모드는 A 칸에 들어가는 가장 적은 줄 | lab_checks "좁은 비교 모드" — 고치기 전 실패 |
| I03 | 한글이 음절 사이("발/견")에서 줄이 바뀜(파라미터 패널 "지금 실험", 알림) → `UiTheme.keep_words`(낱말 잇개 U+2060, 폭 0) | integration4 ⑦ |
| I04 | 1280 창 그래프 가로축에 "0" 만 남음 → 좁은 그림에서는 이름이 겹치지 않을 만큼만 띄움, `graph.x_label_min_px` 56 → 50(1600 창은 그대로 500틱 간격) | 검토 통합 때 검사 더함(graph_checks "가로축 이름", 7절 J02). 2.5배·여백 8px 은 이름 붙은 상수 `NARROW_LABEL_FACTOR`·`X_LABEL_PAD` |
| I05 | ui_driver 농사·밤 장면(과 perf_capture)이 세계를 직접 `step()` 해 기록이 안 따라가 **그래프가 틱 0 한 점에 멈춘 채** 틱 1,696 장면이 찍힘 → `lab.step_ticks` | ui_driver 새 검사(그래프 줄 수·마지막 틱·연대기 = 세계) |
| I06 | 사용자 폴더를 영문으로(`application/config/custom_user_dir_name = "slime-lab"`) — 한글 경로에서 엔진 FileDialog 가 거짓 "권한 없음" 을 띄움(파라미터 담당 요청) | 경로 출력 확인. 검토(G29) 뒤 test_repo_rules `test_user_dir_is_ascii`(project.godot 의 이름이 영문·숫자인지 — 설정을 지우면 실패) |
| I07 | CREDITS 에 합성 효과음(CC0) 줄, SIM-API `cfg` 행(ParamPanel 이 모든 잎 키를 깊은 사본으로 읽음), VIEW-API 낡은 3단계 배치·`fast_civ` 이름, 3단계 성능 표·S15 의 `fast_civ` → 당시 값 `demo_fast` 표기, `experiment_checks.gd.uid` 추적, lab_checks 의 연대기 폭 검사를 새 규칙으로 | test_repo_rules |

구성 요소 담당이 계약과 다르게 정한 것(모두 받아들임, 근거는 VIEW-API 각 구현 메모): 정보 창 세로 전체·아래 자리 = 왼쪽 자리 + 지도·자리 접기 단추는 지도 위(LabMain), 비교 모드에서 한쪽만 멸종하면 멈추지 않음(LabMain), 강조·"바꾼 값 N개" 는 지금 실험과 견줌(ParamPanel), 저장고·밭 수는 이중 축 대신 작은 띠 둘·A/B 색 #2aa98a·#d97630(4단계 검토 G32 에서 뜻 색과 붙어 보여 #3d9406·#e54ec6 으로 바꿈, 7절)(색각 이상 검사 통과 — 처음엔 저장소 밖 dataviz 검사기로 한 번 잼, 4단계 검토(G52) 뒤 `tools/test_repo_rules.py` `TestPaletteClaims` 가 같은 계산(Machado 2009 심도 1.0·OKLab ΔE×100·WCAG 대비)으로 VIEW-API 의 그래프·연대기 색 수치를 config/ui.json 에서 다시 잼, 연대기는 `other` 를 뺀 다섯 묶음)·축 글자 12px(GraphPanel), 연대기 목록 안에서는 "평균" 을 줄임·낱말 단위 직접 줄바꿈(ChroniclePanel), 소리는 사인 + 약한 배음 3종(LabSound).

## 6. `fast_civ` 다시 맞춤(요약)

근거·후보 표·재현 명령은 [`TUNING-fast_civ.md`](TUNING-fast_civ.md). 목표는 "발견이 첫 세대에 바로 열리지 않고 진화 도중에, 100세대 안에 농사".

- 값: `discovery.forage_threshold` 280 · `store_threshold` 30 · `region_size` 16 · `farm_radius` 16 · `farm_threshold` 15(나머지 기본). 예전 값(채집 120·저장 30·농사 8)은 시연·검사용 `demo_fast` 로 남김.
- 씨앗 1~12 × 100세대 실측(검토 고침 뒤 다시 잼: 채집 5.0·저장 5.7·농사 14.3세대, 멸종 2/12 — 맨 앞 절 6): 채집 중앙값 7.7세대(IQR 5.4~14.0, 12/12), 저장 8.6(6.3~16.5, 12/12), 농사 15.9(12.3~26.1, 12/12, 가장 늦은 씨앗 74.3), 멸종 0. 예전 값은 11/12 씨앗이 채집을 바로 열었다(채집·저장·농사 중앙값 0.2·0.3·2.1세대).
- 못 맞춘 목표(정직하게): 저장 15~35·농사 30~70 세대 중앙값은 맞추지 못함 — 빠른 씨앗을 늦추려 임계를 올리면 느린 씨앗(1·3·8·11)이 100세대를 넘김. 씨앗 7 은 여전히 2세대 안에 셋 다 엶(첫 세대 무작위 두뇌의 배부른 줍기 시도 371회). 근본 원인은 발견 집계가 누적이라 첫 세대가 지배하는 것 — 코드 변경 제안으로 남김.
- 검사: S15(`test_farm_reachable`)가 `fast_civ` 를 먼저 시도해 씨앗 1 → 평균 49.0세대(검토 고침 뒤 28.5세대)에 농사, 씨앗 1~3 채집 ≥ 2세대(33.9·4.2·23.3)를 확인(예전 값이면 4.35·0.22·0.49 로 실패). 규칙 검사 전체는 159개(+1).

## 7. 검토에서 고친 것(G01~G56)

4단계 통합 뒤 적대적 검토: 검토자가 렌즈별로 찾은 것을 회의적 검증자 둘이 따로 재현해 **둘 다 확인한 55건**(G01~G56, G50 은 기각되어 번호만 비어 있음)을 다섯 묶음 — LabMain·실험·소리(lab-core) / 파라미터 패널(param) / 그래프(graphs) / 연대기(chronicle) / 검사·문서(tests-docs) — 의 워크트리에서 고치고 main 에 `--no-ff` 로 병합했다. 충돌은 두 곳(VIEW-API ParamPanel "입력" 문단 = 두 묶음의 문장을 합침, graph_checks 머리 주석 = 둘 다 살림), `config/ui.json` 은 묶음마다 자기 절에만 키를 더해 그대로 합쳐졌다(키 지우기·이름 바꾸기 없음). **고친 것마다 그 고침을 잠시 되돌려 새 검사가 실패함을 확인**했다(아래 "고치기 전" 열; 문서·상수만 고친 것은 "—").

```
godot --headless --path . --script res://tests/run_tests.gd                  RESULT: 169 checks passed, 0 failed   (약 90초, 농사 도달 검사 26.6초 포함)
godot --headless --path . --script res://tests/run_tests.gd -- --skip-slow   RESULT: 166 checks passed, 0 failed
godot --headless --path . --script res://tests/run_view_tests.gd             RESULT: 1047 passed, 0 failed (view)   (161초, 두 번 돌려 같음)
    chronicle 86 · experiment 49 · geo 76 · graph 119 · info 55 · integration4 59 · lab 231 · map 84 · param 188 · smoke 17 · sound 59 · web 24
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd
                                                                             RESULT: 53 passed, 0 failed (ui)
xvfb-run … --resolution 1280x720 --script res://tests/ui_driver.gd           RESULT: 52 passed, 0 failed (ui)   (V07 은 1600×900 에서만)
xvfb-run … --script res://tests/graph_capture.gd [-- --extra]                RESULT: 0 failed (graph capture)
xvfb-run … param_capture.gd [--extra] · chronicle_capture.gd [--extra] · timelapse_capture.gd   오류 없음(그림은 눈으로 확인)
python3 -m unittest discover -s tools -p "test_*.py"                         Ran 41 tests … OK
```

화면 검사 로그에 `SCRIPT ERROR`·`ERROR:` 줄 없음(병합 직후 한 번 있었음 — 아래 J01). 규칙 검사 로그의 `ERROR: Parse JSON failed` 4줄은 깨진 설정·스냅숏을 일부러 읽는 검사의 것. 화면 검사는 4단계 819개 → 1,047개, 규칙 검사 159 → 169개(G10·G11), 파이썬 29 → 41개(G15·G22·G29·G52).

| ID | 고친 것 | 검사 | 고치기 전 |
| --- | --- | --- | --- |
| G01 | 패널 글 칸에 적은 뒤 지도·단추를 눌러도 초점이 남아 단축키가 막히고, 친 키가 다음 실험 값에 들어감("42"+"3" → 씨앗 423). LabMain 이 칸 밖 마우스 누름에 초점을 풀고(SpinBox 는 바로 `apply()` — 엔진은 지연 적용이라 같은 클릭의 새 실험이 옛 씨앗을 씀), 읽기 전용 칸은 단축키를 막지 않음. 패널의 모든 단추 동작도 확정 뒤 초점을 풂 | lab_checks `_focus_release`(실제 마우스·키), param_checks(단추 뒤 초점 없음·읽기 전용 칸 FOCUS_NONE) | 실패(패널 몫 11개) |
| G02 | Enter 없이 적던 글자가 고급 설정 A/B 바꾸기·되돌리기·예설정 뒤 엉뚱한 칸에 확정. `_end_edits()` 가 모든 패널 동작 전에 그 칸으로 확정, 고급 칸은 초점을 받을 때의 A/B 칸을 기억 | param_checks `_pending_edits`(실제 키, 4경우) | 실패 8개 |
| G03 | 멸종해 저절로 멈춘 실험에 멸종 줄이 없어 그래프에 멸종 표시가 없고, 배수가 아닌 틱의 내보내기가 실행기와 다름. `Experiment.step()` 이 멸종 틱에 한 줄, 내보낼 때 세계 **사본**(`SimSnapshot` 왕복)의 `tail_row()` 를 덧붙임 | experiment_checks(멸종 틱 221·틱 407 내보내기 = 실행기 글자까지, 세계·기록기 그대로), integration4 ④ | 실패 |
| G04 | 스냅숏 열기·비교 끝내기 뒤 첫 걸음의 사건이 연대기에서 빠짐(틱으로 거름). 실험별 읽은 연대기 수로 거름 | chronicle_checks `_rebuild_next_tick`(네 경로) | 실패 4개 |
| G05 | 비교 모드 세대 축에서 마우스 세로선·값 머리가 A 의 가까운 줄을 따라감. 모든 계열 가운데 마우스에 가장 가까운 줄이 기준, 먼 계열은 "멸종 …"/"— (이 세대 기록 없음 …)" | graph_checks `_gen_compare_checks` | 실패 |
| G06 | 세대 축 시점 표시를 A 의 평균 세대로 놓음. 계열마다 그 틱의 자기 세대에 하나씩(B 점선). 신호 `cursor_tick_requested(tick)` 는 그대로 — 검증자가 든 다른 방법 | `_lab_checks`·`_gen_compare_checks`(B 시점 = B 농사 표지 px) | 실패 |
| G07 | 마우스 값 계산을 프레임마다 4번, 세대 축은 매번 모든 줄을 훑음. `hover_state()` 한 번 계산을 공유, 정렬 색인 이분 탐색(답은 모두 훑기와 같음) | `_hover_cost_checks`(마우스 한 번에 계산 1번), 이분 탐색 = 모두 훑기 | 실패(계산 7번) |
| G08 | 1280×720 비교 모드에서 나란히 시작·상태 줄·비교 모드 단추가 화면 밖. 스크롤 밖 고정 바닥(`Footer`), 제목 "다음 비교 — …" 늘 보임 | param_checks `_layout`·`_real_compare`(화면 안) | 실패 4개 |
| G09 | 값만 다른 비교(돌연변이 0.08 vs 0.02)의 이름이 같음. 이름에 바꾼 값("돌연변이 0.08", 나머지 키=값, 최대 2개 + "외 K개"), 비교면 A·B 가 다른 키를 먼저 | experiment_checks `_labels` | 실패 |
| G10 | 연대기 멸종 줄의 평균 세대가 늘 0.0. 마지막 틱에 죽은 개체들의 평균 세대(시뮬레이션, 새 상태 없음 — 8개 세계의 역사 해시 그대로) | run_tests `test_extinction_mean_gen` | 실패 2개 |
| G11 | S15 가 demo_fast 로도 통과해 `fast_civ` 다시 맞춤을 지키지 못함. fast_civ 씨앗 1 따로(100세대 안 농사 + 틱 3,321·49.0세대 고정 — 검토 고침 뒤 2,040틱·28.5세대) | run_tests `test_farm_reachable` | 실패 2개(농사 임계 100000 — S15 는 통과) |
| G12 | 저장고·밭 띠의 눈금 최댓값이 선 끝에 붙어 지금 수처럼 읽힘(없는데 "1"). 띠 안 오른쪽 "0~N", 자료가 0 이면 안 씀 | `_lab_checks` | 실패 |
| G13 | 비교 모드 알림이 A\|B 경계 가운데에서 두 지도를 가림. 칸마다 알림 열(색 A/B 표), 칸마다 최대 toast_max/2 | lab_checks `_compare_toasts`, ui_driver ⑥ | 실패 |
| G14 | 지금 실험의 씨앗을 0~seed_max 로 잘라 "바꾼 값 1개"·새 실험이 다른 세계. 그대로 보이고 흐린 안내(검토 고침 뒤 씨앗 칸은 64비트 글 칸이라 흐린 안내가 없어짐 — I14·J18) | param_checks `_seed_range`(-5·3e9·그 스냅숏) | 실패 6개 |
| G15 | 고급 설정 85개 영어 키에 설명이 없고 `docs/CONFIG.md` 가 없음. `config/sim-labels.json`(한국어 이름·단위·범위·뜻) 말풍선, 같은 내용의 `docs/CONFIG.md` 생성, `tools/test_sim_labels.py` | param_checks `_labels`, test_sim_labels | 실패(3개 + 파이썬 2개) |
| G16 | A/B 따로 밭 잃음 알림 묶기에 검사 없음 | lab_checks `_toast_rules`·`_compare_toasts` | 실패 |
| G17 | 비교 모드 내보내기 실패가 A/B 어느 쪽인지 말하지 않음. "B/timeseries.csv" + "(A 는 저장됨: 경로)" | lab_checks `_export_fail`(실패하는 하위 클래스 — 실제 디스크 오류 없음) | 실패 |
| G18 | 해석할 수 없는 글자를 적던 칸 + 새 실험 → 옛 값으로 시작하고 오류가 곧 사라짐. 시작하지 않고 줄 아래 오류·"입력 오류"·알림(씨앗 칸 포함) | param_checks `_bad_text` | 실패 6개 |
| G19 | 비교 중 끄면 A 칸에 고친 값이 지워짐. 실험이 바뀐 칸만 다시 맞춤 | `_real_compare` | 실패 2개 |
| G20 | 출생·사망이 기록 간격당 수인데 단위가 없고 A/B 기록 간격이 다르면 견줄 수 없음. `ui.graph.flow_per_ticks`(20)틱당 수, 단위 표시 | `_series_checks`·`_synthetic_checks`·`_lab_checks` | 실패 |
| G21 | B 점선이 가로 위치 무늬라 한 줄짜리 뾰족한 값이 무늬 틈에서 사라짐. 가파른 조각은 길이 기준 무늬 | `_dash_checks`(무늬 자리 10곳) | 실패 |
| G22 | SIM-API 경계 검사 정규식이 4단계 세계 접근 대부분을 놓침. 주석·문자열을 빼고 사슬·별칭·기록기·정적 이름까지 찾고, 화면이 세계에 쓰거나 진행 함수를 부르면 실패(Experiment·LabMain 예외), 자기 검사 | test_repo_rules | 실패(검토자의 변형: 새 규칙 2개 실패, 옛 규칙 통과) |
| G23 | 마우스가 움직일 때마다 세 그래프의 선을 모두 다시 그림. 마우스 겹(`HoverLayer`)만 | `_hover_cost_checks`(GraphView `draw_count` 그대로) | 실패 |
| G24 | B 점선 계단이 빈 배열로 `draw_multiline` → 엔진 ERROR. 빈 묶음은 건너뜀 | `_synthetic_checks`(`dash_skipped`) | 실패(엔진 ERROR 9줄) |
| G25 | 고급 설정을 편 채 슬라이더 한 칸마다 85줄·말풍선을 다시 씀. 다름은 갱신마다 한 번, 말풍선은 바뀔 때만, 줄은 바뀐 것만 | `_refresh_cost`(견준 수 ≤ 86·말풍선 0 — 시간은 출력만) | 실패(256번·85개) |
| G26 | 줄의 세대 칸과 문장 속 평균 세대가 다름(두 번 반올림). 칸은 저장값 그대로 0.01 단위(의도한 바뀜: `%.1f` → `%.2f`) | `_real_chronicle`(422틱 칸 4.35·문장 4.3) | 실패 |
| G27 | 폴더 지우기가 숨은 `.gdignore` 를 건너뛰어 임시 내보내기·검사 폴더가 남음. `include_hidden`, 실패해도 임시 폴더를 지움(PID 이름) | web_checks, integration4 | 실패 |
| G28 | 저장고·밭 띠 선 굵기가 코드 상수. `ui.graph.lane_line_width` | `_synthetic_checks`(덮어쓴 굵기) | 실패 |
| G29 | I04·I06 에 헤드리스 검사가 없는데 W12 가 모두 확인했다고 씀. I06 검사(`test_user_dir_is_ascii`), W12·I04·I06 근거를 다시 씀(I03·I05 는 되돌려 다시 확인). I04 코드 몫은 통합 때(아래 J02) | test_repo_rules, graph_checks "가로축 이름" | 실패 |
| G30 | DESIGN 이 없는 연대기 사건·ui_driver 내보내기 단계를 약속. §8.4·§10·§12·§19 를 실제대로 | 문서 | — |
| G31 | 1280 에서 출생·사망을 켜면 '개체 수' 제목이 사라짐. 견본을 그림 안 띠로, 제목은 자르지 않음 | `_narrow_checks`(최소 폭 ≤ 540·제목 폭 ≥ 글자 폭) | 실패(옛 코드: 559 > 540, 제목 1px) |
| G32 | B 주황·A 초록이 경고 주황·강조 민트와 붙어 보임. A #3d9406·B #e54ec6(뜻 색과 정상 ΔE ≥ 16·색각 이상 ≥ 8.5, 바탕 대비 ≥ 4.5) | graph_checks `_color_checks`, test_repo_rules `TestPaletteClaims` | 실패 |
| G33 | 1280 에서 비교 이름이 씨앗 앞에서 잘려 같은 예설정·다른 씨앗이 같아 보임. 그래프 범례(그래프 묶음)와 지도 위 이름(통합 때, J03)이 예설정 이름만 줄이고 " · 씨앗 N" 은 남김 | `_narrow_checks`, lab_checks "좁은 비교 지도 이름" | 실패 |
| G34 | 1280 비교 지도가 칸 높이의 40% 미만(슬라임 3~4px). 세로로 긴 칸이면 지도를 90° 돌려 맞춤(≥ 55%), 나침반 "북 →", 정보 창 방향 화살표도 화면 기준. 혼자 모드는 북쪽 위 | lab_checks `_compare_portrait`·`_compare_stop`, ui_driver | 실패 |
| G35 | 비교 끄기·새 실험·나란히 시작이 오래 돈 실험을 묻지 않고 버림. `ui.param.confirm_discard_ticks`(2000) 이상이면 확인([끝내기][내보내고 끝내기][취소], 기본 초점 취소) | param_checks `_confirm` | 실패 2개 |
| G36 | sound_checks 가 LabSound 계수만 봐 실제 재생을 빼도 모름. 실제 AudioStreamPlayer 재생·스트림 확인 | sound_checks | 실패(`play()` 를 빼면 14개, 다른 소리면 11개) |
| G37 | 실험실이 자기 LabSound 를 사건에 잇는지 검사 없음 | sound·lab·integration4 | 실패 7개 |
| G38 | `MIN_CHECKS` 가 실제 검사 수보다 크게 낮아 중간에 끊겨도 통과. 모든 모듈을 실제 수로(param 만 180 / 188, 96%) | run_view_tests | —(상수. 연대기는 중간에 끊으면 실패함을 확인) |
| G39 | experiment_checks 가 `user://test_experiment` 를 지우지 않아 지난 실행의 파일이 회귀를 가릴 수 있음. PID 폴더, 처음·끝에 숨은 파일까지 지움 | experiment_checks | 실패 |
| G40 | 그래프 "시점 표시 그림" 검사가 공허(그렸는지·어디인지 안 봄). 그린 자리(px)를 확인 | `_lab_checks`·`_compare_checks` | 실패 6개 |
| G41 | README·presets.json 이 fast_civ·demo_fast 를 부풀려 씀. 실측대로(씨앗 7 은 첫 세대 폭발, demo_fast 씨앗 1 은 21.7세대) | 문서 | — |
| G42 | `stop_compare` 가 모든 알림을 지움(계약: A/B 알림만). 묶음(이름표) 있는 알림만 | lab_checks `_compare_stop` | 실패 |
| G43 | 정보 창을 비운 뒤에도 `current_tag()` 가 옛 이름표 | lab_checks(Esc·비교 끝) | 실패 2개(둘 다 되돌릴 때) |
| G44 | 비교 모드 내보내기 기본 폴더 이름에 A 씨앗만. `-seed<A>-vs-seed<B>`, 웹 스냅숏 이름은 그 실험의 씨앗, 파라미터 패널 스냅숏 저장 기본 이름도 두 씨앗(통합 때, J05) | lab_checks, web_checks, integration4 ⑤ | 실패 |
| G45 | 비교 모드에서 한 프레임에 소리 둘. 프레임의 A·B 사건을 모아 하나 | sound_checks | 실패 |
| G46 | 세로 눈금 수가 `y_ticks_max` 를 넘고 간격이 `y_tick_min_px` 아래 | `_y_tick_checks`(11 범위 × 7 높이) | 실패 |
| G47 | 비교 모드 멸종 표시가 어느 실험인지 말하지 않음. "A 멸종"/"B 멸종", B 점선, 겹치면 한 줄 아래 | `_extinct_compare_checks` | 실패 |
| G48 | 실수를 14자리로 보여 적용 값과 다를 수 있음. `JSON.stringify` 글자 | `_float_text` | 실패 2개 |
| G49 | "받는 쪽마다 따로 깊은 사본" 이 틀림(신호마다 사본 하나, 같은 신호의 청취자는 공유). 문서·주석 | lab_checks `_events`(계약을 적어 둠 — 문서만 틀렸으므로 전후 모두 통과) | — |
| G51 | 그래프·연대기 코드의 이름 없는 조정값(투명도·여백·무늬 배수·배지 간격). `ui.graph`·`ui.chronicle` 키와 이름 붙은 상수(픽셀 그대로) | G28 덮어쓰기 검사, test_repo_rules(문서의 키가 ui.json 에 있음) | — |
| G52 | 확인했다고 쓴 주장 가운데 섞였거나 저장소로 재현할 수 없는 것. 3절 "패널 몫" 문장을 고치고(U10), 색 수치는 `TestPaletteClaims` 가 저장소에서 다시 잼 | test_repo_rules | 실패 2개(나쁜 색) |
| G53 | 정보 창 멸종 안내가 여백 밖으로 넘침. 여백 안 줄바꿈 | lab_checks `_compare_extinction` | 실패 |
| G54 | 한국어 줄바꿈이 좌표·괄호를 가름. 연대기 줄바꿈은 괄호 안·숫자 앞 빈칸을 덜 끊음(지금 실험 카드·알림은 아래 "고치지 않은 것") | chronicle_checks `_wrap`(644 폭) | 실패 |
| G55 | 자리 접기 단추 "설정" ≠ 패널 제목 "실험 조건" → "실험 조건". 연대기 머리 줄 설명 잘림은 통합 때(J04) | lab_checks `_layout`, chronicle_checks "머리 줄 설명" | 실패 |
| G56 | param_checks 의 뼈대 시절 갈래·`t.check(true)` 채우기. 진짜 검사로(119 → 188개) | param_checks | 실패(`apply_compare` 가 실패하면 9개 — 전에는 뼈대 갈래로 통과) |

**병합 뒤 함께 띄워 드러난 것(통합 때 고침)** — 묶음마다 자기 파일만 고쳐서 합쳐야 보이던 것:

| ID | 고친 것 | 검사 · 고치기 전 |
| --- | --- | --- |
| J01 | 파라미터 패널의 새 실험 단추가 고정 바닥으로 옮겨졌는데(G08) lab_checks 의 초점 검사(G01)가 그 단추에 `ScrollContainer.ensure_control_visible` 을 불러 화면 검사 로그에 엔진 `ERROR: Must be an ancestor of the control.` 2줄(CI 는 실패로 봄). 스크롤 안의 칸만 스크롤 | 병합 직후 첫 전체 실행 로그 → 고친 뒤 0줄 |
| J02 | 띠 범위 글이 그림 오른쪽 여백을 쓰게 되며(G12) 1280 창 기술 단계 그래프가 1,212틱에서 가로축 이름 "0" 하나만(통합 I04 의 되풀이 — 검사가 없던 것, U09). 실제 이름 자리로 고름: 양 끝 이름은 안쪽으로 붙이고, 겹치면 더 넓은 간격, 하나뿐이면 둘 이상 들어가는 가장 넓은 간격. `last_x_labels` 기록, 2.5배·8px 를 이름 붙은 상수로 | graph_checks "가로축 이름"(폭 4가지 × 틱 범위 6가지 × 틱·세대 축 × 세 그래프) — 옛 코드 3개 실패(1,212틱 "0" 만, 세대 축 "0.5"·"1.0" 사이 7px) |
| J03 | G33 의 지도 몫(LabMain `_fit_title`, 그래프 묶음이 남긴 것) — 예설정 이름만 줄이고 씨앗은 남김, 꼬리가 길면 씨앗까지 남기고 끝을 줄임 | lab_checks "좁은 비교 지도 이름" — 옛 코드 1개 실패(두 이름이 "시연·검사용(아주 빠른 발견) · 씨앗 N" 을 끝에서 잘라 같아 보임) |
| J04 | G55 의 연대기 몫 — 머리 줄 설명이 안 들어가면 짧은 판 "틱 · 평균 세대 · 사건"(전체는 말풍선) | chronicle_checks "머리 줄 설명" — 옛 코드 1개 실패(320·331 폭에서 183px 글이 148·159px 칸) |
| J05 | G44 의 파라미터 패널 몫 — 비교 중 스냅숏 저장 기본 이름 `-seed<A>-vs-seed<B>` | integration4 ⑤ — 옛 코드 1개 실패 |
| J06 | G03 뒤 필요 없어진 graph_capture 의 "멸종 뒤 200틱 더" 우회 삭제(멸종 줄을 Experiment 가 씀), 이 보고서 4단계 5절의 A/B 색 표기·5단계 B08 의 web_checks 수, `MIN_CHECKS` 를 병합 뒤 실제 수로(graph 119·chronicle 86·lab 231·integration4 59) | 캡처(graphs-edge 의 멸종 표시)·run_view_tests |

**고치지 않은 것(까닭)**

| ID | 남은 것 | 까닭 |
| --- | --- | --- |
| G54 | 파라미터 패널 "지금 실험" 카드("시연·검사용(아주 빠른 / 발견)")·알림("(평균 / 8.1세대)")의 줄바꿈 | 이 둘은 Godot `Label` 자동 줄바꿈(`UiTheme.keep_words` 가 음절 사이만 막음)이라 "덜 끊기" 가 없다. 괄호 안·숫자 앞 빈칸을 낱말 잇개로 단단히 묶으면 1280 창 왼쪽 자리의 카드 이름이 세 줄이 되는 등 득실을 따로 정해야 한다. 연대기 목록(직접 접음)은 고쳤고, 규칙은 `ChroniclePanel.wrap_text` 에 있음 |
| G52 | 같은 지도 크기에서 패널만 숨긴 프레임 시간 대조(U10) | `perf_capture` 에 그 장면이 없고, 여러 작업이 godot 를 함께 돌리는 공유 기계의 새 수치는 3절 표와 견줄 수 없음. 문장은 "가르지 못했다" 로 고침 |
| G14 | 명령줄·실행기·스냅숏의 씨앗 범위 검사 | 시뮬레이션·실행기·스냅숏이 모든 정수 씨앗을 받는 것이 계약. 패널이 그 씨앗을 그대로 보이고 다시 쓰게 고친 것으로 충분(검증자의 방안 A) |
| G35 | 비교 모드를 다시 켤 때 B 칸 = A 사본, 스냅숏 열기는 묻지 않음 | 앞의 것은 VIEW-API 계약(오래 돈 B 는 끌 때 확인 대화 상자가 지킴). 스냅숏은 파일을 고른 것이 확인이고, FileDialog 신호 안에서 두 번째 독점 대화 상자를 띄우면 엔진 오류가 남 |
| G07 | perf_capture 의 마우스 쓸기 장면 | graph_checks 가 마우스 한 번에 계산 1번·선 다시 그리기 없음·이분 탐색을 헤드리스로 확인 — 실제 GPU 프레임 시간은 U02″ 와 같은 까닭으로 미검증 |

## 8. 결과 요약

- **최종 판정: 패널을 붙인 실험실의 종단 동작 통과(4단계 검토 55건 고침), 실제 GPU 속도·OS 대화 상자·Windows 는 미검증**
- 통과 / 실패 / 미검증: W01~W13 **13 / 0 / 0**, 미검증 표 U02″·U03·U06·U07·U08·U10 **6**(U05·U09 는 해결)
- 다음 확인 순서: 실제 GPU 에서 패널을 편 실험실 FPS(U02″) → Windows·macOS 화면·파일 대화 상자(U03·U07·U08) → 소리(U06)

# 1단계 3/5: 실험실 화면·분석 도구 통합 (v0.1.0-dev)

## 1. 대상 기록

| 항목 | 기록 |
| --- | --- |
| 검수 일시 / 담당 | 2026-10-07 / 제작 AI(Claude Code) — 워크트리 5개(SlimeGeo·MapView·InfoPanel·LabMain·분석 도구)를 main 에 병합, 이어서 검토에서 확인된 40건(F01~F43 중 F25·F39·F40 제외)을 고침 |
| 엔진 | Godot 4.4.1-stable, Compatibility(GL) 렌더러 |
| 실행 환경 | 클라우드 리눅스 컨테이너 4코어. 화면은 가상 디스플레이(xvfb) + **llvmpipe**(Mesa 25.2, CPU 소프트웨어 GL) — 실제 GPU 아님 |
| 범위 | `scripts/view/*`, `scripts/ui/*`, `scenes/lab.tscn`, `config/ui.json`, `tests/view/*`, `tests/*_capture.gd`, `tests/ui_driver.gd`, `tests/perf_capture.gd`, `tools/analyze.py`, `tools/test_repo_rules.py`. 시뮬레이션은 시간 계산 순서·사건 사본 두 곳만(역사 해시 그대로) |

## 2. 검사 결과

```
godot --headless --path . --script res://tests/run_tests.gd                  RESULT: 157 checks passed, 0 failed
godot --headless --path . --script res://tests/run_tests.gd -- --skip-slow   RESULT: 157 checks passed, 0 failed
godot --headless --path . --script res://tests/run_view_tests.gd             RESULT: 352 passed, 0 failed (view)
    geo_checks 76 · info_checks 55 · lab_checks 119 · map_checks 84 · smoke_checks 17 (모듈마다 MIN_CHECKS 이상)
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd
                                                                             RESULT: 32 passed, 0 failed (ui)
xvfb-run … --resolution 1280x720 --script res://tests/ui_driver.gd           RESULT: 31 passed, 0 failed (ui)   (V07 은 1600×900 에서만)
python3 -m unittest discover -s tools -p "test_*.py"                         Ran 29 tests … OK
```

화면 검사 로그에 `SCRIPT ERROR`·`ERROR:` 줄 없음(CI 가 이제 이것도 실패로 봄). 규칙 검사 로그의 `ERROR: Parse JSON failed` 4줄은 깨진 설정·스냅숏을 일부러 읽는 검사의 것이다.

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| V01 | 화면을 거쳐 진행해도 역사 해시와 끝 상태(개체·에너지·유전체·먹이 배열·연대기 수)가 헤드리스와 같음. 실제 프레임 진행(`advance_frame`)으로 해시 검사점(100틱)을 둘 넘게, 빨리 감기로만 진행한 틱도 검사점을 지나게, 정보 창을 거쳐도 검사점을 지나게 | 통과 | smoke_checks(8배로 201틱 넘게), lab_checks `_hash`(빨리 감기 구간이 검사점 통과), info_checks, map_checks, ui_driver(480·503틱 — 검토 고침 뒤 480·152·2,412·1,500틱 장면, 모두 헤드리스 해시와 같음) |
| V02 | 실제 MapView·InfoPanel 로 지도 클릭(실제 마우스 입력) → `pick_slime` 이 화면 가운데에 그린 바로 그 개체 → 정보 창·선택 같은 id, 빈 곳 클릭 → 선택 해제. 신호로 대신하는 길 없음 | 통과 | ui_driver(CI 밖, 이 컨테이너에서 실행) |
| V03 | 메시 예산(슬라임 398·식물 112·열매 80·저장고 312·밭 148·고리 288 삼각형), 닫힌 슬라임 곡면 | 통과 | geo_checks |
| V04 | 실험을 바꿔도 앞 세계의 저장고·밭이 남지 않음 | 통과(통합 때 고침) | map_checks |
| V05 | 화면 갱신 없이 세계만 진행한 뒤 `focus_on` 이 낡은 그린 위치가 아니라 지금 칸으로 | 통과(통합 때 고침) | map_checks |
| V06 | F 키 따라가기 ↔ 정보 창 "따라가기" 단추 상태 일치, Home 키 → 둘 다 끔 | 통과 | lab_checks |
| V07 | 1600×900 에서 보통 개체(자식 두 줄 이하)의 정보 창이 스크롤 없이 두뇌 범례까지, 여유 `info.min_vertical_slack`(8px) 이상 | 통과(자동) | info_checks: 정보 창 856px 높이에서 개체 60마리 모두, 가장 빠듯한 개체 여유 9px. ui_driver: lab-02 개체 여유 32px. 공용 단추 모양을 이어받아 머리가 2px 커진 몫은 `info.section_gap` 9→7, `heatmap_block_gap` 8→6, `heatmap_legend_height` 24→22 로 되찾음 |
| V08 | 캡처: 전경·농사 낮(저장고·밭 옆 개체)·같은 자리 밤·64배, 지도 3장, 정보 창 2장, 메시 모음 | 통과(눈으로 확인) | `docs/screenshots/v0.1/` (3D 장면은 JPG 품질 0.85, 117~166KB). 1280×720 판과 전경 선택 고리는 확인용으로만 찍음 |
| V09 | 보간은 마지막 한 틱만: 빨리 감기 중 멈춤·보통 속도로 돌아감에서 모든 슬라임이 지금 칸 근처(고치기 전 3~10칸 낡은 자리), 16배 2틱 프레임에서 한 프레임 이동 ≤ 1.9칸(고치기 전 2.6칸), 틱 경계에서 칸이 그대로인 개체는 움직이지 않음(고치기 전 0.4칸), 저장고 칸 개체는 처마 밖 문 앞, 밭 칸은 흙판 위 | 통과 | lab_checks `_ff_pause`·`_multi_tick_motion`, map_checks `_check_tick_interp`·`_check_store_doorstep`·`_check_farm_ground` |
| V10 | 실제 배속: 다시 재생·배속 바꿈 직후 "실제 —"(거짓 경고 없음), 75·144·240Hz 에서 언제나 정확히 "실제 N.0배", 3FPS 에서 0.75배 + 경고 색 | 통과 | lab_checks `_speed_window` |
| V11 | 시뮬레이션 예산: 250마리 64배 평균 8.5ms(예산 10), 빨리 감기 평균 12.7ms(예산 14) — 다음 틱 비용을 미리 더해 넘기 전에 멈춤(고치기 전 11.8·14.7ms) | 통과 | lab_checks `_budget` |
| V12 | 멀리서 보기: 전경 표시 배율 > 1·가까이 1, 선택 고리 화면 지름 ≥ `map.ring_min_px`(24px) × (1 − 맥동)·맨 위, 128×96·200×150 지도가 처음에 다 보임, `fit_map`/Home 이 처음 맞춤으로, 따라가기가 프레임 빠르기와 무관 | 통과 | map_checks `_check_overview`·`_check_big_maps`·`_check_fit_and_follow`, lab_checks `_extinction` |
| V13 | 알림·멸종: 새 실험이 앞 알림을 지움, 밭 잃음 묶음(×N), 강조 알림은 늦게 지움, 긴 오류는 지도 안에서 줄 바꿈·10초, 멸종 순간 멈춤·표지·"—"·정보 창 안내 | 통과 | lab_checks `_toast_rules`·`_extinction` |
| V14 | 정보 창: 은닉 64·기억 16 개체를 골라도 정보 창·지도 폭 그대로(기억 16·은닉 32 는 칸을 좁혀 가로 스크롤 없이), 따라가기 단추 여백 = `theme.button_padding_*`, 말풍선 = 공용 모양, 지켜보는 동안 자식 단추가 실제로 늘어나는 경로를 겪음 | 통과 | info_checks, lab_checks `_wide_brain` |
| V15 | 저장소 규칙: `assets/` 의 모든 파일이 CREDITS 에, 화면이 쓰는 세계 멤버가 모두 SIM-API 에, 문서의 `ui.절.키` 가 실제 키 | 통과 | tools/test_repo_rules.py |
| V16 | 고친 것마다 검사가 고치기 전 코드에서 실패하는지 | 통과(수동 확인) | 고친 부분만 되돌려 해당 검사 모듈을 돌림: F01·F04·F05·F06·F07·F08·F09·F10·F11·F12·F13·F18·F21·F22·F23·F24·F27·F32·F33·F34·F38 모두 실패. 분석 도구 새·고친 검사는 이전 `analyze.py` 로 돌리면 실패(11 실패·1 오류), 저장소 규칙은 이전 CREDITS·README·SIM-API 로 3개 실패, 중간에 스크립트 오류가 나는 모듈은 이제 FAIL |

## 3. 성능 실측

`tests/perf_capture.gd` (VIEW-API "성능 측정").

**① 헤드리스 미세 측정** — MapView `before_steps + update_view`, 프레임 600개(60fps 가정):

| 세계 · 배속 | 개체 | 화면 µs/프레임 평균(중앙 / 95%) | 틱 있는 프레임 / 없는 프레임 | 시뮬레이션 µs/프레임 |
| --- | --- | --- | --- | --- |
| 기본·250마리 · 1배 | 250 | **446** (388 / 1,206) | 923 / 393 | 327 |
| 기본·250마리 · 4배 | 174 | 522 (382 / 1,270) | 795 / 340 | 1,091 |
| 기본·250마리 · 64배 | 170 | 1,325 (1,387 / 1,746) | 1,325 / — | 18,666 |
| demo_fast(당시 이름 fast_civ) 1,760틱 · 1배 | 170 | 340 (272 / 1,062) | 809 / 287 | 293 |
| demo_fast(당시 이름 fast_civ) 1,760틱 · 64배 | 209 | 1,386 (1,360 / 1,805) | 1,386 / — | 22,399 |

- 검토 전(381µs, 틱 있는 프레임 654µs)보다 틱 있는 프레임이 0.2~0.3ms 무거워졌다: 틱이 바뀔 때 둘레 자리를 지금·이전 배열로 두 번 계산하고, 점유 칸의 풀포기를 줄였다 되돌리고 풀포기 버퍼를 다시 올린다. 여전히 1ms 안팎.

**② 실험실 실측(xvfb + llvmpipe, 1600×900)** — 기본·씨앗 1 을 2,132틱(개체 200)까지 진행한 뒤 개체 하나를 골라 둔 채 각 10초:

| 지도 MSAA · 배속 | 평균 FPS | 프레임 시간 중앙 | 우리 스크립트(`advance_frame`) | 그중 시뮬레이션 / 화면·UI | 실제 배속(10초) | 개체 평균 | 지도 3D 그리기 호출 · 기본 도형 | UI 2D 그리기 호출 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2× · 1배 | **8.0** | 123.7ms | **4.21ms** | 2.77 / 1.44ms | 1.0배 | 236 | 5 · 39.7만 | 173 |
| 2× · 64배 | **8.5** | 118.5ms | **9.44ms** | 7.72 / 1.71ms | 3.4배 | 219 | 5 · 39.0만 | 175 |
| 0 · 1배 | **13.4** | 73.6ms | 2.85ms | 1.67 / 1.18ms | 1.0배 | 236 | 5 · 39.7만 | 173 |
| 0 · 64배 | **12.0** | 80.7ms | 10.28ms | 8.40 / 1.88ms | 7.1배 | 176 | 4 · 37.1만 | 173 |

- **그리기 호출은 지도가 5, 나머지 ~173 은 2D UI** 다(뷰포트별 측정, 검토 전 보고서는 합계만 적어 지도 몫처럼 보였음). 지도의 MultiMesh 1회 그리기 설계는 그대로 지켜진다 — 지도 쪽 그리기 호출을 줄일 여지는 없다. UI 의 대부분은 정보 창(가계 단추·열지도 칸).
- llvmpipe 에서 프레임 시간의 대부분(100ms 넘게)은 그리기다. **실측한 지렛대는 지도 MSAA**: `lab.map_msaa` 2 → 0 이면 1배 프레임 시간 124 → 74ms(-40%). 검토에서는 풀포기 삼각형을 반으로 줄여도(한쪽 면 잎) 차이가 없었다고 보고됐다 — llvmpipe 의 비용은 삼각형 수보다 MSAA 아래 픽셀 채우기. 그래서 "멀리서 풀포기 메시를 낮은 단계로" 는 첫 후보가 아니다(실제 GPU 에서는 미검증).
- 64배 실제 배속이 검토 전(7.4배)보다 낮은 것은 예산을 이제 지키기 때문이다: 틱당 약 3.5ms 인 200마리 세계에서 10ms 예산이면 2틱(7.7ms)에서 멈춘다(예전에는 3틱째를 시작해 11ms). 프레임이 느린 llvmpipe 에서는 프레임당 틱 수가 곧 배속이라 낮아 보인다. 표시는 "목표 64배 / 실제 M배" 를 경고 색으로 정직하게 보인다.
- `view_stats().triangles_estimate` 는 이제 배율 0 으로 숨긴 풀포기 인스턴스와 슬라임 발밑 그림자까지 센다(그리기에 실제로 넘기는 양, 지도 기본 도형 39.7만과 근접한 40.4만).

## 4. 미검증

| ID | 내용 | 이유 |
| --- | --- | --- |
| U02′ | 실제 GPU 에서 200마리 60FPS | 이 환경에는 GPU 가 없어 llvmpipe 로만 쟀음(위 ②). 우리 스크립트 몫(1배 4.2ms)만 확인 |
| U03 | Windows·macOS 에서 화면 실행 | 리눅스뿐 |
| U04 | Windows(cp949·cp1252)에서 `analyze.py` 가 실행기 출력을 읽음 | 리눅스에서 UTF-8 로 읽도록 바꾸고(`encoding="utf-8"`) 실제 자식 프로세스의 한글 출력을 읽는 검사만 함 |
| ~~U05~~ | 바뀐 CI(로그의 `SCRIPT ERROR` 로 실패) | **해결**: 이 절의 마무리 커밋 `a54d4d0` 을 밀어 올린 Actions #5 에서 그대로 돌아 test 통과(4단계 4절) |

## 5. 검토에서 고친 것

검토에서 확인된 40건(F01~F43, F25·F39·F40 은 확인 목록에 없음). "검사" = 고치기 전 코드에서 실패함을 확인한 검사(V16).

| ID | 고친 것 | 검사 |
| --- | --- | --- |
| F01 | 빨리 감기 뒤 누적 = 1(지금 틱의 끝), 틱마다 `before_steps`, MapView 는 두 틱 이상 낡은 기억으로 보간하지 않음 | lab_checks `_ff_pause` |
| F02 | CREDITS 에 나눔고딕(OFL)·이전 프로젝트에서 가져온 파일 4개·`tools/`·파이썬 의존, README 에 OFL | test_repo_rules |
| F03 | CI 가 `SCRIPT ERROR`(화면 검사는 `ERROR:` 도)로 실패, 모듈마다 `MIN_CHECKS`, `t.node()` | 오류 모듈이 이제 FAIL(확인) |
| F04 | 한 프레임 여러 틱이어도 마지막 한 틱만 보간 | lab_checks `_multi_tick_motion`, map_checks `_check_tick_interp` |
| F05 | 둘레 자리(겹침)를 이전 틱 → 지금 틱으로 보간 | map_checks 틱 경계 |
| F06 | 저장고 칸 개체는 문 앞(+Z) 호에 | map_checks `_check_store_doorstep` |
| F07 | 밭 칸에서 슬라임·그림자·운반 열매를 흙판 위, 고리는 이랑 위 | map_checks `_check_farm_ground` |
| F08 | 큰 지도: 맞춘 거리에 따라 최대 거리·먼 면을 늘림 | map_checks `_check_big_maps` |
| F09 | 배속·멈춤·빨리 감기를 바꾸면 실제 배속 창을 비움 | lab_checks `_speed_window` |
| F10 | 실제 배속은 잘리지 않은 프레임 시간으로(창 길이까지) | lab_checks 3FPS |
| F11 | 실제 배속은 틱의 소수 몫까지 셈 | lab_checks 75·144·240Hz |
| F12 | 열지도 칸 너비를 창 폭에 맞추고, 넘치면 열지도만 가로 스크롤 | info_checks, lab_checks `_wide_brain` |
| F13 | 세계를 바꾸면 알림을 지우고 백업 경고는 바꾼 뒤에 | lab_checks `_toast_rules` |
| F14 | 정보 창이 공용 UiTheme 을 이어받음, 화면 코드의 이름 없는 수치를 `ui.json`·이름 붙은 상수로 | info_checks 단추 여백·말풍선 |
| F15 | smoke·lab 의 해시 검사가 검사점을 지나고 상태 배열도 견줌 | 정보 창 오염 주입 시 실패(확인) |
| F16 | 정보 창 해시 검사가 검사점을 지나고, 자식이 실제로 늘어나는 개체를 고름 | info_checks |
| F17 | SIM-API 에 읽기 전용 `cfg`·상수·정적 도움 함수 | test_repo_rules(경계 검사) |
| F18 | 다음 틱 비용(지수 이동 평균)을 더해 보고 예산을 넘기 전에 멈춤 | lab_checks `_budget`(평균 ≤ 예산 + 0.5ms) |
| F19 | `analyze.py` 가 쓰는 폴더에 `.gdignore` | test_analyze `test_gdignore` |
| F20 | DESIGN 의 글꼴·`ui.json` 키 이름, 3단계 바뀐 것(18절) | test_repo_rules(문서 키 검사) |
| F21 | 밭 잃음 알림 묶음(×N), 넘치면 강조 아닌 것부터 지움 | lab_checks `_toast_rules` |
| F22 | 긴 알림 줄 바꿈(지도 폭 안), 오류·경고 10초, 명령줄 오류는 터미널에도 | lab_checks `_toast_rules` |
| F23 | 선택 고리 화면 최소 지름(`map.ring_min_px`), 멀리서는 맨 위에 그림 | map_checks `_check_overview` |
| F24 | 멀리서 슬라임 표시 배율(`map.slime_min_px`, 최대 1.8) | map_checks `_check_overview` |
| F26 | `fit_map()`, Home·0 키, 지도 위 "전체 보기" 단추 | map_checks, lab_checks |
| F27 | 멸종 순간 멈춤(`lab.pause_on_extinction`)·표지·평균 세대 "—"·정보 창 안내 | lab_checks `_extinction` |
| F28 | 실행기가 실제 틱 상한을 `summary.json` 에, 이어 돌리기 때 다르면 mismatch | run_tests `test_runner`, test_analyze |
| F29 | 멸종 실행의 끝 평균 세대 = 멸종 직전 값 | test_analyze, 예시 보고서 다시 만듦 |
| F30 | 실행기 출력을 UTF-8 로 읽음 | test_analyze(인자·실제 자식 프로세스) |
| F31 | ui_driver 지도 클릭에서 신호 대체 길을 없앰, 그린 위치로 투영, 빈 곳 클릭 → 해제 확인 | ui_driver |
| F32 | 따라가기 부드러움을 프레임 시간 기준으로(`camera.follow_ref_fps`) | map_checks `_check_fit_and_follow` |
| F33 | 슬라임이 선 칸의 풀포기를 줄임(`map.plant_occupied_scale`) | map_checks `_check_plants_occupied` |
| F34 | `drain_events()` 는 연대기 사본 | run_tests `test_event_copies`, lab_checks(연대기 CSV) |
| F35 | 성능 측정을 뷰포트별로, 이 보고서의 그리기 호출 몫·지렛대(MSAA) 정정, 삼각형 추정에 숨긴 풀포기·그림자 | 위 3절(실측) |
| F36 | V07 을 자동 검사로(여유 8px) | info_checks, ui_driver |
| F37 | CI 머리 주석(내보내기는 5/5 순서) | — |
| F38 | 빛·계절을 `step()` 끝에서도 계산(틱 사이 = 지금 틱) | run_tests `test_time_after_step` |
| F41 | 빨리 감기 측정 세계가 살아 있음(초기 60마리)을 검사로 | lab_checks |
| F42 | 자연 순서에서 `-` 는 맨 앞·`=` 뒤에서만 음수 부호 | test_analyze `test_natural_order` |
| F43 | `--param` 배열 값(괄호 안 쉼표), 괄호·JSON 오류는 실행 전에 거부 | test_analyze |

## 6. 마무리 고침(F3-R1·F3-R2)

3단계 마무리 커밋(`a54d4d0`)에서 최종 확인(독립 에이전트)이 낸 2건을 고쳤다. 예전에는 이 표가 2단계 절 머리에 R1·R2 로 잘못 들어가 5단계 4절의 R1~R6 과 번호가 겹쳤다(검토 I66 — 옮기고 이름을 바꿈).

| 항목 | 내용 | 검사 |
| --- | --- | --- |
| F3-R1 | `lab_checks` 의 16배 한 프레임 이동 검사가 예산에 걸린 프레임(밀린 틱을 버림)에서 1.92칸을 재 부하가 큰 기계에서 간헐 실패 → 예산에 걸린 프레임은 재지 않음(그 수를 출력, 절반 미만이어야 함) | 수정 뒤 `lab_checks` 통과(예산에 걸리는 상황을 강제로 만들어 본 재현은 하지 않음) |
| F3-R2 | 강조 알림 4개로 꽉 찼을 때 새 일반 알림(예: F 키 "따라가기 켬")이 바로 사라짐 → 방금 띄운 알림은 지우지 않고 가장 오래된 강조 알림을 밀어냄 | `lab_checks` 새 검사(고치기 전 코드에서 실패 확인) |

## 7. 결과 요약

- **최종 판정: 3D 지도·정보 창·실험실 화면 통합 통과(3단계 검토 40건 고침), 실제 GPU 60FPS·Windows·macOS 는 미검증**
- 통과 / 실패 / 미검증: V01~V16 **16 / 0 / 0**, 마무리 고침 F3-R1·F3-R2 통과, 미검증 표 U02′·U03·U04 **3**(U05 는 해결)
- 다음 확인 순서: 실제 GPU 에서 200마리 60FPS(U02′) → Windows·macOS 화면(U03) → Windows 의 `analyze.py`(U04)

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
| S02 | 시뮬레이션 코드에 매직 넘버 없음(상수 선언 밖 숫자는 0·1·2·0.5 만), 금지 수학 함수(sin·cos·exp·log·pow·tanh·randfn 등) 없음 | 통과 | test_static_rules (소스 정적 검사 — 검토 고침 뒤 금지 목록 대신 허용 목록, 1_000·.25·0b·1e6 꼴도 잡음: I36) |
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
| **S15** | **평균 100세대 안에 농사(3단계)에 도달하는 파라미터 조합이 있음** | 통과 | test_farm_reachable: 예설정 `fast_civ`, 씨앗 1 → 평균 21.7세대에 농사(2단계 당시 값 — 4단계에서 다시 맞춘 `fast_civ`([`TUNING-fast_civ.md`](TUNING-fast_civ.md)) 씨앗 1 → 평균 49.0세대(3,321틱)에 농사, 씨앗 1~3 채집 ≥ 2세대(33.9·4.2·23.3). 예전 값은 `demo_fast`)(검토 고침 뒤 다시 잼: 28.5세대(2,040틱), 21.7·3.3·25.9 — 맨 앞 절 7) |
| S16 | 실행기: 인자 오류 거부, 결과 파일 5종·열 이름·행 수, 요약에 실제 설정, 설정 오류 코드 2 | 통과 | test_runner(검토 고침 뒤 수 인자·범위·인자 조합·결과 폴더·쓰기 실패 3 까지 — `tools/test_runner_cli.py`) |
| S17 | 실행기 이어 돌리기(`--resume`) 해시 = 끊김 없이 돌린 해시 | 통과(수동) | 씨앗 42: 30세대(t=2,155) → 이어서 40세대 = 바로 40세대, 둘 다 t=2,940·개체 184·해시 165b2c158266(검토 고침 뒤 자동 검사 test_runner_cli `TestResume`, 다시 잼: t=1,984 → t=2,472·개체 133·`18510b81ad2e` — 맨 앞 절 7) |
| S19 | GitHub Actions(ubuntu-latest): 검사 통과, 씨앗 1·100세대 해시 `713cea4dea1d` = 이 컨테이너의 해시(다른 리눅스 x86_64 기계 사이 결정성) | 통과 | [실행 37576513679](https://github.com/kyusang4657/slime-lab/actions/runs/37576513679)(검토 고침 뒤 규칙이 바뀌어 `171a3a4f1a5f` — Actions #12 도 같음, 맨 앞 절 10) |
| S18 | 성능 기록: 개체·틱당 µs | 통과 | test_performance: 평균 142마리, 17.8µs(검토 고침 뒤 합격 기준을 기계 속도와 떼어 기준 일의 배수로 — 다시 잼: 169마리, 28.8µs·721번 < 1,750, 맨 앞 절 7) |
| S20 | 헤드리스 1,000세대가 설계 13절 "수 분, 목표 5분 이내" | **실패** | 443.7초(7.4분), 아래 3절(검토 고침 뒤 다시 잼: 733.8초 — 기계가 느린 날, 맨 앞 절 7) |

## 3. 1,000세대 실측

```
godot --headless --path . --script res://tests/run_experiment.gd -- --seed=1 --generations=1000 --out=results/g1000
RESULT: seed=1 generations=1000.0 ticks=109604 pop=250 civ=3(농사) hash=78891cb07b26 time=443.7s reason=generations
```

(검토 고침 뒤 다시 잼: 112,234틱·`58e2ef0b38c5`·733.8초 — 규칙 고침으로 역사가 바뀌고 기계가 느린 날, 맨 앞 절 7.)

| 항목 | 값 |
| --- | --- |
| 걸린 시간 | **443.7초(7.4분)**, 평균 247틱/초, 개체·틱당 약 16µs. 실행 중 일부 구간은 검사(run_tests)와 CPU 를 나눠 씀 |
| 목표 | 설계 13절 "수 분, 목표 5분 이내" → **5분 목표는 실패**(7.4분). "수 분"에는 들어옴 |
| 틱·세대 | 109,604틱, 세대당 평균 약 110틱(초반 약 70틱, 후반 약 130틱 — 크기가 작아지는 진화와 함께 길어짐) |
| 출생·사망 | 132,456 / 132,406, 개체 수는 대부분 상한 250 |
| 발견 | 채집 t=2,737(평균 40.5세대) → 저장 t=3,573(54.9세대, 저장고 4개) → 농사 t=9,440(140.7세대). 끝날 때 밭 209칸 |
| 특성 변화 | 크기 1.00 → 0.63, 감지 반경 3 → 1(둘 다 하한 근처까지 줄어듦 — 대사 비용 압력), 평균 에너지 24 → 19 |
| 결과 파일 | summary 3KB, timeseries 720KB, chronicle 1.4KB, lineage 8.3MB(132,656행 = 처음 200 + 출생 132,456 — 예전 글의 132,706 은 계산 실수, 검토 J34), final.snapshot 7.0MB |

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
| 계절 | 4일·겨울 0.1 → 2일·겨울 0.3 | 겨울(240틱)이 수명 한 번만큼 길어 매해 겨울 끝에 멸종. 혹독한 겨울은 예설정 `harsh_winter` 로 남김(지금 `harsh_winter` 는 5일·겨울 0 으로 이보다 혹독한 멸종 조건 — 씨앗 1~12 모두 멸종, 검토 J22) |
| 에너지·번식 | 한입 2 → 3, 기본 대사 0.12 → 0.06, 성장 0.06 → 0.12, 번식 에너지 0.55 → 0.35, 몫 0.35 → 0.3, 쿨다운 20 → 10 | 첫 세대가 자기 수를 잇지 못함(씨앗 3개 × 조합 6가지 시험) |
| 세대 시간 | 성숙 40 → 30, 최대 나이 240 → 200, 상한 400 → 250, 초기 120 → 200 | 1,000세대를 수 분 안에(세대당 약 120틱 → 약 80틱). 성숙 30·나이 180 은 씨앗 1 이 멸종해 버림 |
| 판단 간격 | 성능이 모자라면 2 | 2 로 하면 씨앗 3개 모두 멸종(먹기·돌기 반복 낭비) → 1 유지 |
| 스냅숏 실수 | JSON 숫자(full_precision) → 비트 문자열 | Godot 4.4.1 `JSON.stringify(full_precision=true)` 가 0.1+0.2 → "0.3", 1e-300 → "0.0" (직접 확인) |
| 저장 발견 집계 | 모든 내려놓기 → 채집 발견 뒤의 내려놓기만 | 발견 순서 강제를 규칙으로도 보장 |

## 6. 결과 요약

- **최종 판정: 시뮬레이션 핵심·헤드리스 실행기 통과, 헤드리스 1,000세대 5분 목표만 실패**
- 통과 / 실패 / 미검증: S01~S20 **19 / 1 / 0**(S20 1,000세대 5분), 미검증 표 U01·U02 **2**(U02 는 3·4단계에서 U02′·U02″ 로 이어짐)
- 다음 확인 순서: Windows·macOS 에서 같은 역사 해시(U01) → 화면 단계에서 200마리 60FPS(U02) → 1,000세대 5분 방안(개체 상한 또는 C#/GDExtension) 결정
