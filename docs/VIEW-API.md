# 화면 구성 요소 계약 (v0.1, 3단계)

실험실 화면을 구성 요소로 나누고, 각 요소가 서로 기대하는 이름·시그니처·동작을 고정합니다. 각 요소는 이 문서와 [`SIM-API.md`](SIM-API.md)의 질의만 써서 시뮬레이션을 읽습니다.

## 공통 규칙

1. **화면은 시뮬레이션을 바꾸지 않습니다.** `SimWorld` 의 배열에 쓰거나, `step()` 이외의 진행 함수(`_act`, `_think` 등 밑줄 함수)를 부르거나, `sample()`(기간 카운터를 0 으로 되돌림)·`drain_events()`(사건을 소비함)를 부르는 것은 **LabMain 만** 합니다(`sample()` 은 4단계 기록기만). 화면 때문에 역사 해시가 바뀌면 안 됩니다(검사).
2. **수치는 `config/ui.json`** 에서 `UiConfig` 로 읽습니다(색·크기·속도·예산·카메라). 각 요소는 자기 절(`map`·`slime`·`camera`·`buildings`·`info`·`lab`·`speed`·`theme`)에만 키를 더합니다. 절차적 모양을 정하는 기하 상수(조각 함수의 계수 등)는 이름 붙은 `const` 로 코드에 두어도 됩니다.
3. **외부 모델·이미지·음원 파일 없음.** 메시는 코드로 만듭니다(이전 프로젝트 `little-monster-village` 의 `scripts/world/chars/demon_geo.gd` 의 `sculpt()`·`lathe()` 기법). 글꼴은 `assets/fonts/NanumGothic-*.ttf`(OFL, 프로젝트 기본 글꼴로 지정됨).
4. 렌더러는 **Compatibility(GL)**. 셰이더를 쓰면 Compatibility 에서 동작해야 합니다.
5. 화면 문자열은 한국어, 코드 주석도 한국어(기존 코드와 같은 밀도).
6. 검사: 각 요소는 `tests/view/<요소>_checks.gd` 를 하나 둡니다(아래 "검사 모듈"). `godot --headless --path . --script res://tests/run_view_tests.gd` 가 모두 모아 돌립니다. 헤드리스(더미 렌더러)에서 돌아가야 합니다 — 메시 배열·MultiMesh 데이터·노드 구조·계산은 검사할 수 있고, 픽셀은 못 봅니다(픽셀은 `tests/ui_driver.gd` 캡처).

## 좌표

- 칸 (x, y) 의 중심 = 월드 `Vector3((x + 0.5) * tile, 0, (y + 0.5) * tile)` (`tile = ui.map.tile_size`). 시뮬레이션의 북(방향 0, y 감소) = 월드 -Z, 동(1) = +X.
- 슬라임 모델의 정면 = -Z, 바닥 = y 0, 크기 1 일 때 반지름 `ui.slime.radius`. 개체 크기(`s_size`)만큼 균일 배율.

## SlimeGeo — `scripts/view/slime_geo.gd` (`class_name SlimeGeo`, RefCounted, static)

| 함수 | 반환 | 뜻 |
|---|---|---|
| `slime_mesh()` | ArrayMesh | 슬라임 한 마리(구 하나를 조각해 아래가 납작한 물방울형, 두 눈은 같은 메시의 정점 색). 몸 정점 색은 흰색 계열(인스턴스 색이 곱해져 계통 색이 됨), 눈은 검정·흰 반사점. 삼각형 ≤ `ui.slime.triangles_max`. 결과를 캐시 |
| `slime_material()` | Material | 정점 색 사용, MultiMesh 인스턴스 색이 곱해지는 재질 |
| `plant_mesh()` | ArrayMesh | 풀포기(바닥 y 0, 높이 약 1, 배율로 먹이량 표시) |
| `berry_mesh()` | ArrayMesh | 운반 중인 열매·바닥 먹이(지름 약 1, 배율로 씀) |
| `storehouse_mesh()` | ArrayMesh | 저장고(회전체 움집 + 지붕, 한 칸 크기) |
| `farm_mesh()` | ArrayMesh | 밭(이랑 줄무늬 판, 한 칸 크기, 높이 낮음) |
| `ring_mesh()` | ArrayMesh | 선택 표시 고리(바닥에 놓는 납작한 도넛, 반지름 약 1) |
| `triangle_count(mesh)` | int | 삼각형 수 |
| `shared_material()` | Material | 식물·건물 공용(정점 색 사용) |

