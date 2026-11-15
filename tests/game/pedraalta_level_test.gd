extends GdUnitTestSuite

const LEVEL := preload("res://scenes/levels/pedraalta_level.tscn")

var level: Node3D
var session: GameSession
var encounters: EncounterSpawner


func before_test() -> void:
	RunState.reset()
	RunState.adventurer = load("res://resources/adventurers/knight.tres")
	level = auto_free(LEVEL.instantiate())
	add_child(level)
	session = level.get_node("GameSession")
	encounters = level.get_node("Encounters")
	for i in 3:
		await await_idle_frame()


func after_test() -> void:
	RunState.adventurer = null
	RunState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.action_release("move_forward")


func _groups() -> Array[Node]:
	return encounters.get_children().filter(func(child: Node) -> bool: return child is EnemyGroup)


func _zone_of(group: Node) -> StringName:
	var nearest: Marker3D = null
	for spot: Marker3D in encounters.group_spots.get_children():
		if nearest == null or spot.global_position.distance_to(group.global_position) < nearest.global_position.distance_to(group.global_position):
			nearest = spot
	return nearest.get_meta("zone")


func _wait_for_navigation() -> RID:
	var map := level.get_world_3d().navigation_map
	var probe: Vector3 = encounters.player_spots.get_child(0).global_position
	for frame in 60:
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0:
			break
		await get_tree().physics_frame
	return map


func test_every_group_spot_belongs_to_a_zone() -> void:
	for spot: Marker3D in encounters.group_spots.get_children():
		assert_bool(spot.has_meta("zone")).override_failure_message("%s sem zona" % spot.name).is_true()


# todas as zonas têm grupo; os grupos a mais vão para zonas diferentes, nunca três na mesma
func _check_spread(zones: Array) -> void:
	assert_int(zones.size()).is_equal(encounters.group_count)
	for zone in ["A", "B", "C", "D", "E"]:
		assert_int(zones.count(zone)).override_failure_message("zona %s sem grupo" % zone).is_greater_equal(1)
	for zone in zones:
		assert_int(zones.count(zone)).override_failure_message("grupos demais na zona %s" % zone).is_less_equal(2)


func test_every_zone_gets_a_group_and_the_extras_spread_out() -> void:
	_check_spread(_groups().map(_zone_of))


func test_the_spread_holds_on_every_draw() -> void:
	var player_position := session.player.global_position
	for draw in 20:
		for group in _groups():
			group.free()
		_check_spread(encounters.spawn_groups(player_position).map(_zone_of))


func test_every_group_spot_can_walk_to_every_player_spot() -> void:
	var map := await _wait_for_navigation()

	for group_spot: Marker3D in encounters.group_spots.get_children():
		for player_spot: Marker3D in encounters.player_spots.get_children():
			var path := NavigationServer3D.map_get_path(map, group_spot.global_position, player_spot.global_position, true)
			var reached := not path.is_empty() and path[-1].distance_to(player_spot.global_position) < 1.5
			assert_bool(reached).override_failure_message("%s nao chega em %s" % [group_spot.name, player_spot.name]).is_true()


func test_the_boss_spot_is_reachable_from_the_entrance() -> void:
	var map := await _wait_for_navigation()
	var start: Vector3 = encounters.player_spots.get_child(0).global_position
	var boss := encounters.boss_spot.global_position

	var path := NavigationServer3D.map_get_path(map, start, boss, true)

	assert_bool(not path.is_empty() and path[-1].distance_to(boss) < 1.5).is_true()


func test_every_spot_stands_on_open_ground() -> void:
	var space := level.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1

	for spot: Marker3D in encounters.group_spots.get_children() + encounters.player_spots.get_children():
		query.transform = Transform3D(Basis(), spot.global_position + Vector3.UP * 1.0)
		assert_array(space.intersect_shape(query)).override_failure_message("%s dentro de algo" % spot.name).is_empty()


func test_the_terraces_climb_toward_the_boss() -> void:
	var heights := {}
	for spot: Marker3D in encounters.group_spots.get_children():
		heights[spot.get_meta("zone")] = spot.global_position.y

	assert_float(heights[&"B"]).is_greater(heights[&"A"])
	assert_float(heights[&"C"]).is_greater(heights[&"B"])
	assert_float(heights[&"D"]).is_greater(heights[&"C"])
	assert_float(encounters.boss_spot.global_position.y).is_greater(heights[&"D"])


func test_the_knight_walks_up_the_first_ramp() -> void:
	var knight := session.player
	knight.global_position = Vector3(-8, 0.3, 30)
	knight.camera_pivot.rotation.y = 0.0
	await get_tree().physics_frame

	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
		if knight.global_position.z < 17.0:
			break
	Input.action_release("move_forward")

	assert_float(knight.global_position.y).is_greater(2.5)


func test_the_entrance_zone_always_gets_the_easiest_group() -> void:
	var player_position := session.player.global_position
	for draw in 10:
		for group in _groups():
			group.free()
		for group in encounters.spawn_groups(player_position):
			if _zone_of(group) == &"A":
				assert_str(group.scene_file_path).is_equal(encounters.easy_group.resource_path)


func test_entrance_spots_keep_a_safe_margin_from_the_spawn() -> void:
	for spot: Marker3D in encounters.group_spots.get_children():
		if spot.get_meta("zone") != &"A":
			continue
		for player_spot: Marker3D in encounters.player_spots.get_children():
			assert_float(spot.global_position.distance_to(player_spot.global_position)).is_greater(encounters.min_distance_from_player + 3.0)


func test_the_crevasse_has_deep_water_that_kills() -> void:
	var water := level.find_child("AguaDaFenda", true, false) as KillZone
	assert_object(water).is_not_null()
	var knight := session.player
	knight.global_position = Vector3(4, 7.5, -36)

	for i in 120:
		await get_tree().physics_frame
		if knight.is_dead:
			break

	assert_bool(knight.is_dead).is_true()
