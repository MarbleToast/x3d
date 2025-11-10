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
		_extrude_straight_canonical(st, cross_sections_2d, length, add_caps)
	else:
		_extrude_curved_canonical(st, cross_sections_2d, length, bend_angle, segments, add_caps)

	st.index()
	st.generate_normals()
	return st.commit()


static func _extrude_straight_canonical(
	st: SurfaceTool,
	cross_sections_2d: Array[Array],
	length: float,
	add_caps: bool
) -> void:
	var half_len := length * 0.5

	for cross_section_2d in cross_sections_2d:
		var front_ring: Array[Vector3] = []
		var back_ring: Array[Vector3] = []
		for p in cross_section_2d:
			var pos_3d := Vector3(p.x, p.y, 0)
			front_ring.append(pos_3d + Vector3(0, 0, half_len))
			back_ring.append(pos_3d - Vector3(0, 0, half_len))
		extrude_shape(st, front_ring, back_ring, add_caps)


static func _extrude_curved_canonical(
	st: SurfaceTool,
	cross_sections_2d: Array[Array],
	arc_length: float,
	bend_angle: float,
	segments: int,
	add_caps: bool
) -> void:
	var start_rotation := Basis.IDENTITY
	var start_tangent := Vector3(0, 0, 1)
	var rotation_axis := Vector3(0, -1, 0)

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

	var mid_angle := bend_angle * 0.5
	var mid_to_center := to_center.rotated(rotation_axis, mid_angle)
	var mid_pos := mid_to_center - to_center
	for seg_rings in all_rings:
		for ring in seg_rings:
			for k in range(ring.size()):
				ring[k] -= mid_pos

	for seg in range(segments):
		var rings_a := all_rings[seg]
		var rings_b := all_rings[seg + 1]
		for ring_idx in cross_sections_2d.size():
			var ring_a: Array[Vector3] = rings_a[ring_idx]
			var ring_b: Array[Vector3] = rings_b[ring_idx]
			_stitch_rings(st, ring_a, ring_b)

	if add_caps:
		for ring_idx in cross_sections_2d.size():
			add_filled_caps(st, all_rings[0][ring_idx], all_rings[segments][ring_idx])


static func _stitch_rings(st: SurfaceTool, ring_a: Array[Vector3], ring_b: Array[Vector3]) -> void:
	var n := ring_a.size()
	for i in range(n):
		var j := (i + 1) % n
		st.add_vertex(ring_a[i])
		st.add_vertex(ring_a[j])
		st.add_vertex(ring_b[i])
		st.add_vertex(ring_a[j])
		st.add_vertex(ring_b[j])
		st.add_vertex(ring_b[i])


static func extrude_shape(st: SurfaceTool, front_ring: Array[Vector3], back_ring: Array[Vector3], add_caps: bool) -> void:
	_stitch_rings(st, front_ring, back_ring)
	if add_caps:
		add_filled_caps(st, front_ring, back_ring)


static func add_filled_caps(st: SurfaceTool, front_ring: Array[Vector3], back_ring: Array[Vector3]) -> void:
	var n := front_ring.size()
	if n < 3:
		return

	var front_center := Vector3.ZERO
	var back_center := Vector3.ZERO
	for p in front_ring:
		front_center += p
	for p in back_ring:
		back_center += p
	front_center /= float(n)
	back_center /= float(n)

	for i in range(n):
		var j := (i + 1) % n
		st.add_vertex(front_center)
		st.add_vertex(front_ring[j])
		st.add_vertex(front_ring[i])
		st.add_vertex(back_center)
		st.add_vertex(back_ring[i])
		st.add_vertex(back_ring[j])
