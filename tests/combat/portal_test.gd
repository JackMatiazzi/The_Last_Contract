extends GdUnitTestSuite

const PORTAL := preload("res://scenes/world/portal.tscn")
const BOLT := preload("res://scenes/combat/magic_bolt.tscn")

var arena: TestArena
var mage: Adventurer


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)
	mage = arena.spawn(TestArena.MAGE, Vector3.ZERO) as Adventurer
	await arena.wait_physics(3)


func after_test() -> void:
	Input.action_release("move_forward")


func _portals() -> Array[Node]:
	return arena.root.find_children("*", "Portal", true, false)


func test_the_mage_has_portal_on_secondary_and_keeps_magic_bolt_on_primary() -> void:
	assert_object(mage.secondary_attack).is_instanceof(PortalSpell)
	mage.next_ability()
	assert_object(mage.attack).is_instanceof(RangedAttack)


# cada portal mira para um lado: colados, a regra recusa o segundo
func _cast_toward(yaw_degrees: float) -> void:
	mage.camera_pivot.rotation.y = deg_to_rad(yaw_degrees)
	await arena.wait_physics(1)
	mage.use_secondary()
	var spell := mage.secondary_attack
	await arena.wait_seconds(spell.impact_delay + spell.cooldown)


func test_two_casts_open_a_linked_pair_on_the_ground() -> void:
	await _cast_toward(0.0)
	await _cast_toward(90.0)

	var portals := _portals()
	assert_int(portals.size()).is_equal(2)
	assert_bool((portals[0] as Portal).is_linked()).is_true()
	assert_float((portals[0] as Portal).global_position.y).is_equal_approx(0.0, 0.6)


func test_each_portal_costs_its_own_mana() -> void:
	mage.use_secondary()

	assert_float(mage.mana.current).is_equal_approx(mage.mana.maximum - mage.secondary_attack.cost_override, 0.01)


func test_a_third_cast_closes_the_old_pair() -> void:
	for yaw in [0.0, 90.0, 180.0]:
		await _cast_toward(yaw)

	var alive := _portals().filter(func(portal: Node) -> bool: return not portal.is_queued_for_deletion())
	assert_int(alive.size()).is_equal(1)
	assert_bool((alive[0] as Portal).is_linked()).is_false()


func test_walking_into_a_portal_comes_out_of_the_other() -> void:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = Vector3(0, 0, 3)
	exit.global_position = Vector3(12, 0, 0)
	entry.link = exit
	exit.link = entry
	await arena.wait_physics(2)

	mage.global_position = Vector3(0, 0, 3)
	await arena.wait_physics(3)

	assert_float(mage.global_position.distance_to(exit.global_position)).is_less(2.0)


# os mortos-vivos também atravessam: o portal vira armadilha e atalho para os dois lados
func test_skeletons_travel_through_the_portal_too() -> void:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = Vector3(-6, 0, 0)
	exit.global_position = Vector3(12, 0, 0)
	entry.link = exit
	exit.link = entry
	var skeleton := arena.spawn(TestArena.SKELETON, Vector3(-6, 0, 0))
	await arena.wait_physics(4)

	assert_float(skeleton.global_position.distance_to(exit.global_position)).is_less(2.0)


# os dois portais colados faziam quem saía de um entrar direto no outro, num vai e volta que empilhava
# os inimigos e jogava todos para cima da muralha: o segundo precisa abrir longe do primeiro
func test_the_second_portal_does_not_open_right_next_to_the_first() -> void:
	await _cast_toward(0.0)
	await _cast_toward(0.0)

	assert_int(_portals().size()).is_equal(1)
	assert_bool((_portals()[0] as Portal).is_linked()).is_false()


func test_a_refused_portal_gives_the_mana_back() -> void:
	await _cast_toward(0.0)
	var after_first := mage.mana.current

	await _cast_toward(0.0)

	assert_float(mage.mana.current).is_greater_equal(after_first)


