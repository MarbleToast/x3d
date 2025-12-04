extends FileDialog

@export var line_edit_aperture: LineEdit
@export var line_edit_survey: LineEdit
@export var line_edit_twiss: LineEdit

@export var remove_aperture: Button
@export var remove_twiss: Button

@export var status_label: RichTextLabel

var target: LineEdit

var web_loader: DataLoaderWeb
var use_web: bool


func setup_web_loading() -> void:
	print("Setting up web loaders...")
	
	web_loader = DataLoaderWeb.new()
	
	web_loader.loading_complete.connect(_on_file_selected)
	web_loader.loading_error.connect(_on_loading_error)


func _on_loading_error(message: String) -> void:
	if status_label:
		status_label.text = "Error: " + message
	push_error(message)


func _ready() -> void:
	use_web = OS.has_feature("web")
	if use_web:
		setup_web_loading()


func _on_browse_aperture_pressed() -> void:
	target = line_edit_aperture
	do_dialogue("apertures")


func _on_browse_survey_pressed() -> void:
	target = line_edit_survey
	do_dialogue("survey")


func _on_browse_twiss_pressed() -> void:
	target = line_edit_twiss
	do_dialogue("twiss")


func do_dialogue(key: String) -> void:
	if use_web:
		var fn: Callable
		match key:
			"survey":
				fn = web_loader.load_survey_file
			"apertures":
				fn = web_loader.load_apertures_file
			"twiss":
				fn = web_loader.load_twiss_file
		fn.call()
	else:
		visible = true


func _on_file_selected(file_name: String) -> void:
	visible = false
	target.text = "%s" % file_name
	if target == line_edit_aperture:
		remove_aperture.visible = true
	elif target == line_edit_twiss:
		remove_twiss.visible = true


func _on_remove_aperture_pressed() -> void:
	remove_aperture.visible = false
	line_edit_aperture.text = ""


func _on_remove_twiss_pressed() -> void:
	remove_twiss.visible = false
	line_edit_twiss.text = ""
