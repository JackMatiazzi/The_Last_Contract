extends GdUnitTestSuite

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func after_test() -> void:
	RunState.reset()


func test_adventurer_and_skeleton_spawn_with_their_max_health() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(4, 0, 0))

	assert_float(knight.health).is_equal(10.0)
	assert_float(skeleton.health).is_equal(5.0)


func test_take_damage_reduces_health_and_emits_signal() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var signals := monitor_signals(knight, false)

	knight.take_damage(3.0)

	assert_float(knight.health).is_equal(7.0)
	await assert_signal(signals).is_emitted("health_changed", [7.0, 10.0])


func test_damage_plays_hit_reaction_and_locks_movement() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)

	knight.take_damage(1.0)

	assert_bool(knight.is_busy).is_true()
	assert_str(knight.animation_player.current_animation).is_equal(Character.ANIM_HIT)


func test_dies_at_zero_health() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO)
	var signals := monitor_signals(skeleton, false)

	skeleton.take_damage(5.0)

	assert_bool(skeleton.is_dead).is_true()
	await assert_signal(signals).is_emitted("died")


func test_ignores_damage_after_death() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO)
	skeleton.take_damage(5.0)
	var signals := monitor_signals(skeleton, false)

	skeleton.take_damage(5.0)

	assert_float(skeleton.health).is_equal(0.0)
	await assert_signal(signals).wait_until(200).is_not_emitted("died")
	await assert_signal(signals).wait_until(200).is_not_emitted("health_changed")


func test_death_disables_body_collision() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3.ZERO)

	skeleton.die()
	await arena.wait_physics(2)

	assert_bool(skeleton.collision_shape.disabled).is_true()


# os mortos-vivos recebem só 20% de cada bênção
func test_run_buffs_apply_to_adventurers_and_enemies() -> void:
	RunState.buffs.append(load("res://resources/buffs/couraca.tres"))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(4, 0, 0))

	assert_float(knight.get_damage_taken_factor()).is_equal_approx(0.8, 0.001)
	assert_float(skeleton.get_damage_taken_factor()).is_equal_approx(0.96, 0.001)


func _stat_buff(stat: StatModifier.Stat, amount: float) -> Buff:
	var buff := Buff.new()
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.amount = amount
	buff.modifiers.append(modifier)
	return buff


func test_max_health_never_drops_below_one() -> void:
	RunState.buffs.append(_stat_buff(StatModifier.Stat.MAX_HEALTH, -50.0))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(4, 0, 0))

	assert_float(knight.get_max_health()).is_equal(1.0)
	assert_float(skeleton.get_max_health()).is_equal(1.0)


func test_enemies_feel_a_fifth_of_each_blessing() -> void:
	var fury: Buff = load("res://resources/buffs/furia_cega.tres")
	RunState.buffs.append_array([fury, fury, fury])
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(4, 0, 0))

	assert_float(knight.get_stat_bonus(StatModifier.Stat.DAMAGE)).is_equal(3.0)
	assert_float(skeleton.get_stat_bonus(StatModifier.Stat.DAMAGE)).is_equal_approx(0.6, 0.001)
	assert_float(knight.get_damage_taken_factor()).is_equal_approx(1.9, 0.001)
	assert_float(skeleton.get_damage_taken_factor()).is_equal_approx(1.18, 0.001)


func test_speed_buff_raises_max_speed() -> void:
	RunState.buffs.append(load("res://resources/buffs/passos_leves.tres"))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)

	assert_float(knight.get_max_speed()).is_equal_approx(knight.walk_speed * 1.15, 0.001)


func test_speed_penalty_never_goes_below_floor() -> void:
	var slow := Buff.new()
	var modifier := StatModifier.new()
	modifier.stat = StatModifier.Stat.SPEED
	modifier.amount = -5.0
	slow.modifiers = [modifier]
	RunState.buffs.append(slow)
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)

	assert_float(knight.get_max_speed()).is_equal_approx(knight.walk_speed * Character.MIN_STAT_FACTOR, 0.001)


# o dano dos mortos-vivos vale como porcentagem da vida máxima: vida a mais não deixa o aventureiro imortal
func test_an_enemy_hit_takes_the_same_share_of_any_max_health() -> void:
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(4, 0, 0))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	knight.take_damage(1.0, skeleton)
	assert_float(knight.health / knight.get_max_health()).is_equal_approx(0.9, 0.001)

	RunState.buffs.append(_stat_buff(StatModifier.Stat.MAX_HEALTH, 4.0))
	var sturdy := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 4))
	sturdy.take_damage(1.0, skeleton)

	assert_float(sturdy.get_max_health()).is_equal(14.0)
	assert_float(sturdy.health).is_equal_approx(14.0 - 1.4, 0.001)


func test_armor_cuts_a_fifth_of_each_hit() -> void:
	RunState.buffs.append(load("res://resources/buffs/couraca.tres"))
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(4, 0, 0))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)

	knight.take_damage(1.0, skeleton)

	assert_float(knight.get_max_health()).is_equal(10.0)
	assert_float(knight.health).is_equal_approx(10.0 - 0.8, 0.001)


func test_damage_reduction_never_makes_anyone_immortal() -> void:
	RunState.buffs.append(_stat_buff(StatModifier.Stat.DAMAGE_TAKEN, -5.0))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)

	knight.take_damage(1.0)

	assert_float(knight.get_damage_taken_factor()).is_equal(Character.MIN_STAT_FACTOR)
	assert_float(knight.health).is_equal_approx(10.0 - Character.MIN_STAT_FACTOR, 0.001)


func test_friendly_fire_and_hits_on_enemies_stay_in_points() -> void:
	RunState.buffs.append(_stat_buff(StatModifier.Stat.MAX_HEALTH, 2.0))
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var ally := arena.spawn(TestArena.KNIGHT, Vector3(3, 0, 0))
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(-3, 0, 0))

	ally.take_damage(1.0, knight)
	skeleton.take_damage(1.0, knight)

	assert_float(ally.health).is_equal_approx(ally.get_max_health() - 1.0, 0.001)
	assert_float(skeleton.health).is_equal_approx(skeleton.get_max_health() - 1.0, 0.001)
