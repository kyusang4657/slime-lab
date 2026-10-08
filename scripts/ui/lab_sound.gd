class_name LabSound
extends Node
## 합성 효과음(발견·멸종·저장고). 계약: docs/VIEW-API.md "LabSound".
##
## 음원 파일 없이 실행 중에 파형을 만든다: 음마다 사인 + 약한 배음(ui.sound.<소리>.harmonics), 짧은 올림(attack) 뒤
## 지수 감쇠, 음높이는 hz → hz_end 로 지수 미끄럼. 소리 전체는 0 에서 시작해(fade_s) 끝의 release_s 동안 0 으로 내려가
## 처음·끝 샘플이 0(딸깍 소리 없음), 가장 큰 값을 peak(≤ MAX_PEAK)로 맞춘 16비트 모노 AudioStreamWAV.
## 같은 설정이면 언제나 같은 바이트(난수 없음). 만든 소리는 CC0 로 CREDITS 에.
##   발견(discovery)    = 위로 오르는 세 음 차임(밝은 장조)
##   멸종(extinction)   = 낮게 내려가는 긴 음
##   저장고(store_built) = 짧고 부드러운 "톡"(첫 밭 first_farm 도 같은 소리)
## 같은 소리는 ui.sound.min_interval_s 안에 다시 내지 않는다(빨리 감기에서 사건이 몰려도 시끄럽지 않게).
## 한 묶음(한 프레임의 사건)에서는 가장 중요한 소리 하나만 낸다(멸종 > 발견 > 저장고).

## 사건 종류 → 소리 이름(없는 종류는 소리 없음: 밭 잃음·세대 이정표는 자주 나서 조용히)
const SOUND_OF := {"discovery": "discovery", "extinction": "extinction", "store_built": "store_built", "first_farm": "store_built"}
## 한 묶음에서 고르는 순서(앞이 중요)
const PRIORITY: Array[String] = ["extinction", "discovery", "store_built"]
## 소리 이름(ui.sound 의 절 이름)
const SOUNDS: Array[String] = ["discovery", "extinction", "store_built"]
## 16비트 최댓값, 정규화 상한(설정의 peak 가 이보다 커도 이것으로 자름)
const PCM_MAX := 32767.0
const MAX_PEAK := 0.8
## 감쇠한 음이 이보다 작아지면 그 음은 더 셈하지 않음
const SILENT := 1.0e-5

## 켜고 끔(ui.sound.enabled). 끄면 내던 소리도 멈춘다.
var enabled := true:
	set(v):
		enabled = v
		if not v:
			stop_all()
## 음량(dB, ui.sound.volume_db). 모든 재생기에 넣는다.
var volume_db := -8.0:
	set(v):
		volume_db = v
		for p in _players:
			p.volume_db = v
## 실제로 낸 소리 수(검사용)
var plays := 0
## 마지막으로 낸 소리 이름(검사용, 없으면 "")
var last_sound := ""

var _lab: LabMain
var _players: Array[AudioStreamPlayer] = []
var _streams := {}
# 소리 이름 → 마지막으로 낸 시각(초)
var _last := {}
var _min_interval := 0.5
var _next := 0


func _init() -> void:
	_min_interval = maxf(0.0, UiConfig.num("sound.min_interval_s"))
	for i in maxi(1, UiConfig.integer("sound.players")):
		var p := AudioStreamPlayer.new()
		p.name = "Player%d" % i
		_players.append(p)
		add_child(p)
	volume_db = UiConfig.num("sound.volume_db")
	enabled = bool(UiConfig.value("sound.enabled", true))


func _ready() -> void:
	# 처음 사건 때 멈칫하지 않게 미리 만든다(세 소리 합쳐 약 2초 분량)
	for s in SOUNDS:
		_stream(s)


# 실험실을 닫을 때 내던 소리를 멈춘다(오디오 서버가 재생을 붙든 채 끝나지 않게)
func _exit_tree() -> void:
	stop_all()


## 실험실에 붙인다: events_tagged(어느 실험이든) → 그 묶음에서 가장 중요한 소리 하나.
func bind_lab(lab: LabMain) -> void:
	if _lab != null and _lab.events_tagged.is_connected(_on_events):
		_lab.events_tagged.disconnect(_on_events)
	_lab = lab
	if lab != null:
		lab.events_tagged.connect(_on_events)


func _on_events(_index: int, list: Array) -> void:
	play_events(list)


## 사건 묶음에서 가장 중요한 소리 하나를 낸다(PRIORITY 순). 냈으면 true.
func play_events(list: Array) -> bool:
	var have := {}
	for e in list:
		if typeof(e) == TYPE_DICTIONARY:
			var s := str(SOUND_OF.get(str((e as Dictionary).get("kind", "")), ""))
			if s != "":
				have[s] = str((e as Dictionary).get("kind", ""))
	for s in PRIORITY:
		if have.has(s):
			return play_event(str(have[s]))
	return false


## 사건 종류에 맞는 소리를 낸다(없는 종류·꺼짐·최소 간격 안·트리 밖이면 아무것도 안 함). 실제로 냈으면 true.
func play_event(kind: String) -> bool:
	return play_event_at(kind, float(Time.get_ticks_msec()) / 1000.0)


