extends GdUnitTestSuite

# Inimigos novos que atacam de longe: o mago esqueleto (magia), o arqueiro esqueleto (flecha), o
# mago invocador (elite que também levanta esqueletos) e o mago de batalha (elite só de disparo).

const MAGE := "res://scenes/characters/enemies/skeleton_mage.tscn"
const ARCHER := "res://scenes/characters/enemies/skeleton_archer.tscn"
const SUMMONER := "res://scenes/characters/enemies/skeleton_summoner.tscn"
const BATTLEMAGE := "res://scenes/characters/enemies/skeleton_battlemage.tscn"
# o arqueiro e o mago esqueleto atiram da mesma distância que o Rogue e o Mage, sem vantagem de alcance
const PLAYER_BOLT := preload("res://scenes/combat/crossbow_bolt.tscn")
const PLAYER_MAGIC := preload("res://scenes/combat/magic_bolt.tscn")
const CASTERS := "res://scenes/characters/enemies/groups/casters.tscn"
const SUMMONER_CIRCLE := "res://scenes/characters/enemies/groups/summoner_circle.tscn"
const BATTLEMAGE_SQUAD := "res://scenes/characters/enemies/groups/battlemage_squad.tscn"
const NEW_GROUPS: Array[String] = [CASTERS, SUMMONER_CIRCLE, BATTLEMAGE_SQUAD]
const LEVELS: Array[String] = ["res://scenes/levels/pedraalta_level.tscn", "res://scenes/levels/village_level.tscn"]

var arena: TestArena


func after_test() -> void:
	RunState.adventurer = null
	RunState.reset()


# com a IA ligada (o arena.spawn desliga): um golpe de leve faz o inimigo perceber o jogador e caçar
func _hunting(path: String, player: Character, summon_interval := 0.0) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	if summon_interval > 0.0:
		(enemy.get_node("Summoner") as Summoner).interval = summon_interval
	arena.root.add_child(enemy)
	await arena.wait_physics(3)
	enemy.take_damage(0.1, player)
	return enemy


func _shoots_from_afar(path: String, distance: float) -> void:
	arena = TestArena.new(self)
	await arena.bake_navigation()
	var player := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, distance))
	await _hunting(path, player)

	await arena.wait_seconds(4.0)

	assert_float(player.health).override_failure_message("%s não acertou de %d m" % [path, distance]).is_less(player.get_max_health())


func test_the_skeleton_mage_is_fragile_and_attacks_with_magic_from_afar() -> void:
	arena = TestArena.new(self)
	var mage := arena.spawn(MAGE, Vector3.ZERO) as Enemy

	assert_object(mage.attack).is_instanceof(RangedAttack)
	assert_int((mage.attack as RangedAttack).target_layers).is_equal(2)
	assert_float(mage.get_max_health()).is_less(8.0)
	assert_str(mage.get_display_name()).is_equal("Mago esqueleto")


func test_the_skeleton_mage_reaches_as_far_as_the_player_mage_and_no_farther() -> void:
	arena = TestArena.new(self)
	var mage := arena.spawn(MAGE, Vector3.ZERO) as Enemy
	var bolt := (mage.attack as RangedAttack).projectile_scene.instantiate() as Projectile
	var player_bolt := PLAYER_MAGIC.instantiate() as Projectile

	assert_float(mage.profile.attack_range).is_less_equal(player_bolt.max_distance)
	assert_float(bolt.max_distance).is_equal(player_bolt.max_distance)
	bolt.free()
	player_bolt.free()


func test_the_skeleton_mage_hits_from_five_meters() -> void:
	await _shoots_from_afar(MAGE, 5.0)


func test_the_archer_shoots_arrows_that_reach_its_range() -> void:
	arena = TestArena.new(self)
	var archer := arena.spawn(ARCHER, Vector3.ZERO) as Enemy
	var bow := archer.attack as RangedAttack
	var arrow := bow.projectile_scene.instantiate() as Projectile

	assert_object(bow).is_not_null()
	assert_int(bow.target_layers).is_equal(2)
	assert_str(archer.get_display_name()).is_equal("Arqueiro esqueleto")
	arrow.free()


func test_the_archer_reaches_as_far_as_the_player_rogue_and_no_farther() -> void:
	arena = TestArena.new(self)
	var archer := arena.spawn(ARCHER, Vector3.ZERO) as Enemy
	var arrow := (archer.attack as RangedAttack).projectile_scene.instantiate() as Projectile
	var player_bolt := PLAYER_BOLT.instantiate() as Projectile

	assert_float(archer.profile.attack_range).is_less_equal(player_bolt.max_distance)
	assert_float(arrow.max_distance).is_equal(player_bolt.max_distance)
	arrow.free()
	player_bolt.free()


func test_the_archer_hits_from_five_meters() -> void:
	await _shoots_from_afar(ARCHER, 5.0)


