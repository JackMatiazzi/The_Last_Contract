extends GdUnitTestSuite

var _consent_before: int
var _code_before: String


func before_test() -> void:
	_consent_before = Settings.telemetry_consent
	_code_before = Settings.player_code


func after_test() -> void:
	Settings.telemetry_consent = _consent_before
	Settings.player_code = _code_before
	Settings._save()
	Playtest.uplink.contact = TelemetryUplink.CONTACT
	Playtest.uplink.session = ""
	Playtest.uplink.test_code = ""


func _run() -> Dictionary:
	return {
		"adventurer": "Knight",
		"version": "0.9",
		"events": [
			{"type": "attempt_started", "t": 0.0, "attempt": 1, "buffs": ["x"]},
			{"type": "player_died", "t": 30.0, "attempt": 1, "position": [1.0, 0.0, 2.0], "recap": [{"dano": 3}], "enemy": "Arqueiro esqueleto", "stage": "Pedra Alta"},
			{"type": "blessing_chosen", "t": 40.0, "attempt": 1, "buff": "Lâmina afiada"},
			{"type": "boss_killed", "t": 90.0, "attempt": 2},
			{"type": "trapdoor_entered", "t": 95.0, "attempt": 2},
		],
	}


func test_accepting_creates_a_random_code_for_this_pc() -> void:
	Settings.accept_telemetry(true)

	assert_int(Settings.telemetry_consent).is_equal(Settings.CONSENT_YES)
	assert_bool(RegEx.create_from_string("^[0-9a-f]{32}$").search(Settings.player_code) != null).is_true()


func test_turning_off_keeps_the_code_so_the_player_can_still_delete() -> void:
	Settings.accept_telemetry(true)
	var code := Settings.player_code

	Settings.accept_telemetry(false)

	assert_int(Settings.telemetry_consent).is_equal(Settings.CONSENT_NO)
	assert_str(Settings.player_code).is_equal(code)


func test_after_deleting_the_code_is_forgotten() -> void:
	Settings.accept_telemetry(true)

	Settings.forget_player_code()

	assert_str(Settings.player_code).is_empty()


func test_nothing_is_sent_without_consent() -> void:
	Playtest.uplink.contact = "playtest@exemplo.com"
	Settings.accept_telemetry(false)

	assert_bool(Playtest.uplink.is_active()).is_false()


func test_nothing_is_sent_while_the_contact_is_not_defined() -> void:
	Playtest.uplink.contact = ""
	Settings.accept_telemetry(true)

	assert_bool(Playtest.uplink.is_active()).is_false()


func test_with_consent_and_contact_it_is_active() -> void:
	Playtest.uplink.contact = "playtest@exemplo.com"
	Settings.accept_telemetry(true)

	assert_bool(Playtest.uplink.is_active()).is_true()


func test_the_summary_counts_deaths_attempts_and_the_bonus() -> void:
	RunState.attempt = 2
	var summary := TelemetryUplink.summary(_run().merged({"duration": 600.0}))
	RunState.reset()

	assert_str(summary.classe).is_equal("Knight")
	assert_int(summary.tentativas).is_equal(2)
	assert_int(summary.mortes).is_equal(1)
	assert_bool(summary.achou_bonus).is_true()
	assert_float(summary.minutos).is_equal(10.0)


func test_the_summary_keeps_only_the_fields_the_server_accepts() -> void:
	var events: Array = TelemetryUplink.summary(_run()).eventos
	var death: Dictionary = events[1]

	assert_str(death.enemy).is_equal("Arqueiro esqueleto")
	assert_str(death.stage).is_equal("Pedra Alta")
	assert_bool(death.has("recap")).is_false()
	assert_bool((events[0] as Dictionary).has("buffs")).is_false()


func test_a_long_match_fits_the_size_limit_keeping_the_milestones_and_the_latest_deaths() -> void:
	var run := _run()
	for i in 400:
		run.events.append({"type": "player_died", "t": 100.0 + i, "attempt": 3, "position": [1.0, 2.0, 3.0], "enemy": "Arqueiro esqueleto", "stage": "Pedra Alta", "hits": [["Mago esqueleto", 1.0], ["Arqueiro esqueleto", 2.5]], "taken": 10.0, "healed": 0.0})
	run.events.append({"type": "victory", "t": 999.0, "attempt": 3})

	var events: Array = TelemetryUplink.summary(run).eventos
	var types := events.map(func(event: Dictionary) -> String: return event.type)

	assert_int(JSON.stringify(events).length()).is_less_equal(TelemetryUplink.MAX_EVENT_BYTES)
	assert_array(types).contains(["attempt_started", "boss_killed", "trapdoor_entered", "victory"])
	assert_float(events[-2].t).is_equal(499.0)


func test_sending_keeps_working_while_the_game_is_paused() -> void:
	assert_int(Playtest.uplink.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_sends_go_out_one_at_a_time_in_order() -> void:
	var before := Net.relay_url
	Net.relay_url = "ws://127.0.0.1:9"
	var uplink: TelemetryUplink = auto_free(TelemetryUplink.new())
	add_child(uplink)

	uplink._enqueue("/solo/marco", {"n": 1})
	uplink._enqueue("/solo/marco", {"n": 2})

	assert_int(uplink._queue.size()).is_equal(1)
	assert_dict(uplink._queue[0].body).is_equal({"n": 2})
	assert_bool(uplink.is_idle()).is_false()
	Net.relay_url = before


func test_the_coop_report_carries_the_ticket_and_spends_it() -> void:
	Net.relay_ticket = "ab".repeat(32)

	var report := Net.take_match_report({"resultado": "victory"})

	assert_str(report.ficha).is_equal("ab".repeat(32))
	assert_str(report.apelido).is_equal(Settings.player_name)
	assert_dict(Net.take_match_report({})).is_empty()


func test_an_ally_name_in_a_hit_does_not_leave_the_game() -> void:
	var run := {"events": [{"type": "player_died", "t": 1.0, "attempt": 1, "enemy": "Fogo amigo de Ana", "hits": [["Fogo amigo de Ana", 2.0], ["Esqueleto", 1.0]]}]}

	var death: Dictionary = TelemetryUplink.summary(run).eventos[0]

	assert_str(death.enemy).is_equal("Fogo amigo")
	assert_array(death.hits).is_equal([["Fogo amigo", 2.0], ["Esqueleto", 1.0]])
