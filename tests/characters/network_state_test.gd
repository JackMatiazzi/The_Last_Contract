extends GdUnitTestSuite

# personagem parado nao gasta rede: a sala online cobra por mensagem e a maior parte da partida e espera

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func test_standing_still_has_nothing_new_to_send() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	await arena.wait_physics(3)
	knight._remember_net_state()

	await arena.wait_physics(5)

	assert_bool(knight.has_new_net_state()).is_false()


func test_moving_turning_or_falling_is_new() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	await arena.wait_physics(3)
	knight._remember_net_state()

	knight.global_position += Vector3(0.5, 0.0, 0.0)
	assert_bool(knight.has_new_net_state()).is_true()

	knight._remember_net_state()
	knight.model.rotation.y += 0.5
	assert_bool(knight.has_new_net_state()).is_true()

	knight._remember_net_state()
	knight.velocity = Vector3(0.0, -3.0, 0.0)
	assert_bool(knight.has_new_net_state()).is_true()


func test_nothing_sent_yet_is_always_new() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	await arena.wait_physics(3)

	assert_bool(knight.has_new_net_state()).is_true()
