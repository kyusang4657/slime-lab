class_name SimWorld
extends RefCounted
## 슬라임 세계 한 개. Node·렌더링·입력·파일 대화상자 없이 규칙만 담는다(화면은 읽기만 한다).
## 설계: docs/DESIGN-v0.1.md. 화면이 쓰는 질의 목록: docs/SIM-API.md.
##
## 한 틱 순서: ① 빛·계절, 버려진 밭 → 풀밭(매 틱) ② (plants.update_every 마다) 식물 성장·누적 합 표 ③ 슬라임마다(id 오름차순)
## 감지 → 판단 → 행동 → 대사 ④ 번식 ⑤ 사망 정리 ⑥ 바닥 먹이 썩음·싹 ⑦ 채집·농사 발견 판정 ⑧ 기록·해시.
## 저장고 짓기와 저장 발견은 ⑦ 이 아니라 ③ 의 내려놓기 순간(_drop → _check_store_region)에 일어난다 — 같은 틱 뒤 차례 개체는
## 그 저장고에 바로 넣고 저장고 입력(9·10)으로 본다(검사 test_store_built_in_act).
## 슬라임은 필드별 배열(SoA)이고 배열 순서 = id 오름차순이다(출생은 뒤에 붙이고, 사망은 순서를 지켜 뺀다).

const STAGE_NONE := 0
const STAGE_FORAGE := 1
const STAGE_STORE := 2
const STAGE_FARM := 3
const STAGE_NAMES: Array[String] = ["없음", "채집", "저장", "농사"]

const CAUSE_ALIVE := 0
const CAUSE_STARVED := 1
const CAUSE_OLD := 2
const CAUSE_NAMES: Array[String] = ["살아 있음", "굶주림", "노화"]
const NO_PARENT := -1
const NO_STORE := -1
const SEASON_COUNT := 4
## 저장고 방향 입력: 뒤로 돌아야 할 때 오른쪽(+1)으로 돈다.
const TURN_BACK_SIGN := 1.0
## 생명 난수 흐름을 세계 흐름과 다르게 섞는 값.
const LIFE_SEED_SALT := 0x5bd1e995
## 연대기에 적는 평균 세대의 반올림 단위(JSON 왕복에서 글자가 바뀌지 않게).
const EVENT_GEN_STEP := 0.01

var cfg: Dictionary = {}
var L: Dictionary = {}
var seed_value := 0
var w := 0
var h := 0
var tick := 0
var rng_world: SimRng
var rng_life: SimRng

# ── 지도 ──
var tiles := PackedByteArray()
var fert := PackedFloat64Array()
var base_fert := PackedFloat64Array()
var food := PackedFloat64Array()
var grow_rate := PackedFloat64Array()
var food_cap := PackedFloat64Array()
var dropped := PackedFloat64Array()
var drop_timer := PackedInt32Array()
var drop_listed := PackedByteArray()
var drop_list := PackedInt32Array()
var sat := PackedFloat64Array()
var csat := PackedInt32Array()
var count_grid := PackedInt32Array()
var farm_visit := PackedInt32Array()
var farms := PackedInt32Array()

# ── 문명 ──
var stage := STAGE_NONE
var discovery_tick: Array[int] = [-1, -1, -1, -1]
## 세계에서 처음 밭을 심은 틱(-1 = 아직). 밭을 모두 잃고 다시 심어도 '첫 밭' 사건은 한 번만.
var first_farm_tick := -1
var forage_attempts := 0
var farm_sprouts := 0
var store_drops_total := 0.0
var drop_total_tile := PackedFloat64Array()
var region_drop := PackedFloat64Array()
var regions_x := 0
var regions_y := 0
var store_tiles := PackedInt32Array()
var store_food := PackedFloat64Array()
var store_at := PackedInt32Array()
var store_dist := PackedInt32Array()

# ── 슬라임(SoA, 저장되는 것) ──
var s_id := PackedInt32Array()
var s_x := PackedInt32Array()
var s_y := PackedInt32Array()
var s_head := PackedInt32Array()
var s_age := PackedInt32Array()
var s_gen := PackedInt32Array()
var s_max_age := PackedInt32Array()
var s_last_repro := PackedInt32Array()
var s_last_action := PackedInt32Array()
var s_energy := PackedFloat64Array()
var s_carry := PackedFloat64Array()
var s_mem := PackedFloat64Array()
var s_genome := PackedFloat32Array()
# ── 슬라임(유전체에서 계산, 저장 안 함) ──
var s_size := PackedFloat64Array()
var s_sense := PackedInt32Array()
var s_emax := PackedFloat64Array()
var s_dead := PackedByteArray()

# ── 계통(id 로 바로 찾음, 태어난 모든 개체) ──
var lin_pa := PackedInt32Array()
var lin_pb := PackedInt32Array()
var lin_gen := PackedInt32Array()
var lin_birth := PackedInt32Array()
var lin_death := PackedInt32Array()
var lin_cause := PackedByteArray()
var lin_children := PackedInt32Array()
var lin_size := PackedFloat32Array()
var lin_sense := PackedFloat32Array()
var lin_hue := PackedFloat32Array()

# ── 장부·통계 ──
var led_initial := 0.0
var led_eaten := 0.0
var led_spent := 0.0
var led_repro_loss := 0.0
var led_died := 0.0
var total_births := 0
var total_deaths := 0
var period_births := 0
var period_deaths := 0
var peak_population := 0
var next_milestone := 0
var extinct_tick := -1
var history_hash := ""
var chronicle: Array = []
var _pending_events: Array = []

# ── 매 틱 계산(저장 안 함) ──
var light := 1.0
var season := -1
var season_growth := 1.0
var season_warm := 1.0
var _in := PackedFloat64Array()
var _hid := PackedFloat64Array()
var _wts := PackedFloat64Array()
var _out := PackedFloat64Array()
var _bucket_head := PackedInt32Array()
var _bucket_next := PackedInt32Array()
var _mated := PackedByteArray()

# ── 자주 쓰는 설정 값(설정에서 한 번 읽음) ──
var _G := 0
var _n_in := 0
var _n_hid := 0
var _n_out := 0
var _n_mem := 0
var _w2o := 0
var _to := 0
var _max_food := 0.0
var _carry_max := 0.0
var _bite := 0.0
var _eff := 0.0
var _metab_base := 0.0
var _metab_sense := 0.0
var _metab_move := 0.0
var _rest := 0.0
var _crowd_r := 0
var _crowd_norm := 0.0
var _night_sense := 0.0
var _night_light := 0.0
var _think_every := 1
var _forage_frac := 0.0
var _store_cap := 0.0
var _sample_policy := true
var _sharpness := 1