# a borda da regra: com o primeiro portal a 3,9 m da mira não abre, a 4,1 m abre
func test_the_second_portal_opens_only_from_four_meters_away() -> void:
	await _cast_toward(0.0)
	var first := _portals()[0] as Portal
	var aimed := first.global_position

	first.global_position = aimed + Vector3.RIGHT * 3.9
	await _cast_toward(0.0)
	assert_int(_portals().size()).is_equal(1)

	first.global_position = aimed + Vector3.RIGHT * 4.1
	await _cast_toward(0.0)
	assert_int(_portals().size()).is_equal(2)
	assert_bool(first.is_linked()).is_true()


# quem chega junto não sai no mesmo ponto: um em cima do outro, a física empurrava todos para cima
func test_two_skeletons_arriving_together_land_side_by_side_on_the_ground() -> void:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = Vector3(-6, 0, 0)
	exit.global_position = Vector3(12, 0, 0)
	entry.link = exit
	exit.link = entry
	var first := arena.spawn(TestArena.SKELETON, Vector3(-6, 0, 0))
	var second := arena.spawn(TestArena.SKELETON, Vector3(-6, 0, 0.3))
	await arena.wait_physics(10)

	for skeleton: Character in [first, second]:
		assert_float(skeleton.global_position.distance_to(exit.global_position)).is_less(3.5)
		assert_float(skeleton.global_position.y).is_less(0.5)
	assert_float(first.global_position.distance_to(second.global_position)).is_greater(0.6)


func test_crowded_portal_does_not_choose_a_disconnected_side_exit() -> void:
	var exit := PORTAL.instantiate() as Portal
	exit.position = Vector3(0, 0, -10)
	arena.root.add_child(exit)
	arena.add_wall(Vector3(0.5, 1, -10), Vector3(0.05, 2, 8))
	var region := arena.root.get_node("Navigation") as NavigationRegion3D
	var mesh := NavigationMesh.new()
	mesh.set_vertices(PackedVector3Array([
		Vector3(-5, 0, -14), Vector3(-5, 0, -6), Vector3(0.1, 0, -6), Vector3(0.1, 0, -14),
		Vector3(0.9, 0, -14), Vector3(0.9, 0, -6), Vector3(5, 0, -6), Vector3(5, 0, -14)
	]))
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	mesh.add_polygon(PackedInt32Array([4, 5, 6, 7]))
	region.navigation_mesh = mesh
	var traveler := arena.spawn(TestArena.SKELETON, Vector3(-4, 0, 0))
	await arena.wait_physics(6)

	var center := exit.exit_point()
	assert_vector(exit.free_exit_point(mage)).is_equal_approx(center, Vector3.ONE * 0.01)
	assert_vector(exit.free_exit_point(traveler)).is_equal_approx(center - Vector3.RIGHT * Portal.CROWD_STEP, Vector3.ONE * 0.01)
	assert_vector(exit.free_exit_point(traveler)).is_equal_approx(center - Vector3.RIGHT * Portal.CROWD_STEP * 2.0, Vector3.ONE * 0.01)
	assert_that(exit.free_exit_point(traveler)).is_null()


# elite e Necromante não atravessam: o portal é rota de fuga, não traz o perigo junto
func test_elites_and_the_boss_stay_on_their_side() -> void:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = Vector3(-6, 0, 0)
	exit.global_position = Vector3(12, 0, 0)
	entry.link = exit
	exit.link = entry
	var elite := arena.spawn("res://scenes/characters/enemies/skeleton_elite.tscn", Vector3(-6, 0, 0))
	var boss := arena.spawn("res://scenes/characters/enemies/necromancer.tscn", Vector3(-6, 0, 0.4))
	# o mago de batalha é o mago elite: parece elite e segue a regra deles
	var battlemage := arena.spawn("res://scenes/characters/enemies/skeleton_battlemage.tscn", Vector3(-6, 0, -0.4))
	for enemy: Enemy in [elite, boss, battlemage]:
		enemy.ai_enabled = false
	await arena.wait_physics(4)

	assert_float(elite.global_position.distance_to(exit.global_position)).is_greater(10.0)
	assert_float(boss.global_position.distance_to(exit.global_position)).is_greater(10.0)
	assert_float(battlemage.global_position.distance_to(exit.global_position)).is_greater(10.0)


