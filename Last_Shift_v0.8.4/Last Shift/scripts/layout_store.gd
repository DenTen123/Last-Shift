@tool
class_name LayoutStore
extends RefCounted
## Чтение и запись файла раскладки.
## Источник правды при разработке — res://bunker_layout.json (редактор Godot и игра, запущенная
## из редактора, пишут именно в него). Собранная игра пишет в user://. При загрузке побеждает
## файл с более свежей отметкой "stamp", поэтому устаревшая копия в user:// больше не перекрывает
## свежие правки из редактора.

var host: BunkerWorld

func _init(h: BunkerWorld) -> void:
	host = h


static func _from_editor() -> bool:
	return Engine.is_editor_hint() or OS.has_feature("editor")


func save_path() -> String:
	return WorldConfig.LAYOUT_DEFAULT_PATH if _from_editor() else WorldConfig.LAYOUT_PATH


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	# принимаем только актуальный формат (v: 3)
	if data is Dictionary and int(data.get("v", 0)) == 3:
		return data
	return {}


func _stamp(path: String, data: Dictionary) -> float:
	if data.has("stamp"):
		return float(data.stamp)
	# старые файлы без отметки: личный user:// считаем по времени изменения, вшитый res:// — самым старым
	if path.begins_with("user://"):
		return float(FileAccess.get_modified_time(path))
	return 0.0


func layout_load() -> Dictionary:
	var res_data := _read(WorldConfig.LAYOUT_DEFAULT_PATH)
	var user_data := _read(WorldConfig.LAYOUT_PATH)
	# в редакторе источник правды — res://bunker_layout.json: устаревшая копия в user:// его не перекрывает
	if _from_editor() and not res_data.is_empty():
		return res_data
	if user_data.is_empty():
		return res_data
	if res_data.is_empty():
		return user_data
	if _stamp(WorldConfig.LAYOUT_PATH, user_data) > _stamp(WorldConfig.LAYOUT_DEFAULT_PATH, res_data):
		return user_data
	return res_data


func layout_save(data: Dictionary) -> void:
	data["stamp"] = Time.get_unix_time_from_system()
	var text := JSON.stringify(data)
	var path := save_path()
	print("Раскладка сохраняется: ", path, " (предметов: ", (data.get("items", {}) as Dictionary).size(), ")")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null and path != WorldConfig.LAYOUT_PATH:
		# res:// недоступен для записи (например, собранная игра) — пишем в user://
		path = WorldConfig.LAYOUT_PATH
		f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	else:
		push_error("Не удалось сохранить раскладку: %s" % error_string(FileAccess.get_open_error()))
		if host.ui != null:
			host.ui.toast("Не удалось сохранить раскладку. Проверьте доступ к папке данных игры.")
