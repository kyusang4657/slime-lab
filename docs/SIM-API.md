# 시뮬레이션 API (v0.1)

화면(`scripts/view/`, `scripts/ui/`)은 시뮬레이션을 **이 목록에 있는 것만** 써서 읽고 진행시킵니다. 같은 이름·뜻을 갖는 C#/GDExtension 구현으로 바꿔 끼울 수 있도록 고정해 둔 경계입니다. 목록에 없는 필드(밑줄로 시작하는 것, 장부 변수 등)는 화면에서 쓰지 않습니다.

## 만들기·진행

| 호출 | 뜻 |
|---|---|
| `SimConfig.build(preset: String, overrides: Dictionary) -> {config, error}` | 실험 설정 만들기(기본값 + 예설정 + 덮어쓰기). `overrides` 키는 `"mutation.rate"` 처럼 점으로 이은 이름 |
| `SimConfig.preset_names()`, `SimConfig.presets()` | 예설정 목록(`label` 은 화면 이름) |
| `SimWorld.new().setup(config, seed) -> String` | 새 세계. 성공이면 `""`, 아니면 오류 문장 |
| `world.step()` / `world.step_n(n)` | 1틱 / n틱 진행 |
| `SimSnapshot.save_file(world, path) -> String` | 저장(성공 `""`) |
| `SimSnapshot.load_file(path) -> {world, status, error}` | 불러오기(`status`: loaded·backup·failed) |
| `SimSnapshot.to_text(world) -> String` · `SimSnapshot.from_text(text) -> {world, error}` | 스냅숏 글(웹 내려받기)과 그 글에서 만든 세계 **사본**(화면이 내보낼 끝 줄을 사본의 `sample()` 로 — 진행 중 세계는 그대로) |
| `SimRecorder.new()`, `rec.record(world)`, `rec.write_all(dir, world, extra, with_lineage)` | 시계열 기록과 결과 폴더 쓰기(헤드리스와 같은 형식) |

## 읽기 전용 질의

