extends RefCounted
## LabSound 검사. tests/run_view_tests.gd 가 불러 run(t) 을 부른다. 계약: docs/VIEW-API.md "LabSound".
## 합성 소리(16비트 모노·길이·최댓값·NaN 없음·같은 바이트·처음과 끝이 0 — 딸깍 없음·음높이 방향), 최소 간격,
## 꺼짐, 한 묶음에 하나(멸종 > 발견 > 저장고), 실험실 연결(events_tagged)과 역사 해시. 헤드리스는 더미 오디오 드라이버.
## "소리를 냄" 은 LabSound 의 셈(plays·last_sound)만이 아니라 실제 재생기(AudioStreamPlayer)가 그 소리의 파형으로 재생 중인지까지
## 본다(더미 드라이버도 play() 직후 playing — 재생 호출을 빼먹거나 다른 소리를 넣으면 실패).
## 들어 보려면: godot --headless --path . --script res://tools/render_sounds.gd -- --out=폴더

const DT := 1.0 / 60.0
## 처음·끝 샘플 허용치(FS 비)
const EDGE_MAX := 0.01
## 처음·끝 이 시간 안의 최댓값은 소리 최댓값의 EDGE_FRAC 아래(갑자기 시작·끝나지 않음)
const EDGE_WINDOW_S := 0.001
const EDGE_FRAC := 0.25
## 길이 범위(초)
const DUR_MIN := 0.15
const DUR_MAX := 1.2
## 들리는 소리(최댓값이 이보다 큼)
const AUDIBLE := 0.2
## 빨리 감기처럼 사건이 몰리는 경우: 1초 동안 이만큼
const BURST := 100
## 시계 대신 넣는 시각(초)
const T0 := 1000.0
## 끝에 오디오 서버가 멈춘 재생을 치울 시간(초 — 합격 여부와 무관한 정리)
const DRAIN_S := 0.2
## 이 모듈이 적어도 하는 검사 수(중간에 스크립트 오류로 끊기면 실행기가 실패로 셈)
const MIN_CHECKS := 59


func run(t) -> void:
	_synth(t)
	await _node(t)
	await _with_lab(t)


