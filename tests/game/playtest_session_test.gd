extends GdUnitTestSuite

const GAMEPLAY := preload("res://scenes/test/movement_test.tscn")
const TEST_DIR := "user://playtest_session_test"


func before_test() -> void:
	RunState.reset()
	Playtest.enabled = true
	Playtest.directory = TEST_DIR


func after_test() -> void:
	Playtest.finish("teste")
	Playtest.enabled = false
	Playtest.directory = Playtest.DIR
	RunState.adventurer = null
	RunState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for file in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_DIR)


func _start_game() -> GameSession:
	RunState.adventurer = load("res://resources/adventurers/rogue.tres")
	var game: Node = auto_free(GAMEPLAY.instantiate())
	add_child(game)
	await await_idle_frame()
	return game.get_node("GameSession")


func _events() -> Array:
	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Playtest.last_path))
	return run["events"]


func test_first_attempt_opens_a_run_with_the_chosen_adventurer() -> void:
	await _start_game()

	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Playtest.last_path))
	assert_str(run["adventurer"]).is_equal("Rogue")
	assert_int(int(run["players"])).is_equal(1)
	assert_str(_events()[0]["type"]).is_equal("attempt_started")


func test_death_is_logged_with_where_it_happened() -> void:
	var session := await _start_game()

	session.player.take_damage(999.0)

	var death: Dictionary = _events().filter(func(event: Dictionary) -> bool: return event["type"] == "player_died").front()
	assert_int(death["position"].size()).is_equal(3)
	assert_str(death["recap"]).is_not_empty()


func test_later_attempts_keep_writing_to_the_same_run() -> void:
	await _start_game()
	var first := Playtest.last_path
	RunState.attempt = 2

	await _start_game()

	assert_str(Playtest.last_path).is_equal(first)
	var attempts := _events().filter(func(event: Dictionary) -> bool: return event["type"] == "attempt_started")
	assert_int(attempts.size()).is_equal(2)
	assert_int(int(attempts[1]["attempt"])).is_equal(2)


func _event(kind: String) -> Dictionary:
	var found := _events().filter(func(event: Dictionary) -> bool: return event["type"] == kind)
	return found.front() if not found.is_empty() else {}


func test_death_says_who_killed_and_in_which_stage() -> void:
	var session := await _start_game()
	var skeleton := session.get_parent().get_node("TestDummy") as Character

	session.player.take_damage(999.0, skeleton)

	var death := _event("player_died")
	assert_str(death["enemy"]).is_equal(skeleton.get_display_name())
	assert_str(death["stage"]).is_not_empty()
	assert_str(death["hits"][-1][0]).is_equal(skeleton.get_display_name())
	assert_float(death["taken"]).is_greater(0.0)


func test_the_fallen_boss_and_the_trapdoor_are_logged() -> void:
	var session := await _start_game()
	session.boss = session.get_parent().get_node("TestDummy") as Enemy

	session._on_boss_died()

	assert_dict(_event("boss_killed")).is_not_empty()
	assert_dict(_event("trapdoor_opened")).is_not_empty()


func test_letting_the_trapdoor_close_is_logged() -> void:
	var session := await _start_game()
	session.trapdoor_time = 0.2
	session.open_trapdoor_at(session.player.global_position + Vector3(4, 0, 0))

	await get_tree().create_timer(0.6).timeout

	assert_dict(_event("trapdoor_expired")).is_not_empty()
