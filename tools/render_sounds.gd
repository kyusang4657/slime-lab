extends SceneTree
## 합성 효과음을 WAV 파일로 써서 들어 보기(결과 파일은 저장소에 넣지 않음):
##   godot --headless --path . --script res://tools/render_sounds.gd -- --out=폴더
## LabSound.synth() 와 같은 소리(ui.json 의 sound 절)를 소리마다 <이름>.wav 로 쓰고 길이·최댓값·처음/끝 샘플을 출력한다.
## 인자: --out=폴더(기본 user://sounds)

var _out := "user://sounds"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)
	var failed := 0
	for s in LabSound.SOUNDS:
		var w := LabSound.synth(s)
		if w == null:
			printerr("소리를 만들 수 없음: " + s)
			failed += 1
			continue
		var n := w.data.size() / 2
		var peak := 0
		for i in n:
			peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
		var path := dir.path_join(s + ".wav")
		var err := w.save_to_wav(path)
		print("%s  %.3f초  %d Hz  최댓값 %.3f FS  처음 %d · 끝 %d  → %s%s" % [s, float(n) / float(w.mix_rate), w.mix_rate,
				float(peak) / LabSound.PCM_MAX, w.data.decode_s16(0), w.data.decode_s16((n - 1) * 2), path,
				"" if err == OK else " (저장 실패 %d)" % err])
		if err != OK:
			failed += 1
	quit(1 if failed > 0 else 0)