## MapView — `scripts/view/map_view.gd` (`class_name MapView`, Node3D)

SubViewport 안에 하나씩 둡니다(4단계 비교 모드에서 두 개). 자기 카메라·빛·환경을 직접 만듭니다.

| 멤버 | 뜻 |
|---|---|
| `signal slime_clicked(id: int)` | 왼쪽 클릭(끌기 아님)으로 슬라임을 골랐을 때. 빈 곳이면 `-1` |
| `func bind(world: SimWorld) -> void` | 세계를 붙이고 지형·식물·건물·슬라임을 새로 만든다. 다른 세계로 다시 불러도 됨 |
| `func before_steps() -> void` | 이 프레임에 `step()` 을 부르기 **전에** 호출. 보간용으로 현재 위치(id → 칸)를 기억 |
| `func update_view(alpha: float) -> void` | 매 프레임 `step()` 뒤에 호출. `alpha`(0~1) = 다음 틱까지의 진행률(보간·통통 튐). 슬라임·식물·건물·빛(낮밤)·선택 표시 갱신. 지형 색은 `ui.map.terrain_refresh_ticks` 마다 |
| `func set_selected(id: int) -> void` | 선택 표시(-1 = 없음). 죽은 개체면 표시 없음 |
| `func pick_slime(screen_pos: Vector2) -> int` | 뷰포트 좌표의 광선을 땅(y 0)과 교차해 가장 가까운 살아 있는 슬라임 id(반경 안에 없으면 -1) |
| `func focus_on(id: int) -> void` | 카메라를 그 개체로 옮김 |
| `var follow_selected: bool` | 켜면 선택한 개체를 카메라가 따라감 |
| `func get_camera() -> Camera3D` | 카메라 |
| `func view_stats() -> Dictionary` | `{slimes, plants, stores, farms, triangles_estimate}` (성능 기록용) |
| 입력 | `_unhandled_input`: 왼쪽 끌기 = 이동, 휠 = 확대·축소, 오른쪽 끌기 = 회전, 왼쪽 클릭 = 고르기 |

## InfoPanel — `scripts/ui/info_panel.gd` (`class_name InfoPanel`, PanelContainer)

| 멤버 | 뜻 |
|---|---|
| `signal slime_requested(id: int)` | 부모·조부모·자식 항목을 눌렀을 때 |
| `signal follow_toggled(on: bool)` | "따라가기" 단추 |
| `func show_slime(world: SimWorld, id: int) -> void` | 개체 정보 표시(id, 살아 있음/죽음·원인, 세대, 나이/최대 나이, 에너지 막대, 운반, 현재 행동, 크기·감지·색 견본, 부모·조부모(2대), 자식 목록 `children_of(id, ui.info.children_max)`, 두뇌 그림) |
| `func clear() -> void` | "슬라임을 눌러 고르세요" 안내 |
| `func refresh() -> void` | 같은 개체의 바뀐 값 다시 표시(LabMain 이 `ui.info.refresh_frames` 마다 부름). 그사이 죽었으면 죽음 표시 |
| `func current_id() -> int` | 표시 중인 id(-1 없음) |

`BrainView` — `scripts/ui/brain_view.gd` (`class_name BrainView`, Control): `func set_genome(L: Dictionary, genome: PackedFloat32Array) -> void` 가중치 열지도(입력×은닉, 은닉×출력; 양수·음수 색은 `ui.info.heatmap_*`), 입력·행동 이름은 `SimBrain.INPUT_NAMES`·`ACTION_NAMES`.

## LabMain — `scripts/ui/lab_main.gd` (`class_name LabMain`, Control) + `scenes/lab.tscn`(주 장면)

