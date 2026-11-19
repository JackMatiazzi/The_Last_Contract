extends GdUnitTestSuite

# a cada 2 tentativas jogadas o aventureiro volta recebendo 10% menos dano; os mortos-vivos não ganham isso

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func after_test() -> void:
	RunState.reset()


func _knight_on_attempt(attempt: int) -> Adventurer:
	RunState.attempt = attempt
	return arena.spawn(TestArena.KNIGHT, Vector3(attempt * 3.0, 0, 0)) as Adventurer


func test_the_first_two_attempts_have_no_protection() -> void:
	assert_float(_knight_on_attempt(1).get_damage_taken_factor()).is_equal(1.0)
	assert_float(_knight_on_attempt(2).get_damage_taken_factor()).is_equal(1.0)


func test_every_two_attempts_cut_a_tenth_of_the_damage() -> void:
	assert_float(_knight_on_attempt(3).get_damage_taken_factor()).is_equal_approx(0.9, 0.001)
	assert_float(_knight_on_attempt(4).get_damage_taken_factor()).is_equal_approx(0.9, 0.001)
	assert_float(_knight_on_attempt(5).get_damage_taken_factor()).is_equal_approx(0.8, 0.001)


func test_max_health_stays_the_same() -> void:
	assert_float(_knight_on_attempt(5).get_max_health()).is_equal(10.0)


func test_an_enemy_hit_takes_less_on_later_attempts() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 6))
	var knight := _knight_on_attempt(5)

	knight.take_damage(1.0, skeleton)

	assert_float(knight.health).is_equal_approx(10.0 - 0.8, 0.001)


func test_the_undead_do_not_get_the_protection() -> void:
	RunState.attempt = 5
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 6))

	assert_float(skeleton.get_damage_taken_factor()).is_equal(1.0)
