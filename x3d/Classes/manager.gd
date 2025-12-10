## Manager.gd
## The coordinator, the boss, the big cheese.
## Sets up MeshBuilder instances, threads, UI feedback, etc.
extends Node3D

#region =========== Constants and Node Refs

@export_group("Node References")
## The main camera of the scene.
@export var main_camera: Camera3D

## The BeamAnimationController used to animate the movement of the beam.
## TODO: Make work with multiple mesh chunks.
@export var beam_animator: BeamAnimationController

@export_subgroup("Progress UI")
## The container for the aperture progress wheel, for fading out the whole panel.
@export var aperture_progress_container: Container

## The container for the beam progress wheel, for fading out the whole panel.
@export var beam_progress_container: Container

## The container for the element progress wheel, for fading out the whole panel.
@export var element_progress_container: Container

## The progress wheel for the apertures, modified via MeshBuilder.build_aperture_mesh().
@export var aperture_progress: TextureProgressBar

## The progress wheel for the beam, modified via MeshBuilder.build_beam_mesh().
@export var beam_progress: TextureProgressBar

## The progress wheel for the apertures, modified via MeshBuilder.build_box_meshes().
@export var element_progress: TextureProgressBar

@export_subgroup("'Load New...' UI")
## The Browse button for loading new survey files.
@export var load_survey_button: Button

## The Browse button for loading new aperture files.
@export var load_apertures_button: Button

## The Browse button for loading new twiss files.
@export var load_twiss_button: Button

## The confirmation button to start building.
@export var start_build_button: Button

## The label to inform of any errors when inputting new files to load.
@export var status_label: RichTextLabel

@export_subgroup("Visualisation UI")
## The container for the aperture information when an element is clicked on.
@export var aperture_info_container: Container

## The label that contains the currently selected element's info.
@export var aperture_info: RichTextLabel

## The view menu along the top, for turning on and off visibility for different objects.
@export var view_menu: PopupMenu

@export_group("Materials")
## The material used for apertures.
@export var default_aperture_material: Material

## The material used for the beam.
@export var default_beam_material: Material

## The material used for apertures when wireframe rendering is on.
@export var wireframe_aperture_material: Material
#endregion

#region ================ Onreadies
## The Timer used to debounce the 'Visualisation Scale' slider.
@onready var scale_debounce_timer := $Timer
#endregion

#region ================ Signals
## The signal to notify of an aperture mesh chunk being completed, to them be bundled into a MeshInstance.
signal aperture_mesh_complete(mesh: ArrayMesh)

## The signal to notify of a beam mesh chunk being completed, to them be bundled into a MeshInstance.
signal beam_mesh_complete(mesh: ArrayMesh)

## The signal to nofify that all element meshes are generated.
signal element_meshes_complete

signal web_thread_finished
#endregion

#region ================= Threads
## The thread to export meshes via. Currently unused.
var mesh_export_thread: Thread

## The thread the aperture chunk generation uses. Native platforms only.
var aperture_thread: Thread

## The thread the beam chunk generation uses. Native platforms only.
var beam_thread: Thread

## The thread the element mesh generation uses. Native platforms only.
var magnets_thread: Thread

## The thread everything uses in sequence. Web only, since concurrent mesh generation is painful
## when needing to stream CSV data over the JavascriptBridge.
var web_sequential_thread: Thread
#endregion

#region ================== Meshes
## The MeshBuilder, the main mesh generation object. Can be MeshBuilderNative or MeshBuilderWeb.
var mesh_builder: MeshBuilderBase

## The array of beam mesh chunks. These are positioned and rotated relative to the survey elements.
var beam_mesh_instances: Array[MeshInstance3D] = []

## The array of aperture mesh chunks. These are positioned and rotated relative to the survey elements.
var aperture_mesh_instances: Array[MeshInstance3D] = []

## The array of element meshes. These are positioned and rotated with Euler angles / 3d position.
var element_mesh_instances: Array[StaticBody3D] = []

## The currently used material for the apertures and elements.
var aperture_material: Material

## The currently used material for the beam.
var beam_material: Material