| 멤버 | 뜻 |
|---|---|
| `var world: SimWorld` | 진행 중인 세계 |
| `var map_view: MapView`, `var info_panel: InfoPanel` | 구성 요소 |
| `var left_dock: VBoxContainer`, `var bottom_dock: HBoxContainer` | 4단계(파라미터 패널·그래프·연대기)가 들어갈 빈 자리 |
| `func new_experiment(preset: String, overrides: Dictionary, seed_value: int) -> String` | 새 세계(오류 문장, 성공 "") |
| `func open_snapshot(path: String) -> String` | 스냅숏 열기 |
| `func set_speed(mult: int) -> void`, `func set_paused(p: bool) -> void`, `func set_fast_forward(on: bool) -> void` | 속도 |
| `func select_slime(id: int) -> void` | 선택(지도 표시 + 정보 창) |
| `func actual_speed() -> float` | 최근 `ui.speed.actual_speed_window_s` 동안 실제 배속(1배 = `ticks_per_second_1x`) |
| `signal ticked(world: SimWorld)` | 이 프레임에 1틱 이상 진행했을 때(4단계 그래프가 씀) |
| `signal events(list: Array)` | `drain_events()` 결과(비어 있지 않을 때) |

동작: `_process` 에서 `map_view.before_steps()` → 누적 시간만큼 `world.step()`(프레임당 `ui.speed.sim_budget_ms` 넘지 않게, 빨리 감기면 `fast_forward_budget_ms` 를 다 씀) → `map_view.update_view(alpha)`. 위쪽 막대: ▶/‖, 1·2·4·8·16·32·64배, ⏩, 표시(틱·날·계절·평균 세대·개체 수·문명 단계·"목표 N배 / 실제 M배"). 사건은 위쪽 알림(`ui.lab.toast_seconds`). 키: 스페이스 = 멈춤, 1~7 = 속도, F = 따라가기, Esc = 선택 해제. 명령줄(`--` 뒤): `--seed=N`, `--preset=이름`, `--snapshot=경로`.

**구현 메모(3단계, LabMain 담당이 덧붙임)**

- 더한 멤버(4단계·검사·캡처용):

  | 멤버 | 뜻 |
  |---|---|
  | `func advance_frame(delta: float) -> int` | 한 프레임 진행(아래 순서). `_process` 가 부르고, 검사·캡처는 `set_process(false)` 뒤 직접 불러 프레임을 결정적으로 몬다. 이 프레임에 돈 틱 수를 돌려줌 |
  | `func apply_args(args: PackedStringArray) -> String` | 명령줄 인자로 실험 열기(`_ready` 가 `OS.get_cmdline_user_args()` 로 부름). 잘못된 값은 위험 색 알림 + 기본값, 오류 문장들(줄바꿈)을 돌려줌. 모르는 인자는 무시 |
  | `signal world_changed(world: SimWorld)` | `new_experiment`·`open_snapshot` 로 세계가 바뀌었을 때(4단계 그래프·연대기가 지난 기록을 비움) |
  | `func show_toast(text: String, kind := "info", tick := -1) -> void` | 위쪽 가운데 알림. `kind` = 사건 종류 또는 `info`·`warn`·`error`(4단계의 "저장했습니다" 등도 이것으로) |
  | `func visible_toasts() -> Array[Dictionary]` | 보이는 알림 `{kind, text, left}` |
  | `is_paused()`·`is_fast_forward()`·`target_speed()`·`selected_id()`·`speed_text()` | 지금 상태 |
  | `var last_sim_ms: float`, `var last_budget_hit: bool` | 마지막 프레임의 시뮬레이션 시간과 예산을 다 썼는지(성능 기록용) |

- 프레임 순서(`advance_frame`): 알림 시간 줄이기 → `map_view.before_steps()`(**매 프레임**, 멈춰도·틱이 없어도) → 멈춤이 아니면 진행 → `map_view.update_view(alpha)` → 실제 배속 창에 기록 → 1틱 이상이면 `ticked` → `drain_events()` 가 비어 있지 않으면 `events` + 알림 → `ui.info.refresh_frames` 마다 `info_panel.refresh()` → 위쪽 막대 표시.
  - 보통: `누적 += delta × ticks_per_second_1x × 배속`, 누적 ≥ 1 인 동안 `step()`. 2틱째부터 `sim_budget_ms` 를 넘었으면 멈추고 **밀린 몫을 버림**(누적의 소수 부분만 남김 — 밀린 틱이 쌓여 점점 느려지지 않게). `alpha` = 누적의 소수 부분(0~1).
  - 빨리 감기: `fast_forward_budget_ms` 를 다 쓸 때까지(적어도 1틱) `step()`, 누적은 0, `alpha = 1`.
  - `delta` 는 `ui.speed.max_frame_delta_s` 로 자름(창을 끌거나 멈칫한 프레임이 한꺼번에 몰아 돌지 않게).
  - 사건은 진행 여부와 관계없이 매 프레임 비움(검사·캡처가 `world.step_n` 으로 직접 진행한 사건도 다음 프레임에 알림).
