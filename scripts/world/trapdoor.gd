class_name Trapdoor
extends Interactable
## Deixado pelo Necromante; quem usar leva o grupo inteiro ao calabouço.

const LID_CLOSE_TIME := 0.6

@export var session: GameSession
## a tampa abre para cima ao ser deixada; quando o prazo acaba, ela desce e o alçapão fecha
@export var lid: Node3D

var is_open := true


func can_interact() -> bool:
	return is_open


func _use(_by: Adventurer) -> void:
	session.descend_to_bonus()


func close() -> void:
	is_open = false
	_release_player()
	if lid:
		create_tween().tween_property(lid, "rotation:x", 0.0, LID_CLOSE_TIME)
