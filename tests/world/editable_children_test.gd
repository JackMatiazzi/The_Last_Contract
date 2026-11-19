extends GdUnitTestSuite

# no editor um nó novo (ou um valor trocado) dentro de uma cena instanciada vale mesmo sem [editable path];
# no .exe exportado ele some e quem aponta pra ele recebe null (foi o que derrubava o Michio e o mímico)

const NODE_LINE := "^\\[node name=\"([^\"]+)\"(?: type=\"[^\"]+\")?(?: parent=\"([^\"]+)\")?"


func _scenes(dir: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tscn"):
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scenes(dir.path_join(sub)))
	return found


func _lost_in_export(path: String) -> PackedStringArray:
	var line_regex := RegEx.create_from_string(NODE_LINE)
	var instanced := PackedStringArray()
	var editable := PackedStringArray()
	var entries: Array[PackedStringArray] = []
	var added_paths := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("[editable path="):
			editable.append(line.get_slice("\"", 1))
			continue
		var found := line_regex.search(line)
		if found == null or found.get_string(2).is_empty():
			continue
		var parent := found.get_string(2)
		var node_path := found.get_string(1) if parent == "." else parent + "/" + found.get_string(1)
		if " instance=" in line:
			instanced.append(node_path)
		if " instance=" in line or " type=" in line:
			added_paths.append(node_path)
		entries.append(PackedStringArray([node_path, parent]))
	var problems := PackedStringArray()
	for entry in entries:
		if entry[1] in added_paths:
			continue
		for owner_path in instanced:
			if entry[1].begins_with(owner_path + "/") and not owner_path in editable:
				problems.append("%s: %s precisa de [editable path=\"%s\"]" % [path, entry[0], owner_path])
	return problems


func test_nodes_and_overrides_inside_an_instanced_scene_survive_the_export() -> void:
	var problems := PackedStringArray()
	for scene in _scenes("res://scenes"):
		problems.append_array(_lost_in_export(scene))

	assert_array(problems).is_empty()