# ════════════════════════════ 만들기 ════════════════════════════

## 새 세계. 설정 오류가 있으면 그 문장을 돌려준다(성공 "").
func setup(config: Dictionary, seed_in: int) -> String:
	var err := SimConfig.validate(config)
	if err != "":
		return err
	_load_config(config)
	seed_value = seed_in
	rng_world = SimRng.new(seed_in)
	rng_life = SimRng.new(seed_in ^ LIFE_SEED_SALT)
	var terr := SimTerrain.generate(cfg, seed_in)
	tiles = terr.tiles
	fert = terr.fertility
	base_fert = fert.duplicate()
	_alloc_map()
	var fill := float(cfg.plants.initial_fill)
	for c in w * h:
		_update_tile_rates(c)
		food[c] = food_cap[c] * fill
	_rebuild_stores()
	# 초기 개체: 통과 가능 칸 중 무작위(칸 목록 순서 고정)
	var open := PackedInt32Array()
	for c in w * h:
		if SimGrid.passable(tiles[c]):
			open.append(c)
	var spread := int(cfg.population.initial_age_spread)
	if not open.is_empty():
		for k in int(cfg.population.initial):
			var c: int = open[rng_life.below(open.size())]
			var g := SimBrain.random_genome(cfg, L, rng_life)
			var e0 := float(cfg.body.start_energy_frac) * float(cfg.body.energy_per_size) * float(g[_to + SimBrain.TRAIT_SIZE])
			_spawn(c % w, c / w, rng_life.below(SimGrid.DIR_COUNT), g, e0, 0, NO_PARENT, NO_PARENT, rng_life.below(spread + 1))
	led_initial = total_energy()
	peak_population = s_id.size()
	next_milestone = int(cfg.record.generation_milestone)
	_build_sat()
	_compute_time()
	_hash_step()
	# 처음부터 개체가 없는 세계(초기 개체 0, 지나갈 칸 없음)는 틱 0 에 멸종 — 실행기(틱 0 에서 끝남)와 실험실이 같은 기록을 남기게
	if s_id.is_empty():
		extinct_tick = tick
		_event("extinction", -1, "멸종 — 시작할 때 개체가 없음")
	return ""


func _load_config(config: Dictionary) -> void:
	cfg = config
	L = SimBrain.layout(cfg)
	w = int(cfg.map.width)
	h = int(cfg.map.height)
	_G = L.genes
	_n_in = L.n_in
	_n_hid = L.n_hid
	_n_out = L.n_out
	_n_mem = L.n_mem
	_w2o = L.w2_offset
	_to = L.trait_offset
	_max_food = float(cfg.plants.max_food)
	_carry_max = float(cfg.carry.max)
	_bite = float(cfg.eat.bite)
	_eff = float(cfg.eat.efficiency)
	_metab_base = float(cfg.metab.base)
	_metab_sense = float(cfg.metab.sense_cost)
	_metab_move = float(cfg.metab.move)
	_rest = float(cfg.metab.rest_factor)
	_crowd_r = int(cfg.sense.crowd_radius)
	_crowd_norm = float(cfg.sense.crowd_norm)
	_night_sense = float(cfg.sense.night_factor)
	_night_light = float(cfg.time.night_light_threshold)
	_think_every = int(cfg.brain.think_every)
	_forage_frac = float(cfg.discovery.forage_min_energy_frac)
	_store_cap = float(cfg.store.capacity)
	_sample_policy = str(cfg.brain.policy) == SimBrain.POLICY_SAMPLE
	_sharpness = int(cfg.brain.sharpness)
	_wts.resize(SimBrain.BASE_OUTPUTS)
	_in.resize(_n_in)
	_hid.resize(_n_hid)
	_out.resize(_n_out)
	var rs := int(cfg.discovery.region_size)
	regions_x = (w + rs - 1) / rs
	regions_y = (h + rs - 1) / rs


func _alloc_map() -> void:
	var n := w * h
	food.resize(n)
	food.fill(0.0)
	grow_rate.resize(n)
	grow_rate.fill(0.0)
	food_cap.resize(n)
	food_cap.fill(0.0)
	dropped.resize(n)
	dropped.fill(0.0)
	drop_total_tile.resize(n)
	drop_total_tile.fill(0.0)
	drop_timer.resize(n)
	drop_timer.fill(0)
	drop_listed.resize(n)
	drop_listed.fill(0)
	count_grid.resize(n)
	count_grid.fill(0)
	farm_visit.resize(n)
	farm_visit.fill(0)
	store_at.resize(n)
	store_at.fill(NO_STORE)
	sat.resize((w + 1) * (h + 1))
	sat.fill(0.0)
	csat.resize((w + 1) * (h + 1))
	csat.fill(0)
	region_drop.resize(regions_x * regions_y)
	region_drop.fill(0.0)
	_bucket_head.resize(n)


## 칸의 성장 속도·상한을 지형·비옥도·밭 여부에서 다시 계산한다.
func _update_tile_rates(c: int) -> void:
	var scale := float(cfg.resources.scale)
	if not SimGrid.passable(tiles[c]):
		grow_rate[c] = 0.0
		food_cap[c] = 0.0
		return
	var r := float(cfg.plants.regrow) * fert[c] * scale
	var cap := _max_food * fert[c] * scale
	if tiles[c] == SimGrid.TILE_FARM:
		r *= float(cfg.farm.growth_mult)
		cap *= float(cfg.farm.max_mult)
	grow_rate[c] = r
	food_cap[c] = cap
	if food[c] > cap:
		food[c] = cap


