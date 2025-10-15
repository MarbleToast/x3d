extends Node3D

const APERTURE_THICKNESS_MODIFIER := 1.0
const BEAM_THICKNESS_MODIFIER := 1.0

@export var aperture_material: Material
@export var beam_material: Material

@onready var aperture_progress_container := $"../VBoxContainer/HBoxContainer"
@onready var beam_progress_container := $"../VBoxContainer/HBoxContainer2"
@onready var element_progress_container := $"../VBoxContainer/HBoxContainer3"

@onready var aperture_progress := %ApertureProgress
@onready var beam_progress := %BeamProgress
@onready var element_progress := %ElementProgress

@onready var aperture_info := %ApertureInfo

@onready var toggle_elements := $"../HBoxContainer/Button"
@onready var toggle_beam := $"../HBoxContainer/Button2"
@onready var toggle_apertures := $"../HBoxContainer/Button3"

# Signals for coordinating threads
signal aperture_mesh_complete(mesh: ArrayMesh)
signal beam_mesh_complete(arrays: ArrayMesh)
signal element_meshes_complete

# Thread management
var mesh_export_thread := Thread.new()
var aperture_thread := Thread.new()
var beam_thread := Thread.new()
var magnets_thread := Thread.new()

# Mesh storage
var beam_mesh_instance: MeshInstance3D
var aperture_mesh_instance: MeshInstance3D
var length_mesh_instances: Array[StaticBody3D] = []

# Paths for data files
var survey_path: String = "res://Data/survey.csv"
var apertures_path: String = "res://Data/apertures.csv"
var twiss_path: String = "res://Data/twiss.csv"

var selected_aperture_mesh: ElementMeshInstance:
	set(value):
		if selected_aperture_mesh:
			var old_mat := selected_aperture_mesh.mesh.surface_get_material(0) as StandardMaterial3D
			var old_color := old_mat.albedo_color
			old_color = Color(
				old_color.r / 10,
				old_color.g / 10,
				old_color.b / 10,
				old_color.a
			)
			old_mat.albedo_color = old_color

		var new_mat := value.mesh.surface_get_material(0) as StandardMaterial3D
		var new_color := new_mat.albedo_color
		new_color = Color(
			new_color.r * 10,
			new_color.g * 10,
			new_color.b * 10,
			new_color.a
		)
		new_mat.albedo_color = new_color

		aperture_info.text = "[font_size=26]%s[/font_size][color=#fbb]\n%s\n[font_size=18]%s[/font_size][/color]" % [value.first_slice_name, value.type, value.other_info]
		selected_aperture_mesh = value


func _ready() -> void:
	toggle_elements.set_pressed_no_signal(true)
	toggle_elements.toggled.connect(
		func (val): 
			for m in length_mesh_instances:
				m.visible = val
				m.process_mode = Node.PROCESS_MODE_INHERIT if val else Node.PROCESS_MODE_DISABLED
	)
	
	toggle_beam.set_pressed_no_signal(true)
	toggle_beam.toggled.connect(
		func (val): 
			beam_mesh_instance.visible = val
	)
	
	toggle_apertures.set_pressed_no_signal(true)
	toggle_apertures.toggled.connect(
		func (val): 
			aperture_mesh_instance.visible = val
	)
	
	var survey_data := DataLoader.load_survey(survey_path)
	
	_setup_progress_bars(survey_data)
	_connect_signals()
	
	_start_aperture_thread(survey_data)
	_start_beam_thread(survey_data)
	_start_magnets_thread(survey_data)
	_setup_export_callbacks()


func _setup_progress_bars(survey_data: Array[Dictionary]) -> void:
	aperture_progress.max_value = survey_data.size()
	beam_progress.max_value = survey_data.size()
	element_progress.max_value = survey_data.size()


func _connect_signals() -> void:
	aperture_mesh_complete.connect(_on_aperture_mesh_complete)
	beam_mesh_complete.connect(_on_beam_mesh_complete)
	element_meshes_complete.connect(_on_element_meshes_complete)


