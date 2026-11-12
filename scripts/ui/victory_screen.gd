class_name VictoryScreen
extends CanvasLayer

signal back_to_menu

@onready var summary_label: Label = %SummaryLabel


func _ready() -> void:
	hide()
	%MenuButton.pressed.connect(back_to_menu.emit)


func open(attempt: int) -> void:
	summary_label.text = "A vila está livre. Contrato de %s, cumprido na tentativa %s." % [_signatures(), Hud.roman(attempt)]
	show()
	%MenuButton.grab_focus()


static func join_names(names: Array) -> String:
	if names.size() <= 1:
		return "".join(PackedStringArray(names))
	return "%s e %s" % [", ".join(PackedStringArray(names.slice(0, -1))), names[-1]]


func _signatures() -> String:
	var peers: Array = Net.peers_in_order() if Net.is_online() else [multiplayer.get_unique_id()]
	return join_names(peers.map(func(peer_id: int) -> String: return Net.display_name(peer_id)))
