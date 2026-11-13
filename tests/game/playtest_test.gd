extends GdUnitTestSuite

const TEST_DIR := "user://playtest_test"


func before_test() -> void:
	RunState.reset()
	Playtest.enabled = true
	Playtest.directory = TEST_DIR


func after_test() -> void:
	Playtest.finish("teste")
	Playtest.enabled = false
	Playtest.directory = Playtest.DIR
	for file in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_DIR)


func _saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Playtest.last_path))


func test_disabled_log_writes_nothing() -> void:
	Playtest.enabled = false

	Playtest.start_run("Mage", 1, "PedraaltaLevel")
	Playtest.record("player_died")

	assert_bool(Playtest.is_running()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(TEST_DIR)).is_false()


func test_run_is_saved_on_every_event() -> void:
	Playtest.start_run("Mage", 1, "PedraaltaLevel")
	Playtest.record("group_cleared", {"groups_left": 4})

	var run := _saved()
	assert_str(run["adventurer"]).is_equal("Mage")
	assert_str(run["level"]).is_equal("PedraaltaLevel")
	assert_int(run["events"].size()).is_equal(1)
	assert_str(run["events"][0]["type"]).is_equal("group_cleared")
	assert_int(int(run["events"][0]["groups_left"])).is_equal(4)


func test_events_carry_the_attempt() -> void:
	Playtest.start_run("Knight", 1, "PedraaltaLevel")
	Playtest.record("player_died")
	RunState.attempt = 2
	Playtest.record("attempt_started")

	var events: Array = _saved()["events"]
	assert_int(int(events[0]["attempt"])).is_equal(1)
	assert_int(int(events[1]["attempt"])).is_equal(2)


func test_finish_closes_the_file_with_the_result() -> void:
	Playtest.start_run("Rogue", 2, "VillageLevel")
	var path := Playtest.last_path

	Playtest.finish("victory")
	Playtest.record("ignored_after_finish")

	var run: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(Playtest.is_running()).is_false()
	assert_str(run["result"]).is_equal("victory")
	assert_bool(run.has("duration")).is_true()
	assert_str(run["events"].back()["type"]).is_equal("victory")


func test_each_contract_gets_its_own_file() -> void:
	Playtest.start_run("Mage", 1, "PedraaltaLevel")
	var first := Playtest.last_path
	var first_msec := Time.get_ticks_msec()
	Playtest.finish("gave_up")
	# o nome do arquivo usa o milissegundo do relógio real; um timer da engine pode disparar antes dele mudar
	while Time.get_ticks_msec() <= first_msec:
		await get_tree().process_frame

	Playtest.start_run("Mage", 1, "PedraaltaLevel")

	assert_str(Playtest.last_path).is_not_equal(first)
	assert_bool(FileAccess.file_exists(first)).is_true()
