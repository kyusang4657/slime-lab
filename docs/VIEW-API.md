# 화면 구성 요소 계약 (v0.1, 3~4단계)

실험실 화면을 구성 요소로 나누고, 각 요소가 서로 기대하는 이름·시그니처·동작을 고정합니다. 각 요소는 이 문서와 [`SIM-API.md`](SIM-API.md)의 질의만 써서 시뮬레이션을 읽습니다.

## 공통 규칙

1. **화면은 시뮬레이션을 바꾸지 않습니다.** `SimWorld` 의 배열에 쓰거나, `step()` 이외의 진행 함수(`_act`, `_think` 등 밑줄 함수)를 부르거나, `sample()`(기간 카운터를 0 으로 되돌림)·`drain_events()`(사건을 소비함)를 부르는 것은 **LabMain 만** 합니다(`sample()` 은 4단계 기록기만). 화면 때문에 역사 해시가 바뀌면 안 됩니다(검사). `tools/test_repo_rules.py` 가 `scripts/view`·`scripts/ui` 에서 세계에 닿은 멤버에 대입·`append` 같은 고치는 호출·`step`/`setup`/`sample`/`drain_events` 호출을 찾아 실패시킵니다(허용: Experiment 의 `setup`·`step`·`step_n`·`sample`, LabMain 의 `drain_events`).
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
- **모양 수치(검토 I55):** 소품 메시(풀포기·열매·저장고·밭) 함수 몸통에는 이름 없는 수치를 두지 않는다 — 잎 방향·키·폭, 열매 반지름·잎, 흙판·이랑·싹의 들임·어둡힘은 `slime_geo.gd` 의 이름 붙은 상수(`PLANT_*`·`BERRY_*`·`FARM_*`·`SPROUT_*`·`RIDGE_*`·`SLAB_*`), 저장고 벽·지붕은 옆모습 표 `STORE_WALL_PROFILE`·`STORE_ROOF_PROFILE`(`[높이, 반지름, 색 갈래, 어둡힘]`, 처마 반지름 0.47), 문은 `STORE_DOOR_*`. 번호·반(0.5)·하나만 그대로 쓴다(검사 `geo_checks._named_numbers` 가 함수 몸통을 읽어 셈). 메시는 이름만 바꾼 것이라 정점·색이 그대로다.
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
| `func before_steps() -> void` | `step()` 을 부르기 **직전마다** 호출(한 프레임에 여러 틱이면 틱마다, 프레임 처음에도 한 번). 보간용으로 현재 위치(id → 칸)를 기억(틱이 바뀌었을 때만 복사) |
| `func update_view(alpha: float, delta: float = 1/60) -> void` | 매 프레임 `step()` 뒤에 호출. `alpha`(0~1) = **마지막 틱**의 진행률(보간·통통 튐), `delta` = 이 프레임 시간(따라가기 카메라). 슬라임·식물·건물·빛(낮밤)·선택 표시 갱신. 지형 색은 `ui.map.terrain_refresh_ticks` 마다 |
| `func set_selected(id: int) -> void` | 선택 표시(-1 = 없음). 죽은 개체면 표시 없음 |
| `func pick_slime(screen_pos: Vector2) -> int` | 뷰포트 좌표의 광선이 맞는 그린 몸 가운데 가장 앞(카메라에 가까운) 살아 있는 슬라임 id. 몸에 맞지 않으면 몸 가운데 높이와 교차해 반경 안의 가장 가까운(그린 위치) 개체, 그것도 없으면 -1 |
| `func focus_on(id: int) -> void` | 카메라를 그 개체로 옮김 |
| `func fit_map() -> void` | (추가) 지도 전체 맞춤(처음 방위·고각)으로 되돌리고 따라가기 끔. 다시 움직이기 전까지 뷰포트 크기가 바뀌면 다시 맞춤 |
| `func display_scale() -> float` | (추가) 지금 표시 배율(멀리서 작은 슬라임을 키운 배수, 가까이 1) |
| `var follow_selected: bool` | 켜면 선택한 개체를 카메라가 따라감 |
| `func get_camera() -> Camera3D` | 카메라 |
| `func view_stats() -> Dictionary` | `{slimes, plants, stores, farms, triangles_estimate, chunks, plant_n, terrain_n}` (성능 기록용). `plants` = 먹이가 있어 보이는 풀포기, `triangles_estimate` = 그리기에 넘기는 삼각형(배율 0 으로 숨긴 풀포기 인스턴스·슬라임 발밑 그림자 포함), `chunks` = 땅·풀포기 덩어리 수, `plant_n`·`terrain_n` = 이번 프레임에 다시 본 풀포기·칸 수(갱신이 없던 프레임은 0) |
| 입력 | `_unhandled_input`: 왼쪽 끌기 = 이동, 휠 = 확대·축소, 오른쪽 끌기 = 회전, 왼쪽 클릭 = 고르기 |

**구현 메모(3단계, MapView 담당이 덧붙임)**

