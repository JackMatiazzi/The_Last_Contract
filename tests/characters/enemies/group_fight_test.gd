extends GdUnitTestSuite

# Cada grupo novo luta contra quatro aventureiros parados numa arena aberta.
# Confere o que só aparece com o grupo junto: os tiros acertam o grupo de aventureiros, nenhum
# inimigo machuca o outro e quem ataca de longe fica longe.

const CASTERS := "res://scenes/characters/enemies/groups/casters.tscn"
const SUMMONER_CIRCLE := "res://scenes/characters/enemies/groups/summoner_circle.tscn"
const BATTLEMAGE_SQUAD := "res://scenes/characters/enemies/groups/battlemage_squad.tscn"
const FIGHT_TIME := 8.0
## o toque que acorda cada inimigo no começo
const POKE := 0.1
## quem ataca de longe nunca chega a encostar
const RANGED_MIN_DISTANCE := 4.0

var arena: TestArena
var party: Array[Character] = []


func after_test() -> void:
	party.clear()
	RunState.adventurer = null
	RunState.reset()


func _start_fight(group_path: String) -> Array[Enemy]:
	arena = TestArena.new(self)
	await arena.bake_navigation()
	var classes := [TestArena.KNIGHT, TestArena.BARBARIAN, TestArena.MAGE, TestArena.ROGUE]
	for i in classes.size():
		party.append(arena.spawn(classes[i], Vector3(-3.0 + i * 2.0, 0, 11), 180.0))
	var group := (load(group_path) as PackedScene).instantiate() as Node3D
	arena.root.add_child(group)
	await arena.wait_physics(3)
	var enemies: Array[Enemy] = []
	enemies.assign(group.find_children("*", "Enemy", false, false))
	for enemy in enemies:
		enemy.take_damage(POKE, party[0])
	return enemies


func _party_damage() -> float:
	var total := 0.0
	for adventurer in party:
		total += adventurer.get_max_health() - adventurer.health
	return total


func _nearest_adventurer(enemy: Enemy) -> float:
	var nearest := INF
	for adventurer in party:
		nearest = minf(nearest, enemy.global_position.distance_to(adventurer.global_position))
	return nearest


func _fight_checks(group_path: String) -> void:
	var enemies := await _start_fight(group_path)

	await arena.wait_seconds(FIGHT_TIME)

	assert_float(_party_damage()).override_failure_message("%s não machucou ninguém" % group_path).is_greater(0.0)
	for enemy in enemies:
		assert_float(enemy.health).override_failure_message("%s foi ferido por um aliado" % enemy.name).is_greater_equal(enemy.get_max_health() - POKE - 0.001)
		if enemy.attack is RangedAttack:
			assert_float(_nearest_adventurer(enemy)).override_failure_message("%s chegou perto demais" % enemy.name).is_greater(RANGED_MIN_DISTANCE)


func test_the_casters_fight_together_without_hurting_each_other() -> void:
	await _fight_checks(CASTERS)


func test_the_summoner_circle_fights_together_without_hurting_each_other() -> void:
	await _fight_checks(SUMMONER_CIRCLE)


func test_the_battlemage_squad_fights_together_without_hurting_each_other() -> void:
	await _fight_checks(BATTLEMAGE_SQUAD)
