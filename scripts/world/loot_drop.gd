class_name LootDrop
## poção que cai no chão (baú, mímico, objeto quebrado): uma por jogador da partida, espalhadas em volta,
## com os mesmos nomes em todas as máquinas para as mensagens de rede acharem a mesma poção

const SPREAD := 0.7


static func count() -> int:
	return Net.player_count


static func spawn(parent: Node, scene: PackedScene, base_name: String, origin: Vector3, amount := count()) -> Array[Node3D]:
	var drops: Array[Node3D] = []
	var collected_by: Dictionary[int, bool] = {}
	for i in amount:
		var drop := scene.instantiate() as Node3D
		drop.name = base_name if i == 0 else "%s%d" % [base_name, i + 1]
		if drop is Potion and drop.item.heal_fraction > 0.0:
			drop.collected_by = collected_by
		parent.add_child(drop)
		var angle := TAU * i / amount
		drop.global_position = origin + (Vector3(cos(angle), 0, sin(angle)) * SPREAD if amount > 1 else Vector3.ZERO)
		drops.append(drop)
	return drops
