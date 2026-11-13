extends GdUnitTestSuite

# o Necromante cai e deixa um alcapao no chao: o grupo tem uma contagem para descer ao calabouco (fase bonus);
# se ninguem descer, o contrato fecha com a tela de vitoria

const LEVEL := preload("res://scenes/levels/village_level.tscn")

var level: Node3D
var session: GameSession
var player: Adventurer


class FakeSession extends GameSession:
	var descended := 0

	func descend_to_bonus() -> void:
		descended += 1


func before_test() -> void:
	RunState.reset()
	RunState.adventurer = load("res://resources/adventurers/knight.tres")
	level = auto_free(LEVEL.instantiate())
	add_child(level)
	session = level.get_node("GameSession") as GameSession
	for i in 6:
		await get_tree().physics_frame
	player = session.player
	for enemy: Enemy in level.find_children("*", "Enemy", true, false):
		enemy.ai_enabled = false


func after_test() -> void:
	RunState.adventurer = null
	RunState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _trapdoor() -> Trapdoor:
	return level.find_child("Alcapao", true, false) as Trapdoor


func _victory() -> CanvasLayer:
	return level.get_node("VictoryScreen") as CanvasLayer


func _teleport(spot: Vector3) -> void:
	player.global_position = spot
	player.reset_physics_interpolation()
	for i in 4:
		await get_tree().physics_frame


func test_the_bonus_level_exists() -> void:
	assert_bool(ResourceLoader.exists(GameSession.BONUS_LEVEL)).is_true()


func test_the_fallen_boss_leaves_a_trapdoor_where_he_fell() -> void:
	var boss := level.find_children("*", "Enemy", true, false)[0] as Enemy
	session.boss = boss

	session._on_boss_died()

	var trapdoor := _trapdoor()
	assert_object(trapdoor).is_not_null()
	assert_float((trapdoor.global_position - boss.global_position).slide(Vector3.UP).length()).is_less(0.1)


func test_the_hud_counts_down_while_the_trapdoor_is_open() -> void:
	session.open_trapdoor_at(player.global_position + Vector3(4, 0, 0))

	await get_tree().create_timer(1.2).timeout

	var objective: String = session.hud.objective_label.text
	assert_str(objective).contains("alçapão")
	assert_str(objective).contains(str(int(GameSession.TRAPDOOR_TIME) - 1))
	assert_bool(_victory().visible).is_false()


func test_when_time_runs_out_the_contract_closes_with_the_victory_screen() -> void:
	session.trapdoor_time = 0.5
	session.open_trapdoor_at(player.global_position + Vector3(4, 0, 0))

	await get_tree().create_timer(1.0).timeout

	assert_bool(_victory().visible).is_true()
	assert_bool(_trapdoor().can_interact()).is_false()


func test_using_the_trapdoor_takes_the_group_down() -> void:
	session.open_trapdoor_at(player.global_position + Vector3(1.5, 0, 0))
	var fake: FakeSession = auto_free(FakeSession.new())
	_trapdoor().session = fake
	await _teleport(_trapdoor().global_position + Vector3(0, 0.2, 1))

	_trapdoor()._request_use.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)

	assert_int(fake.descended).is_equal(1)


func test_whoever_is_far_away_cannot_go_down() -> void:
	session.open_trapdoor_at(player.global_position + Vector3(12, 0, 0))
	var fake: FakeSession = auto_free(FakeSession.new())
	_trapdoor().session = fake

	_trapdoor()._request_use.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)

	assert_int(fake.descended).is_equal(0)


func test_the_trapdoor_opens_only_once() -> void:
	session.open_trapdoor_at(player.global_position + Vector3(4, 0, 0))
	session.open_trapdoor_at(player.global_position + Vector3(-4, 0, 0))

	assert_int(level.find_children("Alcapao*", "Trapdoor", true, false).size()).is_equal(1)


func test_falling_after_the_boss_still_closes_the_contract_with_victory() -> void:
	session.open_trapdoor_at(player.global_position + Vector3(4, 0, 0))

	player.take_damage(1000.0)
	await get_tree().process_frame

	assert_bool(_victory().visible).is_true()
	assert_bool(session.death_screen.visible).is_false()


func test_with_the_whole_group_down_no_trapdoor_opens() -> void:
	session.boss = level.find_children("*", "Enemy", true, false)[0] as Enemy
	player.take_damage(1000.0)

	session._on_boss_died()

	assert_object(_trapdoor()).is_null()
