@tool
extends Node3D
## 3D-мир: только бункер в разрезе на тёмном фоне, рампа с люком, гости у люка.
## Управление: WASD — ходить (Shift — бег), стрелки — камера, колесо — зум,
## Q/R или СКМ — поворот камеры, ПКМ — идти, ЛКМ/E — действие, C — камера к герою.
## F — редактор локации: двигать мебель, декор и станции.

const FLOOR := -3.0
const H := -2.1  # высота центра персонажа над полом бункера
const UI := preload("res://scripts/ui.gd")
const M := preload("res://scripts/models.gd")
const LAYOUT_PATH := "user://bunker_layout.json"
# русские имена предметов для дока «Сцена» (ключ = внутренний ключ раскладки)
const ITEM_RU := {
	"generator": "Генератор",
	"barrel_a": "Бочка 1", "barrel_b": "Бочка 2", "barrel_c": "Бочка 3",
	"crate_a": "Ящик 1", "crate_a_top": "Ящик 1 (верх)", "crate_b": "Ящик 2", "crate_c": "Ящик 3",
	"locker_1": "Шкафчик 1", "locker_2": "Шкафчик 2", "locker_3": "Шкафчик 3",
	"plant_pot": "Растение", "warn_sign": "Знак опасности",
	"wall_lamp_1": "Лампа 1", "wall_lamp_2": "Лампа 2", "wall_lamp_3": "Лампа 3", "wall_lamp_4": "Лампа 4",
	"mapboard": "Карта на стене", "tv": "Телевизор", "pegboard": "Доска инструментов",
	"rug_garage": "Ковер 1", "cooler": "Кулер", "rug_med": "Ковер 2", "table": "Стол",
	"air_filter": "Фильтр воздуха", "insul": "Утепление люка", "coffee": "Кофемашина",
}
# места, где сотрудники стоят в покое (до 10 человек)
const IDLE_SPOTS := [
	Vector3(8.5, H, 3.5),    # комната отдыха
	Vector3(10.2, H, 2.6),   # комната отдыха
	Vector3(7.5, H, 2.2),    # комната отдыха
	Vector3(2.0, H, 3.0),    # мастерская
	Vector3(4.2, H, 5.0),    # мастерская
	Vector3(2.0, H, -4.0),   # метеостанция
	Vector3(-6.0, H, -4.0),  # метеостанция
	Vector3(-10.0, H, 1.0),  # гараж
	Vector3(-8.0, H, 9.5),   # грядки
	Vector3(10.2, H, 14.0),  # медблок
]
const SUN_COLS := [Color(0.55, 0.65, 0.95), Color(1.0, 0.85, 0.6), Color(1.0, 0.97, 0.9), Color(1.0, 0.62, 0.38)]

var ui: CanvasLayer
var rig: Node3D
var pitch: Node3D
var cam: Camera3D
var dist := 32.0
var dist_target := 32.0
var yaw := 0.0
var pitch_deg := -55.0
var player: Node3D
var path: Array = []
var pending_body: Node3D = null
var interactables: Array = []
var stations: Array = []
var blocked_body: Node3D = null
var obstacles: Array = []
var astar: AStarGrid2D
var car: Node3D
var car_wheels: Node3D
var car_engine: Node3D
var car_battery: Node3D
var car_tank: Node3D
var car_cabin: Node3D
var hatch: Node3D
var hatch_tween: Tween
var hatch_users := 0
var sun: DirectionalLight3D
var env: Environment
var wnodes: Array = []
var anim: Array = []
var visitor_node: Node3D = null
var visitor_lbl: Label3D = null
var anemo: Node3D
var wind_now := 0.0
var omnis: Array = []
var precips: Array = []
var precip_pms: Array = []
var props: Dictionary = {}
var walked := false
var _edit_poll_acc := 0.0
var gen_body: Node3D = null
var light_base := 1.3
var door_body: Node3D = null
var auto_gates_body: Node3D = null
var auto_leaf: Node3D = null
var auto_gate_tween: Tween
var door_cinematic := false
var _saved_cam := {}
var gates_leaf: Node3D = null
var gate_tween: Tween
var hot_bodies := {}  # быстрые клавиши: id → тело объекта
var wander_cd: Array = []
var potato_crates: Array = []
var furnace_smoke: GPUParticles3D = null
var storming := false
var thunder_cd := 3.0
var _flash := 0.0
var base_bg := Color(0.05, 0.06, 0.07)
var sun_e := 1.0
# редактор локации
var editor_items: Array = []  # {"node", "name", "obs": Vector3(sx, sz, 0), "pickable", "orig", "orig_ry"}
var edit_mode := false
var edit_selected := {}
var edit_drag := false
var edit_drag_off := Vector3.ZERO
var edit_prev_paused := false
var sel_box: MeshInstance3D


func _ready() -> void:
	# сцена строится кодом: и в редакторе (@tool), и в игре
	for c in get_children():
		c.free()  # немедленно: чтобы пересозданные узлы получили чистые имена без суффиксов
	_build_env()
	_build_bunker()
	_build_surface()
	_build_objects()
	_build_stations()
	_build_actors()
	if Engine.is_editor_hint():
		_layout_apply()  # показать в редакторе раскладку, сохранённую ранее
		_editor_look()
		_editor_own_items()  # предметы появляются в доке «Сцена» — можно двигать гизмо
		return
	_register_obstacles()
	_layout_apply()
	_build_astar()
	_build_camera()
	ui = UI.new()
	add_child(ui)
	ui.drive_requested.connect(_start_drive)
	Game.changed.connect(_on_changed)
	Game.worker_left.connect(_on_left)
	Game.worker_back.connect(_on_back)
	Game.npc_arrived.connect(_on_npc_arrived)
	Game.npc_done.connect(_on_npc_done)
	Game.station_used.connect(_on_station_used)
	Game.reset_layout.connect(_edit_reset)  # кнопка «Сбросить раскладку» в журнале
	if Game.visitor != {}:
		_on_npc_arrived(String(Game.visitor.name), String(Game.visitor.status))  # гость из сохранения
	_on_changed()


func _notification(what: int) -> void:
	# авто-пауза, когда окно игры теряет фокус
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not Engine.is_editor_hint():
		if Game.end_state == "" and not Game.cinematic and not Game.paused and ui != null:
			Game.paused = true
			ui.toast("Окно не в фокусе — пауза (Space — продолжить)")


func _editor_look() -> void:
	env.background_color = Color(0.14, 0.16, 0.18)
	env.fog_light_color = Color(0.14, 0.16, 0.18)
	env.fog_density = 0.0
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	env.ambient_light_energy = 0.6
	car_wheels.visible = true
	car_engine.visible = true
	car_battery.visible = true
	car_tank.visible = true
	car_cabin.visible = true
	for st in stations:
		st.parts.model.visible = true
		st.parts.ghost.visible = false
	for k in props:
		props[k].visible = true
	var g: Dictionary = stations[0].parts
	g.lamp.visible = true
	g.irrig.visible = true
	g.plants.visible = true
	g.fruit.visible = true
	for n in interactables:
		if n.has_meta("label"):
			(n.get_meta("label") as Label3D).modulate = Color(1, 1, 1, 1)


# ================= построение =================
func _box(parent: Node, size: Vector3, pos: Vector3, col: Color, emit := false) -> MeshInstance3D:
	return M.box(parent, size, pos, col, emit)


func _item(n: Node3D, item_name: String, obs := Vector3.ZERO, pickable := false) -> void:
	n.name = ITEM_RU.get(item_name, item_name)  # русское имя в доке «Сцена»
	# если тело вложено в другой узел (например, автомобиль) — двигать и считать
	# препятствие нужно по родителю, иначе коллайдер окажется не там
	var mv := n
	if pickable and n.get_parent() is Node3D and n.get_parent() != self:
		mv = n.get_parent()
	editor_items.append({"node": n, "mv": mv, "name": item_name, "obs": obs, "pickable": pickable, "orig": mv.position, "orig_ry": mv.rotation.y})