## The currently selected element mesh, as determined by left click. Shows element info and highlights element.
var selected_element_mesh: ElementMeshInstance:
	set(value):
		if selected_element_mesh:
			var old_mat := selected_element_mesh.get_active_material(0)
			
			# If the material is Standard, then we can interact with it the same way regardless.
			# However, all shaders need to have an `albedo_colour` param to interact with
			# In future, we might need more robust material checking
			match Settings.RENDERER_TYPE:
				Settings.RendererType.WIREFRAME:
					old_mat.set_shader_parameter("albedo_colour", old_mat.get_shader_parameter("albedo_colour") / 10)
					old_mat.set_shader_parameter("wireframe_colour", Color.BLACK)
				_:
					old_mat.albedo_color = old_mat.albedo_color / 10.0
				
				
		var new_mat := value.get_active_material(0)
		match Settings.RENDERER_TYPE:
				Settings.RendererType.WIREFRAME:
					new_mat.set_shader_parameter("albedo_colour", new_mat.get_shader_parameter("albedo_colour") * 10)
					new_mat.set_shader_parameter("wireframe_colour", new_mat.get_shader_parameter("albedo_colour").inverted())
				_:
					new_mat.albedo_color = new_mat.albedo_color * 10.0
		
		aperture_info_container.visible = true
		
		aperture_info.text = "[font_size=26]%s[/font_size]\n[color=#fbb]%s[/color]\n[font_size=18]%s[/font_size][color=dodgerblue][url=https://xsuite.readthedocs.io/en/latest/apireference.html#%s]Go to Docs[/url][/color]" % [
			value.first_slice_name, 
			value.type, 
			value.pretty_print_info(),
			value.type.to_lower() if "Slice" not in value.type else value.type.trim_suffix("Slice").to_lower()
		]
		selected_element_mesh = value

## Debounced value for the 'Visualisation Scale' slider. 
var pending_scale: float
#endregion

#region ================= File paths
## The file path to the survey file. Native only. Web handles this via upload and Javascript object handle.
var survey_path: String

## The file path to the aperture file. Native only. Web handles this via upload and Javascript object handle.
var apertures_path: String

## The file path to the twiss file. Native only. Web handles this via upload and Javascript object handle.
var twiss_path: String
#endregion


func _ready() -> void:
	# Set all meshes to visible
	for i in view_menu.item_count - 1:
		view_menu.set_item_checked(i, true)

	_connect_signals()
	_setup_export_callbacks()


## Resets state, reinitialises MeshBuilder for new inputs, starts generation process.
func setup() -> void:
	print("Mesh Manager setting up for building...")
	
	main_camera.reset_position()
	
	element_mesh_instances = []
	aperture_mesh_instances = []
	beam_mesh_instances = []

	if OS.has_feature("web"):
		mesh_builder = MeshBuilderWeb.new()
		mesh_builder.web_loader = %FileDialog.web_loader
	else:
		mesh_builder = MeshBuilderNative.new()
		mesh_builder.survey_data = time_it(DataLoader.load_survey, survey_path)
		mesh_builder.aperture_path = apertures_path
		mesh_builder.twiss_path = twiss_path
		main_camera.set_cull_mask_value(1, true) # Turned off in editor for Web culling, but we can reenable it. Yay!

	_setup_progress_bars()
	_setup_materials()
	start_building()


## Reinitialise the values for the progress wheels.
func _setup_progress_bars() -> void:
	element_progress_container.visible = true
	
	aperture_progress.value = 0
	beam_progress.value = 0
	element_progress.value = 0

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


## Sets the correct materials for the renderer type.
## TODO: Should be using an enum and getting the materials according to enum.
func _setup_materials() -> void:
	match Settings.RENDERER_TYPE:
		Settings.RendererType.WIREFRAME:
			aperture_material = wireframe_aperture_material
		_:
			aperture_material = default_aperture_material
	
	beam_material = default_beam_material


