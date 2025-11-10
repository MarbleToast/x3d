extends Button

@export var mesh_manager: Node

@export var line_edit_aperture: LineEdit
@export var line_edit_survey: LineEdit
@export var line_edit_twiss: LineEdit

@export var visualiser_canvas_layer: CanvasLayer
@export var menu_container: Control
@export var main_camera: Camera3D

@export var error_text: RichTextLabel

func _on_pressed() -> void:
	print("Import button pressed.")
	if not OS.has_feature("web"):
		if FileAccess.file_exists(line_edit_survey.text):
			mesh_manager.survey_path = line_edit_survey.text
		else:
			error_text.visible = true
			error_text.text = "[color=YELLOW]Invalid survey path: %s. Please check the file path.[/color]" % [error_string(FileAccess.get_open_error())]
			return
			
		if FileAccess.file_exists(line_edit_aperture.text):
			mesh_manager.apertures_path = line_edit_aperture.text
		else:
			mesh_manager.apertures_path = ""
			
		if FileAccess.file_exists(line_edit_twiss.text):
			mesh_manager.twiss_path = line_edit_twiss.text
		else:
			mesh_manager.twiss_path = ""

	if mesh_manager.survey_path or DataLoader.has_loaded_file_on_web(line_edit_survey.text):
		error_text.visible = false
		visualiser_canvas_layer.visible = true
		menu_container.visible = false
		main_camera.do_input_handling = true
		mesh_manager.setup()


func _on_toggle_import_toggled(toggled_on: bool) -> void:
	menu_container.visible = toggled_on
	main_camera.do_input_handling = not toggled_on
