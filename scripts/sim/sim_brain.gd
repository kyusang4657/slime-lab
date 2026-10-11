class_name SimBrain
extends RefCounted
## 슬라임 두뇌(고정 구조 앞먹임 신경망)와 유전체 연산. 설계: docs/DESIGN-v0.1.md 4절, v0.2 의 평생 학습·생애 단계는
## docs/DESIGN-v0.2.md 2·3절.
##
## 유전체(PackedFloat32Array, 개체당 genes 칸) 배치(꺼진 구간은 길이 0 — v0.2 3.7):
##   [w1: 은닉 j 마다 입력 n_in 개] [w2: 출력 q 마다 은닉 n_hid 개] [특성: size, sense, hue] [η: 행동 행마다 학습률 — learn.enabled]
## 입력 n_in = 기본 12 + 기억 m, 출력 n_out = 기본 8 + 기억 m. 기억 출력은 softsign 을 거쳐 다음 판단의 입력이 된다.
## 활성 함수 softsign(x / (1 + |x|)) — 사칙연산만이라 플랫폼마다 같은 비트.
## 평생 학습(learn.enabled): 개체마다 출력층 행동 8행의 '배운 두뇌' 사본(float64)을 따로 들고 고친다(유전되지 않음). 기억 출력 행과
## 입력층 W1 은 늘 유전체에서 읽는다. 순전파는 forward_phen, 갱신 식은 learn_update(세계는 같은 식을 펼쳐 씀 — 검사로 비트 일치).

const BASE_INPUTS := 12
const BASE_OUTPUTS := 8
const TRAIT_GENES := 3
const POLICY_SAMPLE := "sample"
const POLICY_ARGMAX := "argmax"
const TRAIT_SIZE := 0
const TRAIT_SENSE := 1
const TRAIT_HUE := 2
## 학습률 유전자 η 의 수(행동 행마다 하나 — DESIGN-v0.2 3.7). 학습을 끄면 유전체에 붙지 않음(길이 0).
const ETA_GENES := BASE_OUTPUTS
## 갱신 보정 e 의 고를 값(learn.diag_factor — SimConfig.CHOICES 와 같음, 검사): exact = (1 − π)·k·d(o), none = 1 − π(DESIGN-v0.2 3.5).
const DIAG_EXACT := "exact"
const DIAG_NONE := "none"
## 생애 단계(DESIGN-v0.2 2.1): 나이에서 계산하고 저장하지 않음(life_stage). 번호가 첨자.
const LIFE_JUVENILE := 0
const LIFE_YOUNG := 1
const LIFE_ADULT := 2
const LIFE_OLD := 3
const LIFE_STAGE_NAMES: Array[String] = ["어린", "젊은", "어른", "늙은"]

## 입력 번호
const IN_BIAS := 0
const IN_ENERGY := 1
const IN_FOOD_HERE := 2
const IN_FOOD_AHEAD := 3
const IN_FOOD_LEFT := 4
const IN_FOOD_RIGHT := 5
const IN_CROWD := 6
const IN_LIGHT := 7
const IN_CARRY := 8
const IN_STORE_DIR := 9
const IN_STORE_NEAR := 10
const IN_SEASON := 11

## 행동(출력) 번호
const ACT_FORWARD := 0
const ACT_LEFT := 1
const ACT_RIGHT := 2
const ACT_EAT := 3
const ACT_REST := 4
const ACT_GATHER := 5
const ACT_DROP := 6
const ACT_PLANT := 7
## 행동 화면 이름. 1·2 는 제자리에서 방향만 바꾼다(칸을 옮기는 것은 0 앞으로뿐) — "왼쪽으로" 처럼 이동으로 읽히지 않게 "돌기".
const ACTION_NAMES: Array[String] = ["앞으로", "왼쪽 돌기", "오른쪽 돌기", "먹기", "쉬기", "줍기", "내려놓기", "심기"]
const INPUT_NAMES: Array[String] = ["편향", "에너지", "발밑 먹이", "앞 먹이", "왼 먹이", "오른 먹이", "붐빔", "빛", "운반", "저장고 방향", "저장고 가까움", "계절"]


