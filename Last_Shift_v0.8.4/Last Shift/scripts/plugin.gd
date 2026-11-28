@tool
extends EditorPlugin
## Пересборка процедурной сцены после завершения импорта GLB.

var _refresh_pending := false


func _enter_tree() -> void:
	add_tool_menu_item("Обновить модели сцены", _queue_refresh)
	get_editor_interface().get_resource_filesystem().resources_reimported.connect(_on_reimported)
	scene_saved.connect(_on_scene_saved)
	_queue_refresh()


func _flush_layout() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root != null and root.scene_file_path == "res://main.tscn" and root.has_method("flush_layout"):
		root.call("flush_layout")


# вызывается редактором при «Сохранить всё», закрытии проекта и т.п.
func _save_external_data() -> void:
	_flush_layout()


func _exit_tree() -> void:
	_flush_layout()
	remove_tool_menu_item("Обновить модели сцены")
	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)
	var filesystem := get_editor_interface().get_resource_filesystem()
	if filesystem.resources_reimported.is_connected(_on_reimported):
		filesystem.resources_reimported.disconnect(_on_reimported)


func _on_scene_saved(path: String) -> void:
	# Ctrl+S и запуск F5 сохраняют сцену — заодно гарантированно пишем раскладку в res://bunker_layout.json
	if path != "res://main.tscn":
		return
	var root := get_editor_interface().get_edited_scene_root()
	if root != null and root.has_method("flush_layout"):
		root.call("flush_layout")


func _on_reimported(paths: PackedStringArray) -> void:
	for path in paths:
		if path.begins_with("res://models/"):
			_queue_refresh()
			return


func _queue_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_pending = false
	var root := get_editor_interface().get_edited_scene_root()
	if root == null or root.scene_file_path != "res://main.tscn":
		return
	if root.has_method("refresh_editor_models"):
		# Узлы будут пересозданы: не оставляем инспектору старые ссылки.
		get_editor_interface().get_selection().clear()
		root.call("refresh_editor_models")
