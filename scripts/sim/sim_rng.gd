class_name SimRng
extends RefCounted
## 결정적 난수. Godot RandomNumberGenerator(PCG32)의 정수 출력만 쓰고,
## 실수 변환·정규 근사는 사칙연산과 sqrt 로 직접 한다(플랫폼마다 다를 수 있는 log·cos 를 쓰지 않음).

const TWO_POW_32 := 4294967296.0
## 어윈-홀 근사: 균등 난수 4개의 합. 평균 2, 분산 1/3.
const IRWIN_HALL_N := 4
## 분산 1/3 을 1 로 맞추는 배율의 제곱.
const IRWIN_HALL_VAR_INV := 3.0

var _r := RandomNumberGenerator.new()
var _norm_scale := sqrt(IRWIN_HALL_VAR_INV)


func _init(seed_value: int = 0) -> void:
	_r.seed = seed_value


## [0, 1) 균등 실수.
func uniform() -> float:
	return float(_r.randi()) / TWO_POW_32


## [lo, hi) 균등 실수.
func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * uniform()


## [0, n) 정수. n ≤ 0 이면 0.
func below(n: int) -> int:
	if n <= 0:
		return 0
	return int(uniform() * float(n))


## 표준 정규분포 근사(평균 0, 분산 1, 범위 ±2√3).
func normal() -> float:
	var s := 0.0
	for i in IRWIN_HALL_N:
		s += uniform()
	return (s - float(IRWIN_HALL_N) * 0.5) * _norm_scale


func chance(p: float) -> bool:
	return uniform() < p


## 상태 저장(64비트 정수라 JSON 실수로 담지 않고 문자열로).
func get_state_string() -> String:
	return str(_r.state)


func set_state_string(s: String) -> bool:
	if not s.is_valid_int():
		return false
	_r.state = s.to_int()
	return true
