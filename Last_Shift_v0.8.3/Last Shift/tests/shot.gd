extends Node3D
## Разовый визуальный осмотр: окно с игрой, две позы камеры, скриншоты в last_shift_v082_work/shots/.
## Запуск: godot --path . res://tests/shot.tscn

func _ready() -> void:
	# скриншот главного меню: плашка рекорда только в памяти — файл рекорда пользователя не трогаем
	Game.record = {"day": 12, "time": "14:30", "workers": 6}
	var main: Node3D = load("res://main.tscn").instantiate()
	add_child(main)
	var world: Node3D = main
	await get_tree().create_timer(1.5).timeout
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/menu.png")
	world.ui._menu_settings()  # как настоящая кнопка «Настройки»: обложка остаётся фоном
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/modal_settings.png")
	world.ui._back_to_menu()
	# закрываем меню и продолжаем прежний сценарий осмотров
	Game.t = 600  # 10:00 дня 1: тур напарника не стартует, гости и торговец не мешают
	Game.menu_skip = true
	Game.record = {}
	world.ui._close()  # главное меню закрывается только вручную — для скриншотов делаем это кодом
	await get_tree().create_timer(1.5).timeout
	Game.built.medbed = true  # видимая кушетка: проверяем надпись относительно модели
	Game.built.garden = true  # окно грядки с кнопками посадки (иконки культур)
	Game.sites["garage"] = true  # демо-место «Автосервис» из data/game_data.json показано открытым
	Game.changed.emit()
	await get_tree().create_timer(11.0).timeout  # панель подсказок затухает за ~11 с
	var cam_ctl = world.camera
	# поза 1: медблок — кушетка (модель, надпись, габарит)
	cam_ctl.dist = 6.5
	cam_ctl.rig.position = Vector3(11.0, WorldConfig.FLOOR, 15.2)
	cam_ctl.rig.rotation.y = 0.0
	cam_ctl.pitch.rotation_degrees.x = -32.0
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/med.png")
	# поза 2: метеостанция и карта на стене за ней
	cam_ctl.dist = 6.0
	cam_ctl.rig.position = Vector3(2.0, WorldConfig.FLOOR, -2.4)
	cam_ctl.rig.rotation.y = 0.0
	cam_ctl.pitch.rotation_degrees.x = -28.0
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/map.png")
	# поза 3: бункер погружается в темноту (генератор сломан 2/3 срока)
	Game.gen_broken = true
	Game.gen_broken_at = Game.t - 1200
	Game.changed.emit()
	cam_ctl.dist = 22.0
	cam_ctl.rig.position = Vector3(0.0, WorldConfig.FLOOR, 2.0)
	cam_ctl.rig.rotation.y = 0.0
	cam_ctl.pitch.rotation_degrees.x = -45.0
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/dark.png")
	Game.gen_broken = false
	Game.gen_broken_at = 0
	Game.changed.emit()
	# поза 4: дверные стойки в проёме коридора — стены не должны входить в колонны
	cam_ctl.dist = 8.0
	cam_ctl.rig.position = Vector3(2.0, WorldConfig.FLOOR, 6.5)
	cam_ctl.rig.rotation.y = 0.0
	cam_ctl.pitch.rotation_degrees.x = -36.0
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/doors.png")
	# поза 5: угловой стык двух стен (x=-2) сверху — угловая колонна перекрывает оба торца
	cam_ctl.dist = 8.0
	cam_ctl.rig.position = Vector3(-2.0, WorldConfig.FLOOR, 1.5)
	cam_ctl.rig.rotation.y = 0.0
	cam_ctl.pitch.rotation_degrees.x = -62.0
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/corner.png")
	# окна интерфейса: иконки грядки и карты, галочки экспедиции
	world.ui.open_modal("garden")
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/modal_garden.png")
	world.ui.open_modal("map")
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/modal_map.png")
	world.ui.open_modal("exp")
	await _settle()
	get_viewport().get_texture().get_image().save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/shots/modal_exp.png")
	world.ui._close()
	get_tree().quit()


# поза применяется в processing текущего кадра — ждём два отрисованных кадра, чтобы не снять старую камеру
func _settle() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
