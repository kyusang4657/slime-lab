# 오프라인 분석 도구 (`tools/analyze.py`)

헤드리스 실행기(`tests/run_experiment.gd`)를 **씨앗 여러 개 · 파라미터 격자**로 돌리고, 결과 폴더들을 모아 표·보고서·그림을 만드는 파이썬 스크립트입니다. 앱(실험실 화면)에는 들어가지 않습니다 — 앱은 Godot 하나로 오프라인 동작하고, 파이썬은 "여러 번 돌려 비교하기"를 맡습니다.

- 질문 예: "돌연변이율 0.02 와 0.1 중 어느 쪽이 농사를 먼저 여나?", "이 예설정에서 멸종은 몇 번에 한 번?", "씨앗마다 발견 세대가 얼마나 흩어지나?"
- 한 실행의 이야기(지도·개체·연대기)는 실험실 화면에서, **여러 실행의 분포**는 이 도구에서 봅니다.

## 설치

```bash
pip install -r tools/requirements.txt      # numpy, pandas, matplotlib
```

Python 3.9 이상. matplotlib 이 없으면 그림만 건너뛰고 표·보고서는 만듭니다(그렇다고 안내함). godot 4.4.1 이 필요합니다(`--godot` 또는 환경 변수 `GODOT`, 기본 `godot`). 처음 한 번 `godot --headless --path . --import`.

## 명령

### `run` — 같은 설정, 씨앗 여러 개

```bash
python3 tools/analyze.py run --seeds 1-8 --generations 100 --preset fast_civ --out results/fast8
python3 tools/analyze.py run --seeds 1,3,5 --generations 50 --set mutation.rate=0.08 --set resources.scale=1.4 --out results/mut08
```

씨앗마다 실행기 하나를 `OUT/seed<N>/` 에 돌리고, `OUT/runs.csv` 에 결과 줄(`RESULT: …`)·종료 코드를 적은 뒤 `report` 를 부릅니다.

### `sweep` — 파라미터 격자 × 씨앗

```bash
python3 tools/analyze.py sweep --param mutation.rate=0.02,0.05,0.1 --seeds 1-4 --generations 30 --preset fast_civ --out results/mut-sweep
python3 tools/analyze.py sweep --param mutation.rate=0.02,0.1 --param resources.scale=1,1.6 --seeds 1-4 --out results/grid
```

`--param` 을 여러 번 주면 **전체 격자**(위 둘째 줄은 2 × 2 = 4칸)입니다. 칸마다 `OUT/<키=값__키=값>/seed<N>/`. 보고서는 칸(= 묶음)별로 묶습니다. `--set` 은 모든 칸에 공통으로 덮어쓰고, 같은 키를 `--param` 이 또 주면 격자 값이 이깁니다.

### `report DIR` — 이미 있는 결과 모으기

```bash
python3 tools/analyze.py report results/mut-sweep                 # 같은 폴더에 보고서
python3 tools/analyze.py report results --out results/모두-보고서   # 여러 묶음을 한 보고서로
```

`DIR` 아래의 `summary.json` 을 모두 찾습니다(실행기를 손으로 돌린 폴더도 됨). **묶음 이름** = 실행 폴더의 부모 폴더 경로(`mutation.rate=0.1` 등). 씨앗 폴더가 `DIR` 바로 아래에 있으면(`run` 결과) 예설정 이름(+덮어쓰기)으로 짓습니다(`fast_civ`, `default+mutation.rate=0.08`).

### 인자