func _pickable(title: String, size: Vector3, pos: Vector3, col: Color, act: String, hint: String, stand: Vector3, parent: Node = null, movable := false) -> Node3D:
	var body := Node3D.new()
	body.position = pos
	if col.a > 0.0:
		_box(body, size, Vector3.ZERO, col)
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
	(parent if parent != null else self).add_child(body)
	interactables.append(body)
	if movable:
		_item(body, title, Vector3(size.x, size.z, 0) if body.global_position.y < -1.0 else Vector3.ZERO, true)
	elif body.global_position.y < -1.0:
		obstacles.append(Rect2(body.global_position.x - size.x / 2.0, body.global_position.z - size.z / 2.0, size.x, size.z))
	return body


func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.74)
	env.fog_enabled = true
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


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


func _build_bunker() -> void:
	# архитектура — glb из отдельных узлов: стены и землю можно двигать в редакторе
	for pc in M.bunker(self):
		var nm: String = pc.name
		var obs := Vector3.ZERO
		if nm.begins_with("Стена"):
			var wi := int(nm.substr(5)) - 1
			if wi >= 0 and wi < WALLS.size():
				var w: Array = WALLS[wi]
				obs = Vector3(maxf(absf(w[2] - w[0]), 0.3) + 0.08, maxf(absf(w[3] - w[1]), 0.3) + 0.08, 0)
		_item(pc.node, nm, obs, false)
	# лампы без видимых светильников: только свет
	for p in [Vector2(-8, 0), Vector2(2, -5), Vector2(10, -5), Vector2(2, 5), Vector2(10, 5), Vector2(4, 0), Vector2(-8, 12), Vector2(2, 12), Vector2(10, 12)]:
		var o := OmniLight3D.new()
		o.position = Vector3(p.x, FLOOR + 3.0, p.y)
		o.omni_range = 9.0
		o.light_energy = 1.3
		o.light_color = Color(1.0, 0.86, 0.65)
		add_child(o)
		omnis.append(o)
	_decor()


func _decor() -> void:
	for x in [-9.5, -6.5, 2.8, 5.8, 8.5, 11.5]:
		M.door_post(self, Vector3(x, FLOOR, 8.0))
	for z in [-1.5, 1.5]:
		for x in [-2.0, 0.5, 3.5, 8.5, 11.5]:
			M.door_post(self, Vector3(x, FLOOR, z))
	for z in [3.2, 5.8]:
		M.door_post(self, Vector3(6, FLOOR, z))
	var li := 0
	for x in [-11.0, -5.0, 2.0, 10.0]:
		li += 1
		_item(M.wall_lamp(self, Vector3(x, FLOOR + 2.45, -7.8)), "wall_lamp_%d" % li)
	_item(M.warn_sign(self, Vector3(-13.0, FLOOR + 1.6, -7.85)), "warn_sign")
	for i in 3:
		_item(M.locker(self, Vector3(-10.0 + i * 0.9, FLOOR, -7.45), Color(0.35, 0.45, 0.55)), "locker_%d" % (i + 1), Vector3(0.8, 0.6, 0))
	_item(M.plant(self, Vector3(13.2, FLOOR, 2.4)), "plant_pot", Vector3(0.5, 0.5, 0))
	_item(M.mapboard(self, Vector3(5.8, FLOOR + 1.5, -1.62), PI), "mapboard")
	_item(M.tv(self, Vector3(12.5, FLOOR + 1.7, 7.78), PI), "tv")
	_item(M.pegboard(self, Vector3(-13.88, FLOOR + 1.5, 3.0)), "pegboard")
	_item(M.rug(self, Vector3(-8.0, 0, 2.0), Vector3(3.0, 0.03, 2.0), Color(0.24, 0.28, 0.3)), "rug_garage")
	_item(M.cooler(self, Vector3(13.3, FLOOR, -2.3)), "cooler", Vector3(0.7, 0.7, 0))
	# стол в правой нижней комнате (медблок)
	_item(M.rug(self, Vector3(8.6, 0, 11.0), Vector3(3.4, 0.03, 2.2), Color(0.42, 0.22, 0.2)), "rug_med")
	_item(M.table_set(self, Vector3(8.6, FLOOR, 11.0)), "table", Vector3(3.7, 1.3, 0))


func _build_surface() -> void:
	# крышка люка на шарнире у x=-26 (рампа и петли — в glb «бункер»)
	hatch = Node3D.new()
	hatch.position = Vector3(-26, 0, -4.25)
	add_child(hatch)
	var cover := _pickable("Люк", Vector3(11.6, 0.4, 3.4), Vector3(5.8, 0.2, 0), Color(0.35, 0.37, 0.36), "exp", "Люк над лестницей: накрывает вход для людей. Нажми, чтобы снарядить вылазку.", Vector3(-13, H, 0), hatch)
	M.hatch_cover(cover)
	anemo = M.anemometer(self, Vector3(-31, 0, 6.5))
	_build_precip()
	_build_upgrade_props()


func _build_upgrade_props() -> void:
	# появляются при постройке улучшений бункера
	props["filter"] = M.air_filter(self, Vector3(-6.8, FLOOR + 1.6, -7.7))
	_item(props["filter"], "air_filter")
	var insul := Node3D.new()
	add_child(insul)
	M.insul_panel(insul, Vector3(-24.5, 0.18, 3.4))
	M.insul_panel(insul, Vector3(-24.5, 0.18, -3.4))
	props["insul"] = insul
	_item(insul, "insul")
	props["coffee"] = M.coffee_machine(self, Vector3(9.25, FLOOR + 0.92, 11.35))
	_item(props["coffee"], "coffee")
	for k in props:
		props[k].visible = false


func _build_precip() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 1.0, 10.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.gravity = Vector3(0, -30, 0)
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.55, 0.66, 0.82)
	precip_pms.append(pm)
	var pr := GPUParticles3D.new()
	pr.position = Vector3(-26, 9.0, 0)
	pr.amount = 800
	pr.lifetime = 1.1
	pr.process_material = pm
	pr.draw_pass_1 = mesh
	pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pr.visibility_aabb = AABB(Vector3(-16, -12, -14), Vector3(32, 30, 28))
	pr.emitting = false
	add_child(pr)
	precips.append(pr)