func _spawn(x: int, y: int, head: int, g: PackedFloat32Array, energy: float, gen: int, pa: int, pb: int, age: int) -> int:
	var id := lin_pa.size()
	s_id.append(id)
	s_x.append(x)
	s_y.append(y)
	s_head.append(head)
	s_age.append(age)
	s_gen.append(gen)
	var j := int(cfg.life.max_age_jitter)
	s_max_age.append(int(cfg.life.max_age) + rng_life.below(2 * j + 1) - j)
	s_last_repro.append(-int(cfg.repro.cooldown))
	s_last_action.append(SimBrain.ACT_REST)
	s_energy.append(energy)
	s_carry.append(0.0)
	for k in _n_mem:
		s_mem.append(0.0)
	s_genome.append_array(g)
	_append_derived(g)
	s_dead.append(0)
	count_grid[y * w + x] += 1
	lin_pa.append(pa)
	lin_pb.append(pb)
	lin_gen.append(gen)
	lin_birth.append(tick)
	lin_death.append(-1)
	lin_cause.append(CAUSE_ALIVE)
	lin_children.append(0)
	lin_size.append(g[_to + SimBrain.TRAIT_SIZE])
	lin_sense.append(g[_to + SimBrain.TRAIT_SENSE])
	lin_hue.append(g[_to + SimBrain.TRAIT_HUE])
	return id


func _append_derived(g: PackedFloat32Array) -> void:
	var size := float(g[_to + SimBrain.TRAIT_SIZE])
	s_size.append(size)
	s_sense.append(int(floorf(float(g[_to + SimBrain.TRAIT_SENSE]) + 0.5)))
	s_emax.append(float(cfg.body.energy_per_size) * size)


# ════════════════════════════ 진행 ════════════════════════════

func step() -> void:
	_compute_time()
	_abandon_farms()
	if tick % int(cfg.plants.update_every) == 0:
		_grow_plants()
		_build_sat()
	_act_all()
	_reproduce()
	_remove_dead()
	_spoil_dropped()
	_check_civ()
	tick += 1
	# 빛·계절을 새 틱으로 다시 계산: 틱 사이(화면·기록·스냅숏)에서 light·season 이 언제나 지금 tick 을 뜻하게
	_compute_time()
	_after_tick()


func step_n(n: int) -> void:
	for i in n:
		step()


func _compute_time() -> void:
	light = _light_at(tick)
	var gr: Array = cfg.seasons.growth
	season = _season_at(tick)
	if season < 0:
		season_growth = 1.0
		season_warm = 1.0
		return
	season_growth = float(gr[season])
	var top := 0.0
	for v in gr:
		top = maxf(top, float(v))
	season_warm = season_growth / top if top > 0.0 else 0.0


## 틱 t 의 빛(0~1). 낮 구간 [0, 하루 × 낮 비율) 안쪽 양 끝 twilight_ticks 동안 0 ↔ 1 로 고르게 바뀌고, 나머지(밤)는 0.
## 그래서 하루 빛 합 = 낮 틱 − twilight_ticks(검사).
func _light_at(t: int) -> float:
	var tc: Dictionary = cfg.time
	var day := int(tc.day_ticks)
	var phase := float(t % day)
	var lit := float(day) * float(tc.daylight_fraction)
	var tw := float(tc.twilight_ticks)
	if tw <= 0.0:
		return 1.0 if phase < lit else 0.0
	if phase < tw:
		return phase / tw
	if phase < lit - tw:
		return 1.0
	if phase < lit:
		return (lit - phase) / tw
	return 0.0


## 틱 t 의 계절 0~3(-1 = 계절 없음).
func _season_at(t: int) -> int:
	var sd := int(cfg.time.season_days)
	if sd <= 0:
		return -1
	return (t / int(cfg.time.day_ticks) / sd) % SEASON_COUNT


## 식물 성장(plants.update_every 틱마다): 이번 갱신부터 다음 갱신 전까지 틱마다의 (빛 몫 × 계절 배수)를 더해 곱한다 —
## 자라는 양이 갱신 간격과 상관없이 같다(간격은 성능용, 칸 상한에 닿을 때만 몰아 자른 만큼 다름). 간격 1 이면 그 틱 값 그대로.
func _grow_plants() -> void:
	var ng := float(cfg.plants.night_growth)
	var gr: Array = cfg.seasons.growth
	var floor_f := float(cfg.farm.winter_floor)
	var mult := 0.0
	var farm_mult := 0.0
	for k in int(cfg.plants.update_every):
		var light_f := ng + (1.0 - ng) * _light_at(tick + k)
		var si := _season_at(tick + k)
		var sg := 1.0 if si < 0 else float(gr[si])
		mult += light_f * sg
		farm_mult += light_f * maxf(sg, floor_f)
	for c in w * h:
		var r := grow_rate[c]
		if r <= 0.0:
			continue
		if tiles[c] == SimGrid.TILE_FARM:
			food[c] = minf(food_cap[c], food[c] + r * farm_mult)
		else:
			food[c] = minf(food_cap[c], food[c] + r * mult)


## 밭 버려짐(매 틱, 식물 갱신 간격·성장 속도와 상관없이): farm.abandon_ticks 동안 아무도 밟지 않은 밭은 풀밭으로.
func _abandon_farms() -> void:
	var abandon := int(cfg.farm.abandon_ticks)
	var lost := 0
	for c in farms:
		if tick - farm_visit[c] > abandon:
			lost += 1
	if lost == 0:
		return
	var keep := PackedInt32Array()
	for c in farms:
		if tick - farm_visit[c] > abandon:
			tiles[c] = SimGrid.TILE_GRASS
			fert[c] = base_fert[c]
			_update_tile_rates(c)
		else:
			keep.append(c)
	_event("farm_lost", -1, "버려진 밭 %d곳이 풀밭으로 돌아감 (남은 밭 %d)" % [lost, keep.size()])
	farms = keep


## 감지용 누적 합 표: 칸의 식물 먹이 + 바닥 먹이.
func _build_sat() -> void:
	var sw := w + 1
	for y in h:
		var row := 0.0
		var base := (y + 1) * sw
		var prev := y * sw
		for x in w:
			var c := y * w + x
			row += food[c] + dropped[c]
			sat[base + x + 1] = sat[prev + x + 1] + row


## 붐빔 감지용 칸별 개체 수 누적 합 표(틱 시작 때의 위치).
func _build_count_sat() -> void:
	var sw := w + 1
	var cg := count_grid
	for y in h:
		var row := 0
		var base := (y + 1) * sw
		var prev := y * sw
		for x in w:
			row += cg[y * w + x]
			csat[base + x + 1] = csat[prev + x + 1] + row


func _rect_count(x0: int, y0: int, x1: int, y1: int) -> int:
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, w - 1)
	y1 = mini(y1, h - 1)
	var sw := w + 1
	return csat[(y1 + 1) * sw + x1 + 1] - csat[y0 * sw + x1 + 1] - csat[(y1 + 1) * sw + x0] + csat[y0 * sw + x0]


