class_name WebDataLoader
extends RefCounted

## Handles loading CSV data on both native and web platforms
## On web, uses CSVStreamReader to stream data from JavaScript

signal loading_complete(data_type: String)
signal loading_progress(current: int, total: int)
signal loading_error(message: String)

var survey_reader: CSVStreamReader
var apertures_reader: CSVStreamReader
var twiss_reader: CSVStreamReader

var _is_web: bool = false


func _init() -> void:
	_is_web = OS.has_feature("web")
	
	if _is_web:
		survey_reader = CSVStreamReader.new()
		apertures_reader = CSVStreamReader.new()
		twiss_reader = CSVStreamReader.new()
		
		survey_reader.file_opened.connect(_on_survey_opened)
		apertures_reader.file_opened.connect(_on_apertures_opened)
		twiss_reader.file_opened.connect(_on_twiss_opened)
		
		survey_reader.error.connect(func(msg): loading_error.emit("Survey: " + msg))
		apertures_reader.error.connect(func(msg): loading_error.emit("Apertures: " + msg))
		twiss_reader.error.connect(func(msg): loading_error.emit("Twiss: " + msg))


func load_survey_file() -> void:
	"""Opens file picker for survey data"""
	if _is_web:
		survey_reader.open_file(".csv")
	else:
		push_error("Use native file loading for non-web platforms")


func load_apertures_file() -> void:
	"""Opens file picker for apertures data"""
	if _is_web:
		apertures_reader.open_file(".csv")
	else:
		push_error("Use native file loading for non-web platforms")


func load_twiss_file() -> void:
	"""Opens file picker for twiss data"""
	if _is_web:
		twiss_reader.open_file(".csv")
	else:
		push_error("Use native file loading for non-web platforms")


func get_survey_line(index: int, column_map: Dictionary) -> Dictionary:
	"""Gets a single survey line, parsed into a dictionary"""
	if not _is_web:
		return {}
	
	var line := survey_reader.get_line(index)
	if line.is_empty():
		return {}
	
	return DataLoader.parse_survey_line(line, column_map)


func get_apertures_line(index: int) -> PackedStringArray:
	"""Gets a single apertures line"""
	if not _is_web:
		return PackedStringArray()
	
	return apertures_reader.get_line(index)


func get_twiss_line(index: int) -> PackedStringArray:
	"""Gets a single twiss line"""
	if not _is_web:
		return PackedStringArray()
	
	return twiss_reader.get_line(index)


func get_survey_count() -> int:
	"""Returns number of survey lines"""
	return survey_reader.get_line_count() if _is_web else 0


func get_apertures_count() -> int:
	"""Returns number of aperture lines"""
	return apertures_reader.get_line_count() if _is_web else 0


func get_twiss_count() -> int:
	"""Returns number of twiss lines"""
	return twiss_reader.get_line_count() if _is_web else 0


func has_all_files() -> bool:
	"""Check if all required files are loaded"""
	if not _is_web:
		return false
	
	return (survey_reader.get_line_count() > 0 and 
			apertures_reader.get_line_count() > 0 and 
			twiss_reader.get_line_count() > 0)


func load_all_survey_data() -> Array[Dictionary]:
	"""Loads entire survey dataset into memory (use with caution on web)"""
	var result: Array[Dictionary] = []
	var count := get_survey_count()
	var column_map := {}
	
	for i in range(count):
		var line_dict := get_survey_line(i, column_map)
		if not line_dict.is_empty():
			result.append(line_dict)
		
		if i % 100 == 0:
			loading_progress.emit(i, count)
	
	return result


func clear_all() -> void:
	"""Clears all loaded files from memory"""
	if _is_web:
		survey_reader.close_file()
		apertures_reader.close_file()
		twiss_reader.close_file()


func _on_survey_opened(file_name: String, total_lines: int) -> void:
	print("Survey file opened: %s (%d lines)" % [file_name, total_lines])
	loading_complete.emit("survey")


func _on_apertures_opened(file_name: String, total_lines: int) -> void:
	print("Apertures file opened: %s (%d lines)" % [file_name, total_lines])
	loading_complete.emit("apertures")


func _on_twiss_opened(file_name: String, total_lines: int) -> void:
	print("Twiss file opened: %s (%d lines)" % [file_name, total_lines])
	loading_complete.emit("twiss")
