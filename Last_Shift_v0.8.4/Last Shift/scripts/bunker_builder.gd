@tool
class_name BunkerBuilder
extends RefCounted
## Построение бункера, поверхности, мебели и интерактивных объектов.

const M := preload("res://scripts/models.gd")
var host: BunkerWorld
var props: Dictionary = {}
var gen_body: Node3D = null
var hot_bodies := {}  # быстрые клавиши: id → тело объекта
var potato_crates: Array = []
var furnace_smoke: GPUParticles3D = null
# геометрия стен в glb «бункер»; здесь — только координаты для препятствий
const WALLS := [
	[-14, 16, 9, 16, 0.8],
	[11, 16, 14, 16, 0.8],
	[-14, 8, -9.5, 8, 0.9],
	[-6.5, 8, 2.8, 8, 0.9],
	[5.8, 8, 8.5, 8, 0.9],
	[11.5, 8, 14, 8, 0.9],
	[-2, -8, -2, -1.5, 1.6],
	[-2, 1.5, -2, 16, 1.6],
	[-2, -1.5, 0.5, -1.5, 1.6],
	[-2, 1.5, 0.5, 1.5, 1.6],
	[3.5, -1.5, 8.5, -1.5, 1.6],
	[3.5, 1.5, 8.5, 1.5, 1.6],
	[11.5, -1.5, 14, -1.5, 1.6],
	[11.5, 1.5, 14, 1.5, 1.6],
	[6, -8, 6, -1.5, 1.6],
	[6, 1.5, 6, 3.2, 1.6],
	[6, 5.8, 6, 16, 1.6],
	[8.8, 16, 8.8, 18.6, 2.5],
	[11.2, 16, 11.2, 18.6, 2.5],
]

func _init(h: BunkerWorld) -> void:
	host = h


func editor_look() -> void:
	host.gates.car_wheels.visible = true
	host.gates.car_engine.visible = true
	host.gates.car_battery.visible = true
	host.gates.car_tank.visible = true
	host.gates.car_cabin.visible = true
	for st in host.station_ctl.stations:
		st.parts.model.visible = true
		st.parts.ghost.visible = false
	for k in props:
		props[k].visible = true
	var g: Dictionary = host.station_ctl.stations[0].parts
	g.lamp.visible = true
	g.irrig.visible = true
	g.plants.visible = true
	g.fruit.visible = true
	for n in host.interactables:
		if n.has_meta("label"):
			(n.get_meta("label") as Label3D).modulate = Color(1, 1, 1, 1)


func pickable(title: String, size: Vector3, pos: Vector3, col: Color, act: String, hint: String, stand: Vector3, parent: Node = null, movable := false, ry := 0.0) -> Node3D:
	var body := Node3D.new()
	body.position = pos
	body.rotation.y = ry
	if col.a > 0.0:
		M.box(body, size, Vector3.ZERO, col)
	body.set_meta("act", act)
	body.set_meta("hint", hint)
	body.set_meta("stand", stand)
	body.set_meta("size", size)
	if title != "":
		var l := Label3D.new()
		l.text = title
		l.font_size = 40
		l.pixel_size = 0.01
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.outline_size = 10
		l.modulate = Color(1, 1, 1, 1)
		l.position = Vector3(0, size.y / 2.0 + 0.7, 0)
		body.add_child(l)
		body.set_meta("label", l)
	(parent if parent != null else host).add_child(body)
	host.interactables.append(body)
	if movable:
		host.layout.item(body, title, Vector3(size.x, size.z, 0) if body.global_position.y < -1.0 else Vector3.ZERO, true)
	elif body.global_position.y < -1.0:
		host.nav.obstacles.append(Rect2(body.global_position.x - size.x / 2.0, body.global_position.z - size.z / 2.0, size.x, size.z))
	return body


