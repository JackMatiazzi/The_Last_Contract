extends GdUnitTestSuite

# o esqueleto nasce olhando para +Z

var arena: TestArena
var skeleton: Enemy


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)
	skeleton = arena.spawn(TestArena.SKELETON, Vector3.ZERO)
	skeleton.ai_enabled = false


func after_test() -> void:
	Input.action_release("move_forward")


func _sense_with_player_at(position: Vector3) -> Adventurer:
	var player := arena.spawn(TestArena.KNIGHT, position) as Adventurer
	await arena.wait_physics(3)
	skeleton.perception.sense(0.1)
	return player


func test_sees_player_in_front_within_range() -> void:
	await _sense_with_player_at(Vector3(0, 0, 8))

	assert_bool(skeleton.perception.can_see).is_true()


func test_does_not_see_player_behind() -> void:
	await _sense_with_player_at(Vector3(0, 0, -6))

	assert_bool(skeleton.perception.can_see).is_false()


func test_does_not_see_player_beyond_sight_range() -> void:
	await _sense_with_player_at(Vector3(0, 0, skeleton.profile.sight_range + 2.0))

	assert_bool(skeleton.perception.can_see).is_false()


func test_walls_block_sight() -> void:
	arena.add_wall(Vector3(0, 1, 4), Vector3(4, 3, 0.4))
	await _sense_with_player_at(Vector3(0, 0, 8))

	assert_bool(skeleton.perception.can_see).is_false()


func test_hears_running_player_behind() -> void:
	var player := await _sense_with_player_at(Vector3(0, 0, -3))
	player.velocity = Vector3(0, 0, player.run_speed)

	skeleton.perception.sense(0.1)

	assert_bool(skeleton.perception.is_aware()).is_true()


func test_does_not_hear_player_standing_still_behind() -> void:
	await _sense_with_player_at(Vector3(0, 0, -3))

	assert_bool(skeleton.perception.is_aware()).is_false()


func test_notices_player_standing_right_behind() -> void:
	await _sense_with_player_at(Vector3(0, 0, -(skeleton.profile.proximity_range - 0.5)))

	assert_bool(skeleton.perception.is_aware()).is_true()


func test_does_not_notice_close_player_through_a_wall() -> void:
	arena.add_wall(Vector3(0, 1, -1.0), Vector3(4, 3, 0.3))
	await _sense_with_player_at(Vector3(0, 0, -(skeleton.profile.proximity_range - 0.5)))

	assert_bool(skeleton.perception.is_aware()).is_false()


func test_remembers_last_seen_position_for_a_while() -> void:
	var player := await _sense_with_player_at(Vector3(0, 0, 8))
	var seen_at := player.global_position
	player.global_position = Vector3(0, 0, -20)
	await arena.wait_physics(2)

	skeleton.perception.sense(skeleton.profile.memory_time * 0.5)

	assert_bool(skeleton.perception.can_see).is_false()
	assert_bool(skeleton.perception.is_aware()).is_true()
	assert_vector(skeleton.perception.last_known_position).is_equal_approx(seen_at, Vector3.ONE * 0.05)


func test_forgets_after_memory_time() -> void:
	var player := await _sense_with_player_at(Vector3(0, 0, 8))
	player.global_position = Vector3(0, 0, -20)
	await arena.wait_physics(2)

	skeleton.perception.sense(skeleton.profile.memory_time + 0.1)

	assert_bool(skeleton.perception.is_aware()).is_false()


func test_dead_player_is_not_a_target() -> void:
	var player := await _sense_with_player_at(Vector3(0, 0, 8))
	player.take_damage(99.0)

	skeleton.perception.sense(0.1)

	assert_bool(skeleton.perception.can_see).is_false()


# em grupo: ir no mais perto, mas sem ficar trocando por diferença pequena, e responder a quem bate

func _two_players(first_z: float, second_z: float) -> Array[Adventurer]:
	var first := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, first_z)) as Adventurer
	await arena.wait_physics(3)
	skeleton.perception.sense(0.1)
	var second := arena.spawn(TestArena.KNIGHT, Vector3(1.5, 0, second_z)) as Adventurer
	await arena.wait_physics(3)
	skeleton.perception.sense(0.1)
	return [first, second]


func test_switches_to_a_player_that_gets_much_closer() -> void:
	var players := await _two_players(12.0, 2.0)

	assert_object(skeleton.perception.target).is_same(players[1])


func test_keeps_the_target_when_the_other_is_only_a_little_closer() -> void:
	var players := await _two_players(6.0, 5.0)

	assert_object(skeleton.perception.target).is_same(players[0])


func test_whoever_hits_it_becomes_the_target_even_from_farther() -> void:
	var players := await _two_players(2.0, 10.0)

	skeleton.take_damage(1.0, players[1])
	skeleton.perception.sense(0.1)

	assert_object(skeleton.perception.target).is_same(players[1])


func test_after_a_while_without_being_hit_it_goes_back_to_the_closest() -> void:
	var players := await _two_players(2.0, 10.0)
	skeleton.take_damage(1.0, players[1])

	skeleton.perception.sense(Perception.PROVOKED_TIME + 0.1)

	assert_object(skeleton.perception.target).is_same(players[0])
