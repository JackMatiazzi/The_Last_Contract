class_name LeaderboardRow
extends HBoxContainer
## uma linha do placar: cada célula é um Label de texto puro, cortado com reticências se não couber


func set_cells(cells: Array) -> void:
	var labels := get_children()
	for i in labels.size():
		var label := labels[i] as Label
		label.text = str(cells[i]) if i < cells.size() else ""
		label.tooltip_text = label.text
