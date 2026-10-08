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
| `func before_steps() -> void` | `step()` 을 부르기 **직전마다** 호출(한 프레임에 여러 틱이면 틱마다, 프레임 처음에도 한 번). 보간용으로 현재 위치(id → 칸)를 기억(틱이 바뀌었을 때만 복사) |
| `func update_view(alpha: float, delta: float = 1/60) -> void` | 매 프레임 `step()` 뒤에 호출. `alpha`(0~1) = **마지막 틱**의 진행률(보간·통통 튐), `delta` = 이 프레임 시간(따라가기 카메라). 슬라임·식물·건물·빛(낮밤)·선택 표시 갱신. 지형 색은 `ui.map.terrain_refresh_ticks` 마다 |
| `func set_selected(id: int) -> void` | 선택 표시(-1 = 없음). 죽은 개체면 표시 없음 |
| `func pick_slime(screen_pos: Vector2) -> int` | 뷰포트 좌표의 광선을 슬라임 몸 가운데 높이와 교차해 가장 가까운(그린 위치) 살아 있는 슬라임 id(반경 안에 없으면 -1) |
| `func focus_on(id: int) -> void` | 카메라를 그 개체로 옮김 |
| `func fit_map() -> void` | (추가) 지도 전체 맞춤(처음 방위·고각)으로 되돌리고 따라가기 끔. 다시 움직이기 전까지 뷰포트 크기가 바뀌면 다시 맞춤 |
| `func display_scale() -> float` | (추가) 지금 표시 배율(멀리서 작은 슬라임을 키운 배수, 가까이 1) |
| `var follow_selected: bool` | 켜면 선택한 개체를 카메라가 따라감 |
| `func get_camera() -> Camera3D` | 카메라 |
| `func view_stats() -> Dictionary` | `{slimes, plants, stores, farms, triangles_estimate}` (성능 기록용). `plants` = 먹이가 있어 보이는 풀포기, `triangles_estimate` = 그리기에 넘기는 삼각형(배율 0 으로 숨긴 풀포기 인스턴스·슬라임 발밑 그림자 포함) |
| 입력 | `_unhandled_input`: 왼쪽 끌기 = 이동, 휠 = 확대·축소, 오른쪽 끌기 = 회전, 왼쪽 클릭 = 고르기 |

**구현 메모(3단계, MapView 담당이 덧붙임)**

