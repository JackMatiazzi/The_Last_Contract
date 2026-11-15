extends GdUnitTestSuite

# epílogo da vitória: de volta à vila, o Lorde lê os nomes e avisa que o grupo será a próxima leva

const EPILOGUE := preload("res://scenes/cutscenes/victory_epilogue.tscn")

var scene: AdventurerCutscene


func before_test() -> void:
	RunState.reset()
	RunState.adventurer = load("res://resources/adventurers/knight.tres")
	scene = auto_free(EPILOGUE.instantiate()) as AdventurerCutscene
	scene.next_scene = ""
	add_child(scene)
	await await_idle_frame()


func after_test() -> void:
	RunState.adventurer = null
	RunState.reset()


func _caption() -> String:
	return (scene.get_node("UI/Caption") as Label).text


func test_the_lord_reads_the_names_and_admits_it_was_not_expected() -> void:
	scene.say(2)

	assert_str(_caption()).contains(Settings.player_name)
	assert_str(_caption()).contains("não achava possível")


func test_the_lord_orders_the_guards_to_take_them() -> void:
	scene.say(3)

	assert_str(_caption()).contains("Guardas")


func test_it_closes_with_the_lesson_about_contracts() -> void:
	scene.say(4)

	assert_str(_caption()).contains("O contrato foi cumprido")
	assert_str(_caption()).contains("índole do seu contratante")


func test_the_crowd_cheers_then_the_executioner_strikes_and_the_guards_drag_the_body() -> void:
	var fresh: AdventurerCutscene = auto_free(EPILOGUE.instantiate())
	var animation := (scene.get_node("Timeline") as AnimationPlayer).get_animation("epilogue")
	var paths: Array = range(animation.get_track_count()).map(func(track: int) -> String: return str(animation.track_get_path(track)))

	assert_str(fresh.next_scene).is_equal("res://scenes/ui/main_menu.tscn")
	assert_array(paths).contains(["Crowd/Villager/AnimationPlayer", "Guarda1:position", "Guarda2:position", "HeroSpot:position",
		"PublicSquare/Scaffold/Executioner/AnimationPlayer"])


func test_the_victory_screen_no_longer_promises_there_will_be_no_execution() -> void:
	var victory: VictoryScreen = auto_free((load("res://scenes/ui/victory_screen.tscn") as PackedScene).instantiate())
	add_child(victory)

	assert_str((victory.get_node("Center/Panel/Content/Lord") as Label).text).not_contains("não haverá execução")
	assert_str((victory.get_node("%MenuButton") as Button).text).is_equal("Voltar à vila")
	assert_bool(ResourceLoader.exists(GameSession.EPILOGUE)).is_true()
