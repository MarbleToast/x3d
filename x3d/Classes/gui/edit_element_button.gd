extends Button

@export var edit_element_menu: PanelContainer


func _on_toggled(toggled_on: bool) -> void:
	edit_element_menu.visible = toggled_on
