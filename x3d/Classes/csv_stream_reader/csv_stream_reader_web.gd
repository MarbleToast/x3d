class_name CSVStreamReader
extends RefCounted

signal file_opened(file_name: String, total_lines: int)
signal error(message: String)

var _js_interface: JavaScriptObject
var success_callback: JavaScriptObject
var error_callback: JavaScriptObject

var _current_file: String = ""
var _total_lines: int = 0
var _batch_buffer: Dictionary = {}  # batch_start -> Array[Array[String]]
var _batch_access_order: Array = []  # Track access order for LRU eviction
var _last_batch_start: int = -1

const BATCH_SIZE: int = 20 # Each batch has 100 lines
const MAX_CACHED_BATCHES: int = 2  # Keep only 10 batches in memory

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
	
	_batch_buffer = {}
	_last_batch_start = -1
	success_callback = JavaScriptBridge.create_callback(_on_file_selected)
	error_callback = JavaScriptBridge.create_callback(_on_error)
	
	_js_interface.openFile(accept_files, success_callback, error_callback)


func get_line(line_index: int) -> PackedStringArray:
	if not _js_interface or _current_file.is_empty():
		return PackedStringArray()
	
	@warning_ignore("integer_division")
	var batch_start: int = (line_index / BATCH_SIZE) * BATCH_SIZE # yes, looks weird

	if not _batch_buffer.has(batch_start):
		_load_batch(batch_start)

	var batch: Array = _batch_buffer.get(batch_start, [])
	if len(batch) > 0:
		var line_in_batch = line_index - batch_start
		if line_in_batch >= 0 and line_in_batch < batch.size():
			return PackedStringArray(batch[line_in_batch])
	
	return PackedStringArray()


func get_line_count() -> int:
	return _total_lines


func get_current_file_name() -> String:
	return _current_file


func close_file() -> void:
	if _js_interface and not _current_file.is_empty():
		_js_interface.closeFile(_current_file)
		_current_file = ""
		_total_lines = 0
		_batch_buffer = {}
		_batch_access_order = []
		_last_batch_start = -1


func _load_batch(batch_start: int) -> void:
	if not _js_interface or _current_file.is_empty():
		return
	
	var end_index = mini(batch_start + BATCH_SIZE, _total_lines)
	var batch_size = end_index - batch_start
	
	var data = _js_interface.getLineBatch(_current_file, batch_start, batch_size)
	if data:
		
		# Evict oldest batch if cache is full
		while _batch_buffer.size() >= MAX_CACHED_BATCHES:
			var oldest_batch = _batch_access_order.pop_front()
			_batch_buffer.erase(oldest_batch)
		
		var parsed = JSON.parse_string(data)
		if parsed == null or not parsed is Array:
			print("Batch %s parsed as something weird: %s" % [batch_start, parsed])
			return
		
		_batch_buffer[batch_start] = parsed
		_batch_access_order.append(batch_start)
		_last_batch_start = batch_start


func _on_file_selected(args: Array) -> void:
	print("Mr. Godot here. File %s loaded with %d lines." % [args[0], args[1]])
	_current_file = str(args[0])
	_total_lines = int(args[1])
	_batch_buffer = {}
	_batch_access_order = []
	_last_batch_start = -1
	file_opened.emit(_current_file, _total_lines)


func _on_error(args: Array) -> void:
	var err_msg := str(args[0]) if args.size() > 0 else "Unknown error"
	error.emit(err_msg)


const js_source_code = """	
function godotCSVStreamReaderInit() {
	// Check if Papa Parse is loaded
	if (typeof Papa === 'undefined') {
		console.error('PapaParse library not found!');
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
						
						console.log("Paging Mr. Godot...")
						successCallback(file.name, results.data.length);
					},
					error: function(error) {
						console.error("Parse error:", error);
						errorCallback('Failed to parse CSV: ' + error.message);
					},
					skipEmptyLines: true,
					delimiter: "",
					newline: "",
					quoteChar: '"',
					escapeChar: '"',
					dynamicTyping: false,
					preview: 0,
					encoding: "",
					worker: false,
					comments: false,
					step: undefined,
					fastMode: undefined,
					withCredentials: undefined
				});
			};
			
			input.click();
		},
		
		getLine: (fileName, lineIndex) => {
			const fileData = window.csvFiles[fileName];
			if (!fileData || lineIndex < 0 || lineIndex >= fileData.length) {
				return null;
			}
			return JSON.stringify(fileData[lineIndex]);
		},
		
		getLineBatch: (fileName, startIndex, batchSize) => {
			const fileData = window.csvFiles[fileName];
			if (!fileData) {
				return null;
			}
			
			const endIndex = Math.min(startIndex + batchSize, fileData.length);
			const batch = fileData.slice(startIndex, endIndex);
			return JSON.stringify(batch);
		},
		
		closeFile: (fileName) => {
			console.log("Closing file:", fileName);
			delete window.csvFiles[fileName];
		}
	};
	
	return interface;
}

var godotCSVStreamReader = godotCSVStreamReaderInit();
"""
