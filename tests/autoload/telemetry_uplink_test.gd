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


func test_refusing_forgets_the_code() -> void:
	Settings.accept_telemetry(true)

	Settings.accept_telemetry(false)

	assert_int(Settings.telemetry_consent).is_equal(Settings.CONSENT_NO)
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
	var summary := TelemetryUplink.summary(_run())
	RunState.reset()

	assert_str(summary.classe).is_equal("Knight")
	assert_int(summary.tentativas).is_equal(2)
	assert_int(summary.mortes).is_equal(1)
	assert_bool(summary.achou_bonus).is_true()


func test_the_summary_keeps_only_the_fields_the_server_accepts() -> void:
	var events: Array = TelemetryUplink.summary(_run()).eventos
	var death: Dictionary = events[1]

	assert_str(death.enemy).is_equal("Arqueiro esqueleto")
	assert_str(death.stage).is_equal("Pedra Alta")
	assert_bool(death.has("recap")).is_false()
	assert_bool((events[0] as Dictionary).has("buffs")).is_false()


func test_a_long_match_sends_only_the_latest_events() -> void:
	var run := _run()
	for i in TelemetryUplink.MAX_EVENTS + 40:
		run.events.append({"type": "player_died", "t": 100.0 + i, "attempt": 3})

	var events: Array = TelemetryUplink.summary(run).eventos

	assert_int(events.size()).is_equal(TelemetryUplink.MAX_EVENTS)
	assert_float(events[-1].t).is_equal(100.0 + TelemetryUplink.MAX_EVENTS + 39)


func test_sending_keeps_working_while_the_game_is_paused() -> void:
	assert_int(Playtest.uplink.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
