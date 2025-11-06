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
	Quadrupole = { 
		type = "quadrupole", 
		aperture_radius = 0.05, 
		pole_width = 0.08, 
		pole_tip_width = 0.06, 
		yoke_inner_radius = 0.2, 
		yoke_outer_radius = 0.25, 
		custom = true 
	},
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


# ===================== Mesh Creation Methods
func create_element_mesh(
	type: String,
	length: float,
	start_rotation: Basis,
	end_rotation: Basis,
	thickness_modifier: float = 1.0,
	add_caps: bool = true,
) -> Mesh:
	var dimensions: Dictionary = ELEMENT_DIMENSIONS.get(type, ELEMENT_DIMENSIONS._default)
	if dimensions.has("custom"):
		return CustomMeshFactory.create_custom_mesh(type, dimensions, length, start_rotation, thickness_modifier)
		
	var cross_section_func := CrossSectionFactory.get_cross_section_func(type, thickness_modifier, dimensions)
	return MeshGeometry.extrude_cross_sections(cross_section_func, length, start_rotation, end_rotation, 8, add_caps)


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
		shape = CollisionShapeFactory.create_simple_collider(type, length, thickness_modifier)
	
	_collision_shape_cache[key] = shape
	return shape


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
