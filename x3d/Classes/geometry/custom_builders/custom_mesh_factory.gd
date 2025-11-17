class_name CustomMeshFactory
extends RefCounted

static func create_custom_mesh(
	type: String,
	dimensions: Dictionary,
	length: float,
	start_rotation: Basis,
	thickness_modifier: float
) -> ArrayMesh:
	match dimensions.type:
		"quadrupole":
			return QuadrupoleMeshBuilder.create(
				length, start_rotation, thickness_modifier,
				dimensions.aperture_radius, dimensions.pole_width,
				dimensions.pole_tip_width, dimensions.yoke_inner_radius,
				dimensions.yoke_outer_radius
			)

	push_error("Unknown custom mesh type: " + dimensions.type)
	return ArrayMesh.new()
