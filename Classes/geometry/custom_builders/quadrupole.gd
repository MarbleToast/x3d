class_name QuadrupoleMeshBuilder
extends RefCounted


static func create(
	length: float,
	start_rotation: Basis,
	thickness_modifier: float,
	aperture_radius: float,
	pole_width: float,
	pole_tip_width: float,
	yoke_inner_radius: float,
	yoke_outer_radius: float
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var ap_r := aperture_radius * thickness_modifier
	var pole_w := pole_width * thickness_modifier
	var tip_w := pole_tip_width * thickness_modifier
	var yoke_inner := yoke_inner_radius * thickness_modifier
	var yoke_outer := yoke_outer_radius * thickness_modifier
	
	_build_poles(st, length, start_rotation, ap_r, pole_w, tip_w)
	HollowCylinderBuilder.add_to_surface(st, yoke_inner, yoke_outer, length, start_rotation)
	
	st.index()
	st.generate_normals()
	return st.commit()


static func _build_poles(
	st: SurfaceTool,
	length: float,
	start_rotation: Basis,
	aperture_radius: float,
	pole_width: float,
	pole_tip_width: float
) -> void:
	var half_len := length * 0.5
	var start_tangent := start_rotation.z
	
	for pole_idx in 4:
		var angle := TAU * float(pole_idx) / 4.0
		var pole_dir := Vector2(cos(angle), sin(angle))
		var pole_perp := Vector2(-pole_dir.y, pole_dir.x)
		
		var inner_half_width := pole_tip_width / 2.0
		var outer_half_width := pole_tip_width / 1.5
		
		var inner_center := pole_dir * aperture_radius
		var outer_center := pole_dir * (aperture_radius + pole_width)
		
		var pole_2d: Array[Vector2] = [
			inner_center - pole_perp * inner_half_width,
			inner_center + pole_perp * inner_half_width,
			outer_center + pole_perp * outer_half_width,
			outer_center - pole_perp * outer_half_width
		]
		
		var front_ring: Array[Vector3] = []
		var back_ring: Array[Vector3] = []
		
		for p in pole_2d:
			var pos_3d := start_rotation.x * p.x + start_rotation.y * p.y
			front_ring.append(pos_3d + start_tangent * half_len)
			back_ring.append(pos_3d - start_tangent * half_len)
		
		MeshGeometry.extrude_shape_with_caps(st, front_ring, back_ring)