func test_coming_out_does_not_send_you_straight_back() -> void:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = Vector3(0, 0, 3)
	exit.global_position = Vector3(12, 0, 0)
	entry.link = exit
	exit.link = entry
	await arena.wait_physics(2)

	mage.global_position = Vector3(0, 0, 3)
	await arena.wait_physics(3)
	mage.global_position = exit.global_position
	await arena.wait_physics(3)

	assert_float(mage.global_position.distance_to(exit.global_position)).is_less(2.0)


func test_a_wall_in_front_of_the_exit_lands_you_on_the_portal() -> void:
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(exit)
	exit.global_position = Vector3(-10, 0, -10)
	arena.add_wall(Vector3(-10, 1, -10.9), Vector3(4, 2, 0.3))
	exit.look_at(Vector3(-10, 0, -12))
	await arena.wait_physics(2)

	assert_float(exit.exit_point().distance_to(exit.global_position)).is_less(0.5)


# sem mapa de navegação (arena de teste, cena solta), a saída em chão aberto continua à frente
func test_without_navigation_the_exit_stays_in_front_on_open_ground() -> void:
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(exit)
	exit.global_position = Vector3(-10, 0, -10)
	exit.look_at(Vector3(-10, 0, -12))
	await arena.wait_physics(2)

	assert_float(exit.exit_point().distance_to(exit.global_position)).is_equal_approx(Portal.EXIT_OFFSET, 0.1)


