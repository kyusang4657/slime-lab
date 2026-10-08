class_name ParamPanel
extends VBoxContainer
## (뼈대) 파라미터 패널 — 왼쪽 자리. 계약: docs/VIEW-API.md "ParamPanel".

var _lab: LabMain


func bind_lab(lab: LabMain) -> void:
	_lab = lab


## 지금 패널에 적힌 조건 {preset, overrides, seed}. which = 0(A) / 1(B, 비교 모드 칸)
func current_settings(_which: int = 0) -> Dictionary:
	return {preset = str(UiConfig.value("lab.default_preset")), overrides = {}, seed = UiConfig.integer("lab.default_seed")}
