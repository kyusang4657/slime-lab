# 검수 보고서

판정은 `통과 / 실패 / 미검증` 중 하나만 씁니다. 자동 검사로 확인한 것과 확인하지 못한 것을 구분합니다.

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
| B03 | Windows 내보내기 | 통과 | `slime-lab.exe` 100.0MB(서명 없음, 아이콘 리소스는 바꾸지 않음 — rcedit 없음) |
| B04 | Windows 에서 실행 | **미검증** | Windows 기기 없음 |
| B05 | 웹 내보내기(스레드 없는 판, Compatibility) | 통과 | wasm 43.7MB + pck 2.6MB, 합 45MB |
| B06 | 웹 체험판이 브라우저에서 뜨고 실험이 진행됨 | 통과(헤드리스) | 헤드리스 Chromium + SwiftShader WebGL2: 오류·pageerror 없음, 실험실 전체 화면, 틱 진행 |
| B07 | 웹 체험판 속도 | 기록 | SwiftShader(소프트웨어 그래픽)에서 64배 목표에 실제 1.1배. **실제 GPU 브라우저 속도는 미검증** |
| B08 | 웹에서 "CSV 내보내기"·"스냅숏 저장" → 내려받기(zip·JSON), "스냅숏 열기" 숨김 | 통과 | `tests/view/web_checks.gd` 16개(zip 안 5개 파일, zip 의 시계열 = 기록기 CSV, 내려받은 스냅숏을 열면 같은 해시, 웹 모드 단추) — 브라우저의 실제 내려받기 창은 미검증 |
| B09 | 실행 파일에 검사·도구·문서가 들어가지 않음 | 통과 | `exclude_filter`, 실행 파일에서 검사 문장(예: "농사 도달 시도") 0회 |
| B10 | 글꼴 OFL 전문이 배포판에 들어감 | 통과(설정) | 포함 필터 `assets/fonts/OFL-NanumGothic.txt`, Actions zip 에 LICENSE·CREDITS·OFL |
| B11 | 앱 아이콘(코드로 렌더링) | 통과 | `assets/icon.png`(`tests/icon_capture.gd`), 웹 파비콘에도 쓰임 |
| B12 | 타임랩스(빠른 문명·씨앗 5, 32배, 1,800틱, 채집 648 → 저장 702 → 농사 1,024틱) | 통과 | `docs/media/timelapse.webm` 1.2MB(VP9 — 오픈소스 Chromium 계열도 재생), `.mp4` 1.1MB(H.264), `.gif` 2.9MB |
| B13 | Actions: test → export(세 플랫폼, Linux 헤드리스 실행) → pages(main) / release(태그) | 푸시 뒤 확인 | 아래 3절 |

## 3. Actions 첫 실행

(푸시 뒤 기록)

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

화면 검사 로그에 `SCRIPT ERROR`·`ERROR:` 줄 없음. 규칙 검사 로그의 `ERROR: Parse JSON failed` 4줄은 깨진 설정·스냅숏을 일부러 읽는 검사의 것이다. 화면 검사는 3단계 352개 → 819개(새 모듈: param·graph·chronicle·sound·experiment·integration4).

