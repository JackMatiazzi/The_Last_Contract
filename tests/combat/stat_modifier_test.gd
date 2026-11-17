extends GdUnitTestSuite

# o texto da carta da bênção tem que dizer o que ela faz de verdade; meio ponto não vira um ponto inteiro


func _modifier(stat: StatModifier.Stat, amount: float) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.amount = amount
	return modifier


func test_half_a_point_of_damage_is_written_as_half() -> void:
	assert_str(_modifier(StatModifier.Stat.DAMAGE, 0.5).describe()).is_equal("+0,5 de dano")


func test_whole_points_stay_without_decimals() -> void:
	assert_str(_modifier(StatModifier.Stat.DAMAGE, 1.0).describe()).is_equal("+1 de dano")
	assert_str(_modifier(StatModifier.Stat.MAX_HEALTH, -3.0).describe()).is_equal("-3 de vida máxima")
	assert_str(_modifier(StatModifier.Stat.DAMAGE_TAKEN, -0.2).describe()).is_equal("-20% de dano recebido")


func test_the_sharp_blade_card_says_what_it_gives() -> void:
	var blade := load("res://resources/buffs/lamina_afiada.tres") as Buff

	assert_str(blade.describe()).contains("+0,5 de dano")