func _build_objects() -> void:
	var none := Color(0, 0, 0, 0)
	# гараж
	car = Node3D.new()
	car.position = Vector3(-8, FLOOR, 2)
	add_child(car)
	var parts := M.build_car(car)
	car_wheels = parts.wheels
	car_engine = parts.engine
	car_battery = parts.battery
	car_tank = parts.tank
	car_cabin = parts.cabin
	_pickable("Автомобиль", Vector3(4.4, 2.0, 2.2), Vector3(0, 1.0, 0), none, "car", "Автомобиль: детали и выезд.", Vector3(-5.0, H, 2.0), car, true)
	var exp_console := _pickable("Пульт люка", Vector3(1.2, 1.2, 0.8), Vector3(-11, FLOOR + 0.6, -5), none, "exp", "Пульт люка: снарядить вылазку.", Vector3(-11, H, -3.4), null, true)
	M.console(exp_console)
	hot_bodies["exp"] = exp_console
	gen_body = _pickable("Генератор", Vector3(2.4, 1.8, 1.9), Vector3(-12, FLOOR + 0.7, 6.2), none, "gen", "Генератор: снабжает бункер светом.", Vector3(-10.4, H, 6.2), null, true)
	M.generator(gen_body, Vector3(0, -0.7, 0))
	# ворота со смотровым окном — низ узкой лестницы для людей (север въезда)
	door_body = _pickable("Ворота", Vector3(2.4, 2.6, 1.6), Vector3(-14.157, FLOOR, -4.25), none, "door", "Ворота со смотровым окном.", Vector3(-13, H, -4.25), null, true)
	gates_leaf = M.gates(door_body)
	# большие ворота для машины — верх въездной дороги, открываются с готовой машиной
	auto_gates_body = _pickable("Ворота для машины", Vector3(6.2, 3.7, 1.2), Vector3(-26.3, 0.0, 1.25), none, "autogate", "Ворота для машины.", Vector3(-13, H, 1.25), null, true)
	auto_leaf = M.auto_gates(auto_gates_body)
	_item(M.barrel(self, Vector3(-13, FLOOR, -7.2), Color(0.2, 0.45, 0.7)), "barrel_a", Vector3(0.6, 0.6, 0))
	_item(M.barrel(self, Vector3(-12.2, FLOOR, -7.2), Color(0.7, 0.2, 0.2)), "barrel_b", Vector3(0.6, 0.6, 0))
	_item(M.crate(self, Vector3(-4, FLOOR, -7), 1.2), "crate_a", Vector3(1.2, 1.2, 0))
	_item(M.crate(self, Vector3(-4, FLOOR + 1.2, -7), 0.8), "crate_a_top")
	# метеостанция
	M.weather_desk(_pickable("Метеостанция", Vector3(4, 1.0, 1.2), Vector3(2, FLOOR + 0.5, -7), none, "fc", "Метеостанция: прогноз погоды и безопасные окна.", Vector3(2, H, -5.2), null, true))
	# склад
	var shelf_body := _pickable("Стеллаж", Vector3(5, 2.4, 1.0), Vector3(11, FLOOR + 1.2, -7), none, "inv", "Стеллаж: материалы и снаряжение.", Vector3(11, H, -5.2), null, true)
	M.shelf(shelf_body)
	hot_bodies["inv"] = shelf_body
	M.crate(self, Vector3(7.2, FLOOR, -3.5), 1.0)
	M.crate(self, Vector3(13, FLOOR, -3.2), 1.2)
	_item(M.barrel(self, Vector3(7.0, FLOOR, -6.5), Color(0.8, 0.6, 0.15)), "barrel_c", Vector3(0.6, 0.6, 0))
	# ящики картошки появляются по мере запасов
	var pc1 := M.crate(self, Vector3(12.55, FLOOR, -1.95), 0.8)
	pc1.visible = false
	var pc2 := M.crate(self, Vector3(12.55, FLOOR + 0.8, -1.95), 0.62)
	pc2.visible = false
	potato_crates = [pc1, pc2]
	# мастерская
	var bench_body := _pickable("Верстак", Vector3(4.5, 1.0, 1.4), Vector3(0.25, FLOOR + 0.5, 6.8), none, "bench", "Верстак: снаряжение, детали машины, постройки и улучшения.", Vector3(0.25, H, 4.8), null, true)
	M.workbench(bench_body)
	hot_bodies["bench"] = bench_body
	# отдых
	var bed_body := _pickable("Койки", Vector3(1.8, 0.8, 5.0), Vector3(12.6, FLOOR + 0.4, 5.0), none, "bed", "Койки: сон возвращает выносливость (2 часа).", Vector3(10.6, H, 5.5), null, true)
	M.bunks(bed_body)
	hot_bodies["bed"] = bed_body
	M.radio(_pickable("Радио", Vector3(1.0, 1.0, 0.8), Vector3(7.0, FLOOR + 0.5, 7.4), none, "radio", "Радио: полчаса музыки, все дома бодрее.", Vector3(7.8, H, 6.2), null, true))


const STATIONS := [
	{"id": "garden", "title": "Грядка", "empty": "Пусто: нужна грядка", "pos": Vector3(-8, -2.6, 12.5), "size": Vector3(6.0, 0.8, 1.6), "stand": Vector3(-8, -2.1, 10.6), "act": "garden", "hint": "Грядка: посадить и собрать картошку."},
	{"id": "kitchen", "title": "Кухня", "empty": "Пусто: нужна кухня", "pos": Vector3(10.2, -2.1, -4.6), "size": Vector3(2.4, 1.4, 1.6), "stand": Vector3(10.2, -2.1, -2.9), "act": "kitchen", "hint": "Кухня: картошка — в еду или в бензин."},
	{"id": "furnace", "title": "Плавильная печь", "empty": "Пусто: нужна печь", "pos": Vector3(0.5, -2.1, 12.5), "size": Vector3(2.2, 1.8, 2.0), "stand": Vector3(0.5, -2.1, 10.4), "act": "furnace", "hint": "Плавильная печь: сталь и топливные брикеты."},
	{"id": "shredder", "title": "Измельчитель", "empty": "Пусто: нужен измельчитель", "pos": Vector3(3.8, -2.3, 13.0), "size": Vector3(2.0, 1.4, 1.6), "stand": Vector3(3.8, -2.1, 11.0), "act": "shredder", "hint": "Измельчитель: платы и пластик."},
	{"id": "medbed", "title": "Кушетка", "empty": "Пусто: нужна кушетка", "pos": Vector3(12.4, -2.55, 12.8), "size": Vector3(1.8, 0.9, 3.0), "stand": Vector3(10.4, -2.1, 12.8), "act": "medbed", "hint": "Больничная кушетка: лечение людей."},
	{"id": "medcab", "title": "Аптечный шкаф", "empty": "Пусто: нужен шкаф", "pos": Vector3(8.2, -2.0, 15.4), "size": Vector3(2.2, 2.0, 0.8), "stand": Vector3(8.2, -2.1, 13.8), "act": "medcab", "hint": "Аптечный шкаф: делает аптечки."},
]


func _build_stations() -> void:
	var none := Color(0, 0, 0, 0)
	for d in STATIONS:
		var body := _pickable(d.title, d.size, d.pos, none, d.act, d.hint, d.stand, null, true)
		var parts := M.station(body, d.id, d.size)
		stations.append({"body": body, "id": d.id, "d": d, "parts": parts})
		hot_bodies[d.id] = body
	# дым из трубы печи — идёт, когда печь построена
	furnace_smoke = GPUParticles3D.new()
	furnace_smoke.position = Vector3(1.1, -1.0, 12.8)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.gravity = Vector3(0, 0.9, 0)
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color = Color(0.6, 0.6, 0.64)
	furnace_smoke.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.5)
	mesh.material = m
	furnace_smoke.draw_pass_1 = mesh
	furnace_smoke.amount = 12
	furnace_smoke.lifetime = 2.4
	furnace_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	furnace_smoke.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	furnace_smoke.emitting = false
	add_child(furnace_smoke)


func _update_stations() -> void:
	for st in stations:
		var built: bool = Game.built[st.id]
		st.parts.model.visible = built
		st.parts.ghost.visible = not built
		var b: Node3D = st.body
		b.set_meta("act", st.d.act if built else "need:" + String(st.id))
		b.get_meta("label").text = st.d.title if built else st.d.empty
	var g: Dictionary = stations[0].parts
	g.lamp.visible = Game.built.lamp
	g.irrig.visible = Game.built.irrig
	g.plants.visible = Game.crop.state != "empty"
	g.fruit.visible = Game.crop.state == "ready"


func _build_actors() -> void:
	player = M.character(Color(0.9, 0.7, 0.12), Color(0.95, 0.95, 0.95))
	player.position = Vector3(-5, H, -2)
	add_child(player)


func _build_camera() -> void:
	rig = Node3D.new()
	rig.position = Vector3(0, FLOOR, 4)
	add_child(rig)
	pitch = Node3D.new()
	pitch.rotation_degrees.x = pitch_deg
	rig.add_child(pitch)
	cam = Camera3D.new()
	cam.position.z = dist
	cam.fov = 50.0
	cam.far = 300.0
	pitch.add_child(cam)
	cam.make_current()


