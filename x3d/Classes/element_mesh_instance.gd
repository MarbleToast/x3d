class_name ElementMeshInstance
extends MeshInstance3D

var type: String
var first_slice_name: String
var other_info: Dictionary

func pretty_print_info() -> String:
	var s: String = ""
	for k: String in other_info:
		if k in ["line", "element_type", "name"]:
			continue
		
		s += "%s: %s\n" % [k.capitalize(), other_info[k]]
	return s

	
