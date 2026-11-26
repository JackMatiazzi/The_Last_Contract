extends GdUnitTestSuite

const MIMIC := "res://scenes/characters/enemies/mimic.tscn"
const SLOW_POTION := preload("res://resources/items/black_potion_slow.tres")
const WEAK_POTION := preload("res://resources/items/black_potion_weakness.tres")
const HEALTH_POTION := preload("res://resources/items/health_potion.tres")

var arena: TestArena


func before_test() -> void:
	arena = TestArena.new(self)


func test_two_bites_open_the_grab_and_correct_sequence_escapes() -> void:
	var victim := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 1.55)) as Adventurer
	var mimic := arena.spawn(MIMIC, Vector3.ZERO) as Mimic
	victim.knockback = 0.0
	mimic._net_wake()
	victim.take_damage(2.0, mimic)
	victim.take_damage(2.0, mimic)
	mimic._hunt()
	await arena.wait_seconds(0.6)
	assert_object(victim.grabbed_by).is_same(mimic)
	assert_vector(victim._read_move_input()).is_equal(Vector2.ZERO)
	var now := Time.get_ticks_msec()
	for heavy in Mimic.ESCAPE_SEQUENCE:
		mimic._escape_input(true, now)
		mimic._escape_input(false, now + (450 if heavy else 80))
		now += 650
	assert_object(victim.grabbed_by).is_null()
	assert_bool(victim.is_dead).is_false()
	assert_object(mimic.possessed).is_null()


func test_ally_heavy_interrupts_the_grab() -> void:
	var victim := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 1.55)) as Adventurer
	var ally := arena.spawn(TestArena.BARBARIAN, Vector3(2, 0, 0)) as Adventurer
	var mimic := arena.spawn(MIMIC, Vector3.ZERO) as Mimic
	mimic._net_begin_grab(victim.get_path())
	mimic.launch_away_from(ally, 2.0, 1.0)
	assert_object(victim.grabbed_by).is_null()
	assert_bool(victim.is_dead).is_false()


func test_a_mimic_landing_on_an_adventurer_starts_the_escape() -> void:
	var victim := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	var mimic := arena.spawn(MIMIC, Vector3(0, 3, 0)) as Mimic
	mimic._net_wake()
	mimic.velocity.y = -4.0
	await arena.wait_seconds(1.1)
	assert_object(victim.grabbed_by).is_same(mimic)


func test_assimilation_uses_each_class_and_allows_revive_after_defeat() -> void:
	var index := 0
	for scene: String in [TestArena.MAGE, TestArena.ROGUE, TestArena.BARBARIAN, TestArena.KNIGHT]:
		var origin := Vector3(index * 5.0, 0, 1.0)
		var victim := arena.spawn(scene, origin) as Adventurer
		var mimic := arena.spawn(MIMIC, origin - Vector3.FORWARD * 1.55) as Mimic
		var class_attack := victim.attack.title
		victim.take_damage(4.0)
		mimic._net_begin_grab(victim.get_path())
		mimic._escape_input(true, 0)
		mimic._escape_input(false, 450)
		assert_bool(victim.is_dead).is_true()
		assert_bool(victim.model.visible).is_false()
		assert_object(victim.camera_subject).is_same(mimic)
		assert_str(mimic._stolen_attack.title).is_equal(class_attack)
		assert_float(mimic.health).is_equal(20.0)
		var appearance := mimic.animation_player.get_parent()
		var skeleton := appearance.get_node("Rig/Skeleton3D") as Skeleton3D
		var attachment := skeleton.get_node("CabecaDoMimico") as BoneAttachment3D
		assert_int(attachment.bone_idx).is_equal(skeleton.find_bone("head"))
		assert_object(mimic.mouth).is_not_null()
		assert_bool(mimic.mouth.visible).is_true()
		assert_bool(attachment.is_ancestor_of(mimic.mouth)).is_true()
		var original_head := appearance.find_child("%s_Head" % appearance.name, true, false) as MeshInstance3D
		assert_bool(original_head.visible).is_false()
		for accessory in skeleton.get_children():
			if accessory is BoneAttachment3D and accessory != attachment and accessory.bone_idx == attachment.bone_idx:
				assert_bool(accessory.visible).is_false()
		mimic.global_position += Vector3(0, 0, 2)
		var release_spot := mimic.global_position
		mimic.take_damage(100.0)
		assert_object(victim.possessed_by).is_null()
		assert_bool(victim.model.visible).is_true()
		assert_vector(victim.global_position).is_equal(release_spot)
		victim.revive(5.0)
		assert_bool(victim.is_dead).is_false()
		assert_bool((victim.model.find_child("*_Head", true, false) as MeshInstance3D).is_visible_in_tree()).is_true()
		index += 1