func test_a_linked_portal_shows_the_other_side() -> void:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = Vector3(0, 0, -4)
	exit.global_position = Vector3(12, 0, 0)
	await arena.wait_physics(2)
	assert_int(entry.view.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)

	entry.link = exit
	exit.link = entry
	# a camera do outro lado anda no _process: espera quadros de desenho, nao so de fisica
	for i in 3:
		await arena.root.get_tree().process_frame

	var eye := entry.get_viewport().get_camera_3d()
	assert_int(entry.view.render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	assert_float(entry.view_camera.global_position.distance_to(exit.global_position)) \
		.is_equal_approx(eye.global_position.distance_to(entry.global_position), 0.05)



func _linked_pair(entry_spot: Vector3, exit_spot: Vector3, exit_turn := 0.0) -> Array[Portal]:
	var entry := PORTAL.instantiate() as Portal
	var exit := PORTAL.instantiate() as Portal
	arena.root.add_child(entry)
	arena.root.add_child(exit)
	entry.global_position = entry_spot
	exit.global_position = exit_spot
	exit.rotation.y = exit_turn
	entry.link = exit
	exit.link = entry
	return [entry, exit]


func _fire(origin: Vector3, direction: Vector3) -> Projectile:
	var bolt := BOLT.instantiate() as Projectile
	arena.root.add_child(bolt)
	bolt.launch(mage, origin, direction, 1.0, 0)
	return bolt


func test_a_shot_into_the_portal_comes_out_of_the_other_one() -> void:
	_linked_pair(Vector3(0, 0, -4), Vector3(12, 0, 0))
	await arena.wait_physics(2)

	var bolt := _fire(Vector3(0, 1.1, -2), Vector3.FORWARD)
	await arena.wait_physics(20)

	assert_float(bolt.global_position.x).is_equal_approx(12.0, 0.3)
	assert_float(bolt.global_position.z).is_less(0.0)


func test_the_shot_leaves_facing_where_the_exit_faces() -> void:
	_linked_pair(Vector3(0, 0, -4), Vector3(12, 0, 0), PI / 2.0)
	await arena.wait_physics(2)

	var bolt := _fire(Vector3(0, 1.1, -2), Vector3.FORWARD)
	await arena.wait_physics(20)

	assert_float(bolt.global_position.x).is_less(12.0)
	assert_float((-bolt.global_basis.z).x).is_less(-0.9)


func test_a_shot_from_behind_also_leaves_through_the_front() -> void:
	_linked_pair(Vector3(0, 0, -4), Vector3(12, 0, 0))
	await arena.wait_physics(2)

	var bolt := _fire(Vector3(0, 1.1, -6), Vector3.BACK)
	await arena.wait_physics(20)

	assert_float(bolt.global_position.x).is_equal_approx(12.0, 0.3)
	assert_float(bolt.global_position.z).is_less(0.0)


func test_a_shot_beside_the_ring_does_not_travel() -> void:
	_linked_pair(Vector3(0, 0, -4), Vector3(12, 0, 0))
	await arena.wait_physics(2)

	var bolt := _fire(Vector3(2, 1.1, -2), Vector3.FORWARD)
	await arena.wait_physics(20)

	assert_float(bolt.global_position.x).is_equal_approx(2.0, 0.01)


func test_a_portal_without_a_pair_lets_the_shot_go_straight() -> void:
	var lonely := PORTAL.instantiate() as Portal
	arena.root.add_child(lonely)
	lonely.global_position = Vector3(0, 0, -4)
	await arena.wait_physics(2)

	var bolt := _fire(Vector3(0, 1.1, -2), Vector3.FORWARD)
	await arena.wait_physics(20)

	assert_float(bolt.global_position.x).is_equal_approx(0.0, 0.01)
	assert_float(bolt.global_position.z).is_less(-5.0)


func test_the_bar_above_the_portal_empties_as_it_closes() -> void:
	var pair := _linked_pair(Vector3(0, 0, -4), Vector3(8, 0, 0))
	var portal := pair[0]
	portal.lifetime = 1.0
	var full := portal.time_fill.region_rect.size.x

	for i in 30:
		await arena.root.get_tree().process_frame

	assert_float(portal.time_left_fraction()).is_less(1.0)
	assert_float(portal.time_fill.region_rect.size.x).is_less(full)



# o tempo só corre com o par ligado: quem põe o primeiro portal tem tempo para escolher o segundo
func test_a_lone_portal_does_not_start_closing() -> void:
	var portal := PORTAL.instantiate() as Portal
	portal.lifetime = 0.5
	arena.root.add_child(portal)

	await arena.wait_seconds(0.8)

	assert_bool(is_instance_valid(portal)).is_true()
	assert_float(portal.time_left_fraction()).is_equal(1.0)


func test_the_pair_starts_closing_once_the_second_portal_links() -> void:
	var pair := _linked_pair(Vector3(0, 0, -4), Vector3(8, 0, 0))
	pair[0].lifetime = 0.5
	pair[1].lifetime = 0.5

	await arena.wait_seconds(0.3)

	assert_float(pair[0].time_left_fraction()).is_less(1.0)
	assert_float(pair[1].time_left_fraction()).is_less(1.0)


# o tiro de um aventureiro que atravessa o portal pode acertar outro aventureiro do outro lado
func test_a_shot_through_the_portal_can_hit_an_ally_on_the_other_side() -> void:
	var rogue := arena.spawn(TestArena.ROGUE, Vector3(12, 0, -2.5)) as Adventurer
	_linked_pair(Vector3(0, 0, -4), Vector3(12, 0, 0))
	await arena.wait_physics(3)
	var health := rogue.health

	var bolt := _fire(Vector3(0, 1.1, -2), Vector3.FORWARD)
	bolt.collision_mask = 4
	await arena.wait_physics(30)

	assert_float(rogue.health).is_less(health)


func test_a_shot_that_does_not_cross_a_portal_still_ignores_allies() -> void:
	var rogue := arena.spawn(TestArena.ROGUE, Vector3(0, 0, -3)) as Adventurer
	await arena.wait_physics(3)
	var health := rogue.health

	var bolt := _fire(Vector3(0, 1.1, -1), Vector3.FORWARD)
	bolt.collision_mask = 4
	await arena.wait_physics(20)

	assert_float(rogue.health).is_equal(health)


# topo de muralha entra no mapa de navegação como ilha: mirar lá em cima não abre portal
func test_no_portal_on_top_of_a_wall_the_mage_cannot_walk_to() -> void:
	arena.add_wall(Vector3(0, 1.5, 8), Vector3(12, 3, 4))
	await arena.bake_navigation()
	var spell := mage.secondary_attack as PortalSpell

	var on_wall: Variant = spell._walkable_from(mage, Vector3(0, 3, 8))
	var on_ground: Variant = spell._walkable_from(mage, Vector3(0, 0, -6))

	assert_bool(on_wall).is_false()
	assert_bool(on_ground).is_true()