| 이름 | 종류 | 뜻 |
|---|---|---|
| `w`, `h` | int | 지도 크기(칸) |
| `tick`, `seed_value` | int | 현재 틱, 씨앗 |
| `light`, `season`, `season_growth` | float, int, float | 빛 0~1, 계절 0~3(-1 = 계절 없음), 계절 성장 배수. 틱 사이(`setup`·`step()` 뒤·스냅숏을 연 뒤)에는 언제나 **지금 `tick`** 의 값(날 = `tick / cfg.time.day_ticks + 1` 과 같은 틱) |
| `tiles[c]` | PackedByteArray | 칸 종류 `SimGrid.TILE_*`(풀밭·물·바위·밭), `c = y * w + x` |
| `fert[c]`, `food[c]`, `food_cap[c]`, `dropped[c]` | PackedFloat64Array | 비옥도, 식물 먹이, 먹이 상한, 바닥 먹이 |
| `stage`, `discovery_tick[stage]` | int, Array[int] | 문명 단계 `SimWorld.STAGE_*`, 단계별 발견 틱(-1 = 아직) |
| `store_tiles[k]`, `store_food[k]` | 배열 | 저장고 위치(칸 번호)와 저장량 |
| `farms` | PackedInt32Array | 밭 칸 번호 |
| `population()` | int | 살아 있는 개체 수 |
| `s_id[i]`, `s_x[i]`, `s_y[i]`, `s_head[i]` | PackedInt32Array | i 번째 개체(배열 순서 = id 오름차순)의 id·위치·방향(0 북 1 동 2 남 3 서) |
| `s_energy[i]`, `s_emax[i]`, `s_carry[i]`, `s_size[i]` | PackedFloat64Array | 에너지·최대 에너지·운반량·크기 |
| `s_last_action[i]` | PackedInt32Array | 마지막 행동 `SimBrain.ACT_*` |
| `lin_hue[id]` | PackedFloat32Array | 색(계통 표지) — 죽은 개체도 id 로 바로 찾음 |
| `slime_info(id) -> Dictionary` | | 개체 정보(부모·세대·출생·사망·원인·자식 수·특성, 살아 있으면 위치·에너지·행동·유전체) |
| `children_of(id, limit) -> PackedInt32Array` | | 자식 id(태어난 순서, 최대 limit 개). 계통 전체를 훑으므로 클릭 때만 |
| `index_of_id(id) -> int` | | 살아 있으면 배열 위치, 아니면 -1 |
| `mean_generation()`, `mean_of(arr)`, `sum_of(arr)`, `mean_sense()`, `mean_age()` | float | 통계 |
| `sample() -> Dictionary` | | 시계열 한 줄(`SimRecorder.TIMESERIES_COLUMNS` 키). **호출하면 기간 출생·사망 수를 0 으로** 되돌리므로 기록기만 부른다 |
| `chronicle` | Array[Dictionary] | 연대기 `{tick, kind, actor, text, mean_gen, …}` |
| `drain_events() -> Array` | | 지난 호출 이후 새 사건(알림·소리용). 사건 사전은 `chronicle` 항목의 **사본**이라 받는 쪽이 고쳐 써도 연대기·기록이 바뀌지 않음 |
| `history_hash` | String | 역사 해시(같은 씨앗·설정이면 같음) |
| `is_extinct()`, `extinct_tick`, `peak_population` | | 멸종·최고 인구 |
| `cfg` | Dictionary | 이 세계의 실험 설정(`SimConfig.build` 결과). **읽기 전용 — 화면은 절대 쓰지 않음**(시뮬레이션이 매 틱 읽는 살아 있는 사전). 화면이 읽는 키: `cfg.time.day_ticks`(날 표시, LabMain), `cfg.brain.weight_clamp`(두뇌 열지도 색 상한, InfoPanel), `cfg.hash.every`(검사만), **모든 잎 키**(ParamPanel — `cfg` 를 깊은 사본으로 떠서 다음 실험 조건과 견주고 "지금 실험" 요약에만 씀). ParamPanel 은 스냅숏 저장 파일 이름에 `tick` 도 읽음 |

사건 `kind`: `discovery`(+`stage`), `store_built`(+`tile`), `first_farm`, `farm_lost`, `milestone`, `extinction`.

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
| `rec.rows`(기록기 `SimRecorder` 의 멤버) | 지금까지 기록한 줄(`SimRecorder.TIMESERIES_COLUMNS` 키 사전의 Array). 기록기를 가진 Experiment 밖에서는 **읽기만**(Experiment `rows()` 가 그대로 내줌 — 그래프가 읽음) |

`tools/test_repo_rules.py` 가 `scripts/view`·`scripts/ui` 에서 시뮬레이션에 닿는 이름이 모두 이 문서에 있는지 검사합니다: `world.<이름>`·`_world.<이름>`, 사슬(`lab.world.<이름>`·`experiments[k].world.<이름>`), 세계를 가리키는 변수(`SimWorld` 로 적은 변수·인자, `var w := x.world`)의 `w.<이름>`, 기록기(`SimRecorder`)의 멤버, `Sim*.<이름>` 정적 이름(주석·문자열은 뺌). 같은 검사가 화면이 세계를 바꾸지 않는지도 봅니다(세계 멤버에 대입·`append` 같은 고치는 호출·`step`/`setup`/`sample`/`drain_events` 호출 — 진행·기록(`sample`)은 Experiment, `drain_events` 는 LabMain 만).

## 두뇌·유전체

| 이름 | 뜻 |
|---|---|
| `world.L` = `SimBrain.layout(config)` | `{n_in, n_hid, n_out, n_mem, w2_offset, trait_offset, genes}` |
| `SimBrain.forward(L, genome, base, inputs, sharpness) -> {hidden, out, probs, action}` | 정보 창의 두뇌 그림용 순전파 |
| `SimBrain.INPUT_NAMES`, `SimBrain.ACTION_NAMES` | 화면 이름 |
| `SimWorld.STAGE_NAMES`, `SimWorld.CAUSE_NAMES` | 화면 이름 |