## 설정에서 구조를 계산한다. n_act = 행동 출력 수(배운 두뇌의 행 수), eta_offset·eta_len = 학습률 유전자 구간(학습 끔이면 길이 0 —
## 유전자 163 그대로, 켜면 171).
static func layout(cfg: Dictionary) -> Dictionary:
	var m := int(cfg.brain.memory_units)
	var hid := int(cfg.brain.hidden)
	var n_in := BASE_INPUTS + m
	var n_out := BASE_OUTPUTS + m
	var w1 := hid * n_in
	var w2 := n_out * hid
	var eta_len := ETA_GENES if bool(cfg.learn.enabled) else 0
	return {
		n_in = n_in, n_hid = hid, n_out = n_out, n_mem = m, n_act = BASE_OUTPUTS,
		w2_offset = w1, trait_offset = w1 + w2, eta_offset = w1 + w2 + TRAIT_GENES, eta_len = eta_len,
		genes = w1 + w2 + TRAIT_GENES + eta_len,
	}


static func softsign(x: float) -> float:
	return x / (1.0 + absf(x))


## 초기 유전체 하나(가중치 균등, 특성 = 초기값, 색 균등).
static func random_genome(cfg: Dictionary, L: Dictionary, rng: SimRng) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(L.genes)
	var r := float(cfg.brain.init_range)
	var t: int = L.trait_offset
	for i in t:
		g[i] = rng.range_f(-r, r)
	g[t + TRAIT_SIZE] = float(cfg.traits.size_init)
	g[t + TRAIT_SENSE] = float(cfg.traits.sense_init)
	g[t + TRAIT_HUE] = rng.uniform()
	# 학습률 유전자: 난수 없이 처음 값(뽑기 순서는 v0.1 그대로 — DESIGN-v0.2 3.7)
	var eo: int = L.eta_offset
	for k in int(L.eta_len):
		g[eo + k] = float(cfg.learn.eta_init)
	return g


## 뉴런 단위 교차: 은닉 뉴런 j 의 들어오는 가중치와 나가는 가중치를 한 덩어리로 부모 a·b 중 하나에서 가져온다.
static func crossover(L: Dictionary, a: PackedFloat32Array, b: PackedFloat32Array, rng: SimRng) -> PackedFloat32Array:
	var g := a.duplicate()
	var n_in: int = L.n_in
	var n_hid: int = L.n_hid
	var n_out: int = L.n_out
	var w2o: int = L.w2_offset
	for j in n_hid:
		if rng.uniform() < 0.5:
			continue
		for i in n_in:
			g[j * n_in + i] = b[j * n_in + i]
		for q in n_out:
			g[w2o + q * n_hid + j] = b[w2o + q * n_hid + j]
	var t: int = L.trait_offset
	for k in TRAIT_GENES:
		if rng.uniform() >= 0.5:
			g[t + k] = b[t + k]
	# 특성 뒤 구간(η): 특성과 같은 꼴로 유전자 하나씩. 꺼진 구간은 길이 0 이라 뽑지 않음(rng_life 뽑기 수 그대로 — 3.7)
	var eo: int = L.eta_offset
	for k in int(L.eta_len):
		if rng.uniform() >= 0.5:
			g[eo + k] = b[eo + k]
	return g