# ================= состояние =================
func _on_changed() -> void:
	car_wheels.visible = Game.car.wheels
	car_engine.visible = Game.car.engine
	car_battery.visible = Game.car.battery
	car_tank.visible = Game.car.tank
	car_cabin.visible = Game.car_done()
	for k in props:
		props[k].visible = Game.built[k]
	if gen_body != null and is_instance_valid(gen_body):
		var lb: Label3D = gen_body.get_meta("label")
		lb.text = "Генератор — сломан!" if Game.gen_broken else "Генератор"
		gen_body.set_meta("hint", "Генератор сломан: починить за 2 металла." if Game.gen_broken else "Генератор: снабжает бункер светом.")
	if door_body != null and is_instance_valid(door_body):
		door_body.set_meta("hint", "Кто-то стучит в ворота! Посмотрите в окно (E)." if Game.visitor != {} else "Ворота со смотровым окном. Тихо.")
	if auto_gates_body != null and is_instance_valid(auto_gates_body):
		var ac: int = Game.car.values().count(true)
		auto_gates_body.set_meta("hint", "Машина готова! Открой ворота (E) и уезжай — победа!" if Game.car_done() else "Ворота для машины: откроются, когда машина будет готова (детали %d из 4 на верстаке)." % ac)
	if potato_crates.size() >= 2:
		potato_crates[0].visible = Game.res.potato >= 6
		potato_crates[1].visible = Game.res.potato >= 14
	if furnace_smoke != null:
		furnace_smoke.emitting = Game.built.furnace
	_sync_workers()
	_update_stations()
	_apply_weather()


func _sync_workers() -> void:
	while wnodes.size() < Game.workers.size():
		var i := wnodes.size()
		var w: Dictionary = Game.workers[i]
		var n := M.character(w.suit, Color(0.95, 0.8, 0.2))
		n.position = IDLE_SPOTS[i]
		add_child(n)
		wnodes.append(n)
	while anim.size() < Game.workers.size():
		anim.append(false)
	while wander_cd.size() < Game.workers.size():
		wander_cd.append(randf_range(8.0, 40.0))
	for i in wnodes.size():
		if not anim[i]:
			var w: Dictionary = Game.workers[i]
			wnodes[i].visible = (not w.dead) and w.away == null
			if wnodes[i].visible:
				wnodes[i].position = IDLE_SPOTS[i]


func _apply_weather() -> void:
	var w: Dictionary = Game.cur_weather()
	var p := Game.phase()
	var cl := float(w.cloud)
	wind_now = float(w.wind)
	var light: float = [0.12, 0.7, 1.1, 0.45][p] * (1.0 - cl / 220.0)
	# фон остаётся тёмным: снаружи видна только площадка люка
	env.background_color = Color(0.03, 0.035, 0.045).lerp(Color(0.11, 0.13, 0.16), clampf(light, 0.0, 1.0))
	env.fog_light_color = env.background_color
	base_bg = env.background_color
	env.fog_density = 0.003 + wind_now / 26.0 * 0.004 + (0.004 if w.bad else 0.0)
	sun.light_energy = maxf(light, 0.06)
	sun_e = sun.light_energy
	sun.light_color = SUN_COLS[p]
	env.ambient_light_energy = 0.3 + 0.3 * light
	var night := 1.0 - clampf(light * 1.3, 0.0, 1.0)
	light_base = 1.1 + night * 0.6
	for o in omnis:
		o.light_energy = (light_base * 0.35) if Game.gen_broken else light_base
	storming = w.bad
	# осадки над площадкой люка: дождь или снег
	var snowy: bool = w.temp <= 0
	var ratio := clampf((w.cloud - 40) / 60.0, 0.0, 1.0)
	if w.bad:
		ratio = minf(ratio + 0.25, 1.0)
	for pm in precip_pms:
		if snowy:
			pm.gravity = Vector3(0, -2.4, 0)
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.4
			pm.scale_min = 0.9
			pm.scale_max = 1.8
			pm.spread = 15.0
			pm.color = Color(0.95, 0.96, 1.0)
		else:
			pm.gravity = Vector3(0, -30, 0)
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.scale_min = 0.5
			pm.scale_max = 1.0
			pm.spread = 6.0
			pm.color = Color(0.55, 0.66, 0.82)
		pm.direction = Vector3(wind_now / 26.0 * 0.6, -1.0, 0.12).normalized()
	for pr in precips:
		pr.emitting = w.cloud >= 45
		pr.lifetime = 3.2 if snowy else 1.1
		pr.amount_ratio = ratio


# ================= гости =================
var _center_cache := Vector3(1e9, 0.0, 0.0)


func _bunker_center() -> Vector3:
	# центр жилых комнат — от него считаем, какая сторона ворот наружная
	if _center_cache.x > 1e8:
		var s := Vector3.ZERO
		for p in IDLE_SPOTS:
			s += p
		_center_cache = s / float(IDLE_SPOTS.size())
	return _center_cache


func _outward() -> Vector3:
	# наружное направление ворот: от центра бункера к воротам, по доминирующей оси.
	# работает при любом переносе/повороте ворот в редакторе
	var gb: Vector3 = (door_body as Node3D).global_position
	var c := _bunker_center()
	var d := Vector3(gb.x - c.x, 0.0, gb.z - c.z)
	if absf(d.x) >= absf(d.z):
		return Vector3(signf(d.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(d.z))


func _stair_spawn_y(p: Vector3) -> float:
	# высота ступеней у западного въезда: гость/рабочий стоит НА ступени, а не в воздухе
	if p.z <= -6.0 or p.z >= -2.4 or p.x <= -26.0 or p.x >= -12.0:
		return H
	var k := clampi(int((p.x + 26.0) / 2.0), 0, 5)
	return -0.5 * float(k + 1) + 0.9


func _on_npc_arrived(npc_name: String, status: String) -> void:
	Snd.play("knock")
	if visitor_node != null:
		visitor_node.queue_free()
	var d: Dictionary = Game.NPC_DEFS[Game.visitor.def]
	var n := M.character(d.suit, Color(0.95, 0.8, 0.2))
	var gb: Vector3 = (door_body as Node3D).global_position
	var ow := _outward()
	# окно смещено по локальной оси X полотна — гость встаёт ровно напротив него
	var lx := Vector3.ZERO
	if gates_leaf != null and is_instance_valid(gates_leaf):
		lx = ((gates_leaf as Node3D).global_transform.basis.x as Vector3).normalized() * 0.5
	# гость стоит СНАРУЖИ ворот напротив смотрового окна, лицом к бункеру
	var spawn := Vector3(gb.x, H, gb.z) + ow * 3.2
	spawn.y = _stair_spawn_y(spawn)
	n.position = spawn + lx
	n.rotation.y = atan2(ow.x, ow.z)
	add_child(n)
	var l := Label3D.new()
	l.text = npc_name
	l.font_size = 36
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 10
	l.modulate = Color(1, 1, 1, 1)
	l.position = Vector3(0, 1.55, 0)
	n.add_child(l)
	visitor_lbl = l
	visitor_node = n
	# приметы гостя — тоже 3D-модели
	if status == "maniac":
		M.prop(n, "нож")
	if status == "sick":
		M.prop(n, "насморк")
	if ui != null:
		ui.toast("Стук в ворота! Подойдите к воротам и посмотрите в окно (E).")


func _on_npc_done(accepted: bool) -> void:
	var n := visitor_node
	visitor_node = null
	if ui != null:
		ui.hide_npc_bar()
	_labels_visible(true)
	if accepted and n != null:
		_gate_move(true)
		wnodes.append(n)
		anim.append(true)
		var idx := wnodes.size() - 1
		# путь внутрь строим от текущих ворот (где бы их ни поставил редактор)
		var gb: Vector3 = (door_body as Node3D).global_position
		var ow := _outward()
		var under: Vector3 = Vector3(gb.x, H, gb.z)
		var inside: Vector3 = under - ow * 1.5
		var lxi := Vector3.ZERO
		if gates_leaf != null and is_instance_valid(gates_leaf):
			lxi = ((gates_leaf as Node3D).global_transform.basis.x as Vector3).normalized() * 0.5
		var p0 := under + ow * 3.2 + lxi
		p0.y = _stair_spawn_y(p0)
		var pts: Array = [p0, under, inside]
		pts.append_array(_path(inside, IDLE_SPOTS[idx]))
		var seq := create_tween()
		seq.tween_interval(1.4)
		seq.tween_callback(func():
			_walk_tween(n, pts, 6.5).finished.connect(_npc_in_done.bind(idx)))
	elif n != null:
		var gbr: Vector3 = (door_body as Node3D).global_position
		var owr := _outward()
		_walk_tween(n, [Vector3(gbr.x, H, gbr.z) + owr * 6.0], 7.0).finished.connect(n.queue_free)
	if door_cinematic:
		_restore_cam()
		door_cinematic = false
		Game.cinematic = false


func _npc_in_done(i: int) -> void:
	anim[i] = false
	_gate_move(false)


func _wander_done(i: int) -> void:
	anim[i] = false


func _on_station_used(id: String) -> void:
	# клуб пара/дыма над станцией, где что-то переработали
	for st in stations:
		if st.id != id:
			continue
		var col := Color(0.75, 0.75, 0.78)
		if id == "furnace":
			col = Color(0.9, 0.55, 0.25)
		elif id == "kitchen":
			col = Color(0.88, 0.88, 0.82)
		elif id == "medcab":
			col = Color(0.85, 0.92, 0.95)
		elif id == "garden":
			col = Color(0.45, 0.75, 0.4)
		var top: Vector3 = (st.body as Node3D).global_position + Vector3(0, (st.d.size as Vector3).y * 0.5 + 0.5, 0)
		_puff(top, col)
		return


func _puff(pos: Vector3, col: Color) -> void:
	for i in 5:
		var m := _box(self, Vector3(0.16, 0.16, 0.16), pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.1), randf_range(-0.25, 0.25)), col, true)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position:y", m.position.y + randf_range(1.0, 1.6), 1.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3(0.1, 0.1, 0.1), 1.1)
		tw.chain().tween_callback(m.queue_free)