## 사각형 [x0..x1]×[y0..y1](포함, 지도 밖은 잘라 냄)의 먹이 합.
func rect_food(x0: int, y0: int, x1: int, y1: int) -> float:
	x0 = maxi(x0, 0)
	y0 = maxi(y0, 0)
	x1 = mini(x1, w - 1)
	y1 = mini(y1, h - 1)
	if x0 > x1 or y0 > y1:
		return 0.0
	var sw := w + 1
	var s := sat[(y1 + 1) * sw + x1 + 1] - sat[y0 * sw + x1 + 1] - sat[(y1 + 1) * sw + x0] + sat[y0 * sw + x0]
	return maxf(s, 0.0)


## 방향 hd 기준 (앞 f0..f1, 옆 l0..l1, 오른쪽 +) 영역의 먹이를 칸 수 × max_food 로 나눈 값.
func _quad(x: int, y: int, hd: int, f0: int, f1: int, l0: int, l1: int) -> float:
	var fx: int = SimGrid.DX[hd]
	var fy: int = SimGrid.DY[hd]
	var rh := SimGrid.right_of(hd)
	var rx: int = SimGrid.DX[rh]
	var ry: int = SimGrid.DY[rh]
	var ax := x + f0 * fx + l0 * rx
	var ay := y + f0 * fy + l0 * ry
	var bx := x + f1 * fx + l1 * rx
	var by := y + f1 * fy + l1 * ry
	var area := float((f1 - f0 + 1) * (l1 - l0 + 1))
	return rect_food(mini(ax, bx), mini(ay, by), maxi(ax, bx), maxi(ay, by)) / (area * _max_food)


func _act_all() -> void:
	_build_count_sat()
	var n := s_id.size()
	for i in n:
		s_dead[i] = 0
	for i in n:
		_act(i)


func _act(i: int) -> void:
	var x := s_x[i]
	var y := s_y[i]
	var c := y * w + x
	var hd := s_head[i]
	var size := s_size[i]
	var emax := s_emax[i]
	var action := s_last_action[i]
	if (tick + s_id[i]) % _think_every == 0:
		action = _think(i, x, y, c, hd, emax)
		s_last_action[i] = action
	var cost := _metab_base * size + _metab_sense * float(s_sense[i])
	match action:
		SimBrain.ACT_FORWARD:
			var nx: int = x + SimGrid.DX[hd]
			var ny: int = y + SimGrid.DY[hd]
			if nx >= 0 and ny >= 0 and nx < w and ny < h:
				var nc := ny * w + nx
				if SimGrid.passable(tiles[nc]):
					count_grid[c] -= 1
					count_grid[nc] += 1
					s_x[i] = nx
					s_y[i] = ny
					cost += _metab_move * size
					if tiles[nc] == SimGrid.TILE_FARM:
						farm_visit[nc] = tick
		SimBrain.ACT_LEFT:
			s_head[i] = SimGrid.left_of(hd)
		SimBrain.ACT_RIGHT:
			s_head[i] = SimGrid.right_of(hd)
		SimBrain.ACT_EAT:
			_eat(i, c, size, emax)
		SimBrain.ACT_REST:
			cost *= _rest
		SimBrain.ACT_GATHER:
			if stage >= STAGE_FORAGE:
				_gather(i, c, size)
			elif food[c] + dropped[c] > 0.0 and s_energy[i] >= _forage_frac * emax:
				forage_attempts += 1
		SimBrain.ACT_DROP:
			if s_carry[i] > 0.0:
				_drop(i, c)
		SimBrain.ACT_PLANT:
			if stage >= STAGE_FARM:
				_plant(i, x, y, hd)
	s_energy[i] -= cost
	led_spent += cost
	s_age[i] += 1
	if s_energy[i] <= 0.0:
		s_dead[i] = CAUSE_STARVED
	elif s_age[i] >= s_max_age[i]:
		s_dead[i] = CAUSE_OLD


## 감지 → 순전파 → 행동 번호. SimBrain.forward 와 같은 식(검사로 일치 확인).
func _think(i: int, x: int, y: int, c: int, hd: int, emax: float) -> int:
	var r := s_sense[i]
	if light < _night_light:
		r = maxi(1, int(float(r) * _night_sense))
	_in[SimBrain.IN_BIAS] = 1.0
	_in[SimBrain.IN_ENERGY] = s_energy[i] / emax
	var st := store_at[c]
	if st != NO_STORE:
		_in[SimBrain.IN_FOOD_HERE] = store_food[st] / _store_cap
	else:
		_in[SimBrain.IN_FOOD_HERE] = (food[c] + dropped[c]) / _max_food
	# 앞·왼·오른 영역(축 정렬 사각형). _quad 와 같은 계산을 방향별로 펼쳐 씀(검사로 일치 확인).
	var norm_a := float(r * (2 * r + 1)) * _max_food
	match hd:
		0:
			_in[SimBrain.IN_FOOD_AHEAD] = rect_food(x - r, y - r, x + r, y - 1) / norm_a
			_in[SimBrain.IN_FOOD_LEFT] = rect_food(x - r, y - r, x - 1, y + r) / norm_a
			_in[SimBrain.IN_FOOD_RIGHT] = rect_food(x + 1, y - r, x + r, y + r) / norm_a
		1:
			_in[SimBrain.IN_FOOD_AHEAD] = rect_food(x + 1, y - r, x + r, y + r) / norm_a
			_in[SimBrain.IN_FOOD_LEFT] = rect_food(x - r, y - r, x + r, y - 1) / norm_a
			_in[SimBrain.IN_FOOD_RIGHT] = rect_food(x - r, y + 1, x + r, y + r) / norm_a
		2:
			_in[SimBrain.IN_FOOD_AHEAD] = rect_food(x - r, y + 1, x + r, y + r) / norm_a
			_in[SimBrain.IN_FOOD_LEFT] = rect_food(x + 1, y - r, x + r, y + r) / norm_a
			_in[SimBrain.IN_FOOD_RIGHT] = rect_food(x - r, y - r, x - 1, y + r) / norm_a
		_:
			_in[SimBrain.IN_FOOD_AHEAD] = rect_food(x - r, y - r, x - 1, y + r) / norm_a
			_in[SimBrain.IN_FOOD_LEFT] = rect_food(x - r, y + 1, x + r, y + r) / norm_a
			_in[SimBrain.IN_FOOD_RIGHT] = rect_food(x - r, y - r, x + r, y - 1) / norm_a
	var cr := _crowd_r
	_in[SimBrain.IN_CROWD] = float(_rect_count(x - cr, y - cr, x + cr, y + cr) - 1) / _crowd_norm
	_in[SimBrain.IN_LIGHT] = light
	_in[SimBrain.IN_CARRY] = s_carry[i] / (_carry_max * s_size[i])
	_store_inputs(x, y, c, hd)
	_in[SimBrain.IN_SEASON] = season_warm
	var mb := i * _n_mem
	for k in _n_mem:
		_in[SimBrain.BASE_INPUTS + k] = s_mem[mb + k]
	# 순전파(멤버 배열을 지역 이름으로 받아 읽기만 한다 — 멤버 조회보다 빠름)
	var gnm := s_genome
	var inp := _in
	var hid := _hid
	var out := _out
	var n_in := _n_in
	var n_hid := _n_hid
	var base := i * _G
	for j in n_hid:
		var s := 0.0
		var o := base + j * n_in
		for k in n_in:
			s += gnm[o + k] * inp[k]
		hid[j] = s / (1.0 + absf(s))
	var o2 := base + _w2o
	for q in _n_out:
		var s2 := 0.0
		var oq := o2 + q * n_hid
		for j in n_hid:
			s2 += gnm[oq + j] * hid[j]
		out[q] = s2
	var best := _pick_action()
	for k in _n_mem:
		var m := _out[SimBrain.BASE_OUTPUTS + k]
		s_mem[mb + k] = m / (1.0 + absf(m))
	return best