func test_the_summoner_is_an_elite_caster_that_raises_skeletons() -> void:
	arena = TestArena.new(self)
	var summoner := arena.spawn(SUMMONER, Vector3.ZERO) as Enemy

	assert_object(summoner.attack).is_instanceof(RangedAttack)
	assert_object(summoner.get_node_or_null("Summoner")).is_instanceof(Summoner)
	assert_float(summoner.get_max_health()).is_greater(10.0)
	assert_str(summoner.get_display_name()).is_equal("Mago invocador")


func test_the_summoner_raises_skeletons_but_never_more_than_its_limit() -> void:
	arena = TestArena.new(self)
	await arena.bake_navigation()
	var player := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 9))
	var summoner := await _hunting(SUMMONER, player, 0.8)
	var caller := summoner.get_node("Summoner") as Summoner

	await arena.wait_seconds(6.0)

	assert_int(caller.minions.size()).is_greater(0)
	assert_int(caller._alive_count()).is_less_equal(caller.max_alive)


func test_the_battlemage_is_an_elite_that_only_shoots_harder_and_faster() -> void:
	arena = TestArena.new(self)
	var battlemage := arena.spawn(BATTLEMAGE, Vector3.ZERO) as Enemy
	var mage := arena.spawn(MAGE, Vector3(3, 0, 0)) as Enemy
	var elite_shot := battlemage.attack as RangedAttack
	var common_shot := mage.attack as RangedAttack

	assert_object(battlemage.get_node_or_null("Summoner")).is_null()
	assert_float(battlemage.get_max_health()).is_greater(10.0)
	assert_float(elite_shot.damage).is_greater(common_shot.damage)
	assert_float(elite_shot.cooldown).is_less(common_shot.cooldown)
	assert_float(battlemage.profile.attack_range).is_greater(mage.profile.attack_range)
	assert_str(battlemage.get_display_name()).is_equal("Mago de batalha")


func test_the_battlemage_hits_from_eleven_meters() -> void:
	await _shoots_from_afar(BATTLEMAGE, 11.0)


func test_every_new_group_has_four_enemies() -> void:
	for path in NEW_GROUPS:
		var group := (load(path) as PackedScene).instantiate()

		assert_int(group.find_children("*", "Enemy", false, false).size()).override_failure_message(path).is_equal(4)
		group.free()


func test_the_new_groups_bring_the_new_enemies() -> void:
	var casters := (load(CASTERS) as PackedScene).instantiate()
	var circle := (load(SUMMONER_CIRCLE) as PackedScene).instantiate()
	var squad := (load(BATTLEMAGE_SQUAD) as PackedScene).instantiate()
	var files := func(group: Node) -> Array: return group.get_children().map(func(n: Node) -> String: return n.scene_file_path)

	assert_array(files.call(casters)).contains([MAGE, ARCHER])
	assert_array(files.call(circle)).contains([SUMMONER])
	assert_array(files.call(squad)).contains([BATTLEMAGE])
	casters.free()
	circle.free()
	squad.free()


func test_the_levels_can_draw_the_new_groups() -> void:
	for path in LEVELS:
		var level := (load(path) as PackedScene).instantiate()
		var spawner := level.get_node("Encounters") as EncounterSpawner
		var groups := spawner.group_scenes.map(func(scene: PackedScene) -> String: return scene.resource_path)

		assert_array(groups).override_failure_message(path).contains(NEW_GROUPS)
		level.free()


# o tiro vai em quem ele está vendo, mesmo antes de terminar de virar o corpo para lá
func test_a_caster_aims_at_its_target_not_where_its_body_faces() -> void:
	arena = TestArena.new(self)
	var player := arena.spawn(TestArena.KNIGHT, Vector3(6, 0, 0))
	var mage := await _hunting(MAGE, player)
	mage.model.rotation.y = 0.0

	var aim := mage.get_aim_point()

	assert_float(aim.x).is_greater(4.0)
	assert_float(absf(aim.z)).is_less(1.5)


# o elite também arremessa o machado em quem está fora do alcance do golpe
const ELITE := "res://scenes/characters/enemies/skeleton_elite.tscn"


func _thrown_axes() -> Array[Node]:
	return arena.root.find_children("*", "Projectile", true, false).filter(func(node: Node) -> bool: return node.scene_file_path.ends_with("thrown_axe.tscn"))


func test_the_elite_throws_its_axe_at_a_player_out_of_reach() -> void:
	arena = TestArena.new(self)
	await arena.bake_navigation()
	var player := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 7.0))
	await _hunting(ELITE, player)

	var thrown := false
	for i in 180:
		await get_tree().physics_frame
		if not _thrown_axes().is_empty():
			thrown = true
			break

	assert_bool(thrown).is_true()


func test_the_elite_does_not_throw_at_a_player_right_next_to_it() -> void:
	arena = TestArena.new(self)
	await arena.bake_navigation()
	var player := arena.spawn(TestArena.KNIGHT, Vector3(0, 0, 1.4))
	await _hunting(ELITE, player)

	var thrown := false
	for i in 120:
		await get_tree().physics_frame
		thrown = thrown or not _thrown_axes().is_empty()

	assert_bool(thrown).is_false()