- 노드(이름 고정, 검사가 씀): `Camera`(궤도 카메라) · `Environment`(WorldEnvironment) · `Sun` · `Terrain`(ArrayMesh 하나) · `Farms` · `Stores` · `Plants` · `Dropped` · `Slimes` · `SlimeShadows` · `Carry`(MultiMeshInstance3D) · `SelectRing`.
- 궤도 카메라 `scripts/view/orbit_camera.gd`(Camera3D, 전역 이름 없이 `MapView.OrbitCamera` 로 preload): `target`·`yaw`·`pitch`·`distance`, `apply()`, `fit_rect(rect, aspect)`(네 모서리를 투영해 지도 전체가 들어오게), `pan_pixels(rel, vp_h)`, `zoom_at(screen_pos, steps)`(커서 아래 땅 점 고정), `rotate_pixels(rel)`, `ground_point(screen_pos, plane_y)`, `reset_orientation()`, `distance_max()`. 수치는 `camera` 절(`pitch_min_deg`·`pitch_max_deg`·`fit_margin`·`near`·`far`·`focus_distance`·`click_threshold_px`·`gesture_pan_px`·`fit_zoom_out_factor`·`follow_ref_fps` 추가).
- 최대 거리: 설정값 `camera.distance_max`(95) 로 지도 전체가 안 들어오는 큰 지도(128×96 이상, 설정 상한 1024)는 `fit_rect` 가 자르지 않고 맞춘 뒤, 실제 최대 거리 = max(설정값, 맞춘 거리 × `fit_zoom_out_factor`), 먼 자르기 면 = max(`camera.far`, 최대 거리 + 지도 대각선). `distance_max()` 는 실제 값(검사: 128×96·200×150 이 처음에 다 보임). 실시간 그림자는 꺼져 있어 `shadow_distance` 는 늘리지 않음.
- `bind` 는 앞 세계의 저장고·밭 인스턴스를 지우고(통합 때 고침: 건물 없는 새 세계에 앞 세계 건물이 남던 문제), 카메라를 처음 방위·고각으로 돌려 지도 전체를 맞춘다. 사용자가 카메라를 움직이기 전에는 뷰포트 크기가 바뀔 때(SubViewportContainer 배치 뒤 등) 다시 맞춘다.
- 트리에 들어가면 자기 SubViewport 의 `own_world_3d` 를 켠다(지연 호출) — 비교 모드에서 두 지도의 3D 세계가 섞이지 않게.
- `pick_slime` 은 땅(y 0)이 아니라 **슬라임 중심 높이**(메시 높이의 절반 × 표시 배율)의 수평면과 광선을 교차하고, 마지막으로 그린(보간된) 위치 중 `ui.map.pick_radius` × 표시 배율 칸 안의 가장 가까운 개체를 고른다. 클릭은 누른 곳에서 `click_threshold_px` 이상 움직이지 않고 뗐을 때.
- 보간: `before_steps()` 가 (틱이 바뀌었을 때만) id·칸·방향 배열을 복사해 두고, `update_view` 는 틱이 진행한 프레임에 그 복사본을 "이전 위치"로 올린다. 두 배열이 id 오름차순이라 두 포인터로 맞춘다(새로 태어난 개체는 지금 칸에 바로 나타남). **보간은 마지막 한 틱만**: LabMain 이 `step()` 마다 `before_steps()` 를 불러 복사본이 그린 틱의 한 틱 전이고, 복사본이 두 틱 이상 낡았으면(한 번만 부르고 여러 틱) 보간하지 않고 지금 칸에 그린다(낡은 자리에서 미끄러지지 않게). 움직인 개체는 `sin(π·alpha)` 로 뛰고 `sin(2π·alpha)` 로 늘었다 눌리며(부피 유지), 가만히 있으면 숨쉬기, 먹기·줍기·심기 중이면 끄덕임.
- 둘레 자리: 같은 칸의 여러 개체는 `slime.stack_offset` 둘레에 나뉘고, **저장고 칸**의 개체는 움집(처마 반지름 0.47) 안에 묻히지 않게 문 앞(+Z) 반지름 `map.store_slime_offset` 의 호에 `map.store_slime_arc_deg` 간격(넘치면 `store_slime_arc_max_deg` 안에)으로 선다. 둘레 자리는 틱이 바뀔 때 지금 배열과 이전 배열로 각각 계산하고(칸 안 자리 순서 = id 순서) 위치와 함께 보간한다 — 다른 개체가 들고 나도 가만히 있는 개체가 틱 경계에서 튀지 않는다(검사).
- 땅 높이: **밭 칸**에서는 슬라임 바닥·그림자·운반 열매를 흙판 윗면(`map.farm_lift` + 흙판 두께)에 올리고(칸 사이를 뛸 때 보간), 선택 고리는 이랑 꼭대기 위에 둔다.
- 풀포기: 슬라임이 서 있는(또는 이번 틱에 떠난) 칸의 풀포기는 `map.plant_occupied_scale` 배로 줄여 몸을 뚫고 나오지 않게 한다(틱이 바뀔 때만, 바뀐 풀포기의 변환만 다시 씀). `view_stats().plants` 는 먹이로 보이는 수 그대로.
- 표시 배율(멀리서): 카메라 목표 거리에서 크기 1 슬라임의 화면 지름이 `map.slime_min_px` 보다 작으면 그만큼 키운다(최대 `map.slime_display_scale_max`). 몸·뜀 높이·그림자·운반 열매·고르기 반경에 곱하고, 자리(칸·둘레)는 그대로. `focus_distance` 근처에서는 1(실제 크기). 시뮬레이션과 무관.
- 선택 고리: 실제 크기(반지름 × 크기 × `ring_scale` × 표시 배율)의 화면 지름이 `map.ring_min_px` 보다 작으면(전경) 최소 크기로 키우고 깊이 검사 없이 맨 위에 그린다(풀·밭·다른 개체에 가리지 않게). 가까이서는 실제 크기·깊이 검사.
- 따라가기: 목표가 프레임마다 `1 − (1 − camera.follow_lerp)^(delta × camera.follow_ref_fps)` 만큼 선택 개체로 다가간다(프레임 빠르기와 무관, 60fps 에서 예전과 같음).
- 땅 색 갱신은 위 사각형 부분의 정점 색(RGBA8)만 `ArrayMesh.surface_update_attribute_region` 으로 올린다. 식물(`plant_refresh_ticks`)과 땅 색(`terrain_refresh_ticks`)은 각자 최소 프레임 간격(`plant_min_frames`·`terrain_min_frames`)을 두고, 같은 프레임에 둘 다 하지 않는다.
- 메시 바닥 맞춤: 각 SlimeGeo 메시의 AABB 아래면을 y 0 에 맞춰 놓는다(조각 메시는 원래 0, 기본 도형 대용품은 가운데 원점). 인스턴스 색은 메시에 정점 색이 있으면 흰색(메시 색 그대로), 없으면 `ui.map`·`ui.buildings` 의 대신 색.
- 저장고는 Y 축으로 반 바퀴 돌려 놓는다: 메시 정면(-Z, 문)이 남쪽(+Z) = 처음 카메라 쪽을 보게. 밭은 그대로.
- 실시간 그림자는 끔(`map.shadows`): Compatibility 렌더러에서 해 그림자를 켜면 해 빛이 한 번 더 더해져 장면이 크게 밝아진다(측정: 같은 설정에서 #3c8735 → #51c148). 대신 슬라임 발밑에 부드러운 원판 그림자(`blob_shadow_*`, 빛이 떨어지는 쪽으로 조금 밀림).
- 밤에는 해·주변광·배경을 `night_*` 쪽 푸른 색으로 섞고, 슬라임 인스턴스 색을 `night_slime_boost` 배까지 밝혀 계통 색이 읽히게 한다. 계절마다 풀밭 색에 `season_tints` 를 조금 섞는다.
- 검사·기록용 추가 함수: `terrain_tile_color(c) -> Color`(칸의 지금 위 사각형 색), `slime_instance_position(k) -> Vector3`(k 번째 슬라임 인스턴스 위치), `slime_instance_scale(k) -> Vector3`(축별 배율), `shadow_instance_position(k)`, `plant_scale_at(c) -> Vector2`(그린 세로 배율, 먹이량만의 배율), `ring_info() -> {visible, radius, on_top, position}`, `view_stats()` 의 `slime_us`·`plant_us`·`terrain_us`(마지막 갱신 시간 µs).
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
| `func set_empty_text(text: String) -> void` | (추가) 빈 상태 안내 문구("" = 기본). LabMain 이 멸종하면 "멸종했습니다 (틱 N) — 고를 개체가 없습니다" |
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
  | `func visible_toasts() -> Array[Dictionary]` | 보이는 알림 `{kind, text, left, count}`(`count` = 묶인 사건 수) |
  | `func fit_map() -> void` | 지도 전체 보기(Home 키·지도 위 "전체 보기" 단추): `map_view.fit_map()` + 정보 창 따라가기 단추 끔 |
  | `is_paused()`·`is_fast_forward()`·`target_speed()`·`selected_id()`·`speed_text()` | 지금 상태 |
  | `var last_sim_ms: float`, `var last_budget_hit: bool` | 마지막 프레임의 시뮬레이션 시간과 예산을 다 썼는지(성능 기록용) |

- 프레임 순서(`advance_frame`): 알림 시간 줄이기 → `map_view.before_steps()`(**매 프레임**, 멈춰도·틱이 없어도) → 멈춤이 아니면 진행(**틱마다** `before_steps()` → `step()`) → `map_view.update_view(alpha, delta)` → 실제 배속 창에 기록 → 1틱 이상이면 `ticked` → `drain_events()` 가 비어 있지 않으면 `events` + 알림 → 멸종하는 순간이면 멈춤·안내 → `ui.info.refresh_frames` 마다 `info_panel.refresh()` → 위쪽 막대 표시.
  - 보통: `누적 += delta × ticks_per_second_1x × 배속`, 누적 ≥ 1 인 동안 `step()`. 2틱째부터 (지금까지 시간 + 한 틱 비용 추정)이 `sim_budget_ms` 를 넘으면 멈추고 **밀린 몫을 버림**(누적의 소수 부분만 남김 — 밀린 틱이 쌓여 점점 느려지지 않게). 한 틱 비용 추정 = 잰 `step()` 시간의 지수 이동 평균(`speed.step_estimate_alpha`). `alpha` = 누적의 소수 부분(0~1) = 마지막 틱의 진행률.
  - 빨리 감기: 적어도 1틱, 그 뒤 (지금까지 시간 + 한 틱 비용 추정)이 `fast_forward_budget_ms` 안이면 계속 `step()`. 누적은 **1**(= 지금 틱의 끝), 그래서 `alpha = 1` 이고 빨리 감기 중 멈추거나 보통 속도로 돌아가도 그린 자리가 낡지 않는다(다음 보통 프레임은 바로 한 틱 진행).
  - 진행(누적·알림 시간)은 `delta` 를 `ui.speed.max_frame_delta_s` 로 자른 값으로(창을 끌거나 멈칫한 프레임이 한꺼번에 몰아 돌지 않게). 실제 배속 측정은 **자르지 않은** `delta`(창 길이까지)로 — 4FPS 아래에서도 정직하게.
  - 사건은 진행 여부와 관계없이 매 프레임 비움(검사·캡처가 `world.step_n` 으로 직접 진행한 사건도 다음 프레임에 알림).
- 실제 배속 = 최근 `actual_speed_window_s` 동안의 (진행한 틱 몫의 합 ÷ 프레임 시간 합) ÷ `ticks_per_second_1x`. 틱 몫 = 이 프레임의 틱 수 + 누적의 변화(정수 틱이 아니라 소수 몫까지 — 따라가면 정확히 목표 배속, 예산에 걸려 버린 몫은 빠짐), 빨리 감기는 틱 수, 멈춤은 0. 프레임 시간은 `advance_frame` 에 들어온 `delta`(검사에서 결정적). **배속·멈춤·빨리 감기를 바꾸거나 세계를 바꾸면 창을 비운다**(앞 배속의 프레임으로 거짓 "뒤처짐" 경고가 뜨지 않게, 세계를 바꾼 직후 첫 프레임은 넣지 않음). 창이 `WARMUP_FRACTION`(1/4) 차기 전에는 "실제 —", 표시는 `speed.label_refresh_s` 마다 갱신, 창이 `speed.behind_min_fill` 이상 찼고 실제가 목표 × `speed.behind_ratio` 보다 낮으면 경고 색.
- 배치(코드로 만듦, 노드 이름 고정): `Background`(ColorRect) · `Column`(VBox) = `TopBar` / `Middle`(HBox) = `LeftWrap`(PanelContainer `DockPanel`, 폭 `left_panel_width`) ⊃ `LeftDock` | `MapArea`(Control, 늘어남) ⊃ `MapContainer`(SubViewportContainer `stretch`) ⊃ `MapViewport`(`own_world_3d`, `msaa_3d = lab.map_msaa`) ⊃ `MapView` + 지도 위 표지(`MapTitle` 실험 이름·멈춤·`ExtinctBadge` "멸종 · 틱 N"(위험 색)·`FitButton` "전체 보기", `MapHint` 조작 도움말, `Toasts`) | `InfoPanel`(폭 `right_panel_width`) / `BottomWrap`(높이 `bottom_panel_height`) ⊃ `BottomDock`. 두 자리는 자식이 없으면 감싸개째 숨고, 자식을 넣으면(지연 호출로) 보인다. 표지·알림은 마우스를 통과시킨다("전체 보기" 단추만 받음).
- 위쪽 막대: 재생/멈춤·빨리 감기는 **코드로 그린 아이콘**(`UiTheme.icon`, ⏩ 가 나눔고딕에 없음), 멈추면 ▶ 가 경고 색. 속도 단추는 `ButtonGroup`(빨리 감기 중에는 모두 꺼짐, 속도를 고르면 빨리 감기 꺼짐). 상태: 틱 · 날(`tick / day_ticks + 1`) · 계절(봄·여름·가을·겨울 / 계절 없음) · 낮/밤(`light ≥ lab.day_light_threshold`) — 날·계절·빛은 모두 같은 틱(SIM-API: 틱 사이의 `light`·`season` 은 지금 틱) │ 평균 세대(개체가 없으면 "—", 흐린 색) · 개체(0 이면 "멸종", 위험 색) · 문명(`SimWorld.STAGE_NAMES`) …… "목표 N배 / 실제 M배"·"빨리 감기 / 실제 M배"·"멈춤 · 목표 N배". 가장 긴 표시(틱 7자리 등)에서도 최소 창 폭 1280 안(검사).
- 멸종: 멸종하는 순간 한 번 `lab.pause_on_extinction`(기본 켬)이면 멈추고(헤드리스 실행기의 끝 조건과 같게), 정보 창 빈 안내를 멸종 문구로(`set_empty_text`), 지도 위에 "멸종 · 틱 N" 표지를 계속 보인다. 다시 재생하면 빈 지도가 계속 진행. 멸종 때문에 저절로 멈춘 상태는 새 실험·스냅숏에서 풀리고, 이미 멸종한 스냅숏을 열면 멈추지 않는다.
- 알림: 사건 문장 그대로 + 흐린 "틱 N". 왼쪽 띠 = 종류 색, 발견(`★ 새 발견` 머리)은 강조 색 테두리, 멸종·오류는 위험 색 테두리, 경고(`warn`)는 경고 색 테두리, 밭 잃음은 경고 색 띠만. 긴 문장은 줄을 바꿔 지도 폭 안에(폭 = min(`lab.toast_max_width`, 지도 폭 − 양쪽 `map_overlay_margin`), 빈칸 없는 경로도 끊음). `lab.toast_coalesce_kinds`(밭 잃음)의 종류는 이미 보이는 같은 종류 알림을 새 문장으로 고쳐 쓰고 "×N" 을 붙여 맨 아래로(하나만 보임). 최대 `lab.toast_max` 개 — 넘치면 강조 알림(발견·멸종·오류·경고)이 아닌 것 가운데 오래된 것부터 지우고, 모두 강조면 가장 오래된 것. `toast_seconds`(오류·경고는 `toast_error_seconds`) 뒤 사라지며 마지막 `toast_fade_seconds` 동안 흐려짐. **세계를 바꾸면(새 실험·스냅숏) 앞 세계의 알림을 지운다**(백업 경고는 바꾼 뒤에 띄움). 명령줄 오류는 알림과 함께 터미널(`printerr`)에도 전체 문장.
- 선택: `map_view.slime_clicked(id)` → `select_slime(id)`(-1·없는 id = 해제; 죽은 개체 id 는 기록으로 표시), `info_panel.slime_requested(id)` → `select_slime(id)` + `map_view.focus_on(id)`, `info_panel.follow_toggled(on)` → `map_view.follow_selected = on`.
- 단축키는 `_input` 에서 받아 처리하면 소비한다(초점 있는 단추가 스페이스를 먹지 않게). **`LineEdit`·`TextEdit` 에 초점이 있거나 Ctrl·Alt·Meta 가 눌렸으면 무시**. 1~7 은 숫자판 키도. F 는 `map_view.follow_selected` 를 뒤집고 알림, 정보 창의 따라가기 단추도 `info_panel.set_follow()` 로 맞춘다(통합 때 연결).
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

**구현 메모(3단계)**: `--out` 기본값 `res://docs/screenshots/v0.1`, `--copy=폴더` 를 주면 그림을 그곳에도 복사. 프레임은 `advance_frame(1/60)` 으로 몬다(④만 실제 `_process`).
① `lab-01-overview` 기본·씨앗 1 을 8배로 600프레임(480틱) → 해시 비교, 지도 클릭(화면 가운데에 그린 개체를 몸 가운데 높이로 투영 → `pick_slime` 이 바로 그 개체여야 하고, 실제 마우스 입력으로 눌러 정보 창·선택 id 확인, 지도 모서리 클릭 → 선택 해제), 재생·속도·빨리 감기 단추 클릭, 스페이스. ② `lab-02-farm-selected` fast_civ·씨앗 1 을 농사 단계 + 밭 3칸까지(약 1,670틱) → 해가 다 뜰 때까지 진행(낮 장면) → 밭에서 2·4·6칸 안(가까운 것부터)에 있고 남은 수명이 90틱 이상인 개체 가운데 자식이 가장 많은 개체 선택·`focus_on` → 쌓인 사건 알림, 정보 창이 스크롤 없이 두뇌 범례까지(V07, 1600×900 에서 여유 `info.min_vertical_slack` 이상). ③ `lab-03-night` 밤까지 진행 → 같은 개체로 다시 `focus_on`(②와 같은 자리를 낮·밤으로 견줌) → 멈춘 모습. ④ `lab-04-speed64` 64배 단추 클릭 → 실제 시간 150프레임 → "목표 64배 / 실제 M배" 와 해시 비교. 그림은 JPG(품질 0.85, 600KB 이하 확인). 그림 폴더 `docs/screenshots/` 에는 `.gdignore`(가져오기 제외).

## 성능 측정 — `tests/perf_capture.gd` (통합)

- 헤드리스 미세 측정: `godot --headless --path . --script res://tests/perf_capture.gd -- --bench` — 1260×856 SubViewport 의 MapView 에 대해 프레임마다 `before_steps` + `update_view` 시간(틱 있는 프레임·없는 프레임 따로, 중앙·95%·최대)과 시뮬레이션 시간을 1·4·64배(60fps 가정)로 잰다. 세계: 기본 `population.initial = 250`(씨앗 11), fast_civ 1,760틱(씨앗 1).
- 실험실 실측: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/perf_capture.gd [-- --seconds=N --msaa=N]` — 기본·씨앗 1 을 1,500틱 넘게, 개체 200 이상이 될 때까지 진행한 뒤 1배·64배로 각 N초(기본 10) 실제 시간 진행. `LabMain.advance_frame` 을 실제 프레임 시간으로 직접 불러 FPS·프레임 시간·우리 스크립트 시간(시뮬레이션 `last_sim_ms` + 화면·UI 나머지)·그리기 호출·기본 도형 수를 출력한다. 그리기 호출은 전체(모든 뷰포트 합)와 함께 **뷰포트별**로: 지도 SubViewport(3D)의 그리기 호출·기본 도형, 뿌리 창 2D(UI)의 그리기 호출. `--msaa` 는 지도 MSAA 를 바꿔 잰다. llvmpipe(CPU 소프트웨어 GL)에서는 그리기 몫이 대부분이라 실제 GPU 의 FPS 를 뜻하지 않는다.

# 4단계 계약 — 파라미터·그래프·연대기·내보내기·비교

## Experiment — `scripts/ui/experiment.gd` (`class_name Experiment`, RefCounted) — 완성(바꾸지 않음)

세계 + 기록기 + 만든 조건. 기록은 헤드리스 실행기와 **같은 줄**(만들 때 한 줄, `tick % record.every == 0` 이 되는 step 마다 한 줄). `tests/view/experiment_checks.gd` 가 "화면 쪽 timeseries.csv = 실행기 결과(글자까지)"를 검사.

| 멤버 | 뜻 |
|---|---|
| `static create(preset, overrides, seed) -> {experiment, error}` · `static from_snapshot(path) -> {experiment, error, status}` | 만들기 |
| `world`, `recorder`, `preset`, `overrides`, `seed_value`, `snapshot_path`, `label`, `tag`("A"/"B"/"") | 상태(읽기 전용) |
| `step() -> bool`(이번에 기록했으면 true) · `step_n(n)` | 진행(LabMain 만 부름) |
| `rows() -> Array` | 기록한 시계열 줄(`SimRecorder.TIMESERIES_COLUMNS` 키 사전). **읽기 전용** |
| `display_name()` | "A · 기본 · 씨앗 1"(혼자면 label) |
| `export_dir(dir, with_lineage := true) -> PackedStringArray` | summary.json(`source = "lab"`)·timeseries·chronicle·lineage·final.snapshot.json, 실패한 파일 이름 |
| `save_snapshot(path) -> String` | 스냅숏 저장 |

## LabMain 4단계 API (LabMain 담당이 비교 모드를 채움)

| 멤버 | 뜻 | 상태 |
|---|---|---|
| `var experiments: Array[Experiment]` · `experiment(index)` | 진행 중인 실험(혼자 1개, 비교 2개 [A, B]). `world` = `experiments[0].world`, `map_view` = A 의 지도 | 됨 |
| `signal experiments_changed(list: Array)` | 실험 목록이 바뀜(새 실험·스냅숏·비교 시작/끝) — 패널은 처음부터 다시 읽음 | 됨 |
| `signal recorded(index: int, row: Dictionary)` | index 번째 실험이 한 줄 기록 | 됨 |
| `signal events_tagged(index: int, list: Array)` | index 번째 실험의 새 사건(사본). `events(list)` 는 A 만(3단계 호환) | A 만 됨 → 비교 때 B 도 |
| `signal cursor_tick_requested(tick: int)` · `func request_cursor(tick)` | 그래프 시점 표시 요청(연대기 → 그래프), -1 = 지움 | 됨 |
| `func new_experiment(preset, overrides, seed) -> String` · `open_snapshot(path)` | 혼자 모드로 바꿔 시작 | 됨 |
| `func start_compare(a: Dictionary, b: Dictionary) -> String` | a·b = `{preset, overrides, seed}`. 지도 둘을 나란히(A 왼쪽 · B 오른쪽, 사이 `ui.compare.gap_px`), 같은 배속으로 틱마다 A 다음 B 를 진행(예산은 둘 몫을 합쳐 셈), 사건 알림 앞에 "A · "/"B · " | **뼈대 → LabMain 담당** |
| `func stop_compare()` · `func is_comparing() -> bool` | 비교 끝(A 만 남김) | **뼈대 → LabMain 담당** |
| `func select_slime(id, index := 0)` | 비교 모드에서 어느 실험의 개체인지(정보 창 머리에 A/B 표시, 그 지도에만 고리) | **LabMain 담당** |
| `func save_snapshot(path, index := 0) -> String` | 스냅숏 저장 + 알림 | 됨 |
| `func export_csv(dir) -> String` | 결과 폴더 내보내기(비교면 `dir/A`·`dir/B`) + 알림(절대 경로) | 됨 |
| `func default_export_dir() -> String` | `user://experiments/<날짜-시각>-seed<N>` | 됨 |
| `func step_ticks(n)` | 프레임 없이 모든 실험 n틱(기록·`recorded` 포함, 검사·캡처용) | 됨 |
| 자리 채우기 | `_ready` 에서 `ParamPanel` → `left_dock`, `GraphPanel`(늘어남) + `ChroniclePanel`(폭 `ui.chronicle.width`) → `bottom_dock`, `LabSound` → 자식. 각각 `bind_lab(self)` | **LabMain 담당** |

## ParamPanel — `scripts/ui/param_panel.gd` (`class_name ParamPanel`, VBoxContainer, 왼쪽 자리)

- `func bind_lab(lab: LabMain)` — `experiments_changed` 를 받아 "지금 실험" 값을 표시.
- 칸: 예설정(OptionButton, `label`) · 씨앗(SpinBox, 0~`ui.param.seed_max`, "무작위" 단추 — 화면 쪽 시각에서 고름, 시뮬레이션 난수와 무관) · **돌연변이율**(`mutation.rate`, 슬라이더+숫자) · **자원량**(`resources.scale`) · **초기 개체 수**(`population.initial`) · "고급 설정"(접힘: `sim-defaults.json` 의 수·참거짓 잎 키를 절별로, 바꾼 값은 강조) — 값의 기본은 고른 예설정이 적용된 값. 값을 바꿔도 지금 실험에는 적용되지 않고 "새 실험을 눌러 적용 · 바꾼 값 N개" 표시.
- 단추: **새 실험**(AccentButton) → `lab.new_experiment(...)`(오류는 패널 안 빨간 글 + 알림) · 되돌리기(예설정 값으로) · **비교 모드**(켜면 B 칸이 나타남: 예설정·씨앗·세 값, "나란히 시작" → `lab.start_compare(a, b)`, 끄면 `lab.stop_compare()`) · **CSV 내보내기**(`lab.export_csv(lab.default_export_dir())`) · **스냅숏 저장 / 열기**(FileDialog, 파일 시스템, 시작 폴더 `user://experiments`, `.json`) · 소리 켜기(`LabSound.enabled`, 있을 때).
- `func current_settings(which := 0) -> Dictionary` = `{preset, overrides, seed}`(which 1 = B 칸) · `func set_value(key: String, value, which := 0)` · `func apply() -> String`(새 실험 단추와 같음) — 검사용.
- 수치(범위·폭·간격)는 `ui.param`.

**구현 메모(4단계, ParamPanel 담당이 덧붙임)**

- 더한 멤버(검사·캡처·통합용):

  | 멤버 | 뜻 |
  |---|---|
  | `set_value(key, value, which := 0) -> String` | 돌려주는 값 = 이 값의 오류 또는 그 칸 조건의 오류(`""` = 문제 없음). 특별 키 `"preset"`(예설정 이름)·`"seed"`. 글자 값은 칸에 적은 것처럼 해석 |
  | `apply_compare() -> String` | "나란히 시작" 단추와 같음: `lab.start_compare(current_settings(0), current_settings(1))`, 오류는 패널 안 빨간 글 + 알림 |
  | `revert()` · `set_compare_mode(on)` · `is_compare_mode()` | 되돌리기·비교 모드 단추와 같음 |
  | `export_to(dir) -> String` | CSV 내보내기 단추가 `lab.default_export_dir()` 로 부르는 함수(검사는 임시 폴더로) |
  | `open_snapshot_dialog(save) -> FileDialog` · `save_snapshot_to(path)` · `open_snapshot_from(path)` | 스냅숏 대화 상자 띄우기, 고른 파일로 저장·열기(대화 상자의 `file_selected` 가 부름) |
  | `random_seed(which := 0) -> int` | "무작위" 단추와 같음 |
  | `set_advanced_open(on)` · `set_advanced_target(which)` | 고급 설정 펼치기, 비교 모드에서 고급 설정이 보여 줄 칸(A/B) |
  | `status_text()` · `error_text()` · `now_text()` · `field_text(key, which)` · `is_highlighted(key, which, advanced)` · `row_error(key, which, advanced)` · `control(id)` | 상태 줄·오류 글·"지금 실험" 글·칸 글자·강조·줄 아래 오류·노드 찾기(`"apply"`, `"slider:<키>:0"`, `"adv:<키>"` 등 — 주석 참고) |
  | `static leaf_kind(key)` · `leaf_keys()` · `format_value(key, v)` | 설정 잎 키 종류(`int`·`float`·`bool`·`other`)·목록·값 글자 |
  | `TEXT_SAME`·`TEXT_PENDING`·`TEXT_PENDING_COMPARE`·`TEXT_COMPARE_IDLE`·`MAIN_KEYS`·`KIND_*`·`SNAPSHOT_DIR` | 상태 줄 문구·세 주요 키·종류·스냅숏 시작 폴더(`user://experiments`) |

- **칸 = 다음 실험 조건.** 칸마다(A, 비교 모드면 B) `{preset, seed, overrides}` 를 들고, `overrides` 에는 고른 예설정과 **다른 값만** 넣는다(예설정과 같은 값을 적으면 빠짐). 예설정을 고르면 바꾼 값을 지우고 그 예설정 값으로(씨앗은 그대로). 되돌리기는 보이는 칸의 바꾼 값을 지운다(씨앗은 그대로).
- **검사:** 값이 바뀔 때마다 `SimConfig.build(preset, overrides)` 그대로 + 패널 규칙 하나(초기 개체 수 ≤ `population.cap` — 넘으면 처음부터 번식이 막힘). 오류 문장이 가리키는 키의 줄(없으면 마지막으로 바꾼 줄) 바로 아래에 빨간 글, 이름은 위험 색. 칸에 해석할 수 없는 글자(수가 아님, 정수 키에 소수, 배열 키)는 그 줄 아래 오류를 보이고 값은 그대로 둔다. 오류가 있으면 새 실험·나란히 시작 단추를 못 쓰고, `apply()` 도 실험실에 넘기지 않는다(지금 실험 그대로, 오류 알림).
- **강조 = 지금 실험과 다른 값**(왼쪽 강조 색 띠 + 강조 색 값; 띠는 꺼져도 자리를 지켜 이름이 흔들리지 않음). 견주는 기준은 칸과 같은 자리의 지금 실험(비교 중이 아니면 B 칸도 A 실험과 견줌 — B 에서 바꾼 변인만 강조). 상태 줄: `지금 실험과 같음` / `바꾼 값 N개 · 새 실험을 눌러 적용`(비교 중이면 `… 나란히 시작을 눌러 적용`, 비교 전이면 `나란히 시작을 누르면 A·B 를 함께 시작`, 오류면 위험 색 `설정 오류 — …`). N = 설정 잎 키 가운데 다른 것 + 씨앗이 다르면 1. 고급 설정 머리에는 따로 "예설정과 다른 값 K개".
- **지금 실험:** `experiments_changed` 마다 실험별 `label`(A/B 이름표 + `ui.graph.series_a`·`series_b` 색 점)과 세 값(`world.cfg` 를 깊은 사본으로 떠서 읽기만 함)을 다시 쓰고, **칸도 그 실험의 조건으로 맞춘다**(만든 실험 = 그 조건 그대로, 스냅숏 = 다른 값이 가장 적은 예설정 + 다른 값 — 그래서 스냅숏을 열어도 "지금 실험과 같음", 새 실험을 누르면 그 설정·씨앗으로 0틱부터 다시). 실험이 둘이 되면 비교 모드 단추가 켜지고, 둘에서 하나로 줄면 꺼진다.
- **세 주요 값:** 슬라이더(마우스 휠로는 안 바뀜) + 오른쪽 숫자 칸. 범위 `ui.param.mutation_rate_max`·`resource_scale_max`, 초기 개체 수는 `ui.param.initial_min` ~ min(`ui.param.initial_max`, 그 칸 조건의 `population.cap`). 눈금 `ui.param.mutation_rate_step`·`resource_scale_step`·`initial_step` — 슬라이더 값은 눈금 자릿수 글자로 바꿨다 다시 읽어 넣는다(0.30000000000000004 같은 값이 `SimConfig.validate` 의 JSON 왕복 검사에 걸리지 않게). 숫자 칸에는 슬라이더 범위 밖 값도 적을 수 있다(설정 검사 범위 안이면 됨, 슬라이더는 끝에 붙음). 화면을 상태에 맞추는 동안(슬라이더 끝을 줄이면 Range 가 값을 잘라 신호를 냄) 들어오는 신호는 무시한다 — 상한을 낮춰도 초기 개체 수가 몰래 바뀌지 않고 오류로 알린다(검사).
- **고급 설정:** `sim-defaults.json` 의 잎 키 전부를 절별로(절 이름 "지도 · map" 등). 수 → 오른쪽 맞춤 글 칸, 참거짓 → 확인 상자, 배열·글자(`seasons.growth`·`brain.policy`) → 읽기 전용 칸(보이기만). JSON 을 읽으면 수가 모두 실수가 되므로 **정수 키는 파일 글자로 가린다**(소수점 없는 수). 값 글자는 Godot 기본 표기(정수 키는 정수). 줄 이름 말풍선 = 키·예설정 값·지금 실험 값. 비교 모드에서는 머리의 A/B 단추로 고급 설정이 보여 줄 칸을 고른다. 펼쳤을 때만 줄을 갱신한다.
- **입력:** 단추는 초점을 받지 않는다(스페이스 = 멈춤과 겹치지 않게). 글 칸(숫자 칸·씨앗 칸)에 초점이 있으면 LabMain 이 단축키를 무시한다(SpinBox 안의 LineEdit 도 — 검사: 씨앗 칸에 "42 f", 숫자 칸에 "0.07" 을 쳐도 멈춤·배속·따라가기 그대로). Enter = 확정 + 초점 풀기(지도로 돌아가면 단축키가 바로 동작), Esc = 적던 글자 버리고 초점 풀기(선택 해제 아님), 초점이 빠지면 확정. 단추 동작(새 실험·나란히 시작·비교·스냅숏) 전에 입력 중인 칸을 먼저 확정한다.
- **씨앗:** SpinBox 0~`ui.param.seed_max`(정수, 밖이면 자름). "무작위" = 화면 쪽 시각으로 씨앗을 준 **따로 만든** `RandomNumberGenerator` 에서 고름 — 시뮬레이션 난수(SimRng)·Godot 전역 난수와 무관(검사: 전역 `randi()` 순서·세계 해시 그대로).
- **비교 모드:** 켜면(비교 중이 아니면) B 칸 = A 조건 사본, 새 실험 단추 자리에 "나란히 시작"(AccentButton). 끄면 B 칸을 숨기고 `lab.stop_compare()` 를 **늘** 부른다(비교 중이 아니면 LabMain 이 아무것도 하지 않아야 함). 뼈대 `start_compare` 의 오류 문장은 패널 안 빨간 글 + 알림.
- **파일:** CSV 내보내기 = `lab.export_csv(lab.default_export_dir())`(성공·실패 알림은 LabMain). 스냅숏 저장/열기 = 패널 자식 FileDialog 두 개(처음 누를 때 만듦, `FILE_MODE_SAVE_FILE`/`OPEN_FILE`, `ACCESS_FILESYSTEM`, `*.json`, 시작 폴더 `user://experiments` 의 실제 경로 — 없으면 만듦, 크기 `ui.param.dialog_width × dialog_height`, 저장 기본 이름 `snapshot-<날짜-시각>-seed<N>-tick<T>.json`, `use_native_dialog` — 운영 체제 대화 상자를 쓸 수 있으면 그것, 못 쓰면(헤드리스·포털 없는 Linux) 엔진 대화 상자). 비교 중 저장은 `<이름>-A.json`·`<이름>-B.json` 두 파일. 열기 실패는 패널 안 빨간 글 + 알림(지금 실험 그대로).
- **소리:** "소리" 확인 상자 = 실험실 자식 가운데 `LabSound`(종류로 찾음)의 `enabled`. 실험실 자식이 바뀔 때마다 다시 찾고, 없으면 못 씀(말풍선 "소리 장치(LabSound)가 없습니다").
- **배치:** 패널(VBox) ⊃ `Scroll`(세로만) ⊃ 제목 "실험 조건" · 지금 실험(CardPanel) · "다음 실험 …" · A 칸·B 칸(CardPanel, 비교 모드에서 머리에 색 점 + A/B + 왼쪽/오른쪽 지도) · 상태 줄 · 오류 글 · 새 실험/나란히 시작 · [되돌리기][비교 모드] · ─ · CSV 내보내기 · [스냅숏 저장][스냅숏 열기] · 소리 · ─ · ▶ 고급 설정. 가로: 글 칸은 기본 "글자 4개" 최소 폭을 끄고 `ui.param.value_field_width`·`advanced_field_width`·`seed_field_min_width` 만, 예설정 단추는 긴 이름을 말줄임(전체 이름은 말풍선), 긴 문장은 줄바꿈 — 최소 폭 + 스크롤 막대 ≤ `lab.left_panel_width` − 양쪽 여백(검사, 보통·비교 + 고급 설정 둘 다, 왼쪽 자리가 넓어지지 않음·가로로 넘치는 칸 없음). 간격 `ui.param.group_gap`·`row_gap`·`label_width`·`changed_stripe_width`·`chip_size`.
- 시뮬레이션 쪽 쓰는 것: `SimConfig.defaults()`·`presets()`·`preset_names()`·`build()`·`get_value()`·`deep_equal()`·`DEFAULTS_PATH`(정수 키 가리기), `Experiment` 의 만든 조건(`preset`·`overrides`·`seed_value`·`label`·`tag`·`snapshot_path`)과 `world.cfg`(깊은 사본으로 견주기만)·`world.tick`(저장 파일 이름). 세계를 진행하거나 고치지 않는다.
- 검사 `tests/view/param_checks.gd`(119개): 기본값 = 기본 예설정, 예설정 → 세 칸, 슬라이더 눈금·상한, set_value + apply → 새 실험의 cfg·씨앗·개체 수, 범위 밖 값 → 칸 아래 오류·단추 꺼짐·지금 실험 그대로·알림, 글자 오류·정수 키·배열 키, 참거짓 칸, 초기 개체 수 > 상한, 되돌리기, 씨앗 범위·무작위(전역 난수·세계 그대로), 글 칸 입력 중 단축키 무시·Enter/Esc, 내보내기(`export_to(임시 폴더)` + 알림, 단추 → `lab.default_export_dir()` 는 가짜 실험실이 임시 폴더로 돌려 확인 — 공용 `user://experiments` 에 쓰지 않음, 검사 뒤 지움), 스냅숏 대화 상자 설정·저장·열기·없는 파일, 소리 상자, 1280×720 폭, 비교 모드(진짜 실험실: 뼈대면 오류 글 / 통합 뒤면 실험 둘, 가짜 실험실 `FakeLab`: `start_compare` 인자 = 두 칸 조건, 끄면 `stop_compare`).
- 캡처: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 --script res://tests/param_capture.gd -- --out=폴더 [--extra]` → `param-panel.png`(실제 폭·실제 높이(창 − 위쪽 막대 − 아래 자리)의 세 장면: 값을 바꾼 혼자 모드 · 비교 모드 · 고급 설정(바꾼 값·칸 아래 오류)), `--extra` 면 장면별·1280×720 높이 그림도.
- 알려진 한계(엔진 대화 상자로 열릴 때): 안의 엔진 글(경로·폴더 만들기·Save 등)은 엔진 번역이 내보내기에 없어 영어로 보이고(제목·취소 단추만 한국어), 프로젝트 이름이 한글이라 `user://` 실제 경로에 한글이 들어가면 Godot 4.4 의 FileDialog 가 목록은 보여 주면서도 "You don't have permission to access contents of this folder." 를 잘못 띄운다(엔진 `DirAccessUnix::is_readable` 이 경로를 UTF-8 로 넘기지 않음 — 영문 경로에서는 안 뜸, 캡처로 확인). 프로젝트 설정 `application/config/use_custom_user_dir` + 영문 `custom_user_dir_name` 으로 피할 수 있다(통합 담당에게 요청).

## GraphPanel — `scripts/ui/graph_panel.gd` (`class_name GraphPanel`, HBoxContainer, 아래 자리) + `GraphView`(`scripts/ui/graph_view.gd`)

- `func bind_lab(lab)` — `experiments_changed` → 지우고 `rows()` 를 처음부터, `recorded(index, row)` → 덧붙임, `cursor_tick_requested(tick)` → 세로 표시선.
- 그래프 3개(가로로 나란히, 각 제목·축·범례):
  1. **개체 수**: `population` 선(+ `births`·`deaths` 얇은 선, 켜고 끔).
  2. **평균 특성**: 고르기(OptionButton) — `mean_size`·`mean_sense`·`mean_energy`·`mean_age`·`mean_gen`.
  3. **기술 단계**: `civ_stage` 계단선(세로축에 `SimWorld.STAGE_NAMES`) + `storehouses`·`farms` 수(보조 축), 발견 시점 세로선과 이름.
- 가로축: 틱 ↔ 평균 세대(한 단추로 셋 모두). 비교 모드: A 실선(`ui.graph.series_a`), B 점선(`series_b`), 범례에 `display_name()`.
- 마우스를 올리면 세로선 + 가장 가까운 기록 줄의 값(A·B 함께).
- 성능: 줄이 수천 개여도 다시 그리기는 `ui.graph.redraw_hz` 이하, 그릴 때 화면 폭(픽셀 열)에 맞춰 줄임(열마다 최소·최대).
- `func graph_count() -> int`(3) · `func series_points(graph: int, index: int) -> int`(검사용: 그 그래프·실험의 점 수) · `func set_x_axis(mode: String)`("tick"/"gen").

## ChroniclePanel — `scripts/ui/chronicle_panel.gd` (`class_name ChroniclePanel`, VBoxContainer, 아래 자리 오른쪽)

- `func bind_lab(lab)` — `experiments_changed` → 각 실험의 `world.chronicle` 로 다시 채움, `events_tagged(index, list)` → 덧붙임(최신이 위). 비교 모드면 줄 앞에 A/B.
- 줄: "틱 N · 평균 G세대 · 문장"(종류 색 띠). 거르기(OptionButton): 전체·발견·건물(저장고·첫 밭)·밭 잃음·세대·멸종. 최대 `ui.chronicle.max_items` 줄(넘치면 "더 오래된 K개" 표시).
- 줄을 누르면 `lab.request_cursor(tick)`, 행위자(`actor ≥ 0`)가 있으면 `lab.select_slime(actor, index)`.
- `func item_count() -> int` · `func item_text(i) -> String`(검사용).

## LabSound — `scripts/ui/lab_sound.gd` (`class_name LabSound`, Node)

- 실행 중 파형 합성(사인·삼각, 감쇠 포락선, 16비트 `AudioStreamWAV`) — 외부 음원 없음, CC0 로 CREDITS 에.
- 소리: 발견(두세 음 차임), 멸종(낮은 음), 저장고 건설(짧은 톡). `func play_event(kind) -> bool`, `var enabled`(`ui.sound.enabled`), 음량 `ui.sound.volume_db`, 같은 소리 최소 간격 `ui.sound.min_interval_s`(빨리 감기에서 몰려도 시끄럽지 않게).
- `func bind_lab(lab)` — `events_tagged` 를 받아 재생. `static func synth(kind: String) -> AudioStreamWAV`(검사: 길이·최댓값·NaN 없음·같은 입력이면 같은 바이트).
