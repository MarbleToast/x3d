extends FileDialog

@export var line_edit_aperture: LineEdit
@export var line_edit_survey: LineEdit
@export var line_edit_twiss: LineEdit

var target: LineEdit

var file_access_web: FileAccessWeb
var use_web: bool
var file_contents: String


func _ready() -> void:
	use_web = OS.has_feature("web")
	if not use_web:
		file_selected.connect(func (path): _on_file_selected(path))


func _on_browse_aperture_pressed() -> void:
	target = line_edit_aperture
	do_dialogue("aperture")


func _on_browse_survey_pressed() -> void:
	target = line_edit_survey
	do_dialogue("survey")


func _on_browse_twiss_pressed() -> void:
	target = line_edit_twiss
	do_dialogue("twiss")


func do_dialogue(_key: String) -> void:
	if not use_web:
		visible = true


func _on_file_selected(path: String, _data_string: String = "") -> void:
	visible = false
	target.text = "%s" % path