## 행동 고르기. argmax 정책이면 가장 큰 출력(같으면 번호가 작은 쪽),
## sample 정책이면 출력 z = softsign(o) 에 대해 (1 + z)^k 에 비례하는 확률로 뽑는다(k = brain.sharpness,
## SimBrain.policy_weight 와 같은 식을 펼쳐 씀).
func _pick_action() -> int:
	if not _sample_policy:
		return SimBrain.argmax_action(_out)
	var total := 0.0
	var out := _out
	var wts := _wts
	var k := _sharpness
	for q in SimBrain.BASE_OUTPUTS:
		var o := out[q]
		var b := 1.0 + o / (1.0 + absf(o))
		var wq := 1.0
		for e in k:
			wq *= b
		wts[q] = wq
		total += wq
	var r := rng_life.uniform() * total
	for q in SimBrain.BASE_OUTPUTS:
		r -= _wts[q]
		if r < 0.0:
			return q
	return SimBrain.BASE_OUTPUTS - 1


func _store_inputs(x: int, y: int, c: int, hd: int) -> void:
	if store_tiles.is_empty():
		_in[SimBrain.IN_STORE_DIR] = 0.0
		_in[SimBrain.IN_STORE_NEAR] = 0.0
		return
	var d0 := store_dist[c]
	if d0 == SimGrid.FAR:
		_in[SimBrain.IN_STORE_DIR] = 0.0
		_in[SimBrain.IN_STORE_NEAR] = 0.0
		return
	_in[SimBrain.IN_STORE_NEAR] = 1.0 / (1.0 + float(d0))
	if d0 == 0:
		_in[SimBrain.IN_STORE_DIR] = 0.0
		return
	var da := _dist_at(x + SimGrid.DX[hd], y + SimGrid.DY[hd])
	var lh := SimGrid.left_of(hd)
	var rh := SimGrid.right_of(hd)
	var dl := _dist_at(x + SimGrid.DX[lh], y + SimGrid.DY[lh])
	var dr := _dist_at(x + SimGrid.DX[rh], y + SimGrid.DY[rh])
	if da < d0 and da <= dl and da <= dr:
		_in[SimBrain.IN_STORE_DIR] = 0.0
	elif dl < d0 and dl <= dr:
		_in[SimBrain.IN_STORE_DIR] = -1.0
	elif dr < d0:
		_in[SimBrain.IN_STORE_DIR] = 1.0
	else:
		_in[SimBrain.IN_STORE_DIR] = TURN_BACK_SIGN


func _dist_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return SimGrid.FAR
	return store_dist[y * w + x]


## 먹기: 저장고 칸이면 저장분, 아니면 식물 → 바닥 먹이 → 운반분 순서. 배가 차는 만큼만 먹는다.
func _eat(i: int, c: int, size: float, emax: float) -> void:
	var room := (emax - s_energy[i]) / _eff
	if room <= 0.0:
		return
	var want := minf(_bite * size, room)
	var got := 0.0
	var st := store_at[c]
	if st != NO_STORE:
		var t0 := minf(want, store_food[st])
		store_food[st] -= t0
		got += t0
	else:
		var t1 := minf(want, food[c])
		food[c] -= t1
		got += t1
		var t2 := minf(want - got, dropped[c])
		dropped[c] -= t2
		got += t2
	if got < want and s_carry[i] > 0.0:
		var t3 := minf(want - got, s_carry[i])
		s_carry[i] -= t3
		got += t3
	s_energy[i] += got * _eff
	led_eaten += got * _eff


func _gather(i: int, c: int, size: float) -> void:
	var room := _carry_max * size - s_carry[i]
	if room <= 0.0:
		return
	var want := minf(_bite * size, room)
	var t1 := minf(want, dropped[c])
	dropped[c] -= t1
	var t2 := minf(want - t1, food[c])
	food[c] -= t2
	s_carry[i] += t1 + t2


func _drop(i: int, c: int) -> void:
	var amount := s_carry[i]
	var st := store_at[c]
	if st != NO_STORE:
		var put := minf(amount, _store_cap - store_food[st])
		store_food[st] += put
		s_carry[i] -= put
		return
	s_carry[i] = 0.0
	_put_dropped(c, amount)
	if stage < STAGE_FORAGE:
		return
	store_drops_total += amount
	drop_total_tile[c] += amount
	var rs := int(cfg.discovery.region_size)
	var r := (c / w / rs) * regions_x + (c % w) / rs
	region_drop[r] += amount
	_check_store_region(r)


## 죽은 개체의 운반분을 칸에 내려놓는다: 저장고 칸이면 용량까지 저장분으로, 남은 몫(과 저장고가 아닌 칸)은 바닥 먹이.
func _put_down(c: int, amount: float) -> void:
	var st := store_at[c]
	if st != NO_STORE:
		var put := minf(amount, _store_cap - store_food[st])
		store_food[st] += put
		amount -= put
	if amount > 0.0:
		_put_dropped(c, amount)


