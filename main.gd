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
@export var aperture_info: RichTextLabel

# UI buttons
@export var toggle_elements: Button
@export var toggle_beam: Button
@export var toggle_apertures: Button

# Web-specific UI
@export var load_survey_button: Button
@export var load_apertures_button: Button
@export var load_twiss_button: Button
@export var start_build_button: Button
@export var status_label: RichTextLabel

signal aperture_mesh_complete(mesh: ArrayMesh)
signal beam_mesh_complete(mesh: ArrayMesh)
signal element_meshes_complete

var mesh_export_thread: Thread
var aperture_thread: Thread
var beam_thread: Thread
var magnets_thread: Thread

var beam_mesh_instance: MeshInstance3D
var aperture_mesh_instance: MeshInstance3D
var length_mesh_instances: Array[StaticBody3D] = []

# File paths (native)
var survey_path: String
var apertures_path: String
var twiss_path: String

# Builder abstraction
var mesh_builder: MeshBuilderBase

var selected_aperture_mesh: ElementMeshInstance:
	set(value):
		if selected_aperture_mesh:
			var old_mat := selected_aperture_mesh.get_active_material(0) as StandardMaterial3D
			old_mat.albedo_color = old_mat.albedo_color / 10.0
		var new_mat := value.get_active_material(0) as StandardMaterial3D
		new_mat.albedo_color = new_mat.albedo_color * 10.0
		aperture_info.text = "[font_size=26]%s[/font_size][color=#fbb]\n%s\n[font_size=18]%s[/font_size][/color]" % [value.first_slice_name, value.type, value.other_info]
		selected_aperture_mesh = value


func _ready() -> void:
	toggle_elements.set_pressed_no_signal(true)
	toggle_elements.toggled.connect(func(val):
		for m in length_mesh_instances:
			m.visible = val
			m.process_mode = Node.PROCESS_MODE_INHERIT if val else Node.PROCESS_MODE_DISABLED
	)
	
	toggle_beam.set_pressed_no_signal(true)
	toggle_beam.toggled.connect(func(val):
		if beam_mesh_instance: beam_mesh_instance.visible = val
	)
	
	toggle_apertures.set_pressed_no_signal(true)
	toggle_apertures.toggled.connect(func(val):
		if aperture_mesh_instance: aperture_mesh_instance.visible = val
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
		mesh_builder.survey_data = DataLoader.load_survey(survey_path)
		mesh_builder.aperture_path = apertures_path
		mesh_builder.twiss_path = twiss_path

	_setup_progress_bars()
	start_building()


func start_building() -> void:
	for c in get_children():
		if c is MeshInstance3D or c is StaticBody3D:
			c.queue_free()

	aperture_progress_container.visible = true
	_start_aperture_thread()
		
	beam_progress_container.visible = true
	_start_beam_thread()
	
	_start_magnets_thread()


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
		var mesh := mesh_builder.build_aperture_mesh(
			func(line): return DataLoader.parse_edge_line(line, APERTURE_THICKNESS_MODIFIER),
			func(p): aperture_progress.set_value.call_deferred(p)
		)
		aperture_mesh_complete.emit.call_deferred(mesh)
	)


func _start_beam_thread() -> void:
	beam_thread = Thread.new()
	beam_thread.start(func():
		var mesh := mesh_builder.build_beam_mesh(
			func(line): return mesh_builder.create_beam_ellipse(line, BEAM_THICKNESS_MODIFIER),
			func(p): beam_progress.set_value.call_deferred(p)
		)
		beam_mesh_complete.emit.call_deferred(mesh)
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

func _on_aperture_mesh_complete(mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() > 0:
		print("Aperture mesh generated.")
		aperture_mesh_instance = MeshInstance3D.new()
		aperture_mesh_instance.name = "ApertureModel"
		mesh.surface_set_material(0, aperture_material)
		aperture_mesh_instance.mesh = mesh
		add_child(aperture_mesh_instance)
		aperture_progress.value = aperture_progress.max_value
	aperture_thread.wait_to_finish()
	_progress_success_animation(aperture_progress_container)


func _on_beam_mesh_complete(mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() > 0:
		print("Beam mesh generated.")
		beam_mesh_instance = MeshInstance3D.new()
		beam_mesh_instance.name = "Twiss"
		beam_mesh_instance.mesh = mesh
		beam_mesh_instance.set_surface_override_material(0, preload("res://Assets/beam_envelope.tres").duplicate())
		add_child(beam_mesh_instance)
		beam_progress.value = beam_progress.max_value
		
	beam_thread.wait_to_finish()
	_progress_success_animation(beam_progress_container)
	
	beam_animator.beam_mesh_instance = beam_mesh_instance
	beam_animator.start_animation()


func _on_element_meshes_complete() -> void:
	magnets_thread.wait_to_finish()
	_progress_success_animation(element_progress_container)


# ==================== Misc ====================

func _setup_export_callbacks() -> void:
	OBJExporter.export_progress_updated.connect(func(sid, prog):
		print("Exporting surface %s, %.02f%% complete." % [sid, prog * 100])
	)
	OBJExporter.export_completed.connect(func(_obj, _mtl):
		print("Export complete!")
	)


func _add_box_static_body(static_body: StaticBody3D) -> void:
	length_mesh_instances.append(static_body)
	static_body.input_event.connect(_on_aperture_mesh_clicked.bind(static_body.get_node("box")))
	add_child(static_body)


func _on_aperture_mesh_clicked(_cam, event, _pos, _norm, _shape, caller: ElementMeshInstance) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected_aperture_mesh = caller


func _progress_success_animation(container: Container) -> void:
	container.modulate = Color.LIME_GREEN
	await get_tree().create_tween().tween_property(container, "modulate", Color.TRANSPARENT, 2.0).finished
	container.visible = false
	container.modulate = Color.WHITE


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_M and event.pressed and not event.echo:
		_export_mesh()


func _export_mesh() -> void:
	if not mesh_export_thread:
		mesh_export_thread = Thread.new()
	if mesh_export_thread.is_started():
		return
	mesh_export_thread.start(func():
		if beam_mesh_instance:
			OBJExporter.save_mesh_to_files(beam_mesh_instance.mesh, "user://", "mesh_export_beam")
		if aperture_mesh_instance:
			OBJExporter.save_mesh_to_files(aperture_mesh_instance.mesh, "user://", "mesh_export_aperture")
	)


func _exit_tree() -> void:
	for thread in [aperture_thread, beam_thread, magnets_thread, mesh_export_thread]:
		if thread and thread.is_started():
			thread.wait_to_finish()
	if mesh_builder is MeshBuilderWeb:
		(mesh_builder as MeshBuilderWeb).web_loader.clear_all()
