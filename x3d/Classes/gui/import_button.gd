extends Button

@export var mesh_manager: Node

@export var line_edit_aperture: LineEdit
@export var line_edit_survey: LineEdit
@export var line_edit_twiss: LineEdit

@export var visualiser_canvas_layer: Control
@export var menu_container: Control
@export var main_camera: Camera3D

@export var error_text: RichTextLabel

func _on_pressed() -> void:
	print("Import button pressed.")
	if not OS.has_feature("web"):
		if line_edit_survey.text == "":
			error_text.visible = true
			error_text.text = "[color=YELLOW]Empty survey path. You need to include a survey file (*.csv).[/color]"
			return
		
		if not line_edit_survey.text.get_extension() in ["csv", "tfs"]:
			error_text.visible = true
			error_text.text = "[color=YELLOW]Invalid survey path. Please check the file extension (*.csv).[/color]"
			return
			
		if not FileAccess.file_exists(line_edit_survey.text):
			error_text.visible = true
			error_text.text = "[color=YELLOW]Invalid survey path. Please check the file exists.[/color]"
			return

		mesh_manager.survey_path = line_edit_survey.text
			
			
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


func _on_popup_menu_file_index_pressed(index: int) -> void:
	if index == 0:
		menu_container.visible = not menu_container.visible
		main_camera.do_input_handling = menu_container.visible
