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

**공통(구현에서 정함):** 모든 메시는 바닥 y 0, 정면 -Z, 정점 색(`ARRAY_COLOR`)을 쓰며 표면 재질이 이미 붙어 있습니다(슬라임 = `slime_material()`, 나머지 = `shared_material()`, `material_override` 로 바꿔도 됨). MultiMesh 인스턴스 색은 정점 색에 **곱해지므로** 풀포기·열매·건물은 인스턴스 색 흰색 = 설정 색 그대로(어둡게·옅게 하려면 회색), 슬라임은 인스턴스 색 = 계통 색. 고리만 흰색이라 `material_override`(예: `ui.slime.selected_ring_color` 비조명)나 인스턴스 색으로 칠합니다.

| 메시 | 크기(배율 1) | 삼각형(예산 키) |
|---|---|---|
| 슬라임 | 가장 넓은 가로 반지름 = `ui.slime.radius`(0.3), 높이 약 0.42(가로/높이 ≈ 1.4). 머리 꼭대기 = `slime_mesh().get_aabb().end.y`(운반 열매를 얹는 높이) | 398 (`ui.slime.triangles_max`) |
| 풀포기 | 높이 1, 가로 약 0.9 | 112 (`ui.buildings.plant_triangles_max`) |
| 열매 | 지름 약 0.95, 높이 약 0.88(잎 포함) | 80 (`berry_triangles_max`) |
| 저장고 | 0.94 × 높이 1.1 × 0.94, 문은 -Z | 312 (`store_triangles_max`) |
| 밭 | 0.96 × 0.96, 높이 0.18(싹 끝) | 148 (`farm_triangles_max`) |
| 고리 | 바깥 반지름 1, 안쪽 0.8, 높이 0.06 | 288 (`ring_triangles_max`) |

- **슬라임 짜임:** 구 하나를 `ui.slime.segments × rings`(16 × 10) 위도·경도 격자로 조각합니다(아래가 납작한 물방울, 정수리에 작은 꼭지). 두 눈·입 자리의 격자 칸은 비워 두고, 같은 조각 겉면 위에 윤곽을 따라가는 고리 짜임으로 메웁니다 — 윤곽에 정점을 두 벌(몸 색·눈 색) 두어 400 삼각형 안에서도 눈 테두리·흰 반사점·"ᴗ" 입이 또렷합니다. 겉면은 틈 없이 닫혀 있습니다(검사: 모서리마다 삼각형 둘, 오일러 지표 2). 눈을 감싸는 위도·경도에는 격자선이 핀으로 박힙니다(`ProcGeo.spread(..., pins)`).
- **ui.json 키:** `slime` 절 — `segments`, `rings`, `body_color`·`body_bottom`(몸 정점 색, 바닥 둘레가 조금 어두움), `eye_color`·`eye_lower`(눈동자 위·아래), `eye_shine`(반사점), `mouth_color`, `roughness`·`specular`·`rim`·`rim_tint`(젤리 윤기). `buildings` 절 — `store_wall`·`store_roof`·`store_door`, `farm_soil`·`farm_crop`, `plant_base`·`plant_tip`, `berry_skin`·`berry_leaf`, `roughness`·`specular`(공용 재질), `*_triangles_max`.
- **캡처:** `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/geo_capture.gd -- --out=폴더` → `geo-lineup.png`(계통 색 6가지, 크기 0.6·1.0·1.6 × 정면·3/4·옆, 소품, 지도 배율 1:1). 기본 폴더는 `docs/screenshots/v0.1/`.

### ProcGeo — `scripts/view/proc_geo.gd` (`class_name ProcGeo`, RefCounted)

SlimeGeo 가 쓰는 절차적 메시 조립기(이전 프로젝트 `char_geo.gd`·`demon_geo.gd` 기법을 뼈 없이 옮김). 정점 `v`·법선 `n`·정점 색 `c`·번호 `idx` 배열을 쌓고 `to_mesh(material)` 로 ArrayMesh 를 만듭니다. 다른 요소도 써도 됩니다.

