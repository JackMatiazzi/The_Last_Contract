extends GdUnitTestSuite

const HUD := preload("res://scenes/ui/hud.tscn")

var arena: TestArena


func before_test() -> void:
	RunState.reset()
	arena = TestArena.new(self)


func after_test() -> void:
	RunState.reset()


func _spawn_hud(player: Character) -> Hud:
	var hud: Hud = HUD.instantiate()
	hud.player = player
	arena.root.add_child(hud)
	return hud


func test_shows_attempt_and_full_health() -> void:
	var hud := _spawn_hud(arena.spawn(TestArena.KNIGHT, Vector3.ZERO))

	assert_str(hud.attempt_label.text).is_equal("Tentativa I")
	assert_str(hud.health_label.text).is_equal("10 / 10")


func test_follows_damage() -> void:
	var player := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var hud := _spawn_hud(player)

	player.take_damage(3.0)

	assert_str(hud.health_label.text).is_equal("7 / 10")
	assert_float(hud.health_bar.value).is_equal(7.0)


func test_hides_buff_title_without_buffs() -> void:
	var hud := _spawn_hud(arena.spawn(TestArena.KNIGHT, Vector3.ZERO))

	assert_int(hud.buff_list.get_child_count()).is_equal(0)


func test_lists_buffs_once_as_chips_with_stacks() -> void:
	var sharp: Buff = load("res://resources/buffs/lamina_afiada.tres")
	RunState.start_next_attempt(sharp)
	RunState.start_next_attempt(sharp)
	var hud := _spawn_hud(arena.spawn(TestArena.KNIGHT, Vector3.ZERO))

	assert_str(hud.attempt_label.text).is_equal("Tentativa III")
	assert_int(hud.buff_list.get_child_count()).is_equal(1)
	assert_str((hud.buff_list.get_child(0) as Label).text).is_equal("Lâmina Afiada ×2")


func test_boss_warning_stays_longer_and_plays_a_cue() -> void:
	var hud := _spawn_hud(arena.spawn(TestArena.KNIGHT, Vector3.ZERO))

	hud.announce_boss("O Necromante despertou na praça")

	assert_float(Hud.BOSS_ANNOUNCE_HOLD).is_greater(Hud.ANNOUNCE_HOLD)
	assert_bool(hud.boss_cue.playing).is_true()
	assert_str(hud.announcement.text).is_equal("O Necromante despertou na praça")


func test_start_hint_names_the_pause_key() -> void:
	var hud := _spawn_hud(arena.spawn(TestArena.KNIGHT, Vector3.ZERO))

	hud.show_start_hint()

	assert_str(hud.announcement.text).contains("pausa e controles")


func test_attempt_uses_roman_numerals() -> void:
	assert_str(Hud.roman(1)).is_equal("I")
	assert_str(Hud.roman(4)).is_equal("IV")
	assert_str(Hud.roman(9)).is_equal("IX")
	assert_str(Hud.roman(14)).is_equal("XIV")


func test_damage_trail_lags_behind_then_catches_up() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO)
	var hud := _spawn_hud(knight)
	await arena.wait_physics(2)

	knight.take_damage(3.0)
	await arena.wait_physics(2)

	assert_float(hud.health_bar.value).is_equal(7.0)
	assert_float(hud.health_trail.value).is_equal(10.0)
	await arena.wait_seconds(Hud.TRAIL_DELAY + Hud.TRAIL_TIME + 0.4)
	assert_float(hud.health_trail.value).is_equal_approx(7.0, 0.01)


func test_objective_shows_one_diamond_per_group_lit_while_alive() -> void:
	var hud := _spawn_hud(arena.spawn(TestArena.KNIGHT, Vector3.ZERO))

	hud.set_objective("Grupos restantes", 3, 5)

	assert_int(hud.pips.get_child_count()).is_equal(5)
	assert_float(hud.pips.get_child(2).modulate.a).is_equal(1.0)
	assert_float(hud.pips.get_child(3).modulate.a).is_less(1.0)
	assert_str(hud.objective_summary()).is_equal("Grupos restantes: 3")
	hud.set_objective("Derrote o Necromante")
	assert_int(hud.pips.get_child_count()).is_equal(0)
	assert_str(hud.objective_summary()).is_equal("Derrote o Necromante")


func test_stamina_bar_dims_while_exhausted_and_brightens_when_full() -> void:
	var knight := arena.spawn(TestArena.KNIGHT, Vector3.ZERO) as Adventurer
	var hud := _spawn_hud(knight)
	await arena.wait_physics(2)

	knight.stamina.spend(knight.stamina.maximum)
	assert_object(hud.stamina_bar.self_modulate).is_equal(Hud.EXHAUSTED_TINT)

	knight.stamina.refill()
	assert_object(hud.stamina_bar.self_modulate).is_equal(Color.WHITE)
