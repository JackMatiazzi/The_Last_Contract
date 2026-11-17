class_name StatModifier
extends Resource
## DAMAGE e MAX_HEALTH em pontos; os outros em fracao (0.2 = +20%)

enum Stat { DAMAGE, MAX_HEALTH, SPEED, ATTACK_COOLDOWN, DAMAGE_TAKEN, MAX_HEALTH_PERCENT, NOISE, ENERGY_REGEN, LIFESTEAL, THORNS, EXTRA_CHOICE, ENEMY_SHARE }

@export var stat: Stat
@export var amount := 0.0


func describe() -> String:
	match stat:
		Stat.DAMAGE:
			return "%s de dano" % _points(amount)
		Stat.MAX_HEALTH:
			return "%s de vida máxima" % _points(amount)
		Stat.SPEED:
			return "%+d%% de velocidade" % roundi(amount * 100.0)
		Stat.ATTACK_COOLDOWN:
			return "%+d%% de tempo entre ataques" % roundi(amount * 100.0)
		Stat.DAMAGE_TAKEN:
			return "%+d%% de dano recebido" % roundi(amount * 100.0)
		Stat.MAX_HEALTH_PERCENT:
			return "%+d%% de vida máxima" % roundi(amount * 100.0)
		Stat.NOISE:
			return "%+d%% de barulho" % roundi(amount * 100.0)
		Stat.ENERGY_REGEN:
			return "%+d%% de recuperação de energia" % roundi(amount * 100.0)
		Stat.LIFESTEAL:
			return "cura %d%% da vida a cada golpe acertado" % roundi(amount * 100.0)
		Stat.THORNS:
			return "devolve %d%% do dano recebido" % roundi(amount * 100.0)
		Stat.EXTRA_CHOICE:
			return "%+d bênção para escolher" % roundi(amount)
		Stat.ENEMY_SHARE:
			return "mortos-vivos: %+d%% de cada bênção" % roundi(amount * 100.0)
	return ""


# meio ponto aparece como meio ponto, com vírgula: arredondar mostrava "+1" na carta que dá +0,5
static func _points(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%+d" % roundi(value)
	return ("%+.1f" % value).replace(".", ",")
