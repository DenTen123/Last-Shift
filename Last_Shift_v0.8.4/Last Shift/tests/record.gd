extends Node3D
## Съёмка демо-ролика: скрипт управляет игрой, каждый кадр рендера сохраняется
## в record_frames/*.jpg (720p), затем ffmpeg склеивает их в mp4.
## Запуск: godot --path . res://tests/record.tscn
## Файлы пользователя в user:// бэкапятся перед съёмкой и возвращаются после.

const FPS := 30
const OUT_DIR := "C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/record_frames"

var world: Node3D
var ui: CanvasLayer
var frame_i := 0
var audio_rec: AudioEffectRecord


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for f in DirAccess.get_files_at(OUT_DIR):
		if f.begins_with("f") and f.ends_with(".jpg"):
			DirAccess.remove_absolute(OUT_DIR + "/" + f)
	_backup_user_files()
	var master := AudioServer.get_bus_index("Master")
	audio_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(master, audio_rec)
	audio_rec.set_recording_active(true)
	var main: Node3D = load("res://main.tscn").instantiate()
	add_child(main)
	world = main
	ui = world.ui
	_run()


func _backup_user_files() -> void:
	var dir := OS.get_user_data_dir()
	for n in ["save.json", "record.json", "graphics.json"]:
		if FileAccess.file_exists(dir + "/" + n):
			DirAccess.copy_absolute(dir + "/" + n, dir + "/_demo_backup_" + n)


func _restore_user_files() -> void:
	var dir := OS.get_user_data_dir()
	for n in ["save.json", "record.json", "graphics.json"]:
		if FileAccess.file_exists(dir + "/_demo_backup_" + n):
			DirAccess.copy_absolute(dir + "/_demo_backup_" + n, dir + "/" + n)
			DirAccess.remove_absolute(dir + "/_demo_backup_" + n)
		elif FileAccess.file_exists(dir + "/" + n):
			DirAccess.remove_absolute(dir + "/" + n)


func capture() -> void:
	Game.paused = false  # окно могло потерять фокус — для съёмки пауза не нужна
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(OUT_DIR + "/f%05d.jpg" % frame_i, 0.92)
	frame_i += 1


func wait_frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		capture()


# Плавная прокрутка времени: per_frame минут за кадр; попутно держим бункер живым
func wait_min(mins: int, per_frame := 4) -> void:
	var left := maxi(mins, 0)
	while left > 0:
		var step := mini(per_frame, left)
		Game.advance(step)
		left -= step
		_housekeep()
		await RenderingServer.frame_post_draw
		capture()


func wait_until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		_housekeep()
		await RenderingServer.frame_post_draw
		capture()


# держим бункер живым во время прокрутки: генератор заправлен, игрок не падает без сна
func _housekeep() -> void:
	Game.paused = false
	if Game.gen_broken:
		Game.gen_broken = false
		Game.gen_broken_at = 0
	Game.gen_fuel = 100.0
	Game.player_awake = mini(Game.player_awake, 480)
	Game.player_sleep_until = Game.t + 720
	Game.player_food = maxi(Game.player_food, 45)
	Game.res.food = maxi(Game.res.food, 8)
	Game.gate_event = {}  # ночные незнакомцы приходят только в своём кадре сценария


func walk_to(pos: Vector3, frames: int) -> void:
	world.player_ctl.path = world.nav.path(world.player.position, pos)
	await wait_frames(frames)
	world.player_ctl.path = []


# детерминированный гость: не зависит от игровых часов (стук в 9:00 мог быть пропущен)
func force_visitor() -> void:
	if Game.visitor == {}:
		var idx: int = Game.npc_pool.pick_random()
		Game.npc_pool.erase(idx)
		var d: Dictionary = Game.NPC_DEFS[idx]
		Game.visitor = {"name": d.name, "prof": d.prof, "status": "ok", "look": Game.NPC_OK_LOOKS[0], "def": idx}
		Game.visitor_until = Game.t + Game.VISITOR_WAIT
		Game.npc_arrived.emit(String(d.name), "ok")
		Game.changed.emit()


