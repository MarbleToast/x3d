class_name BeamAnimationController
extends Node3D

var beam_mesh_instance: MeshInstance3D:
	set(value):
		beam_mesh_instance = value
		_beam_material = beam_mesh_instance.get_surface_override_material(0)

var _beam_material: ShaderMaterial
@export var fill_duration: float = 10.0

func start_animation(with_delay := true) -> void:
	if not beam_mesh_instance:
		push_error("BeamAnimationController: beam_mesh_instance not assigned")
		return

	get_tree().create_tween().tween_method(
		func(progress):
			_beam_material.set_shader_parameter("fill_progress", progress),
		0.0, 
		1.0, 
		fill_duration
	).set_delay(2.0 if with_delay else 0.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_F and event.pressed and not event.is_echo():
			start_animation(false)
