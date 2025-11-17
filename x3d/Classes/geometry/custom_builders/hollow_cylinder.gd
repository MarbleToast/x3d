class_name HollowCylinderBuilder
extends RefCounted


static func add_to_surface(
	st: SurfaceTool,
	inner_radius: float,
	outer_radius: float,
	length: float,
	start_rotation: Basis,
	radial_segments: int = 32,
	phase_offset: float = 0
) -> void:
	var half_len := length * 0.5
	var start_tangent := start_rotation.z
	
	var outer_front: Array[Vector3] = []
	var outer_back: Array[Vector3] = []
	var inner_front: Array[Vector3] = []
	var inner_back: Array[Vector3] = []
	
	for i in range(radial_segments):
		var angle := (float(i) / radial_segments) * TAU + phase_offset
		var cos_a := cos(angle)
		var sin_a := sin(angle)
		
		var outer_pos := start_rotation.x * (cos_a * outer_radius) + start_rotation.y * (sin_a * outer_radius)
		var inner_pos := start_rotation.x * (cos_a * inner_radius) + start_rotation.y * (sin_a * inner_radius)
		
		outer_front.append(outer_pos + start_tangent * half_len)
		outer_back.append(outer_pos - start_tangent * half_len)
		inner_front.append(inner_pos + start_tangent * half_len)
		inner_back.append(inner_pos - start_tangent * half_len)
	
	# outer radius
	for i in range(radial_segments):
		var j := (i + 1) % radial_segments
		st.add_vertex(outer_back[i])
		st.add_vertex(outer_back[j])
		st.add_vertex(outer_front[i])
		st.add_vertex(outer_back[j])
		st.add_vertex(outer_front[j])
		st.add_vertex(outer_front[i])
	
	# inner radius (reversed winding)
	for i in range(radial_segments):
		var j := (i + 1) % radial_segments
		st.add_vertex(inner_back[i])
		st.add_vertex(inner_front[i])
		st.add_vertex(inner_back[j])
		st.add_vertex(inner_back[j])
		st.add_vertex(inner_front[i])
		st.add_vertex(inner_front[j])
	
	var num_points := outer_front.size()
	
	# front cap fr fr
	for i in range(num_points):
		var j := (i + 1) % num_points
		st.add_vertex(outer_front[i])
		st.add_vertex(inner_front[i])
		st.add_vertex(outer_front[j])
		st.add_vertex(outer_front[j])
		st.add_vertex(inner_front[i])
		st.add_vertex(inner_front[j])
	
	# back cap fr fr
	for i in range(num_points):
		var j := (i + 1) % num_points
		st.add_vertex(outer_back[i])
		st.add_vertex(outer_back[j])
		st.add_vertex(inner_back[i])
		st.add_vertex(outer_back[j])
		st.add_vertex(inner_back[j])
		st.add_vertex(inner_back[i])
