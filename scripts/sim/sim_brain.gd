class_name SimBrain
extends RefCounted
## 슬라임 두뇌(고정 구조 앞먹임 신경망)와 유전체 연산. 설계: docs/DESIGN-v0.1.md 4절.
##
## 유전체(PackedFloat32Array, 개체당 genes 칸) 배치:
##   [w1: 은닉 j 마다 입력 n_in 개] [w2: 출력 q 마다 은닉 n_hid 개] [특성: size, sense, hue]
## 입력 n_in = 기본 12 + 기억 m, 출력 n_out = 기본 8 + 기억 m. 기억 출력은 softsign 을 거쳐 다음 판단의 입력이 된다.
## 활성 함수 softsign(x / (1 + |x|)) — 사칙연산만이라 플랫폼마다 같은 비트.

const BASE_INPUTS := 12
const BASE_OUTPUTS := 8
const TRAIT_GENES := 3
const POLICY_SAMPLE := "sample"
const POLICY_ARGMAX := "argmax"
const TRAIT_SIZE := 0
const TRAIT_SENSE := 1
const TRAIT_HUE := 2

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
const ACTION_NAMES: Array[String] = ["앞으로", "왼쪽으로", "오른쪽으로", "먹기", "쉬기", "줍기", "내려놓기", "심기"]
const INPUT_NAMES: Array[String] = ["편향", "에너지", "발밑 먹이", "앞 먹이", "왼 먹이", "오른 먹이", "붐빔", "빛", "운반", "저장고 방향", "저장고 가까움", "계절"]


## 설정에서 구조를 계산한다.
static func layout(cfg: Dictionary) -> Dictionary:
	var m := int(cfg.brain.memory_units)
	var hid := int(cfg.brain.hidden)
	var n_in := BASE_INPUTS + m
	var n_out := BASE_OUTPUTS + m
	var w1 := hid * n_in
	var w2 := n_out * hid
	return {
		n_in = n_in, n_hid = hid, n_out = n_out, n_mem = m,
		w2_offset = w1, trait_offset = w1 + w2, genes = w1 + w2 + TRAIT_GENES,
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
