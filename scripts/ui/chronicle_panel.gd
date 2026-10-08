class_name ChroniclePanel
extends VBoxContainer
## (뼈대) 연대기 — 아래 자리 오른쪽. 계약: docs/VIEW-API.md "ChroniclePanel".

var _lab: LabMain


func bind_lab(lab: LabMain) -> void:
	_lab = lab


## 지금 보이는 줄 수
func item_count() -> int:
	return 0
