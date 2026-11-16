extends EnemyState

const THROW_FACING_TOLERANCE := 25.0


func think(_delta: float) -> void:
	var perception := enemy.perception
	if perception.target == null or perception.target.is_dead:
		brain.change_state("Idle")
		return
	if not perception.is_aware():
		brain.change_state("Investigate")
		return
	var distance := perception.distance_to_target() if perception.can_see else INF
	if distance <= enemy.profile.attack_range:
		brain.change_state("Attack")
		return
	if enemy.can_throw_at(distance):
		_throw_at(perception.target.global_position)
		return
	var destination := perception.last_known_position
	var far := enemy.global_position.distance_to(destination) > enemy.profile.chase_run_distance
	brain.move_to(destination, far)
	brain.clear_look()


# para, vira para o alvo e arremessa; enquanto vira, não sai do lugar
func _throw_at(target_position: Vector3) -> void:
	brain.stop_moving()
	brain.look_at_point(target_position)
	if enemy.is_facing(target_position, THROW_FACING_TOLERANCE):
		enemy.throw_attack.try_attack(enemy)


func exit() -> void:
	brain.stop_moving()
