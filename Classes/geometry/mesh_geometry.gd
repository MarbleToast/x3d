class_name MeshGeometry
extends RefCounted


static func extrude_cross_sections(
	cross_section_func: Callable,
	length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	segments: int = 8,
	add_caps: bool = true
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start_tangent := start_rotation.z
	var end_tangent := end_rotation.z
	var rotation_axis := start_tangent.cross(end_tangent)
	var bend_angle := start_tangent.angle_to(end_tangent)
	var cross_sections_2d: Array[Array] = cross_section_func.call()
	
	if bend_angle < 1e-6 or rotation_axis.length_squared() < 1e-12:
		_extrude_straight(st, cross_sections_2d, length, start_rotation, add_caps)
	else:
		_extrude_curved(st, cross_sections_2d, length, start_rotation, end_rotation, segments, add_caps)
	
	st.index()
	st.generate_normals()
	return st.commit()


static func _extrude_straight(
	st: SurfaceTool,
	cross_sections_2d: Array[Array],
	length: float,
	start_rotation: Basis,
	add_caps: bool
) -> void:
	var half_len := length * 0.5
	var start_tangent := start_rotation.z
	var front_rings: Array[Array] = []
	var back_rings: Array[Array] = []
	
	for cross_section_2d in cross_sections_2d:
		var front_ring: Array[Vector3] = []
		var back_ring: Array[Vector3] = []
		for p in cross_section_2d:
			var pos_3d: Vector3 = start_rotation.x * p.x + start_rotation.y * p.y
			front_ring.append(pos_3d + start_tangent * half_len)
			back_ring.append(pos_3d - start_tangent * half_len)
		front_rings.append(front_ring)
		back_rings.append(back_ring)
	
	for ring_idx in cross_sections_2d.size():
		var front_ring := front_rings[ring_idx]
		var back_ring := back_rings[ring_idx]
		var num_points := front_ring.size()
		for i in range(num_points):
			var j := (i + 1) % num_points
			st.add_vertex(back_ring[i])
			st.add_vertex(back_ring[j])
			st.add_vertex(front_ring[i])
			st.add_vertex(back_ring[j])
			st.add_vertex(front_ring[j])
			st.add_vertex(front_ring[i])
		if add_caps and num_points >= 3:
			add_filled_caps(st, front_ring, back_ring)


static func _extrude_curved(
	st: SurfaceTool,
	cross_sections_2d: Array[Array],
	arc_length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	segments: int,
	add_caps: bool
) -> void:
	var start_tangent := start_rotation.z
	var end_tangent := end_rotation.z
	var rotation_axis := start_tangent.cross(end_tangent).normalized()
	var bend_angle := start_tangent.angle_to(end_tangent)
	var radius := arc_length / bend_angle
	var to_center := start_tangent.cross(rotation_axis).normalized() * radius
	
	var all_rings: Array[Array] = []
	for seg in range(segments + 1):
		var t := float(seg) / float(segments)
		var angle := bend_angle * t
		var current_to_center := to_center.rotated(rotation_axis, angle)
		var center_pos := current_to_center - to_center
		var local_right := start_rotation.x.rotated(rotation_axis, angle)
		var local_up := start_rotation.y.rotated(rotation_axis, angle)
		var seg_rings: Array[Array] = []
		for cross_section_2d in cross_sections_2d:
			var ring: Array[Vector3] = []
			for p in cross_section_2d:
				var pos_3d: Vector3 = center_pos + local_right * p.x + local_up * p.y
				ring.append(pos_3d)
			seg_rings.append(ring)
		all_rings.append(seg_rings)
	
	# Center the mesh
	var mid_angle := bend_angle / 2.0
	var mid_to_center := to_center.rotated(rotation_axis, mid_angle)
	var mid_pos := mid_to_center - to_center
	for seg_rings in all_rings:
		for ring in seg_rings:
			for k in range(ring.size()):
				ring[k] -= mid_pos
	
	# Stitch segments
	for seg in range(segments):
		var rings_a := all_rings[seg]
		var rings_b := all_rings[seg + 1]
		for ring_idx in cross_sections_2d.size():
			var ring_a: Array[Vector3] = rings_a[ring_idx]
			var ring_b: Array[Vector3] = rings_b[ring_idx]
			var num_points := ring_a.size()
			for i in range(num_points):
				var j := (i + 1) % num_points
				st.add_vertex(ring_a[i])
				st.add_vertex(ring_a[j])
				st.add_vertex(ring_b[i])
				st.add_vertex(ring_a[j])
				st.add_vertex(ring_b[j])
				st.add_vertex(ring_b[i])
	
	if add_caps:
		var first_rings := all_rings[0]
		var last_rings := all_rings[segments]
		for ring_idx in cross_sections_2d.size():
			var first_ring: Array[Vector3] = first_rings[ring_idx]
			var last_ring: Array[Vector3] = last_rings[ring_idx]
			if first_ring.size() >= 3:
				add_filled_caps(st, first_ring, last_ring)



## Extrude a closed shape between two parallel rings with side faces and filled caps
static func extrude_shape_with_caps(st: SurfaceTool, front_ring: Array[Vector3], back_ring: Array[Vector3]) -> void:
	var num_points := front_ring.size()
	
	# Side faces
	for i in range(num_points):
		var j := (i + 1) % num_points
		st.add_vertex(front_ring[i])
		st.add_vertex(front_ring[j])
		st.add_vertex(back_ring[i])
		st.add_vertex(front_ring[j])
		st.add_vertex(back_ring[j])
		st.add_vertex(back_ring[i])
	
	# Filled caps
	add_filled_caps(st, front_ring, back_ring)

## Add triangulated filled caps to front and back rings
static func add_filled_caps(st: SurfaceTool, front_ring: Array[Vector3], back_ring: Array[Vector3]) -> void:
	var num_points := front_ring.size()
	var front_center := Vector3.ZERO
	var back_center := Vector3.ZERO
	for p in front_ring:
		front_center += p
	for p in back_ring:
		back_center += p
	front_center /= float(num_points)
	back_center /= float(num_points)
	
	for i in range(num_points):
		var j := (i + 1) % num_points
		st.add_vertex(front_center)
		st.add_vertex(front_ring[j])
		st.add_vertex(front_ring[i])
		st.add_vertex(back_center)
		st.add_vertex(back_ring[i])
		st.add_vertex(back_ring[j])


static func add_hollow_ring_caps(
	st: SurfaceTool,
	outer_front: Array[Vector3],
	inner_front: Array[Vector3],
	outer_back: Array[Vector3],
	inner_back: Array[Vector3]
) -> void:
	var num_points := outer_front.size()
	
	# Front cap
	for i in range(num_points):
		var j := (i + 1) % num_points
		st.add_vertex(outer_front[i])
		st.add_vertex(inner_front[i])
		st.add_vertex(outer_front[j])
		st.add_vertex(outer_front[j])
		st.add_vertex(inner_front[i])
		st.add_vertex(inner_front[j])
	
	# Back cap
	for i in range(num_points):
		var j := (i + 1) % num_points
		st.add_vertex(outer_back[i])
		st.add_vertex(outer_back[j])
		st.add_vertex(inner_back[i])
		st.add_vertex(outer_back[j])
		st.add_vertex(inner_back[j])
		st.add_vertex(inner_back[i])
