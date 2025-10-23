## This bad boy handles all the mesh generation for visualisation purposes
class_name MeshBuilder
extends RefCounted

# ====================== Constants
## How many vertices make up one cross-section of the beam?
const BEAM_ELLIPSE_RESOLUTION := 20

## When considering the overall size of the accelerator, what should we scale the overall length of the torus?
const TORUS_SCALE_FACTOR := 1.0

## Holds each notable element's properties for visualisation.
## [br]
## [br]type [box, equals, circle, multipole] = the cross section type
## [br]width [box, equals] = the transverse width of the cross-section
## [br]height [box] = the transverse height of the cross-section 
## [br]bar_height [equals] = how thick each bar should be in an equals cross-section
## [br]gap [equals] = how tall the gap should be in an equals cross-section
## [br]radius [circle] = the radius of a circle cross-section
## [br]num_poles [multibox] = how many disjoint boxes should there be radially in the cross-section
## [br]pole_width [multibox] = how wide a dijoint box should be
## [br]pole_height [multibox] = how tall a dijoint box should be
## [br]pole_radius [multibox] = how far out from the centre should a pole be
const ELEMENT_DIMENSIONS := {
	Drift = { width = 0.2, height = 0.2, type = "box" },
	DriftSlice = { width = 0.2, height = 0.2, type = "box" },
	Quadrupole = { width = 0.3, height = 0.3, type = "box" },
	Bend = { width = 0.3, bar_height = 0.1, gap = 0.3, type = "equals" },
	RBend = { width = 0.3, bar_height = 0.1, gap = 0.3, type = "equals" },
	SimpleThinBend = { width = 0.3, bar_height = 0.1, gap = 0.3, type = "equals" },
	LimitEllipse = { radius = 0.3, type = "circle" },
	UniformSolenoid = { radius = 0.3, type = "circle" },
	Solenoid = { radius = 0.3, type = "circle" },
	Sextupole = { num_poles = 6, pole_width = 0.12, pole_height = 0.07, pole_radius = 0.3, type = "multipole" },
	Octupole = { num_poles = 8, pole_width = 0.08, pole_height = 0.05, pole_radius = 0.3, type = "multipole" },
	Multipole = { num_poles = 10, pole_width = 0.07, pole_height = 0.04, pole_radius = 0.3, type = "multipole" },
	MultipoleKick = { num_poles = 10, pole_width = 0.07, pole_height = 0.04, pole_radius = 0.3, type = "multipole" },
	_default = { width = 0.3, height = 0.3, type = "box" }
}

# ===================== Caches and getters
## Stores materials for each element rather than duplicating and setting colour each element
static var _base_material_cache := {}

## Stores similar collision shapes so they don't need to be regenerated
static var _collision_shape_cache := {}

## Stores Basis instances that could be shared rather than recreating them (eg. for straight sections)
static var _basis_cache := {}


## Returns material instance for given colour, either from cache or newly created
static func get_base_material(base_material: Material, colour: Color) -> Material:
	var key := colour.to_html()
	if not _base_material_cache.has(key):
		var mat := base_material.duplicate()
		mat.albedo_color = colour
		_base_material_cache[key] = mat
	return _base_material_cache[key]


## Returns collision shape instance for given type and length, either from cache or newly created
static func get_collision_shape_for_element(
	type: String, 
	length: float, 
	thickness_modifier: float
) -> Shape3D:
	# Create key based on type and dimensions - this needs to be element type because otherwise
	# all multipoles and multipole kicks have the same key, leading to weird colliders
	# 3 d.p on length to increase cache hits (and that level of accuracy is fine)
	var key := "%s_%.3f_%f" % [type, length, thickness_modifier]
	
	if _collision_shape_cache.has(key):
		return _collision_shape_cache[key]
	
	var shape: Shape3D
	var collision_length := length * TORUS_SCALE_FACTOR
	
	var dims: Dictionary = ELEMENT_DIMENSIONS.get(type, ELEMENT_DIMENSIONS["_default"])
	
	match dims.type:
		"box":
			var box := BoxShape3D.new()
			var w: float = dims.width * thickness_modifier
			var h: float = dims.height * thickness_modifier
			box.size = Vector3(w * 2.0, h * 2.0, collision_length)
			shape = box
			
		"equals":
			var box := BoxShape3D.new()
			var w: float = dims.width * thickness_modifier
			var bar_h: float = dims.bar_height * thickness_modifier
			var gap: float = dims.gap * thickness_modifier
			var total_height: float = bar_h * 2.0 + gap
			box.size = Vector3(w * 2.0, total_height, collision_length)
			shape = box
			
		"circle":
			var cylinder := CylinderShape3D.new()
			var r: float = dims.radius * thickness_modifier
			cylinder.radius = r
			cylinder.height = collision_length
			shape = cylinder
			
		"multipole":
			var cylinder := CylinderShape3D.new()
			var pole_r: float = dims.pole_radius * thickness_modifier
			var pole_w: float = dims.pole_width * thickness_modifier
			cylinder.radius = pole_r + pole_w
			cylinder.height = collision_length
			shape = cylinder
	
	_collision_shape_cache[key] = shape
	return shape


