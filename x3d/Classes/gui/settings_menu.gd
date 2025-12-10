extends PanelContainer

@onready var tab_bar := $TabBar
@export var general_settings_container: Container
@export var aperture_beam_settings_container: Container

var aperture_has_text := false
var twiss_has_text := false

func _on_line_edit_aperture_text_changed(new_text: String) -> void:
	aperture_has_text = new_text != ""
	_update_tab_bar_visibility()


func _on_line_edit_twiss_text_changed(new_text: String) -> void:
	twiss_has_text = new_text != ""
	_update_tab_bar_visibility()


func _update_tab_bar_visibility() -> void:
	tab_bar.visible = aperture_has_text or twiss_has_text


func _on_tab_bar_tab_changed(tab: int) -> void:
	var all_tab_content := [general_settings_container, aperture_beam_settings_container]
	for t in all_tab_content:
		t.visible = false
	all_tab_content[tab].visible = true
