class_name DataLoader
extends RefCounted

# Aperture and beam constants
const APERTURE_TORUS_SCALE_FACTOR := 1.0
const RELATIVISTIC_GAMMA := 7247.364757558866
const BEAM_EMITTANCE_X := 2.5e-6 / RELATIVISTIC_GAMMA
const BEAM_EMITTANCE_Y := 2.5e-6 / RELATIVISTIC_GAMMA
const BEAM_NUM_SIGMAS := 3
const BEAM_SIGMA_DELTA := 8e-4


## Parses the survey CSV header and returns a dictionary mapping column names to indices
static func parse_survey_header(header: PackedStringArray) -> Dictionary:
	var column_map := {}
	var required_columns := ["x", "y", "z", "theta", "phi", "psi", "element_type", "length", "name", "s"]
	
	for i in range(header.size()):
		var col_name := header[i].strip_edges().to_lower()
		if col_name in required_columns:
			column_map[col_name] = i
	
	# Verify all required columns were found
	for col in required_columns:
		if col not in column_map:
			push_error("Required column '%s' not found in CSV header" % col)
			return {}
	
	return column_map


## Converts a stringified Python list to a Godot array
##
## Should be fairly portable for types other than floats, and converts None to null.
static func python_list_to_godot_array(arr_str: String) -> Array:
	arr_str = arr_str.strip_edges().trim_prefix("[").trim_suffix("]")
	var result: Array = []
	if arr_str == "":
		return result
	
	for num_str in arr_str.split(","):
		num_str = num_str.strip_edges()
		if num_str == "None" or num_str == "" or num_str == "nan":
			result.append(null)
		else:
			result.append(str_to_var(num_str))
	return result


## Parses a line of aperture data from an Xsuite survey CSV using the column map
static func parse_survey_line(line: PackedStringArray, column_map: Dictionary) -> Dictionary:
	if len(line) < 7:
		return {}
	
	return {
		position = Vector3(
			float(line[column_map["x"]]), 
			float(line[column_map["y"]]), 
			float(line[column_map["z"]])
		) * APERTURE_TORUS_SCALE_FACTOR,
		theta = float(line[column_map["theta"]]),
		phi = float(line[column_map["phi"]]),
		psi = float(line[column_map["psi"]]),
		element_type = line[column_map["element_type"]],
		length = float(line[column_map["length"]]),
		s = float(line[column_map["s"]]),
		name = line[column_map["name"]],
		line = JSON.stringify(line)
	}


## Parses a line of beam envelope data from an Xsuite twiss CSV
static func parse_twiss_line(line: PackedStringArray) -> Dictionary:
	if len(line) < 7:
		return {}
	
	var x := float(line[3])
	var y := float(line[5])
	
	var beta_x := float(line[17])
	var beta_y := float(line[18])
	
	var dx := float(line[23])
	var dy := float(line[25])
	
	var s := float(line[2])
	
	return {
		position = Vector2(x, y),
		s = s,
		sigma = BEAM_SIGMA_DELTA * BEAM_NUM_SIGMAS * Vector2(
			sqrt(BEAM_EMITTANCE_X * beta_x) + absf(dx),
			sqrt(BEAM_EMITTANCE_Y * beta_y) + absf(dy)
		)
	}


## Parses a line of aperture vertex data from an Xsuite apertures CSV
## Returns {points: Array[Vector2], s: float}
static func parse_edge_line(line: PackedStringArray, thickness_multiplier: float = 1.0) -> Dictionary:
	var points: Array[Vector2] = []
	if len(line) < 5:
		return {}
		
	var xs: Array = python_list_to_godot_array(line[3])
	var ys: Array = python_list_to_godot_array(line[4])
	
	if len(xs) == 0 or len(ys) == 0 or xs[0] == null or ys[0] == null:
		return {}
	
	var n: int = min(len(xs), len(ys))
	points.resize(n)
	for i in n:
		if xs[i] != null and ys[i] != null:
			points[i] = Vector2(xs[i], ys[i]) * thickness_multiplier
		else:
			points[i] = Vector2.ZERO

	return {
		points = points,
		s = float(line[3])
	}


## Reads and parses all lines from an Xsuite survey file, discarding non-usable lines
static func load_survey(survey_path: String) -> Array[Dictionary]:
	print("Loading survey data...")
		
	var sf := FileAccess.open(survey_path, FileAccess.READ)
	
	if not sf:
		push_warning("Couldn't open survey file.")
		return []
	
	# Read and parse header to find column indices
	var header := sf.get_csv_line()
	var column_map := parse_survey_header(header)
	
	if column_map.is_empty():
		push_error("Failed to parse survey CSV header - required columns not found")
		return []
	
	var elements: Array[Dictionary] = []
	while not sf.eof_reached():
		var slice_line := sf.get_csv_line()
		if len(slice_line) < 5:
			continue
			
		var curr_slice := parse_survey_line(slice_line, column_map)
		if curr_slice.is_empty():
			continue
			
		elements.append(curr_slice)
	
	print("Got %s elements." % elements.size())
	return elements


## Loads all lines from a CSV into an array
static func load_csv(path: String) -> Array[PackedStringArray]:
	var content: Array[PackedStringArray] = []

	var df := FileAccess.open(path, FileAccess.READ)
	if df == null:
		return content
	df.get_csv_line()
	while not df.eof_reached():
		var line := df.get_csv_line()
		if line.size() >= 5:
			content.append(line)
	df.close()
		
	return content


static func has_loaded_file_on_web(file_key: String) -> bool:
	print("Accessing CSV file object for '%s'..." % file_key)
	return JavaScriptBridge.get_interface("csvFiles")[file_key] != null
