extends GdUnitTestSuite

# o cadafalso do mirante é decoração: o carrasco da execução não fica largado na arena do chefe

const MAP := preload("res://scenes/maps/pedraalta.tscn")


func test_the_scaffold_in_pedra_alta_has_no_executioner() -> void:
	var map: Node3D = auto_free(MAP.instantiate())

	var executioner := map.get_node("Historia/F_Mirante/scaffold0/Executioner") as Node3D

	assert_bool(executioner.visible).is_false()
	assert_int(executioner.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)


func test_the_execution_scene_keeps_its_executioner() -> void:
	var scaffold: Node3D = auto_free((load("res://scenes/props/scaffold.tscn") as PackedScene).instantiate())

	assert_bool((scaffold.get_node("Executioner") as Node3D).visible).is_true()
