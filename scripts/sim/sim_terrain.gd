class_name SimTerrain
extends RefCounted
## 씨앗으로 지형을 만든다: 정수 해시 값 잡음(value noise) 두 겹 → 비옥도·물, 별도 잡음 → 바위.
## 정수 곱셈은 62비트 안에서 끝나도록 상수를 2^30 미만으로 두고, 실수는 사칙연산만 쓴다.

const MASK32 := 0xffffffff
const HASH_PX := 374761393
const HASH_PY := 668265263
const HASH_PS := 1013904223
const HASH_MIX := 1274126177
const HASH_SHIFT_A := 13
const HASH_SHIFT_B := 16
const TWO_POW_32 := 4294967296.0
## 잡음 층마다 씨앗을 다르게 섞는 값.
const SALT_DETAIL := 1
const SALT_ROCK := 2
## smoothstep t*t*(3 - 2t) 의 계수.
const SMOOTH_A := 3.0
const SMOOTH_B := 2.0


static func hash01(ix: int, iy: int, s: int) -> float:
	var h := ((ix & MASK32) * HASH_PX + (iy & MASK32) * HASH_PY + (s & MASK32) * HASH_PS) & MASK32
	h = ((h ^ (h >> HASH_SHIFT_A)) * HASH_MIX) & MASK32
	h = h ^ (h >> HASH_SHIFT_B)
	return float(h) / TWO_POW_32


static func _smooth(t: float) -> float:
	return t * t * (SMOOTH_A - SMOOTH_B * t)


## 격자 간격 cell 의 값 잡음, 0~1.
static func value_noise(x: int, y: int, cell: int, s: int) -> float:
	var cx := x / cell
	var cy := y / cell
	var tx := _smooth(float(x - cx * cell) / float(cell))
	var ty := _smooth(float(y - cy * cell) / float(cell))
	var a := hash01(cx, cy, s)
	var b := hash01(cx + 1, cy, s)
	var c := hash01(cx, cy + 1, s)
	var d := hash01(cx + 1, cy + 1, s)
	var top := a + (b - a) * tx
	var bot := c + (d - c) * tx
	return top + (bot - top) * ty


## 결과: {tiles: PackedByteArray, fertility: PackedFloat64Array}. 통과 가능 칸은 하나로 이어진다(작은 섬은 바위로).
static func generate(cfg: Dictionary, seed_value: int) -> Dictionary:
	var m: Dictionary = cfg.map
	var w := int(m.width)
	var h := int(m.height)
	var cell := int(m.noise_cell)
	var dcell := int(m.noise_detail_cell)
	var dw := float(m.noise_detail_weight)
	var water := float(m.water_level)
	var rcell := int(m.rock_noise_cell)
	var rock := float(m.rock_level)
	var floor_f := float(m.fertility_floor)
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	var fert := PackedFloat64Array()
	fert.resize(w * h)
	for y in h:
		for x in w:
			var c := y * w + x
			var raw := (1.0 - dw) * value_noise(x, y, cell, seed_value) + dw * value_noise(x, y, dcell, seed_value + SALT_DETAIL)
			if raw < water:
				tiles[c] = SimGrid.TILE_WATER
				fert[c] = 0.0
				continue
			if value_noise(x, y, rcell, seed_value + SALT_ROCK) > rock:
				tiles[c] = SimGrid.TILE_ROCK
				fert[c] = 0.0
				continue
			tiles[c] = SimGrid.TILE_GRASS
			var t := clampf((raw - water) / (1.0 - water), 0.0, 1.0)
			fert[c] = floor_f + (1.0 - floor_f) * t
	# 가장 큰 통과 가능 영역만 남긴다(같은 크기면 번호가 작은 영역).
	var comp := SimGrid.components(tiles, w, h)
	var sizes: PackedInt32Array = comp.sizes
	var best := -1
	for i in sizes.size():
		if best == -1 or sizes[i] > sizes[best]:
			best = i
	var labels: PackedInt32Array = comp.labels
	for c in w * h:
		if SimGrid.passable(tiles[c]) and labels[c] != best:
			tiles[c] = SimGrid.TILE_ROCK
			fert[c] = 0.0
	return {tiles = tiles, fertility = fert}
