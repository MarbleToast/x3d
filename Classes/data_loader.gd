class_name DataLoader
extends RefCounted

# Aperture constants
const APERTURE_TORUS_SCALE_FACTOR := 1.0

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
		if num_str == "None" or num_str == "":
			result.append(null)
		else:
			result.append(str_to_var(num_str))
	return result

## Parses a line of aperture data from an Xsuite survey CSV
static func parse_survey_line(line: PackedStringArray) -> Dictionary:
	if len(line) < 7:
		return {}
	return {
		center = Vector3(float(line[1]), float(line[2]), float(line[3])) * APERTURE_TORUS_SCALE_FACTOR,
		psi = deg_to_rad(float(line[6])),
		type = line[14],
		length = float(line[9]),
		id = line[7]
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
	
	# Beam constants
	const RELATIVISTIC_GAMMA := 7247.364757558866
	const BEAM_EMITTANCE_X := 2.5e-6 / RELATIVISTIC_GAMMA
	const BEAM_EMITTANCE_Y := 2.5e-6 / RELATIVISTIC_GAMMA
	const BEAM_NUM_SIGMAS := 3
	const BEAM_SIGMA_DELTA := 8e-4
	
	return {
		position = Vector2(x, y),
		sigma = BEAM_SIGMA_DELTA * BEAM_NUM_SIGMAS * Vector2(
			sqrt(BEAM_EMITTANCE_X * beta_x) + absf(dx),
			sqrt(BEAM_EMITTANCE_Y * beta_y) + absf(dy)
		)
	}

## Parses a line of aperture vertex data from an Xsuite apertures CSV
static func parse_edge_line(line: PackedStringArray) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if len(line) < 5:
		return points
		
	var xs: Array = python_list_to_godot_array(line[3])
	var ys: Array = python_list_to_godot_array(line[4])
	
	if len(xs) == 0 or len(ys) == 0 or xs[0] == null or ys[0] == null:
		return points
	
	var n: int = min(len(xs), len(ys))
	points.resize(n)
	for i in n:
		if xs[i] != null and ys[i] != null:
			points[i] = Vector2(xs[i], ys[i])
		else:
			points[i] = Vector2.ZERO
	return points

# Reads and parses all lines from an Xsuite survey file, discarding non-usable lines
static func load_survey(survey_path: String) -> Array[Dictionary]:
	print("Loading survey data...")
	var sf := FileAccess.open(survey_path, FileAccess.READ)
	
	# Skip header
	sf.get_csv_line()
	
	var apertures: Array[Dictionary] = []
	while not sf.eof_reached():
		var slice_line := sf.get_csv_line()
		if len(slice_line) < 5:
			continue
			
		var curr_slice := parse_survey_line(slice_line)
		if curr_slice.is_empty():
			continue
			
		apertures.append(curr_slice)
	
	print("Got %s apertures." % apertures.size())
	return apertures

## Loads all lines from an Xsuite aperture file into an array
## 
## We need to have all lines because parse_edge_line() discards lines without vertex data,
## meaning we would drop out of sync with the survey file when creating aperture segments 
static func load_aperture_edge_lines(edges_path: String) -> Array[PackedStringArray]:
	print("Loading edge data...")
	var ef := FileAccess.open(edges_path, FileAccess.READ)

	# Skip header
	ef.get_csv_line()
	
	var edges: Array[PackedStringArray] = []
	while not ef.eof_reached():
		var edges_line := ef.get_csv_line()
		if len(edges_line) < 5:
			continue
		edges.append(edges_line)
	
	print("Got %s aperture edges." % edges.size())
	return edges

## Builds segments of consecutive survey slices of the same type
static func build_aperture_segments(survey_data: Array[Dictionary], edges_data: Array[PackedStringArray]) -> Array[Dictionary]:
	print("Building segments...")
	var segments: Array[Dictionary] = []
	var current_type := ""
	var current_segment := {
		type = "", 
		survey = [], 
		edges = [],
		id = "",
	}

	for i in survey_data.size():
		var slice := survey_data[i]
		if slice.type != current_type:
			# Push previous segment if it's not the first line
			if current_segment.survey.size() > 0:
				segments.append(current_segment)
				
			# Start new segment
			current_type = slice.type
			current_segment = {
				id = slice.id,
				type = current_type, 
				survey = [], 
				edges = [] 
			}
		
		var parsed_edges := parse_edge_line(edges_data[i])
		if len(parsed_edges) == 0:
			continue
			
		current_segment.survey.append(slice)
		current_segment.edges.append(parsed_edges)

	# push last
	if current_segment.survey.size() > 0:
		segments.append(current_segment)

	return segments
