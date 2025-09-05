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


## Creates a prism mesh with specified number of sides, radius and length
static func create_prism(sides: int, radius: float, length: float, thickness_modifier: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step := TAU / float(sides)
	var half_len := length * TORUS_SCALE_FACTOR * 0.5

	# top and bottom rings
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for i in sides:
		var angle := i * step
		var x := cos(angle) * radius * thickness_modifier
		var y := sin(angle) * radius * thickness_modifier
		top.append(Vector3(x, y, half_len))
		bottom.append(Vector3(x, y, -half_len))

	# sides
	for i in sides:
		var j := (i + 1) % sides
		st.add_vertex(bottom[i])
		st.add_vertex(bottom[j])
		st.add_vertex(top[i])

		st.add_vertex(bottom[j])
		st.add_vertex(top[j])
		st.add_vertex(top[i])

	# caps
	var top_center := Vector3(0, 0, half_len)
	var bottom_center := Vector3(0, 0, -half_len)
	for i in sides:
		var j := (i + 1) % sides
		# top
		st.add_vertex(top_center)
		st.add_vertex(top[i])
		st.add_vertex(top[j])
		# bottom
		st.add_vertex(bottom_center)
		st.add_vertex(bottom[j])
		st.add_vertex(bottom[i])

	st.index()
	st.generate_normals()
	return st.commit()


## Creates appropriate mesh based on element type
static func create_element_mesh(type: String, length: float, thickness_modifier: float = 1.0) -> Mesh:
	match type:
		"Drift":
			var m := BoxMesh.new()
			m.size = Vector3(
				0.2 * thickness_modifier,
				0.2 * thickness_modifier,
				length * TORUS_SCALE_FACTOR
			)
			return m
		"Bend", "RBend", "SimpleThinBend":
			var m := BoxMesh.new()
			m.size = Vector3(
				0.3 * thickness_modifier,
				0.3 * thickness_modifier,
				length * TORUS_SCALE_FACTOR
			)
			return m 
		"Quadrupole":
			return create_prism(4, 0.25, length) # square
		"Sextupole":
			return create_prism(6, 0.25, length) # hexagon
		"Octupole":
			return create_prism(8, 0.25, length) # octagon
		"Multipole":
			return create_prism(10, 0.25, length) # dodecagon
		"Solenoid":
			var m := CylinderMesh.new()
			m.height = length
			m.top_radius = 0.3
			m.bottom_radius = 0.3
			return m
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.2, 0.2, length if length > 0 else 0.2)
			return m


## Builds box meshes for survey elements with a nonzero length and no aperture data
static func build_box_meshes(
	survey_data: Array[Dictionary], 
	aperture_material: Material,
	progress_callback: Callable = Callable(),
	static_body_callback: Callable = Callable(),
	thickness_modifier: float = 1.0
) -> void:
	print("Building box meshes...")
	
	# Remember the last nonzero tangent
	var prev_tangent := Vector3.FORWARD
	
	for i in range(survey_data.size()):
		var slice := survey_data[i]
		if slice.length <= 0.0:
			continue
		
		# --- Tangent calculation ---
		var tangent: Vector3
		if i > 0:
			tangent = slice.center - survey_data[i - 1].center
		else:
			tangent = prev_tangent
		
		if tangent.length_squared() < 1e-12:
			tangent = prev_tangent
		else:
			tangent = tangent.normalized()
		prev_tangent = tangent  # save for next iteration
		
		# --- Build Frenet-like frame ---
		var up := Vector3.UP
		if abs(tangent.dot(up)) > 0.9:
			up = Vector3.RIGHT
		
		var normal := (up - tangent * up.dot(tangent)).normalized()
		var binormal := tangent.cross(normal).normalized()
		
		var frame := Basis()
		frame.x = normal
		frame.y = binormal
		frame.z = tangent
		
		var box := create_element_mesh(slice.type, slice.length, thickness_modifier)
		var mat := aperture_material.duplicate()
		mat.set_shader_parameter("albedo", ElementColors.get_element_color(slice.type))
		box.surface_set_material(0, mat)

		var mesh_instance := ElementMeshInstance.new()
		mesh_instance.name = "box"
		mesh_instance.mesh = box
		mesh_instance.type = slice.type
		mesh_instance.first_slice_name = slice.id
		
		var static_body := StaticBody3D.new()
		static_body.name = "Box_%d_%s" % [i, slice.type]
		static_body.transform = Transform3D(frame, slice.center)
	
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = box.create_convex_shape()

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
	var prev_slice := {}
	var prev_verts: Array[Vector3] = []
	var prev_tangent := Vector3.FORWARD
	var prev_angle_offset := 0.0
	var prev_type: String = survey_data[0].type

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
			
		if prev_type != curr_slice.type:
			st.set_color(ElementColors.get_element_color(curr_slice.type))

		# Here, we're essentially finding the rotation to angle our edge vertices by finding
		# the direction from one slice to the next as our tangent, then getting its normal and 
		# binormal. This lets us build our own Frenet frame, which we can then minimise the
		# rotation on to prevent Frenet twist
		var curr_center: Vector3 = curr_slice.center
		var tangent: Vector3 = (curr_center - prev_slice.center) if has_prev else prev_tangent
		
		# To catch weird edge cases like two slices intersecting
		if tangent.length_squared() < 1e-12:
			tangent = prev_tangent

		var up := Vector3.UP
		if abs(tangent.dot(up)) > 0.9:
			up = Vector3.RIGHT

		var normal := (up - tangent * up.dot(tangent)).normalized()
		var binormal := tangent.cross(normal).normalized()
		if abs(curr_slice.psi) > 1e-6:
			normal = normal.rotated(tangent, curr_slice.psi)
			binormal = binormal.rotated(tangent, curr_slice.psi)

		prev_tangent = tangent

		# Build those vertices in 3D space
		var curr_verts : Array[Vector3] = []
		for i in len(points_2d):
			var p2 := points_2d[i]
			curr_verts.append(curr_center + normal * p2.x + binormal * p2.y)

		# Stitching process. If we have a previous slice, then we minimise the rotation
		# and stitch them together
		if has_prev:
			var num_verts := len(curr_verts)
			var ref_prev: Vector3 = prev_verts[0] - prev_slice.center
			var ref_curr: Vector3 = curr_verts[0] - curr_center

			var dot_val = clamp(ref_prev.dot(ref_curr), -1.0, 1.0)
			var cross_val = tangent.dot(ref_prev.cross(ref_curr))
			prev_angle_offset += atan2(cross_val, dot_val)

			var index_shift := int(round(prev_angle_offset / (TAU / num_verts)))
			var rotated_ring: Array[Vector3] = []
			for i in num_verts:
				rotated_ring.append(curr_verts[(i + index_shift) % num_verts])

			curr_verts = rotated_ring

			for j in len(curr_verts):
				var jn = (j + 1) % len(curr_verts)
				st.add_vertex(prev_verts[j])
				st.add_vertex(prev_verts[jn])
				st.add_vertex(curr_verts[j])

				st.add_vertex(prev_verts[jn])
				st.add_vertex(curr_verts[jn])
				st.add_vertex(curr_verts[j])

		prev_slice = curr_slice
		prev_verts = curr_verts
		has_prev = true
		
		progress_callback.call(aperture_index)

	st.index()
	st.generate_normals()
	st.optimize_indices_for_cache()
	return st.commit()
