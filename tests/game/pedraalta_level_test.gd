extends GdUnitTestSuite

const LEVEL := preload("res://scenes/levels/pedraalta_level.tscn")
const MIMIC := preload("res://scenes/characters/enemies/mimic.tscn")
const PORTAL := preload("res://scenes/world/portal.tscn")

var level: Node3D
var session: GameSession
var encounters: EncounterSpawner


func before_test() -> void:
	RunState.reset()
	RunState.adventurer = load("res://resources/adventurers/knight.tres")
	level = auto_free(LEVEL.instantiate())
	add_child(level)
	session = level.get_node("GameSession")
	encounters = level.get_node("Encounters")
	for i in 3:
		await await_idle_frame()


func after_test() -> void:
	RunState.adventurer = null
	RunState.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.action_release("move_forward")


func _groups() -> Array[Node]:
	return encounters.get_children().filter(func(child: Node) -> bool: return child is EnemyGroup)


func _zone_of(group: Node) -> StringName:
	var nearest: Marker3D = null
	for spot: Marker3D in encounters.group_spots.get_children():
		if nearest == null or spot.global_position.distance_to(group.global_position) < nearest.global_position.distance_to(group.global_position):
			nearest = spot
	return nearest.get_meta("zone")


func _wait_for_navigation() -> RID:
	var map := level.get_world_3d().navigation_map
	var probe: Vector3 = encounters.player_spots.get_child(0).global_position
	for frame in 60:
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0:
			break
		await get_tree().physics_frame
	return map


func test_every_group_spot_belongs_to_a_zone() -> void:
	for spot: Marker3D in encounters.group_spots.get_children():
		assert_bool(spot.has_meta("zone")).override_failure_message("%s sem zona" % spot.name).is_true()


# todas as zonas têm grupo; os grupos a mais vão para zonas diferentes, nunca três na mesma
func _check_spread(zones: Array) -> void:
	assert_int(zones.size()).is_equal(encounters.group_count)
	for zone in ["A", "B", "C", "D", "E"]:
		assert_int(zones.count(zone)).override_failure_message("zona %s sem grupo" % zone).is_greater_equal(1)
	for zone in zones:
		assert_int(zones.count(zone)).override_failure_message("grupos demais na zona %s" % zone).is_less_equal(2)


func test_every_zone_gets_a_group_and_the_extras_spread_out() -> void:
	_check_spread(_groups().map(_zone_of))


func test_the_spread_holds_on_every_draw() -> void:
	var player_position := session.player.global_position
	for draw in 20:
		for group in _groups():
			group.free()
		_check_spread(encounters.spawn_groups(player_position).map(_zone_of))


func test_every_group_spot_can_walk_to_every_player_spot() -> void:
	var map := await _wait_for_navigation()

	for group_spot: Marker3D in encounters.group_spots.get_children():
		for player_spot: Marker3D in encounters.player_spots.get_children():
			var path := NavigationServer3D.map_get_path(map, group_spot.global_position, player_spot.global_position, true)
			var reached := not path.is_empty() and path[-1].distance_to(player_spot.global_position) < 1.5
			assert_bool(reached).override_failure_message("%s nao chega em %s" % [group_spot.name, player_spot.name]).is_true()


func test_the_boss_spot_is_reachable_from_the_entrance() -> void:
	var map := await _wait_for_navigation()
	var start: Vector3 = encounters.player_spots.get_child(0).global_position
	var boss := encounters.boss_spot.global_position

	var path := NavigationServer3D.map_get_path(map, start, boss, true)

	assert_bool(not path.is_empty() and path[-1].distance_to(boss) < 1.5).is_true()


