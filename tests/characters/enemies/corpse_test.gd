extends GdUnitTestSuite

const REMAINS := "res://scenes/characters/enemies/remains.tscn"
const MIMIC := preload("res://scenes/characters/enemies/mimic.tscn")

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func _kill_quickly_cleaned_skeleton(position: Vector3) -> Enemy:
	var skeleton := arena.spawn(TestArena.SKELETON, position) as Enemy
	skeleton.corpse_time = 0.5
	skeleton.sink_time = 0.3
	await arena.wait_physics(3)
	skeleton.take_damage(99.0)
	return skeleton


func _remains() -> Array[Node]:
	return arena.root.find_children("*", "Decal", true, false).filter(func(d: Node) -> bool: return d.owner and d.owner.scene_file_path == REMAINS)


func test_body_stays_while_corpse_time_lasts() -> void:
	var skeleton := await _kill_quickly_cleaned_skeleton(Vector3.ZERO)

	await arena.wait_seconds(0.3)

	assert_bool(is_instance_valid(skeleton)).is_true()
	assert_int(_remains().size()).is_equal(0)


func test_body_is_removed_after_sinking() -> void:
	var skeleton := await _kill_quickly_cleaned_skeleton(Vector3.ZERO)

	await arena.wait_seconds(0.5 + 0.3 + 0.3)

	assert_bool(is_instance_valid(skeleton)).is_false()


func test_a_mark_stays_where_it_fell() -> void:
	await _kill_quickly_cleaned_skeleton(Vector3(3, 0, 2))

	await arena.wait_seconds(0.5 + 0.3 + 0.3)

	var marks := _remains()
	assert_int(marks.size()).is_equal(1)
	var mark := marks[0] as Decal
	assert_float(Vector2(mark.global_position.x - 3.0, mark.global_position.z - 2.0).length()).is_less(0.2)


func test_mark_does_not_fade_away() -> void:
	await _kill_quickly_cleaned_skeleton(Vector3.ZERO)

	await arena.wait_seconds(3.0)

	assert_int(_remains().size()).is_equal(1)


func test_living_skeleton_is_never_cleaned() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO) as Enemy
	skeleton.corpse_time = 0.2

	await arena.wait_seconds(1.0)

	assert_bool(is_instance_valid(skeleton)).is_true()


# o mímico derrotado solta a poção e o corpo fica um tempo antes de afundar e sumir
func test_a_dead_mimic_leaves_its_loot_and_its_body_sinks_away() -> void:
	var mimic: Mimic = MIMIC.instantiate()
	mimic.corpse_time = 0.5
	mimic.sink_time = 0.3
	arena.root.add_child(mimic)
	await arena.wait_physics(3)

	var fell_at := mimic.global_position.y
	mimic.take_damage(999.0)
	await arena.wait_seconds(0.3)
	assert_bool(is_instance_valid(mimic)).is_true()
	await arena.wait_seconds(0.2 + 0.2)
	assert_float(mimic.global_position.y).is_less(fell_at - 0.1)
	await arena.wait_seconds(0.4)

	assert_bool(is_instance_valid(mimic)).is_false()
	assert_object(arena.root.get_node_or_null("MimicoLoot")).is_not_null()