## Connect each of our signals to their callback functions. Also connects visiblity toggles to their
## lambda callback.
func _connect_signals() -> void:
	aperture_mesh_complete.connect(_on_aperture_mesh_complete)
	beam_mesh_complete.connect(_on_beam_mesh_complete)
	element_meshes_complete.connect(_on_element_meshes_complete)
	web_thread_finished.connect(_on_web_thread_finished)
	view_menu.index_pressed.connect(
		func (val):
			view_menu.set_item_checked(val, not view_menu.is_item_checked(val))
			match val:
				0: # Elements
					for m in element_mesh_instances:
						m.visible = not m.visible
						m.process_mode = Node.PROCESS_MODE_INHERIT if m.visible else Node.PROCESS_MODE_DISABLED
				1: # Aperture
					for m in aperture_mesh_instances:
						m.visible = not m.visible
				2: # Twiss
					for m in beam_mesh_instances:
						m.visible = not m.visible
	)


## If native, multi-thread to generate everything at the same time. If web, thread to have progress,
## but do all mesh generation in sequence.
func start_building() -> void:
	for c in get_children():
		if c is MeshInstance3D or c is StaticBody3D:
			c.queue_free()
	
	if mesh_builder is MeshBuilderWeb:
		_start_web_sequential_thread(
			mesh_builder.web_loader.get_apertures_count() > 0,
			mesh_builder.web_loader.get_twiss_count() > 0
		)
	else:
		if not apertures_path.is_empty():
			aperture_progress_container.visible = true
			_start_aperture_thread()
			
		if not twiss_path.is_empty():
			beam_progress_container.visible = true
			_start_beam_thread()
		
		_start_magnets_thread()


## Set up sequential thread, reset some state. On Web, meshes are generated on render_layer 2 
## so we can toggle the camera's cull mask rather than setting them all visible/nonvisible.
## Nonvisible meshes make for muuuuch faster generation.
func _start_web_sequential_thread(has_apertures: bool, has_twiss: bool) -> void:
	web_sequential_thread = Thread.new()
	
	web_sequential_thread.start(func():
		main_camera.set_cull_mask_value.call_deferred(2, false)
		mesh_builder.build_box_meshes(
			aperture_material,
			func(p): element_progress.set_value.call_deferred(p),
			func(body): _add_box_static_body.call_deferred(body),
			Settings.APERTURE_THICKNESS_MODIFIER
		)
		element_meshes_complete.emit.call_deferred()
		
		if has_apertures:
			aperture_progress_container.set_deferred("visible", true)
			mesh_builder.build_aperture_mesh(
				func(line): return DataLoader.parse_edge_line(line, Settings.APERTURE_THICKNESS_MODIFIER),
				func(p): aperture_progress.set_value.call_deferred(p),
				_add_aperture_mesh_chunk
			)
			aperture_mesh_complete.emit.call_deferred()
		
		if has_twiss:
			beam_progress_container.set_deferred("visible", true)
			mesh_builder.build_beam_mesh(
				func(line): return mesh_builder.create_beam_ellipse(line, Settings.APERTURE_THICKNESS_MODIFIER),
				func(p): beam_progress.set_value.call_deferred(p),
				_add_twiss_mesh_chunk
			)
			beam_mesh_complete.emit.call_deferred()
		
		main_camera.set_cull_mask_value.call_deferred(2, true)
		(mesh_builder as MeshBuilderWeb).web_loader.clear_all() # We can throw everything out now
		web_thread_finished.emit.call_deferred()
	)
	main_camera.reset_position() # Because one might get lost before everything becomes visible


# ==================== Threading
func _start_aperture_thread() -> void:
	aperture_thread = Thread.new()
	aperture_thread.start(func():
		mesh_builder.build_aperture_mesh(
			func(line): return DataLoader.parse_edge_line(line, Settings.APERTURE_THICKNESS_MODIFIER),
			func(p): aperture_progress.set_value.call_deferred(p),
			_add_aperture_mesh_chunk
		)
		aperture_mesh_complete.emit.call_deferred()
	)


func _start_beam_thread() -> void:
	beam_thread = Thread.new()
	beam_thread.start(func():
		mesh_builder.build_beam_mesh(
			func(line): return mesh_builder.create_beam_ellipse(line, Settings.APERTURE_THICKNESS_MODIFIER),
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
			Settings.APERTURE_THICKNESS_MODIFIER
		)
		element_meshes_complete.emit.call_deferred()
	)

