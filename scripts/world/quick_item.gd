class_name QuickItem
extends Resource
## item do slot de acesso rapido: pegar so guarda, o efeito vale ao usar

@export var title := ""
@export var icon: Texture2D
## parte da vida maxima que cura ao usar (0.2 = 20%)
@export var heal_fraction := 0.0
## mana que devolve ao usar
@export var mana_amount := 0.0
## quantos cabem no inventario
@export var max_carried := 4
