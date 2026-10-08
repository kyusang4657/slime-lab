class_name LabSound
extends Node
## (뼈대) 합성 효과음(발견·멸종). 계약: docs/VIEW-API.md "LabSound".

var enabled := true
var _lab: LabMain


func bind_lab(lab: LabMain) -> void:
	_lab = lab


## 사건 종류에 맞는 소리를 낸다(없는 종류·꺼짐이면 아무것도 안 함). 실제로 냈으면 true.
func play_event(_kind: String) -> bool:
	return false
