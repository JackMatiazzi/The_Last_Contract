extends SceneTree
## assa o navmesh de Pedraalta a partir das colisoes e salva o recurso usado pela fase

const NAV_PATH := "res://resources/navigation/pedraalta_navmesh.res"


func _initialize() -> void:
	var source: NavigationMesh = load("res://resources/navigation/village_navmesh.res")
	var nav := source.duplicate() as NavigationMesh
	nav.agent_max_slope = 30.0
	nav.agent_max_climb = 0.25
	var map: Node3D = load("res://scenes/maps/pedraalta.tscn").instantiate()
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nav
	root.add_child(region)
	region.add_child(map)
	for i in 6:
		await physics_frame
	region.bake_navigation_mesh(false)
	var polygons := region.navigation_mesh.get_polygon_count()
	print("poligonos: ", polygons, " vertices: ", region.navigation_mesh.get_vertices().size())
	if polygons == 0:
		push_error("navmesh vazio: nada foi salvo")
		quit(1)
		return
	var err := ResourceSaver.save(region.navigation_mesh, NAV_PATH)
	print("salvo: ", err)
	quit(0 if err == OK else 1)
