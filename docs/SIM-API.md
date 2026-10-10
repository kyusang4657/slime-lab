# 시뮬레이션 API (v0.1)

화면(`scripts/view/`, `scripts/ui/`)은 시뮬레이션을 **이 목록에 있는 것만** 써서 읽고 진행시킵니다. 같은 이름·뜻을 갖는 C#/GDExtension 구현으로 바꿔 끼울 수 있도록 고정해 둔 경계입니다. 목록에 없는 필드(밑줄로 시작하는 것, 장부 변수 등)는 화면에서 쓰지 않습니다.

## 만들기·진행

| 호출 | 뜻 |
|---|---|
| `SimConfig.build(preset: String, overrides: Dictionary) -> {config, error}` | 실험 설정 만들기(기본값 + 예설정 + 덮어쓰기). `overrides` 키는 `"mutation.rate"` 처럼 점으로 이은 **잎** 이름(절 `"body"` 에 사전을 넣으면 거부). `SimConfig.validate` 가 모든 키를 검사: 구조(빠진 키·모르는 키·종류), 범위(`config/sim-labels.json` 의 "(검사)" 범위 = `SimConfig.RULES`·`ARRAY_RULES`·`CHOICES`), 정수 키(sim-defaults.json 에 소수점 없이 적힌 키)의 소수, 관계(크기·감지 초기값, `time.twilight_ticks` ≤ 하루 × 낮 비율 ÷ 2, `life.max_age_jitter` < `life.max_age`). 오류 문장은 `설정 키 = 값: 범위 …` 꼴(정수 키는 정수로). 예설정 파일을 읽지 못하면 `예설정 파일을 읽지 못했습니다: <경로>` |
| `SimConfig.preset_names()`, `SimConfig.presets()` | 예설정 목록(`label` 은 화면 이름) |
| `SimWorld.new().setup(config, seed) -> String` | 새 세계. 성공이면 `""`, 아니면 오류 문장 |
| `world.step()` / `world.step_n(n)` | 1틱 / n틱 진행 |
| `SimSnapshot.save_file(world, path) -> String` | 저장(성공 `""`, 실패면 파일 이름을 담은 문장 — 같은 문장을 `push_error` 로도 남김). 임시 파일 → 다시 읽어 검증 → 교체. 쓰기·검증에 실패한 임시 파일은 지움 |
| `SimSnapshot.load_file(path) -> {world, status, error}` | 불러오기(`status`: loaded·backup·failed). 하위 키·종류·길이·범위(칸 번호·16진 실수·유한한 수)가 틀린 본 파일도 스크립트 오류 없이 실패로 보고 `.bak` 으로 복구, 본 파일은 `.broken` 으로 보관. 설정에 나중에 더한 키(`SimSnapshot.CONFIG_KEYS_ADDED`)가 없는 옛 스냅숏은 그 키를 기본값으로 채움, 첫 밭 틱(`civ.first_farm_tick`)이 없는 옛 스냅숏은 연대기의 `first_farm` 사건에서 다시 만듦 |
| `SimSnapshot.to_text(world) -> String` · `SimSnapshot.from_text(text) -> {world, error}` | 스냅숏 글(웹 내려받기)과 그 글에서 만든 세계 **사본**(화면이 내보낼 끝 줄을 사본의 `sample()` 로 — 진행 중 세계는 그대로). 스냅숏은 세계의 모든 상태를 담음: 연 세계는 틱 안에서만 쓰는 계산 자리와 `drain_events()` 의 알림 대기열(연 뒤 새 사건부터)을 빼면 모든 변수가 같고, 이어 돌리면 끊김 없이 돌린 세계와 같은 역사(밭 단계 포함 — 검사 test_snapshot_roundtrip) |
| `SimRecorder.new()`, `rec.record(world)`, `rec.write_all(dir, world, extra, with_lineage) -> PackedStringArray` | 시계열 기록과 결과 폴더 쓰기(헤드리스와 같은 형식, 실패한 파일 이름 목록). CSV 는 BOM 붙은 UTF-8(BOM 은 파일에만 — `timeseries_csv()` 글에는 없음). `summary.json` 은 CSV 를 다 쓴 뒤 마지막(임시 이름 → 바꾸기): 쓰기 전에 앞선 것을 지우고 CSV 하나라도 못 쓰면 쓰지 않음(목록에 `summary.json(…)`). 쓴 길이를 다시 확인해 디스크가 차서 잘린 파일도 실패로 셈 |

## 읽기 전용 질의

