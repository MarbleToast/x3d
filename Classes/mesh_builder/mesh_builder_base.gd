## This bad boy handles all the mesh generation for visualisation purposes
@abstract class_name MeshBuilderBase
extends RefCounted

# ====================== Constants
const BEAM_ELLIPSE_RESOLUTION := 20
const TORUS_SCALE_FACTOR := 1.0
const COLLIDER_CURVATURE_THRESHOLD := 0.1

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


# ===================== Caches
var _base_material_cache := {}
var _collision_shape_cache := {}
var _basis_cache := {}
var _ring_cache := {}


# ===================== Cache Accessors
func get_base_material(base_material: Material, colour: Color) -> Material:
	var key := colour.to_html()
	if not _base_material_cache.has(key):
		var mat := base_material.duplicate()
		mat.albedo_color = colour
		_base_material_cache[key] = mat
	return _base_material_cache[key]


func get_cached_basis(psi: float, theta: float, phi: float) -> Basis:
	var key := "%.2f_%.2f_%.2f" % [psi, theta, phi]
	if not _basis_cache.has(key):
		_basis_cache[key] = Basis.from_euler(Vector3(psi, theta, phi), EULER_ORDER_XYZ)
	return _basis_cache[key]


## TODO: actually have this cache properly - hashing the whole line means no hits
func get_points_2d_cached(
	data_line: PackedStringArray,
	get_points_func: Callable
) -> Array[Vector2]:
	var line_hash := hash(data_line)
	if not _ring_cache.has(line_hash):
		_ring_cache[line_hash] = get_points_func.call(data_line)
	return _ring_cache[line_hash]


# ===================== Mesh Geometry Utilities
func create_beam_ellipse(twiss_line: PackedStringArray, thickness_modifier: float = 1.0) -> Array[Vector2]:
	var twiss := DataLoader.parse_twiss_line(twiss_line)
	if not twiss:
		return []

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


func calculate_curvature(
	start_rotation: Basis,
	end_rotation: Basis,
	length: float
) -> float:
	var start_tangent := start_rotation.z
	var end_tangent := end_rotation.z
	var bend_angle := start_tangent.angle_to(end_tangent)
	var arc_length := length * TORUS_SCALE_FACTOR
	return min(bend_angle / max(arc_length, 0.1), 1.0)


# ===================== Cache Management
func clear_caches() -> void:
	_base_material_cache.clear()
	_collision_shape_cache.clear()
	_basis_cache.clear()
	_ring_cache.clear()
	print("MeshBuilder caches cleared")


func get_cache_stats() -> Dictionary:
	return {
		"materials": _base_material_cache.size(),
		"collision_shapes": _collision_shape_cache.size(),
		"bases": _basis_cache.size(),
		"rings": _ring_cache.size(),
	}