func build_bunker() -> void:
	# архитектура — glb из отдельных узлов: стены и землю можно двигать в редакторе
	for pc in M.bunker(host):
		var nm: String = pc.name
		var obs := Vector3.ZERO
		if nm.begins_with("Стена"):
			var wi := int(nm.substr(5)) - 1
			if wi >= 0 and wi < WALLS.size():
				var w: Array = WALLS[wi]
				obs = Vector3(maxf(absf(w[2] - w[0]), 0.3) + 0.08, maxf(absf(w[3] - w[1]), 0.3) + 0.08, 0)
		host.layout.item(pc.node, nm, obs, false)
	# лампы без видимых светильников: только свет
	for p in [Vector2(-8, 0), Vector2(2, -5), Vector2(10, -5), Vector2(2, 5), Vector2(10, 5), Vector2(4, 0), Vector2(-8, 12), Vector2(2, 12), Vector2(10, 12)]:
		var o := OmniLight3D.new()
		o.position = Vector3(p.x, WorldConfig.FLOOR + 3.0, p.y)
		o.omni_range = 9.0
		o.light_energy = 1.3
		o.light_color = Color(1.0, 0.86, 0.65)
		host.add_child(o)
		host.weather.omnis.append(o)
	_decor()


func _decor() -> void:
	# стойки чуть шире стены и сдвинуты в проём — торец прячется внутри колонны,
	# угловая колонна закрывает стык двух стен
	for p in WorldConfig.POSTS_Z8:
		var post: Node3D = M.door_post(host, Vector3(p[0] + p[1], WorldConfig.FLOOR, 8.0))
		post.scale = Vector3(p[2], 1.0, p[2])
	for z in [-1.5, 1.5]:
		for p in WorldConfig.POSTS_CORRIDOR:
			var postc: Node3D = M.door_post(host, Vector3(p[0] + p[1], WorldConfig.FLOOR, z))
			postc.scale = Vector3(p[2], 1.0, p[2])
	for p in WorldConfig.POSTS_X6:
		var postx: Node3D = M.door_post(host, Vector3(6, WorldConfig.FLOOR, p[0] + p[1]))
		postx.scale = Vector3(p[2], 1.0, p[2])
	var li := 0
	for x in [-11.0, -5.0, 2.0, 10.0]:
		li += 1
		host.layout.item(M.wall_lamp(host, Vector3(x, WorldConfig.FLOOR + 2.45, -7.8)), "wall_lamp_%d" % li)
	host.layout.item(M.warn_sign(host, Vector3(-13.0, WorldConfig.FLOOR + 1.6, -7.85)), "warn_sign")
	for i in 3:
		host.layout.item(M.locker(host, Vector3(-10.0 + i * 0.9, WorldConfig.FLOOR, -7.45), Color(0.35, 0.45, 0.55)), "locker_%d" % (i + 1), Vector3(0.8, 0.6, 0))
	host.layout.item(M.plant(host, Vector3(13.2, WorldConfig.FLOOR, 2.4)), "plant_pot", Vector3(0.5, 0.5, 0))
	# доска-карта: окно вылазок и разведки — на стене за метеостанцией (как лампа и знак на этой же стене)
	var map_body := pickable("Карта вылазок", Vector3(2.0, 1.4, 0.25), Vector3(2.0, WorldConfig.FLOOR + 1.5, -7.85), Color(0, 0, 0, 0), "map",
		"Карта вылазок: места на поверхности, риск и награда, разведка новых дорог.", Vector3(2.0, WorldConfig.H, -5.8), null, true, 0.0)
	M.mapboard(map_body, Vector3.ZERO, 0.0)
	host.layout.item(M.tv(host, Vector3(12.5, WorldConfig.FLOOR + 1.7, 7.78), PI), "tv")
	host.layout.item(M.pegboard(host, Vector3(-13.88, WorldConfig.FLOOR + 1.5, 3.0)), "pegboard")
	host.layout.item(M.rug(host, Vector3(-8.0, 0, 2.0), Vector3(3.0, 0.03, 2.0), Color(0.24, 0.28, 0.3)), "rug_garage")
	host.layout.item(M.cooler(host, Vector3(13.3, WorldConfig.FLOOR, -2.3)), "cooler", Vector3(0.7, 0.7, 0))
	# стол в правой нижней комнате (медблок)
	host.layout.item(M.rug(host, Vector3(8.6, 0, 11.0), Vector3(3.4, 0.03, 2.2), Color(0.42, 0.22, 0.2)), "rug_med")
	# новый столик — всего 0,7×0,7 м: коллизия по его размеру (раньше невидимая стена 3,7×1,3 м перекрывала вход)
	host.layout.item(M.table_set(host, Vector3(8.6, WorldConfig.FLOOR, 11.0)), "table")
	host.layout.set_obstacle("table", Vector2(0.8, 0.8), Vector2(0.065, 0.08))


