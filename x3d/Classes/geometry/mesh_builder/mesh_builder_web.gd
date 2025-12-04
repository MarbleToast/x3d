class_name MeshBuilderWeb
extends MeshBuilderBase

const SWEEP_CHUNK_VERTEX_LIMIT: int = 64000 # Max vertices per chunk of sweep mesh

var web_loader: DataLoaderWeb

var true_curve_length: float = 0.0
var survey_count: int = 0
var column_map: Dictionary = {}

var _last_survey_index := 0
var is_initialising := false
var survey_data_initialised: bool = false


func _init_survey_streaming_data() -> void:
	is_initialising = true
	
	survey_count = web_loader.get_survey_count()
	var header := web_loader.get_survey_line_raw(0)
	column_map = DataLoader.parse_survey_header(header)
	
	var last_slice := web_loader.get_survey_line(survey_count - 1, column_map)
	true_curve_length = last_slice.s + last_slice.length
	
	is_initialising = false
	survey_data_initialised = true


func get_transform_at_s(global_s: float) -> Transform3D:
	if not survey_data_initialised and not is_initialising:
		_init_survey_streaming_data()
	
	if survey_count == 0:
		return Transform3D.IDENTITY
	
	var s := fposmod(global_s, true_curve_length)
	
	var i := _last_survey_index

	while i < survey_count - 1:
		var next_slice := web_loader.get_survey_line(i + 1, column_map)
		if "s" not in next_slice:
			i += 1
			push_warning("`s` couldn't be found in %s." % next_slice)
			continue
		if s < next_slice.s:
			break
		i += 1
		
	while i > 0:
		var curr_slice := web_loader.get_survey_line(i, column_map)
		if not curr_slice:
			i -= 1
			continue
		if s >= curr_slice.s:
			break
		i -= 1

	if i == 0:
		var first_slice := web_loader.get_survey_line(0, column_map)
		if first_slice and s < first_slice.s:
			i = survey_count - 1

	_last_survey_index = i
	
	var slice := web_loader.get_survey_line(i, column_map)
	if not ("s" in slice and "length" in slice and "psi" in slice and "theta" in slice and "phi" in slice and "position" in slice):
		print("Invalid survey slice at index %d; returning identity transform." % i)
		return Transform3D.IDENTITY
	
	var local_s: float = s - slice.s
	if local_s < 0.0:
		local_s += true_curve_length
	
	var frac := clampf(local_s / slice.length, 0.0, 1.0)
	
	var start_basis := get_cached_basis(slice.psi, slice.theta, slice.phi)
	var start_pos: Vector3 = slice.position
	
	var next_i := (i + 1) % survey_count
	var next_slice_mod := web_loader.get_survey_line(next_i, column_map)
	if not ("psi" in next_slice_mod and "theta" in next_slice_mod and "phi" in next_slice_mod and "position" in next_slice_mod):
		print("Invalid next survey slice at index %d; returning start transform." % next_i)
		return Transform3D(start_basis, start_pos)
	
	var end_basis := get_cached_basis(next_slice_mod.psi, next_slice_mod.theta, next_slice_mod.phi)
	var end_pos: Vector3 = next_slice_mod.position
	
	var start_trans := Transform3D(start_basis, start_pos)
	var end_trans := Transform3D(end_basis, end_pos)
	
	return start_trans.interpolate_with(end_trans, frac)