# ===================== Mesh Creation Methods
func create_bent_mesh(
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
		_build_straight_mesh(st, cross_sections_2d, length, start_rotation, add_caps)
	else:
		_build_curved_mesh(st, cross_sections_2d, length, start_rotation, end_rotation, segments, add_caps)
	
	st.index()
	st.generate_normals()
	return st.commit()


func _build_straight_mesh(
	st: SurfaceTool,
	cross_sections_2d: Array[Array],
	length: float,
	start_rotation: Basis,
	add_caps: bool
) -> void:
	var half_len := length * TORUS_SCALE_FACTOR * 0.5
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
			_add_caps(st, front_ring, back_ring)


func _build_curved_mesh(
	st: SurfaceTool,
	cross_sections_2d: Array[Array],
	length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	segments: int,
	add_caps: bool
) -> void:
	var start_tangent := start_rotation.z
	var end_tangent := end_rotation.z
	var rotation_axis := start_tangent.cross(end_tangent).normalized()
	var bend_angle := start_tangent.angle_to(end_tangent)
	var arc_length := length * TORUS_SCALE_FACTOR
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
				_add_caps(st, first_ring, last_ring)


func _add_caps(st: SurfaceTool, front_ring: Array[Vector3], back_ring: Array[Vector3]) -> void:
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


func create_element_mesh(
	type: String,
	length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	thickness_modifier: float = 1.0,
	add_caps: bool = true,
) -> Mesh:
	var cross_section_func := _get_cross_section_func(type, thickness_modifier)
	return create_bent_mesh(cross_section_func, length, start_rotation, end_rotation, 8, add_caps)


func _get_cross_section_func(type: String, thickness_modifier: float) -> Callable:
	var dimensions: Dictionary = ELEMENT_DIMENSIONS.get(type, ELEMENT_DIMENSIONS._default)
	
	match dimensions.type:
		"box":
			return _box_cross_section.bindv([dimensions.width, dimensions.height, thickness_modifier])
		"circle":
			return _circle_cross_section.bindv([dimensions.radius, thickness_modifier])
		"equals":
			return _equals_cross_section.bindv([thickness_modifier])
		"multipole":
			return _multipole_cross_section.bindv([
				dimensions.num_poles, dimensions.pole_width,
				dimensions.pole_height, dimensions.pole_radius, thickness_modifier
			])
	return _box_cross_section.bindv([0.3, 0.3, thickness_modifier])


func _box_cross_section(width: float, height: float, thickness_modifier: float, offset: Vector2 = Vector2.ZERO) -> Array[Array]:
	var w := width * thickness_modifier
	var h := height * thickness_modifier
	return [[
		Vector2(-w, -h) + offset,
		Vector2(w, -h) + offset,
		Vector2(w, h) + offset,
		Vector2(-w, h) + offset
	]]


func _equals_cross_section(thickness_modifier: float) -> Array[Array]:
	var w := 0.3 * thickness_modifier
	var h := 0.1 * thickness_modifier
	var gap := 0.4 * thickness_modifier
	return [
		_box_cross_section(w, h, 1.0, Vector2(0, gap / 2))[0],
		_box_cross_section(w, h, 1.0, Vector2(0, -gap / 2))[0]
	]


func _circle_cross_section(radius: float, thickness_modifier: float, sides: int = 20) -> Array[Array]:
	var pts: Array[Vector2] = []
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		pts.append(Vector2(cos(a), sin(a)) * radius * thickness_modifier)
	return [pts]


func _multipole_cross_section(num_poles: int, width: float, height: float, radius: float, thickness_modifier: float) -> Array[Array]:
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


func get_collision_shape_for_element(
	type: String,
	length: float,
	thickness_modifier: float,
	start_rotation: Basis,
	end_rotation: Basis,
	mesh: Mesh
) -> Shape3D:
	var key := "%s_%.3f_%f" % [type, length, thickness_modifier]
	
	if _collision_shape_cache.has(key):
		return _collision_shape_cache[key]
	
	var shape: Shape3D
	var curvature := calculate_curvature(start_rotation, end_rotation, length)
	
	if curvature > COLLIDER_CURVATURE_THRESHOLD:
		shape = mesh.create_convex_shape()
	else:
		shape = create_simple_collider(type, length, thickness_modifier)
	
	_collision_shape_cache[key] = shape
	return shape


func create_simple_collider(type: String, length: float, thickness_modifier: float) -> Shape3D:
	var collision_length := length * TORUS_SCALE_FACTOR
	var dims: Dictionary = ELEMENT_DIMENSIONS.get(type, ELEMENT_DIMENSIONS._default)
	
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
	
	return BoxShape3D.new()


func _calculate_element_position(slice: Dictionary, start_rotation: Basis, end_rotation: Basis) -> Vector3:
	var start_tangent := start_rotation.z
	var end_tangent := end_rotation.z
	var rotation_axis := start_tangent.cross(end_tangent)
	var bend_angle := start_tangent.angle_to(end_tangent)
	var arc_length: float = slice.length * TORUS_SCALE_FACTOR
	
	if bend_angle < 1e-6 or rotation_axis.length_squared() < 1e-12:
		return slice.position + start_tangent * (arc_length * 0.5)
	else:
		rotation_axis = rotation_axis.normalized()
		var radius := arc_length / bend_angle
		var to_center := start_tangent.cross(rotation_axis).normalized() * radius
		var mid_angle := bend_angle / 2.0
		var mid_to_center := to_center.rotated(rotation_axis, mid_angle)
		return slice.position + (mid_to_center - to_center)


func _stitch_rings(prev_verts: Array[Vector3], curr_verts: Array[Vector3]) -> PackedVector3Array:
	var num_verts := curr_verts.size()
	var verts := PackedVector3Array()
	verts.resize(num_verts * 6)
	var k := 0
	for j in num_verts:
		var jn := (j + 1) % num_verts
		verts[k] = prev_verts[j]
		verts[k+1] = prev_verts[jn]
		verts[k+2] = curr_verts[j]
		verts[k+3] = prev_verts[jn]
		verts[k+4] = curr_verts[jn]
		verts[k+5] = curr_verts[j]
		k += 6
	return verts


func _add_multipole_kick(
	parent_pos: Vector3,
	slice: Dictionary,
	start_rotation: Basis,
	end_rotation: Basis,
	aperture_material: Material,
	thickness_modifier: float,
	static_body_callback: Callable
) -> void:
	var kick_mesh := create_element_mesh("MultipoleKick", 0.0, start_rotation, end_rotation, thickness_modifier, true)
	var kick_color := ElementColors.get_element_color("MultipoleKick")
	var kick_mat := get_base_material(aperture_material, kick_color).duplicate()
	kick_mesh.surface_set_material(0, kick_mat)
	
	var kick_collision := CollisionShape3D.new()
	kick_collision.shape = get_collision_shape_for_element("MultipoleKick", 0.02, thickness_modifier, start_rotation, end_rotation, kick_mesh)
	kick_collision.transform = Transform3D(start_rotation)
	kick_collision.rotation.x = PI / 2.0
	
	var kick_instance := ElementMeshInstance.new()
	kick_instance.mesh = kick_mesh
	kick_instance.name = "box"
	kick_instance.type = "MultipoleKick"
	kick_instance.first_slice_name = slice.name + " (Kick)"
	kick_instance.other_info = slice
	
	var kick_body := StaticBody3D.new()
	kick_body.name = "Multipole_%s_kick" % slice.name
	kick_body.transform = Transform3D(Basis.IDENTITY, parent_pos + start_rotation * Vector3(0, 0, -slice.length/2))
	
	kick_body.add_child(kick_instance)
	kick_body.add_child(kick_collision)
	
	if static_body_callback.is_valid():
		static_body_callback.call(kick_body)


@abstract func build_box_meshes(
	aperture_material: Material,
	progress_callback: Callable = Callable(),
	static_body_callback: Callable = Callable(),
	thickness_modifier: float = 1.0
) -> void

@abstract func build_beam_mesh(
	get_points_func: Callable,  # (line: PackedStringArray) -> Array[Vector2]
	progress_callback: Callable = Callable()
) -> ArrayMesh

@abstract func build_aperture_mesh(
	get_points_func: Callable,  # (line: PackedStringArray) -> Array[Vector2]
	progress_callback: Callable = Callable()
) -> ArrayMesh
