class_name MeshBuilder
extends RefCounted

# Constants
const BEAM_ELLIPSE_RESOLUTION := 20
const TORUS_SCALE_FACTOR := 1.0


## Creates an ellipse from a parsed twiss line, with width and height according to sigma in x and y
static func create_beam_ellipse(twiss_line: PackedStringArray, thickness_modifier: float = 1.0) -> Array[Vector2]:
	var twiss := DataLoader.parse_twiss_line(twiss_line)
	var pts: Array[Vector2] = []
	var center: Vector2 = twiss.position
	var sigma: Vector2 = twiss.sigma
	var step := TAU / float(BEAM_ELLIPSE_RESOLUTION)
	
	for i in BEAM_ELLIPSE_RESOLUTION:
		var angle := i * step
		pts.append(center + Vector2(cos(angle) * sigma.x, sin(angle) * sigma.y))
	
	var result: Array[Vector2]
	result.assign(pts.map(func(v): return v * thickness_modifier))
	return result


## Creates a mesh that follows an arc with a given cross-section
## cross_section_func should return Array[Array[Vector2]] representing multiple disjoint polygons in XY plane
static func create_bent_mesh(
	cross_section_func: Callable,  # () -> Array[Array[Vector2]]
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
		var half_len := length * TORUS_SCALE_FACTOR * 0.5
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
		
		# Create sides for each sub-shape
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
					# Front cap
					st.add_vertex(front_center)
					st.add_vertex(front_ring[j])
					st.add_vertex(front_ring[i])
					# Back cap
					st.add_vertex(back_center)
					st.add_vertex(back_ring[i])
					st.add_vertex(back_ring[j])
		
		st.index()
		st.generate_normals()
		return st.commit()
	
	rotation_axis = rotation_axis.normalized()
	
	var arc_length := length * TORUS_SCALE_FACTOR
	var radius := arc_length / bend_angle
	
	var to_center := start_tangent.cross(rotation_axis).normalized() * radius
	
	var all_rings: Array[Array] = []  # Array[segment][sub-shape][vertex]
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
	
	var mid_angle := bend_angle / 2.0
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
			var num_points := first_ring.size()
			
			if num_points >= 3:
				var first_center := Vector3.ZERO
				var last_center := Vector3.ZERO
				for p in first_ring:
					first_center += p
				for p in last_ring:
					last_center += p
				first_center /= float(num_points)
				last_center /= float(num_points)
				
				for i in range(num_points):
					var j := (i + 1) % num_points
					st.add_vertex(first_center)
					st.add_vertex(first_ring[j])
					st.add_vertex(first_ring[i])
					
					st.add_vertex(last_center)
					st.add_vertex(last_ring[i])
					st.add_vertex(last_ring[j])
	
	st.index()
	st.generate_normals()
	return st.commit()


## Creates appropriate bent mesh for an element based on type and cross-section
static func create_element_mesh(
	type: String,
	length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	thickness_modifier: float = 1.0,
	add_caps: bool = true
) -> Mesh:

	var box_cross_section = func (width: float, height: float, offset: Vector2 = Vector2.ZERO) -> Array[Array]:
		var w := width * thickness_modifier
		var h := height * thickness_modifier
		return [[
			Vector2(-w, -h) + offset,
			Vector2(w, -h) + offset,
			Vector2(w, h) + offset,
			Vector2(-w, h) + offset
		]]
	
	var equals_sign_cross_section = func () -> Array[Array]:
		var w := 0.3 * thickness_modifier
		var h := 0.1 * thickness_modifier
		var gap := 0.3 * thickness_modifier
		return [
			box_cross_section.call(w, h, Vector2(0, gap / 2))[0],
			box_cross_section.call(w, h, Vector2(0, -gap / 2))[0]
		]
	
	var multi_box_cross_section = func (num_poles: int, width: float, height: float, radius: float) -> Array[Array]:
		var polys: Array[Array] = []
		for i in num_poles:
			var angle := TAU * (float(i) + 1) / float(num_poles)
			var offset := Vector2(cos(angle), sin(angle)) * radius * thickness_modifier
			var w := width * thickness_modifier
			var h := height * thickness_modifier
			
			var poly: Array[Vector2] = [
				Vector2(-w, -h),
				Vector2(w, -h),
				Vector2(w, h),
				Vector2(-w, h)
			]
			var rotation_angle := angle + PI / 2
			var rotated_poly: Array = poly.map(func(p): return p.rotated(rotation_angle))

			rotated_poly = rotated_poly.map(func(p): return p + offset)
			polys.append(rotated_poly)
		return polys
	
	var circle_cross_section = func (radius: float = 0.3, sides: int = 20) -> Array[Array]:
		var pts: Array[Vector2] = []
		for i in range(sides):
			var a := TAU * float(i) / float(sides)
			pts.append(Vector2(cos(a), sin(a)) * radius * thickness_modifier)
		return [pts]
	
	var cross_section_func: Callable
	match type:
		"Drift", "DriftSlice":
			add_caps = false
			cross_section_func = box_cross_section.bind(0.2, 0.2)
		"LimitEllipse", "UniformSolenoid", "Solenoid":
			cross_section_func = circle_cross_section.bind(0.3)
		"Bend", "RBend", "SimpleThinBend":
			cross_section_func = equals_sign_cross_section
		"Quadrupole":
			cross_section_func = multi_box_cross_section.bind(4, 0.3, 0.08, 0.3)
		"Sextupole":
			cross_section_func = multi_box_cross_section.bind(6, 0.2, 0.07, 0.3)
		"Octupole":
			cross_section_func = multi_box_cross_section.bind(8, 0.08, 0.05, 0.3)
		"Multipole", "Multipole Kick":
			cross_section_func = multi_box_cross_section.bind(10, 0.07, 0.04, 0.3)
		_:
			cross_section_func = box_cross_section.bind(0.3, 0.3)
	
	return create_bent_mesh(
		cross_section_func,
		length,
		start_rotation,
		end_rotation,
		8,
		add_caps
	)


## Builds box meshes for survey elements
static func build_box_meshes(
	survey_data: Array[Dictionary], 
	aperture_material: Material,
	progress_callback: Callable = Callable(),
	static_body_callback: Callable = Callable(),
	thickness_modifier: float = 1.0
) -> void:
	print("Building box meshes...")
	
	for i in range(survey_data.size()):
		var slice := survey_data[i]
		
		# Turns out when you aren't converting radians to radians via deg_to_rad(), the rotations work properly
		# So, yes, we can use simple Basis construction rather than Frenet framing from averages
		var start_rotation := Basis.from_euler(Vector3(slice.psi, slice.theta, slice.phi), EULER_ORDER_XYZ)
		var end_rotation := start_rotation

		# Ok, we need to see if the angle for the next element is different. If it is, we need to bend.
		# If we are bending, then we need to offset the resultant mesh's position by the arc's centre,
		# which obviously bows out unlike the straight meshes
		if i + 1 < len(survey_data):
			var next_slice := survey_data[i + 1]
			end_rotation = Basis.from_euler(Vector3(next_slice.psi, next_slice.theta, next_slice.phi), EULER_ORDER_XYZ)
		
		var box_position: Vector3
		var start_tangent := start_rotation.z
		var end_tangent := end_rotation.z
		var rotation_axis := start_tangent.cross(end_tangent)
		var bend_angle := start_tangent.angle_to(end_tangent)
		var arc_length: float = slice.length * TORUS_SCALE_FACTOR
	
		if bend_angle < 1e-6 or rotation_axis.length_squared() < 1e-12:
			# Straight = offset by half-length along tangent, nice and easy
			box_position = slice.position + start_tangent * (arc_length * 0.5)
		else:
			# Bent = compute arc midpoint, find that position, offset by that
			# this took a while to sort out
			rotation_axis = rotation_axis.normalized()
			var radius := arc_length / bend_angle
			var to_center := start_tangent.cross(rotation_axis).normalized() * radius
			var mid_angle := bend_angle / 2.0
			var mid_to_center := to_center.rotated(rotation_axis, mid_angle)
			var mid_pos := mid_to_center - to_center
			box_position = slice.position + mid_pos
	
		var box := create_element_mesh(
			slice.element_type, 
			slice.length, 
			start_rotation, 
			end_rotation, 
			thickness_modifier
		)
			
		var mat: Material = aperture_material.duplicate()
		mat.albedo_color = ElementColors.get_element_color(slice.element_type)
		box.surface_set_material(0, mat)

		var mesh_instance := ElementMeshInstance.new()
		mesh_instance.name = "box"
		mesh_instance.mesh = box
		mesh_instance.type = slice.element_type
		mesh_instance.first_slice_name = slice.name
		mesh_instance.other_info = JSON.stringify(slice, "\t", false) # gotta be a better way but eh
		
		var static_body := StaticBody3D.new()
		static_body.name = "Box_%d_%s" % [i, slice.element_type]
		static_body.transform = Transform3D(Basis.IDENTITY, box_position) # mesh already rotated
	
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = box.create_convex_shape()
		
		if slice.element_type == "Multipole":
			var kick_box := create_element_mesh(
				"Multipole Kick", 
				0, 
				start_rotation, 
				end_rotation, 
				thickness_modifier
			)
			
			var mat_kick: Material = aperture_material.duplicate()
			mat_kick.albedo_color = ElementColors.get_element_color("Multipole Kick")
			kick_box.surface_set_material(0, mat_kick)
			
			var kick_instance := ElementMeshInstance.new()
			kick_instance.name = "box"
			kick_instance.mesh = kick_box
			kick_instance.type = "Multipole Kick"
			kick_instance.first_slice_name = slice.name
			kick_instance.other_info = JSON.stringify(slice, "\t", false) # gotta be a better way but eh
			kick_instance.position.z = -slice.length / 2
			
			var kick_collision_shape := CollisionShape3D.new()
			kick_collision_shape.shape = kick_box.create_convex_shape()
			
			static_body.add_child(kick_instance)
			static_body.add_child(kick_collision_shape)

		static_body.add_child(mesh_instance)
		static_body.add_child(collision_shape)
		
		if static_body_callback.is_valid():
			static_body_callback.call(static_body)
		
		if progress_callback.is_valid():
			progress_callback.call(i)
	
	print("Box mesh generation complete.")


## Creates a SurfaceTool and populates it with toroidal data, to be committed to an ArrayMesh or to arrays
static func build_sweep_mesh(
	survey_data: Array[Dictionary], 
	data_path: String, 
	get_points_func: Callable, 
	progress_callback: Callable = Callable()
) -> ArrayMesh:
	print("Building mesh from %s..." % data_path)
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var df := FileAccess.open(data_path, FileAccess.READ)
	if df == null:
		push_error("Could not open data CSV file.")
		return ArrayMesh.new()
		
	# Skip headers
	df.get_csv_line()
	
	var aperture_index := 0
	var has_prev := false
	var prev_verts: Array[Vector3] = []
	var prev_type: String = survey_data[0].element_type

	st.set_color(ElementColors.get_element_color(survey_data[0].element_type))

	while not df.eof_reached():
		var data_line := df.get_csv_line()
		if len(data_line) < 5:
			continue

		var curr_slice := survey_data[aperture_index]
		aperture_index += 1

		# Get the 2D cross-section points via callback
		var points_2d: Array[Vector2] = get_points_func.call(data_line)
		if points_2d.is_empty():
			continue
			
		if prev_type != curr_slice.element_type:
			st.set_color(ElementColors.get_element_color(curr_slice.element_type))
			prev_type = curr_slice.element_type

		# Compute the local basis from the Euler angles in the survey data
		var curr_center: Vector3 = curr_slice.position
		var curr_rotation := Basis.from_euler(Vector3(curr_slice.psi, curr_slice.theta, curr_slice.phi), EULER_ORDER_XYZ)
		
		# Build vertices in 3D space using the local basis
		var curr_verts: Array[Vector3] = []
		for p in points_2d:
			curr_verts.append(curr_center + curr_rotation.x * p.x + curr_rotation.y * p.y)

		# Stitching process
		if has_prev:
			var num_verts := len(curr_verts)
			for j in num_verts:
				var jn := (j + 1) % num_verts
				st.add_vertex(prev_verts[j])
				st.add_vertex(prev_verts[jn])
				st.add_vertex(curr_verts[j])

				st.add_vertex(prev_verts[jn])
				st.add_vertex(curr_verts[jn])
				st.add_vertex(curr_verts[j])

		prev_verts = curr_verts
		has_prev = true
		
		progress_callback.call(aperture_index)

	st.index()
	st.generate_normals()
	st.optimize_indices_for_cache()
	return st.commit()
