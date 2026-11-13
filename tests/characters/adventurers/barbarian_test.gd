extends GdUnitTestSuite

const SCENE := TestArena.BARBARIAN

var arena: TestArena
var checks: AdventurerChecks


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)
	checks = AdventurerChecks.new(self, arena)


func after_test() -> void:
	Input.action_release("move_forward")


func test_spawns_ready_to_play() -> void:
	await checks.check_spawns_ready_to_play(SCENE)


func test_walks() -> void:
	await checks.check_walks(SCENE)


func test_attack_cycle() -> void:
	await checks.check_attack_cycle(SCENE)


func test_dies() -> void:
	await checks.check_dies(SCENE)


func test_shows_two_one_handed_axes() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO)

	assert_array(checks.visible_weapons(barbarian)).is_equal(["1H_Axe", "1H_Axe_Offhand"])


func test_quick_attack_is_a_single_axe_blow_in_front() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var front := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.3))
	var behind := arena.spawn(TestArena.SKELETON, Vector3(0, 0, -1.3))
	await arena.wait_physics(3)

	barbarian.attack.try_attack(barbarian)
	await arena.wait_seconds(barbarian.attack.impact_delay + 0.1)

	assert_float(front.health).is_equal(4.0)
	assert_float(behind.health).is_equal(5.0)


func test_charged_spin_hits_four_enemies_around_at_once() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var around: Array[Character] = []
	for offset in [Vector3(0, 0, 1.3), Vector3(0, 0, -1.3), Vector3(1.3, 0, 0), Vector3(-1.3, 0, 0)]:
		around.append(arena.spawn(TestArena.SKELETON, offset))
	await arena.wait_physics(3)

	barbarian.attack.try_attack(barbarian, true)
	await arena.wait_seconds(barbarian.attack.heavy_impact_delay + 0.1)

	for skeleton in around:
		assert_float(skeleton.health).is_equal(3.0)


func test_charged_spin_does_not_reach_far_enemies() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var far := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 3.0))
	await arena.wait_physics(3)

	barbarian.attack.try_attack(barbarian, true)
	await arena.wait_seconds(barbarian.attack.heavy_impact_delay + 0.1)

	assert_float(far.health).is_equal(5.0)


func test_spin_is_the_charged_attack() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer

	assert_array(Array(barbarian.attack.animations)).is_equal(["1H_Melee_Attack_Chop"])
	assert_str(barbarian.attack.heavy_animation).is_equal("2H_Melee_Attack_Spin")


func _hold_attack_as_gamepad() -> int:
	var before: int = Settings.input_device
	Settings.set_value(&"input_device", Settings.InputDevice.GAMEPAD)
	await arena.send_action("attack")
	return before


func _release(before: int) -> void:
	Input.action_release("attack")
	Settings.set_value(&"input_device", before)


func test_holding_the_attack_keeps_spinning_and_pays_each_turn() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	await arena.wait_physics(3)
	var before := await _hold_attack_as_gamepad()

	await arena.wait_seconds(Adventurer.HEAVY_HOLD_TIME + 1.6)

	assert_bool(barbarian.is_sustaining()).is_true()
	assert_str(barbarian.animation_player.current_animation).is_equal("2H_Melee_Attack_Spinning")
	assert_float(barbarian.stamina.current).is_less(barbarian.stamina.maximum - barbarian.heavy_cost)
	_release(before)


func test_letting_go_stops_the_spin() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	await arena.wait_physics(3)
	var before := await _hold_attack_as_gamepad()
	await arena.wait_seconds(Adventurer.HEAVY_HOLD_TIME + 1.0)

	_release(before)
	await arena.wait_physics(2)
	var spent := barbarian.stamina.current
	await arena.wait_seconds(0.8)

	assert_bool(barbarian.is_sustaining()).is_false()
	assert_float(barbarian.stamina.current).is_greater_equal(spent)


func test_spinning_walks_and_hits_around() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var left := arena.spawn(TestArena.SKELETON, Vector3(-3.5, 0, 0))
	var right := arena.spawn(TestArena.SKELETON, Vector3(3.5, 0, 0))
	await arena.wait_physics(3)
	var before := await _hold_attack_as_gamepad()
	await arena.wait_seconds(Adventurer.HEAVY_HOLD_TIME + 0.8)
	assert_float(left.health + right.health).is_equal(left.get_max_health() * 2.0)
	var start := barbarian.global_position

	Input.action_press("move_left")
	await arena.wait_seconds(1.2)
	Input.action_release("move_left")

	assert_float(barbarian.global_position.distance_to(start)).is_greater(1.0)
	assert_float(left.health + right.health).is_less(left.get_max_health() * 2.0)
	_release(before)


func test_the_spin_ends_when_stamina_runs_out() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	await arena.wait_physics(3)
	var before := await _hold_attack_as_gamepad()
	await arena.wait_seconds(Adventurer.HEAVY_HOLD_TIME + 0.1)

	var lowest := barbarian.stamina.current
	for i in 300:
		lowest = minf(lowest, barbarian.stamina.current)
		if not barbarian.is_sustaining():
			break
		await arena.wait_physics(1)

	assert_bool(barbarian.is_sustaining()).is_false()
	assert_bool(Input.is_action_pressed("attack")).is_true()
	assert_float(lowest).is_less(barbarian.cost_of(barbarian.sustained_attack))
	_release(before)


func test_getting_hit_cancels_the_spin_until_pressed_again() -> void:
	var barbarian := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 6))
	await arena.wait_physics(3)
	var before := await _hold_attack_as_gamepad()
	await arena.wait_seconds(Adventurer.HEAVY_HOLD_TIME + 1.0)
	assert_bool(barbarian.is_sustaining()).is_true()

	barbarian.take_damage(1.0, skeleton)
	await arena.wait_seconds(1.0)

	assert_bool(barbarian.is_sustaining()).is_false()
	assert_str(barbarian.animation_player.current_animation).is_not_equal("2H_Melee_Attack_Spinning")
	_release(before)
