extends RefCounted
## "세계 그대로" 검사 도우미(검사 모듈이 아님 — 이름이 _checks.gd 가 아니라 실행기가 돌리지 않음).
## 역사 해시는 hash.every(기본 100)틱마다만 바뀌므로, 틱을 진행하지 않은 채 해시를 견주면 아무것도 증명하지 못한다
## (검토 I89: 화면 동작이 세계의 에너지·유전체를 바꿔도 "세계 그대로" 검사가 통과했음). 대신 스냅숏의 모든 절
## (SimSnapshot.to_dict — 개체·지도·문명·계통·통계·난수 상태·설정·연대기·역사 해시)을 글로 굳혀 견준다.
##
## 스냅숏을 열면 첫 기록 줄(SimWorld.sample)이 기간 출생·사망 수를 0 으로 가져가므로, 연 세계를 저장한 세계와 견줄 때는
## OPENED_IGNORE 를 넘긴다.
##
## 쓰는 법(화면 동작 앞뒤의 같은 세계):
##   const WorldCompare := preload("res://tests/view/world_compare.gd")
##   var before := WorldCompare.fingerprint(w)
##   … 화면 동작 …
##   t.check(WorldCompare.diff(before, w) == "", "… 세계 그대로 %s" % WorldCompare.diff(before, w))
## 두 세계(화면으로 돌린 세계 대 헤드리스 세계, 연 스냅숏 대 원래 세계): WorldCompare.same(a, b) == "".
## 결과는 같으면 "", 다르면 다른 절 이름("slimes.energy, civ.stage" 처럼 — 최대 MAX_LISTED 개).

## 다른 절 이름을 이만큼까지 적는다
const MAX_LISTED := 8
## 연 스냅숏의 세계에서 다를 수 있는 절(열 때 기록한 첫 줄이 기간 카운터를 비움)
const OPENED_IGNORE := ["stats.period_births", "stats.period_deaths"]


## 세계의 지문: 스냅숏 절마다(한 단계 아래 키까지) JSON 글. 사전·배열은 깊이 굳히므로 뒤에 세계가 바뀌어도 그대로.
static func fingerprint(w: SimWorld) -> Dictionary:
	var out := {}
	if w == null:
		return out
	var d := SimSnapshot.to_dict(w)
	for k: String in d:
		var v: Variant = d[k]
		if v is Dictionary:
			for k2: String in v:
				out["%s.%s" % [k, k2]] = JSON.stringify(v[k2], "", true, true)
		else:
			out[k] = JSON.stringify(v, "", true, true)
	return out


## 지문 둘을 견준다. 같으면 "", 다르면 다른 절 이름. ignore = 보지 않을 절 이름("stats.period_births" 처럼 — 까닭이 있는
## 것만: 예를 들어 스냅숏을 열면 첫 기록 줄(sample)이 기간 출생·사망 수를 가져간다).
static func compare(x: Dictionary, y: Dictionary, ignore: Array = []) -> String:
	if x.is_empty() or y.is_empty():
		return "세계 없음"
	var keys: Array = x.keys()
	for k in y.keys():
		if not x.has(k):
			keys.append(k)
	keys.sort()
	var diffs: Array[String] = []
	for k in keys:
		if not ignore.has(k) and x.get(k, null) != y.get(k, null):
			diffs.append(str(k))
	if diffs.size() > MAX_LISTED:
		return ", ".join(diffs.slice(0, MAX_LISTED)) + " … (%d개)" % diffs.size()
	return ", ".join(diffs)


## 앞서 뜬 지문과 지금 세계가 같은가(같은 세계의 동작 앞뒤). 같으면 "".
static func diff(before: Dictionary, w: SimWorld, ignore: Array = []) -> String:
	return compare(before, fingerprint(w), ignore)


## 두 세계의 상태가 같은가(틱·해시만이 아니라 모든 절). 같으면 "".
static func same(a: SimWorld, b: SimWorld, ignore: Array = []) -> String:
	return compare(fingerprint(a), fingerprint(b), ignore)
