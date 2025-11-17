extends Button

@export var x: SpinBox
@export var y: SpinBox
@export var z: SpinBox

@export var psi: SpinBox
@export var theta: SpinBox
@export var phi: SpinBox

@export var length: SpinBox

@export var mesh_manager: Node3D


func _on_pressed() -> void:
	var pos := Vector3(x.value, y.value, z.value)
	mesh_manager.regenerate_mesh(
		mesh_manager.selected_element_mesh,
		mesh_manager.selected_element_mesh.type,
		length.value,
		pos,
		psi.value,
		theta.value,
		phi.value
	)


func _on_visibility_changed() -> void:
	if visible:
		var selected_element: ElementMeshInstance = mesh_manager.selected_element_mesh
		x.value = selected_element.other_info.position.x
		y.value = selected_element.other_info.position.y
		z.value = selected_element.other_info.position.z
		psi.value = selected_element.other_info.psi
		theta.value = selected_element.other_info.theta
		phi.value = selected_element.other_info.phi
		length.value = selected_element.other_info.length