| 멤버 | 뜻 |
|---|---|
| `vert(p, n, col) -> int`, `tri(a, b, d)`, `quad(a, b, e, d)` | 정점·삼각형. `tri` 는 세 정점 법선 합을 바깥으로 보고 앞면 감김(바깥에서 시계 방향)을 자동으로 맞추고, 넓이 0 은 버림 |
| `sculpt(ce, r, segs, rings, shape, col, col_of, lats, lons, holes)` | 구 조각: `shape.call(dir) -> float`(방향별 반지름 배수), 법선은 조각 겉면 차분, `col_of.call(dir, p) -> Color`. `lats`·`lons` 로 격자 각도 지정, `holes`(Rect2i 칸 묶음)는 비워 둠. 삼각형 = 2 × segs × (rings - 1) - 구멍 |
| `grid_index(i, j)`, `grid_loop(rect)` | 마지막 조각 격자의 정점 번호, 칸 묶음 둘레(한 바퀴) |
| `surface_vert(ce, r, dir, shape, col) -> int` | 같은 조각 겉면 위 임의 방향에 정점(법선 포함) |
| `zip_loops(outer, ang_o, inner, ang_i)`, `fan(center, loop)` | 정점 수가 다른 두 닫힌 고리를 각도 순으로 이음(삼각형 = 두 수의 합), 부채꼴 |
| `static spread(count, a0, a1, density, pins) -> PackedFloat64Array` | 밀도 함수대로 구간을 나눈 각도(핀 위치엔 반드시 격자선) |
| `static direction(lat, lon)`, `lat_of(dir)`, `lon_of(dir)`, `tangent_uv(center, dir)`, `tangent_dir(center, uv)`, `bump(dir, cdir, sigma)`, `smin(a, b, k)` | 구 좌표(경도 0 = -Z)·접평면 좌표·가우스 혹·부드러운 최솟값 |
| `lathe(prof, segs, close_top, close_bottom, center)` | 회전체: `prof = [{y, r 또는 rx·rz, col}]` 위→아래, 같은 자리 마디 두 번 = 각진 모서리, 반지름 0 = 꼭짓점 |
| `torus(ce, R, r, col, segs, rings, flat)`, `leaf(...)`, `petal(...)` | 납작하게 누를 수 있는 도넛, 휘는 양면 잎(V 단면), 작은 양면 마름모 잎 |
| `translate(off, from)`, `scale_uniform(k, from)`, `transform(xf, from)`, `bounds()`, `triangles()`, `to_mesh(material)` | 정점 옮기기·경계 상자·삼각형 수·메시 만들기 |

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

**구현 메모(3단계, MapView 담당이 덧붙임)**