- 노드(이름 고정, 검사가 씀): `Camera`(궤도 카메라) · `Environment`(WorldEnvironment) · `Sun` · `Terrain`(첫 덩어리의 땅 ArrayMesh) · `Farms` · `Stores` · `Plants`(첫 덩어리의 풀포기) · `Dropped` · `Slimes` · `SlimeShadows` · `Carry`(MultiMeshInstance3D) · `SelectRing`. 지도가 덩어리(`ui.map.chunk_tiles`² 칸) 하나보다 크면 나머지 덩어리는 `Terrain_k`·`Plants_k`(k = 1, 2, …, 덩어리는 행 우선) — 기본 지도 64×48 은 덩어리 하나라 예전과 같다.
- 궤도 카메라 `scripts/view/orbit_camera.gd`(Camera3D, 전역 이름 없이 `MapView.OrbitCamera` 로 preload): `target`·`yaw`·`pitch`·`distance`, `apply()`, `fit_rect(rect, aspect)`(네 모서리를 투영해 지도 전체가 들어오게), `pan_pixels(rel, vp_h)`, `zoom_at(screen_pos, steps)`(커서 아래 땅 점 고정), `rotate_pixels(rel)`, `ground_point(screen_pos, plane_y)`, `reset_orientation()`, `distance_max()`. (4단계 검토 반영) `portrait_yaw`(라디안, 0 = 끔)·`portrait_gain`: 0 이 아니면 `fit_rect` 가 지금 방위와 그만큼 돌린 방위로 각각 맞춰 보고, 돌린 쪽 거리가 `portrait_gain` 배 이상 가까우면(지도가 그만큼 크게 보이면) 돌린 방위를 남긴다 — LabMain 이 비교 모드 지도에 `ui.compare.portrait_yaw_deg`·`portrait_gain_min` 을 넣는다(세로로 긴 칸). `view_turns() -> int` = 화면이 북쪽 위(방위 0)에서 90° 씩 몇 번 돌았는지(0~3, 1 = 화면 위가 서쪽·북쪽은 오른쪽). 수치는 `camera` 절(`pitch_min_deg`·`pitch_max_deg`·`fit_margin`·`near`·`far`·`focus_distance`·`click_threshold_px`·`gesture_pan_px`·`fit_zoom_out_factor`·`follow_ref_fps` 추가).
- 최대 거리: 설정값 `camera.distance_max`(95) 로 지도 전체가 안 들어오는 큰 지도(128×96 이상, 설정 상한 1024)는 `fit_rect` 가 자르지 않고 맞춘 뒤, 실제 최대 거리 = max(설정값, 맞춘 거리 × `fit_zoom_out_factor`), 먼 자르기 면 = max(`camera.far`, 최대 거리 + 지도 대각선). `distance_max()` 는 실제 값(검사: 128×96·200×150 이 처음에 다 보임). 실시간 그림자는 꺼져 있어 `shadow_distance` 는 늘리지 않음.
- `bind` 는 앞 세계의 저장고·밭 인스턴스를 지우고(통합 때 고침: 건물 없는 새 세계에 앞 세계 건물이 남던 문제), 카메라를 처음 방위·고각으로 돌려 지도 전체를 맞춘다. 사용자가 카메라를 움직이기 전에는 뷰포트 크기가 바뀔 때(SubViewportContainer 배치 뒤 등) 다시 맞춘다.
- 트리에 들어가면 자기 SubViewport 의 `own_world_3d` 를 켠다(지연 호출) — 비교 모드에서 두 지도의 3D 세계가 섞이지 않게.
- `pick_slime` 은 **깊이를 본다**(검토 I53): ① 마지막으로 그린 인스턴스 변환(크기·표시 배율·늘어남·뜀·땅 높이)을 입힌 슬라임 메시 삼각형과 광선을 교차해(감싸는 구 → 지역 경계 상자로 먼저 거름) 맞는 개체 가운데 가장 앞(광선 거리 최소) 것을 고른다 — 같은 칸에 겹친 개체나 낮은 고각에서 보이는 앞 개체(예전에는 고정 높이 평면과만 교차해 앞 개체 위쪽을 누르면 뒤 개체가, 고각 25° 에서 큰 개체 머리를 누르면 반경 밖이라 -1 = 선택 해제가 됐다). ② 아무 몸에도 맞지 않으면 예전처럼 **슬라임 중심 높이**(메시 높이의 절반 × 표시 배율)의 수평면과 교차해 그린(보간된) 위치 중 `ui.map.pick_radius` × 표시 배율 칸 안의 가장 가까운 개체(작은 몸 둘레를 눌러도 고르게). 한 번에 약 0.13ms(250마리, 헤드리스, 최대 약 1.2ms). 클릭은 누른 곳에서 `click_threshold_px` 이상 움직이지 않고 뗐을 때. 검사 `map_checks._check_pick_depth`(겹친 칸 앞 개체 위쪽 — 양쪽 방위, 고각 25° 크기 1.6 머리, 몸 옆 반경 안).
- 보간: `before_steps()` 가 (틱이 바뀌었을 때만) id·칸·방향 배열을 복사해 두고, `update_view` 는 틱이 진행한 프레임에 그 복사본을 "이전 위치"로 올린다. 두 배열이 id 오름차순이라 두 포인터로 맞춘다(새로 태어난 개체는 지금 칸에 바로 나타남). **보간은 마지막 한 틱만**: LabMain 이 `step()` 마다 `before_steps()` 를 불러 복사본이 그린 틱의 한 틱 전이고, 복사본이 두 틱 이상 낡았으면(한 번만 부르고 여러 틱) 보간하지 않고 지금 칸에 그린다(낡은 자리에서 미끄러지지 않게). 움직인 개체는 `sin(π·alpha)` 로 뛰고 `sin(2π·alpha)` 로 늘었다 눌리며(부피 유지), 가만히 있으면 숨쉬기, 먹기·줍기·심기 중이면 끄덕임.
- 둘레 자리: 같은 칸의 여러 개체는 `ui.slime.stack_offset` 둘레에 나뉜다 — `ui.slime.stack_ring` 마리를 넘으면 한 마리마다 `ui.slime.stack_grow` 배씩 넓히되 `stack_offset × ui.slime.stack_max_k` 까지(`static func stack_max()`, 검토 I55: 예전에는 코드 상수 0.42 가 설정을 조용히 잘랐다. `static var STACK_MAX` 는 예전 이름을 쓰는 검사를 위한 같은 값). **저장고 칸**의 개체는 움집(처마 반지름 0.47) 안에 묻히지 않게 문 앞 반지름 `map.store_slime_offset` 의 호에 `map.store_slime_arc_deg` 간격(넘치면 `store_slime_arc_max_deg` 안에)으로 선다. 문 앞 = 문 방향 이웃 쪽: 남 → 동 → 서 → 북(`DOOR_ORDER`) 가운데 지도 안·지나갈 수 있고 다른 저장고가 아닌 첫 이웃, 없으면 지나갈 수 있는 첫 이웃(검토 I54: 예전에는 늘 남쪽이라 남쪽이 바위면 몸이 바위 속에, 맨 아래 줄이면 지도 밖 허공에 그려졌다). 둘레가 모두 막힌 저장고는 남쪽, 반지름을 칸 안(0.5 − `slime.radius`)까지 줄인다. 문 방향은 물·바위·지도 끝·저장고 목록만 보므로 저장고 목록이 바뀔 때만 다시 정한다. 둘레 자리는 틱이 바뀔 때 지금 배열과 이전 배열로 각각 계산하고(칸 안 자리 순서 = id 순서) 위치와 함께 보간한다 — 다른 개체가 들고 나도 가만히 있는 개체가 틱 경계에서 튀지 않는다(검사).
- 땅 높이: **밭 칸**에서는 슬라임 바닥·그림자·운반 열매를 흙판 윗면(`map.farm_lift` + 흙판 두께)에 올리고(칸 사이를 뛸 때 보간), 선택 고리는 이랑 꼭대기 위에 둔다.
- 풀포기: 슬라임이 서 있는(또는 이번 틱에 떠난) 칸의 풀포기는 `map.plant_occupied_scale` 배로 줄여 몸을 뚫고 나오지 않게 한다(틱이 바뀔 때만, 바뀐 풀포기의 변환만 다시 씀). `view_stats().plants` 는 먹이로 보이는 수 그대로.
- 표시 배율(멀리서): 카메라 목표 거리에서 크기 1 슬라임의 화면 지름이 `map.slime_min_px` 보다 작으면 그만큼 키운다(최대 `map.slime_display_scale_max`). 몸·뜀 높이·그림자·운반 열매·고르기 반경에 곱하고, 자리(칸·둘레)는 그대로. `focus_distance` 근처에서는 1(실제 크기). 시뮬레이션과 무관.
- 선택 고리: 실제 크기(반지름 × 크기 × `ring_scale` × 표시 배율)의 화면 지름이 `map.ring_min_px` 보다 작으면(전경) 최소 크기로 키우고 깊이 검사 없이 맨 위에 그린다(풀·밭·다른 개체에 가리지 않게). 가까이서는 실제 크기·깊이 검사.
- 따라가기: 목표가 프레임마다 `1 − (1 − camera.follow_lerp)^(delta × camera.follow_ref_fps)` 만큼 선택 개체로 다가간다(프레임 빠르기와 무관, 60fps 에서 예전과 같음).
- 땅 색 갱신은 위 사각형 부분의 정점 색(RGBA8)만 `ArrayMesh.surface_update_attribute_region` 으로 올린다. 식물(`plant_refresh_ticks`)과 땅 색(`terrain_refresh_ticks`)은 각자 최소 프레임 간격(`plant_min_frames`·`terrain_min_frames`)을 두고, 같은 프레임에 둘 다 하지 않는다.
- **덩어리·바뀐 것만 쓰기(검토 I52):** 땅과 풀포기를 `ui.map.chunk_tiles`(64)² 칸 덩어리로 나눠 덩어리마다 메시·MultiMesh 하나로 그린다(화면 밖 덩어리는 엔진이 잘라 냄). 식물·땅 색 갱신 **한 바퀴**는 위 간격 조건에서 시작해 **한 프레임에 덩어리 하나씩** 돌고(두 바퀴가 함께 돌면 프레임을 번갈아), 묶은 직후·세계가 되돌아갔을 때만 전체를 한 번에 한다. 덩어리 안에서는 먹이량 배율·칸 종류가 바뀐 풀포기와 색이 바뀐 칸만 버퍼에 쓰고, 쓴 덩어리만 올린다. 개체가 선 칸의 풀포기 줄이기(점유)는 덩어리가 여럿이면 그 인스턴스 하나만 바로 보낸다(덩어리 하나면 예전처럼 버퍼 전체 한 번). 그래서 한 프레임 비용은 지도 크기가 아니라 덩어리 크기에 비례한다 — 기본 지도는 덩어리 하나라 그림·버퍼가 예전과 바이트까지 같고(400프레임 비교) 비용도 같거나 조금 적다(헤드리스 미세 측정 1배 화면 약 0.73ms/프레임, 예전 약 0.76~0.80ms). 큰 지도에서는 덩어리 수만큼의 프레임 동안 새 먹이량·색이 덩어리별로 퍼져 나타난다(256×256 은 16덩어리 ≈ 식물·땅 번갈아 약 0.5초).
- **큰 지도 비용(헤드리스, 이 기계, 1틱/프레임 진행):** 한 프레임 식물·땅 색 갱신 중앙값 — 64×48 약 0.7·1.5ms(덩어리 1), 128×128 약 1.0·2.0ms(4), 256×256 약 1.7·2.1ms(16), 512×512 약 1.8·2.2ms(64). 고치기 전 256×256 은 식물 약 23ms·땅 색 약 28ms(칸 수에 비례, 64×48 의 약 21배). 칸 수에 그대로 비례하는 것은 남는다: 지도를 붙이는 시간(메시 만들기, 256×256 약 0.55초·512×512 약 2.5초·1024×1024 약 14초 — 마지막은 검토 탐침 값), 그리는 삼각형(숨긴 풀포기 포함 256×256 약 650만·512×512 약 2,600만 — 지도 전체를 한 화면에 볼 때 GPU 부담), 그리고 시뮬레이션 한 틱(256×256 약 23ms·512×512 약 80ms). 그래서 지도 창으로 보기에는 256×256 이하를 권한다(설정 범위 8~1024 는 `SimConfig.validate` 가 막는 범위일 뿐 성능을 보장하지 않음 — `docs/CONFIG.md` `map.width`). 검사 `map_checks._check_big_map_cost`: 256×256 에서 한 프레임에 다시 보는 풀포기·칸 ≤ 덩어리 크기, 식물·땅 색 한 프레임 시간 비(256×256 / 64×48, 같은 실행 안 중앙값) < 칸 수 비 / 4(고치기 전 약 21배), 나눠 돈 결과가 새로 묶은 MapView 와 모든 칸에서 같음.
- 메시 바닥 맞춤: 각 SlimeGeo 메시의 AABB 아래면을 y 0 에 맞춰 놓는다(조각 메시는 원래 0, 기본 도형 대용품은 가운데 원점). 인스턴스 색은 메시에 정점 색이 있으면 흰색(메시 색 그대로), 없으면 `ui.map`·`ui.buildings` 의 대신 색.
- 저장고는 메시 정면(-Z, 문)이 문 앞 자리 쪽을 보게 Y 축으로 직각 단위로 돌려 놓는다(보통 남쪽 +Z = 처음 카메라 쪽, 남쪽이 물·바위·지도 끝이면 동·서·북 — 위 둘레 자리). 밭은 그대로.
- 실시간 그림자는 끔(`map.shadows`): Compatibility 렌더러에서 해 그림자를 켜면 해 빛이 한 번 더 더해져 장면이 크게 밝아진다(측정: 같은 설정에서 #3c8735 → #51c148). 대신 슬라임 발밑에 부드러운 원판 그림자(`blob_shadow_*`, 빛이 떨어지는 쪽으로 조금 밀림). 원판 안쪽 고리 반지름·진하기 = `ui.map.blob_shadow_inner`·`ui.map.blob_shadow_inner_alpha`, 뛰어오르면 높이 1 당 `ui.map.blob_shadow_shrink` 만큼 작아진다.
- 그 밖의 보기 조정값도 `ui.json`(검토 I55, 예전에는 코드 상수): 땅 옆면의 물 옆면 어둡힘 `ui.map.water_side_dark`·아래 모서리 어둡힘 `ui.map.side_bottom_dark`, 먹기·줍기·심기 끄덕임 횟수 `ui.map.action_bob_per_tick`(틱당, 0.5 = 반 번). `map_view.gd` 에 남은 숫자 상수는 버퍼 짜임·해시·직각·바이트·수치 오차·고리 메시 치수·문 방향 순서 같은 기술 상수뿐이다(검사 `map_checks._check_ui_tuning` 이 소스를 읽어 견주고, 설정을 바꿔 MapView 를 만들어 겹침 둘레·그림자 원판에 그대로 쓰이는지 본다).
- 밤에는 해·주변광·배경을 `night_*` 쪽 푸른 색으로 섞고, 슬라임 인스턴스 색을 `night_slime_boost` 배까지 밝혀 계통 색이 읽히게 한다. 계절마다 풀밭 색에 `season_tints` 를 조금 섞는다.
- 검사·기록용 추가 함수: `terrain_tile_color(c) -> Color`(칸의 지금 위 사각형 색, 덩어리와 무관하게 칸 번호로), `slime_instance_position(k) -> Vector3`(k 번째 슬라임 인스턴스 위치), `slime_instance_scale(k) -> Vector3`(축별 배율), `shadow_instance_position(k)`, `plant_scale_at(c) -> Vector2`(그린 세로 배율, 먹이량만의 배율), `ring_info() -> {visible, radius, on_top, position}`, `view_stats()` 의 `slime_us`·`plant_us`·`terrain_us`(마지막 갱신 시간 µs).
- 측정(헤드리스, 이 기계 Xeon 2.3GHz, 검토 뒤): 슬라임 250마리 갱신 약 0.4ms/프레임(`update_view` 평균 약 0.45~0.58ms, 식물·땅 갱신 몫 포함, 틱이 바뀐 프레임은 둘레 자리·풀포기 점유 계산으로 약 0.9ms), 식물 2,587포기 갱신 약 0.6ms(2틱·2프레임마다), 땅 색 3,072칸 약 0.85ms(10틱·2프레임마다). `tests/view/map_checks.gd` 가 매번 출력한다.
- 캡처: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/map_capture.gd -- --out=폴더` → `map-overview`·`map-closeup`·`map-night`(JPG 품질 0.85).

## InfoPanel — `scripts/ui/info_panel.gd` (`class_name InfoPanel`, PanelContainer)

| 멤버 | 뜻 |
|---|---|
| `signal slime_requested(id: int)` | 부모·조부모·자식 항목을 눌렀을 때 |
| `signal follow_toggled(on: bool)` | "따라가기" 단추 |
| `func show_slime(world: SimWorld, id: int) -> void` | 개체 정보 표시(id, 살아 있음/죽음·원인, 세대, 나이/최대 나이, 에너지 막대, 운반, 현재 행동, 크기·감지·색 견본, 부모·조부모(2대), 자식 목록 `children_of(id, ui.info.children_max)`, 두뇌 그림) |
| `func clear() -> void` | "슬라임을 눌러 고르세요" 안내(`set_empty_text` 로 바꾼 문구가 있으면 그것) |
| `func refresh() -> void` | 같은 개체의 바뀐 값 다시 표시(LabMain 이 `ui.info.refresh_frames` 마다 부름). 그사이 죽었으면 죽음 표시 |
| `func current_id() -> int` | 표시 중인 id(-1 없음) |
| `func set_follow(on: bool) -> void` | (추가) "따라가기" 단추 모양만 맞춤(신호 없음). LabMain 이 F·Home 키 등으로 따라가기를 바꿨을 때 부른다 |
| `func set_empty_text(text: String) -> void` | (추가) 빈 상태 안내 문구("" = 기본). LabMain 이 멸종하면 "멸종했습니다 (틱 N)\n고를 개체가 없습니다". 안내는 본문과 같은 여백(`info.padding`) 안에서 줄을 바꾼다(4단계 검토 반영 — 긴 비교 모드 안내가 창 양쪽 끝에 닿던 것) |
| `func set_view_turns(turns: int) -> void` · `func heading_text(hd) -> String` | (추가, 4단계 검토 반영) 지도 화면이 북쪽 위에서 90° 씩 돈 수(`OrbitCamera.view_turns()`). "방향" 은 낱말 그대로 화살표만 화면 방향으로("북 ↑" → 화면이 한 번 돌면 "북 →"). LabMain 이 선택한 지도로 매 프레임 넣음(바뀔 때만 다시 씀). `HEADING_WORDS`·`HEADING_ARROWS` |
| `static func brain_width() -> float` | (추가) 두뇌 열지도가 들어갈 너비 = `lab.right_panel_width` − 테두리 − 2 × `info.padding` − `info.scrollbar_width` |
| `func content_overflow() -> float` | (추가) 스크롤 본문이 보이는 높이를 넘는 픽셀(음수 = 여유). V07 검사용 |
| `func summary_text() -> String` | (추가) 머리 한 줄 `"#id · N세대 · 살아 있음"` / `"… · 죽음 · 원인 · 틱 T"`, 빈 상태면 안내 문구(검사·캡처 확인용) |
| `var children_scans: int` | (추가, 검사용) `children_of` 를 부른 횟수 |
| `const META_ID`, `META_REL`, `REL_PARENT`·`REL_GRANDPARENT`·`REL_CHILD` | (추가) 가계 단추(Button)의 메타 `slime_id`·`relation` |

동작 세부: 너비 `ui.lab.right_panel_width` — 고른 개체(큰 두뇌 포함)에 따라 바뀌지 않는다(지도 폭이 선택마다 출렁이지 않게, 검사). 테마는 공용 `UiTheme.build()` 를 바탕으로(`merge_with`, 따라가기 단추·말풍선이 실험실과 같은 모양 — `theme.button_padding_*`) 이 창에만 있는 것(작은 단추 형 변형 `InfoSmallButton`, 가계 단추, 에너지 막대, 가는 스크롤 막대, 촘촘한 구분선)만 더한다. 수치는 `info` 절(`title_font_size`·`inline_gap`·`key_gap`·`title_gap`·`separator_gap`·`energy_outline`·`relative_pad_*`·`relative_*lighten`·`dead_dot_alpha`·`dead_text_alpha`·`min_vertical_slack` 등), 색 견본의 눈 = `slime.eye_color`, 바닥 그림자 = `map.blob_shadow_alpha`. 머리(작은 슬라임 모양 색 견본 `Color.from_hsv(hue, ui.slime.saturation, ui.slime.value)`·`#id`·세대·생사/원인/사망 틱·따라가기)는 고정, 나머지(현재 상태 / 죽음 → 특성 → 가계 → 두뇌)는 세로 스크롤. 없는 id 는 안내 문구만 보이고 `current_id()` = -1. 가계 단추는 `#id` + 계통 색 점, 죽은 친척은 속 빈 점·흐린 글자(refresh 때 생사 갱신). 자식은 최대 `ui.info.children_max` 개 + 넘치면 `+K`. `refresh()` 는 `slime_info` 한 번 + 친척 수만큼 `index_of_id` 만 쓰고, `children_of` 는 (세계, id) 가 바뀌거나 자식 수가 바뀌었고 목록이 한도 미만일 때만 부른다. 지켜보던 개체가 죽으면 마지막 두뇌를 "죽기 직전의 두뇌" 로 남기고, 처음부터 죽은 개체(유전체 없음)는 두뇌 대신 안내 문구. 단추는 초점을 받지 않는다(스페이스 = 멈춤과 겹치지 않게). LabMain 연결: `slime_requested` → `select_slime(id)`, `follow_toggled` → `map_view.follow_selected`.

`BrainView` — `scripts/ui/brain_view.gd` (`class_name BrainView`, Control): `func set_genome(L: Dictionary, genome: PackedFloat32Array) -> void` 가중치 열지도(입력×은닉, 은닉×출력; 양수·음수 색은 `ui.info.heatmap_*`), 입력·행동 이름은 `SimBrain.INPUT_NAMES`·`ACTION_NAMES`.

| 멤버(추가) | 뜻 |
|---|---|
| `var weight_clamp: float` | 색 세기 정규화 상한. `set_genome` 전에 `world.cfg.brain.weight_clamp` 를 넣는다(InfoPanel 이 함) |
| `func set_highlight_action(a: int) -> void`, `func highlight_action() -> int` | 아래 덩어리에서 현재 행동 줄 강조(-1 없음) |
| `var max_width: float` | (추가) 열지도 전체가 들어가야 하는 너비(INF = 제한 없음). InfoPanel 이 `brain_width()` 를 넣는다 |
| `static func size_for(L, max_w := INF) -> Vector2` | 최소 크기: 너비 = `heatmap_label_width` + max(n_in, n_hid)·칸 너비, 높이 = `heatmap_header_height` + n_hid·cell + `heatmap_block_gap` + cell(은닉 번호 줄) + n_out·cell + `heatmap_legend_height`(행 높이 = `heatmap_cell`). `set_genome` 이 `custom_minimum_size` 로 넣음 |
| `static func cell_width_for(L, max_w := INF) -> float` | (추가) 칸 너비 = `heatmap_cell`, 단 `max_w` 안에 들도록 `heatmap_cell_min` 까지 좁힘. 그래도 넘치면(은닉 41 이상) InfoPanel 이 열지도만 가로 스크롤(세로 휠은 바깥으로). 칸이 글자보다 좁으면 열 이름은 몇 칸마다 하나 |
| `func cell_at(pos: Vector2) -> Dictionary` | 그 위치의 칸 `{block: "w1"/"w2"/"input", row, col, weight, text}`(밖이면 `{}`). 풍선 도움말(`_get_tooltip`)이 씀 |
| `static func input_name(i)`, `output_name(q)` | 화면 이름(기본 다음은 `"기억 k"`) |
| `static func weight_color(w, clamp) -> Color` | 음수 색 ← 창 색(0) → 양수 색, 세기 = (abs(w) / clamp)^`heatmap_gamma` |
| `static func legend_texts(clamp) -> PackedStringArray`, `var last_legend` | (검토 고침) 범례 양 끝 글 `["-c", "+c"]` — 상한을 반올림하지 않고 정수면 정수, 아니면 필요한 소수 자릿수(`GraphView.fmt_num`·`decimals_for`, 2.5 → "-2.5"; I44: 예전 "%.0f" 는 2.5 → "±2", 0.5 → "±0" 이라 색 눈금과 어긋났음). 빼기는 '-'(U+002D) — 수학 빼기 '−'(U+2212)는 나눔고딕에 없어 웹에서 네모(J17). `last_legend` = 마지막으로 그린 것(검사: `param_checks` 의 weight_clamp 2.5·0.5·4) |

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

동작: `_process` 에서 `map_view.before_steps()` → 누적 시간만큼 (틱마다 `before_steps()` 뒤) `world.step()`(다음 틱 비용을 미리 더해 보고 프레임당 `ui.speed.sim_budget_ms` 를 넘기 전에 멈춤, 빨리 감기면 `fast_forward_budget_ms` 를 다 씀) → `map_view.update_view(alpha, delta)`. 위쪽 막대: ▶/‖, 1·2·4·8·16·32·64배, ⏩, 표시(틱·날·계절·평균 세대·개체 수·문명 단계·"목표 N배 / 실제 M배"). 사건은 위쪽 알림(`ui.lab.toast_seconds`). 키: 스페이스 = 멈춤, 1~7 = 속도, F = 따라가기, Home·0 = 지도 전체 보기, Esc = 선택 해제. 명령줄(`--` 뒤): `--seed=N`, `--preset=이름`, `--snapshot=경로`.

**구현 메모(3단계, LabMain 담당이 덧붙임)**

- 더한 멤버(4단계·검사·캡처용):

  | 멤버 | 뜻 |
  |---|---|
  | `func advance_frame(delta: float) -> int` | 한 프레임 진행(아래 순서). `_process` 가 부르고, 검사·캡처는 `set_process(false)` 뒤 직접 불러 프레임을 결정적으로 몬다. 이 프레임에 돈 틱 수를 돌려줌 |
  | `func apply_args(args: PackedStringArray) -> String` | 명령줄 인자로 실험 열기(`_ready` 가 `OS.get_cmdline_user_args()` 로 부름). 잘못된 값은 위험 색 알림 + 기본값, 오류 문장들(줄바꿈)을 돌려줌. 모르는 인자는 무시 |
  | `signal world_changed(world: SimWorld)` | `new_experiment`·`open_snapshot` 로 세계가 바뀌었을 때(4단계 그래프·연대기가 지난 기록을 비움) |
  | `func show_toast(text: String, kind := "info", tick := -1) -> void` | 위쪽 가운데 알림. `kind` = 사건 종류 또는 `info`·`warn`·`error`(4단계의 "저장했습니다" 등도 이것으로) |
  | `func visible_toasts() -> Array[Dictionary]` | 보이는 알림 `{kind, text, left, count, group}`(`count` = 묶인 사건 수, `group` = 비교 모드 실험 이름표 — "" 없음) |
  | `func fit_map() -> void` | 지도 전체 보기(Home 키·지도 위 "전체 보기" 단추): `map_view.fit_map()` + 정보 창 따라가기 단추 끔 |
  | `is_paused()`·`is_fast_forward()`·`target_speed()`·`selected_id()`·`speed_text()` | 지금 상태 |
  | `var last_sim_ms: float`, `var last_budget_hit: bool` | 마지막 프레임의 시뮬레이션 시간과 예산을 다 썼는지(성능 기록용) |

- 프레임 순서(`advance_frame`): 알림 시간 줄이기 → `map_view.before_steps()`(**매 프레임**, 멈춰도·틱이 없어도) → 멈춤이 아니면 진행(**틱마다** `before_steps()` → `step()`) → `map_view.update_view(alpha, delta)` → 실제 배속 창에 기록 → 1틱 이상이면 `ticked` → `drain_events()` 가 비어 있지 않으면 `events` + 알림 → 멸종하는 순간이면 멈춤·안내 → `ui.info.refresh_frames` 마다 `info_panel.refresh()` → 위쪽 막대 표시.
  - 보통: `누적 += delta × ticks_per_second_1x × 배속`, 누적 ≥ 1 인 동안 `step()`. 2틱째부터 (지금까지 시간 + 한 틱 비용 추정)이 `sim_budget_ms` 를 넘으면 멈추고 **밀린 몫을 버림**(누적의 소수 부분만 남김 — 밀린 틱이 쌓여 점점 느려지지 않게). 한 틱 비용 추정 = 잰 `step()` 시간의 지수 이동 평균(`speed.step_estimate_alpha`). `alpha` = 누적의 소수 부분(0~1) = 마지막 틱의 진행률.
  - 빨리 감기: 적어도 1틱, 그 뒤 (지금까지 시간 + 한 틱 비용 추정)이 `fast_forward_budget_ms` 안이면 계속 `step()`. 누적은 **1**(= 지금 틱의 끝), 그래서 `alpha = 1` 이고 빨리 감기 중 멈추거나 보통 속도로 돌아가도 그린 자리가 낡지 않는다(다음 보통 프레임은 바로 한 틱 진행).
  - 진행(누적·알림 시간)은 `delta` 를 `ui.speed.max_frame_delta_s` 로 자른 값으로(창을 끌거나 멈칫한 프레임이 한꺼번에 몰아 돌지 않게). 실제 배속 측정은 **자르지 않은** `delta`(창 길이까지)로 — 4FPS 아래에서도 정직하게.
  - 사건은 진행 여부와 관계없이 매 프레임 비움(검사·캡처가 `world.step_n` 으로 직접 진행한 사건도 다음 프레임에 알림).
- 실제 배속 = 최근 `actual_speed_window_s` 동안의 (진행한 틱 몫의 합 ÷ 프레임 시간 합) ÷ `ticks_per_second_1x`. 틱 몫 = 이 프레임의 틱 수 + 누적의 변화(정수 틱이 아니라 소수 몫까지 — 따라가면 정확히 목표 배속, 예산에 걸려 버린 몫은 빠짐), 빨리 감기는 틱 수, 멈춤은 0. 프레임 시간은 `advance_frame` 에 들어온 `delta`(검사에서 결정적). **배속·멈춤·빨리 감기를 바꾸거나 세계를 바꾸면 창을 비운다**(앞 배속의 프레임으로 거짓 "뒤처짐" 경고가 뜨지 않게, 세계를 바꾼 직후 첫 프레임은 넣지 않음). 창이 `WARMUP_FRACTION`(1/4) 차기 전에는 "실제 —", 표시는 `speed.label_refresh_s` 마다 갱신, 창이 `speed.behind_min_fill` 이상 찼고 실제가 목표 × `speed.behind_ratio` 보다 낮으면 경고 색.
- 배치(3단계 기록 — **4단계 배치는 아래 "LabMain 4단계 API" 구현 메모가 대신함**: 정보 창이 세로 전체, 아래 자리 = 왼쪽 자리 + 지도 폭, 자리 접기, 알림은 표지 줄 아래, 비교 모드 멸종·선택)(코드로 만듦, 노드 이름 고정): `Background`(ColorRect) · `Column`(VBox) = `TopBar` / `Middle`(HBox) = `LeftWrap`(PanelContainer `DockPanel`, 폭 `left_panel_width`) ⊃ `LeftDock` | `MapArea`(Control, 늘어남) ⊃ `MapContainer`(SubViewportContainer `stretch`) ⊃ `MapViewport`(`own_world_3d`, `msaa_3d = lab.map_msaa`) ⊃ `MapView` + 지도 위 표지(`MapTitle` 실험 이름·멈춤·`ExtinctBadge` "멸종 · 틱 N"(위험 색)·`FitButton` "전체 보기", `MapHint` 조작 도움말, `Toasts`) | `InfoPanel`(폭 `right_panel_width`) / `BottomWrap`(높이 `bottom_panel_height`) ⊃ `BottomDock`. 두 자리는 자식이 없으면 감싸개째 숨고, 자식을 넣으면(지연 호출로) 보인다. 표지·알림은 마우스를 통과시킨다("전체 보기" 단추만 받음).
- 위쪽 막대: 재생/멈춤·빨리 감기는 **코드로 그린 아이콘**(`UiTheme.icon`, ⏩ 가 나눔고딕에 없음), 멈추면 ▶ 가 경고 색. 속도 단추는 `ButtonGroup`(빨리 감기 중에는 모두 꺼짐, 속도를 고르면 빨리 감기 꺼짐). 상태: 틱 · 날(`tick / day_ticks + 1`) · 계절(봄·여름·가을·겨울 / 계절 없음) · 낮/밤(`light ≥ lab.day_light_threshold`) — 날·계절·빛은 모두 같은 틱(SIM-API: 틱 사이의 `light`·`season` 은 지금 틱) │ 평균 세대(개체가 없으면 "—", 흐린 색) · 개체(0 이면 "멸종", 위험 색) · 문명(`SimWorld.STAGE_NAMES`) …… "목표 N배 / 실제 M배"·"빨리 감기 / 실제 M배"·"멈춤 · 목표 N배". 가장 긴 표시(틱 7자리 등)에서도 최소 창 폭 1280 안(검사).
- 멸종: 멸종하는 순간 한 번 `lab.pause_on_extinction`(기본 켬)이면 멈추고(헤드리스 실행기의 끝 조건과 같게 — 한 프레임에 여러 틱을 돌던 중이어도 **멸종한 틱에서** 남은 틱을 버리고 멈춤, `_extinction_stop`; 4단계 최종 점검: 예전엔 프레임 끝까지 돌아 멸종 다음 틱에서 멈출 수 있었음, 빨리 감기에서 늘 — 검사), 정보 창 빈 안내를 멸종 문구로(`set_empty_text`), 지도 위에 "멸종 · 틱 N" 표지를 계속 보인다. 다시 재생하면 빈 지도가 계속 진행. 멸종 때문에 저절로 멈춘 상태는 새 실험·스냅숏에서 풀리고, 이미 멸종한 스냅숏을 열면 멈추지 않는다.
- 알림: 사건 문장 그대로 + 흐린 "틱 N". 왼쪽 띠 = 종류 색, 발견(`★ 새 발견` 머리)은 강조 색 테두리, 멸종·오류는 위험 색 테두리, 경고(`warn`)는 경고 색 테두리, 밭 잃음은 경고 색 띠만. 긴 문장은 줄을 바꿔 지도 폭 안에(폭 = min(`lab.toast_max_width`, 지도 폭 − 양쪽 `map_overlay_margin`), 빈칸 없는 경로도 끊음). `lab.toast_coalesce_kinds`(밭 잃음)의 종류는 이미 보이는 같은 종류 알림을 새 문장으로 고쳐 쓰고 "×N" 을 붙여 맨 아래로(하나만 보임). 최대 `lab.toast_max` 개 — 넘치면 강조 알림(발견·멸종·오류·경고)이 아닌 것 가운데 오래된 것부터 지우고, 모두 강조면 가장 오래된 것. `toast_seconds`(오류·경고는 `toast_error_seconds`) 뒤 사라지며 마지막 `toast_fade_seconds` 동안 흐려짐. **세계를 바꾸면(새 실험·스냅숏) 앞 세계의 알림을 지운다**(백업 경고는 바꾼 뒤에 띄움). 명령줄 오류는 알림과 함께 터미널(`printerr`)에도 전체 문장.
- 선택: `map_view.slime_clicked(id)` → `select_slime(id)`(-1·없는 id = 해제; 죽은 개체 id 는 기록으로 표시), `info_panel.slime_requested(id)` → `select_slime(id)` + `map_view.focus_on(id)`, `info_panel.follow_toggled(on)` → `map_view.follow_selected = on`.
- 단축키는 `_input` 에서 받아 처리하면 소비한다(초점 있는 단추가 스페이스를 먹지 않게). **글자를 적을 수 있는 `LineEdit`·`TextEdit` 에 초점이 있거나 Ctrl·Alt·Meta 가 눌렸으면 무시**(읽기 전용 칸은 해당 없음). 1~7 은 숫자판 키도. F 는 `map_view.follow_selected` 를 뒤집고 알림, 정보 창의 따라가기 단추도 `info_panel.set_follow()` 로 맞춘다(통합 때 연결).
- **글 칸 초점 풀기(4단계 검토 반영):** 글 칸에 초점이 있을 때 그 칸 밖(지도·단추·다른 패널)을 마우스(왼쪽·오른쪽·가운데 단추, 휠은 아님)로 누르면 `_input` 이 초점을 푼다(SpinBox 안의 칸이면 화살표를 포함한 SpinBox 전체를 칸 안으로 보고, 그 SpinBox 는 지금 확정 — 엔진은 지연 호출로 확정해 같은 누름의 "새 실험" 이 옛 씨앗을 썼음). 단추·지도는 초점을 받지 않아 엔진이 초점을 풀지 않으므로, 고치기 전에는 씨앗을 적고 새 실험·지도를 눌러도 단축키가 꺼진 채 스페이스·숫자가 칸에 들어가 다음 실험에 확정됐다("42" → "42 4"). 검사 `lab_checks._focus_release`(실제 마우스·키 입력).
- 날 표시에 하루 틱 수가 필요해 `world.cfg.time.day_ticks` 를 읽기만 한다(SIM-API 의 읽기 전용 `cfg` 항목). InfoPanel 도 `cfg.brain.weight_clamp` 만 읽는다. `tools/test_repo_rules.py` 가 화면이 쓰는 세계 멤버가 모두 SIM-API 에 있는지 검사한다.
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
| `keep_words(text)` · `plain_text(text)` · `WORD_JOINER` | (4단계 통합) 한국어 낱말 단위 줄바꿈: 빈칸이 아닌 글자 사이에 낱말 잇개(U+2060, 폭 0)를 넣어 ICU 가 한글 음절 사이("발/견")에서 끊지 않게 / 빼서 되돌림. 알림 본문·파라미터 패널 "지금 실험" 이 씀(검사 integration4_checks) |

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

- 모듈마다 `const MIN_CHECKS := N`(이 모듈이 적어도 하는 검사 수)을 둡니다. Godot 4.4 는 스크립트 오류가 난 함수만 멈추고 계속 돌기 때문에, 검사 수가 그보다 적으면 실행기가 그 모듈을 실패로 셉니다. CI 는 화면 검사 로그에 `SCRIPT ERROR`·`ERROR:` 가 한 줄이라도 있으면 실패로 봅니다.
- 실행기 도움 함수: `t.node(부모, 경로)`(없으면 실패로 세고 null — 이름이 바뀐 노드를 건드려 끊기지 않게), `t.same_state(세계 A, 세계 B)`(틱·해시·개체·에너지·유전체·먹이 배열·연대기 수를 견줘 다른 것의 이름, 같으면 ""). 역사 해시는 `hash.every`(100)틱마다만 바뀌므로 "화면을 거쳐도 같음" 검사는 검사점을 지나거나 상태 배열을 직접 견줍니다.
- `--verbose` 는 통과한 검사도 출력, 끝의 PASS/FAIL 줄에 모듈별 검사 수.

## 캡처 — `tests/ui_driver.gd` (LabMain 담당)

`xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/ui_driver.gd -- --out=폴더` 로 실험실 장면을 띄워 시나리오(전경·가까이·개체 선택+정보 창·밤·농사 단계)를 진행·캡처하고, 동작(클릭 → 정보 창 id, 속도 바꾸기, 화면 진행 중 역사 해시가 헤드리스와 같음)을 확인해 `RESULT: N passed, M failed (ui)` 를 출력합니다.

**구현 메모(3단계)**: (4단계 통합: ②·③ 의 진행은 세계를 직접 `step()` 하지 않고 `lab.step_ticks` 로 — 기록·`recorded` 가 따라가 그래프·연대기가 세계와 맞음. 직접 돌리면 그래프가 첫 줄에 멈춘 채 찍혔음.) `--out` 기본값 `res://docs/screenshots/v0.1`, `--copy=폴더` 를 주면 그림을 그곳에도 복사. 프레임은 `advance_frame(1/60)` 으로 몬다(④만 실제 `_process`).
① `lab-01-overview` 기본·씨앗 1 을 8배로 600프레임(480틱) → 해시 비교, 지도 클릭(화면 가운데에 그린 개체를 몸 가운데 높이로 투영 → `pick_slime` 이 바로 그 개체여야 하고, 실제 마우스 입력으로 눌러 정보 창·선택 id 확인, 지도 모서리 클릭 → 선택 해제), 재생·속도·빨리 감기 단추 클릭, 스페이스. ② `lab-02-farm-selected` demo_fast·씨앗 1 을 농사 단계 + 밭 3칸까지(약 1,670틱) → 해가 다 뜰 때까지 진행(낮 장면) → 밭에서 2·4·6칸 안(가까운 것부터)에 있고 남은 수명이 90틱 이상인 개체 가운데 자식이 가장 많은 개체 선택·`focus_on` → 쌓인 사건 알림, 정보 창이 스크롤 없이 두뇌 범례까지(V07, 1600×900 에서 여유 `info.min_vertical_slack` 이상). ③ `lab-03-night` 밤까지 진행 → 같은 개체로 다시 `focus_on`(②와 같은 자리를 낮·밤으로 견줌) → 멈춘 모습. ④ `lab-04-speed64` 64배 단추 클릭 → 실제 시간 150프레임 → "목표 64배 / 실제 M배" 와 해시 비교. 그림은 JPG(품질 0.85, 600KB 이하 확인). 그림 폴더 `docs/screenshots/` 에는 `.gdignore`(가져오기 제외).

## 성능 측정 — `tests/perf_capture.gd` (통합)

- 헤드리스 미세 측정: `godot --headless --path . --script res://tests/perf_capture.gd -- --bench` — 1260×856 SubViewport 의 MapView 에 대해 프레임마다 `before_steps` + `update_view` 시간(틱 있는 프레임·없는 프레임 따로, 중앙·95%·최대)과 시뮬레이션 시간을 1·4·64배(60fps 가정)로 잰다. 세계: 기본 `population.initial = 250`(씨앗 11), demo_fast 1,760틱(씨앗 1).
- 실험실 실측: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/perf_capture.gd [-- --seconds=N --msaa=N --only=base,rows,compare]` — 기본·씨앗 1 을 1,500틱 넘게, 개체 200 이상이 될 때까지 진행한 뒤 1배·64배로 각 N초(기본 10) 실제 시간 진행. `LabMain.advance_frame` 을 실제 프레임 시간으로 직접 불러 FPS·프레임 시간·우리 스크립트 시간(시뮬레이션 `last_sim_ms` + 화면·UI 나머지)·그리기 호출·기본 도형 수를 출력한다. 그리기 호출은 전체(모든 뷰포트 합)와 함께 **뷰포트별**로: 지도 SubViewport(3D)의 그리기 호출·기본 도형, 뿌리 창 2D(UI)의 그리기 호출. `--msaa` 는 지도 MSAA 를 바꿔 잰다. llvmpipe(CPU 소프트웨어 GL)에서는 그리기 몫이 대부분이라 실제 GPU 의 FPS 를 뜻하지 않는다.

- **4단계(통합 때 넓힘):** 자리를 모두 편 실험실에서 장면 셋을 1배·64배로 잰다 — ㉮ 위의 3단계 장면(세계를 `lab.step_ticks` 로 키워 기록·그래프·연대기가 따라감)과 같은 세계를 자리 둘 다 접고(지도 1260×856 = 3단계 크기) 한 번 더, ㉯ 기록 5,000줄 혼자(기본·씨앗 1·`record.every` 2·10,000틱), ㉰ 기록 5,000줄씩 비교(씨앗 1 | 2). 줄마다 그래프 다시 그리기 횟수·세 그래프 `_draw` 합(GraphView `last_draw_us`)·묶음 새로 만들기 횟수를 더 적는다. 연대기 `_draw` 는 따로 재지 않는다(보이는 줄만 그림). `record.every` 2 는 64배에서 프레임당 새 줄이 기본(20)의 10배인 무거운 쪽이다.

# 4단계 계약 — 파라미터·그래프·연대기·내보내기·비교

## Experiment — `scripts/ui/experiment.gd` (`class_name Experiment`, RefCounted) — 완성(바꾸지 않음)

세계 + 기록기 + 만든 조건. 기록은 헤드리스 실행기와 **같은 줄**(만들 때 한 줄, `tick % record.every == 0` 이 되는 step 마다 한 줄, **멸종한 틱에 한 줄** — 실행기는 멸종에서 멈추며 끝 줄을 쓰고, 그래프의 개체 수 0 줄·"멸종" 표시도 이 줄에서). **멸종한 틱 뒤로는 기록하지 않는다**(세계는 빈 채 더 진행할 수 있음 — 비교 모드에서 한쪽만 멸종했거나 멸종해 멈춘 뒤 다시 재생했을 때). 내보낼 때 마지막 기록 줄이 지금 틱이 아니고 멸종하지 않았으면 `tail_row()` 를 timeseries.csv 에만 더한다(실행기가 그 틱에서 끝나며 쓰는 줄). 그래서 내보낸 timeseries.csv 는 같은 씨앗·설정으로 그 틱까지(멸종했으면 멸종까지) 돌린 실행기 결과와 글자까지 같다 — `tests/view/experiment_checks.gd` 가 배수 틱·배수가 아닌 틱·멸종해 저절로 멈춘 틱·멸종 뒤 더 진행한 틱·비교 모드에서 한쪽만 멸종한 `A/`·`B/` 모두 검사(4단계 검토 반영: 전에는 배수 틱만 같았고, 멸종해 멈춘 실험의 그래프에 멸종 표시가 없었음. 4단계 최종 점검: 비교 모드에서 멸종한 쪽이 개체 0 줄을 계속 쌓아 그쪽 CSV 가 실행기와 달랐음).

| 멤버 | 뜻 |
|---|---|
| `static create(preset, overrides, seed) -> {experiment, error}` · `static from_snapshot(path) -> {experiment, error, status}` | 만들기 |
| `world`, `recorder`, `preset`, `overrides`, `seed_value`, `snapshot_path`, `label`, `tag`("A"/"B"/"") | 상태(읽기 전용) |
| `step() -> bool`(이번에 기록했으면 true) · `step_n(n)` | 진행(LabMain 만 부름) |
| `rows() -> Array` | 기록한 시계열 줄(`SimRecorder.TIMESERIES_COLUMNS` 키 사전). **읽기 전용** |
| `display_name()` | "A · 기본 · 씨앗 1 · 돌연변이 0.08"(혼자면 label) |
| `label` = `static default_label(preset, overrides, seed, first := [])` | (4단계 검토 반영) "예설정 이름 · 씨앗 N · 바꾼 값": 세 주요 값은 짧은 이름(`SHORT_NAMES` = 파라미터 패널 "지금 실험" 줄의 말 "돌연변이 0.08"·"자원 1.4"·"개체 150"), 나머지는 "키=값"(plants.regrow=0.5), 최대 `ui.lab.label_max_overrides`(2)개 + "외 K개"(`overrides_brief`). 수는 파라미터 패널 입력 칸과 같은 표기(`describe_value` → `ParamPanel.format_value`: 정수 키는 150, 실수는 JSON 표기 — 4단계 최종 점검: 예전엔 0.123456789012345 를 0.12345678901234 로 줄여 입력 칸과 달랐음). 순서: `first` → 세 주요 값 → 키 이름 순. 비교 모드에서 LabMain 이 A·B 가 다른 키(`differing_keys`)를 `first` 로 다시 지어 값만 다른 비교도 이름(범례·지도 표지·창 제목·지금 실험·summary.json)이 갈린다(전에는 둘 다 "… · 바꾼 값 1개"). 스냅숏 = "스냅숏 파일 · 씨앗 N" |
| `export_dir(dir, with_lineage := true) -> PackedStringArray` | summary.json(`source = "lab"`, `rows` = 파일의 줄 수)·timeseries(+ 끝 줄)·chronicle·lineage·final.snapshot.json, 실패한 파일 이름 |
| `tail_row() -> Dictionary` | 내보낼 때 더하는 끝 줄(마지막 기록 줄이 지금 틱이거나 멸종했으면 `{}`). `sample()` 은 기간 출생·사망 수를 0 으로 되돌리므로 세계 **사본**(`SimSnapshot.to_text`/`from_text` 왕복 — 기간 카운터까지 담김)에서 부른다: 세계·기록기·다음 기록은 그대로(검사) |
| `save_snapshot(path) -> String` | 스냅숏 저장 |

## LabMain 4단계 API (LabMain 담당이 비교 모드를 채움)

| 멤버 | 뜻 | 상태 |
|---|---|---|
| `var experiments: Array[Experiment]` · `experiment(index)` | 진행 중인 실험(혼자 1개, 비교 2개 [A, B]). `world` = `experiments[0].world`, `map_view` = A 의 지도 | 됨 |
| `signal experiments_changed(list: Array)` | 실험 목록이 바뀜(새 실험·스냅숏·비교 시작/끝) — 패널은 처음부터 다시 읽음 | 됨 |
| `signal recorded(index: int, row: Dictionary)` | index 번째 실험이 한 줄 기록 | 됨 |
| `signal events_tagged(index: int, list: Array)` | index 번째 실험의 새 사건(사본). `events(list)` 는 A 만(3단계 호환) | 됨(A·B) |
| `signal cursor_tick_requested(tick: int)` · `func request_cursor(tick)` | 그래프 시점 표시 요청(연대기 → 그래프), -1 = 지움 | 됨 |
| `func new_experiment(preset, overrides, seed) -> String` · `open_snapshot(path)` | 혼자 모드로 바꿔 시작 | 됨 |
| `func start_compare(a: Dictionary, b: Dictionary) -> String` | a·b = `{preset, overrides, seed}`. 지도 둘을 나란히(A 왼쪽 · B 오른쪽, 사이 `ui.compare.gap_px`), 같은 배속으로 틱마다 A 다음 B 를 진행(예산은 둘 몫을 합쳐 셈), 사건 알림 앞에 "A · "/"B · " | 됨 |
| `func stop_compare()` · `func is_comparing() -> bool` | 비교 끝(A 만 남김) | 됨 |
| `func select_slime(id, index := 0)` | 비교 모드에서 어느 실험의 개체인지(정보 창 머리에 A/B 표시, 그 지도에만 고리) | 됨 |
| `func save_snapshot(path, index := 0) -> String` | 스냅숏 저장 + 알림 | 됨 |
| `func export_csv(dir) -> String` | 결과 폴더 내보내기(비교면 `dir/A`·`dir/B`) + 알림(절대 경로). 실패 문장 "내보내기 실패: 파일들" — 비교 모드면 파일마다 "B/timeseries.csv" 처럼 실험 이름표, 다 쓴 쪽은 "(A 는 저장됨: 절대 경로)"(4단계 검토 반영) | 됨 |
| `func default_export_dir() -> String` | `user://experiments/<날짜-시각>-seed<N>`(비교 모드 `-seed<A>-vs-seed<B>`) | 됨 |
| `func step_ticks(n)` | 프레임 없이 모든 실험 n틱(기록·`recorded` 포함, 검사·캡처용) | 됨 |
| 자리 채우기 | `_ready` 에서 `ParamPanel` → `left_dock`, `GraphPanel`(늘어남) + `ChroniclePanel`(폭 `ui.chronicle.width`, 좁은 창에서는 아래 메모대로 줄임) → `bottom_dock`, `LabSound` → 자식. 각각 `bind_lab(self)` | 됨 |

**구현 메모(4단계, LabMain 담당이 덧붙임 — 3단계 메모의 배치·알림 위치·멸종·선택 설명을 이것으로 고쳐 읽음)**

- 더한 멤버:

  | 멤버 | 뜻 |
  |---|---|
  | `var param_panel: ParamPanel` · `graph_panel: GraphPanel` · `chronicle_panel: ChroniclePanel` · `lab_sound: LabSound` | 자리에 넣은 패널(노드 이름도 같음: `LeftDock/ParamPanel`, `BottomDock/GraphPanel`·`BottomDock/ChroniclePanel`, `LabSound`) |
  | `func map_view_of(index) -> MapView` | index 번째 실험의 지도(0 = A = `map_view`, 1 = B, 없으면 null) |
  | `func selected_index() -> int` | 선택한 개체의 실험 번호(선택 없으면 -1) |
  | `static func tag_color(index) -> Color` | 실험 색 = 그래프 계열 색(`ui.graph.series_a`·`ui.graph.series_b`) — 이름표 바탕에 씀. 연대기 A/B 표시도 이것을 쓰면 색이 한 벌 |
  | `func set_dock_open(which, open)` · `is_dock_open(which)` · `const DOCK_LEFT = "left"`, `DOCK_BOTTOM = "bottom"` | 자리 펴기·접기(지도 오른쪽 아래 단추와 같음). 처음 값 `ui.lab.left_dock_open`·`ui.lab.bottom_dock_open` |
  | `func fit_map(index := -1)` | 지도 전체 보기: -1(Home·0 키) = 모든 지도, 지도 위 "전체 보기" 단추 = 그 지도만 |
  | `func show_toast(text, kind, tick, group := "")` | `group` = 비교 모드 이름표. 밭 잃음 묶기는 같은 종류·같은 group 끼리만(검사 `lab_checks._toast_rules`). 비교 모드에서 group 이 있는 알림은 그 지도 칸에(아래 "비교 모드 알림") |
  | `func view_turns(index) -> int` · `const ARROWS` | (4단계 검토 반영) index 번째 지도 화면이 북쪽 위에서 90° 씩 돈 수(0~3). 지도 나침반·정보 창 방향 화살표가 씀 |

- **배치(노드 이름 고정)**: `Column`(VBox) = `TopBar` / `Body`(HBox) = `Main`(VBox: `Middle`(HBox: `LeftWrap` ⊃ `LeftDock` | `MapArea`) / `BottomWrap` ⊃ `BottomDock`) | `InfoPanel`. 정보 창은 아래 자리 옆까지 세로 전체(1600×900 에서 두뇌 범례까지 스크롤 없이 — V07), 아래 자리 폭 = 왼쪽 자리 + 지도. 1280×720·자리 모두 펼침: 지도 680×456, 비교 모드 한 칸 338×456(검사 ≥ 320×400).
- **지도 칸**: `MapArea` ⊃ `MapContainer`(A) [· `MapContainerB`] ⊃ `MapViewport`(`own_world_3d`) ⊃ `MapView` — 위치·크기를 코드로(픽셀 정수, `MapArea.resized` 마다): 혼자 = 자리 전체, 비교 = 반씩(사이 `ui.compare.gap_px`, 남는 1px 은 B). B 칸·표지는 `start_compare` 때 만들고, 혼자로 돌아가면(`stop_compare`·`new_experiment`·`open_snapshot`) 트리에서 바로 빼서 지운다. 지도 클릭은 `select_slime(id, 칸 번호)`.
- **지도 위 표지**: 칸마다 왼쪽 위 `MapTitle`/`MapTitleB` = [`Tag` 이름표(비교 모드만: 실험 색 바탕 `ui.compare.tag_radius`·`ui.compare.tag_pad_h`·`ui.compare.tag_pad_v`, 어두운 굵은 글자 — 글자 자체에는 실험 색을 입히지 않음)] `Title` 실험 이름(칸 폭에 맞춰 줄임: 예설정 이름만 "…" 로 줄이고 " · 씨앗 N · 바꾼 값" 꼬리는 남김 — `GraphPanel.split_name`, 꼬리도 길면 `static fit_tail(tail, room, wid, seed_shared)`: 예설정 이름을 빼고 꼬리 끝을 줄이되 두 지도를 가르는 첫 몫은 남김 — 씨앗, 단 비교 모드에서 A·B 씨앗이 같으면(`MapPane.seed_shared`) 씨앗을 빼고 A·B 가 다른 첫 바꾼 값("… · 돌연변이 0.08"), 그 몫도 길면 값은 두고 이름을 줄임("… · 돌연… 0.08", "… · plants…=0.5"), 그것도 안 되면 끝을 자름; 전체 이름은 `MapPane.full_title`. 4단계 최종 점검: 예전엔 씨앗을 남기고 값을 잘라 값만 다른 비교가 1280 창·멈춤에서 둘 다 "… · 씨앗 1 · 돌연…" — lab_checks "좁은 비교 지도 이름(씨앗 같고 …)". 4단계 검토 G33 의 지도 몫, 통합 때: 예전엔 끝을 잘라 1280 창에서 씨앗만 다른 비교의 두 이름이 같아 보였음 — lab_checks "좁은 비교 지도 이름") · 멈춤 · `ExtinctBadge`(그 실험) · `FitButton`(그 지도). 공용: 왼쪽 아래 `MapHint`(넓으면 한 줄, 좁으면 마우스·키 두 줄, 더 좁으면 키 줄을 나눈 세 줄 — 비교 모드에서는 A 칸에 들어가는 가장 적은 줄로 A 칸 안: 1280 창·자리 펼침은 세 줄, 통합 때 더함), 오른쪽 아래 `DockToggles`(`LeftToggle` "실험 조건"(그 패널의 제목과 같은 말 — 4단계 검토 반영, 전에는 "설정") · `BottomToggle` "그래프·연대기", 눌림 = 보임, 자식이 있는 자리만), 알림 `Toasts` 는 표지 줄 아래 `ui.lab.toast_margin_top` 에서 시작(좁은 지도·비교 모드에서 표지를 가리지 않게).
- **비교 모드 알림(4단계 검토 반영):** 실험 알림(group "A"/"B" — 사건·F 키)은 그 지도 칸 가운데 위의 칸마다 묶음 `ToastsA`/`ToastsB` 에, 폭 = min(`lab.toast_max_width`, 칸 폭 − 양쪽 `map_overlay_margin`) 안에서 줄바꿈하고, 앞머리 "A · " 대신 지도 표지와 같은 실험 색 이름표 상자(`Tag`)를 그린다(`visible_toasts()` 의 text 는 "A · …" 그대로). 이름표 없는 알림(저장·내보내기·오류)은 공용 `Toasts`(지도 자리 가운데)에, 칸 알림이 있으면 그 아래. 고치기 전에는 알림 하나가 두 지도 사이 가운데에 걸쳐 두 지도 위쪽을 함께 가렸다. 최대 수 `lab.toast_max` 는 모두 합쳐, 칸마다는 `lab.toast_max` ÷ 칸 수(2)개까지(좁은 칸에서 줄바꿈해 길어진 알림이 그 지도를 다 덮지 않게 — 오래된 일상 알림부터 지움), 칸 알림의 발견 머리는 "★" 만. 검사 `lab_checks._compare_toasts`, 캡처 ⑥ 은 쌓인 알림을 그대로 둔 채 찍음.
- **비교 모드 지도 방향(4단계 검토 반영):** 1280 창의 비교 칸(약 338×456)처럼 세로로 긴 칸에서는 64×48 지도를 북쪽 위 그대로 맞추면 칸 높이의 약 39% 만 썼다. 비교 모드 지도는 `ui.compare.portrait_yaw_deg`(90°) 돌린 방위로도 맞춰 보고 `ui.compare.portrait_gain_min`(1.15)배 이상 크게 보이면 그 방위로(`OrbitCamera.portrait_yaw` — Home·"전체 보기"도 같은 방위, 두 칸 같은 크기라 A·B 같은 방향). 화면 위가 북쪽이 아니면 표지에 나침반 `North` "북 →"(사용자가 오른쪽 끌기로 돌렸을 때도), 정보 창 "방향" 화살표도 화면 방향(`InfoPanel.set_view_turns`). 혼자 모드는 북쪽 위(비교를 끝내면 카메라를 움직이지 않은 지도는 다시 북쪽 위로 맞춤). 검사 `lab_checks._compare_portrait`(지도가 칸 높이의 55% 이상, 두 지도 같은 방향, 나침반·방향 화살표).
- **자리**: 자식이 있고 접지 않았을 때만 보인다(접은 자리는 자식이 들어와도 숨긴 채, 패널을 모두 빼면 접기 단추도 숨음 — 검사).
- **패널 붙이기**: `_ready` 에서 배치 → 패널을 자리에 넣고 `bind_lab(self)` → 명령줄로 첫 실험. 즉 **`bind_lab` 때 `experiments` 는 비어 있고 `world` 는 null**, 첫 `experiments_changed` 가 곧 온다(패널은 그때 읽으면 됨). 크기: ParamPanel 세로 늘어남, GraphPanel 가로·세로 늘어남, ChroniclePanel 세로 늘어남·최소 폭 = (창 폭 − 정보 창 − 아래 자리 여백) × `ui.chronicle.dock_frac` 를 [`ui.chronicle.min_width`, `ui.chronicle.width`] 로 자르고 그래프 최소 폭이 들어가게 더 줄인 값(창 크기가 바뀔 때마다, 통합 때 더함 — 1600 창 420, 1280 창 331). 고정 420 이면 1280 창에서 연대기 420 + 그래프 최소 540 이 아래 자리 920 을 넘어 정보 창이 창 밖으로 46px 밀렸다(검사 `_fits_window`).
- **진행**: 프레임 처음과 틱마다 **지도마다** `before_steps()`, 한 틱(`_step_once`) = A.step() 다음 B.step()(기록하면 `recorded(k, 줄)`), 프레임 끝에 지도마다 `update_view(alpha, delta)`. 한 틱 비용 추정 = 두 실험 step 시간의 합이라 예산(`ui.speed.sim_budget_ms`·빨리 감기)은 둘 몫을 합쳐 센다. 두 세계는 언제나 같은 틱(검사: 프레임마다 같은 틱 수, 두 해시·상태가 헤드리스와 같음).
- **사건**: 실험마다 `drain_events()` → `events_tagged(k, 사본)`, A 는 `events(사본)` 도. 깊은 사본은 **signal 마다 하나**라 청취자가 고쳐 써도 알림·연대기·다른 signal 의 청취자는 그대로(검사 `lab_checks._events`). 같은 signal 의 청취자끼리는 같은 배열을 받으므로 고쳐 쓰지 않는다(꾸미려면 먼저 복사 — ChroniclePanel·LabSound 는 읽기만, 4단계 검토 반영: 전에는 "받는 쪽마다 따로" 라고 잘못 적었음). 비교 모드 알림 = "A · 문장"/"B · 문장"(`visible_toasts()` 의 text 도, group = "A"/"B").
- **선택**: 고리는 그 실험의 지도에만, 정보 창 머리 이름표 = `InfoPanel.set_tag(tag, tag_color(index))`(혼자면 ""; InfoPanel 에 더한 것은 `set_tag(tag: String, col := 투명 → 강조 색)` · `current_tag() -> String` 둘뿐, 머리 `#id` 앞 실험 색 상자). `clear()`(Esc·해제·비교 끝)는 이름표도 지워 `current_tag()` = ""(4단계 검토 반영 — 전에는 빈 창이 "B" 를 돌려줌). 가계 단추는 같은 실험 안에서 옮겨 가며 그 지도에서 카메라를 맞춤. 따라가기(정보 창 단추·F 키)는 선택한(선택이 없으면 마지막으로 선택했던) 실험의 지도에서; 다른 실험의 개체를 고르면 앞 지도의 따라가기를 끄고 단추를 새 지도 상태로. F 알림은 비교 모드면 "A 지도 따라가기 켬". Esc·빈 곳 클릭·없는 실험 번호 = 해제(모든 지도의 고리 지움).
- **멸종(비교 모드)**: 한쪽만 멸종하면 **멈추지 않는다** — 살아남은 쪽을 같은 틱으로 계속 견주게(그 순간은 "A · 멸종 …" 위험 색 알림과 그 지도의 `ExtinctBadge` 로 남음). **모든 실험이 멸종하면** `lab.pause_on_extinction` 대로 멈춘다(혼자 모드 = 3단계와 같음). 정보 창 빈 안내(두 줄): "A 는 멸종했습니다 (틱 N)\nB 지도에서 고르세요" / "A·B 모두 멸종했습니다\n고를 개체가 없습니다".
- **위쪽 막대(비교 모드)**: 평균 세대·개체·문명 대신 `[A] 개체 · 문명 │ [B] 개체 · 문명`(이름표 = 실험 색 상자, 평균 세대는 그래프에서). 틱·계절·낮밤은 두 실험이 같으면 하나, 다르면 "A값/B값"(예: 혹독한 겨울과 견주면 "여름/봄"); 하루 길이가 달라(고급 설정) 날이 다르면 "날" 은 숨긴다(틱이 기준). 가장 긴 경우에도 최소 창 폭 안(검사).
- **`stop_compare()`**: A 의 실험·세계·기록·카메라·(A 의) 선택은 그대로 두고 이름표를 지우고 B 를 버린다. `experiments_changed([A])`(세계는 그대로라 `world_changed` 없음), 이름표(group) 붙은 알림 — 사건 "A · / B · "·비교 모드 F 키 알림 — **만** 지우고(이름표 없는 오류·저장 알림은 남음, 이름도 혼자 모드 순서로 — 4단계 검토 반영, 전에는 알림을 모두 지웠음, 검사) "비교를 끝냈습니다 — … 만 계속합니다" 알림, 한 틱 비용 추정·실제 배속 창은 다시 잰다. 비교 중이 아니면 아무것도 안 함.
- **`start_compare` 오류**: 빠진 키는 기본(`lab.default_preset`·`{}`·`lab.default_seed`), 만들기 실패면 "A: 문장"/"B: 문장"을 돌려주고 지금 실험은 그대로.
- **캡처(`tests/ui_driver.gd`)**: ⑤ `lab-05-panels` 기본·씨앗 1 을 `step_ticks(1200)` 뒤 4배로 그림 — 패널 자리 이름, "그래프·연대기" 단추를 실제 마우스로 눌러 접었다 폄, 해시·기록 줄 수. ⑥ `lab-06-compare` demo_fast | 기본(씨앗 1)을 `step_ticks(1500)` → 두 해시가 헤드리스와 같음 → 2배로 그리며 쌓인 알림 이름표 확인 → B 지도 가운데 개체를 실제 마우스로 눌러 고름(실험 번호 1, 정보 창 이름표 B, 고리는 B 지도에만) → 쌓인 알림을 그대로 둔 채(실험 알림이 모두 자기 지도 칸 안 — 확인) 찍음. 두 지도는 같은 방향(1280 창에서는 돌려 맞춤, 나침반 "북 →").

## ParamPanel — `scripts/ui/param_panel.gd` (`class_name ParamPanel`, VBoxContainer, 왼쪽 자리)

- `func bind_lab(lab: LabMain)` — `experiments_changed` 를 받아 "지금 실험" 값을 표시.
- 칸: 예설정(OptionButton, `label`) · 씨앗(글 칸 — 64비트 정수, "무작위" 단추 — 0~`ui.param.seed_max` 에서 화면 쪽 시각으로 고름, 시뮬레이션 난수와 무관) · **돌연변이율**(`mutation.rate`, 슬라이더+숫자) · **자원량**(`resources.scale`) · **초기 개체 수**(`population.initial`) · "고급 설정"(접힘: `sim-defaults.json` 의 수·참거짓 잎 키를 절별로, 바꾼 값은 강조) — 값의 기본은 고른 예설정이 적용된 값. 값을 바꿔도 지금 실험에는 적용되지 않고 "새 실험을 눌러 적용 · 바꾼 값 N개" 표시.
- 단추: **새 실험**(AccentButton) → `lab.new_experiment(...)`(오류는 패널 안 빨간 글 + 알림) · 되돌리기(예설정 값으로) · **비교 모드**(켜면 B 칸이 나타남: 예설정·씨앗·세 값, "나란히 시작" → `lab.start_compare(a, b)`, 끄면 `lab.stop_compare()`) · **CSV 내보내기**(`lab.export_csv(lab.default_export_dir())`) · **스냅숏 저장 / 열기**(FileDialog, 파일 시스템, 시작 폴더 `user://experiments`, `.json`) · 소리 켜기(`LabSound.enabled`, 있을 때).
- `func current_settings(which := 0) -> Dictionary` = `{preset, overrides, seed}`(which 1 = B 칸) · `func set_value(key: String, value, which := 0)` · `func apply() -> String`(새 실험 단추와 같음) — 검사용.
- 수치(범위·폭·간격)는 `ui.param`.

**구현 메모(4단계, ParamPanel 담당이 덧붙임)**

- 더한 멤버(검사·캡처·통합용):

  | 멤버 | 뜻 |
  |---|---|
  | `set_value(key, value, which := 0) -> String` | 돌려주는 값 = 이 값의 오류 또는 그 칸 조건의 오류(`""` = 문제 없음). 특별 키 `"preset"`(예설정 이름)·`"seed"`. 글자 값은 칸에 적은 것처럼 해석 |
  | `apply_compare() -> String` | "나란히 시작" 단추와 같음: `lab.start_compare(current_settings(0), current_settings(1))`, 오류는 패널 안 빨간 글 + 알림 |
  | `revert()` · `set_compare_mode(on)` · `is_compare_mode()` | 되돌리기·비교 모드 단추와 같음(`apply()`·`apply_compare()`·`set_compare_mode()` 는 묻지 않음 — 확인 대화 상자는 단추에만) |
  | `export_to(dir) -> String` | CSV 내보내기 단추가 `lab.default_export_dir()` 로 부르는 함수(검사는 임시 폴더로) |
  | `open_snapshot_dialog(save) -> FileDialog` · `save_snapshot_to(path)` · `open_snapshot_from(path)` | 스냅숏 대화 상자 띄우기, 고른 파일로 저장·열기(대화 상자의 `file_selected` 가 부름) |
  | `random_seed(which := 0) -> int` | "무작위" 단추와 같음 |
  | `set_advanced_open(on)` · `set_advanced_target(which)` | 고급 설정 펼치기, 비교 모드에서 고급 설정이 보여 줄 칸(A/B) |
  | `status_text()` · `error_text()` · `now_text()` · `field_text(key, which)` · `is_highlighted(key, which, advanced)` · `row_error(key, which, advanced)` · `control(id)` | 상태 줄·오류 글·"지금 실험" 글·칸 글자·강조·줄 아래 오류(`"seed"` = 씨앗 칸 아래)·노드 찾기(`"apply"`, `"footer"`, `"seed:0"`(씨앗 글 칸 `LineEdit`), `"slider:<키>:0"`, `"adv:<키>"`, `"adv_name:<키>"`, `"card_side:1"`, `"confirm_dialog"`, `"overwrite_dialog"` 등 — 주석 참고) |
  | `static leaf_kind(key)` · `leaf_keys()` · `format_value(key, v)` | 설정 잎 키 종류(`int`·`float`·`bool`·`other`)·목록·값 글자 |
  | `static key_label(key) -> {name, unit, range, help}` · `key_help(key) -> String` | 잎 키의 한국어 이름표(`config/sim-labels.json`, 없으면 `{}`)·고급 설정 말풍선 머리("이름 — 뜻" + "단위 · 범위") |
  | `var confirm_discard_ticks: int` | 이만큼 이상 돈 실험을 버리는 단추 동작은 먼저 물음(처음 값 `ui.param.confirm_discard_ticks`, 0 = 묻지 않음 — 검사가 낮춰 봄) |
  | `var stats_tip_builds`·`stats_diff_evals` | 검사용 계수: 고급 설정 말풍선을 만든 줄 수, "지금 실험과 다른가" 를 견준 수 |
  | `var snapshot_dir` · `snapshot_paths(path) -> PackedStringArray` | 스냅숏 대화 상자의 시작 폴더(처음 값 `SNAPSHOT_DIR` = `user://experiments` — 검사는 프로세스마다 다른 임시 폴더로 바꿔 공용 폴더를 만들지 않음, 검토 고침 I37) · 고른 경로로 실제로 쓰는 파일(혼자 `[path]`, 비교 중 `[<이름>-A.json, <이름>-B.json]`) |
  | `static keyboard_focus(c, ring := false)` · `static release_button_focus(panel, event)` · `static style_dialog(d)` | 키보드로 닿는 단추·고르기 상자 만들기(아래 "입력" — 그래프·연대기 패널도 씀), 패널 `_input` 이 왼쪽 누름에서 단추 초점 풀기, 대화 상자를 실험실 모양으로(아래 "실험을 버리기 전 확인") |
  | `TEXT_SAME`·`TEXT_PENDING`·`TEXT_PENDING_COMPARE`·`TEXT_COMPARE_IDLE`·`TEXT_NEXT`·`TEXT_NEXT_COMPARE`·`TEXT_COL_NEXT`·`COL_SIDES`·`MAIN_KEYS`·`KIND_*`·`SNAPSHOT_DIR`·`LABELS_PATH` | 상태 줄 문구·칸 위 제목(혼자/비교)·칸 머리("다음 조건"/"왼쪽 지도"·"오른쪽 지도")·세 주요 키·종류·스냅숏 시작 폴더(`user://experiments`)·이름표 파일 |

- **칸 = 다음 실험 조건.** 칸마다(A, 비교 모드면 B) `{preset, seed, overrides}` 를 들고, `overrides` 에는 고른 예설정과 **다른 값만** 넣는다(예설정과 같은 값을 적으면 빠짐). 예설정을 고르면 바꾼 값을 지우고 그 예설정 값으로(씨앗은 그대로). 되돌리기는 보이는 칸의 바꾼 값을 지운다(씨앗은 그대로).
- **검사:** 값이 바뀔 때마다 `SimConfig.build(preset, overrides)` 그대로 + 패널 규칙 하나(초기 개체 수 ≤ `population.cap` — 넘으면 처음부터 번식이 막힘). 오류 문장이 가리키는 키의 줄(없으면 마지막으로 바꾼 줄) 바로 아래에 빨간 글, 이름은 위험 색. 칸에 해석할 수 없는 글자(수가 아님, 정수 키에 소수, 배열 키)는 그 줄 아래 오류를 보이고 값은 그대로 둔다. 오류가 있으면 새 실험·나란히 시작 단추를 못 쓰고, `apply()` 도 실험실에 넘기지 않는다(지금 실험 그대로, 오류 알림). **입력 중이던 칸(Enter 없음)의 해석할 수 없는 글자**도 같다: 새 실험·나란히 시작(단추·`apply()`·`apply_compare()`)이 칸을 먼저 확정하다 해석 오류가 나면 시작하지 않고 그 줄 아래 오류 + 패널 "입력 오류: …"(비교 모드면 "B: …") + 알림(씨앗 칸 포함). 예전에는 옛 값으로 시작하고 오류가 곧 사라졌다. **실제 마우스로 단추를 누를 때도 같다**(검토 고침 I14): 칸 밖 누름에서 LabMain 이 초점을 풀어 칸이 단추 신호보다 먼저 확정되므로, 패널은 그 누름(`_input` — 패널이 LabMain 의 자식이라 먼저 받음)에서 난 해석 오류를 기억해 두었다가 같은 누름의 새 실험·나란히 시작이면 시작하지 않는다(지도를 누른 것이면 확정만 — 오류는 보이고 값 그대로, 그 뒤 단추는 지금 값으로 시작; 예전에는 실제 클릭이면 숫자 칸은 옛 값으로 시작하고 오류가 사라졌고, 씨앗 칸은 LabMain 의 `SpinBox.apply()` 가 "42 f" 를 42 로 계산해 씨앗 42 로 시작했음).
- **강조 = 지금 실험과 다른 값**(왼쪽 강조 색 띠 + 강조 색 값; 띠는 꺼져도 자리를 지켜 이름이 흔들리지 않음). 견주는 기준은 칸과 같은 자리의 지금 실험(비교 중이 아니면 B 칸도 A 실험과 견줌 — B 에서 바꾼 변인만 강조). 상태 줄: `지금 실험과 같음` / `바꾼 값 N개 · 새 실험을 눌러 적용`(비교 중이면 `… 나란히 시작을 눌러 적용`, 비교 전이면 `나란히 시작을 누르면 A·B 를 함께 시작`, 오류면 위험 색 `설정 오류 — …`). N = 설정 잎 키 가운데 다른 것 + 씨앗이 다르면 1. 고급 설정 머리에는 따로 "예설정과 다른 값 K개". "다른가" 는 갱신 한 번에 보이는 칸마다 한 번만 센다(지금 실험 `cfg`·예설정은 잎 키 → 값으로 펴 둠) — 상태 줄 N·주요 값·고급 설정 강조가 함께 씀.
- **지금 실험:** `experiments_changed` 마다 실험별 `label`(A/B 이름표 + `ui.graph.series_a`·`series_b` 색 점)과 세 값(`world.cfg` 를 깊은 사본으로 떠서 읽기만 함)을 다시 쓰고, **칸도 그 실험의 조건으로 맞춘다**(만든 실험 = 그 조건 그대로, 스냅숏 = 다른 값이 가장 적은 예설정 + 다른 값 — 그래서 스냅숏을 열어도 "지금 실험과 같음", 새 실험을 누르면 그 설정·씨앗으로 0틱부터 다시). 씨앗도 자르지 않고 그대로(아래 "씨앗"). 칸을 맞추는 것은 **그 자리의 실험이 바뀐 칸만**(지난번 `Experiment` 와 다른 것 — 새 실험·스냅숏·나란히 시작은 늘 새 실험): 비교를 끄면(`stop_compare` → 같은 A) A 칸에 고쳐 둔 다음 실험 값이 그대로 남는다(예전에는 지워졌음). 실험이 둘이 되면 비교 모드 단추가 켜지고, 둘에서 하나로 줄면 꺼진다.
- **세 주요 값:** 슬라이더(마우스 휠로는 안 바뀜) + 오른쪽 숫자 칸. 범위 `ui.param.mutation_rate_max`·`resource_scale_max`, 초기 개체 수는 `ui.param.initial_min` ~ min(`ui.param.initial_max`, 그 칸 조건의 `population.cap`). 눈금 `ui.param.mutation_rate_step`·`resource_scale_step`·`initial_step` — 슬라이더 값은 눈금 자릿수 글자로 바꿨다 다시 읽어 넣는다(0.30000000000000004 같은 값이 `SimConfig.validate` 의 JSON 왕복 검사에 걸리지 않게). 숫자 칸에는 슬라이더 범위 밖 값도 적을 수 있다(설정 검사 범위 안이면 됨, 슬라이더는 끝에 붙음). 화면을 상태에 맞추는 동안(슬라이더 끝을 줄이면 Range 가 값을 잘라 신호를 냄) 들어오는 신호는 무시한다 — 상한을 낮춰도 초기 개체 수가 몰래 바뀌지 않고 오류로 알린다(검사).
- **고급 설정:** `sim-defaults.json` 의 잎 키 전부를 절별로(절 이름 "지도 · map" 등). 수 → 오른쪽 맞춤 글 칸, 참거짓 → 확인 상자, 배열·글자(`seasons.growth`·`brain.policy`) → 읽기 전용 칸(보이기만). JSON 을 읽으면 수가 모두 실수가 되므로 **정수 키는 파일 글자로 가린다**(소수점 없는 수). 값 글자: 정수 키는 정수, 실수는 `JSON.stringify` 글자(`SimConfig.validate` 가 JSON 왕복을 보장하므로 적용되는 값 그대로 — 0.123456789012345 가 14자리로 잘리거나 5e-15 가 0.0 으로 보이지 않음; 보통 값 0.05·1.0 은 예전과 같음). 줄 이름은 설정 키 그대로(설계 10절), **말풍선 = 한국어 이름·뜻·단위·범위**(`config/sim-labels.json`, 같은 내용의 [`CONFIG.md`](CONFIG.md) — `tools/test_sim_labels.py` 가 모든 잎 키에 있는지·validate 범위와 같은지·문서가 최신인지 검사) + 키 + 예설정 값 + 지금 실험 값, 칸 말풍선 = 키 — 한국어 이름. 읽기 전용 칸(배열·글자)은 초점을 받지 않고(눌러도 단축키 그대로) 전체 값을 말풍선으로(좁은 칸에서 배열이 잘림). 고급 설정 맨 위에 "키 이름에 마우스를 올리면 …" 안내. 비교 모드에서는 머리의 A/B 단추로 고급 설정이 보여 줄 칸을 고른다. 펼쳤을 때만 줄을 갱신하고, 말풍선은 (칸·예설정·지금 실험)이 바뀔 때만 다시 만들며, 줄마다 마지막으로 쓴 값·강조·오류를 기억해 바뀐 것만 쓴다 — 슬라이더를 끄는 동안(프레임마다 `set_value`) 85줄을 다시 쓰지 않게(헤드리스 측정: 고급 설정을 펼친 채 `set_value` 한 번 약 3.6ms → 1.2ms, 남은 몫의 절반은 `SimConfig.build` 검사; 검사는 시간 대신 견준 수·말풍선 수를 봄).
- **입력:** 단추·고르기 상자(예설정)·확인 상자(소리·참거짓 칸)·고급 설정 펼침·A/B 단추는 **키보드 초점을 받는다**(검토 고침 J16 — `keyboard_focus`: Tab 으로 닿고 Enter 로 누름, 눌러도 초점은 그 단추에 남아 이어서 Tab. 스페이스는 그대로 멈춤 — LabMain `_input` 이 GUI 보다 먼저 스페이스를 먹으므로 초점 단추가 눌리지 않음, 검사. 확인 상자·납작한 단추는 공용 단추의 초점 테두리, 강조 단추(새 실험·나란히 시작)는 글 색 테두리 — 강조 바탕 위에서도 보이게). 마우스로 누르면 초점을 남기지 않는다(누른 뒤 Enter 가 같은 단추를 다시 누르지 않게, 초점 테두리가 남지 않게 — 마우스 쓰는 사람에게는 예전과 같음), 단추에 초점을 둔 채 다른 곳(지도 등)을 누르면 패널 `_input` 이 그 초점을 푼다(`release_button_focus` — 그 뒤 Enter 가 그 단추를 누르지 않게, 검사). 슬라이더는 초점을 받지 않는다(키보드는 옆 숫자 칸). 예전에는 모든 단추가 `FOCUS_NONE` 이라 Tab 이 글 칸 넷만 돌아 마우스 없이는 새 실험·비교·내보내기·스냅숏을 못 했다. 글 칸(숫자 칸·씨앗 칸)에 초점이 있으면 LabMain 이 단축키를 무시한다(검사: 씨앗 칸에 "42 f", 숫자 칸에 "0.07" 을 쳐도 멈춤·배속·따라가기 그대로). Enter = 확정 + 초점 풀기(지도로 돌아가면 단축키가 바로 동작), Esc = 적던 글자 버리고 초점 풀기(선택 해제 아님), 초점이 빠지면 확정. 칸 밖(지도·단추·다른 패널)을 누르면 LabMain 이 초점을 풀어 확정한다(4단계 검토 반영 — 단추·지도는 초점을 받지 않아 전에는 초점이 남았음, LabMain 메모 "글 칸 초점 풀기"). **패널의 모든 단추 동작(새 실험·나란히 시작·비교 모드·되돌리기·고급 설정 A/B·예설정 고르기·무작위·고급 설정 펼침·참거짓 칸·CSV 내보내기·스냅숏·소리) 전에 입력 중인 칸을 먼저 그 칸으로 확정하고 글 칸의 초점을 푼다**(단추를 신호·키로 누르면 글 칸이 초점을 쥔 채일 수 있음 — 확정 뒤 초점을 풀어 동작 직후 단축키가 듣고, 남은 글자가 나중에 엉뚱한 칸에 확정되지 않게. 단추의 키보드 초점은 그대로). 고급 설정 칸은 초점이 들어올 때의 A/B 칸으로 확정한다(A 에 적다가 B 단추를 누르면 A 에 들어감 — 예전에는 B 로 갔음). 되돌리기·예설정은 확정한 뒤 그 값을 지우므로 적던 글자는 남지 않고 칸에는 새 값이 보인다. 실험 목록이 바뀔 때(`experiments_changed`)도 같은 순서.
- **씨앗:** 글 칸(`LineEdit`) + 정수 해석 — **64비트 정수 전체**(−9223372036854775808 ~ 9223372036854775807, 실험실·실행기·스냅숏과 같이 자르지 않음). 글자는 십진 정수만(부호 하나 + 숫자, 앞뒤 빈칸 무시): 소수("42.7")·식("2+3"·"7*6")·16진("0x10")·지수("1e3")·글자 섞임("42 f")·64비트 범위 밖은 그 줄 아래 오류, 씨앗 그대로 — Enter·초점 빠짐·단추(신호·실제 클릭) 모두 같은 규칙(검토 고침 I14·J18: 예전 씨앗 칸은 실수 SpinBox 라 Enter 뒤 지연된 식 계산이 "42 f"→42·"2+3"→5·"42.7"→43 으로 오류를 지우고 씨앗을 바꿨고, 2^53 넘는 씨앗은 다른 수로 보였으며(…993 → …992), INT64_MAX 는 초점만 빼도 씨앗 0 이 됐음). 칸 글자 = `str(씨앗)`(실수로 바꾸지 않음 — INT64_MIN 도 "-…" 하나, 검토 고침 J31). 지금 실험에서 가져온 씨앗도 그대로(명령줄 `--seed=-5`, 2^53 넘는 씨앗의 스냅숏): 칸은 그 값, 상태 줄은 "지금 실험과 같음", 새 실험은 같은 씨앗(예전에는 0 으로 잘라 "바꾼 값 1개" 가 뜨고 새 실험이 다른 세계였음). "무작위" = 화면 쪽 시각으로 씨앗을 준 **따로 만든** `RandomNumberGenerator` 에서 고름 — 시뮬레이션 난수(SimRng)·Godot 전역 난수와 무관(검사: 전역 `randi()` 순서·세계 해시 그대로).
- **비교 모드:** 켜면(비교 중이 아니면) B 칸 = A 조건 사본, 새 실험 단추 자리에 "나란히 시작"(AccentButton), 칸 위 제목 "다음 비교 — 나란히 시작을 누르면 적용"(혼자 모드 "다음 실험 — 새 실험을 누르면 적용", 늘 보임). 칸 머리 = A/B + 비교가 돌기 전 "다음 조건", 비교 중 "왼쪽 지도"/"오른쪽 지도"(지도가 하나일 때 왼쪽/오른쪽이라 하지 않음). 끄면 B 칸을 숨기고 `lab.stop_compare()` 를 **늘** 부른다(비교 중이 아니면 LabMain 이 아무것도 하지 않아야 함). `start_compare` 의 오류 문장은 패널 안 빨간 글 + 알림.
- **실험을 버리기 전 확인:** 단추로 새 실험·나란히 시작(지금 실험 모두를 버림)·비교 끄기(B 를 버림)를 누를 때 버릴 실험의 틱이 `confirm_discard_ticks`(= `ui.param.confirm_discard_ticks`, 2000) 이상이면 `ConfirmationDialog`("실험을 끝낼까요?" — 몇 틱 실험을 끝내는지, [끝내기] [내보내고 끝내기](웹: 내려받고 끝내기 — `lab.export_csv(lab.default_export_dir())`/`download_results()` 뒤에 동작, 실패하면 버리지 않음) [취소], 폭 `ui.param.confirm_width`, 높이는 글·단추에 맞춤, 기본 초점 = 취소 — Enter·스페이스 한 번에 버리지 않게, 글은 낱말 단위 줄바꿈, 틱은 위쪽 막대·알림과 같이 세 자리 쉼표 "틱 12,005")를 먼저 띄운다. 모양은 실험실 테마(`style_dialog`: 바탕 = `theme.panel`, 창 테두리·제목 줄 = `theme.topbar` + `theme.panel_border`, 제목 = 굵은 글꼴 — 테두리 모양은 엔진 기본 그대로 색만; 스냅숏 대화 상자·덮어쓰기 물음도 같음. 검토 고침 I50: 예전에는 엔진 기본 회색 창에 글과 단추 사이가 크게 비었고 틱에 쉼표가 없었음). 묻는 동안·취소하면 비교 모드 단추는 켜진 채, 실험은 그대로. 대화 상자가 떠 있는 동안 실험실 단축키는 듣지 않는다(LabMain `_dialog_open`). 조건·입력 오류가 있으면 묻지 않고 그 오류를 보임. 함수(`apply()`·`apply_compare()`·`set_compare_mode()`)와 스냅숏 열기(파일 대화 상자에서 고른 것이 이미 확인)는 묻지 않는다. 비교 모드 단추 말풍선에 "비교 중에 끄면 B 실험은 끝나고 A 만 계속".
- **파일:** CSV 내보내기 = `lab.export_csv(lab.default_export_dir())`(성공·실패 알림은 LabMain). 스냅숏 저장/열기 = 패널 자식 FileDialog 두 개(처음 누를 때 만듦, `FILE_MODE_SAVE_FILE`/`OPEN_FILE`, `ACCESS_FILESYSTEM`, `*.json`, 시작 폴더 `user://experiments` 의 실제 경로 — 없으면 만듦, 크기 `ui.param.dialog_width × dialog_height`, 저장 기본 이름 `snapshot-<날짜-시각>-seed<N>-tick<T>.json`(비교 중이면 `-seed<A>-vs-seed<B>` — `default_export_dir` 와 같은 규칙, 4단계 검토 G44 의 패널 몫, 통합 때), `use_native_dialog` — 운영 체제 대화 상자를 쓸 수 있으면 그것, 못 쓰면(헤드리스·포털 없는 Linux) 엔진 대화 상자). 시작 폴더는 `snapshot_dir`(처음 값 `user://experiments`). 비교 중 저장은 `<이름>-A.json`·`<이름>-B.json` 두 파일(`snapshot_paths`) — 대화 상자(엔진·운영 체제)의 덮어쓰기 물음은 고른 `<이름>.json` 만 보므로, 실제로 쓸 -A/-B 가 이미 있으면 패널이 두 이름을 적어 직접 묻는다("스냅숏을 덮어쓸까요?" [덮어쓰기] [취소], 기본 초점 = 취소, 파일 대화 상자가 닫힌 뒤 띄움 — 검토 고침 J05: 예전에는 같은 이름으로 두 번 저장하면 묻지 않고 덮어써 `.bak` 한 단계만 남았음; 혼자 모드로 저장한 `<이름>.json` 이 있으면 대화 상자가 그 파일을 덮어쓸지 먼저 묻는 것은 엔진·운영 체제 동작이라 남음 — 그 파일은 쓰지 않음). `save_snapshot_to(path)`(함수)는 묻지 않는다. **저장 대화 상자가 떠 있는 동안 실험실을 멈춘다**(재생 중이었을 때만 — 고르거나 취소·닫으면, 덮어쓰기 물음이 있으면 그것이 끝난 뒤 다시 재생): 기본 이름의 틱 = 파일 안 틱(검토 고침 J06: 예전에는 대화 상자를 연 틱으로 이름을 정하고 그사이 실험이 돌아 4배 재생에서 2초면 50틱, 64배면 수천 틱 어긋났음). 열기 대화 상자는 폴더에서 가장 최근에 바뀐 스냅숏(`*.json`)을 골라 둔 채 열고, 이름 칸에 글자가 있으면 "열기" 단추를 켠다(검토 고침 J20: 엔진 대화 상자는 내보내기 하위 폴더 줄이 골라진 채 열려 `OPEN_FILE` 에서 "열기" 를 끄고 이름을 쳐도 켜지 않았음 — Enter 만 됐음). 저장 기본 이름의 씨앗은 `str()`(INT64_MIN 도 부호 하나, J31). 열기 실패는 패널 안 빨간 글 + 알림(지금 실험 그대로). 웹 "결과 내려받기" 실패는 `download_results` 가 띄우는 알림 하나(패널은 빨간 글만 — 검토 고침 I40: 예전에는 패널이 "결과를 내려받을 수 없습니다: …" 알림을 하나 더 띄움).
- **소리:** "소리" 확인 상자 = 실험실 자식 가운데 `LabSound`(종류로 찾음)의 `enabled`. 실험실 자식이 바뀔 때마다 다시 찾고, 없으면 못 씀(말풍선 "소리 장치(LabSound)가 없습니다").
- **배치:** 패널(VBox) = `Scroll`(세로만, 늘어남) ⊃ 제목 "실험 조건" · 지금 실험(CardPanel) · "다음 실험 …"/"다음 비교 …" · A 칸·B 칸(CardPanel, 비교 모드에서 머리에 색 점 + A/B + 다음 조건/왼쪽·오른쪽 지도) · ─ · CSV 내보내기 · [스냅숏 저장][스냅숏 열기] · 소리 · ─ · ▶ 고급 설정 / **`Footer`(고정 바닥)** = ─ · 상태 줄 · 오류 글(최대 `ui.param.footer_error_lines` 줄, 전체는 말풍선) · 새 실험/나란히 시작 · [되돌리기][비교 모드]. 바닥은 스크롤 밖이라 칸이 길어져도(비교 모드 B 칸·고급 설정) 주요 단추·비교 끄기 단추가 늘 보인다(예전에는 1280×720 에서 비교 모드를 켜면 B 칸이 끼어 나란히 시작·상태 줄·비교 모드 단추가 보이는 칸 아래로 밀렸음 — 검사: 1280×720·자리 펼침에서 보통·비교 + 고급 설정·비교 중 모두 화면 안). 가로: 글 칸은 기본 "글자 4개" 최소 폭을 끄고 `ui.param.value_field_width`·`advanced_field_width`·`seed_field_min_width` 만, 예설정 단추는 긴 이름을 말줄임(전체 이름은 말풍선), 긴 문장은 줄바꿈 — 최소 폭 + 스크롤 막대 ≤ `lab.left_panel_width` − 양쪽 여백(검사, 보통·비교 + 고급 설정 둘 다, 왼쪽 자리가 넓어지지 않음·가로로 넘치는 칸 없음). 간격 `ui.param.group_gap`·`row_gap`·`label_width`·`changed_stripe_width`·`chip_size`.
- 시뮬레이션 쪽 쓰는 것: `SimConfig.defaults()`·`presets()`·`preset_names()`·`build()`·`get_value()`·`deep_equal()`·`DEFAULTS_PATH`(정수 키 가리기), `Experiment` 의 만든 조건(`preset`·`overrides`·`seed_value`·`label`·`tag`·`snapshot_path`)과 `world.cfg`(깊은 사본으로 견주기만)·`world.tick`(저장 파일 이름). 세계를 진행하거나 고치지 않는다.
- 검사 `tests/view/param_checks.gd`(254개): 기본값 = 기본 예설정, 예설정 → 세 칸, 슬라이더 눈금·상한, set_value + apply → 새 실험의 cfg·씨앗·개체 수, 범위 밖 값 → 칸 아래 오류·단추 꺼짐·지금 실험 그대로·알림, 글자 오류·정수 키·배열 키, 참거짓 칸, 초기 개체 수 > 상한, 되돌리기, 고급 설정에 0(실제 키 + Enter) → 그 줄 아래 SimConfig 오류·0 으로 나누는 키(패널 오류 = `SimConfig.build` 오류, 이름표 범위가 "(검사)" 이고 0 이 밖이면 반드시 거부 — 검토 고침 g1a 병합 뒤 이 길로 막힘)·"(검사)" 범위 키마다 말풍선 범위 = 검사 범위(바로 밖 값 → 줄 아래 오류), 씨앗 64비트(음수·상한 밖 그대로, 64비트 밖·소수 → 오류)·무작위(전역 난수·세계 상태 = 스냅숏 글 그대로 — 역사 해시는 검사점에서만 바뀌므로 해시로 견주지 않음, 검토 고침 I89), 글 칸 입력 중 단축키 무시·Enter/Esc, 입력 중(Enter 없음, 실제 키) + 단추 → A/B 단추·되돌리기·예설정·새 실험·무작위·비교 모드 뒤 값이 제자리·초점 풀림·단축키 바로 동작, 읽기 전용 고급 칸 초점 없음, 해석 못 한 글자("0,07"·씨앗 "42 f"·B 칸) + 새 실험/나란히 시작 → 시작 안 함·줄 아래 오류·알림, 씨앗 칸 + 실제 Enter("42 f"·"2+3"·"7*6"·"42.7"·"0x10"·"1e3"·"12abc" → 오류·씨앗 그대로, "+77" → 77)·초점 빠짐, 실제 마우스 클릭(씨앗 "42 f"·숫자 칸 "0,07" + 새 실험 단추 → 시작 안 함, 지도 클릭 → 확정만·그 뒤 단추는 시작), 2^53+1·INT64_MAX·INT64_MIN 씨앗(칸 글자 = 씨앗·초점 넣고 빼기·Enter 만 → 그대로·새 실험 같은 씨앗·저장 기본 이름 부호 하나), 키보드(단추·고르기 상자 `FOCUS_ALL`, 씨앗 칸에서 Tab 만으로 새 실험 단추·스페이스 = 멈춤·Enter = 누름·초점 그대로·단추 초점 + 지도 클릭 → 풀림·마우스 클릭 → 초점 남기지 않음), 한국어 이름표(모든 잎 키)·말풍선·배열 칸 전체 값, **글자 범위**(검토 고침 J17 — 이전 저장소의 test_font_coverage: `scripts/ui`·`scripts/view`·`scripts/sim` 의 주석 아닌 줄, `scenes`, `config/*.json` 의 모든 글자가 나눔고딕 보통·굵게 둘 다에 있음. 웹 빌드는 시스템 대체 글꼴이 없어 없는 글자가 네모 — 두뇌 범례 '−' U+2212 가 그랬음. 다른 묶음이 고치기로 한 파일은 `FONT_PENDING` 에서 잠시 건너뛰되 그 파일이 고쳐지면 목록에서 지우라고 실패), 두뇌 열지도 범례 끝 글(weight_clamp 2.5·0.5·4 → "-2.5"·"-0.5"·"-4", I44·J17), 실수 글자 = JSON 글자(15자리·5e-15), 고급 설정을 펼친 채 `set_value`·슬라이더 한 번에 견준 수 ≤ 키 + 1·말풍선 다시 만들지 않음(시간은 출력만), 내보내기(`export_to(임시 폴더)` + 알림, 단추 → `lab.default_export_dir()` 는 가짜 실험실이 임시 폴더로 돌려 확인 — 공용 `user://experiments` 에 쓰지 않음, 검사 뒤 지움), 스냅숏 대화 상자 설정(시작 폴더 = 프로세스 임시 `snapshot_dir`)·저장·열기·없는 파일, 재생 중 저장(대화 상자 동안 멈춤·이름 틱 = 파일 틱·저장/취소 뒤 다시 재생·멈춰 있었으면 그대로), 열기 대화 상자(하위 폴더가 있어도 최근 스냅숏이 골라져 "열기" 켜짐 → 열림, 스냅숏 없는 폴더에서 경로를 치면 켜짐), 비교 중 같은 이름 두 번 저장 → -A/-B 덮어쓰기 물음(취소 그대로·덮어쓰기 새 틱), 소리 상자(LabSound 를 빼면 못 씀·돌아오면 다시), 범위 밖 씨앗(-5·3,000,000,000·그 스냅숏) → 칸 그대로·지금 실험과 같음·새 실험 같은 씨앗, 1280×720 폭·주요 단추가 화면 안(보통·비교 + 고급 설정·비교 중)·제목·칸 머리, 비교 모드(진짜 실험실: 나란히 시작 → 실험 둘·비교 중 A 칸을 고치고 끄면 그대로 남고 새 실험에 쓰임, 가짜 실험실 `FakeLab`: `start_compare` 인자 = 두 칸 조건, 끄면 `stop_compare`), 확인 대화 상자(문턱 아래는 바로·틱 60 → 물음·실험실 색·높이 = 글·단추·대화 상자 중 단축키 무시·취소 그대로·끝내기·`apply()` 는 안 물음·비교 끄기/나란히 시작 물음·취소하면 단추 켜진 채·틱 1,060 쉼표, 가짜 실험실: 내보내고 끝내기 → 결과 폴더 뒤 새 실험·웹 결과 내려받기 실패 → 알림 하나). 임시 파일은 프로세스마다 다른 `user://test_param-<프로세스>` 아래(검토 고침 I37 — 예전 고정 이름 `user://test_param` 은 사본 둘을 함께 돌리면 서로 지웠음). 종단(패널 → 실험실 → 그래프·연대기)은 `integration4_checks`.
- 캡처: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/param_capture.gd -- --out=폴더 [--extra]` → `param-panel.png`(실제 폭·실제 높이(창 − 위쪽 막대 − 아래 자리)의 세 장면: 값을 바꾼 혼자 모드 · 비교 모드 · 고급 설정(바꾼 값·칸 아래 오류)), `--extra` 면 장면별·1280×720 높이 그림과 확인 대화 상자(`param-confirm.png`, 창 전체)도.
- 알려진 한계(엔진 대화 상자로 열릴 때): 안의 엔진 글(경로·폴더 만들기·Save 등)은 엔진 번역이 내보내기에 없어 영어로 보이고(제목·취소 단추만 한국어), 프로젝트 이름이 한글이라 `user://` 실제 경로에 한글이 들어가면 Godot 4.4 의 FileDialog 가 목록은 보여 주면서도 "You don't have permission to access contents of this folder." 를 잘못 띄운다(엔진 `DirAccessUnix::is_readable` 이 경로를 UTF-8 로 넘기지 않음 — 영문 경로에서는 안 뜸, 캡처로 확인). 프로젝트 설정 `application/config/use_custom_user_dir` + 영문 `custom_user_dir_name` 으로 피할 수 있다 — **통합 때 켬**(`custom_user_dir_name = "slime-lab"`, Linux 에서 `~/.local/share/slime-lab`, Windows 에서 `%APPDATA%\slime-lab`).

## GraphPanel — `scripts/ui/graph_panel.gd` (`class_name GraphPanel`, HBoxContainer, 아래 자리) + `GraphView`(`scripts/ui/graph_view.gd`)

- `func bind_lab(lab)` — `experiments_changed` → 지우고 `rows()` 를 처음부터, `recorded(index, row)` → 덧붙임, `cursor_tick_requested(tick)` → 세로 표시선.
- 그래프 3개(가로로 나란히, 각 제목·축·범례):
  1. **개체 수**: `population` 선(+ `births`·`deaths` 얇은 선, 켜고 끔).
  2. **평균 특성**: 고르기(OptionButton) — `mean_size`·`mean_sense`·`mean_energy`·`mean_age`·`mean_gen`.
  3. **기술 단계**: `civ_stage` 계단선(세로축에 `SimWorld.STAGE_NAMES`) + `storehouses`·`farms` 수(보조 축), 발견 시점 세로선과 이름.
- 가로축: 틱 ↔ 평균 세대(한 단추로 셋 모두). 비교 모드: A 실선(`ui.graph.series_a`), B 점선(`series_b`), 범례에 `display_name()`.
- 마우스를 올리면 세로선 + 가장 가까운 기록 줄의 값(A·B 함께).
- 성능: 줄이 수천 개여도 다시 그리기는 `ui.graph.redraw_hz` 이하, 그릴 때 화면 폭(픽셀 열)에 맞춰 줄임(열마다 최소·최대).
- `func graph_count() -> int`(3) · `func series_points(graph: int, index: int) -> int`(검사용: graph 번째 그래프가 index 번째 실험을 잇는 점 수 = `GraphView.series_point_count` — 그 그래프의 선마다 줄인 점 수 가운데 가장 큰 것. 줄이 그림 폭보다 적으면 기록 줄 수와 같고(평균 특성은 개체가 없는 줄이 빠짐), 많으면 줄인 수 ≤ 그림 폭 × 4. 검토 고침 I38: 예전엔 graph 를 무시하고 기록 줄 수를 돌려 "그래프 세 개 모두" 검사가 공허했음. 기록 줄 수는 `series[index].size()`) · `func set_x_axis(mode: String)`("tick"/"gen").

**구현 메모(4단계, GraphPanel 담당이 덧붙임)**

- 배치(코드로 만듦, 노드 이름 고정): `GraphPanel`(HBox) ⊃ `Body`(VBox) = `Header`(`Legend` 범례 · `RecordNote` 기록 시작 알림(아래 "스냅숏에서 연 실험") | "가로축" `XTick` 틱 · `XGen` 평균 세대) / `Charts`(HBox) = `Card0`·`Card1`·`Card2`(CardPanel 모양, 여백 `ui.graph.card_pad_h`·`ui.graph.card_pad_v`) ⊃ `TitleRow`(`Title` 제목 + 조작 하나: `Flows` "출생·사망" / `Trait` OptionButton / `Hint` "세로선 = 발견") + `Graph0`~`Graph2`(GraphView, 자식 `HoverLayer` = 마우스 겹). 작은 단추는 공용 Button 모양에 세로 여백 `ui.graph.button_pad_v`·글자 `lab.font_size_small`. **제목은 줄이지 않는다**(최소 폭 = 글 폭): 출생·사망 견본은 제목 줄이 아니라 개체 수 그래프 안 위쪽 띠에 그린다(4단계 검토 G31: 1280 창에서 견본 `FlowKeys` 가 "개체 수" 제목을 0 폭으로 밀어냈음 — 지금은 제목 줄 + 출생·사망을 켜도 패널 최소 폭 540 그대로, 검사).
- 데이터 입구는 셋: `load_experiments(list)`(= `experiments_changed`, 지우고 각 `rows()` 를 처음부터), `append_row(index, row)`(= `recorded`, 한 줄 덧붙임 — 다시 훑지 않음, 없는 번호는 무시), `set_cursor_tick(tick)`(= `cursor_tick_requested`). `bind_lab` 이 셋을 연결하고 지금 `lab.experiments` 를 바로 읽는다(LabMain 이 `_ready` 에서 첫 실험을 연 뒤에 묶어도 됨). LabMain 없이(검사·캡처) 같은 함수로 몬다 — 비교는 `x.tag = "A"/"B"` → `load_experiments([a, b])` → 진행할 때마다 `append_row(k, x.rows().back())`. 검사는 실험 없이 쌓은 합성 기록도 `load_series(list: Array[Series])` 로 넣는다(`Series.new(null)` + `append(줄)`).
- 실험마다 `GraphPanel.Series`: 열마다 PackedFloat64Array(`C_POP` … `C_FARMS`, 사전을 프레임마다 복사하지 않음), 틱·평균 세대 가로 값, 열별 최솟값·최댓값(세로 범위를 다시 훑지 않음), 발견 표시 `{stage, tick, gen}`(틱 = `world.discovery_tick`, 세대 = 연대기 발견 사건의 `mean_gen` — 기록 간격 사이의 정확한 시점), 멸종 줄·틱. 개체 수가 0 인 줄의 평균 열은 NaN(선이 끊김 — 평균 함수가 돌려주는 0 이 거짓 바닥이 되지 않게), 세대 가로 값은 마지막 평균 세대를 이어 씀(멸종한 세대 자리로 선이 떨어짐). 평균 세대는 (값, 줄 번호) 순으로 정렬한 사본(`gen_sorted`·`gen_order`)도 늘 유지해 세대 축의 가장 가까운 줄을 이분 탐색으로 찾는다.
- **출생·사망 = `ui.graph.flow_per_ticks`(20)틱당 수**: 기록 줄의 `births`·`deaths` 는 앞 줄 이후의 수(기록 간격 `record.every` 만큼)라, 쌓을 때 × flow_per_ticks ÷ (이 줄 틱 − 앞 줄 틱)으로 고친다(첫 줄은 그 실험의 `record.every`). 기록 간격이 기본(20)이면 기록 줄의 수 그대로이고, 고급 설정으로 A·B 의 간격이 달라도 같은 눈금(검토 G20: 간격 100 인 B 가 5배 빠르게 보였음, 검사). 단위는 개체 수 그래프 위쪽 띠 견본("— 출생 — 사망 20틱당", 그래프가 좁으면 단위만 빠짐)·값 읽기 머리("· 출생·사망 20틱당")·단추 말풍선에. 내보낸 timeseries.csv 는 기록 줄 그대로(간격마다의 수).
- 가로축: 셋이 같은 범위. 시작 = 눈금 간격(1·2·2.5·5 × 10^k, 약 `ui.graph.x_ticks` 칸)의 배수로 내림, 끝 = 간격 ÷ `ui.graph.x_snap_div` 단위로 올림(오른쪽 여유 약 5% 이하, 범위가 가끔만 바뀜). 최소 폭 `ui.graph.x_min_span_ticks`(틱)·`ui.graph.x_min_span_gen`(세대) — 새 실험의 첫 점이 왼쪽에서 자라 나감. 눈금 이름은 `ui.graph.x_label_min_px` 이상 떨어지게 간격 배수를 고르고(그림 폭이 그 `NARROW_LABEL_FACTOR`(2.5)배보다 좁으면 이름이 겹치지 않을 만큼만 — 1280 창에서 "0" 하나만 남던 것, 통합 때 고침·값 56 → 50), 오른쪽 끝에 단위(틱/세대). 이름은 눈금 가운데, 양 끝에서는 안쪽으로 붙인다(오른쪽은 단위 글자 앞까지, 자기 눈금을 덮을 때만). 실제 이름(소수 "0.5" 등)이 서로 `X_LABEL_PAD`(8px)보다 붙으면 더 넓은 간격으로, 그래도 이름이 하나뿐이면 둘 이상이 겹치지 않고 들어가는 가장 넓은 간격으로 낮춘다(4단계 검토 통합 때: 띠 범위 글이 오른쪽 여백을 쓰며(G12) 그림이 좁아져 1280 창 기술 단계 그래프가 1,212틱에서 다시 "0" 하나만 — 그린 이름을 기록하지 않아 검사가 없던 I04, `graph_checks` "가로축 이름": 폭 4가지 × 틱 범위 6가지 × 틱·세대 축 × 세 그래프가 이름 ≥ 2·겹치지 않음·단위 앞).
- 세로축: 개체 수 = 0 부터(출생·사망을 켜면 그 최댓값도 포함). 평균 특성 = 자료 범위 ± `ui.graph.y_pad_frac` 를 눈금 간격의 배수로 넓힘, 범위가 값 크기의 `ui.graph.y_min_span_frac` 보다 좁으면 그만큼 넓힘(평평한 값도 범위가 생기고, 0.0003 같은 잡음이 높이를 다 차지해 큰 변화처럼 보이지 않음), 자료가 모두 0 이상이면 축도 0 이상. 눈금은 **많아야 `ui.graph.y_ticks_max` 개, 간격 ≥ `ui.graph.y_tick_min_px`**: 칸 수 ≤ min(높이 ÷ y_tick_min_px, y_ticks_max − 1) 로 간격을 고르고, 양 끝을 간격의 배수로 넓혀 칸이 넘치면 다음 간격(1·2·2.5·5 × 10^k)으로(검토 G46: 평평한 감각 3.0 에 눈금 7개·20px 간격이던 것 → 2.9~3.1 다섯 개; 0 을 사이에 둔 자료는 늘 두 칸 이상이라 간격 둘보다 낮은 그림에서만 간격이 좁아질 수 있음, 검사). 왼쪽 여백은 눈금 이름 폭에 맞추되 같은 데이터·설정 동안 줄이지 않음(폭이 자꾸 바뀌어 다시 묶지 않게).
- 기술 단계: 위 = 계단선(세로축 `SimWorld.STAGE_NAMES`, 단계가 오른 세로 마디는 정확한 발견 시점에 — 앞뒤 기록 두 줄 사이로 맞춤), 아래 = 저장고·밭 **작은 띠 둘**(높이 `ui.graph.lane_frac`, 띠마다 0~위 끝을 따로 — 이름은 왼쪽, 범위 "0~N" 은 오른쪽 그 띠 상자 안 세로 가운데; 자료가 모두 0 이면 범위 글 없음. 검토 G12: 위 끝 값 "1" 을 띠 위 선 자리에 두었더니 아래 띠의 글이 위 띠 선 끝 옆에 놓여 "저장고 1" 처럼 읽혔고, 아무것도 없어도 "1" 이 보였음). 눈금이 다른 수를 한 그림에 겹치는 이중 축 대신 작은 그래프로 나눴다("보조 축"의 구현). 발견 세로선(`ui.graph.marker_alpha`, B 는 점선) + 위 띠에 단계 이름(겹치면 생략 — 세로축·값 읽기에 있음). 다른 두 그래프에는 흐린 세로선만(`ui.graph.markers_on_all`, `ui.graph.marker_faint_alpha`). 비교 모드에서 A·B 계단선은 `ui.graph.stage_offset_px` 만큼 위·아래로 엇갈려 그림(같은 단계여도 둘 다 보이게, 픽셀만 — 값·값 읽기는 그대로).
- 개체 수 그래프: 개체 수가 0 이 된 시점(`world.extinct_tick`)에 위험 색 세로선(`ui.graph.extinct_alpha`) + "멸종". 비교 모드면 "A 멸종"·"B 멸종"이고 B 는 점선, 같은 자리면 이름을 한 줄씩 아래로(검토 G47, 검사). 그리는 순서: 격자·축 → 발견·멸종·시점 세로선 → 계열 선(B 다음 A) → **이름(시점 이름 상자·멸종 이름)** — 이름은 선 위(검토 고침 I46: 85% 바탕 상자를 데이터 선이 덮어 "A · 틱 1,636" 이 읽히지 않았음, 검사는 `last_lines`·`last_cursor`·`last_extinct` 의 그린 순서 `seq`).
- 색: A = `ui.graph.series_a`(#3d9406 풀빛 초록), B = `ui.graph.series_b`(#e54ec6 자홍), 출생 `ui.graph.births`, 사망 `ui.graph.deaths`(무채색 — 색상으로 가르는 것은 A·B·출생 셋뿐). 세 색은 카드 바탕(`theme.background`) 위에서 dataviz 검사기 전 쌍 통과(색각 이상 모의 ΔE ≥ 8.6, 정상 ΔE ≥ 23.8, 명도 대비 ≥ 3:1, 명도·채도 범위 안). **뜻 색과도 구별**(4단계 검토 G32: 예전 A #2aa98a 는 강조 민트 `theme.accent`(발견 띠·알림)와 정상 ΔE 14.4, B #d97630 은 경고 주황 `theme.warn`(멈춤·밭 잃음)과 10.3·위험 `theme.danger` 와 7.9 로 붙어 "주황 띠 = B" 로 읽혔다): A·B 와 경고·강조·위험의 모든 쌍이 정상 ΔE ≥ 16.0, 색각 이상(제1·제2 색맹 중 작은 값) ΔE ≥ 8.5. 이름표(실험 색 바탕에 바탕색 굵은 글자)도 읽히게 바탕 대비 ≥ 4.5(A 4.61·B 5.28). 이 문턱은 `graph_checks` 가 같은 식(OKLab × 100, Machado 2009)으로 검사한다. `LabMain.tag_color`·연대기 A/B 표시·파라미터 패널 색 점이 이 키를 읽어 함께 바뀜. 3단계 기본값(강조색과 같은 #7fd1b9·#e8a05a)은 명도 범위 밖이라 4단계 처음에 바꿨었다. 글자는 데이터 색을 입지 않음(범례·값 읽기는 선 견본 + 글자색). 눈금선 `ui.graph.grid`, 축 `ui.graph.axis`.
- 선: 굵기 `ui.graph.line_width`(출생·사망은 `ui.graph.thin_width`, 저장고·밭 띠는 `ui.graph.lane_line_width` — 검토 G28: 예전엔 띠 굵기를 코드에 line_width × 0.75 로), 점선 무늬 `ui.graph.dash_px`·`ui.graph.dash_gap_px` 는 **가로 위치 기준**(그림 영역 왼쪽부터 무늬를 깔고 켬 구간의 조각만 — 줄인 선이 한 열 안에서 오르내려도 무늬가 고르고, 새 줄이 와도 무늬가 흐르지 않음). 단 **가파른 조각**(세로 변화 > 가로 변화 × 2 이고 무늬 한 칸(dash + gap)보다 김, 또는 가로 변화가 거의 0 — 한 열 안의 뾰족한 값·단계 오름 세로선)은 조각 길이를 따라 점선(시작 = 켬): 가로 위치 무늬로는 끔 열에 든 뾰족한 값이 통째로 사라졌다(검토 G21) — 이제 무늬 자리와 무관하게 꼭짓점까지(꼭짓점에서 끝나는 조각도 많아야 dash_gap 만큼만 덜, 검사). 점선 조각은 선마다 모아 한 번에 그리고, 모두 무늬 틈에 들어 비었으면 그리지 않는다(검토 G24: 빈 배열로 `draw_multiline` → 엔진 ERROR). 지금 값(마지막 점)에 표면색 고리 + 점(`ui.graph.point_radius`·`ui.graph.surface_ring_px`). B 를 먼저, A 를 위에.
- 줄이기(M4): 가로 픽셀 열마다 연속한 줄 가운데 첫·최소·최대·끝 줄 번호만 남김(`GraphView.Runs`) — 점 수 ≤ 그림 폭 × 4, 열마다 최솟값·최댓값이 그대로(한 줄짜리 뾰족한 값도 남음 — 실선·점선 모두, 검사). 묶음은 줄 번호만 가져 세로 범위가 바뀌어도 다시 묶지 않는다. (가로 범위·그림 폭·가로축·데이터 세대 `epoch`)가 바뀔 때만 처음부터, 그 사이에는 새 줄만 더함. 실험마다 줄의 픽셀 열은 그래프마다 한 번만 계산해 그 그래프의 선들이 함께 씀. 세대 축처럼 가로 값이 되돌아가도 "연속한 같은 열"로 묶으므로 맞다.
- 다시 그리기: 새 줄은 모아서 `ui.graph.redraw_hz` 이하(`_process` 가 `advance(delta)` 를 부름 — 검사는 delta 를 직접 줌), 크기·가로축·고르기·시점 표시·실험 바뀜은 바로. 숨겨진 동안은 그리지 않음. **마우스는 마우스 겹(`HoverLayer`, 그래프와 같은 크기·마우스 통과)만** 다시 그린다 — 선·눈금·묶음은 그대로(검토 G23: 마우스가 움직일 때마다 세 그래프의 모든 선을 다시 만들었음). 보이는 것(마우스 그래프·실험마다 줄·기준 가로 값)이 그대로면(세로로만, 같은 줄 안) 아무것도 다시 그리지 않음. 배치(`layout_now`)도 크기·데이터·가로축·고르기가 그대로면 앞 계산을 그대로 씀(검사: 마우스 뒤 GraphView `draw_count` 그대로, 마우스 겹만 한 번씩).
- 마우스: 그림 영역 위의 가로 값 → `GraphPanel.hover_state()`(가로 값·가로축·데이터가 그대로면 앞 계산을 그대로 — 세 그래프 + 값 읽기가 한 번을 나눠 씀, 검토 G07: 예전엔 그리기마다 4번, 세대 축은 매번 모든 줄을 훑음): 실험마다 가장 가까운 기록 줄(틱 축 = 틱의 이분 탐색, 세대 축 = 정렬해 둔 평균 세대의 이분 탐색 — 차이가 같으면 뒤 줄, 모두 훑는 것과 같은 답, 검사), 그 가운데 마우스에 가장 가까운 줄이 **기준**(세로선·머리 글의 가로 값). 다른 실험의 줄은 기준에서 max(`ui.graph.hover_gap_px` 픽셀, 그 실험의 평균 줄 간격의 반) 안에 있을 때만 값·점으로 보인다(검토 G05: 세대 축 비교에서 세로선·머리가 A 의 줄을 따라가 — A 가 멸종해 그 세대에 이르지 못하면 마우스에서 수백 px 떨어진 A 의 마지막 세대에 선이 서고, B 의 값이 그 세대의 값처럼 보였음). 세 그래프 모두 기준 세로선(`ui.graph.hover_line`) + 보이는 줄의 점(표면색 고리, `ui.graph.hover_dot_radius`), 마우스가 있는 그래프에만 값 읽기 상자(`ui.graph.tip_pad`·`ui.graph.tip_radius`, 기준선 옆 `ui.graph.tip_offset_px`, 넘치면 왼쪽): 머리(기준 틱, 또는 평균 세대 — 혼자면 " · 틱 N" 도) + 실험마다 값(비교면 A/B 선 견본). 비교 모드에서 세대 축이면 실험마다 자기 줄의 "(G세대 · 틱 N)", 틱 축이면 자기 줄의 틱이 머리와 다를 때(기록 간격이 다름) "(틱 N)". 좁은 그래프(1280 창)에서는 줄을 그래프 폭에 맞게 " · "·" (" 앞에서 접는다(`GraphView.wrap_readout`, 이어지는 줄은 견본 없이 들여 씀 — 상자가 그래프 밖으로 잘리지 않게, 검사). 기준 근처에 기록이 없는 실험은 흐린 글로 "A  멸종 (틱 N · G세대)"(멸종해 그 세대에 이르지 못함) / "— (이 세대 기록 없음 · 최고 G세대)" / 틱 축은 멸종한 뒤의 틱이면 "A  멸종 (틱 N)"(멸종 뒤로는 기록하지 않아 줄이 없을 뿐 — 검토 고침 I45: 예전엔 틱 축만 "기록 없음"), 그 밖 "— (이 틱 기록 없음)", 점 없음. 평균 특성의 이름은 고르기 항목과 같다(`GraphPanel.TRAIT_NAMES` 크기·**감지**·에너지·나이·세대 — 정보 창·README 와 같은 "감지", 검토 고침 I51; 설정 절 `sense` "감각" 은 다른 것). 개체가 없으면 평균은 "— (개체 없음)", 개체 수 0 은 "멸종". 그림 영역 밖·마우스가 나가면 지움.
- 시점 표시: `ui.graph.cursor` 색 세로선(`CURSOR_WIDTH`) + 바닥 쪽 "틱 N"(이름 상자 `ui.graph.cursor_label_alpha`·`cursor_label_pad_h`·`cursor_label_pad_v`). 틱 축은 세로선 하나. **세대 축은 실험마다** 그 틱에 그 실험이 있던 평균 세대에(`Series.gen_at_tick`: 그 틱의 발견 표시 → 멸종 뒤면 멸종한 세대 → 그 틱의 연대기 사건의 `mean_gen` → 앞뒤 기록 줄 사이를 틱으로 이음). 같은 시점도 실험마다 세대가 달라서다(검토 G06: 예전엔 첫 실험의 가장 가까운 줄의 세대 하나 — B 의 발견 줄을 눌러도 A 의 세대에 섰고, 혼자여도 연대기 줄·발견 세로선과 어긋났음). 비교면 B 는 점선, 이름 "A · 틱 N"/"B · 틱 N", 이름이 겹치면 한 줄씩 위로. 요청은 그대로 `cursor_tick_requested(tick)` 하나(어느 실험의 줄인지 몰라도 그 실험의 세로선은 그 실험의 발견 세로선·연대기 세대 자리와 같음, 검사). -1·새 실험이면 지움. **시점이 마지막 기록 줄 뒤면 가로축을 그 자리까지 넓힌다**(그 세계가 이미 지난 틱일 때만 — 세계에 없는 틱은 넓히지 않고 범위 밖이라 그리지 않음): 사건은 기록 간격 사이에도 나서, 멈춘 채 연대기의 최신 줄을 누르면 그 틱이 가로축 끝(마지막 기록 줄을 올린 값)을 넘을 수 있었다(검토 고침 I15: cursor_tick 만 바뀌고 세 그래프 모두 선이 없었음 — 시연용 씨앗 2 의 틱 126 저장고, 검사는 연대기 `activate_item` 경로로 틱·세대 축). 그래서 GraphView 의 배치 열쇠에 `cursor_tick` 도 든다. 첫 기록 줄 앞의 시점은 넓히지 않는다(그 앞은 기록이 없음 — 아래 스냅숏).
- **스냅숏에서 연 실험**(검토 고침 J19): 스냅숏에는 세계와 연대기만 있어 연 실험은 연 틱부터 다시 기록한다(실행기 `--resume` 과 같은 설계). 그 앞의 발견 세로선·연대기 줄의 시점 표시는 가로축 범위 밖이라 그리지 않으므로, 첫 기록 줄이 틱 0 보다 뒤인 실험이 있으면 머리(`RecordNote`, 흐린 작은 글, 말풍선에 까닭)에 "기록은 틱 N 부터"(비교면 "B 기록은 틱 N 부터")를 보인다. `record_note() -> String`(없으면 "")·`record_note_shown()`(검사용).
- 빈 기록: 눈금선만 + "기록 없음"(뜻 없는 눈금 값은 쓰지 않음). 줄 하나: 점 하나. 범례: 비교면 실험마다 선 견본(A 실선·B 점선) + `display_name()`, 혼자면 실험 이름만(선이 하나라 견본 없음). 범례는 코드로 그려 왼쪽부터 붙이고, 자리가 모자라면 **가운데(예설정 이름)만** "…" 로 줄이고 앞(이름표 "A · ")·끝(" · 씨앗 N · 돌연변이 0.08 …" — `GraphPanel.SEED_MARK` 부터, 바꾼 값은 `Experiment.default_label` 의 짧은 설명)은 남긴다(먼저 남길 폭을 주고 나머지를 자연 폭 비례로). 그래도 안 들어가면 그때만 뒤를 자름(전체 이름은 말풍선). 검토 G33: 1280 창에서 같은 예설정을 씨앗만 바꿔 견주면 범례 둘이 "A · 시연·검사용(아주 빠른 발…" 로 똑같았음 → 지금 "A · 시연·검사용(… · 씨앗 1"(검사). 지도 위 실험 이름(LabMain `_fit_title`)도 같은 나눔으로 예설정 이름만 줄임(통합 때 — LabMain "지도 위 표지").
- 검사·캡처용 API: `view(graph) -> GraphView` · `x_bounds()`·`x_step()`·`row_x(index, row)`·`nearest_row(index, x)`·`hover_rows()`·`hover_state() -> HoverState{rows, valid, anchor_x, anchor}`·`hover_computes`·`cursor_x(index)`·`data_rev`·`load_series(list)`·`flow_unit()`·`legend_texts()`·`legend_items()`·`legend_shown()`·`static split_name(text, tag)`·`advance(delta) -> bool`·`redraw_now()`·`redraw_interval()`·`is_dirty()`·`redraw_count`·`set_show_flows(on)`·`set_trait(i)`. GraphView: `point_px(index, row, col)`·`data_to_px(x)`·`px_span(px)`·`hover_at(pos)`·`hover_draw_count()`·`readout_lines()`·`readout_text()`·`wrap_readout(lines, max_w, key_space)`·`y_range()`·`y_ticks()`·`layout_now()`·`last_lines`(+ `width`·`seq` = 그린 순서)·`last_markers`·`last_extinct`(+ `seq`)·`last_cursor`(+ `seq`)·`last_lane_labels`·`last_x_labels`(`{text, value, rect}`)·`last_flow_key`·`last_hover_px`·`dash_skipped`·`last_draw_us`·`rebuild_count`·`last_fed_rows`(마지막 그리기가 묶음에 새로 넣은 줄 수, 선마다 합)·`line_runs(index, col)`·`series_point_count(index)`, 정적 `reduce(xs, ys, x0, x1, width)`·`run_indices(runs)`·`nice_step(span, target, integer)`·`next_nice(step, integer)`·`fmt_num(v, d)`·`fmt_rate(v)`. 이름 붙은 기하 상수(GraphView): `VERTICAL_DASH_FRAC`(세로 점선 무늬 = dash_px × 0.5)·`KEY_DASH_FRAC`(값 읽기 견본 0.6)·`TIP_PAD_V_FRAC`·`STEEP_RATIO`·`LABEL_GAP`·`TICK_LEN`·`CURSOR_WIDTH`·`X_LABEL_PAD`·`NARROW_LABEL_FACTOR`·`X_UNIT_GAP`, GraphPanel `LEGEND_KEY_SCALE`(범례 견본 = legend_key_px × 1.5).
- 측정(헤드리스, 개발 컴퓨터): 합성 6,000줄 × 실험 2 를 1600×260 패널에 — 세 그래프 `_draw` 합이 묶음을 새로 만들 때 약 21 ms, 새 줄만 더할 때 약 5~10 ms(`tests/view/graph_checks.gd` 가 참고로 출력만). 검사는 시계가 아니라 센 수로 본다: 새 줄 뒤 그리기가 묶음에 넣은 줄 = 새 줄 수 × 선 수(`last_fed_rows`), 점 수 ≤ 그림 폭 × 4, 묶음을 다시 만들지 않음(검토 고침 I34: 예전 "새 줄 뒤 그리기 < 20 ms" 는 기계 속도·부하에 묶인 단언 — 그리기마다 8 ms 늦춘 흉내에서 코드가 맞아도 실패). 묶음을 새로 만드는 것은 실험·크기·가로축이 바뀔 때와 줄이 약 5% 늘 때마다뿐.
- 키보드(검토 고침 J16): `XTick`·`XGen`·`Flows`·`Trait` 은 키보드 초점을 받는다(`ParamPanel.keyboard_focus` — Tab·Enter, 스페이스는 LabMain 이 먼저 멈춤으로 받아 단추가 눌리지 않음, 마우스로 누르면 초점을 남기지 않음). 패널 `_input` 이 왼쪽 누름에서 이 패널 단추의 초점을 푼다(`ParamPanel.release_button_focus`). 그래프 자체(마우스 값 읽기)는 마우스만.
- 검사 `tests/view/graph_checks.gd`: 눈금·숫자 표시, 줄이기(열마다 첫·끝·최소·최대가 참값, 뾰족한 값 유지, 나눠 넣어도 같음, NaN 에서 끊김), 가로 위치 점선 비율, 멸종 줄·NaN·세대 이어 쓰기, 실험실에 묶기(`lab.bottom_dock.add_child(panel)` + `bind_lab`) → `step_ticks` 로 점 수 증가·값 일치·다시 그리기 간격·시점 표시·발견 세로선 자리(틱·세대 축)·가로축 바꾸기의 알려진 점 좌표·마우스 가장 가까운 줄과 값 읽기·출생·사망·평평한 값·역사 해시 그대로·새 실험이면 지움, 비교(직접 만든 두 실험: 범례·A 실선/B 점선·엇갈림·A/B 값 읽기·빈 목록·줄 하나), 6,000줄 × 2(점 수 ≤ 폭 × 4, 뾰족한 값, 새 줄만 더함, 그리기 시간). 4단계 검토 뒤 더함: 점선의 뾰족한 값(무늬 자리 10곳)·빈 점선 조각, 세로 눈금 수·간격(평평한 값 포함 77가지), 실험 색 대 뜻 색(ΔE·바탕 대비), 출생·사망 틱당(간격 20 = 100)·세대 축 이분 탐색 = 모두 훑기, 시점 표시선이 실제로 그 자리에(틱 축 세 그래프, 범위 밖·-1 이면 없음, 세대 축 = 발견 세로선·연대기 세대), 띠 범위 글, 마우스는 겹만·계산 한 번·세로 움직임은 그리지 않음(틱·세대 축, 6,000줄 × 2), 세대 축 비교(A 멸종: 세로선·머리 = 마우스 자리, A 줄 "멸종", B 시점 표시 = B 발견 세로선), 비교 멸종 이름, 가장 좁은 폭의 제목·범례(씨앗 남김), 합성 비교(B 의 자기 틱·같은 빠르기·빈 점선 건너뜀·선 굵기 = ui.json), 가로축 이름(통합 때: 폭 4가지 × 틱 범위 6가지 × 틱·세대 축 — 이름 ≥ 2·겹치지 않음·단위 앞, U09). 검토 고침(g4b): 마지막 기록 줄 뒤 사건의 연대기 줄을 누르면 세 그래프 모두 세로선(틱·세대 축, I15), 그래프마다 그리는 점 수(평균 특성은 멸종 줄 빠짐·세대 축에서 한 열에 모인 줄·6,000줄 = 그린 점, I38), 틱 축 "A  멸종 (틱 N)"(I45), 이름이 선 위(I46), "감지"(I51), 스냅숏에서 연 실험의 "기록은 틱 N 부터"(J19), 새 줄 뒤 그리기의 센 수(I34). 각 검사는 고치기 전 코드로 되돌려 실패함을 확인했다.
- 캡처 `tests/graph_capture.gd`: 아래 자리와 같은 DockPanel 바탕을 SubViewport 에 그려 1600×260 과 1000×220 을 위아래로 붙임 → `docs/screenshots/v0.1/graphs-single.png`(시연용·씨앗 1·2,500틱: 위 = 출생·사망 + 개체 수 마우스 값, 아래 = 세대 축 · 평균 에너지 · 시점 표시), `graphs-compare.png`(A 기본 · B 시연용, 각 2,500틱: 위 = 기술 단계 마우스 값, 아래 = 세대 축 · 출생·사망 · B 의 농사 발견 시점(실험마다 자기 세대에) · A 가 이르지 못한 세대의 마우스 값). `--extra` 는 1280 창의 아래 자리 폭·멸종·줄 하나·실험 없음 참고 그림.

## ChroniclePanel — `scripts/ui/chronicle_panel.gd` (`class_name ChroniclePanel`, VBoxContainer, 아래 자리 오른쪽)

- `func bind_lab(lab)` — `experiments_changed` → 각 실험의 `world.chronicle` 로 다시 채움, `events_tagged(index, list)` → 덧붙임(최신이 위). 비교 모드면 줄 앞에 A/B.
- 줄: "틱 N · 평균 G세대 · 문장"(종류 색 띠). 거르기(OptionButton): 전체·발견·건물(저장고·첫 밭)·밭 잃음·세대·멸종. 최대 `ui.chronicle.max_items` 줄(넘치면 "더 오래된 K개" 표시).
- 줄을 누르면 `lab.request_cursor(tick)`, 행위자(`actor ≥ 0`)가 있으면 `lab.select_slime(actor, index)`.
- `func item_count() -> int` · `func item_text(i) -> String`(검사용).

**구현 메모(4단계, 연대기 담당이 덧붙임)**

- 더한 멤버:

  | 멤버 | 뜻 |
  |---|---|
  | `signal row_activated(tick: int, actor: int, index: int)` | 줄을 눌렀을 때(행위자 없으면 -1, 실험 번호). LabMain 없이도 받을 수 있게(비교 모드 검사) |
  | `func set_experiments(list: Array)` | `experiments_changed` 와 같음: 각 `world.chronicle` 을 처음부터 읽어 **우리 사본** 줄로(연대기 사전은 고치지 않음, 검사). `bind_lab` 도 지금 실험을 바로 이것으로 읽음 |
  | `func append_events(index: int, list: Array)` | `events_tagged` 와 같음: 새 사건만 덧붙임. 다시 읽을 때 연대기에 이미 있던 사건(그때 아직 비우지 않은 것)은 **연대기 위치로** 건너뜀: LabMain 은 `drain_events` 바로 뒤에 보내므로 목록 = 연대기의 끝이고, 그 가운데 위치가 다시 읽은 항목 수보다 앞인 것만 뺌(두 번 들어가지 않음). 틱으로 거르지 않음 — 발견·저장고·첫 밭·밭 잃음은 한 틱을 진행하는 도중에 진행 전 틱 번호를 달고 나와, "다시 읽은 틱 이하 = 이미 읽음" 으로 거르던 때는 스냅숏을 열거나 비교를 끝낸 바로 뒤 틱의 사건을 잃었음(검사). 연대기의 끝과 다른 목록(검사가 꾸며 넣은 사건)은 모두 덧붙임 |
  | `func set_filter(id)` · `filter()` · `const FILTER_*`(0 전체 · 1 발견 · 2 건물 · 3 밭 잃음 · 4 세대 · 5 멸종) · `const GROUP_OF`(kind → 묶음) | 거르기. 모르는 kind 는 전체에만 |
  | `func activate_item(i)` | 줄을 누른 것과 같음 |
  | `item(i) -> {tick, kind, actor, text, gen, index, group}` · `older_count()` · `group_count(id)` · `item_tooltip(i)` · `item_rect(i)`(전역) · `scroll_to_item(i)` · `list_stats() -> {drawn, shaped, height}` · `list_control()` · `var max_items`(바꾸면 `refresh()`) | 검사·캡처용 |
  | `static wrap_text(font, text, fs, width, max_lines, ellipsis)` · `ellipsize(...)` · `group_color(g)` · `commas(v)` | 도움 함수 |

- 배치(노드 이름 고정): `Head`(HBox: "연대기" 굵게 · 흐린 열 설명 "틱 · 평균 세대 · 사건 — 최신이 위"(다 들어가지 않으면 `HINT_SHORT` "틱 · 평균 세대 · 사건", 전체는 말풍선 — 4단계 검토 G55 의 연대기 몫, 통합 때: 1280 창에서 "… — 최…" 로 잘렸음; `hint_text()`) · `Filter` OptionButton) / `Card`(CardPanel) ⊃ `Rows`(목록 Control) | `Scroll`(VScrollBar). 폭 `ui.chronicle.width`, 자기 테마 = `UiTheme.build()`(실험실 뿌리와 같은 것 — 혼자 띄워도 같은 모양). 거르기 단추는 키보드 초점을 받음(검토 고침 J16 — `ParamPanel.keyboard_focus`: Tab·Enter 로 차림표, 스페이스는 LabMain 이 먼저 멈춤으로 받아 차림표가 열리지 않음, 마우스로 누르면 초점을 남기지 않음, 패널 `_input` 이 왼쪽 누름에서 단추 초점을 풂), 목록은 초점을 받지 않음(줄 고르기는 마우스).
- 목록 = **Control 하나가 보이는 줄만 그림**(300줄이어도 노드 9개, 검사). 줄 = 종류 색 띠(`ui.chronicle.stripe_width`) · [비교: A/B 이름표 — 테두리 = `ui.graph.series_a`/`series_b`] · "틱 N"(숫자 오른쪽 맞춤) · "G세대"(흐림 — 목록 안에서만 "평균" 을 줄임, 머리 줄·풍선 도움말·`item_text` 에는 있음. G = 사건의 `mean_gen` 그대로 0.01 단위 = chronicle.csv — 0.1 단위로 한 번 더 반올림하면 반올림 전 값으로 쓴 문장 속 "(평균 X세대)" 와 어긋났음: 4.35 → "4.4세대" 옆에 "평균 4.3세대") · 문장. 문장은 **낱말(빈칸) 단위로 접음**(ICU 줄바꿈은 한글 음절 사이 "남/은" 에서 끊어서 직접 접음, 한 낱말이 폭보다 길 때만 글자 단위). 다음 낱말이 넘치면 그 줄의 빈칸 가운데 덜 붙여 둔 마지막 자리에서 끊음: 숫자로 시작하는 낱말 앞("밭 1곳이"·"시도 121회")과 괄호 안("(30, 0)"·"(남은 밭 55)")은 다른 자리가 없을 때만(괄호 묶음이 폭보다 넓을 때 — 그때도 수는 앞 낱말과 함께 "(남은" / "밭 55)"). 시뮬레이션 문장은 그대로, 최대 `ui.chronicle.text_max_lines` 줄 넘으면 말줄임, 풍선 도움말에 실험 이름·틱·평균 세대·문장 전체·누르면 하는 일. 줄마다 접은 결과를 사본 줄에 담아 두고 글 폭이 바뀔 때만 다시 접음(새 사건 하나 → 하나만, 검사). 열 폭(틱·세대)은 보이는 줄 가운데 가장 넓은 것.
- 보이는 줄 = 실험마다(거르기 묶음의) 줄 끝에서 틱이 큰 것을 골라 `max_items` 개(O(max_items)). 같은 틱이면 뒤 실험(B)이 위(한 틱에 A 다음 B 를 진행). 넘치면 맨 아래 "더 오래된 K개는 생략 — 내보낸 chronicle.csv 에 모두 있음". 거르기 항목에 사건 수 "발견 (3)"(모든 실험 합, 색 견본 = 띠 색 — 범례 구실).
- 스크롤: 막대는 늘 자리를 차지(나타났다 사라지며 글 폭이 바뀌어 다시 접히지 않게, 필요 없으면 투명). 휠 = `ui.chronicle.wheel_step_px`. 읽던 중(맨 위가 아닐 때) 새 줄이 위에 붙으면 읽던 줄이 제자리(검사), 맨 위를 보고 있었으면 새 줄이 보임.
- 고른 줄(누른 줄)은 강조(`ItemList` 의 selected 상자), 거르기를 바꿨다 와도 유지(그래프 시점 표시와 맞게), 실험이 바뀌면 지움. 행위자 고르기: LabMain 의 `select_slime` 이 실험 번호를 받으면(인자 2개) `select_slime(actor, index)`, 3단계처럼 id 하나만 받으면 A(0) 의 줄만 고름(B 의 id 를 A 세계에서 고르면 다른 개체).
- 띠 색 `ui.chronicle.colors`(묶음별: `discovery` 민트 = 테마 강조 · `building` 파랑 · `farm_lost` 주황 = 경고 · `milestone` 회청 · `extinction` 빨강 = 위험 · `other`). 어두운 바탕(#15181d)에서 색각 이상 모의 모든 쌍 ΔE ≥ 9.8, 빨강·주황(위험·경고 뜻 색)은 정상 시각 ΔE 14.8 — 색만으로 구별하지 않고 문장이 종류를 말함. 글자 크기 = `ui.chronicle.text_font_size`(문장)·`ui.lab.font_size_small`(틱·세대), 여백 `row_pad_v`·`col_gap`·`badge_pad_h`·`badge_radius`·`badge_gap`(A/B 이름표와 틱 사이), 견본 `swatch_px`.
- 캡처: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/chronicle_capture.gd -- --out=폴더 [--extra]` → `chronicle.png`(demo_fast·씨앗 1·세대 이정표 10세대마다, 2,130틱 — 발견 3·저장고 4·첫 밭·밭 잃음 3·세대 2. 왼쪽 420×220 = 아래 자리 높이, 첫 밭 줄을 누른 상태 / 오른쪽 420×300). `--extra`: `chronicle-compare`(A/B)·`chronicle-filter`(건물)·`chronicle-filter-farm`·`chronicle-limit`(max_items 6)·`chronicle-empty`·`chronicle-extinct`(기본·자원 절반·씨앗 1 — 4세대까지 번식한 뒤 699틱 멸종, 멸종 줄 "4.00세대").
- 검사 `tests/view/chronicle_checks.gd`: 다시 읽기·순서·글·중복 없음·덧붙이기·거르기(단추 포함)·연대기 그대로·400개에서 300줄 + "더 오래된 100개"·노드 수·보이는 줄만 그림·새 줄만 접음·읽던 줄 제자리·긴 문장 말줄임·풍선 도움말·휠·고른 줄 유지·크기, 비교 모드는 `Experiment` 둘을 `set_experiments([A, B])`·`append_events(1, …)` 로(A/B 머리·틱 순 섞기·같은 틱이면 B 위·`row_activated(틱, 행위자, 1)`·실제 마우스 클릭), 실험실 연결(`bind_lab` 두 번에도 한 번씩 · `advance_frame` 의 `events_tagged` · 마우스로 첫 밭 줄 → `request_cursor` + 그 개체 선택 · 역사 해시 그대로), 다시 읽은 바로 뒤 틱의 사건(demo_fast·씨앗 2 의 126틱 "저장 발견"·"저장고 1호": `set_experiments` 뒤 — 비우지 않은 사건이 있을 때·없을 때 —, 실험실에서 스냅숏을 열고, 비교를 끝내고 한 틱 → 줄 수 = 세계 연대기), 줄의 평균 세대 = 저장값·문장과 어긋나지 않음(씨앗 1 의 422틱 "4.35세대" · 문장 4.3), 낱말 단위 줄바꿈(괄호 안·숫자 앞에서 끊지 않음 — 여러 폭에서 줄마다 괄호 짝·숫자로 시작하는 줄 없음, 폭보다 넓은 괄호는 안에서 접되 수는 앞 낱말과), 머리 줄 설명이 좁은 폭(320·331)에서 짧은 판·넓으면 전체로 칸 안(통합 때). `MIN_CHECKS` = 실제 검사 수(86 — 고정 씨앗이라 늘 같음).

## LabSound — `scripts/ui/lab_sound.gd` (`class_name LabSound`, Node)

- 실행 중 파형 합성(사인·삼각, 감쇠 포락선, 16비트 `AudioStreamWAV`) — 외부 음원 없음, CC0 로 CREDITS 에.
- 소리: 발견(두세 음 차임), 멸종(낮은 음), 저장고 건설(짧은 톡). `func play_event(kind) -> bool`, `var enabled`(`ui.sound.enabled`), 음량 `ui.sound.volume_db`, 같은 소리 최소 간격 `ui.sound.min_interval_s`(빨리 감기에서 몰려도 시끄럽지 않게).
- `func bind_lab(lab)` — `events_tagged` 를 받아 재생. `static func synth(kind: String) -> AudioStreamWAV`(검사: 길이·최댓값·NaN 없음·같은 입력이면 같은 바이트).

**구현 메모(4단계, 소리 담당이 덧붙임)**

- 합성(`synth(sound)` — 부를 때마다 새로, 같은 설정이면 같은 바이트): 음마다 사인 + 약한 배음(`harmonics` = 1·2·3배음 세기), 올림 `attack_s` 뒤 `exp(−decay_per_s·t)`, 음높이 `hz` → `hz_end` 를 `glide_s` 동안 지수 미끄럼(위상을 샘플마다 쌓아 끊김 없음). 소리 전체에 처음 `ui.sound.fade_s`·끝 `release_s` 의 사인 제곱 덮개 → 처음·끝 샘플 0(딸깍 없음), 최댓값을 `peak`(≤ 0.8 FS)로 맞춰 16비트 모노 `ui.sound.mix_rate`(22050 Hz), 반복 없음. 난수 없음.
  - 발견 `ui.sound.discovery`: G5·C6·E6(784·1047·1319 Hz) 세 음이 0.085초 간격으로 오르는 차임, 0.95초, 최댓값 0.6.
  - 멸종 `ui.sound.extinction`: 220 → 110 Hz 로 1초 동안 내려가는 낮은 음, 1.15초, 최댓값 0.6.
  - 저장고 `ui.sound.store_built`: 1050 → 620 Hz 로 0.03초 만에 떨어지는 짧은 "톡", 0.16초, 최댓값 0.42(자주 나서 작게).
  - `func synth_samples(sound) -> PackedFloat32Array`(−1~1 샘플, 검사용), `const SOUNDS`·`SOUND_OF`(kind → 소리: `first_farm` = 저장고 소리, 밭 잃음·세대는 소리 없음)·`PRIORITY`.
- 노드: 재생기(`AudioStreamPlayer`) `ui.sound.players` 개를 자식으로, 쉬는 것부터(모두 바쁘면 차례로). `_ready` 에서 세 소리를 미리 만듦(이 기계에서 합쳐 약 66ms, 한 번). `enabled = false` 면 내던 소리도 멈춤, `volume_db` 를 바꾸면 모든 재생기에. 트리를 떠날 때 멈춤(오디오 서버가 재생을 붙든 채 끝나지 않게).
- `play_event(kind)` = `play_event_at(kind, 지금 초)`: 꺼짐·소리 없는 종류·트리 밖·같은 소리(종류가 아니라 소리 이름 기준)를 `min_interval_s` 안에 다시 → false. `play_event_at` 은 시각을 받아 검사가 시계 없이 최소 간격을 확인. `play_events(list)`: 한 묶음에서 가장 중요한 소리 하나만(멸종 > 발견 > 저장고). `bind_lab` 은 `events_tagged`(A·B 모두)를 받아 그 프레임의 사건을 모았다가 프레임 끝(지연 호출)에 `play_events` 한 번 — 비교 모드에서 A·B 사건이 한 프레임에 와도 소리는 하나(4단계 검토 반영: 전에는 실험마다 하나씩이라 A 멸종과 B 차임이 겹쳤음). 받은 배열은 읽기만. `var plays`·`last_sound`·`player_count()`(검사용).
- 들어 보기: `godot --headless --path . --script res://tools/render_sounds.gd -- --out=폴더` → `discovery.wav`·`extinction.wav`·`store_built.wav`(저장소에 넣지 않음)와 길이·최댓값·처음/끝 샘플 출력.
- 검사 `tests/view/sound_checks.gd`: 소리마다 16비트 모노·표본율·길이 0.15~1.2초·최댓값 ≤ 0.8 FS 이고 들림·NaN/inf 없음·처음/끝 샘플 0 근처·처음/끝 1ms 가 서서히·다시 만들어도 같은 바이트, 발견이 멸종보다 높고 멸종은 내려감(영점 교차), 최소 간격·같은 소리를 쓰는 종류·1초에 100번 → 2번·꺼짐(내던 소리도 멈춤)·음량·묶음 우선순위·트리 밖 — "냄/안 냄" 은 셈(`plays`)만이 아니라 **실제 재생기**(`AudioStreamPlayer.playing` + 그 소리의 파형)까지(더미 드라이버도 play() 직후 재생 중), 실험실이 붙인 **자기** `LabSound` 의 `events_tagged`(A·B) 연결·한 프레임 A·B 묶음 → 소리 하나·두 번 붙여도 한 번과 실제 진행 사건·역사 그대로(4단계 검토 반영).

## 종단 검사 — `tests/view/integration4_checks.gd` (4단계 통합)

실제 실험실 장면(1280×720)에 실제 패널을 모두 붙인 채 패널 → 실험실 → 시뮬레이션 → 그래프·연대기로 이어지는 길을 확인한다(검사 58개, 프레임은 `advance_frame` 64배). 임시 폴더는 프로세스마다 따로(`user://integration4_checks-<pid>`), 처음과 끝에 숨은 파일까지 지운다.
① ParamPanel 에 예설정·씨앗·세 값·고급 키를 넣고 `apply()` → 새 세계의 `cfg`·씨앗·개체 수, "지금 실험과 같음", 화면으로 진행해도 헤드리스와 같은 상태·해시, 그래프 세 개 점 수 = 기록 줄 수.
② `set_compare_mode(true)` → A·B 칸(바꾼 값은 그 칸에만) → `apply_compare()` → 지도 둘, 범례 둘, B 에 첫 밭이 생길 때까지 진행 → A·B 모두 헤드리스와 같음, 그래프 계열 둘, 연대기 A/B 줄 수 = 두 연대기 합, 알림 이름표.
③ 연대기의 B 첫 밭 줄을 실제 마우스로 누름 → B 의 행위자 선택(실험 번호 1, 정보 창 이름표 B, 고리는 B 지도에만) + 그래프 시점 표시, 행위자 없는 A 줄 → 시점만, 두 세계 그대로.
④ 패널 `export_to(dir)` → `dir/A`·`dir/B` 의 timeseries.csv·chronicle.csv = 같은 예설정·바꾼 값·씨앗·틱 수의 헤드리스 실행기 결과(글자까지 — `record.every` 의 배수가 아닌 틱에서 내보내 끝 줄까지), summary.json 출처·이름표·해시, 알림의 절대 경로.
⑤ 비교 중 스냅숏 저장 → `-A`·`-B` 두 파일(저장 대화 상자 기본 이름에 두 씨앗 `-seed1-vs-seed2-tick<T>`), B 를 열면 혼자 모드로 같은 틱·해시, 혼자 저장 → 더 진행 → 열기 = 저장한 상태(헤드리스와 비교), 이어 돌려도 같음, 없는 파일은 오류 글.
⑥ "소리" 상자 ↔ `LabSound.enabled`, 실험실의 LabSound 가 `events_tagged` 에 붙어 있음. ⑦ `UiTheme.keep_words`(폭 그대로, 빈칸에서만 줄바꿈).

## 5단계 더함 — 웹 체험판 내려받기 (LabMain·ParamPanel)

| 멤버 | 뜻 |
|---|---|
| `static LabMain.is_web() -> bool` | 웹 체험판인지(`OS.has_feature("web")`) |
| `LabMain.results_zip_bytes() -> PackedByteArray` | `export_csv` 와 같은 결과 폴더(비교면 `A/`·`B/`)를 zip 바이트로(실패하면 빈 배열). 데스크톱에서도 같아 검사함. 임시 폴더 `user://web_export/<프로세스>-<µs>` 와 zip 은 끝나면(실패해도) 숨은 `.gdignore` 까지 지운다(4단계 검토 반영 — 전에는 내려받을 때마다 폴더가 하나씩 남았음). `last_zip_tmp_dir`(검사용) |
| `LabMain.download_results() -> String` · `download_snapshot(index := 0) -> String` | 웹: 브라우저 내려받기(`JavaScriptBridge.download_buffer`). 데스크톱: 같은 바이트를 `user://downloads/` 에 저장. 이름: 결과 = `default_export_dir()` 이름 + `.zip`(비교면 두 씨앗), 스냅숏 = `snapshot-<날짜-시각>-seed<그 실험의 씨앗>-tick<T>[-A/-B].json`. `last_download_name` = 마지막 파일 이름(검사용) |
| `ParamPanel.web_mode` · `set_web_mode(on)` | 웹이면 "결과 내려받기(zip)"·"스냅숏 내려받기"(비교면 A·B 두 파일), "스냅숏 열기" 숨김. 기본 = `LabMain.is_web()` |

검사: `tests/view/web_checks.gd`(혼자·비교 zip 내용, 임시 폴더가 남지 않음, 내려받기 이름의 씨앗, 검사가 쓴 파일은 끝에 지움). 앱 아이콘 `tests/icon_capture.gd`, 타임랩스 `tests/timelapse_capture.gd` + `tools/make_timelapse.sh`.
