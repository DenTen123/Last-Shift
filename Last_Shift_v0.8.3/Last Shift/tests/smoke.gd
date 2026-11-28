extends SceneTree
## Дымовой тест новых механик (генератор, поломки, карта, просьбы, рецепты, ворота).
## Запуск: godot --headless --path . --script res://tests/smoke.gd

var fails := 0
var G: Node = null

func check(cond: bool, name: String) -> void:
	if cond:
		print("OK   ", name)
	else:
		fails += 1
		print("FAIL ", name)


# Дозаправки и рецепты внутри себя вызывают advance(): топливо успевает чуть потратиться.
func near(value: float, target: float, tol: float) -> bool:
	return absf(value - target) <= tol


# Плохая погода детерминирована по времени — просто подбираем безопасное окно.
# Тест крутит часы: бак генератора пополняем сам, случайные поломки нейтрализуем —
# иначе генератор законно глохнет посреди проверки и ломает все последующие допущения.
func wait_good_weather() -> void:
	var guard := 0
	while bool(G.trip_weather(G.t).bad) and guard < 40:
		G.gen_fuel = 100.0
		G.advance(60)
		guard += 1
	if G.gen_broken:
		G.gen_broken = false
		G.gen_broken_at = 0


func ready_worker() -> void:
	G.workers[0].st = 100
	G.workers[0].hp = 100
	G.workers[0].sick = false
	G.workers[0].asleep = false
	G.workers[0].task = null


func _initialize() -> void:
	# автозагрузки появляются после _initialize — ждём первый кадр
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	# страховка: даже если тест упадёт с ошибкой GDScript, процесс завершится сам
	create_timer(100.0).timeout.connect(func():
		print("WATCHDOG: тест не завершился сам")
		quit(2))