# ================= люк и экспедиции =================
func _tween_hatch(deg: float) -> void:
	if hatch_tween:
		hatch_tween.kill()
	hatch_tween = create_tween()
	hatch_tween.tween_property(hatch, "rotation:z", deg_to_rad(deg), 1.5)


func _hatch_acquire() -> void:
	hatch_users += 1
	_tween_hatch(75.0)
	Snd.play("hatch")


func _hatch_release() -> void:
	hatch_users = maxi(0, hatch_users - 1)
	if hatch_users == 0:
		get_tree().create_timer(1.0).timeout.connect(_hatch_try_close)


func _hatch_try_close() -> void:
	if hatch_users == 0:
		_tween_hatch(0.0)


func _walk_tween(node: Node3D, pts: Array, speed: float) -> Tween:
	var tw := create_tween()
	var cur: Vector3 = node.position
	for p in pts:
		var a: Vector3 = cur
		var b: Vector3 = p
		var ang := atan2(-(b.x - a.x), -(b.z - a.z))
		tw.tween_property(node, "rotation:y", ang, 0.12)
		tw.tween_property(node, "position", b, maxf(a.distance_to(b) / speed, 0.05))
		cur = b
	return tw


func _on_left(i: int) -> void:
	anim[i] = true
	var n: Node3D = wnodes[i]
	n.visible = true
	n.position = IDLE_SPOTS[i]
	_hatch_acquire()
	# выход через дверь для людей и вверх по узкой лестнице (север въезда)
	var pts := _path(IDLE_SPOTS[i], Vector3(-13, H, 0))
	pts.append(Vector3(-14, H, -4.25))
	pts.append(Vector3(-26, 0.9, -4.25))
	pts.append(Vector3(-30, 0.9, -4.25))
	_walk_tween(n, pts, 7.0).finished.connect(_out_done.bind(i))


func _out_done(i: int) -> void:
	wnodes[i].visible = false
	anim[i] = false
	_hatch_release()


func _on_back(i: int, ok: bool) -> void:
	_hatch_acquire()
	if not ok:
		get_tree().create_timer(3.0).timeout.connect(_hatch_release)
		return
	anim[i] = true
	var n: Node3D = wnodes[i]
	n.visible = true
	n.position = Vector3(-30, 0.9, -4.25)
	var pts: Array = [Vector3(-26, 0.9, -4.25), Vector3(-14, H, -4.25)]
	pts.append_array(_path(Vector3(-13, H, 0), IDLE_SPOTS[i]))
	_walk_tween(n, pts, 7.0).finished.connect(_in_done.bind(i))


func _in_done(i: int) -> void:
	anim[i] = false
	_hatch_release()
	_on_changed()


# ================= финальный выезд =================
func _start_drive() -> void:
	Game.cinematic = true
	_auto_gate_move(true)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_method(_drive_step, 0.0, 1.0, 9.0)
	tw.finished.connect(_drive_end)


func _drive_step(s: float) -> void:
	var x := lerpf(-8.0, -34.0, s)
	var y := FLOOR + 3.0 * clampf((-14.0 - x) / 12.0, 0.0, 1.0)
	car.position = Vector3(x, y, lerpf(2.0, 1.25, minf(s * 4.0, 1.0)))
	car.rotation.z = -atan(3.0 / 12.0) if (x < -14.0 and x > -26.0) else 0.0
	rig.position = car.position


func _drive_end() -> void:
	Game.cinematic = false
	Game.drive_out()


# ================= движение по клику и WASD =================
const CS := 0.5
const GW := 57
const GH := 49
const PLAYER_R := 0.4
const HOT_ORDER := ["garden", "kitchen", "inv", "bench", "exp", "bed", "furnace", "shredder", "medbed", "medcab"]


func _obs(x: float, z: float, sx: float, sz: float) -> void:
	obstacles.append(Rect2(x - sx / 2.0, z - sz / 2.0, sx, sz))


func _register_obstacles() -> void:
	# стены теперь — редактируемые куски: их препятствия считаются из позиций узлов
	for z in [-1.5, 1.5]:
		for x in [-2.0, 0.5, 3.5, 8.5, 11.5]:
			_obs(x, z, 0.3, 0.3)
	for z in [3.2, 5.8]:
		_obs(6, z, 0.3, 0.3)
	for x in [-9.5, -6.5, 2.8, 5.8, 8.5, 11.5]:
		_obs(x, 8.0, 0.3, 0.3)
	_obs(8.8, 17.3, 0.5, 2.9)
	_obs(11.2, 17.3, 0.5, 2.9)
	_obs(10, 18.55, 1.7, 0.5)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi((p.x + 14.0) / CS), 0, GW - 1), clampi(roundi((p.z + 8.0) / CS), 0, GH - 1))


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(-14.0 + c.x * CS, H, -8.0 + c.y * CS)


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, GW, GH)
	astar.cell_size = Vector2(CS, CS)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for x in GW:
		for y in GH:
			var pt := _cell_pos(Vector2i(x, y))
			var solid := absf(pt.x) > 13.6 or pt.z < -7.6 or pt.z > 15.6
			# тамбур южного входа проходим
			if solid and pt.x > 8.9 and pt.x < 11.1 and pt.z > 15.6 and pt.z < 18.4:
				solid = false
			if not solid:
				for r in obstacles:
					if (r as Rect2).grow(PLAYER_R).has_point(Vector2(pt.x, pt.z)):
						solid = true
						break
			if not solid:
				for it in editor_items:
					var ob: Vector3 = it.obs
					if ob.x <= 0.0:
						continue
					var mvn: Node3D = it.mv
					if not is_instance_valid(mvn) or not (it.node as Node).visible:
						continue
					var gp := mvn.global_position
					if Rect2(gp.x - ob.x / 2.0, gp.z - ob.y / 2.0, ob.x, ob.y).grow(PLAYER_R).has_point(Vector2(pt.x, pt.z)):
						solid = true
						break
			astar.set_point_solid(Vector2i(x, y), solid)


func _build_nav() -> void:
	_register_obstacles()
	_build_astar()


func _solid_at(p: Vector3) -> bool:
	if absf(p.x) > 13.4 or p.z < -7.4:
		return true
	if p.z > 15.4:
		return not (p.x > 8.9 and p.x < 11.1 and p.z < 18.3)  # тамбур проходим
	return astar.is_point_solid(_cell(p))