- 실제 배속 = 최근 `actual_speed_window_s` 동안의 (틱 합 ÷ 프레임 시간 합) ÷ `ticks_per_second_1x`. 프레임 시간은 `advance_frame` 에 들어온 `delta`(검사에서 결정적). 창이 `WARMUP_FRACTION`(1/4) 차기 전에는 "실제 —", 표시는 `speed.label_refresh_s` 마다 갱신, 실제가 목표 × `speed.behind_ratio` 보다 낮으면 경고 색.
- 배치(코드로 만듦, 노드 이름 고정): `Background`(ColorRect) · `Column`(VBox) = `TopBar` / `Middle`(HBox) = `LeftWrap`(PanelContainer `DockPanel`, 폭 `left_panel_width`) ⊃ `LeftDock` | `MapArea`(Control, 늘어남) ⊃ `MapContainer`(SubViewportContainer `stretch`) ⊃ `MapViewport`(`own_world_3d`, `msaa_3d = lab.map_msaa`) ⊃ `MapView` + 지도 위 표지(`MapTitle` 실험 이름·멈춤, `MapHint` 조작 도움말, `Toasts`) | `InfoPanel`(폭 `right_panel_width`) / `BottomWrap`(높이 `bottom_panel_height`) ⊃ `BottomDock`. 두 자리는 자식이 없으면 감싸개째 숨고, 자식을 넣으면(지연 호출로) 보인다. 표지·알림은 마우스를 통과시킨다.
- 위쪽 막대: 재생/멈춤·빨리 감기는 **코드로 그린 아이콘**(`UiTheme.icon`, ⏩ 가 나눔고딕에 없음), 멈추면 ▶ 가 경고 색. 속도 단추는 `ButtonGroup`(빨리 감기 중에는 모두 꺼짐, 속도를 고르면 빨리 감기 꺼짐). 상태: 틱 · 날(`tick / day_ticks + 1`) · 계절(봄·여름·가을·겨울 / 계절 없음) · 낮/밤(`light ≥ lab.day_light_threshold`) │ 평균 세대 · 개체(0 이면 "멸종", 위험 색) · 문명(`SimWorld.STAGE_NAMES`) …… "목표 N배 / 실제 M배"·"빨리 감기 / 실제 M배"·"멈춤 · 목표 N배". 가장 긴 표시(틱 7자리 등)에서도 최소 창 폭 1280 안(검사).
- 알림: 사건 문장 그대로 + 흐린 "틱 N". 왼쪽 띠 = 종류 색, 발견(`★ 새 발견` 머리)은 강조 색, 멸종·오류는 위험 색, 밭 잃음·경고는 경고 색 테두리. 최대 `lab.toast_max` 개(오래된 것부터 지움), `toast_seconds` 뒤 사라지며 마지막 `toast_fade_seconds` 동안 흐려짐.
- 선택: `map_view.slime_clicked(id)` → `select_slime(id)`(-1·없는 id = 해제; 죽은 개체 id 는 기록으로 표시), `info_panel.slime_requested(id)` → `select_slime(id)` + `map_view.focus_on(id)`, `info_panel.follow_toggled(on)` → `map_view.follow_selected = on`.
- 단축키는 `_input` 에서 받아 처리하면 소비한다(초점 있는 단추가 스페이스를 먹지 않게). **`LineEdit`·`TextEdit` 에 초점이 있거나 Ctrl·Alt·Meta 가 눌렸으면 무시**. 1~7 은 숫자판 키도. F 는 `map_view.follow_selected` 를 뒤집고 알림(정보 창의 따라가기 단추 모양은 따라 바뀌지 않음 — 계약에 InfoPanel 쪽 설정 함수가 없음).
- 날 표시에 하루 틱 수가 필요해 `world.cfg.time.day_ticks` 를 읽기만 한다(SIM-API 목록 밖 — 보고서에 기록).
- 창 최소 크기 `lab.min_width × min_height`(헤드리스에서는 건너뜀). 창 제목 = "프로젝트 이름 — 예설정 · 씨앗 N".