## ① 합성: 형식·길이·최댓값·NaN·덮개·같은 바이트·음높이
func _synth(t) -> void:
	var rate := UiConfig.integer("sound.mix_rate")
	t.check(rate == 22050 or rate == 44100, "표본율 %d Hz(22050 또는 44100)" % rate)
	var zcr := {}
	for s in LabSound.SOUNDS:
		var w := LabSound.synth(s)
		t.check(w != null, "%s 소리를 만듦" % s)
		if w == null:
			continue
		t.check(w.format == AudioStreamWAV.FORMAT_16_BITS and not w.stereo and w.mix_rate == rate and w.loop_mode == AudioStreamWAV.LOOP_DISABLED,
				"%s: 16비트 모노 %d Hz, 반복 없음" % [s, rate])
		var n := w.data.size() / 2
		var dur := float(n) / float(rate)
		t.check(dur >= DUR_MIN and dur <= DUR_MAX and absf(w.get_length() - dur) < 0.01, "%s: 길이 %.3f초(%.2f~%.1f)" % [s, dur, DUR_MIN, DUR_MAX])
		var peak := 0
		for i in n:
			peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
		var pk := float(peak) / LabSound.PCM_MAX
		t.check(pk <= 0.8 + 1.0e-4 and pk >= AUDIBLE, "%s: 최댓값 %.3f FS(≤ 0.8, 들림)" % [s, pk])
		var f := LabSound.synth_samples(s)
		var finite := f.size() == n
		for v in f:
			if is_nan(v) or is_inf(v):
				finite = false
				break
		t.check(finite, "%s: 샘플 %d개 모두 유한(NaN·inf 없음)" % [s, f.size()])
		t.check(absf(f[0]) <= EDGE_MAX and absf(f[n - 1]) <= EDGE_MAX, "%s: 처음·끝 샘플이 0 근처(%.4f, %.4f)" % [s, f[0], f[n - 1]])
		var win := maxi(2, int(EDGE_WINDOW_S * float(rate)))
		var head := 0.0
		var tail := 0.0
		for i in win:
			head = maxf(head, absf(f[i]))
			tail = maxf(tail, absf(f[n - 1 - i]))
		t.check(head <= pk * EDGE_FRAC and tail <= pk * EDGE_FRAC, "%s: 처음·끝 %.0fms 는 서서히(%.3f, %.3f ≤ %.3f)" % [s, EDGE_WINDOW_S * 1000.0, head, tail, pk * EDGE_FRAC])
		var again := LabSound.synth(s)
		t.check(again != null and again != w and again.data == w.data, "%s: 다시 만들어도 같은 바이트(결정적)" % s)
		zcr[s] = _crossings(f, 0, n) / dur
	t.check(LabSound.synth("없는소리") == null and LabSound.synth_samples("milestone").is_empty(), "없는 소리 이름 → null·빈 배열")
	t.check(LabSound.synth("discovery").data != LabSound.synth("store_built").data, "소리마다 다른 파형")
	# 음높이: 발견(높은 차임) > 멸종(낮은 음), 멸종은 내려감, 저장고는 짧음
	if zcr.has("discovery") and zcr.has("extinction"):
		t.check(float(zcr.discovery) > 3.0 * float(zcr.extinction), "발견이 멸종보다 훨씬 높은 소리(영점 교차 %.0f / %.0f 회/초)" % [float(zcr.discovery), float(zcr.extinction)])
	var ex := LabSound.synth_samples("extinction")
	var r := float(UiConfig.integer("sound.mix_rate"))
	if ex.size() > int(r):
		var early := _crossings(ex, int(0.05 * r), int(0.25 * r)) / 0.2
		var late := _crossings(ex, int(0.75 * r), int(0.95 * r)) / 0.2
		t.check(early > late * 1.4 and early / 2.0 < 300.0, "멸종: 낮은 음(약 %.0f Hz)에서 내려감(약 %.0f Hz)" % [early / 2.0, late / 2.0])
	var sb := LabSound.synth("store_built")
	t.check(sb != null and sb.get_length() <= 0.2, "저장고: 짧은 톡(%.2f초)" % (sb.get_length() if sb != null else -1.0))


