extends GdUnitTestSuite

const RING := preload("res://scenes/props/forest_ring.tscn")


func test_no_tree_inside_the_clear_square_or_past_the_radius() -> void:
	var spots := ForestBuilder.scatter(20.0, 40.0, 2.6, 7)

	assert_int(spots.size()).is_greater(0)
	for spot in spots:
		assert_float(maxf(absf(spot.x), absf(spot.y))).is_greater_equal(20.0)
		assert_float(spot.length()).is_less_equal(40.0)


func test_trees_keep_their_spacing() -> void:
	var spots := ForestBuilder.scatter(20.0, 40.0, 2.6, 7)

	for i in spots.size():
		for j in range(i + 1, spots.size()):
			assert_float(spots[i].distance_to(spots[j])).is_greater_equal(2.6)


func test_same_seed_gives_the_same_forest() -> void:
	assert_array(ForestBuilder.scatter(20.0, 40.0, 2.6, 7)).is_equal(ForestBuilder.scatter(20.0, 40.0, 2.6, 7))


func test_mist_and_ground_leave_the_village_clear() -> void:
	var ring: ForestRing = auto_free(RING.instantiate())
	var free_half := ring.clear_half_size - ForestRing.MIST_INSET

	ring._fit_mist()
	ring._fit_ground()

	for volume in ring.find_children("*", "FogVolume", false, false):
		var near := (volume as FogVolume).position.abs() - (volume as FogVolume).size / 2.0
		assert_bool(near.x >= free_half - 0.01 or near.z >= free_half - 0.01).is_true()
	var plane := (ring.get_node("Chao") as MeshInstance3D).mesh as PlaneMesh
	assert_float(plane.size.x).is_equal_approx((ring.outer_radius + ForestRing.GROUND_MARGIN) * 2.0, 0.01)


func test_village_level_turns_on_the_volumetric_fog() -> void:
	var level: Node = auto_free(load("res://scenes/levels/village_level.tscn").instantiate())
	var environment := (level.get_node("WorldEnvironment") as WorldEnvironment).environment

	assert_bool(environment.volumetric_fog_enabled).is_true()


func test_saved_forest_has_instances() -> void:
	var ring: ForestRing = auto_free(RING.instantiate())

	for holder in ring.find_children("*", "MultiMeshInstance3D", false, false):
		var multimesh := (holder as MultiMeshInstance3D).multimesh
		assert_int(multimesh.instance_count).is_greater(0)


func test_one_tree_model_per_holder() -> void:
	var ring: ForestRing = auto_free(RING.instantiate())

	assert_int(ring.models.size()).is_equal(ring.find_children("*", "MultiMeshInstance3D", false, false).size())
