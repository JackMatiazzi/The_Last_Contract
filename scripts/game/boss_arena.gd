class_name BossArena
extends StaticBody3D
## A colisão fecha o Mirante até o chefe surgir. O mesmo limite vale para portais e para o chefe.

const BOSS_MARGIN := 0.75

@onready var barrier: CollisionShape3D = $CollisionShape3D
@onready var cylinder := barrier.shape as CylinderShape3D

var locked := true


func unlock() -> void:
	locked = false
	barrier.set_deferred("disabled", true)
	$BarrierMesh.hide()


func contains(point: Vector3) -> bool:
	var local := to_local(point) - barrier.position
	return absf(local.y) <= cylinder.height * 0.5 and Vector2(local.x, local.z).length() <= cylinder.radius


func keep_boss_inside(boss: Enemy) -> void:
	if not is_instance_valid(boss) or boss.is_dead or not boss.is_multiplayer_authority():
		return
	var offset := (boss.global_position - global_position).slide(Vector3.UP)
	var limit := cylinder.radius - BOSS_MARGIN
	if offset.length_squared() <= limit * limit:
		return
	var outward := offset.normalized()
	var position_on_border := global_position + outward * limit
	position_on_border.y = boss.global_position.y
	boss.global_position = position_on_border
	boss.velocity -= outward * maxf(boss.velocity.dot(outward), 0.0)
	boss.reset_physics_interpolation()