## Returns basis instance for given Euler angles, either from cache or newly created
static func get_cached_basis(psi: float, theta: float, phi: float) -> Basis:
	# Round to reasonable precision to improve cache hits
	var key := "%.2f_%.2f_%.2f" % [psi, theta, phi]
	if not _basis_cache.has(key):
		_basis_cache[key] = Basis.from_euler(Vector3(psi, theta, phi), EULER_ORDER_XYZ)
	return _basis_cache[key]


## Clear all caches to free memory
static func clear_caches() -> void:
	_base_material_cache.clear()
	_collision_shape_cache.clear()
	_basis_cache.clear()
	print("MeshBuilder caches cleared")


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
## Now supports creating multipole with integrated kick visualization
static func create_element_mesh(
	type: String,
	length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	thickness_modifier: float = 1.0,
	add_caps: bool = true,
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
		var gap := 0.4 * thickness_modifier
		return [
			box_cross_section.call(w, h, Vector2(0, gap / 2))[0],
			box_cross_section.call(w, h, Vector2(0, -gap / 2))[0]
		]
	
	var multi_box_cross_section = func (num_poles: int, width: float, height: float, radius: float) -> Array[Array]:
		var polys: Array[Array] = []
		for i in num_poles:
			var angle := TAU * float(i) / num_poles + TAU / (2 * num_poles)
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
	var dimensions: Dictionary = ELEMENT_DIMENSIONS.get(type, ELEMENT_DIMENSIONS._default)
	
	match dimensions.type:
		"box":
			cross_section_func = box_cross_section.bind(
				dimensions.width, 
				dimensions.height
			)
		"circle":
			cross_section_func = circle_cross_section.bind(
				dimensions.radius
			)
		"equals":
			cross_section_func = equals_sign_cross_section
		"multipole":
			cross_section_func = multi_box_cross_section.bind(
				dimensions.num_poles, 
				dimensions.pole_width,
				dimensions.pole_height,
				dimensions.pole_radius,
			)
	
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
		
		var start_rotation := get_cached_basis(slice.psi, slice.theta, slice.phi)
		var end_rotation := start_rotation

		if i + 1 < len(survey_data):
			var next_slice := survey_data[i + 1]
			end_rotation = get_cached_basis(next_slice.psi, next_slice.theta, next_slice.phi)
		
		var box_position: Vector3
		var start_tangent := start_rotation.z
		var end_tangent := end_rotation.z
		var rotation_axis := start_tangent.cross(end_tangent)
		var bend_angle := start_tangent.angle_to(end_tangent)
		var arc_length: float = slice.length * TORUS_SCALE_FACTOR
	
		if bend_angle < 1e-6 or rotation_axis.length_squared() < 1e-12:
			box_position = slice.position + start_tangent * (arc_length * 0.5)
		else:
			rotation_axis = rotation_axis.normalized()
			var radius := arc_length / bend_angle
			var to_center := start_tangent.cross(rotation_axis).normalized() * radius
			var mid_angle := bend_angle / 2.0
			var mid_to_center := to_center.rotated(rotation_axis, mid_angle)
			var mid_pos := mid_to_center - to_center
			box_position = slice.position + mid_pos
	
		# Create main mesh
		var box := create_element_mesh(
			slice.element_type, 
			slice.length, 
			start_rotation, 
			end_rotation, 
			thickness_modifier
		)

		var colour := ElementColors.get_element_color(slice.element_type)
		var base_mat := get_base_material(aperture_material, colour)
		var mat := base_mat.duplicate()  # Each instance gets its own material
		box.surface_set_material(0, mat)

		var mesh_instance := ElementMeshInstance.new()
		mesh_instance.name = "box"
		mesh_instance.mesh = box
		mesh_instance.type = slice.element_type
		mesh_instance.first_slice_name = slice.name
		mesh_instance.other_info = slice
		
		var static_body := StaticBody3D.new()
		static_body.name = "Box_%d_%s" % [i, slice.element_type]
		static_body.transform = Transform3D(Basis.IDENTITY, box_position)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = get_collision_shape_for_element(
			slice.element_type, 
			slice.length, 
			thickness_modifier
		)
		collision_shape.transform = Transform3D(start_rotation)
		if collision_shape.shape is CylinderShape3D:
			collision_shape.rotation.x = PI / 2.0
		
		if slice.element_type == "Multipole":
			var kick_mesh := create_element_mesh(
				"MultipoleKick", 
				0.0,
				start_rotation, 
				end_rotation, 
				thickness_modifier,
				true
			)
			
			var kick_color := ElementColors.get_element_color("MultipoleKick")
			var kick_base_mat := get_base_material(aperture_material, kick_color)
			var kick_mat := kick_base_mat.duplicate()
			kick_mesh.surface_set_material(0, kick_mat)
			
			var kick_collision := CollisionShape3D.new()
			kick_collision.shape = get_collision_shape_for_element(
				"MultipoleKick",
				0.02,
				thickness_modifier
			)
			kick_collision.transform = Transform3D(start_rotation)
			kick_collision.rotation.x = PI / 2.0
			
			var kick_instance := ElementMeshInstance.new()
			kick_instance.name = "box"
			kick_instance.mesh = kick_mesh
			kick_instance.type = "MultipoleKick"
			kick_instance.first_slice_name = slice.name + " (Kick)"
			kick_instance.other_info = slice
			
			var kick_body := StaticBody3D.new()
			kick_body.name = "Box_%d_%s" % [i, slice.element_type]
			kick_body.transform = Transform3D(Basis.IDENTITY, box_position + start_rotation * Vector3(0, 0, -slice.length/2))
			
			kick_body.add_child(kick_instance)
			kick_body.add_child(kick_collision)
			
			if static_body_callback.is_valid():
				static_body_callback.call(kick_body)

		static_body.add_child(mesh_instance)
		static_body.add_child(collision_shape)
		
		if static_body_callback.is_valid():
			static_body_callback.call(static_body)
		
		if progress_callback.is_valid():
			progress_callback.call(i)
	
	print("Box mesh generation complete.")
	print("Created %s collision polyhedrons, %s materials, and %s transformation bases." % [
		len(_collision_shape_cache), len(_base_material_cache), len(_basis_cache)
	])


## Creates a SurfaceTool and populates it with toroidal data, to be committed to an ArrayMesh or to arrays
static func build_sweep_mesh(
	survey_data: Array[Dictionary], 
	line_data: Array[PackedStringArray], 
	get_points_func: Callable, 
	progress_callback: Callable = Callable()
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var has_prev := false
	var prev_verts: Array[Vector3] = []

	for aperture_index in range(len(line_data)):
		var data_line := line_data[aperture_index]
		var curr_slice := survey_data[aperture_index % len(survey_data)]
		aperture_index += 1

		# Get the 2D cross-section points via callback
		var points_2d: Array[Vector2] = get_points_func.call(data_line)
		if points_2d.is_empty():
			continue

		# Use cached basis
		var curr_center: Vector3 = curr_slice.position
		var curr_rotation := get_cached_basis(curr_slice.psi, curr_slice.theta, curr_slice.phi)
		
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
		
		if progress_callback.is_valid():
			progress_callback.call(aperture_index)

	st.index()
	st.generate_normals()
	st.optimize_indices_for_cache()
	return st.commit()


static func build_sweep_mesh_streaming(
	web_loader: WebDataLoader,
	get_line_func: Callable,  # (index: int) -> PackedStringArray
	line_count: int,
	get_points_func: Callable,  # (line: PackedStringArray) -> Array[Vector2]
	progress_callback: Callable = Callable()
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var has_prev := false
	var prev_verts: Array[Vector3] = []
	var survey_count := web_loader.get_survey_count()
	var header := web_loader.get_survey_line_raw(0)
	var column_map := DataLoader.parse_survey_header(header)

	for i in range(line_count):
		var data_line: PackedStringArray = get_line_func.call(i)
		var slice_index := i % survey_count
		var curr_slice := web_loader.get_survey_line(slice_index, column_map)
		
		if curr_slice.is_empty():
			continue

		# Get the 2D cross-section points via callback
		var points_2d: Array[Vector2] = get_points_func.call(data_line)
		if points_2d.is_empty():
			continue

		# Use cached basis
		var curr_center: Vector3 = curr_slice.position
		var curr_rotation := get_cached_basis(
			curr_slice.psi, 
			curr_slice.theta, 
			curr_slice.phi
		)
		
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
		
		if progress_callback.is_valid():
			progress_callback.call(i)

	st.index()
	st.generate_normals()
	st.optimize_indices_for_cache()
	return st.commit()


## Builds box meshes using streamed survey data
static func build_box_meshes_streaming(
	web_loader: WebDataLoader,
	aperture_material: Material,
	progress_callback: Callable = Callable(),
	static_body_callback: Callable = Callable(),
	thickness_modifier: float = 1.0
) -> void:
	print("Building box meshes (streaming)...")
	
	var survey_count := web_loader.get_survey_count()
	
	var header := web_loader.get_survey_line_raw(0)
	var column_map := DataLoader.parse_survey_header(header)
	
	for i in range(survey_count):
		var slice := web_loader.get_survey_line(i,column_map)
		if slice.is_empty():
			continue
		
		var start_rotation := get_cached_basis(slice.psi, slice.theta, slice.phi)
		var end_rotation := start_rotation

		if i + 1 < survey_count:
			var next_slice := web_loader.get_survey_line(i + 1, column_map)
			if not next_slice.is_empty():
				end_rotation = get_cached_basis(
					next_slice.psi, 
					next_slice.theta, 
					next_slice.phi
				)
		
		var box_position: Vector3
		var start_tangent := start_rotation.z
		var end_tangent := end_rotation.z
		var rotation_axis := start_tangent.cross(end_tangent)
		var bend_angle := start_tangent.angle_to(end_tangent)
		var arc_length: float = slice.length * TORUS_SCALE_FACTOR
	
		if bend_angle < 1e-6 or rotation_axis.length_squared() < 1e-12:
			box_position = slice.position + start_tangent * (arc_length * 0.5)
		else:
			rotation_axis = rotation_axis.normalized()
			var radius := arc_length / bend_angle
			var to_center := start_tangent.cross(rotation_axis).normalized() * radius
			var mid_angle := bend_angle / 2.0
			var mid_to_center := to_center.rotated(rotation_axis, mid_angle)
			var mid_pos := mid_to_center - to_center
			box_position = slice.position + mid_pos
	
		# Create main mesh
		var box := create_element_mesh(
			slice.element_type, 
			slice.length, 
			start_rotation, 
			end_rotation, 
			thickness_modifier
		)

		var colour := ElementColors.get_element_color(slice.element_type)
		var base_mat := get_base_material(aperture_material, colour)
		var mat := base_mat.duplicate()
		box.surface_set_material(0, mat)

		var mesh_instance := ElementMeshInstance.new()
		mesh_instance.name = "box"
		mesh_instance.mesh = box
		mesh_instance.type = slice.element_type
		mesh_instance.first_slice_name = slice.name
		mesh_instance.other_info = slice
		
		var static_body := StaticBody3D.new()
		static_body.name = "Box_%d_%s" % [i, slice.element_type]
		static_body.transform = Transform3D(Basis.IDENTITY, box_position)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = get_collision_shape_for_element(
			slice.element_type, 
			slice.length, 
			thickness_modifier
		)
		if collision_shape.shape is CylinderShape3D:
			collision_shape.rotation.x = PI / 2.0
		
		if slice.element_type == "Multipole":
			var kick_mesh := create_element_mesh(
				"MultipoleKick", 
				0.0,
				start_rotation, 
				end_rotation, 
				thickness_modifier,
				true
			)
			
			var kick_color := ElementColors.get_element_color("MultipoleKick")
			var kick_base_mat := get_base_material(aperture_material, kick_color)
			var kick_mat := kick_base_mat.duplicate()
			kick_mesh.surface_set_material(0, kick_mat)
			
			var kick_collision := CollisionShape3D.new()
			kick_collision.shape = get_collision_shape_for_element(
				"MultipoleKick",
				0.02,
				thickness_modifier
			)
			kick_collision.position.z = -slice.length / 2
			kick_collision.rotation.x = PI / 2.0
			
			var kick_instance := ElementMeshInstance.new()
			kick_instance.name = "box"
			kick_instance.mesh = kick_mesh
			kick_instance.type = "MultipoleKick"
			kick_instance.first_slice_name = slice.name + " (Kick)"
			kick_instance.other_info = slice
			kick_instance.position.z = -slice.length / 2
			
			var kick_body := StaticBody3D.new()
			kick_body.name = "Box_%d_%s_kick" % [i, slice.element_type]
			kick_body.transform = Transform3D(Basis.IDENTITY, box_position)
			
			kick_body.add_child(kick_instance)
			kick_body.add_child(kick_collision)
			
			if static_body_callback.is_valid():
				static_body_callback.call(kick_body)

		static_body.add_child(mesh_instance)
		static_body.add_child(collision_shape)
		
		if static_body_callback.is_valid():
			static_body_callback.call(static_body)
		
		if progress_callback.is_valid():
			progress_callback.call(i)
		
		# Yield every 10 elements to prevent blocking
		if i % 10 == 0:
			await Engine.get_main_loop().process_frame
	
	print("Box mesh generation complete (streaming).")
	print("Created %s collision polyhedrons, %s materials, and %s transformation bases." % [
		len(_collision_shape_cache), len(_base_material_cache), len(_basis_cache)
	])
