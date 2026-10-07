class_name BrainView
extends Control
## (뼈대) 두뇌 가중치 열지도. 계약: docs/VIEW-API.md "BrainView".

var _L: Dictionary = {}
var _genome := PackedFloat32Array()


func set_genome(L: Dictionary, genome: PackedFloat32Array) -> void:
	_L = L
	_genome = genome
	queue_redraw()