| 이름 | 종류 | 뜻 |
|---|---|---|
| `w`, `h` | int | 지도 크기(칸) |
| `tick`, `seed_value` | int | 현재 틱(= 진행한 틱 수, `step()` 끝에서 1 늚), 씨앗. 진행 중에 생긴 기록(계통의 출생·사망 틱, 발견 틱, 사건 대부분)은 진행 중인 틱 번호 = 진행 전 `tick` 으로 적힘 — 파일마다의 틱 기준은 [`DESIGN-v0.1.md`](DESIGN-v0.1.md) 8.4 |
| `light`, `season`, `season_growth` | float, int, float | 빛 0~1, 계절 0~3(-1 = 계절 없음), 계절 성장 배수. 틱 사이(`setup`·`step()` 뒤·스냅숏을 연 뒤)에는 언제나 **지금 `tick`** 의 값(날 = `tick / cfg.time.day_ticks + 1` 과 같은 틱) |
| `tiles[c]` | PackedByteArray | 칸 종류 `SimGrid.TILE_*`(풀밭·물·바위·밭), `c = y * w + x` |
| `fert[c]`, `food[c]`, `food_cap[c]`, `dropped[c]` | PackedFloat64Array | 비옥도, 식물 먹이, 먹이 상한, 바닥 먹이 |
| `stage`, `discovery_tick[stage]` | int, Array[int] | 문명 단계 `SimWorld.STAGE_*`, 단계별 발견 틱(발견한 틱 번호, -1 = 아직) |
| `store_tiles[k]`, `store_food[k]` | 배열 | 저장고 위치(칸 번호)와 저장량 |
| `farms` | PackedInt32Array | 밭 칸 번호 |
| `population()` | int | 살아 있는 개체 수 |
| `s_id[i]`, `s_x[i]`, `s_y[i]`, `s_head[i]` | PackedInt32Array | i 번째 개체(배열 순서 = id 오름차순)의 id·위치·방향(0 북 1 동 2 남 3 서) |
| `s_energy[i]`, `s_emax[i]`, `s_carry[i]`, `s_size[i]` | PackedFloat64Array | 에너지·최대 에너지·운반량·크기 |
| `s_last_action[i]` | PackedInt32Array | 마지막 행동 `SimBrain.ACT_*` |
| `lin_hue[id]` | PackedFloat32Array | 색(계통 표지) — 죽은 개체도 id 로 바로 찾음 |
| `slime_info(id) -> Dictionary` | | 개체 정보(부모·세대·출생·사망·원인·자식 수·특성, 살아 있으면 위치·에너지·행동·유전체). 특성의 sense 는 유전자 실수(실제 감지 반경은 반올림한 칸 수), 혼자 분열한 자식은 parent_b = -1 |
| `children_of(id, limit) -> PackedInt32Array` | | 자식 id(태어난 순서, 최대 limit 개). 계통 전체를 훑으므로 클릭 때만 |
| `index_of_id(id) -> int` | | 살아 있으면 배열 위치, 아니면 -1 |
| `mean_generation()`, `mean_of(arr)`, `sum_of(arr)`, `mean_sense()`, `mean_age()` | float | 통계(`mean_sense()` 는 반올림한 감지 반경의 평균, 개체가 없으면 모두 0) |
| `sample() -> Dictionary` | | 시계열 한 줄(`SimRecorder.TIMESERIES_COLUMNS` 키 — 열마다의 뜻·구간 값과 누적 값은 DESIGN 8.4). **호출하면 기간 출생·사망 수를 0 으로** 되돌리므로 기록기만 부른다 |
| `chronicle` | Array[Dictionary] | 연대기 `{tick, kind, actor, text, mean_gen, …}` |
| `drain_events() -> Array` | | 지난 호출 이후 새 사건(알림·소리용). 사건 사전은 `chronicle` 항목의 **사본**이라 받는 쪽이 고쳐 써도 연대기·기록이 바뀌지 않음 |
| `history_hash` | String | 역사 해시(같은 씨앗·설정이면 같음). setup 끝과 `cfg.hash.every` 틱마다(검사점)만 상태를 섞으므로 검사점 사이 틱의 차이는 담지 않음 — 두 세계가 지금 같은 상태인지는 `SimSnapshot.to_text` 글 전체로 견줌 |
| `is_extinct()`, `extinct_tick`, `peak_population` | | 멸종(-1 = 아직, 값은 진행한 뒤 틱 = 마지막 개체가 죽은 틱 번호 + 1)·최고 인구. 처음부터 개체가 없는 세계(초기 개체 0, 지나갈 칸 없음)는 `setup` 이 `extinct_tick = 0` 과 멸종 사건을 남김 — 실행기는 틱 0 에서 끝나고 실험실도 같은 기록 |
| `cfg` | Dictionary | 이 세계의 실험 설정(`SimConfig.build` 결과). **읽기 전용 — 화면은 절대 쓰지 않음**(시뮬레이션이 매 틱 읽는 살아 있는 사전). 화면이 읽는 키: `cfg.time.day_ticks`(날 표시, LabMain), `cfg.time.night_light_threshold`(낮/밤 표시 — `light` 가 이 값보다 작으면 밤, 시뮬레이션의 밤 감지와 같은 문턱, LabMain), `cfg.brain.weight_clamp`(두뇌 열지도 색 상한, InfoPanel), `cfg.hash.every`(검사만), **모든 잎 키**(ParamPanel — `cfg` 를 깊은 사본으로 떠서 다음 실험 조건과 견주고 "지금 실험" 요약에만 씀). ParamPanel 은 스냅숏 저장 파일 이름에 `tick` 도 읽음 |