# ==================== Mesh completion handlers

func _add_box_static_body(static_body: StaticBody3D) -> void:
	# static_body already set to render_layer 2 for camera culling
	element_mesh_instances.append(static_body)
	static_body.input_event.connect(_on_aperture_mesh_clicked.bind(static_body.get_node("box")))
	add_child(static_body)


func _add_aperture_mesh_chunk(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.mesh.surface_set_material(0, aperture_material)
	mesh_instance.name = "ApertureChunk%s" % len(aperture_mesh_instances)
	if mesh_builder is MeshBuilderWeb:
		mesh_instance.set_layer_mask_value(2, true) # Set to render_layer 2 for camera culling
	aperture_mesh_instances.append(mesh_instance)
	add_child.call_deferred(mesh_instance)


func _add_twiss_mesh_chunk(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.mesh.surface_set_material(0, beam_material)
	mesh_instance.name = "TwissChunk%s" % len(beam_mesh_instances)
	if mesh_builder is MeshBuilderWeb:
		mesh_instance.set_layer_mask_value(2, true) # Set to render_layer 2 for camera culling
	beam_mesh_instances.append(mesh_instance)
	add_child.call_deferred(mesh_instance)


func _on_aperture_mesh_complete() -> void:
	aperture_progress.value = aperture_progress.max_value
	if aperture_thread and aperture_thread.is_started():
		aperture_thread.wait_to_finish()
	_progress_success_animation(aperture_progress_container)


func _on_beam_mesh_complete() -> void:
	beam_progress.value = beam_progress.max_value
	if beam_thread and beam_thread.is_started():
		beam_thread.wait_to_finish()
	_progress_success_animation(beam_progress_container)
	## TODO: Animator needs to work across chunks
	#beam_animator.beam_mesh_instance = beam_mesh_instance
	#beam_animator.start_animation()


func _on_element_meshes_complete() -> void:
	if magnets_thread and magnets_thread.is_started():
		magnets_thread.wait_to_finish()
	_progress_success_animation(element_progress_container)
	

func _on_web_thread_finished() -> void:
	web_sequential_thread.wait_to_finish()


# ==================== Misc

## Timing function for benchmarking
func time_it(fn: Callable, ...varargs: Array) -> Variant:
	var t := Time.get_ticks_msec()
	var res = fn.callv(varargs)
	print("%s returned in %s ms." % [fn.get_method(), Time.get_ticks_msec() - t])
	return res


## Sets up callbacks for exporting meshes. Currently unused.
func _setup_export_callbacks() -> void:
	OBJExporter.export_progress_updated.connect(func(sid, prog):
		print("Exporting surface %s, %.02f%% complete." % [sid, prog * 100])
	)
	OBJExporter.export_completed.connect(func(_obj, _mtl):
		print("Export complete!")
	)


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
	for thread in [aperture_thread, beam_thread, magnets_thread, mesh_export_thread, web_sequential_thread]:
		if thread and thread.is_started():
			thread.wait_to_finish()
	if mesh_builder is MeshBuilderWeb:
		(mesh_builder as MeshBuilderWeb).web_loader.clear_all()

# ============= Event callbacks
## For debouncing 'Visualisation Scale' slider 
func _on_h_slider_value_changed(value: float) -> void:
	pending_scale = value
	scale_debounce_timer.start()

 ## For debouncing 'Visualisation Scale' slider... again. This one was a two-parter
func _on_timer_timeout() -> void:
	scale = Vector3.ONE * pending_scale


## When clicking on the info panel's 'Go to Docs' link, handle opening the default browser.
func _on_aperture_info_meta_clicked(meta: Variant) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s', '_blank')" % str(meta))
	else:
		OS.shell_open(str(meta))


## When clicking on an element mesh, set the selected_element_mesh property (and fire its setter)
func _on_aperture_mesh_clicked(_cam, event, _pos, _norm, _shape, caller: ElementMeshInstance) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected_element_mesh = caller