- 노드(이름 고정, 검사가 씀): `Camera`(궤도 카메라) · `Environment`(WorldEnvironment) · `Sun` · `Terrain`(ArrayMesh 하나) · `Farms` · `Stores` · `Plants` · `Dropped` · `Slimes` · `SlimeShadows` · `Carry`(MultiMeshInstance3D) · `SelectRing`.
- 궤도 카메라 `scripts/view/orbit_camera.gd`(Camera3D, 전역 이름 없이 `MapView.OrbitCamera` 로 preload): `target`·`yaw`·`pitch`·`distance`, `apply()`, `fit_rect(rect, aspect)`(네 모서리를 투영해 지도 전체가 들어오게), `pan_pixels(rel, vp_h)`, `zoom_at(screen_pos, steps)`(커서 아래 땅 점 고정), `rotate_pixels(rel)`, `ground_point(screen_pos, plane_y)`, `reset_orientation()`. 수치는 `camera` 절(`pitch_min_deg`·`pitch_max_deg`·`fit_margin`·`near`·`far`·`focus_distance`·`click_threshold_px`·`gesture_pan_px` 추가).
- `bind` 는 카메라를 처음 방위·고각으로 돌려 지도 전체를 맞춘다. 사용자가 카메라를 움직이기 전에는 뷰포트 크기가 바뀔 때(SubViewportContainer 배치 뒤 등) 다시 맞춘다.
- 트리에 들어가면 자기 SubViewport 의 `own_world_3d` 를 켠다(지연 호출) — 비교 모드에서 두 지도의 3D 세계가 섞이지 않게.
- `pick_slime` 은 땅(y 0)이 아니라 **슬라임 중심 높이**(메시 높이의 절반)의 수평면과 광선을 교차하고, 마지막으로 그린(보간된) 위치 중 `ui.map.pick_radius` 칸 안의 가장 가까운 개체를 고른다. 클릭은 누른 곳에서 `click_threshold_px` 이상 움직이지 않고 뗐을 때.
- 보간: `before_steps()` 가 (틱이 바뀌었을 때만) id·칸·방향 배열을 복사해 두고, `update_view` 는 틱이 진행한 프레임에 그 복사본을 "이전 위치"로 올린다. 두 배열이 id 오름차순이라 두 포인터로 맞춘다(새로 태어난 개체는 지금 칸에 바로 나타남). 움직인 개체는 `sin(π·alpha)` 로 뛰고 `sin(2π·alpha)` 로 늘었다 눌리며(부피 유지), 가만히 있으면 숨쉬기, 먹기·줍기·심기 중이면 끄덕임. 같은 칸의 여러 개체는 `slime.stack_offset` 둘레에 나뉜다.
- 땅 색 갱신은 위 사각형 부분의 정점 색(RGBA8)만 `ArrayMesh.surface_update_attribute_region` 으로 올린다. 식물(`plant_refresh_ticks`)과 땅 색(`terrain_refresh_ticks`)은 각자 최소 프레임 간격(`plant_min_frames`·`terrain_min_frames`)을 두고, 같은 프레임에 둘 다 하지 않는다.
- 메시 바닥 맞춤: 각 SlimeGeo 메시의 AABB 아래면을 y 0 에 맞춰 놓는다(조각 메시는 원래 0, 기본 도형 대용품은 가운데 원점). 인스턴스 색은 메시에 정점 색이 있으면 흰색(메시 색 그대로), 없으면 `ui.map`·`ui.buildings` 의 대신 색.
- 저장고는 Y 축으로 반 바퀴 돌려 놓는다: 메시 정면(-Z, 문)이 남쪽(+Z) = 처음 카메라 쪽을 보게. 밭은 그대로.
- 실시간 그림자는 끔(`map.shadows`): Compatibility 렌더러에서 해 그림자를 켜면 해 빛이 한 번 더 더해져 장면이 크게 밝아진다(측정: 같은 설정에서 #3c8735 → #51c148). 대신 슬라임 발밑에 부드러운 원판 그림자(`blob_shadow_*`, 빛이 떨어지는 쪽으로 조금 밀림).
- 밤에는 해·주변광·배경을 `night_*` 쪽 푸른 색으로 섞고, 슬라임 인스턴스 색을 `night_slime_boost` 배까지 밝혀 계통 색이 읽히게 한다. 계절마다 풀밭 색에 `season_tints` 를 조금 섞는다.
- 검사·기록용 추가 함수: `terrain_tile_color(c) -> Color`(칸의 지금 위 사각형 색), `slime_instance_position(k) -> Vector3`(k 번째 슬라임 인스턴스 위치), `view_stats()` 의 `slime_us`·`plant_us`·`terrain_us`(마지막 갱신 시간 µs).
- 측정(헤드리스, 이 기계 Xeon 2.3GHz): 슬라임 250마리 갱신 약 0.35ms/프레임(`update_view` 평균 약 0.45ms, 식물·땅 갱신 몫 포함), 식물 2,587포기 갱신 약 0.6ms(2틱·2프레임마다), 땅 색 3,072칸 약 0.9~1.1ms(10틱·2프레임마다). `tests/view/map_checks.gd` 가 매번 출력한다.
- 캡처: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/map_capture.gd -- --out=폴더` → `map-overview`·`map-closeup`·`map-night`(500KB 넘으면 JPG).

## InfoPanel — `scripts/ui/info_panel.gd` (`class_name InfoPanel`, PanelContainer)

| 멤버 | 뜻 |
|---|---|
| `signal slime_requested(id: int)` | 부모·조부모·자식 항목을 눌렀을 때 |
| `signal follow_toggled(on: bool)` | "따라가기" 단추 |
| `func show_slime(world: SimWorld, id: int) -> void` | 개체 정보 표시(id, 살아 있음/죽음·원인, 세대, 나이/최대 나이, 에너지 막대, 운반, 현재 행동, 크기·감지·색 견본, 부모·조부모(2대), 자식 목록 `children_of(id, ui.info.children_max)`, 두뇌 그림) |
| `func clear() -> void` | "슬라임을 눌러 고르세요" 안내 |
| `func refresh() -> void` | 같은 개체의 바뀐 값 다시 표시(LabMain 이 `ui.info.refresh_frames` 마다 부름). 그사이 죽었으면 죽음 표시 |
| `func current_id() -> int` | 표시 중인 id(-1 없음) |
| `func set_follow(on: bool) -> void` | (추가) "따라가기" 단추 모양만 맞춤(신호 없음). LabMain 이 F 키 등으로 따라가기를 바꿨을 때 부른다 |
| `func summary_text() -> String` | (추가) 머리 한 줄 `"#id · N세대 · 살아 있음"` / `"… · 죽음 · 원인 · 틱 T"`, 빈 상태면 안내 문구(검사·캡처 확인용) |
| `var children_scans: int` | (추가, 검사용) `children_of` 를 부른 횟수 |
| `const META_ID`, `META_REL`, `REL_PARENT`·`REL_GRANDPARENT`·`REL_CHILD` | (추가) 가계 단추(Button)의 메타 `slime_id`·`relation` |

동작 세부: 너비 `ui.lab.right_panel_width`. 머리(작은 슬라임 모양 색 견본 `Color.from_hsv(hue, ui.slime.saturation, ui.slime.value)`·`#id`·세대·생사/원인/사망 틱·따라가기)는 고정, 나머지(현재 상태 / 죽음 → 특성 → 가계 → 두뇌)는 세로 스크롤. 없는 id 는 안내 문구만 보이고 `current_id()` = -1. 가계 단추는 `#id` + 계통 색 점, 죽은 친척은 속 빈 점·흐린 글자(refresh 때 생사 갱신). 자식은 최대 `ui.info.children_max` 개 + 넘치면 `+K`. `refresh()` 는 `slime_info` 한 번 + 친척 수만큼 `index_of_id` 만 쓰고, `children_of` 는 (세계, id) 가 바뀌거나 자식 수가 바뀌었고 목록이 한도 미만일 때만 부른다. 지켜보던 개체가 죽으면 마지막 두뇌를 "죽기 직전의 두뇌" 로 남기고, 처음부터 죽은 개체(유전체 없음)는 두뇌 대신 안내 문구. 단추는 초점을 받지 않는다(스페이스 = 멈춤과 겹치지 않게). LabMain 연결: `slime_requested` → `select_slime(id)`, `follow_toggled` → `map_view.follow_selected`.

`BrainView` — `scripts/ui/brain_view.gd` (`class_name BrainView`, Control): `func set_genome(L: Dictionary, genome: PackedFloat32Array) -> void` 가중치 열지도(입력×은닉, 은닉×출력; 양수·음수 색은 `ui.info.heatmap_*`), 입력·행동 이름은 `SimBrain.INPUT_NAMES`·`ACTION_NAMES`.

| 멤버(추가) | 뜻 |
|---|---|
| `var weight_clamp: float` | 색 세기 정규화 상한. `set_genome` 전에 `world.cfg.brain.weight_clamp` 를 넣는다(InfoPanel 이 함) |
| `func set_highlight_action(a: int) -> void`, `func highlight_action() -> int` | 아래 덩어리에서 현재 행동 줄 강조(-1 없음) |
| `static func size_for(L) -> Vector2` | 최소 크기: 너비 = `heatmap_label_width` + max(n_in, n_hid)·`heatmap_cell`, 높이 = `heatmap_header_height` + n_hid·cell + `heatmap_block_gap` + cell(은닉 번호 줄) + n_out·cell + `heatmap_legend_height`. `set_genome` 이 `custom_minimum_size` 로 넣음 |
| `func cell_at(pos: Vector2) -> Dictionary` | 그 위치의 칸 `{block: "w1"/"w2"/"input", row, col, weight, text}`(밖이면 `{}`). 풍선 도움말(`_get_tooltip`)이 씀 |
| `static func input_name(i)`, `output_name(q)` | 화면 이름(기본 다음은 `"기억 k"`) |
| `static func weight_color(w, clamp) -> Color` | 음수 색 ← 창 색(0) → 양수 색, 세기 = (abs(w) / clamp)^`heatmap_gamma` |

배치: 위 덩어리 = 은닉 8행 × 입력 n_in 열(유전체 w1 순서), 열 위에 입력 이름을 한글 세로쓰기로, 아래 덩어리 = 출력 n_out 행 × 은닉 8열(w2), 기억 열·행은 강조색 선으로 나눔, 맨 아래 범례(−상한 … +상한).

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
