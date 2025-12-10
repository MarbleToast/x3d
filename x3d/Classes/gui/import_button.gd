extends Button

@export var mesh_manager: Node
@export var main_camera: Camera3D

@export_group("File Input Fields")
@export var line_edit_survey: LineEdit
@export var line_edit_aperture: LineEdit
@export var line_edit_twiss: LineEdit

@export_group("Settings Input Fields")
@export var renderer_type: OptionButton
@export var element_blacklist: TextEdit

@export_group("UI Containers")
@export var visualiser_canvas_layer: Control
@export var menu_container: Control
@export var error_text: RichTextLabel

@onready var _is_web := OS.has_feature("web")

func _on_pressed() -> void:
	print("Import button pressed.")
	
	var validation_error := _validate_inputs()
	if validation_error:
		_show_error(validation_error)
		return
	
	handle_pre_setup()
	mesh_manager.setup()


func _validate_inputs() -> String:
	if line_edit_survey.text.is_empty():
		return "Empty survey path. You need to include a survey file (*.csv)."
	
	if not line_edit_survey.text.get_extension() in ["csv", "tfs"]:
		return "Invalid survey path. Please check the file extension (*.csv)."
	
	if _is_web:
		return _validate_web_inputs()
	else:
		return _validate_native_inputs()


func _validate_web_inputs() -> String:
	if not DataLoader.has_loaded_file_on_web(line_edit_survey.text):
		return "The survey file could not be loaded."
	return ""


func _validate_native_inputs() -> String:
	if not FileAccess.file_exists(line_edit_survey.text):
		return "Invalid survey path. Please check the file exists."
	return ""


func handle_pre_setup() -> void:
	error_text.visible = false
	menu_container.visible = false
	visualiser_canvas_layer.visible = true
	main_camera.do_input_handling = true
	
	_push_settings()
	
	if _is_web:
		_clear_inputs()
	else:
		_configure_native_mesh_manager()


func _configure_native_mesh_manager() -> void:
	mesh_manager.survey_path = line_edit_survey.text
	mesh_manager.apertures_path = line_edit_aperture.text if FileAccess.file_exists(line_edit_aperture.text) else ""
	mesh_manager.twiss_path = line_edit_twiss.text if FileAccess.file_exists(line_edit_twiss.text) else ""


func _push_settings() -> void:
	Settings.ELEMENT_BLACKLIST = element_blacklist.text.remove_char(" ".unicode_at(0)).split(",")
	Settings.RENDERER_TYPE = Settings.RendererType[renderer_type.get_item_text(renderer_type.selected).to_upper()] # This is brittle but whatever


func _clear_inputs() -> void:
	line_edit_survey.text = ""
	line_edit_aperture.text = ""
	line_edit_twiss.text = ""


func _show_error(message: String) -> void:
	error_text.visible = true
	error_text.text = "[color=YELLOW]%s[/color]" % message


## Toggles the import menu visibility and the camera input handling
func _on_popup_menu_file_index_pressed(index: int = 0) -> void:
	if index == 0: 
		visualiser_canvas_layer.visible = true
		menu_container.visible = not menu_container.visible
		main_camera.do_input_handling = not menu_container.visible
	
