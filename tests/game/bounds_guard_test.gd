extends GdUnitTestSuite

const LEVEL := preload("res://scenes/levels/pedraalta_level.tscn")

var level: Node3D
var session: GameSession
var guard: BoundsGuard


func before_test() -> void:
	RunState.reset()
	RunState.adventurer = load("res://resources/adventurers/knight.tres")
	level = auto_free(LEVEL.instantiate())
	add_child(level)
	session = level.get_node("GameSession")
	guard = level.get_node("BoundsGuard")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait_seconds(1.5)


func after_test() -> void:
	RunState.adventurer = null
	RunState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame


func test_falling_below_the_map_brings_the_player_back() -> void:
	var start := session.player.global_position

	session.player.global_position = Vector3(0, guard.fall_limit_y - 1.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_float(session.player.global_position.distance_to(start)).is_less(1.5)


# topo da muralha está no mapa de navegação, mas sem caminho: depois de uns segundos lá, volta
func test_standing_on_top_of_the_wall_brings_the_player_back() -> void:
	var start := session.player.global_position

	session.player.global_position = Vector3(-23.5, 18.2, -9)
	await _wait_seconds(BoundsGuard.STRANDED_LIMIT + 1.5)

	assert_float(session.player.global_position.distance_to(start)).is_less(1.5)


func test_walkable_ground_leaves_the_player_where_they_are() -> void:
	var terrace := Vector3(9, 6.2, -22)

	session.player.global_position = terrace
	await _wait_seconds(BoundsGuard.STRANDED_LIMIT + 1.5)

	assert_float(Vector2(session.player.global_position.x - terrace.x, session.player.global_position.z - terrace.z).length()).is_less(1.0)


# na Pedra Alta, quem passa da muralha ou da cerca cai no lago em volta e se afoga ali mesmo
func test_falling_past_the_walls_drowns_in_the_lake() -> void:
	var outside := Vector3(32, 1, 0)

	session.player.global_position = outside
	await _wait_seconds(2.0)

	assert_bool(session.player.is_dead).is_true()
	assert_str(session.player.damage_log.death_cause()).contains("Afogado fora da muralha")
	assert_float(Vector2(session.player.global_position.x - outside.x, session.player.global_position.z - outside.z).length()).is_less(1.0)
