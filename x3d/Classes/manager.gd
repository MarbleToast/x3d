extends Node3D

const APERTURE_THICKNESS_MODIFIER := 1.0
const BEAM_THICKNESS_MODIFIER := 1.0

@export var main_camera: Camera3D
@export var beam_animator: BeamAnimationController

@export var aperture_material: Material
@export var beam_material: Material

# Progress bars
@export var aperture_progress_container: Container
@export var beam_progress_container: Container
@export var element_progress_container: Container
@export var aperture_progress: TextureProgressBar
@export var beam_progress: TextureProgressBar
@export var element_progress: TextureProgressBar

# Aperture info panel, right side
@export var aperture_info_container: Container
@export var aperture_info: RichTextLabel

# UI buttons
@export var view_menu: PopupMenu

# Web-specific UI
@export var load_survey_button: Button
@export var load_apertures_button: Button
@export var load_twiss_button: Button
@export var start_build_button: Button
@export var status_label: RichTextLabel

@onready var scale_debounce_timer := $Timer

signal aperture_mesh_complete(mesh: ArrayMesh)
signal beam_mesh_complete(mesh: ArrayMesh)
signal element_meshes_complete

var mesh_export_thread: Thread
var aperture_thread: Thread
var beam_thread: Thread
var magnets_thread: Thread

var beam_mesh_instances: Array[MeshInstance3D] = []
var aperture_mesh_instances: Array[MeshInstance3D] = []
var length_mesh_instances: Array[StaticBody3D] = []

# File paths (native)
var survey_path: String
var apertures_path: String
var twiss_path: String

# Builder abstraction
var mesh_builder: MeshBuilderBase

var pending_scale: float

var selected_element_mesh: ElementMeshInstance:
	set(value):
		if selected_element_mesh:
			var old_mat := selected_element_mesh.get_active_material(0) as StandardMaterial3D
			old_mat.albedo_color = old_mat.albedo_color / 10.0
		var new_mat := value.get_active_material(0) as StandardMaterial3D
		new_mat.albedo_color = new_mat.albedo_color * 10.0
		
		aperture_info_container.visible = true
		
		aperture_info.text = "[font_size=26]%s[/font_size]\n[color=#fbb]%s[/color]\n[font_size=18]%s[/font_size][color=dodgerblue][url=https://xsuite.readthedocs.io/en/latest/apireference.html#%s]Go to Docs[/url][/color]" % [
			value.first_slice_name, 
			value.type, 
			value.pretty_print_info(),
			value.type.to_lower() if "Slice" not in value.type else value.type.trim_suffix("Slice").to_lower()
		]
		selected_element_mesh = value


func _ready() -> void:
	for i in view_menu.item_count - 1:
		view_menu.set_item_checked(i, true)
	
	view_menu.index_pressed.connect(
		func (val):
			view_menu.set_item_checked(val, not view_menu.is_item_checked(val))
			match val:
				0: # Elements
					for m in length_mesh_instances:
						m.visible = not m.visible
						m.process_mode = Node.PROCESS_MODE_INHERIT if m.visible else Node.PROCESS_MODE_DISABLED
				1: # Aperture
					for m in aperture_mesh_instances:
						m.visible = not m.visible
				2: # Twiss
					for m in beam_mesh_instances:
						m.visible = not m.visible
	)

	_connect_signals()
	_setup_export_callbacks()


func setup() -> void:
	print("Mesh Manager setting up for building...")
	
	main_camera.reset_position()
	
	length_mesh_instances = []

	if OS.has_feature("web"):
		mesh_builder = MeshBuilderWeb.new()
		mesh_builder.web_loader = %FileDialog.web_loader
	else:
		mesh_builder = MeshBuilderNative.new()
		mesh_builder.survey_data = time_it(DataLoader.load_survey, survey_path)
		mesh_builder.aperture_path = apertures_path
		mesh_builder.twiss_path = twiss_path

	_setup_progress_bars()
	start_building()


func start_building() -> void:
	for c in get_children():
		if c is MeshInstance3D or c is StaticBody3D:
			c.queue_free()
	
	var cond_ap: bool
	var cond_tw: bool
	if mesh_builder is MeshBuilderWeb:
		cond_ap = mesh_builder.web_loader.get_apertures_count() > 0
		cond_tw = mesh_builder.web_loader.get_twiss_count() > 0
	else:
		cond_ap = not apertures_path.is_empty()
		cond_tw = not twiss_path.is_empty()
			
	
	if cond_ap:
		aperture_progress_container.visible = true
		_start_aperture_thread()
		
	if cond_tw:
		beam_progress_container.visible = true
		_start_beam_thread()
	
	_start_magnets_thread()


func regenerate_mesh(
	element: ElementMeshInstance,
	type: String,
	length: float,
	pos: Vector3, 
	start_psi: float, start_theta: float, start_phi: float,	
):
	var start_rotation := mesh_builder.get_cached_basis(start_psi, start_theta, start_phi)
	var end_rotation := mesh_builder.get_cached_basis(element.other_info.end_psi, element.other_info.end_theta, element.other_info.end_phi)
	element.mesh = mesh_builder.create_element_mesh(
		element.type,
		length,
		start_rotation,
		end_rotation
	)
	element.get_parent().transform = Transform3D(
		start_rotation,
		mesh_builder._calculate_element_position({
			length = length,
			position = pos
		}, start_rotation, end_rotation)
	)


