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
