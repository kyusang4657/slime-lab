class_name GraphPanel
extends HBoxContainer
## (뼈대) 그래프 3개(개체 수·평균 특성·기술 단계) — 아래 자리. 계약: docs/VIEW-API.md "GraphPanel".

var _lab: LabMain


func bind_lab(lab: LabMain) -> void:
	_lab = lab


## 그래프 수(3)
func graph_count() -> int:
	return 0