| 인자 | 기본 | 뜻 |
|---|---|---|
| `--seeds` | `1-4` | `1-8`, `1,3,5`, `1-3,7` (겹치면 한 번, 오름차순) |
| `--generations` | `100` | 목표 평균 세대(실행기 `--generations`) |
| `--preset` | `default` | `config/presets.json` 이름 |
| `--set 키=값` | — | 설정 덮어쓰기, 여러 번. 값은 실행기가 해석(`[1,1,0.5,0]` 같은 배열도 됨) |
| `--param 키=v1,v2` | — | `sweep` 전용, 여러 번 → 격자 |
| `--jobs N` | min(4, CPU 수) | 동시에 돌릴 실행기 수 |
| `--godot` | `$GODOT` 또는 `godot` | godot 실행 파일 |
| `--repo` | `tools/` 의 부모 | 저장소 위치 |
| `--out` | (필수) | 결과 폴더 |
| `--lineage` / `--no-lineage` | `--no-lineage` | 묶음에서는 `lineage.csv`(1,000세대면 8MB)를 기본으로 쓰지 않음 |
| `--max-ticks` | 설정값 | 틱 상한 |
| `--timeout` | `3600` | 실행 하나의 시간 제한(초). 넘으면 그 실행만 끝내고 `timeout` 으로 기록 |
| `--no-report`, `--no-plots` | — | 보고서 / 그림 끄기 |
| `--lang` | `auto` | 그림 문구 `ko`·`en`. `auto` 는 나눔고딕(`assets/fonts`)을 쓸 수 있으면 한국어 |

**이어 돌리기:** `summary.json` 이 이미 있는 씨앗 폴더는 건너뜁니다. 같은 명령을 다시 주면 실패·중단된 것만 다시 돌립니다(`runs.csv` 의 이전 성공 줄은 그대로 둠). 건너뛰기 전에 그 결과의 예설정·목표 세대·덮어쓰기를 이번 요청과 비교해, 다르면 덮어쓰지 않고 경고와 함께 `mismatch` 로 기록합니다(보고서의 실패 표에 나옴). 설정을 바꿨으면 다른 `--out` 을 쓰세요. 종료 코드: 모두 성공 0, 실패·mismatch 가 있으면 1, 인자·저장소 오류 2.

## 결과 파일

```
OUT/
  runs.csv                 실행 기록: cell, seed, status(ok·failed·timeout·error·existing·mismatch), exit_code, wall_seconds, result(RESULT 줄), out_dir, command
  summary.csv              실행마다 한 줄 (아래)
  cells.csv                묶음마다 한 줄 (아래)
  report.md                한국어 보고서(표 + 그림 + 읽는 법)
  population.png  mean_gen.png  traits.png  civ_stage.png  discovery.png
  seed1/  …                실행기 결과(summary.json, timeseries.csv, chronicle.csv, final.snapshot.json) + run.log
```

**`summary.csv`** (UTF-8, 쉼표, 영문 열 이름, 빈 값 `NaN`):

| 열 | 뜻 |
|---|---|
| `cell`, `seed`, `preset`, `overrides`, `generations_target` | 묶음, 씨앗, 예설정, 실제 덮어쓰기(`키=값;…`), 목표 세대 |
| `end_reason` | `generations`(목표 도달) · `extinction` · `max_ticks` |
| `ticks`, `mean_generation`, `population`, `peak_population`, `births`, `deaths` | 끝날 때 값(`summary.json`) |
| `civ_stage`, `civ_stage_name` | 끝날 때 문명 단계 0~3(없음·채집·저장·농사) |
| `extinct_tick`, `storehouses`, `farms` | 멸종 틱(-1 없음), 저장고·밭 수 |
| `disc_tick_forage` · `disc_gen_forage` (`_store`, `_farm`) | 채집(저장·농사) **발견 틱(-1)·발견 세대(NaN = 발견 못 함)** |
| `final_mean_size`, `final_mean_sense` | 살아 있던 마지막 기록의 평균 크기·감지 반경 |
| `run_seconds`, `history_hash`, `path` | 실행기 시간, 역사 해시(64자), 실행 폴더(상대 경로) |

**`cells.csv`**: `runs`, `extinct`·`extinction_rate`, `reached_<단계>`·`reach_rate_<단계>`(끝 단계가 그 이상인 실행 수·비율), `disc_gen_<단계>_n/_median/_q1/_q3/_iqr`(도달한 실행만), `mean_generation_median`, `ticks_median`, `population_median`, `peak_population_median`, `final_mean_size_median`, `final_mean_sense_median`, `run_seconds_median`, `run_seconds_total`.

## 그림

모두 실행마다 얇은 선(또는 점) 하나이고, 색 = 묶음(고정 순서 8색). 묶음이 8개를 넘으면 색을 돌려쓰지 않고 **묶음마다 작은 그림**(가로 4칸씩)으로 나눕니다(특성 그림은 `traits_mean_size.png`·`traits_mean_sense.png` 두 장). 묶음이 둘 이상이면 아래에 범례, 하나면 부제에 이름.

