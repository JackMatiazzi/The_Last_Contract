@tool
class_name ForestBuilder
extends RefCounted
## A semente fixa faz a floresta sair igual em toda maquina e em todo build, enquanto os modelos nao mudarem.

## tentativas por arvore que cabe na area: mapa maior ganha mais tentativas e a mata nao sai rala
const ATTEMPTS_PER_SLOT := 5.0


# o quadrado de dentro e o mapa com folga; o raio externo fica onde a neblina ja esconde a borda
static func scatter(clear_half_size: float, outer_radius: float, spacing: float, seed_value: int) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var area := PI * outer_radius * outer_radius - 4.0 * clear_half_size * clear_half_size
	var attempts := ceili(maxf(area, 0.0) / (spacing * spacing) * ATTEMPTS_PER_SLOT)
	var spots: Array[Vector2] = []
	for attempt in attempts:
		var p := Vector2(rng.randf_range(-outer_radius, outer_radius), rng.randf_range(-outer_radius, outer_radius))
		if maxf(absf(p.x), absf(p.y)) < clear_half_size or p.length() > outer_radius:
			continue
		if spots.any(func(other: Vector2) -> bool: return other.distance_to(p) < spacing):
			continue
		spots.append(p)
	return spots


static func build(meshes: Array[Mesh], spots: Array[Vector2], seed_value: int) -> Array[MultiMesh]:
	# o renderizador falso do --headless nao guarda o buffer do MultiMesh: salvaria todas as arvores na origem
	assert(DisplayServer.get_name() != "headless", "ForestBuilder: gere pelo editor, nao com --headless")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var per_mesh: Array = []
	for i in meshes.size():
		per_mesh.append([])
	for spot in spots:
		per_mesh[rng.randi() % meshes.size()].append(spot)
	var result: Array[MultiMesh] = []
	for i in meshes.size():
		result.append(_multimesh(meshes[i], per_mesh[i], rng))
	return result


static func first_mesh(model: PackedScene) -> Mesh:
	var root := model.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if found.size() == 1 else null
	root.free()
	assert(mesh, "ForestBuilder: %s precisa ter exatamente uma malha (tem %d)" % [model.resource_path, found.size()])
	return mesh


static func _multimesh(mesh: Mesh, spots: Array, rng: RandomNumberGenerator) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = spots.size()
	for i in spots.size():
		var spot: Vector2 = spots[i]
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6))
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(spot.x, 0.0, spot.y)))
	return multimesh