## ② 노드: 설정값, 최소 간격, 같은 소리를 쓰는 종류, 소리 없는 종류, 몰림, 꺼짐, 한 묶음에 하나
func _node(t) -> void:
	var snd := LabSound.new()
	t.root.add_child(snd)
	await t.frames(1)
	t.check(snd.player_count() == UiConfig.integer("sound.players"), "재생기 %d개(ui.sound.players)" % snd.player_count())
	t.check(snd.enabled == bool(UiConfig.value("sound.enabled", true)), "enabled = ui.sound.enabled")
	var vol_ok := is_equal_approx(snd.volume_db, UiConfig.num("sound.volume_db"))
	for p in snd.get_children():
		if p is AudioStreamPlayer and not is_equal_approx((p as AudioStreamPlayer).volume_db, snd.volume_db):
			vol_ok = false
	t.check(vol_ok, "음량 = ui.sound.volume_db(모든 재생기)")
	var gap := UiConfig.num("sound.min_interval_s")
	t.check(gap > 0.0, "최소 간격 %.2f초" % gap)
	snd.stop_all()
	t.check(snd.play_event_at("discovery", T0) and snd.plays == 1 and snd.last_sound == "discovery" and _active(snd, "discovery") == 1
			and _playing(snd) == 1, "발견 → 소리(재생기 하나가 발견 파형을 재생)")
	snd.stop_all()
	t.check(not snd.play_event_at("discovery", T0 + gap * 0.5) and _playing(snd) == 0, "최소 간격 안의 같은 소리는 안 냄(재생기 조용)")
	t.check(snd.play_event_at("store_built", T0 + gap * 0.5) and _active(snd, "store_built") == 1 and _playing(snd) == 1, "다른 소리(저장고)는 냄")
	snd.stop_all()
	t.check(not snd.play_event_at("first_farm", T0 + gap * 0.6) and _playing(snd) == 0, "첫 밭은 저장고와 같은 소리 → 간격 안이라 안 냄")
	t.check(snd.play_event_at("discovery", T0 + gap) and _active(snd, "discovery") == 1, "간격이 지나면 다시 냄")
	snd.stop_all()
	t.check(not snd.play_event_at("milestone", T0 + 10.0) and not snd.play_event_at("farm_lost", T0 + 10.0) and not snd.play_event_at("", T0 + 10.0)
			and _playing(snd) == 0, "세대·밭 잃음·없는 종류는 소리 없음(재생기 조용)")
	t.check(snd.play_event_at("extinction", T0 + 10.0) and snd.last_sound == "extinction" and _active(snd, "extinction") == 1, "멸종 → 소리(멸종 파형)")
	snd.stop_all()
	t.check(snd.play_event_at("first_farm", T0 + 12.0) and snd.last_sound == "store_built" and _active(snd, "store_built") == 1, "첫 밭 → 저장고 파형")
	# 빨리 감기처럼 1초에 100번
	snd.stop_all()
	var before := snd.plays
	for i in BURST:
		snd.play_event_at("discovery", T0 + 20.0 + float(i) / float(BURST))
	var want := int(floorf((1.0 - 1.0 / float(BURST)) / gap)) + 1
	t.check(snd.plays - before == want and _active(snd, "discovery") == mini(want, snd.player_count()),
			"1초에 사건 %d번 → 소리 %d번만(최소 간격), 재생 중 %d" % [BURST, snd.plays - before, _active(snd, "discovery")])
	# 꺼짐: 내던 소리도 멈춤
	snd.enabled = false
	var p0 := snd.plays
	t.check(_playing(snd) == 0, "끄면 내던 소리도 멈춤")
	t.check(not snd.play_event_at("extinction", T0 + 100.0) and snd.plays == p0 and _playing(snd) == 0, "꺼지면 안 냄")
	snd.enabled = true
	t.check(snd.play_event_at("extinction", T0 + 100.0) and _active(snd, "extinction") == 1, "다시 켜면 냄")
	snd.volume_db = -20.0
	var vol2 := true
	for p in snd.get_children():
		if p is AudioStreamPlayer and not is_equal_approx((p as AudioStreamPlayer).volume_db, -20.0):
			vol2 = false
	t.check(vol2, "volume_db 를 바꾸면 모든 재생기에")
	snd.queue_free()
	# 한 묶음에 하나(멸종 > 발견 > 저장고) — 실제 시계를 쓰므로 새 노드
	var s2 := LabSound.new()
	t.root.add_child(s2)
	await t.frames(1)
	t.check(s2.play_events([{kind = "store_built"}, {kind = "discovery"}, {kind = "farm_lost"}]) and s2.plays == 1 and s2.last_sound == "discovery"
			and _active(s2, "discovery") == 1 and _playing(s2) == 1, "묶음에서 가장 중요한 소리 하나(발견 — 재생기도 하나)")
	s2.stop_all()
	t.check(s2.play_events([{kind = "discovery"}, {kind = "extinction"}]) and s2.last_sound == "extinction" and s2.plays == 2 and _active(s2, "extinction") == 1
			and _playing(s2) == 1, "멸종이 발견보다 먼저")
	s2.stop_all()
	t.check(not s2.play_events([{kind = "milestone"}, {kind = "farm_lost"}]) and not s2.play_events([]) and s2.plays == 2 and _playing(s2) == 0, "소리 없는 묶음")
	s2.queue_free()
	# 트리 밖이면 낼 수 없음
	var s3 := LabSound.new()
	t.check(not s3.play_event_at("discovery", T0), "트리 밖이면 false")
	s3.free()
	await t.frames(1)


