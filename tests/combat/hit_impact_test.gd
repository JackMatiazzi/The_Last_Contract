extends GdUnitTestSuite

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func after_test() -> void:
	RunState.reset()


func test_hit_pushes_the_enemy_away_from_the_attacker() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	await arena.wait_physics(5)
	var start := skeleton.global_position.z

	knight.heavy_attack()
	await arena.wait_seconds(1.0)

	assert_float(skeleton.global_position.z - start).is_greater(0.3)


func test_heavier_hit_pushes_harder() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var light := arena.spawn(TestArena.SKELETON, Vector3(3, 0, 1.2))
	var heavy := arena.spawn(TestArena.SKELETON, Vector3(-3, 0, 1.2))
	await arena.wait_physics(5)

	light.take_damage(1.0, knight)
	heavy.take_damage(2.0, knight)

	assert_float(heavy.knockback_velocity.length()).is_greater(light.knockback_velocity.length())


func test_push_fades_out() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	await arena.wait_physics(5)

	skeleton.take_damage(1.0, knight)
	await arena.wait_seconds(1.0)

	assert_float(skeleton.knockback_velocity.length()).is_equal(0.0)


func test_revived_adventurer_is_not_thrown_by_the_killing_blow() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO)
	var knight := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 1.2))
	await arena.wait_physics(5)

	knight.take_damage(knight.health, skeleton)
	knight.revive(5.0)

	assert_float(knight.knockback_velocity.length()).is_equal(0.0)


func test_freeze_holds_even_while_standing_still() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO)
	await arena.wait_physics(5)

	skeleton.freeze_animation(Character.HITSTOP_HEAVY)
	await arena.wait_physics(3)

	assert_float(skeleton.animation_player.speed_scale).is_equal(0.0)


func test_blocked_hit_does_not_push() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO)
	var knight := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 1.2), 180.0)
	await arena.wait_physics(5)
	knight.use_secondary()
	await arena.wait_physics(3)

	knight.take_damage(1.0, skeleton)

	assert_float(knight.health).is_equal(knight.get_max_health())
	assert_float(knight.knockback_velocity.length()).is_equal(0.0)


func test_landing_a_hit_freezes_attacker_and_target_for_a_moment() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	await arena.wait_physics(5)

	knight.attack.try_attack(knight)
	await _wait_for_hit(skeleton)

	assert_float(knight.animation_player.speed_scale).is_equal(0.0)
	assert_float(skeleton.animation_player.speed_scale).is_equal(0.0)
	await arena.wait_seconds(0.3)
	assert_float(knight.animation_player.speed_scale).is_greater(0.0)
	assert_float(skeleton.animation_player.speed_scale).is_greater(0.0)


func test_a_miss_neither_freezes_nor_shakes() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	arena.spawn(TestArena.SKELETON, Vector3(0, 0, -1.2))
	await arena.wait_physics(5)

	knight.attack.try_attack(knight)
	await arena.wait_seconds(knight.attack.impact_delay + 0.05)

	assert_float(knight.animation_player.speed_scale).is_greater(0.0)
	assert_float(knight.shake_trauma).is_equal(0.0)


func test_heavy_hit_shakes_the_camera_more_than_a_quick_one() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	await arena.wait_physics(5)

	knight.on_hit_landed(false)
	var quick := knight.shake_trauma
	knight.shake_trauma = 0.0
	knight.on_hit_landed(true)

	assert_float(quick).is_greater(0.0)
	assert_float(knight.shake_trauma).is_greater(quick)
	assert_object(skeleton).is_not_null()


func test_shake_settles_back_to_the_normal_framing() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	await arena.wait_physics(5)
	var framing := Vector2(knight.camera.h_offset, knight.camera.v_offset)

	knight.on_hit_landed(true)
	await arena.wait_seconds(1.0)

	assert_float(knight.shake_trauma).is_equal(0.0)
	assert_vector(Vector2(knight.camera.h_offset, knight.camera.v_offset)).is_equal_approx(framing, Vector2.ONE * 0.001)


func test_crossbow_hit_also_shakes_the_shooter() -> void:
	var rogue := arena.spawn(TestArena.ROGUE, Vector3.ZERO) as Adventurer
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 5))
	await arena.wait_physics(5)

	rogue.attack.try_attack(rogue)
	await _wait_for_hit(skeleton)

	assert_float(rogue.shake_trauma).is_greater(0.0)


func _until_awake(enemy: Enemy) -> void:
	for i in 240:
		if enemy.brain.current_state_name not in ["Dormant", "Awaken"]:
			return
		await arena.wait_physics(1)


func _wait_for_hit(target: Character) -> void:
	for i in 120:
		if target.health < target.get_max_health():
			return
		await arena.wait_physics(1)


func test_a_staggered_undead_cannot_be_staggered_again_right_away() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2))
	(skeleton as Enemy).max_health = 99.0
	(skeleton as Enemy).health = 99.0
	await arena.wait_physics(5)
	skeleton.take_damage(0.01, knight)
	await _until_awake(skeleton as Enemy)

	skeleton.take_damage(1.0, knight)
	var first := skeleton.action_id
	await arena.wait_seconds(Character.HIT_RECOVERY + 0.1)
	skeleton.play_action("1H_Melee_Attack_Chop", 1.0, 0.0, 1.0)
	var swing := skeleton.action_id
	skeleton.take_damage(1.0, knight)

	assert_int(first).is_greater(0)
	assert_int(skeleton.action_id).is_equal(swing)


func test_the_guard_wears_off_and_the_next_hit_staggers_again() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(0, 0, 1.2)) as Enemy
	skeleton.max_health = 99.0
	skeleton.health = 99.0
	await arena.wait_physics(5)
	skeleton.take_damage(0.01, knight)
	await _until_awake(skeleton as Enemy)
	skeleton.take_damage(1.0, knight)

	await arena.wait_seconds(skeleton.flinch_guard + 0.3)
	var before := skeleton.action_id
	skeleton.take_damage(1.0, knight)

	assert_int(skeleton.action_id).is_greater(before)
	assert_str(skeleton.animation_player.current_animation).is_equal(Character.ANIM_HIT)
