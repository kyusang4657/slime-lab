class_name SimGrid
extends RefCounted
## 격자 칸·이웃·BFS. 순수 함수만 둔다(시뮬레이션·검사·화면이 함께 사용).
## 이전 프로젝트(little-monster-village)의 scripts/core/grid_logic.gd 에서 BFS 경로 부분을 가져와
## 울타리·건물 점유를 빼고 "통과 가능 칸"과 "다중 출발 거리장"만 남겼다.
##
## 칸 번호 c = y * width + x. 방향 0 북(0,-1) · 1 동(1,0) · 2 남(0,1) · 3 서(-1,0), 오른쪽 = (h + 1) % 4.

const TILE_GRASS := 0
const TILE_WATER := 1
const TILE_ROCK := 2
const TILE_FARM := 3

const DIR_COUNT := 4
const DX: Array[int] = [0, 1, 0, -1]
const DY: Array[int] = [-1, 0, 1, 0]
## 거리장에서 닿지 않는 칸.
const FAR := 1 << 30


static func passable(kind: int) -> bool:
	return kind == TILE_GRASS or kind == TILE_FARM


static func right_of(h: int) -> int:
	return (h + 1) % DIR_COUNT


static func left_of(h: int) -> int:
	return (h + DIR_COUNT - 1) % DIR_COUNT


## 다중 출발 BFS 거리장. sources 의 칸에서 통과 가능 칸만 따라 4이웃 거리. 닿지 않으면 FAR.
## 이웃 순서와 큐 순서가 고정이라 결과는 결정적이다.
static func distance_field(tiles: PackedByteArray, w: int, h: int, sources: PackedInt32Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(FAR)
	var queue := PackedInt32Array()
	queue.resize(w * h)
	var head := 0
	var tail := 0
	for s in sources:
		if s >= 0 and s < w * h and dist[s] == FAR:
			dist[s] = 0
			queue[tail] = s
			tail += 1
	while head < tail:
		var c := queue[head]
		head += 1
		var x := c % w
		var y := c / w
		var nd := dist[c] + 1
		for d in DIR_COUNT:
			var nx: int = x + DX[d]
			var ny: int = y + DY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var n := ny * w + nx
			if dist[n] != FAR or not passable(tiles[n]):
				continue
			dist[n] = nd
			queue[tail] = n
			tail += 1
	return dist


## 통과 가능 칸의 연결 요소 번호(통과 불가 = -1). 결과: {labels, sizes}
static func components(tiles: PackedByteArray, w: int, h: int) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(w * h)
	labels.fill(-1)
	var sizes := PackedInt32Array()
	for c in w * h:
		if labels[c] != -1 or not passable(tiles[c]):
			continue
		var id := sizes.size()
		var src := PackedInt32Array([c])
		var d := distance_field(tiles, w, h, src)
		var count := 0
		for i in w * h:
			if d[i] != FAR:
				labels[i] = id
				count += 1
		sizes.append(count)
	return {labels = labels, sizes = sizes}