func _start_aperture_thread(survey_data: Array[Dictionary]) -> void:
	aperture_thread.start(func():
		var mesh := MeshBuilder.build_sweep_mesh(
			survey_data,
			apertures_path,
			func(aperture_line): return DataLoader.parse_edge_line(aperture_line, APERTURE_THICKNESS_MODIFIER),
			func(progress: int): aperture_progress.set_value.call_deferred(progress)
		)
		aperture_mesh_complete.emit.call_deferred(mesh)
	)


func _start_beam_thread(survey_data: Array[Dictionary]) -> void:
	beam_thread.start(func():
		var mesh := MeshBuilder.build_sweep_mesh(
			survey_data,
			twiss_path,
			func(twiss_line): return MeshBuilder.create_beam_ellipse(twiss_line, BEAM_THICKNESS_MODIFIER),
			func(progress: int): beam_progress.set_value.call_deferred(progress)
		)
		beam_mesh_complete.emit.call_deferred(mesh)
	)


func _start_magnets_thread(survey_data: Array[Dictionary]) -> void:
	magnets_thread.start(func():
		MeshBuilder.build_box_meshes(
			survey_data,
			aperture_material,
			func(progress: int): element_progress.set_value.call_deferred(progress),
			func(static_body: StaticBody3D): _add_box_static_body.call_deferred(static_body),
			APERTURE_THICKNESS_MODIFIER
		)
		element_meshes_complete.emit.call_deferred()
	)


func _setup_export_callbacks() -> void:
	OBJExporter.export_progress_updated.connect(
		func(sid: int, prog: float): print("Exporting surface %s, %.02f/100 complete." % [sid, prog * 100])
	)
	OBJExporter.export_completed.connect(
		func(_obj, _mtl): print("Export complete!")
	)


func _add_box_static_body(static_body: StaticBody3D) -> void:
	length_mesh_instances.append(static_body)
	static_body.input_event.connect(_on_aperture_mesh_clicked.bind(static_body.get_node("box")))
	add_child(static_body)


func _on_aperture_mesh_complete(mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() > 0:
		print("Aperture mesh generated.")
		aperture_mesh_instance = MeshInstance3D.new()
		aperture_mesh_instance.name = "ApertureModel"
		add_child(aperture_mesh_instance)
		
		mesh.surface_set_material(0, aperture_material)
		aperture_mesh_instance.mesh = mesh
		aperture_progress.value = aperture_progress.max_value
	_progress_success_animation(aperture_progress_container)


func _on_aperture_mesh_clicked(
	_camera: Node, 
	event: InputEvent, 
	_event_position: Vector3, 
	_normal: Vector3, 
	_shape_index: int, 
	caller: ElementMeshInstance
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected_aperture_mesh = caller


func _on_beam_mesh_complete(mesh: ArrayMesh) -> void:
	if mesh.get_surface_count() > 0:
		print("Beam mesh generated.")
		beam_mesh_instance = MeshInstance3D.new()
		beam_mesh_instance.name = "Twiss"
		add_child(beam_mesh_instance)
		
		mesh.surface_set_material(0, beam_material)
		beam_mesh_instance.mesh = mesh
		beam_progress.value = beam_progress.max_value
	_progress_success_animation(beam_progress_container)


func _on_element_meshes_complete() -> void:
	_progress_success_animation(element_progress_container)


func _progress_success_animation(container: Container) -> void:
	container.modulate = Color.LIME_GREEN
	await get_tree().create_tween().tween_property(container, "modulate", Color.TRANSPARENT, 2.0).finished
	container.queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_M and event.pressed and not event.echo:
			_export_mesh()


func _export_mesh() -> void:
	mesh_export_thread.start(func():
		if beam_mesh_instance:
			OBJExporter.save_mesh_to_files(beam_mesh_instance.mesh, "user://", "mesh_export_beam")
		if aperture_mesh_instance:
			OBJExporter.save_mesh_to_files(aperture_mesh_instance.mesh, "user://", "mesh_export_aperture")
	)


func _exit_tree() -> void:
	if aperture_thread.is_started():
		aperture_thread.wait_to_finish()
	if beam_thread.is_started():
		beam_thread.wait_to_finish()
	if mesh_export_thread.is_started():
		mesh_export_thread.wait_to_finish()
	if magnets_thread.is_started():
		magnets_thread.wait_to_finish()