func test_arena_blocks_walking_and_portals_until_the_last_group_falls() -> void:
	var map := await _wait_for_navigation()
	var arena := session.boss_arena
	var center := arena.global_position
	var approach := NavigationServer3D.map_get_closest_point(map, Vector3(0, 12, -49))
	var mage := (load(TestArena.MAGE) as PackedScene).instantiate() as Adventurer
	session.add_child(mage)
	mage.global_position = approach
	mage.camera_pivot.global_position = approach + Vector3.UP * 1.5
	mage.camera.global_position = mage.camera_pivot.global_position
	mage.camera.h_offset = 0.0
	mage.camera.v_offset = 0.0
	mage.camera.look_at(center)
	var spell := mage.secondary_attack as PortalSpell
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 13.5, -49), center + Vector3.UP * 1.48, 1)
	var space := level.get_world_3d().direct_space_state

	assert_bool(session.allows_portal_at(center)).is_false()
	assert_object(space.intersect_ray(ray).get("collider")).is_same(arena)
	var blocked_spot: Variant = spell._ground_spot(mage)
	assert_bool(blocked_spot == null or not arena.contains(blocked_spot)).is_true()

	for i in range(session._groups_left - 1):
		session._on_group_cleared()
	assert_bool(arena.locked).is_true()
	assert_object(session.boss).is_null()

	session._on_group_cleared()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_bool(arena.locked).is_false()
	assert_bool(session.allows_portal_at(center)).is_true()
	assert_bool(space.intersect_ray(ray).get("collider") != arena).is_true()
	assert_object(session.boss).is_not_null()

	mage.camera_pivot.global_position = approach + Vector3.UP * 1.5
	mage.camera.global_position = mage.camera_pivot.global_position
	mage.camera.h_offset = 0.0
	mage.camera.look_at(center)
	var allowed_spot: Variant = spell._ground_spot(mage)
	assert_bool(allowed_spot is Vector3 and arena.contains(allowed_spot)).is_true()