## play_event 와 같되 지금 시각(초)을 받는다(검사가 최소 간격을 시계 없이 확인).
func play_event_at(kind: String, now_s: float) -> bool:
	if not enabled:
		return false
	var s := str(SOUND_OF.get(kind, ""))
	if s == "" or not is_inside_tree():
		return false
	if _last.has(s) and now_s - float(_last[s]) < _min_interval:
		return false
	var stream := _stream(s)
	if stream == null:
		return false
	# 쉬는 재생기, 모두 바쁘면 차례로 가장 오래 전에 시작한 것
	var p: AudioStreamPlayer = null
	for q in _players:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _players[_next % _players.size()]
		_next += 1
	p.stream = stream
	p.volume_db = volume_db
	p.play()
	_last[s] = now_s
	plays += 1
	last_sound = s
	return true


## 내던 소리를 모두 멈춘다.
func stop_all() -> void:
	for p in _players:
		if p.playing:
			p.stop()


## 재생기 수(검사용)
func player_count() -> int:
	return _players.size()


func _stream(s: String) -> AudioStreamWAV:
	if not _streams.has(s):
		_streams[s] = synth(s)
	return _streams[s]


# ════════════════════════════ 합성 ════════════════════════════

## 소리(SOUNDS 의 이름)를 16비트 모노 AudioStreamWAV 로 만든다(부를 때마다 새로, 같은 설정이면 같은 바이트). 없는 이름이면 null.
static func synth(sound: String) -> AudioStreamWAV:
	var buf := synth_samples(sound)
	if buf.is_empty():
		return null
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(roundf(clampf(buf[i], -1.0, 1.0) * PCM_MAX)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = false
	w.mix_rate = UiConfig.integer("sound.mix_rate")
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	w.data = data
	return w


## 소리의 샘플(−1~1, 가장 큰 값 = peak). 없는 이름이면 빈 배열.
## 설정 ui.sound.<소리> = {duration_s, peak, release_s, harmonics: [1배음, 2배음…], notes: [{t_s, hz, hz_end?, glide_s?, attack_s, decay_per_s}]}
static func synth_samples(sound: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var all := UiConfig.section("sound")
	if not SOUNDS.has(sound) or typeof(all.get(sound)) != TYPE_DICTIONARY:
		return out
	var cfg: Dictionary = all[sound]
	var rate := float(UiConfig.integer("sound.mix_rate"))
	var dur := float(cfg.get("duration_s", 0.5))
	var n := maxi(2, int(roundf(dur * rate)))
	var harm: Array[float] = []
	for h in cfg.get("harmonics", [1.0]):
		harm.append(float(h))
	var acc := PackedFloat64Array()
	acc.resize(n)
	for note: Dictionary in cfg.get("notes", []):
		_add_note(acc, rate, note, harm)
	# 소리 전체의 처음(fade_s)·끝(release_s) 덮개: 0 에서 시작해 0 으로 끝남(사인 제곱 곡선 — 기울기도 0 에서 시작)
	var fade_n := maxi(1, int(roundf(UiConfig.num("sound.fade_s") * rate)))
	var rel_n := clampi(int(roundf(float(cfg.get("release_s", 0.05)) * rate)), 1, n - 1)
	var peak := 0.0
	for i in n:
		var g := 1.0
		if i < fade_n:
			g = pow(sin(0.5 * PI * float(i) / float(fade_n)), 2.0)
		var from_end := n - 1 - i
		if from_end < rel_n:
			g *= pow(sin(0.5 * PI * float(from_end) / float(rel_n)), 2.0)
		acc[i] *= g
		peak = maxf(peak, absf(acc[i]))
	var want := clampf(float(cfg.get("peak", 0.6)), 0.0, MAX_PEAK)
	var k := want / peak if peak > 0.0 else 0.0
	out.resize(n)
	for i in n:
		out[i] = acc[i] * k
	return out


## 음 하나를 더한다: 시작 t_s, 음높이 hz → hz_end(glide_s 동안 지수 미끄럼), 올림 attack_s 뒤 exp(−decay_per_s·t).
## 위상을 샘플마다 쌓아(음높이가 바뀌어도 파형이 끊기지 않음) 배음 sin(2π·h·위상) 을 더한다.
static func _add_note(acc: PackedFloat64Array, rate: float, note: Dictionary, harm: Array[float]) -> void:
	var n := acc.size()
	var i0 := clampi(int(roundf(float(note.get("t_s", 0.0)) * rate)), 0, n)
	var hz0 := maxf(1.0, float(note.get("hz", 440.0)))
	var hz1 := maxf(1.0, float(note.get("hz_end", hz0)))
	var glide := maxf(1.0e-4, float(note.get("glide_s", 1.0)))
	var attack := maxf(1.0e-4, float(note.get("attack_s", 0.005)))
	var decay := maxf(0.0, float(note.get("decay_per_s", 4.0)))
	var ratio := hz1 / hz0
	var phase := 0.0
	for i in range(i0, n):
		var t := float(i - i0) / rate
		var env := minf(1.0, t / attack) * exp(-decay * t)
		if t > attack and env < SILENT:
			break
		var v := 0.0
		for h in harm.size():
			v += harm[h] * sin(TAU * float(h + 1) * phase)
		acc[i] += env * v
		var hz := hz0 * pow(ratio, minf(1.0, t / glide))
		phase = fposmod(phase + hz / rate, 1.0)
