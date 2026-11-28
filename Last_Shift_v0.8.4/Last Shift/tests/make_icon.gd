extends Node3D
## Разовая генерация иконки: рендер модели «карта_на_стене» на тёмном фоне карточек.
## Запуск: godot --path . res://tests/make_icon.tscn

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17231c")  # фон карточек в интерфейсе
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.9)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -24, 0)
	sun.light_energy = 1.15
	add_child(sun)
	var board: Node3D = load("res://models/карта_на_стене.glb").instantiate()
	add_child(board)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0.0, 0.12, 2.7)  # модель смотрит в +Z — снимаем анфас
	add_child(cam)
	cam.make_current()
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var side := mini(img.get_width(), img.get_height())
	var crop := Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side)
	var icon := img.get_region(crop)
	icon.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	icon.save_png("C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/extracted/Last_Shift_v0.8.2/Last Shift/scripts/icons/map.png")
	get_tree().quit()