func test_the_necromancer_stays_inside_the_arena_when_pushed() -> void:
	var arena := session.boss_arena
	session._summon_boss()
	var boss := session.boss
	boss.ai_enabled = false
	boss.global_position = arena.global_position + Vector3.RIGHT * 10.0
	boss.velocity = Vector3(10.0, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_bool(arena.contains(boss.global_position)).is_true()
	assert_float(boss.velocity.x).is_less_equal(0.0)


func test_every_spot_stands_on_open_ground() -> void:
	var space := level.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1

	for spot: Marker3D in encounters.group_spots.get_children() + encounters.player_spots.get_children():
		query.transform = Transform3D(Basis(), spot.global_position + Vector3.UP * 1.0)
		assert_array(space.intersect_shape(query)).override_failure_message("%s dentro de algo" % spot.name).is_empty()


func test_the_terraces_climb_toward_the_boss() -> void:
	var heights := {}
	for spot: Marker3D in encounters.group_spots.get_children():
		heights[spot.get_meta("zone")] = spot.global_position.y

	assert_float(heights[&"B"]).is_greater(heights[&"A"])
	assert_float(heights[&"C"]).is_greater(heights[&"B"])
	assert_float(heights[&"D"]).is_greater(heights[&"C"])
	assert_float(encounters.boss_spot.global_position.y).is_greater(heights[&"D"])


func test_the_knight_walks_up_the_first_ramp() -> void:
	var knight := session.player
	knight.global_position = Vector3(-8, 0.3, 30)
	knight.camera_pivot.rotation.y = 0.0
	await get_tree().physics_frame

	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
		if knight.global_position.z < 17.0:
			break
	Input.action_release("move_forward")

	assert_float(knight.global_position.y).is_greater(2.5)


func test_the_entrance_zone_always_gets_the_easiest_group() -> void:
	var player_position := session.player.global_position
	for draw in 10:
		for group in _groups():
			group.free()
		for group in encounters.spawn_groups(player_position):
			if _zone_of(group) == &"A":
				assert_str(group.scene_file_path).is_equal(encounters.easy_group.resource_path)


func test_entrance_spots_keep_a_safe_margin_from_the_spawn() -> void:
	for spot: Marker3D in encounters.group_spots.get_children():
		if spot.get_meta("zone") != &"A":
			continue
		for player_spot: Marker3D in encounters.player_spots.get_children():
			assert_float(spot.global_position.distance_to(player_spot.global_position)).is_greater(encounters.min_distance_from_player + 3.0)


func test_the_crevasse_has_deep_water_that_kills() -> void:
	var water := level.find_child("AguaDaFenda", true, false) as KillZone
	assert_object(water).is_not_null()
	var knight := session.player
	knight.global_position = Vector3(4, 7.5, -36)

	for i in 120:
		await get_tree().physics_frame
		if knight.is_dead:
			break

	assert_bool(knight.is_dead).is_true()


# em grupo, quem ainda está de pé precisa saber quem caiu para ir reviver
func _ally() -> Adventurer:
	var ally := load("res://scenes/characters/adventurers/mage.tscn").instantiate() as Adventurer
	ally.position = session.player.global_position + Vector3(2, 0.3, 0)
	session.add_child(ally)
	ally.set_display_name("Brann")
	session.players.append(ally)
	session.watch_player(ally)
	return ally


func test_when_an_ally_falls_the_screen_shows_their_name() -> void:
	var ally := _ally()
	await get_tree().physics_frame

	ally.take_damage(999.0)

	assert_str(session.hud.announcement.text).contains("Brann caiu")


func test_when_you_fall_with_allies_standing_the_screen_says_so() -> void:
	_ally()
	await get_tree().physics_frame

	session.player.take_damage(999.0)

	assert_str(session.hud.announcement.text).contains("Você caiu")


func _chests() -> Array[Node]:
	return encounters.get_children().filter(func(child: Node) -> bool: return child is Chest or child is Mimic)


func test_solo_draws_five_chests_and_one_mimic() -> void:
	var chests := _chests()

	assert_int(chests.filter(func(chest: Node) -> bool: return chest is Chest).size()).is_equal(encounters.chest_count)
	assert_int(chests.filter(func(chest: Node) -> bool: return chest is Mimic).size()).is_equal(1)
	assert_int(encounters.chest_spots.get_child_count()).is_equal(11)


# quatro jogadores: os cinco baús continuam e entram quatro mímicos, em pontos que mudam a cada sorteio
func test_each_player_adds_a_mimic_in_a_drawn_spot() -> void:
	for chest in _chests():
		chest.free()
	var mimic_spots := {}
	for draw in 6:
		var spawned := encounters.spawn_chests(4)
		var mimics := spawned.filter(func(chest: Node3D) -> bool: return chest is Mimic)
		assert_int(spawned.size()).is_equal(encounters.chest_count + 4)
		assert_int(mimics.size()).is_equal(4)
		for mimic: Node3D in mimics:
			mimic_spots[Vector2i(roundi(mimic.global_position.x), roundi(mimic.global_position.z))] = true
		for chest in spawned:
			chest.free()

	assert_int(mimic_spots.size()).is_greater(4)


func test_the_chests_land_on_the_drawn_spots() -> void:
	var spots := encounters.chest_spots.get_children().map(func(spot: Marker3D) -> Vector3: return spot.global_position)

	# o mímico tem física e assenta no chão: compara só a posição no plano
	for chest: Node3D in _chests():
		var ground := Vector2(chest.global_position.x, chest.global_position.z)
		assert_bool(spots.any(func(spot: Vector3) -> bool: return Vector2(spot.x, spot.z).distance_to(ground) < 0.3)).is_true()


# no co-op cada máquina sorteia sozinha: com a mesma semente os baús e o mímico têm de sair iguais
func test_the_same_seed_draws_the_same_chests_on_every_machine() -> void:
	for chest in _chests():
		chest.free()
	var draw := func() -> Array:
		seed(4242)
		var spawned := encounters.spawn_chests()
		var layout := spawned.map(func(chest: Node3D) -> String: return "%s@%s" % [chest.name, chest.global_position])
		for chest in spawned:
			chest.free()
		return layout

	var first: Array = draw.call()
	var second: Array = draw.call()

	assert_array(first).is_equal(second)


# o portal do mago sobe terraço, mas não põe ninguém em cima da muralha nem do paredão norte
func test_the_portal_reaches_terraces_but_not_the_walls() -> void:
	await _wait_for_navigation()
	var mage := (load("res://scenes/characters/adventurers/mage.tscn") as PackedScene).instantiate() as Adventurer
	level.add_child(mage)
	mage.global_position = Vector3(0, 0, 30)
	var spell := PortalSpell.new()

	assert_bool(spell._walkable_from(mage, Vector3(9, 6, -22))).is_true()
	assert_bool(spell._walkable_from(mage, Vector3(-23.5, 18, -9))).is_false()
	assert_bool(spell._walkable_from(mage, Vector3(0, 20, -71.5))).is_false()
	spell.free()


func _structures_around(grid: GridMap, spot: Vector3, radius: float) -> int:
	var count := 0
	var center := grid.local_to_map(grid.to_local(spot))
	var reach := ceili(radius / grid.cell_size.x) + 1
	for dx in range(-reach, reach + 1):
		for dy in range(-1, 5):
			for dz in range(-reach, reach + 1):
				var cell := center + Vector3i(dx, dy, dz)
				if grid.get_cell_item(cell) == GridMap.INVALID_CELL_ITEM:
					continue
				var world := grid.to_global(grid.map_to_local(cell))
				if Vector2(world.x - spot.x, world.z - spot.z).length() < radius:
					count += 1
	return count


func _on_navigation(map: RID, point: Vector3) -> bool:
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length() < 0.35 and absf(closest.y - point.y) < 0.7


# baú colado em casa afundava na parede e soltava a poção lá dentro; na beira, a poção caía do terraço
func test_every_chest_spot_stands_clear_with_room_for_the_loot() -> void:
	var map := await _wait_for_navigation()
	var houses := level.get_node("Navigation/Pedraalta/Estrutura") as GridMap
	var spawn: Vector3 = encounters.player_spots.get_child(0).global_position
	for spot: Marker3D in encounters.chest_spots.get_children():
		var at := spot.global_position
		var loot := spot.global_transform * Vector3(0, 0, 1.6)
		var path := NavigationServer3D.map_get_path(map, spawn, at, true)
		var end: Vector3 = path[path.size() - 1] if not path.is_empty() else Vector3.INF

		assert_int(_structures_around(houses, at, 2.5)).override_failure_message("%s colado numa casa" % spot.name).is_equal(0)
		assert_bool(_on_navigation(map, at)).override_failure_message("%s fora do chão andável" % spot.name).is_true()
		assert_float(Vector2(end.x - at.x, end.z - at.z).length()).override_failure_message("%s sem caminho a pé" % spot.name).is_less(0.5)
		assert_bool(_on_navigation(map, loot)).override_failure_message("%s solta a poção fora do chão" % spot.name).is_true()


# caído com o grupo de pé, a câmera passa a seguir um aliado; o ataque troca de aliado e reviver volta para si
func test_a_fallen_player_watches_the_allies_still_standing() -> void:
	var first := _ally()
	var second := _ally()
	second.set_display_name("Iris")
	await get_tree().physics_frame

	session.player.take_damage(999.0)
	assert_object(session.player.camera_subject).is_same(first)
	assert_str(session.hud.announcement.text).contains("Assistindo Brann")

	# sem mouse capturado (como no CI) o ataque só troca de aliado no controle
	var device_before: int = Settings.input_device
	Settings.input_device = Settings.InputDevice.GAMEPAD
	session._unhandled_input(_attack_press())
	Settings.input_device = device_before
	assert_object(session.player.camera_subject).is_same(second)

	second.take_damage(999.0)
	assert_object(session.player.camera_subject).is_same(first)

	session.player.revive(5.0)
	assert_object(session.player.camera_subject).is_null()



func test_when_the_watched_ally_leaves_the_camera_moves_to_another() -> void:
	var first := _ally()
	var second := _ally()
	await get_tree().physics_frame
	first.name = "4242"
	session.player.take_damage(999.0)
	assert_object(session.player.camera_subject).is_same(first)

	session._on_player_left(4242)

	assert_object(session.player.camera_subject).is_same(second)

func _attack_press() -> InputEventAction:
	var press := InputEventAction.new()
	press.action = "attack"
	press.pressed = true
	return press


# a sala online caiu por um instante: o jogador vê que o jogo está voltando, e o grupo vê quem caiu
func test_a_dropped_connection_shows_while_the_game_resumes() -> void:
	Net.connection_resuming.emit(true)
	assert_str(session.hud.announcement.text).is_equal(GameSession.RESUMING_LINE)

	Net.connection_resuming.emit(false)
	assert_str(session.hud.announcement.text).is_equal(GameSession.RESUMED_LINE)


func test_an_ally_losing_the_connection_is_announced_until_they_return() -> void:
	Net.player_away.emit(1, true)
	assert_str(session.hud.announcement.text).contains("perdeu a conexão")

	Net.player_away.emit(1, false)
	assert_str(session.hud.announcement.text).contains("voltou")


# com o aventureiro embaixo do terraço, o mímico desce pela rampa em vez de empacar na beirada
func test_an_awake_mimic_comes_down_the_ramp_after_the_player() -> void:
	var knight := session.player
	# os esqueletos ficam parados no teste e fechariam o caminho
	for group in _groups():
		group.free()
	knight.global_position = Vector3(-2, 3.3, -4)
	var map := await _wait_for_navigation()
	var mimic: Mimic = MIMIC.instantiate()
	level.add_child(mimic)
	mimic.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(9, 6, -20)) + Vector3.UP * 0.2
	assert_float(mimic.global_position.y).is_greater(5.0)
	await get_tree().physics_frame

	mimic._wake(knight)
	for i in 900:
		await get_tree().physics_frame
		knight.heal(knight.get_max_health())
		if mimic.global_position.distance_to(knight.global_position) < mimic.strike_range:
			break

	assert_float(mimic.global_position.distance_to(knight.global_position)).is_less(mimic.strike_range)


