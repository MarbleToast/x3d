class_name CSVStreamReader
extends RefCounted

signal file_opened(file_name: String, total_lines: int)
signal error(message: String)

var _js_interface: JavaScriptObject
var _current_file: String = ""
var _total_lines: int = 0

func _init() -> void:
	if not OS.has_feature("web"):
		push_error("CSVStreamReader only works on web platform!")
		return
	
	JavaScriptBridge.eval(js_source_code, true)
	_js_interface = JavaScriptBridge.get_interface("godotCSVStreamReader")


func open_file(accept_files: String = ".csv") -> void:
	"""Opens a file picker dialog for CSV files"""
	if not _js_interface:
		error.emit("JavaScript interface not initialized")
		return
	
	var on_file_selected = JavaScriptBridge.create_callback(_on_file_selected)
	var on_error = JavaScriptBridge.create_callback(_on_error)
	
	_js_interface.openFile(accept_files, on_file_selected, on_error)


func get_line(line_index: int) -> PackedStringArray:
	"""Gets a specific line from the currently open CSV file"""
	if not _js_interface or _current_file.is_empty():
		return PackedStringArray()
	
	var line_data = _js_interface.getLine(_current_file, line_index)
	if line_data == null:
		return PackedStringArray()
	
	# Convert JavaScript array to PackedStringArray
	var result := PackedStringArray()
	var array_length: int = _js_interface.getArrayLength(line_data)
	for i in range(array_length):
		result.append(str(_js_interface.getArrayElement(line_data, i)))
	
	return result


func get_line_count() -> int:
	"""Returns total number of lines in the current file"""
	return _total_lines


func get_current_file_name() -> String:
	"""Returns the name of the currently loaded file"""
	return _current_file


func close_file() -> void:
	"""Closes the current file and frees memory"""
	if _js_interface and not _current_file.is_empty():
		_js_interface.closeFile(_current_file)
		_current_file = ""
		_total_lines = 0


func _on_file_selected(args: Array) -> void:
	_current_file = str(args[0])
	_total_lines = int(args[1])
	file_opened.emit(_current_file, _total_lines)


func _on_error(args: Array) -> void:
	var err_msg := str(args[0]) if args.size() > 0 else "Unknown error"
	error.emit(err_msg)


const js_source_code = """
function godotCSVStreamReaderInit() {
	// Storage for parsed CSV files
	const csvFiles = {};
	
	function parseCSVFile(text) {
		const lines = [];
		let currentLine = [];
		let currentField = '';
		let inQuotes = false;
		
		for (let i = 0; i < text.length; i++) {
			const char = text[i];
			const nextChar = text[i + 1];
			
			if (inQuotes) {
				if (char === '"') {
					if (nextChar === '"') {
						currentField += '"';
						i++;
					} else {
						inQuotes = false;
					}
				} else {
					currentField += char;
				}
			} else {
				if (char === '"') {
					inQuotes = true;
				} else if (char === ',' || char === ';') {
					currentLine.push(currentField.trim());
					currentField = '';
				} else if (char === '\\n') {
					if (currentField || currentLine.length > 0) {
						currentLine.push(currentField.trim());
						lines.push(currentLine);
						currentLine = [];
						currentField = '';
					}
				} else if (char === '\\r') {
					// Skip carriage returns
				} else {
					currentField += char;
				}
			}
		}
		
		// Handle last field/line
		if (currentField || currentLine.length > 0) {
			currentLine.push(currentField.trim());
			lines.push(currentLine);
		}
		
		return lines;
	}
	
	const interface = {
		openFile: (acceptFiles, successCallback, errorCallback) => {
			const input = document.createElement('input');
			input.type = 'file';
			input.accept = acceptFiles;
			console.log("Opening file...");
			
			input.onchange = (event) => {
				const file = event.target.files[0];
				if (!file) {
					errorCallback('No file selected');
					return;
				}
				
				const reader = new FileReader();
				
				reader.onload = (e) => {
					try {
						const text = e.target.result;
						const parsedLines = parseCSVFile(text);
						
						// Store parsed data
						csvFiles[file.name] = parsedLines;
						
						// Notify Godot
						successCallback(file.name, parsedLines.length);
					} catch (err) {
						errorCallback('Failed to parse CSV: ' + err.message);
					}
				};
				
				reader.onerror = () => {
					errorCallback('Failed to read file');
				};
				
				reader.readAsText(file);
			};
			
			input.click();
		},
		
		getLine: (fileName, lineIndex) => {
			const fileData = csvFiles[fileName];
			if (!fileData || lineIndex < 0 || lineIndex >= fileData.length) {
				return null;
			}
			return fileData[lineIndex];
		},
		
		getArrayLength: (arr) => {
			return arr ? arr.length : 0;
		},
		
		getArrayElement: (arr, index) => {
			return arr && arr[index] !== undefined ? arr[index] : '';
		},
		
		closeFile: (fileName) => {
			delete csvFiles[fileName];
		}
	};
	
	return interface;
}

var godotCSVStreamReader = godotCSVStreamReaderInit();
"""
