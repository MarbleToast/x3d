class_name CSVStreamReader
extends RefCounted

signal file_opened(file_name: String, total_lines: int)
signal error(message: String)

var _js_interface: JavaScriptObject
var success_callback: JavaScriptObject
var error_callback: JavaScriptObject

var _current_file: String = ""
var _total_lines: int = 0

func _init() -> void:
	if not OS.has_feature("web"):
		push_error("CSVStreamReader only works on web platform!")
		return
	
	JavaScriptBridge.eval(js_source_code, true)
	_js_interface = JavaScriptBridge.get_interface("godotCSVStreamReader")


func open_file(accept_files: String = ".csv") -> void:
	if not _js_interface:
		error.emit("JavaScript interface not initialized")
		return
	
	success_callback = JavaScriptBridge.create_callback(_on_file_selected)
	error_callback = JavaScriptBridge.create_callback(_on_error)
	
	_js_interface.openFile(accept_files, success_callback, error_callback)


func get_line(line_index: int) -> PackedStringArray:
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
	return _total_lines


func get_current_file_name() -> String:
	return _current_file


func close_file() -> void:
	if _js_interface and not _current_file.is_empty():
		_js_interface.closeFile(_current_file)
		_current_file = ""
		_total_lines = 0


func _on_file_selected(args: Array) -> void:
	print("File %s loaded with %d lines." % [args[0], args[1]])
	_current_file = str(args[0])
	_total_lines = int(args[1])
	file_opened.emit(_current_file, _total_lines)


func _on_error(args: Array) -> void:
	var err_msg := str(args[0]) if args.size() > 0 else "Unknown error"
	error.emit(err_msg)


const js_source_code = """	
function godotCSVStreamReaderInit() {
	// Check if Papa Parse is loaded
	if (typeof Papa === 'undefined') {
		console.error('PapaParse library not found! Make sure to include it in your HTML head:');
		console.error('<script src="https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js"></script>');
	}
	
	const interface = {
		openFile: (acceptFiles, successCallback, errorCallback) => {
			const input = document.createElement('input');
			input.type = 'file';
			input.accept = acceptFiles;
			console.log("Opening file picker...");
			
			input.onchange = (event) => {
				const file = event.target.files[0];
				if (!file) {
					console.error("No file selected");
					errorCallback('No file selected');
					return;
				}
				
				console.log("Reading file:", file.name);
				
				// Use PapaParse to parse the CSV
				Papa.parse(file, {
					complete: function(results) {
						console.log("Parse complete. Rows:", results.data.length);

						window.csvFiles[file.name] = results.data;
						
						console.log("Calling Godot to inform it of success!")
						successCallback(file.name, results.data.length);
					},
					error: function(error) {
						console.error("Parse error:", error);
						errorCallback('Failed to parse CSV: ' + error.message);
					},
					skipEmptyLines: true,
					// Additional PapaParse options for robustness
					delimiter: "",  // Auto-detect
					newline: "",    // Auto-detect
					quoteChar: '"',
					escapeChar: '"',
					dynamicTyping: false,  // Keep everything as strings for consistency
					preview: 0,     // Parse entire file
					encoding: "",   // Auto-detect
					worker: false,  // Don't use worker thread (keep it simple)
					comments: false,
					step: undefined,
					fastMode: undefined,
					withCredentials: undefined
				});
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
			console.log("Closing file:", fileName);
			delete csvFiles[fileName];
		}
	};
	
	return interface;
}

var godotCSVStreamReader = godotCSVStreamReaderInit();
"""