# de qualquer ponto de baú, o mímico acordado chega a quem bateu e recuou uns metros por chão andável
func test_an_awake_mimic_reaches_the_player_from_every_chest_spot() -> void:
	for group in _groups():
		group.free()
	for chest in level.find_children("*", "Mimic", true, false) + level.find_children("*", "Chest", true, false):
		chest.free()
	var map := await _wait_for_navigation()
	var knight := session.player
	for spot: Marker3D in encounters.chest_spots.get_children():
		var goal := _walkable_point_near(map, spot.global_position)
		var mimic: Mimic = MIMIC.instantiate()
		level.add_child(mimic)
		mimic.global_position = spot.global_position + Vector3.UP * 0.3
		await get_tree().physics_frame
		mimic._wake(knight)
		for i in 600:
			knight.global_position = goal + Vector3.UP * 0.3
			knight.velocity = Vector3.ZERO
			knight.heal(knight.get_max_health())
			await get_tree().physics_frame
			if mimic.global_position.distance_to(knight.global_position) < mimic.strike_range:
				break

		assert_float(mimic.global_position.distance_to(knight.global_position)).override_failure_message("o mímico do ponto %s travou em %s" % [spot.name, mimic.global_position]).is_less(mimic.strike_range)
		mimic.free()


# um ponto a mais de 4 m que a navegação liga ao baú: perto de casa, o mais próximo pode cair num chão isolado
func _walkable_point_near(map: RID, origin: Vector3) -> Vector3:
	for offset: Vector3 in [Vector3(6, 0, 6), Vector3(-6, 0, 6), Vector3(6, 0, -6), Vector3(-6, 0, -6), Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8)]:
		var candidate := NavigationServer3D.map_get_closest_point(map, origin + offset)
		var route := NavigationServer3D.map_get_path(map, origin, candidate, true)
		if not route.is_empty() and route[route.size() - 1].distance_to(candidate) < 0.5 and candidate.distance_to(origin) > 4.0:
			return candidate
	return origin