func _setup_progress_bars() -> void:
	element_progress_container.visible = true

	if mesh_builder is MeshBuilderWeb:
		var loader := (mesh_builder as MeshBuilderWeb).web_loader
		aperture_progress.max_value = loader.get_apertures_count()
		beam_progress.max_value = loader.get_twiss_count()
		element_progress.max_value = loader.get_survey_count()
	else:
		var survey := (mesh_builder as MeshBuilderNative).survey_data
		aperture_progress.max_value = survey.size()
		beam_progress.max_value = survey.size()
		element_progress.max_value = survey.size()


func _connect_signals() -> void:
	aperture_mesh_complete.connect(_on_aperture_mesh_complete)
	beam_mesh_complete.connect(_on_beam_mesh_complete)
	element_meshes_complete.connect(_on_element_meshes_complete)


# ==================== Unified threading ====================

func _start_aperture_thread() -> void:
	aperture_thread = Thread.new()
	aperture_thread.start(func():
		mesh_builder.build_aperture_mesh(
			func(line): return DataLoader.parse_edge_line(line, APERTURE_THICKNESS_MODIFIER),
			func(p): aperture_progress.set_value.call_deferred(p),
			_add_aperture_mesh_chunk
		)
		aperture_mesh_complete.emit.call_deferred()
	)


func _start_beam_thread() -> void:
	beam_thread = Thread.new()
	beam_thread.start(func():
		mesh_builder.build_beam_mesh(
			func(line): return mesh_builder.create_beam_ellipse(line, BEAM_THICKNESS_MODIFIER),
			func(p): beam_progress.set_value.call_deferred(p),
			_add_twiss_mesh_chunk
		)
		beam_mesh_complete.emit.call_deferred()
	)


func _start_magnets_thread() -> void:
	magnets_thread = Thread.new()
	magnets_thread.start(func():
		mesh_builder.build_box_meshes(
			aperture_material,
			func(p): element_progress.set_value.call_deferred(p),
			func(body): _add_box_static_body.call_deferred(body),
			APERTURE_THICKNESS_MODIFIER
		)
		element_meshes_complete.emit.call_deferred()
	)

# ==================== Mesh completion handlers ====================

func _add_box_static_body(static_body: StaticBody3D) -> void:
	length_mesh_instances.append(static_body)
	static_body.input_event.connect(_on_aperture_mesh_clicked.bind(static_body.get_node("box")))
	add_child(static_body)


func _add_aperture_mesh_chunk(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.mesh.surface_set_material(0, aperture_material)
	mesh_instance.name = "ApertureChunk%s" % len(aperture_mesh_instances)
	aperture_mesh_instances.append(mesh_instance)
	add_child.call_deferred(mesh_instance)


func _add_twiss_mesh_chunk(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.mesh.surface_set_material(0, beam_material)
	mesh_instance.name = "TwissChunk"
	beam_mesh_instances.append(mesh_instance)
	add_child.call_deferred(mesh_instance)


func _on_aperture_mesh_complete() -> void:
	aperture_progress.value = aperture_progress.max_value
	aperture_thread.wait_to_finish()
	_progress_success_animation(aperture_progress_container)


func _on_beam_mesh_complete() -> void:
	beam_progress.value = beam_progress.max_value
	beam_thread.wait_to_finish()
	_progress_success_animation(beam_progress_container)
	
	#beam_animator.beam_mesh_instance = beam_mesh_instance
	#beam_animator.start_animation()


func _on_element_meshes_complete() -> void:
	magnets_thread.wait_to_finish()
	_progress_success_animation(element_progress_container)


# ==================== Misc ====================

func time_it(fn: Callable, ...varargs: Array) -> Variant:
	var t := Time.get_ticks_msec()
	var res = fn.callv(varargs)
	print("%s returned in %s ms." % [fn.get_method(), Time.get_ticks_msec() - t])
	return res


func _setup_export_callbacks() -> void:
	OBJExporter.export_progress_updated.connect(func(sid, prog):
		print("Exporting surface %s, %.02f%% complete." % [sid, prog * 100])
	)
	OBJExporter.export_completed.connect(func(_obj, _mtl):
		print("Export complete!")
	)


func _on_aperture_mesh_clicked(_cam, event, _pos, _norm, _shape, caller: ElementMeshInstance) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected_element_mesh = caller


func _progress_success_animation(container: Container) -> void:
	container.modulate = Color.LIME_GREEN
	await get_tree().create_tween().tween_property(container, "modulate", Color.TRANSPARENT, 2.0).finished
	container.visible = false
	container.modulate = Color.WHITE


#func _input(event: InputEvent) -> void:
	#if event is InputEventKey and event.keycode == KEY_M and event.pressed and not event.echo:
		#_export_mesh()


#func _export_mesh() -> void:
	#if not mesh_export_thread:
		#mesh_export_thread = Thread.new()
	#if mesh_export_thread.is_started():
		#return
	#mesh_export_thread.start(func():
		#if beam_mesh_instance:
			#OBJExporter.save_mesh_to_files(beam_mesh_instance.mesh, "user://", "mesh_export_beam")
		#if aperture_mesh_instance:
			#OBJExporter.save_mesh_to_files(aperture_mesh_instance.mesh, "user://", "mesh_export_aperture")
	#)


func _exit_tree() -> void:
	for thread in [aperture_thread, beam_thread, magnets_thread, mesh_export_thread]:
		if thread and thread.is_started():
			thread.wait_to_finish()
	if mesh_builder is MeshBuilderWeb:
		(mesh_builder as MeshBuilderWeb).web_loader.clear_all()


func _on_h_slider_value_changed(value: float) -> void:
	pending_scale = value
	scale_debounce_timer.start()


func _on_timer_timeout() -> void:
	scale = Vector3.ONE * pending_scale


func _on_aperture_info_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))
