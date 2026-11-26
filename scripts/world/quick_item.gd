class_name QuickItem
extends Resource
## item do slot de acesso rapido: pegar so guarda, o efeito vale ao usar

enum Debuff { NONE, SLOW, WEAKNESS }

const WORLD_SCENES := {
	"res://resources/items/health_potion.tres": "res://scenes/world/health_potion.tscn",
	"res://resources/items/mana_potion.tres": "res://scenes/world/mana_potion.tscn",
	"res://resources/items/black_potion_slow.tres": "res://scenes/world/black_potion_slow.tscn",
	"res://resources/items/black_potion_weakness.tres": "res://scenes/world/black_potion_weakness.tscn",
}

@export var title := ""
@export var icon: Texture2D
## parte da vida maxima que cura ao usar (0.2 = 20%)
@export var heal_fraction := 0.0
## mana que devolve ao usar
@export var mana_amount := 0.0
## quantos cabem no inventario
@export var max_carried := 4
@export var debuff := Debuff.NONE
@export var seal_color := Color.WHITE


func debuff_label() -> String:
	return "Lentidão" if debuff == Debuff.SLOW else "Fraqueza"