| ID | 확인 내용 | 판정 | 근거 |
| --- | --- | --- | --- |
| W01 | 파라미터 패널 값(예설정·씨앗·세 주요 값·고급 키) → 새 실험의 `cfg`·씨앗·개체 수, 적용 전에는 지금 실험 그대로, 적용 뒤 "지금 실험과 같음", 범위 밖 값은 줄 아래 오류·단추 꺼짐 | 통과 | integration4 ①, param_checks |
| W02 | 패널로 비교 시작 → 지도 둘, 바꾼 값은 그 칸의 세계에만, 그래프 세 개에 계열 둘(점 수 = 기록 줄 수), 범례 둘, 연대기 A/B 줄 수 = 두 연대기 합, 알림 "A · "/"B · " | 통과 | integration4 ②, lab_checks `_compare`, ui_driver ⑥ |
| W03 | 연대기 줄을 실제 마우스로 누름 → 그래프 시점 세로선, 행위자(첫 밭)가 있으면 **그 실험의** 개체 선택(실험 번호 1, 정보 창 이름표 B, 고리는 B 지도에만), 두 세계 그대로 | 통과 | integration4 ③, chronicle_checks |
| W04 | 패널의 CSV 내보내기 → 비교면 `A/`·`B/` 각각의 timeseries.csv·chronicle.csv 가 같은 예설정·바꾼 값·씨앗·틱 수의 헤드리스 실행기 결과와 **글자까지** 같음 | 통과 | integration4 ④, experiment_checks |
| W05 | 스냅숏 저장 → 더 진행 → 열기 = 저장한 틱·해시·상태(처음부터 돌린 헤드리스 세계와 비교), 이어 돌려도 같음. 비교 중 저장은 `-A`·`-B` 두 파일 | 통과 | integration4 ⑤ |
| W06 | 화면은 시뮬레이션을 바꾸지 않음: 패널을 모두 붙인 채 실제 프레임(64배)·`step_ticks` 로 진행해도 역사 해시·상태 배열이 헤드리스와 같음(혼자·비교 A·B, 연대기 클릭 뒤에도) | 통과 | integration4 ①②③⑤, lab_checks, chronicle_checks, graph_checks, ui_driver ⑤⑥ |
| W07 | 최소 창 1280×720·자리 모두 펼침에서 배치가 창 안(정보 창 오른쪽 끝 = 창 끝, 아래 자리 = 왼쪽 자리 + 지도), 비교 지도 한 칸 ≥ 320×400, 조작 도움말이 A 칸 안, 가장 긴 위쪽 막대 ≤ 1280 | 통과(통합 때 고침) | lab_checks `_fits_window`·`_compare_layout`·`_docks`, ui_driver 1280 |
| W08 | V07(1600×900 에서 정보 창이 스크롤 없이 두뇌 범례까지) — 패널을 붙여도 | 통과 | ui_driver 1600(정보 창이 세로 전체) |
| W09 | 캡처 장면의 그래프·연대기가 세계와 맞음(그래프 줄 수 = 기록, 마지막 기록 틱이 세계 틱의 `record.every` 안, 연대기 = 세계 연대기) | 통과(통합 때 고침) | ui_driver lab-02 새 검사 |
| W10 | 효과음: 16비트 모노, 길이·최댓값 ≤ 0.8 FS·NaN 없음·첫/끝 샘플 0·같은 입력이면 같은 바이트·음높이 방향, 같은 소리 0.5초 간격, 묶음에서 가장 중요한 소리 하나, 패널 "소리" 상자 ↔ `LabSound.enabled` | 통과(자동) | sound_checks, integration4 ⑥ |
| W11 | 연구용 `fast_civ`: 씨앗 1 이 평균 49.0세대에 농사, 씨앗 1~3 의 채집이 평균 2세대 이후(예전 값이면 실패) | 통과 | run_tests `test_farm_reachable` |
| W12 | 통합에서 고친 것마다 검사가 고치기 전 코드에서 실패 | 통과(수동 확인) — **I04 는 미검증** | 고친 것마다 따로(5절): I01·I02 — 연대기 폭 규칙·세 줄 도움말을 되돌리면 lab_checks 4개 실패(정보 창 오른쪽 끝 1326 > 1280 등), 되살리면 통과. I03 — `keep_words` 가 글자를 그대로 돌려주게 하면 integration4 ⑦ 1개 실패("발/견" 에서 줄바꿈), I05 — ui_driver 농사 장면을 예전처럼 세계 `step()` 으로 돌리면 새 검사 1개 실패(그래프 1줄·마지막 틱 0 / 세계 1,696): 둘 다 통합 때가 아니라 4단계 검토(G29) 때 확인. I06 — 검토 때 더한 test_repo_rules `test_user_dir_is_ascii`(설정 줄을 지우거나 이름이 한글이면 실패). **I04 는 자동 검사가 없다**(캡처로만, U09). 구성 요소별 확인은 각 담당(연대기: 중복 건너뛰기·A/B 순서를 일부러 깨면 8개 실패, fast_civ: 예전 값이면 S15 실패) |
| W13 | 캡처를 1600×900·1280×720 둘 다 눈으로 확인: 전경·농사 낮(선택)·밤·64배·패널·비교, 그래프·연대기·파라미터 패널 | 통과(눈으로 확인) | `docs/screenshots/v0.1/`(lab-*.jpg 150~220KB, png 63~124KB). 1280 판은 확인용으로만 찍음 |

## 3. 성능 실측

`tests/perf_capture.gd`(VIEW-API "성능 측정" 4단계). **먼저 기계 속도:** 지도·시뮬레이션 코드는 3단계와 같은데(diff 없음) 같은 헤드리스 미세 측정이 3단계 보고서보다 약 1.7배 느렸다(기본·250마리 1배 화면 768µs ↔ 446µs, 64배 시뮬레이션 32.1ms ↔ 18.7ms, demo_fast 1배 627 ↔ 340µs). 공유 기계가 그만큼 느렸던 것이므로 **아래 수치는 이 날의 수치끼리만** 견준다.

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
| U03·U05 | Windows·macOS 화면 실행, 바뀐 CI | 리눅스뿐, 밀어 올리지 않아 GitHub Actions 에서 아직 돌지 않음(같은 명령을 이 컨테이너에서 돌려 0 failed·오류 줄 0 확인) |
| U09 | I04: 좁은 그래프(1280 창 아래 자리)의 가로축 이름이 둘 이상·서로 겹치지 않음 | 캡처로만 봄. GraphView 가 그린 가로축 이름을 기록하지 않아 헤드리스 검사가 없음(그래프 담당 몫 — `last_markers` 처럼 기록하고 graph_checks 에 좁은 폭·1600 폭 경우를 더하면 됨) |
| U10 | 패널의 실제 그리기 몫(같은 지도 크기에서 패널만 숨긴 프레임 시간 대조) | perf_capture 에 그 장면이 없음 — 3절의 편·접은 비교는 지도 크기가 달라 패널 몫을 가르지 못함 |