func build_surface() -> void:
	# крышка люка на шарнире у x=-26 (рампа и петли — в glb «бункер»)
	host.gates.hatch = Node3D.new()
	host.gates.hatch.position = Vector3(-26, 0, -2.75)
	host.add_child(host.gates.hatch)
	var cover := pickable("Люк", Vector3(12, 0.4, 6.2), Vector3(6, 0.2, 0), Color(0.35, 0.37, 0.36), "exp", "Люк над лестницей: накрывает вход для людей. Нажми, чтобы снарядить вылазку.", Vector3(-13, WorldConfig.H, 0), host.gates.hatch)
	M.hatch_cover(cover)
	host.weather.anemo = M.anemometer(host, Vector3(-31, 0, 6.5))
	host.weather.build_precip()
	_build_upgrade_props()


func _build_upgrade_props() -> void:
	# появляются при постройке улучшений бункера
	props["filter"] = M.air_filter(host, Vector3(-6.8, WorldConfig.FLOOR + 1.6, -7.7))
	host.layout.item(props["filter"], "air_filter")
	var insul := Node3D.new()
	host.add_child(insul)
	M.insul_panel(insul, Vector3(-24.5, 0.18, 3.4))
	M.insul_panel(insul, Vector3(-24.5, 0.18, -3.4))
	props["insul"] = insul
	host.layout.item(insul, "insul")
	props["coffee"] = M.coffee_machine(host, WorldConfig.COFFEE_POS)
	host.layout.item(props["coffee"], "coffee")
	for k in props:
		props[k].visible = false