func _run() -> void:
	# ---------- главное меню с плашкой рекорда (демо-значения) ----------
	Game.record = {"day": 12, "time": "14:30", "workers": 6}
	await wait_frames(200)
	ui._menu_settings()
	await wait_frames(150)
	ui._back_to_menu()
	await wait_frames(130)

	# ---------- новая игра: напарник показывает бункер ----------
	ui._menu_new()
	await wait_frames(100)
	await walk_to(Vector3(-6.0, WorldConfig.H, 6.0), 90)
	await wait_frames(120)  # реплика у грядки
	await walk_to(Vector3(-1.5, WorldConfig.H, -3.2), 90)
	await wait_frames(130)  # реплика у метеостанции
	await walk_to(Vector3(-2.0, WorldConfig.H, 0.0), 70)
	await wait_until(func(): return not world.staff.tour_active, 420)

	# ---------- генератор: топливо и дозаправка ----------
	await walk_to(Vector3(-10.4, WorldConfig.H, 6.2), 100)
	Game.gen_fuel = 46.0  # для наглядности: бак наполовину пуст
	ui.open_modal("gen")
	await wait_frames(90)
	Game.gen_refuel()
	await wait_frames(60)
	ui._close()

	# ---------- поломка: течь ----------
	Game.incidents.append({"id": 1, "kind": "leak", "spot": 1, "born": Game.t, "loss": 0, "loss_txt": ""})
	Game.changed.emit()
	await wait_frames(50)
	await walk_to(Vector3(-4.0, WorldConfig.H, -4.8), 100)
	ui.open_modal("inc:1")
	await wait_frames(70)
	Game.res.rubber = 5
	Game.res.plastic = 5
	Game.fix_incident(1)
	await wait_frames(60)
	ui._close()

	# ---------- гость у ворот (детерминированно) ----------
	await wait_min(120)
	force_visitor()
	await wait_frames(70)
	await walk_to(Vector3(-13.0, WorldConfig.H, -2.75), 90)
	world.gates.look_door()
	await wait_frames(170)  # кинематика: взгляд в смотровое окно, бар с историей
	Game.npc_accept()
	await wait_frames(160)  # ворота открываются, гость входит

	# ---------- разговор и просьба ----------
	ui.open_modal("talk:1")
	await wait_frames(90)
	Game.workers[1].req = {"res": "wire", "n": 1}
	Game.res.wire = 3
	Game.changed.emit()
	await wait_frames(80)
	Game.fulfill_request(1)
	await wait_frames(70)
	ui._close()

	# ---------- третий сотрудник ----------
	Game.beds = 3
	await wait_min(90)
	force_visitor()
	await wait_frames(60)
	Game.npc_accept()
	await wait_frames(130)

	# ---------- карта вылазок ----------
	Game.sites["gas"] = true
	Game.sites["garage"] = true
	await walk_to(Vector3(3.99, WorldConfig.H, -5.8), 90)
	ui.open_modal("map")
	await wait_frames(110)
	ui._close()

	# ---------- экспедиция: галочки и отправка троих ----------
	ui.open_modal("exp")
	await wait_frames(60)
	for i in 3:
		ui._toggle_w(i)
		await wait_frames(25)
	ui.pick_site = "gas"
	await wait_frames(40)
	for w in Game.workers:
		w.sick = false
		w.hp = 100
		w.st = 100
	ui._send()
	await wait_frames(90)  # сотрудники уходят через люк
	ui._close()
	await wait_min(185)    # прокрутка 3 часов — возвращение с добычей
	await wait_frames(110) # вход обратно с лутом

	# ---------- кухня и рецепты ----------
	await walk_to(Vector3(10.2, WorldConfig.H, -2.9), 90)
	Game.res.potato = 5
	Game.res.food = maxi(Game.res.food, 9)
	ui.open_modal("kitchen")
	await wait_frames(70)
	Game.cook("stew")
	await wait_frames(80)
	ui._close()

	# ---------- ночь: происшествие у ворот ----------
	await wait_min((int(Game.t / 1440) * 1440 + 1380) - Game.t + 1440)
	var guard := 0
	while Game.gate_event.is_empty() and guard < 80:
		Game._maybe_gate_event()
		guard += 1
	await wait_frames(70)  # незнакомец подходит к воротам
	await walk_to(Vector3(-13.0, WorldConfig.H, -2.75), 90)
	world.gates.look_door()
	await wait_frames(150)
	if not Game.gate_event.is_empty():
		Game.res[String(Game.gate_event.res)] = maxi(int(Game.res[String(Game.gate_event.res)]), int(Game.gate_event.n)) + 1
		Game.gate_give()
	await wait_frames(90)  # итог в журнале, камера возвращается

	# ---------- верстак и машина ----------
	Game.car = {"engine": true, "wheels": true, "battery": true, "tank": true}
	Game.changed.emit()
	await walk_to(Vector3(0.25, WorldConfig.H, 4.8), 80)
	ui.open_modal("bench")
	await wait_frames(70)
	ui._set_bench_cat("car")
	await wait_frames(90)  # все детали «УСТАНОВЛЕНО»
	ui._close()

	# ---------- победа: выезд ----------
	ui._drive()
	await wait_frames(240)  # посадка команды, ворота поднимаются
	await wait_until(func(): return Game.end_state == "win", 500)
	await wait_frames(140)  # экран «Выезд»

	# ---------- меню с настоящим рекордом ----------
	Game.end_state = ""
	ui.open_modal("menu")
	await wait_frames(220)

	# ---------- финал ----------
	audio_rec.set_recording_active(false)
	var wav := audio_rec.get_recording()
	if wav != null:
		wav.save_wav(OUT_DIR + "/audio.wav")
	_restore_user_files()
	get_tree().quit()