func _free_cell(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 12):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= GW or n.y >= GH:
					continue
				if astar.is_point_solid(n):
					continue
				var d := float(dx * dx + dy * dy)
				if d < bd:
					bd = d
					best = n
		if best.x >= 0:
			return best
	return c


func _los(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.2) + 1
	for i in range(n + 1):
		if astar.is_point_solid(_cell(a.lerp(b, float(i) / float(n)))):
			return false
	return true


func _path(a: Vector3, b: Vector3) -> Array:
	var ia := _free_cell(_cell(a))
	var ib0 := _cell(b)
	var ib := _free_cell(ib0)
	var raw: Array = []
	for c in astar.get_id_path(ia, ib):
		raw.append(_cell_pos(c))
	if raw.is_empty():
		return []
	if ib == ib0:
		raw[raw.size() - 1] = Vector3(b.x, H, b.z)
	var out: Array = []
	var i := 0
	while i < raw.size() - 1:
		var j: int = raw.size() - 1
		while j > i + 1 and not _los(raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	if out.is_empty():
		out.append(raw[raw.size() - 1])
	return out


func _floor_hit(pos: Vector2) -> Variant:
	var from := cam.project_ray_origin(pos)
	return Plane(Vector3.UP, FLOOR).intersects_ray(from, cam.project_ray_normal(pos))


func _screen_rect(n: Node3D) -> Rect2:
	var half: Vector3 = n.get_meta("size") * 0.5
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for ax in [-1.0, 1.0]:
		for ay in [-1.0, 1.0]:
			for az in [-1.0, 1.0]:
				var wp: Vector3 = n.global_transform * Vector3(ax * half.x, ay * half.y, az * half.z)
				if cam.is_position_behind(wp):
					return Rect2()
				var sp := cam.unproject_position(wp)
				mn = Vector2(minf(mn.x, sp.x), minf(mn.y, sp.y))
				mx = Vector2(maxf(mx.x, sp.x), maxf(mx.y, sp.y))
	return Rect2(mn, mx - mn).grow(6.0)


func _pick_at(pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_area := INF
	for n in interactables:
		var r := _screen_rect(n)
		if r.has_point(pos) and r.get_area() < best_area:
			best_area = r.get_area()
			best = n
	return best


func _dist_stand(n: Node3D) -> float:
	var st: Vector3 = n.get_meta("stand")
	return Vector2(player.position.x - st.x, player.position.z - st.z).length()


func _nearest(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for n in interactables:
		var d := _dist_stand(n)
		if d < bd:
			bd = d
			best = n
	return best


func _trigger(n: Node3D) -> void:
	pending_body = null
	blocked_body = n
	path.clear()
	var act: String = n.get_meta("act")
	if act == "radio":
		Game.radio()
	elif act == "door":
		if Game.visitor == {}:
			ui.toast("За воротами тихо — никого нет.")
			Snd.play("click")
		else:
			_look_door()
	elif act == "autogate":
		_on_auto_gate()
	else:
		ui.open_modal(act)


func _look_door() -> void:
	# кинематика: камера подходит к воротам (где бы они ни стояли) и смотрит
	# в смотровое окно на гостя; подписи объектов прячем, чтобы ничего не мешало
	if door_cinematic:
		return
	door_cinematic = true
	Game.cinematic = true
	_saved_cam = {"p": rig.position, "yaw": yaw, "pitch": pitch_deg, "dist": dist}
	path.clear()
	pending_body = null
	_labels_visible(false)
	var gb: Vector3 = (door_body as Node3D).global_position
	var ow := _outward()
	# мировая позиция смотрового окна — дырка в полотне (лист на месте, ворота закрыты)
	var wp := Vector3(gb.x, H + 1.35, gb.z)
	if gates_leaf != null and is_instance_valid(gates_leaf):
		wp = (gates_leaf as Node3D).global_transform * Vector3(0.5, 1.35, 0.0)
	var look_pos := wp - ow * 0.55
	var look_yaw := atan2(-ow.x, -ow.z)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rig, "position", look_pos, 1.1).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(rig, "rotation:y", look_yaw, 1.1)
	tw.tween_property(pitch, "rotation_degrees:x", -2.0, 1.1)
	tw.tween_property(self, "dist", 1.2, 1.1)
	tw.tween_property(cam, "position:z", 1.2, 1.1)
	tw.chain().tween_interval(0.9)
	tw.chain().tween_callback(ui.show_npc_bar)


func _labels_visible(v: bool) -> void:
	for n in interactables:
		if n.has_meta("label"):
			(n.get_meta("label") as Label3D).visible = v
	if visitor_lbl != null and is_instance_valid(visitor_lbl):
		visitor_lbl.visible = v


func _gate_move(up: bool) -> void:
	if gates_leaf == null or not is_instance_valid(gates_leaf):
		return
	if gate_tween:
		gate_tween.kill()
	gate_tween = create_tween()
	var ty := (FLOOR + 2.5) if up else 0.0
	gate_tween.tween_property(gates_leaf, "position:y", ty, 1.3).set_ease(Tween.EASE_IN_OUT)
	Snd.play("hatch")


func _auto_gate_move(up: bool) -> void:
	if auto_leaf == null or not is_instance_valid(auto_leaf):
		return
	if auto_gate_tween:
		auto_gate_tween.kill()
	auto_gate_tween = create_tween()
	auto_gate_tween.tween_property(auto_leaf, "position:y", 4.0 if up else 0.0, 1.6).set_ease(Tween.EASE_IN_OUT)
	Snd.play("hatch")


func _on_auto_gate() -> void:
	if not Game.car_done():
		var cnt: int = Game.car.values().count(true)
		ui.toast("Машина не готова: детали %d из 4 (верстак). Ворота откроются, когда она будет собрана." % cnt)
		Snd.play("click")
		return
	_start_drive()


func _restore_cam() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rig, "position", _saved_cam.p, 0.9).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(rig, "rotation:y", _saved_cam.yaw, 0.9)
	tw.tween_property(pitch, "rotation_degrees:x", _saved_cam.pitch, 0.9)
	tw.tween_property(self, "dist", _saved_cam.dist, 0.9)
	tw.tween_property(cam, "position:z", _saved_cam.dist, 0.9)
	tw.chain().tween_callback(func(): pitch_deg = _saved_cam.pitch)


func _interact(n: Node3D) -> void:
	pending_body = n
	if _dist_stand(n) < 1.0:
		_trigger(n)
		return
	path = _path(player.position, n.get_meta("stand"))


# ================= редактирование в редакторе Godot =================
## Предметы выдаются в док «Сцена» (owner = корень сцены): их можно выбирать
## и двигать стандартным гизмо. Каждые 0.5 с изменения фиксируются в раскладке.
func _editor_own_items() -> void:
	var root := get_tree().edited_scene_root
	if root == null:
		return
	for it in editor_items:
		var mv: Node3D = it.mv
		if is_instance_valid(mv):
			mv.owner = root
			it.saved_p = mv.position
			it.saved_r = mv.rotation
			it.saved_hidden = not (it.node as Node).visible


func _editor_poll(delta: float) -> void:
	_edit_poll_acc += delta
	if _edit_poll_acc < 0.2:
		return
	_edit_poll_acc = 0.0
	var dirty := false
	for it in editor_items:
		var mv: Node3D = it.mv
		if not is_instance_valid(mv):
			if not bool(it.get("saved_hidden", false)):
				it.saved_hidden = true  # предмет удалили в редакторе
				dirty = true
			continue
		var hidden: bool = not (it.node as Node3D).visible
		if bool(it.get("saved_hidden", false)) != hidden:
			it.saved_hidden = hidden
			dirty = true
		var sp: Vector3 = it.get("saved_p", mv.position)
		var sr: Vector3 = it.get("saved_r", mv.rotation)
		if mv.position != sp or (mv.rotation - sr).length() > 0.0001:
			it.saved_p = mv.position
			it.saved_r = mv.rotation
			dirty = true
	if dirty:
		_layout_store()


# ================= редактор локации (в игре, F) =================
func _item_by_name(item_name: String) -> Dictionary:
	for it in editor_items:
		if it.name == item_name:
			return it
	return {}


func _meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c)
		_meshes(c, out)