func build_objects() -> void:
	var none := Color(0, 0, 0, 0)
	# гараж
	host.gates.car = Node3D.new()
	host.gates.car.position = Vector3(-8, WorldConfig.FLOOR, 2)
	host.add_child(host.gates.car)
	var parts := M.build_car(host.gates.car)
	host.gates.car_wheels = parts.wheels
	host.gates.car_engine = parts.engine
	host.gates.car_battery = parts.battery
	host.gates.car_tank = parts.tank
	host.gates.car_cabin = parts.cabin
	pickable("Автомобиль", Vector3(4.4, 2.0, 2.2), Vector3(0, 1.0, 0), none, "car", "Автомобиль: детали и выезд.", Vector3(-5.0, WorldConfig.H, 2.0), host.gates.car, true)
	var exp_console := pickable("Пульт люка", Vector3(1.2, 1.2, 0.8), Vector3(-11, WorldConfig.FLOOR + 0.6, -5), none, "exp", "Пульт люка: снарядить вылазку.", Vector3(-11, WorldConfig.H, -3.4), null, true)
	M.console(exp_console)
	hot_bodies["exp"] = exp_console
	gen_body = pickable("Генератор", Vector3(2.4, 1.8, 1.9), Vector3(-12, WorldConfig.FLOOR + 0.7, 6.2), none, "gen", "Генератор: снабжает бункер светом.", Vector3(-10.4, WorldConfig.H, 6.2), null, true)
	M.generator(gen_body, Vector3(0, -0.7, 0))
	# ворота со смотровым окном — у лестницы для людей (северная полоса въезда).
	# Повёрнуты поперёк лестницы (полотно вдоль Z), поэтому распахиваются внутрь бункера.
	host.gates.door_body = pickable("Ворота", Vector3(2.4, 2.6, 1.6), Vector3(-14.157, WorldConfig.FLOOR, -2.75), none, "door", "Ворота со смотровым окном.", Vector3(-13, WorldConfig.H, -2.75), null, true, -PI / 2.0)
	host.gates.gates_leaf = M.gates(host.gates.door_body)
	# большие ворота для машины — верх въездной дороги, открываются с готовой машиной
	host.gates.auto_gates_body = pickable("Ворота для машины", Vector3(6.2, 3.7, 1.2), Vector3(-26.3, 0.0, 2.75), none, "autogate", "Ворота для машины.", Vector3(-13, WorldConfig.H, 2.75), null, true, PI / 2.0)
	host.gates.auto_leaf = M.auto_gates(host.gates.auto_gates_body)
	host.layout.item(M.barrel(host, Vector3(-13, WorldConfig.FLOOR, -7.2), Color(0.2, 0.45, 0.7)), "barrel_a", Vector3(0.6, 0.6, 0))
	host.layout.item(M.barrel(host, Vector3(-12.2, WorldConfig.FLOOR, -7.2), Color(0.7, 0.2, 0.2)), "barrel_b", Vector3(0.6, 0.6, 0))
	host.layout.item(M.crate(host, Vector3(-4, WorldConfig.FLOOR, -7), 1.2), "crate_a", Vector3(1.2, 1.2, 0))
	host.layout.item(M.crate(host, Vector3(-4, WorldConfig.FLOOR + 1.2, -7), 0.8), "crate_a_top")
	# метеостанция
	M.weather_desk(pickable("Метеостанция", Vector3(4, 1.0, 1.2), Vector3(2, WorldConfig.FLOOR + 0.5, -7), none, "fc", "Метеостанция: прогноз погоды и безопасные окна.", Vector3(2, WorldConfig.H, -5.2), null, true))
	# склад
	var shelf_body := pickable("Стеллаж", Vector3(5, 2.4, 1.0), Vector3(11, WorldConfig.FLOOR + 1.2, -7), none, "inv", "Стеллаж: материалы и снаряжение.", Vector3(11, WorldConfig.H, -5.2), null, true)
	M.shelf(shelf_body)
	hot_bodies["inv"] = shelf_body
	host.layout.item(M.crate(host, Vector3(7.2, WorldConfig.FLOOR, -3.5), 1.0), "crate_b", Vector3(1.0, 1.0, 0))
	host.layout.item(M.crate(host, Vector3(13, WorldConfig.FLOOR, -3.2), 1.2), "crate_c", Vector3(1.2, 1.2, 0))
	host.layout.item(M.barrel(host, Vector3(7.0, WorldConfig.FLOOR, -6.5), Color(0.8, 0.6, 0.15)), "barrel_c", Vector3(0.6, 0.6, 0))
	# ящики картошки появляются по мере запасов
	var pc1 := M.crate(host, Vector3(12.55, WorldConfig.FLOOR, -1.95), 0.8)
	pc1.visible = false
	var pc2 := M.crate(host, Vector3(12.55, WorldConfig.FLOOR + 0.8, -1.95), 0.62)
	pc2.visible = false
	potato_crates = [pc1, pc2]
	# мастерская
	var bench_body := pickable("Верстак", Vector3(4.5, 1.0, 1.4), Vector3(0.25, WorldConfig.FLOOR + 0.5, 6.8), none, "bench", "Верстак: снаряжение, детали машины, постройки и улучшения.", Vector3(0.25, WorldConfig.H, 4.8), null, true)
	M.workbench(bench_body)
	hot_bodies["bench"] = bench_body
	# отдых
	var bed_body := pickable("Койки", Vector3(1.8, 0.8, 7.4), Vector3(WorldConfig.BED_X0, WorldConfig.FLOOR + 0.4, WorldConfig.BED_ZC), none, "bed", "Койки: сон на 8 часов, построить кровати (до 10).", Vector3(WorldConfig.BED_X0 - 1.7, WorldConfig.H, WorldConfig.BED_ZC), null, true)
	var bunk_root := M.bunks(bed_body)
	host.rest.bunk_north = bunk_root.find_child("койка_1", true, false) as Node3D
	host.rest.bunk_south = bunk_root.find_child("койка_2", true, false) as Node3D
	if host.rest.bunk_north != null:
		host.rest.bunk_north.position.z += WorldConfig.BUNK_TOP_SHIFT  # северная койка — вплотную к стене, южная на месте
	hot_bodies["bed"] = bed_body
	M.radio(pickable("Радио", Vector3(1.0, 1.0, 0.8), Vector3(7.0, WorldConfig.FLOOR + 0.5, 7.4), none, "radio", "Радио: музыка, вызов торговца, сигнал выживших.", Vector3(7.8, WorldConfig.H, 6.2), null, true))


