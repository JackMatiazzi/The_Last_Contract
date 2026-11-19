extends Node3D
## O Lorde é dois modelos no mesmo lugar, com o mesmo esqueleto de animação: o humano e o morto-vivo.
## A metade de ossos repete a animação da metade humana.

@onready var _flesh: AnimationPlayer = $AnimationPlayer
@onready var _bones: AnimationPlayer = $Bones/AnimationPlayer


func _ready() -> void:
	_flesh.current_animation_changed.connect(_bones.play)
	_bones.play(_flesh.current_animation if not _flesh.current_animation.is_empty() else &"Idle")
