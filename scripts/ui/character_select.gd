class_name CharacterSelect
extends Node3D

const MISSION_INTRO := "res://scenes/cutscenes/mission_intro.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const SLOT_SPACING := 2.4
const STEP_FORWARD := 0.9
const HIGHLIGHT_TIME := 0.25
const NAME_HEIGHT := 2.9
const DIMMED := Color(0.75, 0.7, 0.65, 0.55)
const HIGHLIGHT := Color(1.0, 0.84, 0.5, 1.0)
## altura do meio do corpo, de onde se mede o clique no boneco
const BODY_HEIGHT := 1.0
## distância máxima, em pixels na tela, entre o clique e o meio do boneco
const PICK_RADIUS := 110.0

@export var stage: Node3D
@export var ring: Node3D
@export var spotlight: SpotLight3D

var models: Array[Node3D] = []
var name_tags: Array[Label3D] = []

@onready var picker: AdventurerPicker = %AdventurerPicker
@onready var contract: ContractSign = %ContractSign


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in picker.options.size():
		_add_slot(i, picker.options[i])
	picker.selection_changed.connect(_highlight)
	picker.confirmed.connect(_offer_contract)
	picker.back_requested.connect(get_tree().change_scene_to_file.bind(MAIN_MENU))
	contract.signed.connect(func(_signature: String) -> void: _start_contract(picker.selected))
	contract.cancelled.connect(_back_to_choice)
	_highlight(picker.selected)


func _add_slot(index: int, info: AdventurerInfo) -> void:
	var model := info.model.instantiate() as Node3D
	model.position.x = (index - (picker.options.size() - 1) / 2.0) * SLOT_SPACING
	stage.add_child(model)
	_animation_player(model).play(Character.ANIM_IDLE)
	models.append(model)

	var tag := Label3D.new()
	tag.text = "%d  %s" % [index + 1, info.title]
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 56
	tag.outline_size = 14
	tag.position.y = NAME_HEIGHT
	model.add_child(tag)
	name_tags.append(tag)


func _highlight(_info: AdventurerInfo) -> void:
	var chosen := picker.selected_index
	var tween := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	for i in models.size():
		var forward := STEP_FORWARD if i == chosen else 0.0
		tween.tween_property(models[i], "position:z", forward, HIGHLIGHT_TIME)
		tween.tween_property(name_tags[i], "modulate", HIGHLIGHT if i == chosen else DIMMED, HIGHLIGHT_TIME)
	var spot := models[chosen].position + Vector3(0, 0, STEP_FORWARD)
	tween.tween_property(ring, "position", Vector3(spot.x, ring.position.y, spot.z), HIGHLIGHT_TIME)
	tween.tween_property(spotlight, "global_position:x", stage.to_global(spot).x, HIGHLIGHT_TIME)

	var player := _animation_player(models[chosen])
	player.play("Cheer")
	player.queue(Character.ANIM_IDLE)


func _unhandled_input(event: InputEvent) -> void:
	if not picker.visible or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var index := model_at((event as InputEventMouseButton).position)
	if index >= 0:
		picker.select(index)
		get_viewport().set_input_as_handled()


## o boneco mais perto do ponto clicado na tela; -1 quando o clique foi longe de todos
func model_at(screen_point: Vector2) -> int:
	var camera := get_viewport().get_camera_3d()
	var nearest := -1
	var nearest_distance := PICK_RADIUS
	for i in models.size():
		var center := camera.unproject_position(models[i].global_position + Vector3.UP * BODY_HEIGHT)
		var distance := center.distance_to(screen_point)
		if distance < nearest_distance:
			nearest = i
			nearest_distance = distance
	return nearest


# o seletor escondido para de ler as setas e o Esc, que agora sao do contrato
func _offer_contract(info: AdventurerInfo) -> void:
	picker.hide()
	contract.open(info)


func _back_to_choice() -> void:
	picker.show()
	picker.focus_accept()


func _start_contract(info: AdventurerInfo) -> void:
	RunState.reset()
	RunState.adventurer = info
	Net.match_seed = randi()
	get_tree().change_scene_to_file(MISSION_INTRO)


func _animation_player(model: Node) -> AnimationPlayer:
	return model.get_node("AnimationPlayer")
