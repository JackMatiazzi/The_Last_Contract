extends GdUnitTestSuite

# o Lorde é meio humano e meio esqueleto: o grupo foi enganado desde o começo

const LORD := preload("res://scenes/cutscenes/lord.tscn")

var lord: Node3D


func before_test() -> void:
	lord = auto_free(LORD.instantiate())
	add_child(lord)
	await await_idle_frame()


func _visible(path: String) -> bool:
	return (lord.get_node(path) as Node3D).visible


func test_half_of_him_is_bone() -> void:
	assert_bool(_visible("Rig/Skeleton3D/Knight_ArmLeft")).is_true()
	assert_bool(_visible("Rig/Skeleton3D/Knight_ArmRight")).is_false()
	assert_bool(_visible("Rig/Skeleton3D/Knight_LegRight")).is_false()
	assert_bool(_visible("Bones/Rig/Skeleton3D/Skeleton_Minion_ArmRight")).is_true()
	assert_bool(_visible("Bones/Rig/Skeleton3D/Skeleton_Minion_LegRight")).is_true()
	assert_bool(_visible("Bones/Rig/Skeleton3D/Skeleton_Minion_ArmLeft")).is_false()
	assert_bool(_visible("Bones/Rig/Skeleton3D/Skeleton_Minion_Body")).is_false()


func test_both_halves_move_together() -> void:
	(lord.get_node("AnimationPlayer") as AnimationPlayer).play("Interact")
	await await_idle_frame()

	assert_str((lord.get_node("Bones/AnimationPlayer") as AnimationPlayer).current_animation).is_equal("Interact")
