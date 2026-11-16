extends GdUnitTestSuite

# a cada 2 tentativas jogadas o aventureiro volta com 1 de vida máxima a mais; os mortos-vivos não ganham isso

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func after_test() -> void:
	RunState.reset()


func _knight_on_attempt(attempt: int) -> Adventurer:
	RunState.attempt = attempt
	return arena.spawn(TestArena.KNIGHT, Vector3(attempt * 3.0, 0, 0)) as Adventurer


func test_the_first_two_attempts_have_no_bonus() -> void:
	assert_float(_knight_on_attempt(1).get_max_health()).is_equal(10.0)
	assert_float(_knight_on_attempt(2).get_max_health()).is_equal(10.0)


func test_every_two_attempts_add_one_max_health() -> void:
	assert_float(_knight_on_attempt(3).get_max_health()).is_equal(11.0)
	assert_float(_knight_on_attempt(4).get_max_health()).is_equal(11.0)
	assert_float(_knight_on_attempt(5).get_max_health()).is_equal(12.0)


func test_the_adventurer_starts_the_attempt_with_the_full_new_health() -> void:
	assert_float(_knight_on_attempt(3).health).is_equal(11.0)


func test_the_undead_do_not_get_the_bonus() -> void:
	RunState.attempt = 5
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 6))

	assert_float(skeleton.get_max_health()).is_equal(5.0)
