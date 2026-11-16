extends Node3D
## gira o modelo em volta do próprio eixo, como um machado arremessado

@export var degrees_per_second := 900.0


func _process(delta: float) -> void:
	rotate_x(deg_to_rad(degrees_per_second) * delta)