| 파일 | 보이는 것 |
|---|---|
| `population.png` | 개체 수 대 틱. 멸종한 실행은 끝에 ×. 상한(`population.cap`, 기본 250)에 붙은 구간은 먹이가 아니라 상한이 개체 수를 정함 |
| `mean_gen.png` | 평균 세대 대 틱. 기울기 = 세대 교체 속도 |
| `traits.png` | 평균 크기(왼쪽)·평균 감지 반경(오른쪽) 대 평균 세대. 거의 변하지 않을 때 잡음이 커 보이지 않게 세로 범위를 최소 0.2·1.0 으로 둠 |
| `civ_stage.png` | 문명 단계 계단선 대 평균 세대. 겹치지 않게 실행마다 세로로 조금씩 띄움. 멸종한 실행은 끝에 × |
| `discovery.png` | 단계(채집·저장·농사)마다 한 칸, 세로 = 묶음. 점 = 실행, 회색 상자 = 사분위 범위(실행 3개 이상), 검은 선 = 중앙값, 오른쪽 = 도달 수/전체 |

## 발견 세대는 이렇게 계산합니다

1. 실행의 `chronicle.csv` 에서 `kind = discovery` 인 줄을 찾습니다. 시뮬레이션이 발견 순간에 `mean_gen`(그 틱에 살아 있는 개체들의 평균 세대, 0.01 단위로 반올림)을 함께 적습니다.
2. 단계는 문장 머리 `채집 발견 — …`·`저장 발견 — …`·`농사 발견 — …` 로 가립니다. 머리가 다르면(문구가 바뀐 경우) `summary.json` 의 `discovery_ticks` 와 **같은 틱**의 사건으로 맞춥니다.
3. 연대기가 없거나 사건이 빠졌는데 `summary.json` 에 발견 틱이 있으면, `timeseries.csv` 의 평균 세대를 그 틱으로 선형 보간합니다(근사).
4. 발견하지 못한 단계는 틱 -1, 세대 `NaN`. 묶음 통계(중앙값·사분위)는 **도달한 실행만**으로 계산하고, 도달 비율을 따로 적습니다.

사분위는 numpy 기본(선형 보간) 백분위수입니다.

## 주의

- **시간:** 기본 설정에서 실행 하나가 평균 약 250틱/초, 세대당 약 110틱 → **세대당 약 0.45초**(1,000세대 ≈ 7.4분, `docs/TEST-REPORT.md`). 전체 ≈ 묶음 수 × 씨앗 수 × 세대 × 0.45초 ÷ `--jobs`. CPU 코어보다 `--jobs` 를 크게 주면 빨라지지 않습니다. `fast_civ` 40세대 씨앗 4개는 4코어에서 약 15초.
- **`run_seconds`** 는 동시에 돌던 다른 실행과 CPU 를 나눈 시간입니다. 성능 비교에는 `--jobs 1` 로.
- **결정성:** 같은 씨앗·같은 설정·같은 코드면 역사 해시가 같습니다(병렬로 돌려도). 같은 결과 폴더로 `report` 를 다시 만들면 `summary.csv`·`cells.csv`·`report.md` 는 바이트까지 같습니다(검사함. `summary.csv`·`cells.csv` 는 pandas 2.2 와 3.0 사이에서도 같음을 확인). 실행을 다시 돌리면 `run_seconds` 만 달라집니다. 해시가 다르면 설정이나 코드가 다른 것입니다.
- **중도 절단:** 목표 세대에서 멈추므로, 그보다 늦게 올 발견은 "도달 못 함"으로 셉니다. 늦은 단계를 비교할 때는 목표 세대를 넉넉히.
- **평균 세대는 단조롭지 않을 수 있습니다**(나이 많은 고세대 개체가 한꺼번에 죽으면 잠깐 내려감). 문명 단계 그림의 가로축이 잠깐 뒤로 가는 것은 그 때문입니다.
- 결과 폴더를 저장소 안(`results/…`, git 에서 무시됨)에 두면 실행기가 `.gdignore` 를 넣어 Godot 가 CSV 를 가져오지 않습니다.
- 씨앗 4개 정도의 사분위 범위는 거칩니다. 결론을 내기 전에 씨앗을 늘리세요.

