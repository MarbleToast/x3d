class_name CollisionShapeFactory
extends RefCounted

static func create_simple_collider(type: String, collision_length: float, thickness_modifier: float) -> Shape3D:
	var dims: Dictionary = Settings.ELEMENT_DIMENSIONS.get(type, Settings.ELEMENT_DIMENSIONS._default)
	
	match dims.type:
		"box":
			var box := BoxShape3D.new()
			box.size = Vector3(dims.width * thickness_modifier * 2.0, dims.height * thickness_modifier * 2.0, collision_length)
			return box
		"equals":
			var box := BoxShape3D.new()
			var total_height: float = (dims.bar_height * 2.0 + dims.gap) * thickness_modifier
			box.size = Vector3(dims.width * thickness_modifier * 2.0, total_height, collision_length)
			return box
		"circle":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = dims.radius * thickness_modifier
			cylinder.height = collision_length
			return cylinder
		"multipole":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = (dims.pole_radius + dims.pole_width) * thickness_modifier
			cylinder.height = collision_length
			return cylinder
		"quadrupole":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = dims.yoke_outer_radius * thickness_modifier
			cylinder.height = collision_length
			return cylinder
	
	return BoxShape3D.new()
