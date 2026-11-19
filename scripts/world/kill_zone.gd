class_name KillZone
extends Area3D
## água funda ou abismo: quem cai dentro morre na hora, aventureiro ou morto-vivo.
## Cada máquina só mata quem ela controla, como o resto do dano do jogo

const DEFAULT_CAUSE := "Afogado na fenda"
## acima de qualquer vida do jogo, mesmo com a maior redução de dano ou com o golpe reduzido do Michio
const LETHAL_DAMAGE := 999.0
const ADVENTURERS_AND_UNDEAD := 6

@export var cause := DEFAULT_CAUSE


func _init() -> void:
	collision_layer = 0
	collision_mask = ADVENTURERS_AND_UNDEAD


func _ready() -> void:
	body_entered.connect(_drown)


func get_display_name() -> String:
	return cause


func _drown(body: Node3D) -> void:
	var victim := body as Character
	if victim == null or victim.is_dead or not victim.is_multiplayer_authority():
		return
	victim.take_damage(LETHAL_DAMAGE, self)