## Builds box meshes using streamed survey data from web loader
func build_box_meshes(
	aperture_material: Material,
	progress_callback: Callable = Callable(),
	static_body_callback: Callable = Callable(),
	thickness_modifier: float = 1.0
) -> void:
	print("Building box meshes (streaming)...")
	if not survey_data_initialised and not is_initialising:
		_init_survey_streaming_data()
	
	for i in range(survey_count):
		var slice := web_loader.get_survey_line(i, column_map)
		if slice.is_empty():
			continue
			
		if slice.element_type in ["LimitEllipse", "LimitRectEllipse"]:
			continue
		
		var start_rotation := get_cached_basis(slice.psi, slice.theta, slice.phi)
		var end_rotation := start_rotation
		
		if i + 1 < survey_count:
			var next_slice := web_loader.get_survey_line(i + 1, column_map)
			if not next_slice.is_empty():
				end_rotation = get_cached_basis(next_slice.psi, next_slice.theta, next_slice.phi)
		
		var box_position := _calculate_element_position(slice, start_rotation, end_rotation)
		var box := create_element_mesh(slice.element_type, slice.length, start_rotation, end_rotation, thickness_modifier)
		
		var colour := ElementColors.get_element_color(slice.element_type)
		var mat := get_base_material(aperture_material, colour).duplicate()
		
		var mesh_instance := ElementMeshInstance.new()
		mesh_instance.mesh = box
		mesh_instance.material_override = mat
		mesh_instance.name = "box"
		mesh_instance.type = slice.element_type
		mesh_instance.first_slice_name = slice.name
		mesh_instance.other_info = slice
		mesh_instance.set_layer_mask_value(2, true)
		
		var static_body := StaticBody3D.new()
		static_body.name = "Box_%d_%s" % [i, slice.element_type]
		static_body.transform = Transform3D(start_rotation, box_position)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = get_collision_shape_for_element(
			slice.element_type, slice.length, thickness_modifier, 
			start_rotation, end_rotation, box
		)
		if collision_shape.shape is CylinderShape3D:
			collision_shape.rotation.x = PI / 2.0
		
		static_body.add_child(mesh_instance)
		static_body.add_child(collision_shape)
		
		if slice.element_type == "Multipole":
			_add_multipole_kick(
				box_position, slice, start_rotation, end_rotation,
				aperture_material, thickness_modifier, static_body_callback
			)
		
		if static_body_callback.is_valid():
			static_body_callback.call(static_body)
		
		if progress_callback.is_valid():
			progress_callback.call(i)
	
	print("Box mesh generation complete (streaming).")
	print("Created %s shapes, %s materials, %s bases, %s meshes." % [
		len(_collision_shape_cache), len(_base_material_cache), len(_basis_cache), len(_mesh_cache)
	])


## Builds sweep mesh using streamed data in chunks (for OOM purposes)
func build_sweep_mesh(
	mesh_type: String,
	get_line_func: Callable,
	line_count: int,
	get_points_func: Callable,
	progress_callback: Callable = Callable(),
	chunk_callback: Callable = Callable()
) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var has_prev := false
	var prev_verts: Array[Vector3] = []
	var vertex_count := 0
	var chunk_transform := Transform3D.IDENTITY
	var is_first_in_chunk := true
	
	for i in range(line_count):
		var data_line: PackedStringArray = get_line_func.call(i)
		
		var points_2d: Dictionary = get_points_func.call(data_line)
		if points_2d.is_empty():
			continue
		
		var curr_trans := get_transform_at_s(points_2d.s)
		
		if is_first_in_chunk:
			chunk_transform = curr_trans
			is_first_in_chunk = false
		
		var curr_verts: Array[Vector3] = []
		for p in points_2d.points:
			curr_verts.append(curr_trans.origin + curr_trans.basis.x * p.x + curr_trans.basis.y * p.y)
		
		if has_prev:
			var fan := _stitch_rings(prev_verts, curr_verts, chunk_transform.affine_inverse())
			for v in fan:
				st.add_vertex(v)
			vertex_count += fan.size()
			
			# Commit mesh chunk if approaching vertex limit
			if vertex_count > SWEEP_CHUNK_VERTEX_LIMIT - 1000:
				_finalize_mesh_chunk(st, chunk_transform, chunk_callback)
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				vertex_count = 0
				is_first_in_chunk = true
		
		prev_verts = curr_verts
		has_prev = true
		
		if progress_callback.is_valid():
			progress_callback.call(i)
	
	
	if vertex_count > 0:
		_finalize_mesh_chunk(st, chunk_transform, chunk_callback)
	
	match mesh_type:
		"apertures":
			web_loader.clear_apertures()
		"twiss":
			web_loader.clear_twiss()


func build_beam_mesh(
	get_points_func: Callable,  # (line: PackedStringArray) -> Array[Vector2]
	progress_callback: Callable = Callable(),
	chunk_callback: Callable = Callable()
) -> void:
	build_sweep_mesh(
		"twiss",
		web_loader.get_twiss_line,
		web_loader.get_twiss_count(),
		get_points_func,
		progress_callback,
		chunk_callback
	)
	
	
func build_aperture_mesh(
	get_points_func: Callable,
	progress_callback: Callable = Callable(),
	chunk_callback: Callable = Callable()
) -> void:
	build_sweep_mesh(
		"apertures",
		web_loader.get_apertures_line,
		web_loader.get_apertures_count(),
		get_points_func,
		progress_callback,
		chunk_callback
	)
