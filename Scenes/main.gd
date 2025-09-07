extends TextureRect

@onready var subviewport: SubViewport = $SubViewportContainer/SubViewport

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var local_pos = subviewport.get_mouse_position()
			handle_subviewport_click(local_pos, event)


func handle_subviewport_click(local_pos: Vector2, event: InputEvent) -> void:
	var camera := subviewport.get_camera_3d()
	if camera == null:
		return
	
	var space_state := get_viewport().get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = camera.project_ray_origin(local_pos)
	params.to = params.from + camera.project_ray_normal(local_pos) * 1000.0
	var result := space_state.intersect_ray(params)
	
	if result:
		var obj: StaticBody3D = result.collider
		if obj and obj is StaticBody3D:  # Or whatever handler you use
			obj.input_event.emit(camera, event, result.position, result.normal, result.face_index)
