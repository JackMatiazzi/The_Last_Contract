extends GdUnitTestSuite

# água funda: quem cai nela morre na hora, aventureiro ou morto-vivo

var arena: TestArena
var water: KillZone


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)
	water = KillZone.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4, 2, 4)
	water.add_child(shape)
	water.position = Vector3(10, 1, 0)
	arena.root.add_child(water)


func test_an_adventurer_that_falls_in_dies() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3(10, 0.2, 0))

	await arena.wait_physics(6)

	assert_bool(knight.is_dead).is_true()


func test_an_undead_that_falls_in_dies_too() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(10, 0.2, 0))

	await arena.wait_physics(6)

	assert_bool(skeleton.is_dead).is_true()


func test_whoever_stays_out_of_the_water_is_fine() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3(0, 0.2, 0))

	await arena.wait_physics(6)

	assert_bool(knight.is_dead).is_false()


func test_the_death_names_the_water() -> void:
	assert_str(water.get_display_name()).is_equal(KillZone.DEFAULT_CAUSE)