## 돌연변이: 유전자마다 확률 rate 로 N(0, sigma × 배율)을 더하고 범위를 자른다. 바꾼 유전자 수를 돌려준다.
static func mutate(cfg: Dictionary, L: Dictionary, g: PackedFloat32Array, rng: SimRng) -> int:
	var rate := float(cfg.mutation.rate)
	var sigma := float(cfg.mutation.sigma)
	var clamp_w := float(cfg.brain.weight_clamp)
	var tr: Dictionary = cfg.traits
	var t: int = L.trait_offset
	var changed := 0
	for i in t:
		if rng.uniform() < rate:
			g[i] = clampf(g[i] + rng.normal() * sigma, -clamp_w, clamp_w)
			changed += 1
	if rng.uniform() < rate:
		g[t + TRAIT_SIZE] = clampf(g[t + TRAIT_SIZE] + rng.normal() * sigma * float(tr.mutation_scale_size), float(tr.size_min), float(tr.size_max))
		changed += 1
	if rng.uniform() < rate:
		g[t + TRAIT_SENSE] = clampf(g[t + TRAIT_SENSE] + rng.normal() * sigma * float(tr.mutation_scale_sense), float(tr.sense_min), float(tr.sense_max))
		changed += 1
	if rng.uniform() < rate:
		var hue: float = g[t + TRAIT_HUE] + rng.normal() * sigma * float(tr.mutation_scale_hue)
		while hue < 0.0:
			hue += 1.0
		while hue >= 1.0:
			hue -= 1.0
		g[t + TRAIT_HUE] = hue
		changed += 1
	# η: 특성 뒤에만 붙으므로 꺼져 있으면 뽑기 수가 그대로. 범위 [0, learn.eta_max] 로 자름
	var eo: int = L.eta_offset
	if int(L.eta_len) > 0:
		var lc: Dictionary = cfg.learn
		var eta_max := float(lc.eta_max)
		var eta_sigma := sigma * float(lc.mutation_scale_eta)
		for k in int(L.eta_len):
			if rng.uniform() < rate:
				g[eo + k] = clampf(g[eo + k] + rng.normal() * eta_sigma, 0.0, eta_max)
				changed += 1
	return changed


## 정책 가중치 (1 + softsign(o))^k. k 는 정수(거듭 곱셈만 써서 플랫폼마다 같은 비트).
static func policy_weight(o: float, k: int) -> float:
	var b := 1.0 + o / (1.0 + absf(o))
	var wv := 1.0
	for i in k:
		wv *= b
	return wv


## 기본 출력 중 가장 큰 번호(같으면 작은 번호).
static func argmax_action(out: PackedFloat64Array) -> int:
	var best := 0
	for q in BASE_OUTPUTS:
		if out[q] > out[best]:
			best = q
	return best


## 순전파(할당하는 판, 검사·정보 창용). 시뮬레이션은 같은 식을 SimWorld._think 에 펼쳐 쓴다(검사로 일치 확인).
## 결과: {hidden, out, probs}. probs = sample 정책의 행동 확률(기본 출력 8개).
static func forward(L: Dictionary, genome: PackedFloat32Array, base: int, inputs: PackedFloat64Array, sharpness: int = 1) -> Dictionary:
	var n_in: int = L.n_in
	var n_hid: int = L.n_hid
	var n_out: int = L.n_out
	var hid := PackedFloat64Array()
	hid.resize(n_hid)
	var out := PackedFloat64Array()
	out.resize(n_out)
	for j in n_hid:
		var s := 0.0
		var o: int = base + j * n_in
		for i in n_in:
			s += float(genome[o + i]) * inputs[i]
		hid[j] = softsign(s)
	var w2o: int = base + L.w2_offset
	for q in n_out:
		var s2 := 0.0
		var o2: int = w2o + q * n_hid
		for j in n_hid:
			s2 += float(genome[o2 + j]) * hid[j]
		out[q] = s2
	var probs := PackedFloat64Array()
	probs.resize(BASE_OUTPUTS)
	var total := 0.0
	for q in BASE_OUTPUTS:
		probs[q] = policy_weight(out[q], sharpness)
		total += probs[q]
	for q in BASE_OUTPUTS:
		probs[q] /= total
	return {hidden = hid, out = out, probs = probs, action = argmax_action(out)}


