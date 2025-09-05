extends TextureRect

@onready var subviewport := $SubViewportContainer/SubViewport

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		# Translate global mouse to SubViewport coordinates
		var local_pos = subviewport.get_local_mouse_position()
		# Call a function to handle picking
		handle_subviewport_click(local_pos, event)


func handle_subviewport_click(local_pos: Vector2, event: InputEvent) -> void:
	var camera := subviewport.get_camera_3d()
	if camera == null:
		return
	
	# Cast a ray from camera through the mouse position
	var from := camera.project_ray_origin(local_pos)
	var to := from + camera.project_ray_normal(local_pos) * 1000.0
	
	var space_state := subviewport.get_world_3d().direct_space_state
	var result := space_state.intersect_ray(from, to, [], 1)
	
	if result:
		var obj := result.collider
		if obj and obj.has_:  # Or whatever handler you use
			obj._on_click(event)
