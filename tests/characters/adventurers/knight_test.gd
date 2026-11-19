extends GdUnitTestSuite

const SCENE := TestArena.KNIGHT

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


func test_shows_sword_and_badge_shield_only() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO)

	assert_array(checks.visible_weapons(knight)).is_equal(["1H_Sword", "Badge_Shield"])


func test_combo_has_three_different_swings() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer

	assert_int(knight.attack.animations.size()).is_equal(3)
	assert_int(Array(knight.attack.animations).filter(func(a): return knight.animation_player.has_animation(a)).size()).is_equal(3)


func test_hits_one_enemy_in_front_and_not_one_behind() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var front := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	var back := arena.spawn(TestArena.SKELETON, Vector3(0, 0, -1.2))
	await arena.wait_physics(3)

	knight.attack.try_attack(knight)
	await arena.wait_seconds(knight.attack.impact_delay + 0.1)

	assert_float(front.health).is_equal(4.0)
	assert_float(back.health).is_equal(5.0)


func test_full_combo_kills_skeleton_in_five_hits() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	await arena.wait_physics(3)

	var swings := 0
	while not skeleton.is_dead and swings < 10:
		if knight.attack.try_attack(knight):
			swings += 1
		await arena.wait_physics(1)
	await arena.wait_seconds(knight.attack.impact_delay + 0.1)

	assert_bool(skeleton.is_dead).is_true()
	assert_int(swings).is_equal(5)


# espada em dobro: o golpe chega bem mais longe que o de antes (que parava em uns 2 m)
func _sword_of(knight: Adventurer) -> Node3D:
	return knight.find_child("1H_Sword", true, false) as Node3D


func test_the_sword_is_twice_its_original_size() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer

	assert_vector(_sword_of(knight).scale).is_equal_approx(Vector3.ONE * 2.0, Vector3.ONE * 0.01)


func test_the_bigger_sword_hits_an_enemy_farther_away() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	var near := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 2.6))
	var far := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 4.5))
	await arena.wait_physics(3)

	knight.attack.try_attack(knight)
	await arena.wait_seconds(knight.attack.impact_delay + 0.1)

	assert_float(near.health).is_equal(4.0)
	assert_float(far.health).is_equal(5.0)


func _sword_height_at(knight: Adventurer, animation_time: float) -> float:
	knight.animation_player.play(knight.attack.heavy_animation)
	knight.animation_player.seek(animation_time, true)
	await arena.wait_physics(1)
	return _sword_of(knight).global_position.y


# o dano do golpe pesado sai com a espada descendo, não erguida no alto antes do golpe
func test_the_heavy_hit_lands_while_the_sword_comes_down() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	await arena.wait_physics(2)
	var impact := knight.attack.heavy_impact_delay * knight.attack.heavy_animation_speed

	var before: float = await _sword_height_at(knight, impact - 0.05)
	var falling: float = before - await _sword_height_at(knight, impact)

	assert_float(falling).is_greater(0.05)


# cada golpe rápido da sequência acerta com a espada descendo, não ainda erguida
func test_the_quick_chop_lands_while_the_sword_comes_down() -> void:
	var knight := arena.spawn(SCENE, Vector3.ZERO) as Adventurer
	await arena.wait_physics(2)
	var chop: String = knight.attack.animations[0]
	var impact: float = knight.attack.impact_delays[0] * knight.attack.animation_speed

	knight.animation_player.play(chop)
	knight.animation_player.seek(impact - 0.05, true)
	await arena.wait_physics(1)
	var before := _sword_of(knight).global_position.y
	knight.animation_player.seek(impact, true)
	await arena.wait_physics(1)

	assert_float(before - _sword_of(knight).global_position.y).is_greater(0.05)