## ③ 실험실 연결: 실험실이 _ready 에서 붙인 **자기** LabSound(bind_lab 을 빼먹으면 실패)가 events_tagged(A·B) 를 프레임 끝에
## 한 묶음으로 모아 소리 하나(비교 모드에서 A 멸종 + B 발견이 한 프레임에 와도 하나 — 멸종), 실제 진행의 사건, 역사 해시 그대로.
func _with_lab(t) -> void:
	var lab: LabMain = load("res://scenes/lab.tscn").instantiate()
	t.root.add_child(lab)
	await t.frames(1)
	lab.set_process(false)
	lab.set_paused(true)
	var snd := lab.lab_sound
	t.check(snd != null and lab.events_tagged.is_connected(snd._on_events), "실험실의 LabSound 가 events_tagged 에 붙어 있음")
	if snd == null:
		return
	snd.enabled = true
	snd.reset_rate_limit()
	snd.stop_all()
	var p0 := snd.plays
	lab.events_tagged.emit(0, [_ev("discovery")])
	await t.frames(1)
	t.check(snd.plays == p0 + 1 and snd.last_sound == "discovery" and _active(snd, "discovery") == 1, "events_tagged(A) → 실험실의 LabSound 가 발견 소리")
	snd.stop_all()
	lab.events_tagged.emit(1, [_ev("extinction")])
	await t.frames(1)
	t.check(snd.plays == p0 + 2 and snd.last_sound == "extinction" and _active(snd, "extinction") == 1, "events_tagged(B) → 멸종 소리")
	# 한 프레임에 A·B 묶음 둘(비교 모드): 소리 하나, 더 중요한 것(멸종)
	snd.reset_rate_limit()
	snd.stop_all()
	lab.events_tagged.emit(0, [_ev("discovery")])
	lab.events_tagged.emit(1, [_ev("extinction"), _ev("store_built")])
	await t.frames(1)
	t.check(snd.plays == p0 + 3 and snd.last_sound == "extinction" and _playing(snd) == 1 and _active(snd, "extinction") == 1,
			"한 프레임에 A 발견 + B 멸종 → 소리 하나(멸종, 재생 중 %d)" % _playing(snd))
	# 다시 붙여도(두 번) 한 번씩
	snd.bind_lab(lab)
	snd.bind_lab(lab)
	snd.reset_rate_limit()
	snd.stop_all()
	lab.events_tagged.emit(0, [_ev("discovery")])
	await t.frames(1)
	t.check(snd.plays == p0 + 4 and _playing(snd) == 1, "두 번 붙여도 사건 한 묶음에 소리 한 번")
	# 실제 진행: demo_fast 씨앗 2 는 100틱 안팎에 채집 발견
	t.check(lab.new_experiment("demo_fast", {}, 2) == "", "새 실험")
	# 위에서 낸 발견 소리의 최소 간격(실제 시계 0.5초)이 빠른 기계에서는 아직 안 지나 다음 발견 소리를 막는다 — 비우고 잰다
	snd.reset_rate_limit()
	snd.stop_all()
	var p1 := snd.plays
	lab.step_ticks(130)
	lab.advance_frame(DT)
	await t.frames(1)
	var kinds := {}
	for e: Dictionary in lab.world.chronicle:
		kinds[e.kind] = true
	t.check(kinds.has("discovery") and snd.plays == p1 + 1 and _active(snd, "discovery") == 1, "진행 중 사건 묶음 → 소리 한 번(%s)" % [kinds.keys()])
	var ref: SimWorld = t.make_world({}, 2, "demo_fast")
	ref.step_n(lab.world.tick)
	t.check(t.same_state(lab.world, ref) == "", "소리가 붙어도 상태가 헤드리스와 같음")
	lab.queue_free()
	await t.frames(1)
	await t.root.get_tree().create_timer(DRAIN_S).timeout


## 시험 사건 하나
static func _ev(kind: String) -> Dictionary:
	return {tick = 1, kind = kind, actor = -1, text = "검사", mean_gen = 0.0}


## 재생 중인 재생기 수
static func _playing(snd: LabSound) -> int:
	var n := 0
	for p in snd.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).playing:
			n += 1
	return n


## 그 소리(LabSound 가 만들어 둔 파형)를 재생 중인 재생기 수
static func _active(snd: LabSound, sound: String) -> int:
	var want := snd._stream(sound)
	var n := 0
	for p in snd.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).playing and (p as AudioStreamPlayer).stream == want:
			n += 1
	return n


## 부호가 바뀐 횟수(영점 교차, [a, b) 구간)
func _crossings(f: PackedFloat32Array, a: int, b: int) -> float:
	var c := 0
	var prev := 0.0
	for i in range(a, mini(b, f.size())):
		var v := f[i]
		if v != 0.0:
			if prev != 0.0 and signf(v) != signf(prev):
				c += 1
			prev = v
	return float(c)