## 예시 (`docs/analysis/example/`)

이 저장소에 함께 올린 작은 예시입니다(원본 실행 폴더는 올리지 않음, 보고서·표·그림만).

```bash
python3 tools/analyze.py run   --seeds 1-4 --generations 40 --preset fast_civ --out results/example-run --jobs 4
python3 tools/analyze.py sweep --param mutation.rate=0.02,0.05,0.1 --seeds 1-4 --generations 30 --preset fast_civ \
                               --out results/example-sweep --jobs 4
```

- [`run/report.md`](analysis/example/run/report.md) — `fast_civ` 씨앗 4개 × 40세대. 4개 모두 농사까지 도달, 농사 발견 세대 중앙값 6.1(씨앗별 21.7 · 2.0 · 10.2 · 1.95). 씨앗 1 의 21.7세대는 규칙 검사 S15(`docs/TEST-REPORT.md`)와 같은 값입니다(결정성).
- [`sweep/report.md`](analysis/example/sweep/report.md) — 돌연변이율 0.02·0.05·0.1 × 씨앗 4개 × 30세대. 0.1 에서 씨앗 하나가 멸종(약 1,000틱). 씨앗 4개라 칸 사이 차이는 아직 결론이 아닙니다.
- 읽을거리: `fast_civ` 의 채집 임계(배부른 줍기 시도 120회)는 씨앗 2·4 처럼 **약 0.2세대 만에** 넘기도 합니다. 이 예설정에서 채집 발견 세대는 진화보다 첫 개체들의 무작위 행동을 더 많이 반영한다는 뜻입니다.

![발견 세대 — 돌연변이율 격자](analysis/example/sweep/discovery.png)

## PyTorch 를 쓰지 않는 이유

분석에는 numpy·pandas·matplotlib 만 씁니다. 시뮬레이션에도 PyTorch 를 넣지 않았습니다.

1. **두뇌가 아주 작습니다.** 개체마다 12-8-8 앞먹임 신경망(곱셈 약 160회/판단). 250마리를 한 번에 계산해도 GPU·텐서 라이브러리의 시동 비용이 계산보다 큽니다.
2. **경사 하강을 쓰지 않습니다.** 학습은 신경진화(번식 때 유전체 교차 + 돌연변이, 살아남은 쪽이 남음)입니다. 자동 미분·최적화기가 필요 없습니다.
3. **결정성.** 같은 씨앗이면 비트 단위로 같은 역사(사칙연산·sqrt 만, `docs/DESIGN-v0.1.md` 7절). GPU·병렬 커널은 덧셈 순서가 바뀌어 결과가 기계마다 달라질 수 있습니다.
4. **오프라인 단일 실행 파일.** 앱은 Godot 하나로 설치 없이 돌아가야 합니다. 수백 MB 의 파이썬·PyTorch 런타임을 넣을 수 없습니다.

파이썬이 맞는 자리는 여기 — 여러 실행을 모아 통계·그림을 만드는 **오프라인 분석**입니다. 나중에 정말 큰 모델로 행동을 학습시켜 보고 싶다면(예: 진화한 두뇌를 모방 학습), 그것도 이 도구처럼 앱 바깥의 별도 실험으로 두는 것이 맞습니다.

## 검사

```bash
python3 -m unittest discover -s tools -p "test_*.py" -v
```

`tools/test_analyze.py`: 가짜 결과 폴더(묶음 2개 × 씨앗 2개)로 `summary.csv`(발견 세대·NaN·정렬)·`cells.csv`(중앙값·사분위·도달·멸종 비율)·`report.md`·그림, 같은 입력 → 같은 출력, matplotlib 없을 때, 묶음 9개(작은 그림 모드), 씨앗·격자 인자 해석, `run`·`sweep` 가 만드는 godot 명령줄과 이어 돌리기·실패 기록(가짜 subprocess). godot 이 있으면(`GODOT` 또는 PATH) 실제 실행기로 씨앗 2개 × 2세대를 돌려 같은 씨앗의 해시가 같은지도 봅니다. GitHub Actions(`build.yml` 의 마지막 단계)에서도 돌립니다.
