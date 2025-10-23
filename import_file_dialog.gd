extends FileDialog

@export var line_edit_aperture: LineEdit
@export var line_edit_survey: LineEdit
@export var line_edit_twiss: LineEdit

@export var status_label: RichTextLabel

var target: LineEdit

var web_loader: WebDataLoader
var use_web: bool
var file_contents: String


func setup_web_loading() -> void:
	print("Setting up web loaders...")
	
	web_loader = WebDataLoader.new()
	
	# Connect signals
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
	else:
		print("Desktop, initialising standard FileDialog node.")
		file_selected.connect(func (path): _on_file_selected("", path))


func _on_browse_aperture_pressed() -> void:
	target = line_edit_aperture
	do_dialogue(web_loader.load_apertures_file)


func _on_browse_survey_pressed() -> void:
	target = line_edit_survey
	do_dialogue(web_loader.load_survey_file if web_loader else null)


func _on_browse_twiss_pressed() -> void:
	target = line_edit_twiss
	do_dialogue(web_loader.load_twiss_file)


func do_dialogue(fn: Callable = Callable()) -> void:
	if use_web:
		fn.call()
	else:
		visible = true


func _on_file_selected(_data_type: String, file_name: String) -> void:
	visible = false
	target.text = "%s" % file_name