## 바닥 먹이를 더한다. 칸의 더미 전체가 타이머 하나를 쓰므로 더 놓으면 더미 전체가 다시 spoil_ticks 를 받는다.
## 내려놓은 틱의 ⑥(_spoil_dropped)에서도 타이머가 하나 줄므로 + 1 — 내려놓은 틱부터 꼭 spoil_ticks 틱 뒤(그 틱의 ⑥)에 썩는다.
func _put_dropped(c: int, amount: float) -> void:
	dropped[c] += amount
	drop_timer[c] = int(cfg.dropped.spoil_ticks) + 1
	if drop_listed[c] == 0:
		drop_listed[c] = 1
		drop_list.append(c)


func _plant(i: int, x: int, y: int, hd: int) -> void:
	var seed_cost := float(cfg.farm.seed_cost)
	if s_carry[i] < seed_cost:
		return
	var nx: int = x + SimGrid.DX[hd]
	var ny: int = y + SimGrid.DY[hd]
	if nx < 0 or ny < 0 or nx >= w or ny >= h:
		return
	var nc := ny * w + nx
	if tiles[nc] != SimGrid.TILE_GRASS or store_at[nc] != NO_STORE or store_dist[nc] > int(cfg.farm.radius):
		return
	s_carry[i] -= seed_cost
	tiles[nc] = SimGrid.TILE_FARM
	fert[nc] = 1.0
	farm_visit[nc] = tick
	_update_tile_rates(nc)
	farms.append(nc)
	if first_farm_tick == -1:
		first_farm_tick = tick
		_event("first_farm", s_id[i], "첫 밭 — #%d, (%d, %d) 에 심음" % [s_id[i], nx, ny])


# ── 번식 ──

## 번식 자격. 이번 틱에 이미 짝지은 개체(_mated)는 쿨다운이 0 이어도 다시 뽑히지 않는다(한 틱에 한 번).
func _eligible(i: int, maturity: int, min_frac: float, cooldown: int) -> bool:
	return s_dead[i] == 0 and _mated[i] == 0 and s_age[i] >= maturity and s_energy[i] >= min_frac * s_emax[i] \
			and tick - s_last_repro[i] >= cooldown


func _reproduce() -> void:
	var rp: Dictionary = cfg.repro
	var maturity := int(rp.maturity)
	var min_frac := float(rp.min_energy_frac)
	var cooldown := int(rp.cooldown)
	var cost_frac := float(rp.cost_frac)
	var teff := float(rp.transfer_efficiency)
	var asexual: bool = rp.asexual_when_alone
	var cap := int(cfg.population.cap)
	var n := s_id.size()
	var alive := 0
	for i in n:
		if s_dead[i] == 0:
			alive += 1
	# 칸별 목록(배열 순서 = id 오름차순)
	_bucket_head.fill(-1)
	_bucket_next.resize(n)
	_mated.resize(n)
	_mated.fill(0)
	for k in n:
		var i := n - 1 - k
		var c := s_y[i] * w + s_x[i]
		_bucket_next[i] = _bucket_head[c]
		_bucket_head[c] = i
	var births: Array = []
	for i in n:
		if alive + births.size() >= cap:
			break
		if not _eligible(i, maturity, min_frac, cooldown):
			continue
		var partner := -1
		var mr := int(rp.mate_radius)
		for py in range(maxi(0, s_y[i] - mr), mini(h, s_y[i] + mr + 1)):
			for px in range(maxi(0, s_x[i] - mr), mini(w, s_x[i] + mr + 1)):
				var j := _bucket_head[py * w + px]
				while j != -1:
					if partner != -1 and j >= partner:
						break
					if j != i and _eligible(j, maturity, min_frac, cooldown):
						partner = j
						break
					j = _bucket_next[j]
		if partner == -1 and not asexual:
			continue
		var b := partner if partner != -1 else i
		var ca := cost_frac * s_energy[i]
		var cb := cost_frac * s_energy[b] if b != i else 0.0
		s_energy[i] -= ca
		if b != i:
			s_energy[b] -= cb
		s_last_repro[i] = tick
		s_last_repro[b] = tick
		_mated[i] = 1
		_mated[b] = 1
		var ga := s_genome.slice(i * _G, (i + 1) * _G)
		var gb := s_genome.slice(b * _G, (b + 1) * _G)
		var g := SimBrain.crossover(L, ga, gb, rng_life)
		SimBrain.mutate(cfg, L, g, rng_life)
		# 자식 에너지는 자식의 최대 에너지까지(넘친 몫은 효율 손실과 함께 사라짐 — 장부 led_repro_loss)
		var e_child := minf((ca + cb) * teff, float(cfg.body.energy_per_size) * float(g[_to + SimBrain.TRAIT_SIZE]))
		led_repro_loss += (ca + cb) * (1.0 - teff) + ((ca + cb) * teff - e_child)
		births.append({x = s_x[i], y = s_y[i], head = rng_life.below(SimGrid.DIR_COUNT), g = g, e = e_child,
				gen = maxi(s_gen[i], s_gen[b]) + 1, pa = s_id[i], pb = s_id[b] if b != i else NO_PARENT})
		lin_children[s_id[i]] += 1
		if b != i:
			lin_children[s_id[b]] += 1
	for bdata in births:
		_spawn(bdata.x, bdata.y, bdata.head, bdata.g, bdata.e, bdata.gen, bdata.pa, bdata.pb, 0)
	total_births += births.size()
	period_births += births.size()


