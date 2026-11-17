extends GdUnitTestSuite

# o texto do efeito quebra linha dentro do cartão: "-15% de tempo entre ataques" passava da borda

const CARD := preload("res://scenes/ui/buff_card.tscn")
const BUFFS := ["couraca", "frenesi", "furia_cega", "lamina_afiada", "passos_leves", "sangue_frio", "vigor"]


func test_every_blessing_text_fits_inside_the_card() -> void:
	for buff_name: String in BUFFS:
		var card: BuffCard = auto_free(CARD.instantiate())
		add_child(card)
		card.setup(load("res://resources/buffs/%s.tres" % buff_name), 0)
		await await_idle_frame()

		var inside := card.size.x - 36.0
		var text_width := card.effects_label.get_combined_minimum_size().x
		assert_float(text_width).override_failure_message("%s pede %.0f px num cartão de %.0f" % [buff_name, text_width, inside]).is_less_equal(inside)
