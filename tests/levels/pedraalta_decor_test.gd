extends GdUnitTestSuite

# a arena do chefe no mirante fica limpa: nem cadafalso nem carrasco largados ali

const MAP := preload("res://scenes/maps/pedraalta.tscn")


func test_the_boss_arena_has_no_scaffold_or_executioner() -> void:
	var map: Node3D = auto_free(MAP.instantiate())

	assert_object(map.get_node_or_null("Historia/F_Mirante/scaffold0")).is_null()
	assert_array(map.find_children("Executioner", "", true, false)).is_empty()


func test_the_execution_scene_keeps_its_executioner() -> void:
	var scaffold: Node3D = auto_free((load("res://scenes/props/scaffold.tscn") as PackedScene).instantiate())

	assert_bool((scaffold.get_node("Executioner") as Node3D).visible).is_true()