## 5. 통합에서 고친 것

| ID | 고친 것 | 검사 |
| --- | --- | --- |
| I01 | 최소 창 1280×720 에서 아래 자리 최소 폭(연대기 420 + 그래프 최소 540 + 간격·여백 = 986px)이 자리(940px)를 넘어 **정보 창과 위쪽 막대 오른쪽 끝이 창 밖으로 46px** 밀림(구성 요소 검사로는 보이지 않음 — 각자 따로 띄움). 연대기 폭을 창 폭에 맞춤: (창 − 정보 창 − 여백) × `chronicle.dock_frac`(0.36)를 [`chronicle.min_width` 320, `chronicle.width` 420]로 자르고 그래프 최소 폭을 보장 → 1600 창 420, 1280 창 331 | lab_checks `_fits_window`(혼자·비교), 1600 창이면 420. 고치기 전 실패 확인 |
| I02 | 1280 창 비교 모드에서 두 줄 조작 도움말이 A·B 지도 사이를 걸침 → 키 줄을 나눈 세 줄 단계, 비교 모드는 A 칸에 들어가는 가장 적은 줄 | lab_checks "좁은 비교 모드" — 고치기 전 실패 |
| I03 | 한글이 음절 사이("발/견")에서 줄이 바뀜(파라미터 패널 "지금 실험", 알림) → `UiTheme.keep_words`(낱말 잇개 U+2060, 폭 0) | integration4 ⑦ |
| I04 | 1280 창 그래프 가로축에 "0" 만 남음 → 좁은 그림에서는 이름이 겹치지 않을 만큼만 띄움, `graph.x_label_min_px` 56 → 50(1600 창은 그대로 500틱 간격) | 캡처로만 확인 — **자동 검사 없음**(U09). 좁은 그림 판정의 2.5배·여백 8px 도 아직 코드 상수 |
| I05 | ui_driver 농사·밤 장면(과 perf_capture)이 세계를 직접 `step()` 해 기록이 안 따라가 **그래프가 틱 0 한 점에 멈춘 채** 틱 1,696 장면이 찍힘 → `lab.step_ticks` | ui_driver 새 검사(그래프 줄 수·마지막 틱·연대기 = 세계) |
| I06 | 사용자 폴더를 영문으로(`application/config/custom_user_dir_name = "slime-lab"`) — 한글 경로에서 엔진 FileDialog 가 거짓 "권한 없음" 을 띄움(파라미터 담당 요청) | 경로 출력 확인. 검토(G29) 뒤 test_repo_rules `test_user_dir_is_ascii`(project.godot 의 이름이 영문·숫자인지 — 설정을 지우면 실패) |
| I07 | CREDITS 에 합성 효과음(CC0) 줄, SIM-API `cfg` 행(ParamPanel 이 모든 잎 키를 깊은 사본으로 읽음), VIEW-API 낡은 3단계 배치·`fast_civ` 이름, 3단계 성능 표·S15 의 `fast_civ` → 당시 값 `demo_fast` 표기, `experiment_checks.gd.uid` 추적, lab_checks 의 연대기 폭 검사를 새 규칙으로 | test_repo_rules |

구성 요소 담당이 계약과 다르게 정한 것(모두 받아들임, 근거는 VIEW-API 각 구현 메모): 정보 창 세로 전체·아래 자리 = 왼쪽 자리 + 지도·자리 접기 단추는 지도 위(LabMain), 비교 모드에서 한쪽만 멸종하면 멈추지 않음(LabMain), 강조·"바꾼 값 N개" 는 지금 실험과 견줌(ParamPanel), 저장고·밭 수는 이중 축 대신 작은 띠 둘·A/B 색 #2aa98a·#d97630(색각 이상 검사 통과 — 처음엔 저장소 밖 dataviz 검사기로 한 번 잼, 4단계 검토(G52) 뒤 `tools/test_repo_rules.py` `TestPaletteClaims` 가 같은 계산(Machado 2009 심도 1.0·OKLab ΔE×100·WCAG 대비)으로 VIEW-API 의 그래프·연대기 색 수치를 config/ui.json 에서 다시 잼, 연대기는 `other` 를 뺀 다섯 묶음)·축 글자 12px(GraphPanel), 연대기 목록 안에서는 "평균" 을 줄임·낱말 단위 직접 줄바꿈(ChroniclePanel), 소리는 사인 + 약한 배음 3종(LabSound).