# a saída do portal ficava 1,4 m à frente dele mesmo com muralha, parapeito ou beira de rampa ali:
# soldado e mago de batalha saíam em cima da muralha, na borda do mapa. Em qualquer chão da vila e em
# qualquer direção, quem sai fica em chão que a navegação liga ao portal por um caminho curto
func test_the_portal_exit_always_lands_on_walkable_ground_next_to_the_portal() -> void:
	var map := await _wait_for_navigation()
	var entry: Portal = auto_free(PORTAL.instantiate())
	var exit: Portal = auto_free(PORTAL.instantiate())
	level.add_child(entry)
	level.add_child(exit)
	entry.link = exit
	exit.link = entry
	var stranded: Array[String] = []
	var ahead := 0
	for x in range(-27, 28, 3):
		for z in range(-66, 58, 3):
			var spot := NavigationServer3D.map_get_closest_point(map, Vector3(x, 20, z))
			if Vector2(spot.x - x, spot.z - z).length() > 1.0:
				continue
			for k in 8:
				var facing := Vector3(sin(k * TAU / 8.0), 0, cos(k * TAU / 8.0))
				exit.global_position = spot
				exit.look_at(spot + facing)
				var point := exit.exit_point()
				if point.is_equal_approx(spot):
					continue
				ahead += 1
				var on_nav := NavigationServer3D.map_get_closest_point(map, point)
				var path := NavigationServer3D.map_get_path(map, spot, on_nav, true)
				var walk := 0.0
				for i in range(1, path.size()):
					walk += path[i - 1].distance_to(path[i])
				if on_nav.distance_to(point) > 0.8 or walk > Portal.EXIT_MAX_WALK + 0.5:
					stranded.append("%s virado para %s saiu em %s" % [spot, facing, point])

	assert_array(stranded).is_empty()
	# em chão aberto a saída continua à frente: cair sempre em cima do portal também passaria acima
	assert_int(ahead).is_greater(300)