func _remove_dead() -> void:
	var n := s_id.size()
	var k := 0
	var any := false
	for i in n:
		if s_dead[i] != 0:
			any = true
			break
	if not any:
		return
	# 유전체는 살아남은 개체의 덩어리만 이어 붙여 새로 만든다(원소 단위 이동보다 훨씬 빠름)
	var genome := PackedFloat32Array()
	for i in n:
		if s_dead[i] == 0:
			genome.append_array(s_genome.slice(i * _G, (i + 1) * _G))
	for i in n:
		if s_dead[i] != 0:
			var id := s_id[i]
			lin_death[id] = tick
			lin_cause[id] = s_dead[i]
			var c := s_y[i] * w + s_x[i]
			count_grid[c] -= 1
			if s_carry[i] > 0.0:
				_put_down(c, s_carry[i])
			led_died += s_energy[i]
			total_deaths += 1
			period_deaths += 1
			continue
		if k != i:
			s_id[k] = s_id[i]
			s_x[k] = s_x[i]
			s_y[k] = s_y[i]
			s_head[k] = s_head[i]
			s_age[k] = s_age[i]
			s_gen[k] = s_gen[i]
			s_max_age[k] = s_max_age[i]
			s_last_repro[k] = s_last_repro[i]
			s_last_action[k] = s_last_action[i]
			s_energy[k] = s_energy[i]
			s_carry[k] = s_carry[i]
			s_size[k] = s_size[i]
			s_sense[k] = s_sense[i]
			s_emax[k] = s_emax[i]
			s_dead[k] = 0
			for m in _n_mem:
				s_mem[k * _n_mem + m] = s_mem[i * _n_mem + m]
		k += 1
	s_id.resize(k)
	s_x.resize(k)
	s_y.resize(k)
	s_head.resize(k)
	s_age.resize(k)
	s_gen.resize(k)
	s_max_age.resize(k)
	s_last_repro.resize(k)
	s_last_action.resize(k)
	s_sense.resize(k)
	s_energy.resize(k)
	s_carry.resize(k)
	s_size.resize(k)
	s_emax.resize(k)
	s_dead.resize(k)
	s_mem.resize(k * _n_mem)
	s_genome = genome


# ── 바닥 먹이 ──

func _spoil_dropped() -> void:
	if drop_list.is_empty():
		return
	var keep := PackedInt32Array()
	var chance := float(cfg.dropped.sprout_chance)
	var sprout_food := float(cfg.dropped.sprout_food)
	var sprout_fert := float(cfg.dropped.sprout_fertility)
	var farm_r := int(cfg.discovery.farm_radius)
	for c in drop_list:
		if dropped[c] <= 0.0:
			dropped[c] = 0.0
			drop_listed[c] = 0
			continue
		drop_timer[c] -= 1
		if drop_timer[c] > 0:
			keep.append(c)
			continue
		dropped[c] = 0.0
		drop_listed[c] = 0
		if tiles[c] != SimGrid.TILE_GRASS or not rng_world.chance(chance):
			continue
		# 싹: 그 칸이 조금 비옥해지고 먹이가 돋는다(농사의 전조)
		base_fert[c] = minf(1.0, base_fert[c] + sprout_fert)
		fert[c] = base_fert[c]
		_update_tile_rates(c)
		food[c] = minf(food_cap[c], food[c] + sprout_food * float(cfg.resources.scale))
		if not store_tiles.is_empty() and store_dist[c] <= farm_r:
			farm_sprouts += 1
	drop_list = keep


# ── 문명 ──

func _check_civ() -> void:
	if stage == STAGE_NONE and forage_attempts >= int(cfg.discovery.forage_threshold):
		_discover(STAGE_FORAGE, "배부른 줍기 시도 %d회" % forage_attempts)
	if stage == STAGE_STORE and farm_sprouts >= int(cfg.discovery.farm_threshold):
		_discover(STAGE_FARM, "저장고 근처 싹 %d번" % farm_sprouts)


func _discover(new_stage: int, why: String) -> void:
	stage = new_stage
	discovery_tick[new_stage] = tick
	_event("discovery", -1, "%s 발견 — %s (평균 %.1f세대)" % [STAGE_NAMES[new_stage], why, mean_generation()], {stage = new_stage})


func _check_store_region(r: int) -> void:
	if region_drop[r] < float(cfg.discovery.store_threshold):
		return
	var best := _region_best_tile(r)
	# 가장 많이 놓인 칸이 밭이면 짓지 않는다(밭 위 저장고는 저장고이자 밭으로 두 번 세고 밭 먹이를 먹을 수 없음 —
	# _plant 도 저장고 칸에는 심지 않음). 기본값(farm.radius < store.min_spacing)에서는 간격 규칙이 이미 막는 경우.
	var build := best != -1 and tiles[best] != SimGrid.TILE_FARM
	if build and stage >= STAGE_STORE:
		if store_tiles.size() >= int(cfg.store.max_count):
			build = false
		else:
			var spacing := int(cfg.store.min_spacing)
			for s in store_tiles:
				if absi(s % w - best % w) + absi(s / w - best / w) < spacing:
					build = false
					break
	_reset_region(r)
	if not build:
		return
	# 그 칸의 바닥 먹이 더미는 새 저장고에 넣는다(용량까지 — 저장고 칸에서는 입력·먹기가 저장분만 보므로 더미가 숨지 않게).
	# 용량을 넘는 몫만 바닥에 남아 썩는다.
	var moved := minf(dropped[best], _store_cap)
	dropped[best] -= moved
	store_tiles.append(best)
	store_food.append(moved)
	_rebuild_stores()
	if stage == STAGE_FORAGE:
		_discover(STAGE_STORE, "구역에 모아 놓은 먹이 %.0f" % float(cfg.discovery.store_threshold))
	_event("store_built", -1, "저장고 %d호 — (%d, %d)" % [store_tiles.size(), best % w, best / w], {tile = best})


func _region_best_tile(r: int) -> int:
	var rs := int(cfg.discovery.region_size)
	var rx := (r % regions_x) * rs
	var ry := (r / regions_x) * rs
	var best := -1
	for y in range(ry, mini(ry + rs, h)):
		for x in range(rx, mini(rx + rs, w)):
			var c := y * w + x
			if store_at[c] != NO_STORE or not SimGrid.passable(tiles[c]):
				continue
			if best == -1 or drop_total_tile[c] > drop_total_tile[best]:
				best = c
	return best


func _reset_region(r: int) -> void:
	var rs := int(cfg.discovery.region_size)
	var rx := (r % regions_x) * rs
	var ry := (r / regions_x) * rs
	region_drop[r] = 0.0
	for y in range(ry, mini(ry + rs, h)):
		for x in range(rx, mini(rx + rs, w)):
			drop_total_tile[y * w + x] = 0.0


func _rebuild_stores() -> void:
	store_at.fill(NO_STORE)
	for k in store_tiles.size():
		store_at[store_tiles[k]] = k
	store_dist = SimGrid.distance_field(tiles, w, h, store_tiles)


# ── 기록 ──