func _item_aabb(n: Node3D) -> AABB:
	var meshes: Array = []
	_meshes(n, meshes)
	var comb := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			comb = ab
			first = false
		else:
			comb = comb.merge(ab)
	return comb


func _pick_item(pos: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var best := {}
	var best_d := INF
	for it in editor_items:
		var n: Node3D = it.node
		if not is_instance_valid(n) or not n.visible:
			continue
		var ab := _item_aabb(n)
		if ab.size == Vector3.ZERO:
			continue
		var hit: Variant = ab.intersects_ray(from, dir)
		if hit != null:
			var d: float = from.distance_to(hit as Vector3)
			if d < best_d:
				best_d = d
				best = it
	return best


func _layout_load() -> Dictionary:
	if FileAccess.file_exists(LAYOUT_PATH):
		var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			# принимаем только актуальный формат (v: 3) — старые файлы с неверными
			# координатами игнорируются, и предметы возвращаются на заводские места
			if data is Dictionary and int(data.get("v", 0)) == 3:
				return data
	return {}


func _layout_save(data: Dictionary) -> void:
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func _layout_store() -> void:
	var items := {}
	for it in editor_items:
		var mv: Node3D = it.mv
		if is_instance_valid(mv):
			items[it.name] = {
				"p": [mv.position.x, mv.position.y, mv.position.z],
				"r": [rad_to_deg(mv.rotation.x), rad_to_deg(mv.rotation.y), rad_to_deg(mv.rotation.z)],
				"hidden": not (it.node as Node).visible,
			}
	_layout_save({"v": 3, "items": items})


func _layout_apply() -> void:
	var data := _layout_load()
	if data.is_empty():
		return
	var items: Dictionary = data.get("items", {})
	for it in editor_items:
		if not items.has(it.name):
			continue
		var rec: Dictionary = items[it.name]
		var mv: Node3D = it.mv
		var n: Node3D = it.node
		if not is_instance_valid(mv):
			continue
		var p: Array = rec.p
		var np := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var delta := np - (mv.position as Vector3)
		var r: Array = rec.get("r", [0.0, float(rec.get("ry", 0.0)), 0.0])
		mv.position = np
		mv.rotation = Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
		n.visible = not bool(rec.get("hidden", false))
		if it.pickable and n.has_meta("stand"):
			n.set_meta("stand", (n.get_meta("stand") as Vector3) + delta)


func _enter_edit() -> void:
	edit_mode = true
	edit_prev_paused = Game.paused
	Game.paused = true
	_sel_box_init()
	ui.toast("Редактор включён: ЛКМ — выбрать и тащить · F — выход")


func _exit_edit() -> void:
	edit_mode = false
	edit_selected = {}
	edit_drag = false
	if sel_box != null:
		sel_box.visible = false
	Game.paused = edit_prev_paused
	_layout_store()
	_build_astar()


func _sel_box_init() -> void:
	if sel_box != null and is_instance_valid(sel_box):
		return
	sel_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	sel_box.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.8, 0.2, 0.3)
	m.no_depth_test = true
	sel_box.material_override = m
	sel_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sel_box.visible = false
	add_child(sel_box)


func _edit_move(it: Dictionary, delta: Vector3) -> void:
	var n: Node3D = it.node
	var mv: Node3D = it.mv
	if not is_instance_valid(mv):
		return
	mv.position += delta
	if it.pickable and n.has_meta("stand"):
		n.set_meta("stand", (n.get_meta("stand") as Vector3) + delta)


func _edit_update_box() -> void:
	if sel_box == null:
		return
	if edit_selected == {} or not is_instance_valid(edit_selected.node) or not (edit_selected.node as Node3D).visible:
		sel_box.visible = false
		return
	var n: Node3D = edit_selected.node
	var ab := _item_aabb(n)
	if ab.size == Vector3.ZERO:
		sel_box.visible = false
		return
	sel_box.visible = true
	sel_box.position = ab.get_center()
	sel_box.scale = ab.size + Vector3(0.12, 0.12, 0.12)


func _edit_reset() -> void:
	for it in editor_items:
		var mv: Node3D = it.mv
		if not is_instance_valid(mv):
			continue
		var delta: Vector3 = (it.orig as Vector3) - mv.position
		mv.position = it.orig
		mv.rotation.y = it.orig_ry
		(it.node as Node3D).visible = true
		if it.pickable and (it.node as Node3D).has_meta("stand"):
			(it.node as Node3D).set_meta("stand", ((it.node as Node3D).get_meta("stand") as Vector3) + delta)
	edit_selected = {}
	edit_drag = false
	if sel_box != null:
		sel_box.visible = false
	_layout_store()
	_build_astar()


func _edit_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_F, KEY_ESCAPE:
				_exit_edit()
			KEY_Z:
				if edit_selected != {}:
					(edit_selected.node as Node3D).rotation.y += deg_to_rad(15.0)
					_layout_store()
			KEY_X:
				if edit_selected != {}:
					(edit_selected.node as Node3D).rotation.y -= deg_to_rad(15.0)
					_layout_store()
			KEY_DELETE:
				if edit_selected != {}:
					(edit_selected.node as Node3D).visible = false
					edit_selected = {}
					if sel_box != null:
						sel_box.visible = false
					_layout_store()
					_build_astar()
			KEY_BACKSPACE:
				_edit_reset()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		dist_target = clampf(dist_target - 2.5, 9.0, 44.0)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		dist_target = clampf(dist_target + 2.5, 9.0, 44.0)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var it := _pick_item(e.position)
			edit_selected = it
			edit_drag = it != {}
			if edit_drag:
				var n: Node3D = it.node
				var h: Variant = Plane(Vector3.UP, n.position.y).intersects_ray(cam.project_ray_origin(e.position), cam.project_ray_normal(e.position))
				edit_drag_off = n.position - (h as Vector3) if h != null else Vector3.ZERO
		else:
			if edit_drag:
				_layout_store()
			edit_drag = false
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		yaw = clampf(yaw - e.relative.x * 0.006, -1.2, 1.2)
		pitch_deg = clampf(pitch_deg - e.relative.y * 0.3, -78.0, -30.0)
		rig.rotation.y = yaw
		pitch.rotation_degrees.x = pitch_deg
	elif e is InputEventMouseMotion and edit_drag and edit_selected != {} and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var n: Node3D = edit_selected.node
		var h: Variant = Plane(Vector3.UP, n.position.y).intersects_ray(cam.project_ray_origin(e.position), cam.project_ray_normal(e.position))
		if h != null:
			var target: Vector3 = (h as Vector3) + edit_drag_off
			var np := n.position
			np.x = snappedf(target.x, 0.25)
			np.z = snappedf(target.z, 0.25)
			_edit_move(edit_selected, np - n.position)


func _edit_keys(dt: float) -> void:
	# камера
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += dt * 1.2
	if Input.is_physical_key_pressed(KEY_R):
		yaw -= dt * 1.2
	yaw = clampf(yaw, -1.2, 1.2)
	rig.rotation.y = yaw
	dist = lerpf(dist, dist_target, minf(1.0, 10.0 * dt))
	cam.position.z = dist
	if edit_selected == {} or not is_instance_valid(edit_selected.node):
		return
	var n: Node3D = edit_selected.node
	var v := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		v.z -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		v.z += 1.0
	var delta := Vector3.ZERO
	if v.x != 0.0 or v.z != 0.0:
		var d3 := rig.transform.basis * Vector3(v.x, 0, v.z)
		d3.y = 0.0
		delta += d3.normalized() * 3.0 * dt
	if Input.is_physical_key_pressed(KEY_PAGEUP):
		delta.y += 1.2 * dt
	if Input.is_physical_key_pressed(KEY_PAGEDOWN):
		delta.y -= 1.2 * dt
	if delta != Vector3.ZERO:
		_edit_move(edit_selected, delta)


