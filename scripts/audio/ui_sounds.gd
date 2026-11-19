extends Node
## Autoload/Gerenciador global que conecta efeitos sonoros automaticamente à UI.
## Monitora a árvore de nós e conecta os sons de clique e foco a qualquer
## nó do tipo 'BaseButton' (como Button, TextureButton, etc) que entrar no jogo.
# o foco so soa depois de uma acao do jogador, senao tocaria no grab_focus de cada tela


## Tempo máximo (em segundos) decorrido após um input para permitir o som de foco.
## Evita disparos indesejados no 'grab_focus' automático durante abertura de telas.
const FOCUS_AFTER_INPUT := 0.5
## Player de áudio com o efeito sonoro de clique.
@export var click: AudioStreamPlayer
## Player de áudio com o efeito sonoro de passagem do mouse / foco de teclado.
@export var focus: AudioStreamPlayer
## Marca temporal (em segundos) do último input pressionado pelo jogador.
var _last_input := -INF


func _ready() -> void:
	# Garante que a UI continue tocando sons mesmo com o jogo pausado (GetTree().paused = true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	# Atualiza o timer do último input manual do jogador
	if event.is_pressed():
		_last_input = Time.get_ticks_msec() / 1000.0

## Chamado automaticamente sempre que um novo nó entra na cena.
func _on_node_added(node: Node) -> void:
	# Conecta os sons apenas se o nó for um botão da UI e ainda não estiver conectado
	if node is BaseButton and not node.pressed.is_connected(click.play):
		node.pressed.connect(click.play)
		node.focus_entered.connect(_on_focus.bind(node))
		node.mouse_entered.connect(focus.play)

## Toca o som de foco apenas se o foco foi resultado de uma ação recente do jogador
## e o botão está numa tela aberta: na partida, o analógico pega o botão do menu de pausa fechado.
func _on_focus(button: BaseButton) -> void:
	if Time.get_ticks_msec() / 1000.0 - _last_input <= FOCUS_AFTER_INPUT and _is_on_screen(button):
		focus.play()


# o CanvasLayer escondido não entra no is_visible_in_tree dos botões dele
static func _is_on_screen(button: BaseButton) -> bool:
	if not button.is_visible_in_tree():
		return false
	var node := button.get_parent()
	while node:
		if node is CanvasLayer and not (node as CanvasLayer).visible:
			return false
		node = node.get_parent()
	return true