## 6. `fast_civ` 다시 맞춤(요약)

근거·후보 표·재현 명령은 [`TUNING-fast_civ.md`](TUNING-fast_civ.md). 목표는 "발견이 첫 세대에 바로 열리지 않고 진화 도중에, 100세대 안에 농사".

- 값: `discovery.forage_threshold` 280 · `store_threshold` 30 · `region_size` 16 · `farm_radius` 16 · `farm_threshold` 15(나머지 기본). 예전 값(채집 120·저장 30·농사 8)은 시연·검사용 `demo_fast` 로 남김.
- 씨앗 1~12 × 100세대 실측: 채집 중앙값 7.7세대(IQR 5.4~14.0, 12/12), 저장 8.6(6.3~16.5, 12/12), 농사 15.9(12.3~26.1, 12/12, 가장 늦은 씨앗 74.3), 멸종 0. 예전 값은 11/12 씨앗이 채집을 바로 열었다(채집·저장·농사 중앙값 0.2·0.3·2.1세대).
- 못 맞춘 목표(정직하게): 저장 15~35·농사 30~70 세대 중앙값은 맞추지 못함 — 빠른 씨앗을 늦추려 임계를 올리면 느린 씨앗(1·3·8·11)이 100세대를 넘김. 씨앗 7 은 여전히 2세대 안에 셋 다 엶(첫 세대 무작위 두뇌의 배부른 줍기 시도 371회). 근본 원인은 발견 집계가 누적이라 첫 세대가 지배하는 것 — 코드 변경 제안으로 남김.
- 검사: S15(`test_farm_reachable`)가 `fast_civ` 를 먼저 시도해 씨앗 1 → 평균 49.0세대에 농사, 씨앗 1~3 채집 ≥ 2세대(33.9·4.2·23.3)를 확인(예전 값이면 4.35·0.22·0.49 로 실패). 규칙 검사 전체는 159개(+1).

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
| V01 | 화면을 거쳐 진행해도 역사 해시와 끝 상태(개체·에너지·유전체·먹이 배열·연대기 수)가 헤드리스와 같음. 실제 프레임 진행(`advance_frame`)으로 해시 검사점(100틱)을 둘 넘게, 빨리 감기로만 진행한 틱도 검사점을 지나게, 정보 창을 거쳐도 검사점을 지나게 | 통과 | smoke_checks(8배로 201틱 넘게), lab_checks `_hash`(빨리 감기 구간이 검사점 통과), info_checks, map_checks, ui_driver(480·503틱) |
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
| U05 | 바뀐 CI(로그의 `SCRIPT ERROR` 로 실패) | 커밋만 하고 밀어 올리지 않아 GitHub Actions 에서 아직 돌지 않음. 같은 grep 을 이 컨테이너 로그에 돌려 0줄 확인 |

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

# 1단계 2/5: 시뮬레이션 핵심·헤드리스 실행기 (v0.1.0-dev)


최종 확인(독립 에이전트)에서 나온 2건도 고쳤습니다.

| 항목 | 내용 | 검사 |
| --- | --- | --- |
| R1 | `lab_checks` 의 16배 한 프레임 이동 검사가 예산에 걸린 프레임(밀린 틱을 버림)에서 1.92칸을 재 부하가 큰 기계에서 간헐 실패 → 예산에 걸린 프레임은 재지 않음(그 수를 출력, 절반 미만이어야 함) | 수정 뒤 `lab_checks` 통과(예산에 걸리는 상황을 강제로 만들어 본 재현은 하지 않음) |
| R2 | 강조 알림 4개로 꽉 찼을 때 새 일반 알림(예: F 키 "따라가기 켬")이 바로 사라짐 → 방금 띄운 알림은 지우지 않고 가장 오래된 강조 알림을 밀어냄 | `lab_checks` 새 검사(고치기 전 코드에서 실패 확인) |

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
| **S15** | **평균 100세대 안에 농사(3단계)에 도달하는 파라미터 조합이 있음** | 통과 | test_farm_reachable: 예설정 `fast_civ`, 씨앗 1 → 평균 21.7세대에 농사(2단계 당시 값 — 4단계에서 다시 맞춘 `fast_civ`([`TUNING-fast_civ.md`](TUNING-fast_civ.md)) 씨앗 1 → 평균 49.0세대(3,321틱)에 농사, 씨앗 1~3 채집 ≥ 2세대(33.9·4.2·23.3). 예전 값은 `demo_fast`) |
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
