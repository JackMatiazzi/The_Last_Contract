class_name MeleeAttack
extends Attack
## a hitbox atravessa parede, entao cada alvo precisa de linha livre ate o atacante

const WORLD_LAYER := 1
const CHEST_HEIGHT := 1.0
## alcance do golpe pesado contra barris e caixotes, a partir do centro da hitbox
const BREAK_RADIUS := 1.4

## vazio usa a mesma hitbox; o Barbarian troca o golpe a frente pelo giro em volta
@export var heavy_hitbox: Area3D

var _wall_query := PhysicsRayQueryParameters3D.new()

@onready var hitbox: Area3D = $Hitbox


func _ready() -> void:
	_wall_query.collision_mask = WORLD_LAYER


func _perform(attacker: Character, total_damage: float, heavy: bool) -> void:
	var strike := heavy_hitbox if heavy and heavy_hitbox else hitbox
	var landed := false
	for body in strike.get_overlapping_bodies():
		if body is Character and body != attacker and _has_clear_line(attacker, body):
			body.take_damage(total_damage, attacker)
			body.freeze_animation(Character.HITSTOP_HEAVY if heavy else Character.HITSTOP)
			landed = true
	if landed:
		attacker.on_hit_landed(heavy)
	for area in strike.get_overlapping_areas():
		if area is HealthPotion:
			area.shatter()
	if heavy:
		get_tree().call_group(BreakableProps.GROUP, "break_near", _strike_center(strike), BREAK_RADIUS)


func _has_clear_line(attacker: Character, target: Character) -> bool:
	_wall_query.from = attacker.global_position + Vector3.UP * CHEST_HEIGHT
	_wall_query.to = target.global_position + Vector3.UP * CHEST_HEIGHT
	return get_world_3d().direct_space_state.intersect_ray(_wall_query).is_empty()


# a origem da hitbox fica no atacante; quem esta deslocada para frente e a forma de colisao
func _strike_center(strike: Area3D) -> Vector3:
	for child in strike.get_children():
		if child is CollisionShape3D:
			return child.global_position
	return strike.global_position