### UiTheme — `scripts/ui/ui_theme.gd` (`class_name UiTheme`, RefCounted, static)

| 멤버 | 뜻 |
|---|---|
| `build() -> Theme` | 공용 테마(캐시). LabMain 뿌리에 붙어 모든 자식 Control 이 이어받음. `reset()` 은 다음 `build()` 가 다시 만들게 |
| `regular_font()`, `bold_font()` | 나눔고딕 보통·굵게 |
| `color(key) -> Color` | `ui.theme.<key>` |
| `box(bg, border, border_w, radius, pad_h, pad_v) -> StyleBoxFlat` | 같은 모양의 상자(음수 = 테마 기본값) |
| `has_glyphs(text)`, `glyph_or(glyph, fallback)` | 글자가 기본 글꼴에 있는지 / 없으면 대신 글자 |
| `icon(shape, px) -> Texture2D` | 흰 아이콘(`ICON_PLAY`·`ICON_PAUSE`·`ICON_FAST`), 단추의 `icon_*_color` 가 색을 입힘 |

형 변형(`theme_type_variation`): `TitleLabel`(굵게·`font_size_title`) · `DimLabel`(흐림·`font_size_small`) · `ValueLabel`(굵게) · `TopBar` · `DockPanel` · `CardPanel`(패널 안 어두운 묶음) · `OverlayPanel`(지도 위 반투명) · `ToastPanel` · `AccentButton`(주요 동작) · `FlatButton`(목록 항목). 기본 형: Label·Button(보통·올림·눌림=켜짐·못 씀·초점)·OptionButton·CheckBox·ProgressBar(배경·채움=강조 색)·LineEdit·HSlider·스크롤 막대·ItemList·TabContainer·말풍선·차림표·구분선. 수치는 `theme`(색·`corner_radius`·`border_width`·`panel_padding`·`button_padding_*`·`separation`)과 `lab`(`font_size*`).

## 검사 모듈 — `tests/view/<요소>_checks.gd`

```gdscript
extends RefCounted
## <요소> 검사. tests/run_view_tests.gd 가 불러 run(t) 을 부른다.

func run(t) -> void:
	# t.check(조건: bool, 설명: String)
	# t.root: Window(장면 트리 뿌리), t.make_world(sets: Dictionary, seed: int) -> SimWorld
	# 노드가 프레임을 거쳐야 하면: await t.frames(n)
	t.check(true, "예시")
```

`run` 은 `await` 를 써도 됩니다(실행기가 기다림).

## 캡처 — `tests/ui_driver.gd` (LabMain 담당)

`xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd -- --out=폴더` 로 실험실 장면을 띄워 시나리오(전경·가까이·개체 선택+정보 창·밤·농사 단계)를 진행·캡처하고, 동작(클릭 → 정보 창 id, 속도 바꾸기, 화면 진행 중 역사 해시가 헤드리스와 같음)을 확인해 `RESULT: N passed, M failed (ui)` 를 출력합니다.

**구현 메모(3단계)**: `--out` 기본값 `res://docs/screenshots/v0.1`, `--copy=폴더` 를 주면 그림을 그곳에도 복사. 프레임은 `advance_frame(1/60)` 으로 몬다(④만 실제 `_process`).
① `lab-01-overview` 기본·씨앗 1 을 8배로 600프레임(480틱) → 해시 비교, 지도 클릭(실제 MapView 면 `pick_slime` 이 찾은 개체를 실제 마우스 입력으로, 뼈대면 `slime_clicked` 신호로) → 정보 창 id, 재생·속도·빨리 감기 단추 클릭, 스페이스. ② `lab-02-farm-selected` fast_civ·씨앗 1 을 농사 단계 + 밭 3칸까지(약 1,670틱) → 자식이 가장 많은 개체 선택·`focus_on` → 쌓인 사건 알림. ③ `lab-03-night` 밤까지 진행 후 멈춘 모습. ④ `lab-04-speed64` 64배 단추 클릭 → 실제 시간 150프레임 → "목표 64배 / 실제 M배" 와 해시 비교. 600KB 넘으면 JPG. 그림 폴더 `docs/screenshots/` 에는 `.gdignore`(가져오기 제외).