사건 `kind`: `discovery`(+`stage`), `store_built`(+`tile`), `first_farm`(세계에서 한 번 — 밭을 모두 잃고 다시 심어도 다시 나오지 않음), `farm_lost`, `milestone`, `extinction`(처음부터 개체가 없으면 틱 0). 사건의 `tick` 은 `discovery`·`store_built`·`first_farm`·`farm_lost` 가 진행 중인 틱 번호, `milestone`·`extinction` 이 진행한 뒤 틱이다. `mean_gen` = 사건 때의 평균 세대(0.01 단위) — `extinction` 은 개체가 모두 사라진 뒤라 마지막 개체군(마지막 틱에 죽은 개체)의 평균 세대. 사건마다 어느 상태의 평균인지는 DESIGN 8.4 "틱 기준".

## 상수·정적 도움 함수

다른 구현(C#/GDExtension)도 같은 이름·값으로 내놓아야 하는 것. 화면은 아래만 씁니다.

| 이름 | 뜻 |
|---|---|
| `SimGrid.TILE_GRASS`·`TILE_WATER`·`TILE_ROCK`·`TILE_FARM` | 칸 종류(`tiles[c]` 값) |
| `SimGrid.DX`, `SimGrid.DY`, `SimGrid.DIR_COUNT` | 방향(0 북 1 동 2 남 3 서)의 x·y 변화, 방향 수(4) |
| `SimGrid.passable(tile) -> bool` | 슬라임이 설 수 있는 칸(풀밭·밭) |
| `SimBrain.ACT_*`(`ACT_EAT`·`ACT_GATHER`·`ACT_PLANT` 등) | 행동 번호(`s_last_action` 값) |
| `SimBrain.BASE_INPUTS`, `SimBrain.BASE_OUTPUTS` | 기억 뉴런을 빼 기본 입력(12)·출력(8) 수 |
| `SimWorld.STAGE_*`, `SimWorld.NO_PARENT`, `SimWorld.SEASON_COUNT` | 문명 단계 번호, 부모 없음(-1), 계절 수 |
| `SimConfig.defaults()`, `SimConfig.get_value(cfg, dotted)`, `SimConfig.deep_equal(a, b)`, `SimConfig.load_json(path)`, `SimConfig.DEFAULTS_PATH` | 기본값의 깊은 사본, 점 이름(`"mutation.rate"`)으로 값 읽기(없으면 null), 깊은 비교, JSON 파일 읽기(없거나 깨지면 null), 기본값 파일 경로(ParamPanel 이 정수 키를 가리려 글자로 읽음). 모두 읽기만 |
| `SimConfig.TICK_MAX` | 틱의 상한(1e9). 틱 단위 키(`life.max_age`·`repro.cooldown`·`run.max_ticks` 등)의 검사 상한이고, 틱 값은 32비트 정수 배열에 담기므로 실행기 `--max-ticks`·실험실 진행도 이 틱에서 멈춰야 함 |
| `rec.rows`(기록기 `SimRecorder` 의 멤버) | 지금까지 기록한 줄(`SimRecorder.TIMESERIES_COLUMNS` 키 사전의 Array). 기록기를 가진 Experiment 밖에서는 **읽기만**(Experiment `rows()` 가 그대로 내줌 — 그래프가 읽음) |

`tools/test_repo_rules.py` 가 `scripts/view`·`scripts/ui` 에서 시뮬레이션에 닿는 이름이 모두 이 문서에 있는지 검사합니다: `world.<이름>`·`_world.<이름>`, 사슬(`lab.world.<이름>`·`experiments[k].world.<이름>`), 세계를 가리키는 변수(`SimWorld` 로 적은 변수·인자, `var w := x.world`)의 `w.<이름>`, 기록기(`SimRecorder`)의 멤버, `Sim*.<이름>` 정적 이름(주석·문자열은 뺌). 같은 검사가 화면이 세계를 바꾸지 않는지도 봅니다(세계 멤버에 대입·`append` 같은 고치는 호출·`step`/`setup`/`sample`/`drain_events` 호출 — 진행·기록(`sample`)은 Experiment, `drain_events` 는 LabMain 만).

## 두뇌·유전체

| 이름 | 뜻 |
|---|---|
| `world.L` = `SimBrain.layout(config)` | `{n_in, n_hid, n_out, n_mem, w2_offset, trait_offset, genes}` |
| `SimBrain.forward(L, genome, base, inputs, sharpness) -> {hidden, out, probs, action}` | 정보 창의 두뇌 그림용 순전파 |
| `SimBrain.INPUT_NAMES`, `SimBrain.ACTION_NAMES` | 화면 이름(행동 1·2 "왼쪽 돌기"·"오른쪽 돌기" 는 제자리에서 방향만 바꿈 — 칸을 옮기는 것은 0 "앞으로" 뿐) |
| `SimWorld.STAGE_NAMES`, `SimWorld.CAUSE_NAMES` | 화면 이름. 번호가 첨자: 단계 0 없음·1 채집·2 저장·3 농사, 사망 원인 0 살아 있음·1 굶주림·2 노화(lineage.csv 의 death_cause 와 같은 번호 — DESIGN 8.4) |