## 순전파 — 평생 학습을 켠 세계(DESIGN-v0.2 3.1). forward 와 같되 행동 출력 q < BASE_OUTPUTS 의 W2 는 배운 두뇌 w2(float64,
## w2_base 부터 q × n_hid + j)에서, 기억 출력 행과 W1 은 유전체에서 읽는다. SimWorld._think 의 표현형 경로와 비트 단위로 같다(검사).
static func forward_phen(L: Dictionary, genome: PackedFloat32Array, base: int, w2: PackedFloat64Array, w2_base: int,
		inputs: PackedFloat64Array, sharpness: int = 1) -> Dictionary:
	var n_in: int = L.n_in
	var n_hid: int = L.n_hid
	var n_out: int = L.n_out
	var hid := PackedFloat64Array()
	hid.resize(n_hid)
	var out := PackedFloat64Array()
	out.resize(n_out)
	for j in n_hid:
		var s := 0.0
		var o: int = base + j * n_in
		for i in n_in:
			s += float(genome[o + i]) * inputs[i]
		hid[j] = softsign(s)
	for q in BASE_OUTPUTS:
		var s2 := 0.0
		var oq: int = w2_base + q * n_hid
		for j in n_hid:
			s2 += w2[oq + j] * hid[j]
		out[q] = s2
	var w2o: int = base + L.w2_offset
	for q in range(BASE_OUTPUTS, n_out):
		var s3 := 0.0
		var o3: int = w2o + q * n_hid
		for j in n_hid:
			s3 += float(genome[o3 + j]) * hid[j]
		out[q] = s3
	var probs := PackedFloat64Array()
	probs.resize(BASE_OUTPUTS)
	var total := 0.0
	for q in BASE_OUTPUTS:
		probs[q] = policy_weight(out[q], sharpness)
		total += probs[q]
	for q in BASE_OUTPUTS:
		probs[q] /= total
	return {hidden = hid, out = out, probs = probs, action = argmax_action(out)}


## 생애 단계(DESIGN-v0.2 2.1). 판정 순서: 나이 < 성숙이면 어린, 그다음 늙은(나이 ≥ old_frac × 수명) → 어른(≥ adult_frac × 수명) → 젊은.
## 그래서 adult_frac × 수명 < 성숙이면 젊은 구간이 비고, old_frac × 수명 < 성숙이면 어린 다음이 바로 늙은이다.
static func life_stage(age: int, max_age: int, maturity: int, adult_frac: float, old_frac: float) -> int:
	if age < maturity:
		return LIFE_JUVENILE
	var a := float(age)
	var m := float(max_age)
	if a >= old_frac * m:
		return LIFE_OLD
	if a >= adult_frac * m:
		return LIFE_ADULT
	return LIFE_YOUNG


## 몸 크기 비율 g(나이)(DESIGN-v0.2 2.2) = f + (1 − f) × min(나이, M) ÷ M. M = 성숙 나이(0 이면 1), 성숙 뒤는 정확히 1
## (f + (1 − f) 가 반올림으로 1 이 아닐 수 있어 따로 — 성숙한 몸이 v0.1 과 같은 비트).
static func growth_factor(age: int, maturity: int, birth_frac: float) -> float:
	if maturity <= 0 or age >= maturity:
		return 1.0
	return birth_frac + (1.0 - birth_frac) * float(age) / float(maturity)


## 갱신 보정 e(DESIGN-v0.2 3.5): 고른 행 a 의 log π_a 를 출력 o_a 로 미분한 대각 항. exact = (1 − π_a) × k × d(o),
## d(o) = 1 ÷ (1 + |o|)(o < 0), 1 ÷ ((1 + o)(1 + 2o))(o ≥ 0). exact 가 아니면 1 − π_a. 세계는 같은 식을 펼쳐 씀(검사).
static func diag_e(o: float, pi_a: float, sharpness: int, exact: bool) -> float:
	if not exact:
		return 1.0 - pi_a
	var d := 1.0 / (1.0 + absf(o)) if o < 0.0 else 1.0 / ((1.0 + o) * (1.0 + 2 * o))
	return (1.0 - pi_a) * float(sharpness) * d


## λᵐ 표(m = 0 … H − 1, 거듭 곱 — ** 를 쓰지 않음, DESIGN-v0.1 7.1).
static func decay_table(decay: float, ring_len: int) -> PackedFloat64Array:
	var lam := PackedFloat64Array()
	lam.resize(ring_len)
	var v := 1.0
	for m in ring_len:
		lam[m] = v
		v *= decay
	return lam