func test_black_potion_can_be_drunk_at_full_health_and_weakens_attack() -> void:
	var player := arena.spawn(TestArena.MAGE, Vector3.ZERO) as Adventurer
	player.inventory.add(WEAK_POTION)
	assert_bool(player.use_item()).is_true()
	assert_int(player.inventory.count_of(WEAK_POTION)).is_equal(0)
	assert_float(player.get_stat_bonus(StatModifier.Stat.DAMAGE)).is_equal(-0.5)


func test_possessed_mage_hits_an_ally_with_a_hostile_projectile() -> void:
	var victim := arena.spawn(TestArena.MAGE, Vector3(0, 0, 1.5)) as Adventurer
	var ally := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 6)) as Adventurer
	var mimic := arena.spawn(MIMIC, Vector3.ZERO) as Mimic
	mimic._net_wake()
	mimic._net_begin_grab(victim.get_path())
	mimic._assimilate()
	mimic._target = ally
	await arena.wait_seconds(1.2)
	assert_float(ally.health).is_less(ally.get_max_health())


func test_black_potion_changes_to_the_amber_lacre_on_even_attempts() -> void:
	var scene := preload("res://scenes/world/black_potion_slow.tscn")
	var potion := scene.instantiate() as Potion
	potion.alternate_item = WEAK_POTION
	var previous_attempt := RunState.attempt
	RunState.attempt = 2
	arena.root.add_child(potion)
	RunState.attempt = previous_attempt
	assert_object(potion.item).is_same(WEAK_POTION)
	var seal := potion.model.get_node("Lacre") as MeshInstance3D
	assert_that(seal.get_active_material(0).albedo_color).is_equal(WEAK_POTION.seal_color)


func test_dropped_black_potion_only_slows_the_first_enemy() -> void:
	var player := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	var enemy := arena.spawn(TestArena.SKELETON, Vector3(3, 0, 0))
	var other := arena.spawn(TestArena.SKELETON, Vector3(5, 0, 0))
	await arena.wait_physics(3)
	player.inventory.add(SLOW_POTION)
	player.drop_item()
	var trap := arena.root.find_child("*PocaoLargada1", false, false) as Potion
	assert_object(trap).is_not_null()
	assert_bool(trap.armed).is_true()
	assert_int(player.inventory.count_of(SLOW_POTION)).is_equal(0)
	trap._trigger_trap(player)
	assert_bool(trap._consumed).is_false()
	enemy.global_position = trap.global_position
	await arena.wait_physics(5)
	assert_float(enemy.get_stat_bonus(StatModifier.Stat.SPEED)).is_equal(-0.35)
	assert_bool(trap._consumed).is_true()
	trap._trigger_trap(other)
	assert_float(other.get_stat_bonus(StatModifier.Stat.SPEED)).is_equal(0.0)


func test_dropped_life_potion_can_be_picked_up_by_another_player() -> void:
	var player := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	var ally := arena.spawn(TestArena.MAGE, Vector3(3, 0, 0)) as Adventurer
	await arena.wait_physics(3)
	player.inventory.add(HEALTH_POTION)
	player.drop_item()
	var potion := arena.root.find_child("*PocaoLargada1", false, false) as Potion
	assert_object(potion).is_not_null()
	assert_bool(potion.armed).is_false()
	player.remove_from_group("players")
	ally.global_position = potion.global_position
	await arena.wait_physics(5)
	assert_int(ally.inventory.count_of(HEALTH_POTION)).is_equal(1)
