class_name Trapdoor
extends Interactable
## Deixado pelo Necromante; quem usar leva o grupo inteiro ao calabouço.

@export var session: GameSession

var is_open := true


func can_interact() -> bool:
	return is_open


func _use(_by: Adventurer) -> void:
	session.descend_to_bonus()


func close() -> void:
	is_open = false
	_release_player()