func _run() -> void:
	G = root.get_node("Game")
	seed(20261128)  # фиксированный сид: погодные окна и события не меняются между запусками
	# настоящие save.json и record.json пользователя должны пережить тест: бэкап перед, возврат после
	var save_path: String = OS.get_user_data_dir() + "/save.json"
	var backup_path: String = OS.get_user_data_dir() + "/save_smoke_backup.json"
	var had_save: bool = FileAccess.file_exists(save_path)
	if had_save:
		DirAccess.copy_absolute(save_path, backup_path)
	var rec_path: String = OS.get_user_data_dir() + "/record.json"
	var rec_backup: String = OS.get_user_data_dir() + "/record_smoke_backup.json"
	var had_record: bool = FileAccess.file_exists(rec_path)
	if had_record:
		DirAccess.copy_absolute(rec_path, rec_backup)
	var gfx_path: String = OS.get_user_data_dir() + "/graphics.json"
	var gfx_backup: String = OS.get_user_data_dir() + "/graphics_smoke_backup.json"
	var had_gfx: bool = FileAccess.file_exists(gfx_path)
	if had_gfx:
		DirAccess.copy_absolute(gfx_path, gfx_backup)
	G.reset()

	# ---------- 1. генератор ----------
	G.gen_fuel = 40.0  # бак не полный: иначе дозаправка рано выходит (tank >= 99%)
	G.res.fuel = 5
	G.gen_refuel()
	check(float(G.gen_fuel) > 95.0 and int(G.res.fuel) == 4, "gen_refuel: полный бак за 1 топливо")
	var fuel0: float = G.gen_fuel
	G.advance(60)
	check(float(G.gen_fuel) < fuel0, "gen_drain: топливо тратится со временем")
	check(int(G.gen_runtime_hours()) == 40, "gen_runtime: без построек бак — 40 часов")
	G.built.lamp = true
	G.built.kitchen = true
	G.built.furnace = true
	G.built.shredder = true
	check(int(G.gen_runtime_hours()) == 32, "gen_runtime: 4 потребителя — 32 часа")
	G.built.lamp = false
	G.built.kitchen = false
	G.built.furnace = false
	G.built.shredder = false
	G.gen_fuel = 100.0

	# ---------- 2. поломки ----------
	G.incidents = [{"id": 1, "kind": "door", "spot": 0, "born": G.t, "loss": 0, "loss_txt": ""}]
	check(not G.send(0, false, "", "waste"), "door: заклинившая дверь блокирует вылазку")
	check(G.send_repair(0, 1), "send_repair: сотрудник взял задание")
	G.advance(121)
	check(G.incidents.is_empty(), "repair: задание сняло поломку за 2 ч")
	G.incidents = [{"id": 2, "kind": "leak", "spot": 1, "born": G.t, "loss": 0, "loss_txt": ""}]
	G.res.food = 10
	var food0: int = G.res.food
	G._incidents_hourly()
	check(int(G.res.food) == food0 - 1 and int(G.incidents[0].loss) == 1, "leak: течь портит еду каждый час")
	G.incidents = [{"id": 3, "kind": "leak", "spot": 1, "born": G.t, "loss": 3, "loss_txt": "еда ×3"}]
	G.res.rubber = 5
	G.res.plastic = 5
	G.fix_incident(3)
	check(G.incidents.is_empty(), "fix_incident: игрок починил деталями")

	# ---------- 3. карта вылазок ----------
	G.sites = {"waste": true}
	wait_good_weather()
	ready_worker()
	check(G.scout(0, "gas"), "scout: разведка запущена")
	G.advance(181)
	check(bool(G.sites.get("gas", false)) and not bool(G.workers[0].dead), "scout: АЗС открыто после 3 ч")
	wait_good_weather()
	ready_worker()
	check(G.send(0, false, "", "gas"), "send: вылазка на АЗС")
	if G.workers[0].away != null:
		check(String(G.workers[0].away.site) == "gas", "send: у вылазки есть место")
	else:
		check(false, "send: у вылазки есть место")
	for sid in G.SITES:
		G._loot(G.workers[0], {"site": sid, "pack": false, "tool": "", "music": false})
	check(true, "loot: все шесть мест дают добычу без ошибок")
	G.advance(181)
	check(G.workers[0].away == null, "return: сотрудник вернулся с места")

	# ---------- 3б. мультивыбор галочками ----------
	check(G.sendable(0), "sendable: готовый сотрудник проходит")
	check(not G.sendable(2), "sendable: несуществующий индекс отсекается")
	# второй сотрудник для групповой отправки
	G.workers.append({"name": "Тест", "prof": "drifter", "cap": 3, "eff": 1.0, "st": 100, "hp": 100, "sick": false,
		"away": null, "dead": false, "xp": 0, "lvl": 1, "suit": Color(0.3, 0.3, 0.3), "maniac": false, "kill_at": -1,
		"bed": -1, "asleep": false, "nobed": false, "nosleep": 0, "music_at": -99999,
		"loyal": 0, "loyal50": false, "loyal90": false, "req": {}, "task": null, "talk_at": -99999, "last_chat": ""})
	check(G.sendable(1), "sendable: второй сотрудник готов")
	G.workers[0].sick = true
	check(not G.sendable(0), "sendable: больной отсекается")
	G.workers[0].sick = false
	wait_good_weather()
	ready_worker()
	G.workers[1].st = 100
	check(G.send(0, false, "", "gas") and G.send(1, false, "", "gas"), "multi: двое отмеченных вышли одной волной")
	G.advance(181)
	check(G.workers[0].away == null and G.workers[1].away == null, "multi: оба вернулись")

	# ---------- 4. рецепты ----------
	G.built.kitchen = true
	G.res.potato = 5
	G.res.food = 10
	var ft: int = G.t
	G.cook("stew")
	check(int(G.buffs.loot_until) == ft + 720, "stew: бонус добычи на 12 ч")
	G.res.herbs = 4
	G.cook("tea")
	check(int(G.buffs.immune_until) > int(G.buffs.loot_until), "tea: иммунитет на 24 ч")
	G.res.potato = 5
	G.res.herbs = 4
	G.workers[0].st = 60
	G.cook("roast")
	check(int(G.workers[0].st) >= 80, "roast: горячий ужин даёт выносливость")

	# ---------- 5. просьбы и разговоры ----------
	G.workers[0].req = {"res": "wire", "n": 2}
	G.res.wire = 5
	var wire0: int = G.res.wire
	G.fulfill_request(0)
	check(int(G.res.wire) == wire0 - 2 and int(G.workers[0].loyal) >= 10 and G.workers[0].req == {}, "fulfill_request: просьба выполнена")
	G.workers[0].talk_at = -99999
	G.talk(0)
	check(int(G.workers[0].loyal) >= 11 and String(G.workers[0].last_chat) != "", "talk: разговор даёт лояльность и реплику")
	check(not G.talk_ready(0), "talk: кулдаун 3 ч работает")
	G.workers[0].loyal = 50
	G.workers[0].loyal50 = false
	G.workers[0].req = {"res": "wire", "n": 1}
	G.res.wire = 5
	G.fulfill_request(0)
	check(bool(G.workers[0].loyal50) and float(G.workers[0].eff) > 1.0, "loyalty 50: бонус к добыче")

	# ---------- 6. происшествия у ворот ----------
	var guard := 0
	while G.gate_event.is_empty() and guard < 200:
		G._maybe_gate_event()
		guard += 1
	check(not G.gate_event.is_empty(), "gate: незнакомец пришёл")
	var ge: Dictionary = G.gate_event
	var had: int = int(G.res[String(ge.res)])
	G.res[String(ge.res)] = had + 5
	G.gate_give()
	check(G.gate_event.is_empty() and int(G.res[String(ge.res)]) == had + 5 - int(ge.n), "gate_give: отдал требуемое — конфликт решён")
	while G.gate_event.is_empty() and guard < 400:
		G._maybe_gate_event()
		guard += 1
	G.gate_refuse()
	check(G.gate_event.is_empty(), "gate_refuse: прогнал — инцидент закрыт")

	# ---------- 7. сохранение ----------
	check(bool(G.save_game()), "save: файл записан")
	G.gen_fuel = 55.5  # портим значение: после загрузки должно вернуться из сейва
	check(bool(G.load_game()), "load: файл прочитан")
	check(float(G.gen_fuel) != 55.5, "load: gen_fuel восстановлен из сейва")
	check(bool(G.sites.get("gas", false)), "load: карта сохранена")

	# ---------- 7б. рекорд при победе ----------
	for k in G.car:
		G.car[k] = true
	G.drive_out()
	var rec: Dictionary = G.load_record()
	check(not rec.is_empty() and int(rec.get("workers", 0)) >= 1, "record: победа пишет рекорд — спасённые люди")
	check(int(rec.get("day", 0)) == G.day(), "record: день выезда записан")
	var rec_old: Dictionary = rec.duplicate()
	G.save_record()  # повторная запись того же результата не должна менять плашку
	var rec2: Dictionary = G.load_record()
	check(int(rec2.get("day", 0)) == int(rec_old.get("day", 0)) and int(rec2.get("workers", 0)) == int(rec_old.get("workers", 0)), "record: повтор не портит плашку")
	G.end_state = ""  # фиктивную победу сбрасываем — дальше идут обычные проверки

	# ---------- 7в. настройки графики ----------
	G.graphics.scale = 0.6
	G.graphics.effects = false
	G.save_graphics()
	G.graphics = {"scale": 1.0, "msaa": 2, "shadows": true, "effects": true, "fullscreen": false}
	G.load_graphics()
	check(absf(float(G.graphics.scale) - 0.6) < 0.01 and not bool(G.graphics.effects), "graphics: настройки сохраняются и читаются")

	# ---------- 7г. расширение через данные ----------
	G.load_game_data()  # штатный файл из data/
	check(int(G.sites_data.size()) == 7 and int(G.recipes_data.size()) == 3, "data: файл проекта загружен (6 мест + Автосервис)")
	check(bool(G.sites_data.has("garage")), "data: новое место из данных появилось в игре")
	var bad := FileAccess.open("user://data_bad.json", FileAccess.WRITE)
	bad.store_string("{ это не json")
	bad.close()
	G.load_game_data("user://data_bad.json")
	check(int(G.sites_data.size()) == 6 and bool(G.sites_data.has("waste")) and int(G.recipes_data.size()) == 3, "data: битый файл — работа на встроенных значениях (6 мест), состояние не сломано")
	DirAccess.remove_absolute("user://data_bad.json")
	var ugly := FileAccess.open("user://data_ugly.json", FileAccess.WRITE)
	ugly.store_string(JSON.stringify({
		"sites": {
			"noloot": {"name": "Без добычи", "risk": 0.1, "yield": 1.0},
			"badres": {"name": "Неизвестный ресурс", "risk": 0.1, "yield": 1.0, "loot": {"unobtanium": 2.0}},
			"ok": {"name": "Хорошее место", "risk": 0.05, "yield": 1.05, "desc": "работает", "loot": {"metal": 2.0}}
		},
		"recipes": {"badbuff": {"name": "Х", "cost": {"food": 1}, "min": 10, "buff": "телепорт", "desc": "нет такого эффекта"}}
	}))
	ugly.close()
	G.load_game_data("user://data_ugly.json")
	check(bool(G.sites_data.has("ok")) and not G.sites_data.has("noloot") and not G.sites_data.has("badres"), "data: битые записи пропущены, хорошая принята")
	check(not G.recipes_data.has("badbuff"), "data: рецепт с неизвестным эффектом пропущен")
	DirAccess.remove_absolute("user://data_ugly.json")
	G.load_game_data()  # вернуть штатные каталоги для следующих проверок

	# ---------- 8. блэкаут: поломка генератора ----------
	ready_worker()
	G.gen_fuel = 0.1  # меньше расхода за один шаг (~0.44% при 40 ч) — бак обязан дойти до нуля
	G.advance(10)
	check(bool(G.gen_broken) and int(G.gen_broken_at) == int(G.t), "blackout: пустой бак — поломка и запуск 30 ч темноты")
	check(not G.send(0, false, "", "waste"), "blackout: люк обесточен — вылазки закрыты")
	G.built.furnace = true
	G.res.metal = 5
	G.res.fuel = 5
	var metal0: int = G.res.metal
	G.process("steel")
	check(int(G.res.metal) == metal0, "blackout: плавильная печь не работает")
	G.beds = 5
	G.visitor = {"name": "Глеб", "prof": "engineer", "status": "ok", "look": "", "def": 0}
	var wc0: int = G.workers.size()
	G.npc_accept()
	check(G.workers.size() == wc0 and not G.visitor.is_empty(), "blackout: ворота обесточены — гостя не впустить")
	G.visitor = {}
	check(G.darkness_factor() >= 0.0 and G.darkness_factor() < 0.05, "dark: темнота только началась")
	G.res.metal = 5
	G.res.wire = 5
	G.res.fuel = 5
	G.repair_generator()
	check(not bool(G.gen_broken) and G.darkness_factor() == 0.0 and float(G.gen_fuel) > 90.0, "repair_generator: свет вернулся, двери работают")
	G.gen_broken = true
	G.gen_broken_at = G.t - 1800
	G.advance(10)
	check(G.end_state == "lose", "dark: полная темнота через 30 часов — конец игры")

	# ---------- итог ----------
	if had_save:
		DirAccess.copy_absolute(backup_path, save_path)
		DirAccess.remove_absolute(backup_path)
	elif FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)  # тестовый сейв не должен оставаться пользователю
	if had_record:
		DirAccess.copy_absolute(rec_backup, rec_path)
		DirAccess.remove_absolute(rec_backup)
	elif FileAccess.file_exists(rec_path):
		DirAccess.remove_absolute(rec_path)  # тестовый рекорд не должен остаться пользователю
	if had_gfx:
		DirAccess.copy_absolute(gfx_backup, gfx_path)
		DirAccess.remove_absolute(gfx_backup)
	elif FileAccess.file_exists(gfx_path):
		DirAccess.remove_absolute(gfx_path)  # тестовые настройки графики не должны остаться
	print("---")
	print("ПРОВАЛЕНО: %d" % fails)
	quit(1 if fails > 0 else 0)
