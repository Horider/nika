extends RefCounted

const Flow = preload("res://scripts/story_flow.gd")
const AUTO_PATH := "user://autosave.json"
const MANUAL_PATH := "user://manual-save.json"

static func write(path: String, state: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var body := JSON.stringify(state)
	var wrapped := JSON.stringify({"format": "nika-godot", "body": body, "sha256": body.sha256_text()})
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(wrapped)
	file.flush()
	file.close()
	var backup := absolute + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		var error := DirAccess.rename_absolute(absolute, backup)
		if error != OK: return error
	var result := DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if result != OK and FileAccess.file_exists(backup):
		DirAccess.rename_absolute(backup, absolute)
	return result

static func read(path: String, catalog: Dictionary) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(candidate)) != OK: continue
		var parsed: Variant = parser.data
		if not parsed is Dictionary: continue
		var data: Variant = parsed
		if parsed.get("format") == "nika-godot":
			var body := str(parsed.get("body", ""))
			if body.sha256_text() != parsed.get("sha256"): continue
			if parser.parse(body) != OK: continue
			data = parser.data
		if not data is Dictionary: continue
		var flow := Flow.new(catalog)
		if flow.restore(data):
			return {"ok": true, "state": flow.snapshot(), "backup": candidate != path}
	return {"ok": false, "state": {}, "backup": false}