func build_actors() -> void:
	host.player = M.character(Color(0.9, 0.7, 0.12), Color(0.95, 0.95, 0.95))
	host.player.position = Vector3(-5, WorldConfig.H, -2)
	host.add_child(host.player)


func earth_color() -> Color:
	var it := host.layout.item_by_name("Земля 5")
	if not it.is_empty():
		var ms: Array = []
		host.layout._meshes(it.node, ms)
		for m in ms:
			var mt := (m as MeshInstance3D).get_active_material(0)
			if mt is StandardMaterial3D:
				return (mt as StandardMaterial3D).albedo_color
	return Color(0.2, 0.17, 0.13)


# Видимость построек и подсказки у интерактивных предметов по состоянию игры
func sync_scene_props() -> void:
	for k in props:
		props[k].visible = Game.built[k]
	if gen_body != null and is_instance_valid(gen_body):
		var lb: Label3D = gen_body.get_meta("label")
		lb.text = "Генератор — сломан!" if Game.gen_broken else "Генератор · топливо %d%%" % int(Game.gen_fuel)
		if Game.gen_broken:
			var left := maxi(0, Game.DARK_LIMIT - (Game.t - Game.gen_broken_at))
			gen_body.set_meta("hint", "Генератор сломан: до полной темноты %d ч. Почините (металл, провод, топливо)." % ((left + 59) / 60))
		else:
			gen_body.set_meta("hint", "Генератор: топливо %d%%, хватит на ~%d ч. E — дозаправка." % [int(Game.gen_fuel), maxi(Game.gen_hours(), 1)])
	if host.gates.door_body != null and is_instance_valid(host.gates.door_body):
		host.gates.door_body.set_meta("hint", "У ворот кто-то есть! Посмотрите в окно (E)." if Game.visitor != {} or not Game.gate_event.is_empty() else "Ворота со смотровым окном. Тихо.")
	if host.gates.auto_gates_body != null and is_instance_valid(host.gates.auto_gates_body):
		var ac: int = Game.car.values().count(true)
		host.gates.auto_gates_body.set_meta("hint", "Машина готова! Открой ворота (E) и уезжай — победа!" if Game.car_done() else "Ворота для машины: откроются, когда машина будет готова (детали %d из 4 на верстаке)." % ac)
	if potato_crates.size() >= 2:
		potato_crates[0].visible = Game.res.potato >= 6
		potato_crates[1].visible = Game.res.potato >= 14
	if furnace_smoke != null:
		furnace_smoke.emitting = Game.built.furnace and not Game.gen_broken  # без света печь не работает — дыма нет