## 학습 갱신 한 번(DESIGN-v0.2 3.5, 손 계산 검사용 — 세계는 SimWorld._learn 에 같은 식을 펼쳐 씀). 고리(개체의 칸 ring_base … +H − 1,
## 다음에 쓸 자리 pos)의 m = 0(방금) … H − 1 차례로: 슬롯 s = (pos − 1 − m + H) mod H, a = ring_a[s](음수면 건너뜀),
## c = δ × mult × η[a] × λᵐ × ring_e[s], j = 0 … 은닉 − 1: w = w2[a, j] + c × ring_h[s, j] 를 ±clamp 로 자름(비교로).
## η[a] = genome[eta_base + a]. w2 를 그 자리에서 고치고, 실제로 바뀐 양(자른 뒤 abs(새 − 옛))의 합을 돌려준다(어린 동안 배운 양).
static func learn_update(w2: PackedFloat64Array, w2_base: int, n_hid: int, ring_a: PackedInt32Array, ring_e: PackedFloat32Array,
		ring_h: PackedFloat32Array, ring_base: int, ring_len: int, pos: int, delta: float, mult: float,
		genome: PackedFloat32Array, eta_base: int, lam: PackedFloat64Array, clamp_w: float) -> float:
	var moved := 0.0
	var dm := delta * mult
	for m in ring_len:
		var s := (pos - 1 - m + ring_len) % ring_len
		var a := ring_a[ring_base + s]
		if a < 0:
			continue
		var c := dm * float(genome[eta_base + a]) * lam[m] * float(ring_e[ring_base + s])
		var hb := (ring_base + s) * n_hid
		var wb := w2_base + a * n_hid
		for j in n_hid:
			var old := w2[wb + j]
			var nw := old + c * float(ring_h[hb + j])
			if nw > clamp_w:
				nw = clamp_w
			elif nw < -clamp_w:
				nw = -clamp_w
			moved += absf(nw - old)
			w2[wb + j] = nw
	return moved


## 배운 양 dw(DESIGN-v0.2 11.2) = 행동 가중치 n_act × n_hid 개의 abs(배운 − 타고난) 평균.
static func learned_amount(L: Dictionary, genome: PackedFloat32Array, base: int, w2: PackedFloat64Array, w2_base: int) -> float:
	var n_hid: int = L.n_hid
	var w2o: int = base + L.w2_offset
	var s := 0.0
	for q in BASE_OUTPUTS:
		for j in n_hid:
			s += absf(w2[w2_base + q * n_hid + j] - float(genome[w2o + q * n_hid + j]))
	return s / float(BASE_OUTPUTS * n_hid)


## 동화 지수 assim(DESIGN-v0.2 11.2): 고리의 채워진 칸(ring_a ≥ 0)의 은닉 값마다, 타고난 W2 로 고른 가장 큰 행동과 배운 W2 로 고른
## 가장 큰 행동(같으면 작은 번호)이 같은 몫(0~1). 채워진 칸이 없으면 0.
static func assimilation(L: Dictionary, genome: PackedFloat32Array, base: int, w2: PackedFloat64Array, w2_base: int,
		ring_a: PackedInt32Array, ring_h: PackedFloat32Array, ring_base: int, ring_len: int) -> float:
	var n_hid: int = L.n_hid
	var w2o: int = base + L.w2_offset
	var seen := 0
	var same := 0
	for s in ring_len:
		if ring_a[ring_base + s] < 0:
			continue
		seen += 1
		var hb := (ring_base + s) * n_hid
		var best_g := 0
		var best_l := 0
		var top_g := 0.0
		var top_l := 0.0
		for q in BASE_OUTPUTS:
			var og := 0.0
			var ol := 0.0
			for j in n_hid:
				var hv := float(ring_h[hb + j])
				og += float(genome[w2o + q * n_hid + j]) * hv
				ol += w2[w2_base + q * n_hid + j] * hv
			if q == 0 or og > top_g:
				top_g = og
				best_g = q
			if q == 0 or ol > top_l:
				top_l = ol
				best_l = q
		if best_g == best_l:
			same += 1
	return float(same) / float(seen) if seen > 0 else 0.0