func _unhandled_input(e: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F and Game.end_state == "" and not Game.cinematic and not Game.modal_open:
		if edit_mode:
			_exit_edit()
		else:
			_enter_edit()
		return
	if edit_mode:
		_edit_input(e)
		return
	if Game.end_state != "" or Game.cinematic:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		# быстрые клавиши: отправить персонажа к станции и открыть её
		var idx := -1
		match e.physical_keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
			KEY_4: idx = 3
			KEY_5: idx = 4
			KEY_6: idx = 5
			KEY_7: idx = 6
			KEY_8: idx = 7
			KEY_9: idx = 8
			KEY_0: idx = 9
		if idx >= 0:
			if Game.modal_open:
				return
			var b: Node3D = hot_bodies.get(HOT_ORDER[idx], null)
			if b != null and is_instance_valid(b):
				_interact(b)
			return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_E:
		if Game.modal_open:
			return
		var nb := _nearest(1.6)
		if nb != null:
			_trigger(nb)
		return
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				dist_target = clampf(dist_target - 2.5, 9.0, 44.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				dist_target = clampf(dist_target + 2.5, 9.0, 44.0)
			MOUSE_BUTTON_RIGHT:
				if Game.modal_open:
					return
				var obj := _pick_at(e.position)
				if obj != null:
					_interact(obj)
				else:
					var h: Variant = _floor_hit(e.position)
					if h != null and absf(h.x) < 13.4 and h.z > -7.4 and (h.z < 15.4 or (h.x > 9.0 and h.x < 11.0 and h.z < 18.2)):
						pending_body = null
						path = _path(player.position, h)
			MOUSE_BUTTON_LEFT:
				if Game.modal_open:
					return
				var obj := _pick_at(e.position)
				if obj != null:
					_interact(obj)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		yaw = clampf(yaw - e.relative.x * 0.006, -1.2, 1.2)
		pitch_deg = clampf(pitch_deg - e.relative.y * 0.3, -78.0, -30.0)
		rig.rotation.y = yaw
		pitch.rotation_degrees.x = pitch_deg


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_poll(delta)
		return
	if Game.end_state != "":
		return
	if edit_mode:
		_edit_keys(delta)
		_edit_update_box()
		if ui != null:
			var s := "РЕДАКТОР: ЛКМ — выбрать и тащить · стрелки — двигать · PgUp/PgDn — высота · Z/X — поворот · Delete — убрать · Backspace — сброс · F/Esc — выход"
			if edit_selected != {} and is_instance_valid(edit_selected.node):
				s = "Выделено: %s · %s" % [(edit_selected.node as Node3D).name, s]
			ui.set_hint(s)
		return
	if not Game.cinematic:
		_camera_input(delta)
	walked = false
	_wasd_move(delta)
	_move_player(delta)
	var tt := Time.get_ticks_msec() / 1000.0
	M.animate(player, tt, walked or not path.is_empty())
	if blocked_body != null and _dist_stand(blocked_body) > 2.4:
		blocked_body = null
	for i in wnodes.size():
		M.animate(wnodes[i], tt, anim[i])
	if anemo != null:
		anemo.rotation.y += delta * (1.0 + wind_now * 0.4)
	if Game.gen_broken:
		var oi := 0
		for o in omnis:
			(o as OmniLight3D).light_energy = light_base * 0.35 * (0.72 + 0.28 * absf(sin(tt * 21.0 + oi * 1.7)))
			oi += 1
	# гроза: вспышки молний (без звука)
	if storming:
		thunder_cd -= delta
		_flash = maxf(0.0, _flash - delta * 2.5)
		if thunder_cd <= 0.0:
			thunder_cd = randf_range(4.0, 12.0)
			_flash = 1.0
		if _flash > 0.0:
			env.background_color = base_bg.lerp(Color(0.9, 0.92, 1.0), _flash * 0.55)
			sun.light_energy = sun_e + 5.0 * _flash
	# сотрудники иногда прогуливаются по бункеру
	if not Game.paused and not Game.modal_open and not Game.cinematic:
		for i in wnodes.size():
			if anim[i] or i >= wander_cd.size():
				continue
			var w: Dictionary = Game.workers[i]
			if w.dead or w.away != null:
				continue
			wander_cd[i] -= delta
			if wander_cd[i] <= 0.0:
				wander_cd[i] = randf_range(25.0, 70.0)
				var spot: Vector3 = IDLE_SPOTS[randi() % IDLE_SPOTS.size()]
				if spot.distance_to((wnodes[i] as Node3D).position) > 1.0:
					var pts := _path((wnodes[i] as Node3D).position, spot)
					if pts.size() > 0:
						anim[i] = true
						_walk_tween(wnodes[i], pts, 4.5).finished.connect(_wander_done.bind(i))
	# подписи объектов всегда белые и видимые; при наведении — толще обводка
	var hovered: Node3D = null
	if not Game.modal_open and not Game.cinematic:
		hovered = _pick_at(get_viewport().get_mouse_position())
	for n in interactables:
		if not n.has_meta("label"):
			continue
		var l: Label3D = n.get_meta("label")
		l.modulate = Color(1, 1, 1, 1)
		l.outline_size = 22 if n == hovered else 10
	if ui != null:
		var txt := ""
		if not Game.modal_open and not Game.cinematic:
			if hovered != null:
				txt = String(hovered.get_meta("hint"))
			else:
				var nb := _nearest(1.6)
				if nb != null:
					txt = "E — " + String(nb.get_meta("hint"))
		ui.set_hint(txt)


func _camera_input(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	if v != Vector2.ZERO:
		rig.position += rig.transform.basis * Vector3(v.x, 0, v.y) * 18.0 * delta
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += delta * 1.2
	if Input.is_physical_key_pressed(KEY_R):
		yaw -= delta * 1.2
	yaw = clampf(yaw, -1.2, 1.2)
	rig.rotation.y = yaw
	dist = lerpf(dist, dist_target, minf(1.0, 10.0 * delta))
	cam.position.z = dist
	rig.position.x = clampf(rig.position.x, -34.0, 16.0)
	rig.position.z = clampf(rig.position.z, -12.0, 18.0)
	if Input.is_physical_key_pressed(KEY_C):
		rig.position = Vector3(player.position.x, FLOOR, player.position.z)


func _wasd_move(delta: float) -> void:
	if Game.modal_open or Game.cinematic or Game.end_state != "" or edit_mode:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if v == Vector2.ZERO:
		return
	walked = true
	path.clear()
	pending_body = null
	var dir := rig.transform.basis * Vector3(v.x, 0, v.y)
	dir.y = 0.0
	dir = dir.normalized()
	var spd_mult := 1.0
	if Game.player_food <= 0:
		spd_mult = 0.7  # голодный ходишь медленнее
	if Game.player_st < 25:
		spd_mult = 0.55  # без сна еле ногами перебираешь
	var spd := (10.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.5) * spd_mult
	var np: Vector3 = player.position + dir * spd * delta
	if not _solid_at(np):
		player.position = np
	elif not _solid_at(Vector3(np.x, player.position.y, player.position.z)):
		player.position.x = np.x
	elif not _solid_at(Vector3(player.position.x, player.position.y, np.z)):
		player.position.z = np.z
	var targ := atan2(-dir.x, -dir.z)
	player.rotation.y = lerp_angle(player.rotation.y, targ, minf(1.0, 14.0 * delta))


func _move_player(delta: float) -> void:
	if pending_body != null and _dist_stand(pending_body) < 1.0:
		_trigger(pending_body)
		return
	if path.is_empty():
		return
	var target: Vector3 = path[0]
	var d := Vector3(target.x - player.position.x, 0, target.z - player.position.z)
	if d.length() < 0.12:
		path.pop_front()
		if path.is_empty() and pending_body != null:
			_trigger(pending_body)
		return
	player.position += d.normalized() * minf(6.5 * delta, d.length())
	player.rotation.y = lerp_angle(player.rotation.y, atan2(-d.x, -d.z), minf(1.0, 14.0 * delta))
