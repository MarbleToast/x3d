extends FileDialog

@export var line_edit_aperture: LineEdit
@export var line_edit_survey: LineEdit
@export var line_edit_twiss: LineEdit

var target: LineEdit

var file_access_web: FileAccessWeb
var use_web: bool
var file_contents: String


func _ready() -> void:
	file_selected.connect(func (path): _on_file_selected(path))
	
	use_web = OS.has_feature("web")
	if use_web:
		file_access_web = FileAccessWeb.new()
		file_access_web.loaded.connect(
			func (file_name, _file_type, b64): 
				_on_file_selected(file_name, b64)
		)


func _on_browse_aperture_pressed() -> void:
	target = line_edit_aperture
	do_dialogue("aperture")


func _on_browse_survey_pressed() -> void:
	target = line_edit_survey
	do_dialogue("survey")


func _on_browse_twiss_pressed() -> void:
	target = line_edit_twiss
	do_dialogue("twiss")


func do_dialogue(key: String) -> void:
	if use_web:
		file_access_web.open("*.csv", key)
	else:
		visible = true


func _on_file_selected(path: String, _data_string: String = "") -> void:
	visible = false
	target.text = "%s" % path
