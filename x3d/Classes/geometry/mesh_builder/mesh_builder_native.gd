class_name MeshBuilderNative
extends MeshBuilderBase

var survey_data: Array[Dictionary]:
	set(value):
		if not value.is_empty():
			survey_data = value
			true_curve_length = value[-1].s + value[-1].length

var aperture_path: String
var twiss_path: String

var true_curve_length: float
var _last_survey_index := 0


func get_transform_at_s(global_s: float) -> Transform3D:
	if survey_data.is_empty():
		return Transform3D.IDENTITY
	
	var s := fposmod(global_s, true_curve_length)
	
	var i := _last_survey_index
	while i < survey_data.size() - 1 and s >= survey_data[i + 1].s:
		i += 1
	
	while i > 0 and s < survey_data[i].s:
		i -= 1
	
	_last_survey_index = i
	
	var slice := survey_data[i]
	var local_s: float = s - slice.s
	if local_s < 0:
		local_s += true_curve_length
	
	var frac: float = clampf(local_s / slice.length, 0.0, 1.0)
	
	var start_basis := get_cached_basis(slice.psi, slice.theta, slice.phi)
	var start_pos: Vector3 = slice.position
	
	var next_i := (i + 1) % survey_data.size()
	var next_slice := survey_data[next_i]
	var end_basis := get_cached_basis(next_slice.psi, next_slice.theta, next_slice.phi)
	var end_pos: Vector3 = next_slice.position
	
	var start_trans := Transform3D(start_basis, start_pos)
	var end_trans := Transform3D(end_basis, end_pos)
	
	return start_trans.interpolate_with(end_trans, frac)


func build_box_meshes(
	aperture_material: Material,
	progress_callback: Callable = Callable(),
	static_body_callback: Callable = Callable(),
	thickness_modifier: float = 1.0
) -> void:
	print("Building box meshes...")

	for i in range(survey_data.size()):
		var slice := survey_data[i]
		if slice.element_type in Settings.ELEMENT_BLACKLIST:
			continue

		var start_rotation := get_cached_basis(slice.psi, slice.theta, slice.phi)
		var end_rotation := start_rotation
		
		if i + 1 < len(survey_data):
			var next_slice := survey_data[i + 1]
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
		
		var static_body := StaticBody3D.new()
		static_body.name = "Box_%d_%s" % [i, slice.element_type]
		static_body.transform = Transform3D(start_rotation, box_position)
		
		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = get_collision_shape_for_element(slice.element_type, slice.length, thickness_modifier, start_rotation, end_rotation, box)
		if collision_shape.shape is CylinderShape3D:
			collision_shape.rotation.x = PI / 2.0
		
		static_body.add_child(mesh_instance)
		static_body.add_child(collision_shape)
		
		if slice.element_type == "Multipole":
			_add_multipole_kick(box_position, slice, start_rotation, end_rotation, aperture_material, thickness_modifier, static_body_callback)
		
		if static_body_callback.is_valid():
			static_body_callback.call(static_body)
		
		if progress_callback.is_valid():
			progress_callback.call(i)
	
	print("Box mesh generation complete.")
	print("Created %s shapes, %s materials, %s bases, %s meshes." % [
		len(_collision_shape_cache), len(_base_material_cache), len(_basis_cache), len(_mesh_cache)
	])


func build_sweep_mesh(
	path: String,
	get_points_func: Callable,
	progress_callback: Callable = Callable(),
	chunk_callback: Callable = Callable()
) -> void:
	var line_data := DataLoader.load_csv(path)
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var has_prev := false
	var prev_verts: Array[Vector3] = []
	var vertex_count := 0
	var chunk_transform := Transform3D.IDENTITY
	var is_first_in_chunk := true
	
	for aperture_index in range(len(line_data)):
		var data_line := line_data[aperture_index]
		
		var points_2d: Dictionary = get_points_func.call(data_line) # {points: Array[Vector2], s: float}
		if points_2d.is_empty():
			continue
		
		var curr_trans: Transform3D = get_transform_at_s(points_2d.s)
		
		if is_first_in_chunk:
			chunk_transform = curr_trans
			is_first_in_chunk = false
		
		var curr_verts: Array[Vector3] = []
		for p: Vector2 in points_2d.points:
			var world_pos := curr_trans.origin + curr_trans.basis.x * p.x + curr_trans.basis.y * p.y
			curr_verts.append(world_pos)
		
		if has_prev:
			var fan := _stitch_rings(prev_verts, curr_verts, chunk_transform.affine_inverse())
			for v in fan:
				st.add_vertex(v)
			vertex_count += fan.size()
			
			if vertex_count > Settings.SWEEP_CHUNK_VERTEX_LIMIT - 1000:
				_finalize_mesh_chunk(st, chunk_transform, chunk_callback)
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				vertex_count = 0
				is_first_in_chunk = true
		
		prev_verts = curr_verts
		has_prev = true
		
		if progress_callback.is_valid():
			progress_callback.call(aperture_index)

	if vertex_count > 0:
		_finalize_mesh_chunk(st, chunk_transform, chunk_callback)


func build_beam_mesh(
	get_points_func: Callable,  # (line: PackedStringArray) -> Array[Vector2]
	progress_callback: Callable = Callable(),
	chunk_callback: Callable = Callable()
) -> void:
	build_sweep_mesh(
		twiss_path,
		get_points_func,
		progress_callback,
		chunk_callback
	)


func build_aperture_mesh(
	get_points_func: Callable,  # (line: PackedStringArray) -> Array[Vector2]
	progress_callback: Callable = Callable(),
	chunk_callback: Callable = Callable()
) -> void:
	build_sweep_mesh(
		aperture_path,
		get_points_func,
		progress_callback,
		chunk_callback
	)