func _event(kind: String, actor: int, text: String, extra: Dictionary = {}) -> void:
	var e := {tick = tick, kind = kind, actor = actor, text = text, mean_gen = snappedf(mean_generation(), EVENT_GEN_STEP)}
	# extra 가 기본 값을 덮어씀(멸종 사건의 mean_gen)
	e.merge(extra, true)
	chronicle.append(e)
	# 알림용 사본(화면·4단계 청취자가 고쳐 써도 연대기가 바뀌지 않게)
	_pending_events.append(e.duplicate())


func _after_tick() -> void:
	var n := s_id.size()
	if n > peak_population:
		peak_population = n
	if n == 0 and extinct_tick == -1:
		extinct_tick = tick
		# 개체가 모두 사라진 뒤라 mean_generation() 은 0 — 마지막 개체군(이 틱에 죽은 개체)의 평균 세대를 싣는다
		_event("extinction", -1, "멸종 — 마지막 개체가 사라짐", {mean_gen = snappedf(_last_deaths_mean_gen(), EVENT_GEN_STEP)})
	if n > 0:
		var mg := mean_generation()
		var step_m := int(cfg.record.generation_milestone)
		while step_m > 0 and mg >= float(next_milestone):
			_event("milestone", -1, "평균 %d세대 도달 — 개체 %d" % [next_milestone, n])
			next_milestone += step_m
	if tick % int(cfg.hash.every) == 0:
		_hash_step()


## 방금 진행한 틱에 죽은 개체들의 평균 세대(계통 기록 lin_death 로 셈 — 멸종 때 한 번만 부름, 상태를 따로 두지 않아
## 스냅숏에서 이어 돌려도 같음). 죽은 개체가 없으면 0.
func _last_deaths_mean_gen() -> float:
	var t := tick - 1
	var s := 0
	var n := 0
	for id in lin_death.size():
		if lin_death[id] == t:
			s += lin_gen[id]
			n += 1
	return float(s) / float(n) if n > 0 else 0.0


func _hash_step() -> void:
	var gsum := 0.0
	for v in s_genome:
		gsum += v
	var psum := 0
	var idsum := 0
	for i in s_id.size():
		psum += s_x[i] * h + s_y[i] + s_head[i]
		idsum += s_id[i]
	var foodsum := 0.0
	for v in food:
		foodsum += v
	var line := "%s|%d|%d|%d|%d|%d|%s|%s|%s|%s" % [history_hash, tick, s_id.size(), idsum, psum, stage,
			bits(total_energy()), bits(gsum), bits(foodsum), bits(store_drops_total)]
	history_hash = line.sha256_text()


static func bits(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


# ════════════════════════════ 질의(화면·기록·검사용, 읽기 전용) ════════════════════════════

func population() -> int:
	return s_id.size()


func total_energy() -> float:
	var s := 0.0
	for v in s_energy:
		s += v
	return s


## 장부상 있어야 할 에너지 합(현재 합과 같아야 한다).
func ledger_expected() -> float:
	return led_initial + led_eaten - led_spent - led_repro_loss - led_died


func mean_generation() -> float:
	var n := s_gen.size()
	if n == 0:
		return 0.0
	var s := 0
	for g in s_gen:
		s += g
	return float(s) / float(n)


func mean_of(arr: PackedFloat64Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += v
	return s / float(arr.size())


func mean_sense() -> float:
	if s_sense.is_empty():
		return 0.0
	var s := 0
	for v in s_sense:
		s += v
	return float(s) / float(s_sense.size())


func mean_age() -> float:
	if s_age.is_empty():
		return 0.0
	var s := 0
	for v in s_age:
		s += v
	return float(s) / float(s_age.size())


func sum_of(arr: PackedFloat64Array) -> float:
	var s := 0.0
	for v in arr:
		s += v
	return s


func index_of_id(id: int) -> int:
	var lo := 0
	var hi := s_id.size() - 1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if s_id[mid] == id:
			return mid
		if s_id[mid] < id:
			lo = mid + 1
		else:
			hi = mid - 1
	return -1


func is_extinct() -> bool:
	return s_id.is_empty()


func drain_events() -> Array:
	var e := _pending_events
	_pending_events = []
	return e


## 개체 정보(살아 있으면 현재 상태 포함, 죽었으면 계통 기록만). 없는 id 면 {}.
func slime_info(id: int) -> Dictionary:
	if id < 0 or id >= lin_pa.size():
		return {}
	var d := {
		id = id, parent_a = lin_pa[id], parent_b = lin_pb[id], gen = lin_gen[id], birth = lin_birth[id],
		death = lin_death[id], cause = lin_cause[id], children = lin_children[id],
		size = lin_size[id], sense = lin_sense[id], hue = lin_hue[id], alive = false,
	}
	var i := index_of_id(id)
	if i != -1:
		d.alive = true
		d.x = s_x[i]
		d.y = s_y[i]
		d.heading = s_head[i]
		d.age = s_age[i]
		d.max_age = s_max_age[i]
		d.energy = s_energy[i]
		d.energy_max = s_emax[i]
		d.carry = s_carry[i]
		d.action = s_last_action[i]
		d.genome = s_genome.slice(i * _G, (i + 1) * _G)
	return d


## id 의 자식 id 목록(태어난 순서, 최대 limit 개). 계통 배열을 처음부터 훑으므로 클릭 때만 부른다.
func children_of(id: int, limit: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if id < 0 or id >= lin_pa.size():
		return out
	for c in range(id + 1, lin_pa.size()):
		if lin_pa[c] == id or lin_pb[c] == id:
			out.append(c)
			if out.size() >= limit:
				break
	return out


## 시계열 한 줄(기록기가 CSV 로 씀). 호출하면 기간 출생·사망 수를 0 으로 되돌린다.
func sample() -> Dictionary:
	var stored := sum_of(store_food)
	var row := {
		tick = tick, day = tick / int(cfg.time.day_ticks), season = season, light = light,
		population = s_id.size(), births = period_births, deaths = period_deaths,
		mean_gen = mean_generation(), mean_energy = mean_of(s_energy), mean_size = mean_of(s_size),
		mean_sense = mean_sense(), mean_age = mean_age(), food_total = sum_of(food),
		dropped_total = sum_of(dropped), stored_total = stored, carry_total = sum_of(s_carry),
		civ_stage = stage, storehouses = store_tiles.size(), farms = farms.size(),
		forage_attempts = forage_attempts, store_drops = store_drops_total, farm_sprouts = farm_sprouts,
	}
	period_births = 0
	period_deaths = 0
	return row


