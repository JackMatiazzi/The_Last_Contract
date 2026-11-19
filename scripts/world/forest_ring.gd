@tool
class_name ForestRing
extends Node3D
## Floresta de fundo para qualquer mapa: coloque a cena no mapa, ajuste o tamanho e clique em "Gerar floresta".
## A neblina rasteira so aparece se o Environment da fase tiver volumetric_fog_enabled.

## Os modelos ficam copiados na cena: se uma arvore mudar no Blender, clique em "Gerar floresta" de novo.

## o chao passa do raio para a borda dele ficar dentro da neblina
const GROUND_MARGIN := 50.0
## a neblina comeca um pouco antes das arvores para cobrir o chao entre o mapa e a mata
const MIST_INSET := 4.0
## rasteira: mais alta que isso vira parede na frente da camera
const MIST_HEIGHT := 1.6

## metade do lado do quadrado livre no centro: a metade do mapa mais a folga ate as primeiras arvores
@export var clear_half_size := 30.0
@export var outer_radius := 62.0
@export var spacing := 2.6
@export var seed_value := 2611
## um MultiMeshInstance3D filho por modelo, na mesma ordem
@export var models: Array[PackedScene] = []
@export_tool_button("Gerar floresta") var generate_button := generate


func generate() -> void:
	var holders := find_children("*", "MultiMeshInstance3D", false, false)
	if models.is_empty() or holders.size() != models.size():
		push_error("ForestRing: %d modelos para %d MultiMeshInstance3D" % [models.size(), holders.size()])
		return
	var meshes: Array[Mesh] = []
	for model in models:
		meshes.append(ForestBuilder.first_mesh(model))
	var spots := ForestBuilder.scatter(clear_half_size, outer_radius, spacing, seed_value)
	var multimeshes := ForestBuilder.build(meshes, spots, seed_value)
	for i in holders.size():
		(holders[i] as MultiMeshInstance3D).multimesh = multimeshes[i]
	_fit_ground()
	_fit_mist()


# recurso novo em vez de mexer no da cena: assim o tamanho fica salvo no mapa que usa a floresta
func _fit_ground() -> void:
	var ground := $Chao as MeshInstance3D
	var plane := (ground.mesh as PlaneMesh).duplicate() as PlaneMesh
	plane.size = Vector2.ONE * (outer_radius + GROUND_MARGIN) * 2.0
	ground.mesh = plane


# norte e sul cobrem a largura toda, leste e oeste so o miolo: os cantos nao dobram a densidade
func _fit_mist() -> void:
	var start := clear_half_size - MIST_INSET
	var depth := outer_radius + GROUND_MARGIN - start
	var middle := start + depth / 2.0
	var full := (start + depth) * 2.0
	var y := MIST_HEIGHT / 2.0 - 0.5
	_place($NeblinaNorte, Vector3(0, y, -middle), Vector3(full, MIST_HEIGHT, depth))
	_place($NeblinaSul, Vector3(0, y, middle), Vector3(full, MIST_HEIGHT, depth))
	_place($NeblinaLeste, Vector3(middle, y, 0), Vector3(depth, MIST_HEIGHT, start * 2.0))
	_place($NeblinaOeste, Vector3(-middle, y, 0), Vector3(depth, MIST_HEIGHT, start * 2.0))


func _place(volume: FogVolume, at: Vector3, box: Vector3) -> void:
	volume.position = at
	volume.size = box
