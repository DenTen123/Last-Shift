@tool
extends RefCounted
## Модели: настоящие 3D-меши, собранные в Blender и экспортированные в .glb (res://models/).
## Каждый конструктор создаёт пивот, ставит внутрь экземпляр .glb и возвращает пивот.
## Если .glb ещё не импортирован — ставится простой куб-заглушка, чтобы игра не ломалась.

static var _mats := {}
static var _scenes := {}

# соответствие id станции → имя файла модели
const ST_GLB := {"garden": "грядка", "kitchen": "кухня", "furnace": "печь", "shredder": "измельчитель", "medbed": "кушетка", "medcab": "аптечный_шкаф"}


# ---------- базовые помощники ----------
static func mat(col: Color, emit := false) -> StandardMaterial3D:
	var key := col.to_html() + ("e" if emit else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if emit:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.4
	_mats[key] = m
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, col: Color, emit := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat(col, emit)
	m.position = pos
	parent.add_child(m)
	return m


static func pivot(parent: Node, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ---------- загрузка .glb ----------
static func clear_scene_cache() -> void:
	_scenes.clear()


static func _scene(n: String) -> PackedScene:
	var path := "res://models/%s.glb" % n
	var updated := "res://models/updated/%s.glb" % n
	if ResourceLoader.exists(updated):
		path = updated
	# Ключ — фактический файл: новый импорт не должен брать старую модель.
	# Отсутствующие ресурсы не кэшируем: импорт может ещё выполняться.
	if not ResourceLoader.exists(path):
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _spawn(parent: Node, n: String, fb := Vector3.ONE, fbcol := Color(0.6, 0.6, 0.6)) -> Node3D:
	var ps := _scene(n)
	if ps != null:
		var inst := ps.instantiate() as Node3D
		if ResourceLoader.exists("res://models/updated/%s.glb" % n):
			inst.set_meta("layout_revision", "models_20261119")
		parent.add_child(inst)
		return inst
	return box(parent, fb, Vector3.ZERO, fbcol)


static func _find(root: Node, nm: String) -> Node:
	if root == null:
		return null
	return root.find_child(nm, true, true)


static func _node3d(n: Node, fb: Node3D) -> Node3D:
	return (n as Node3D) if n is Node3D else fb


static func _recolor(root: Node, target: String, col: Color) -> void:
	if root == null:
		return
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var hit := false
			for s in mi.mesh.get_surface_count():
				var mm := mi.get_active_material(s)
				if mm != null and mm.resource_name == target:
					hit = true
					break
			if not hit:
				continue
			# слитый меш общий для всех инстансов: дублируем, чтобы цвет был индивидуальным
			var mesh := mi.mesh.duplicate() as Mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var mm := mesh.surface_get_material(s)
				if mm != null and mm.resource_name == target:
					var m2 := mm.duplicate() as StandardMaterial3D
					if m2 != null:
						m2.albedo_color = col
						mesh.surface_set_material(s, m2)
			mi.mesh = mesh


# ---------- персонаж (ноги на y=-0.9, лицо смотрит в -Z) ----------
static func character(suit: Color, accent: Color) -> Node3D:
	var r := Node3D.new()
	var inst := _spawn(r, "персонаж", Vector3(0.6, 1.9, 0.4), suit)
	_recolor(inst, "Suit", suit)
	_recolor(inst, "SuitDark", suit.darkened(0.25))
	_recolor(inst, "Accent", accent)
	_recolor(inst, "AccentDark", accent.darkened(0.2))
	var limbs: Array = []
	for nm in ["PivotLegL", "PivotLegR", "PivotArmL", "PivotArmR"]:
		var nd := _find(inst, nm)
		limbs.append(_node3d(nd, pivot(r, Vector3.ZERO)))
	r.set_meta("limbs", limbs)
	return r


static func animate(n: Node3D, t: float, moving: bool) -> void:
	if not n.has_meta("limbs"):
		return
	var l: Array = n.get_meta("limbs")
	var a: float
	if moving:
		a = sin(t * 10.0) * 0.8
	else:
		a = sin(t * 2.2) * 0.06  # лёгкое «дыхание» в покое
	l[0].rotation.x = a
	l[1].rotation.x = -a
	l[2].rotation.x = -a if moving else -a * 0.6
	l[3].rotation.x = a if moving else a * 0.6


# ---------- автомобиль (перед смотрит в -X) ----------
static func build_car(car: Node3D) -> Dictionary:
	var inst := _spawn(car, "автомобиль", Vector3(4.4, 2.4, 2.2), Color(0.78, 0.42, 0.16))
	var out := {}
	for k in [["wheels", "PartWheels"], ["engine", "PartEngine"], ["battery", "PartBattery"], ["tank", "PartTank"], ["cabin", "PartCabin"]]:
		out[k[0]] = _node3d(_find(inst, k[1]), pivot(car, Vector3.ZERO))
	return out


# ---------- архитектура бункера (полы, стены, земля, рампа, тамбур) ----------
static func bunker(p: Node) -> Array:
	var inst := _spawn(p, "бункер", Vector3(28, 3, 24), Color(0.4, 0.4, 0.4))
	var out: Array = []
	for c in inst.get_children():
		if c is Node3D and String(c.name).begins_with("Piece"):
			out.append({"name": String(c.name).trim_prefix("Piece"), "node": c})
	return out


# ---------- приметы гостей (нож / насморк) ----------
static func prop(p: Node, n: String) -> void:
	_spawn(p, n, Vector3(0.2, 0.3, 0.2), Color(0.6, 0.6, 0.6))


# ---------- мебель (локальные координаты внутри коллайдера) ----------
static func shelf(p: Node) -> void:
	_spawn(p, "стеллаж", Vector3(5, 2.4, 1.0), Color(0.55, 0.38, 0.2))


static func weather_desk(p: Node) -> void:
	_spawn(p, "метеостанция", Vector3(4, 1.5, 1.2), Color(0.3, 0.32, 0.34))


static func workbench(p: Node) -> void:
	_spawn(p, "верстак", Vector3(4.5, 1.0, 1.4), Color(0.6, 0.4, 0.2))


# Модель «койки» — ОДНА кровать из models/койки.glb (вместо прежней сдвоенной модели из models/updated).
# Для двух стартовых мест игры создаются узлы «койка_1» (север, z=-1.5) и «койка_2» (юг, z=+1.5)
# относительно центра ряда; в каждом — экземпляр одной и той же модели, основание на полу.
# Возвращает корень (узел «койки»).
const BUNK_GLB := "res://models/койки.glb"

static func bunks(p: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "койки"
	p.add_child(root)
	var ps: PackedScene = null
	if ResourceLoader.exists(BUNK_GLB):
		ps = load(BUNK_GLB) as PackedScene
	for i in 2:
		var slot := Node3D.new()
		slot.name = "койка_%d" % (i + 1)
		slot.position = Vector3(0, 0, -1.5 if i == 0 else 1.5)
		root.add_child(slot)
		if ps == null:
			box(slot, Vector3(1.7, 0.35, 2.65), Vector3(0, -0.225, 0), Color(0.45, 0.47, 0.5))
			continue
		var inst := ps.instantiate() as Node3D
		slot.add_child(inst)
		_center_on_floor(inst, -0.4)
	return root


# Центрирует модель по X/Z и ставит её нижнюю точку на высоту floor_y (в координатах родителя).
static func _center_on_floor(inst: Node3D, floor_y: float) -> void:
	var bb := _local_aabb(inst, Transform3D.IDENTITY)
	if bb.size == Vector3.ZERO:
		return
	var c := bb.get_center()
	inst.position = Vector3(-c.x, floor_y - bb.position.y, -c.z)


static func _local_aabb(n: Node, xf: Transform3D) -> AABB:
	var res := AABB()
	var has := false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		res = xf * (n as MeshInstance3D).get_aabb()
		has = true
	for ch in n.get_children():
		var cx := xf
		if ch is Node3D:
			cx = xf * (ch as Node3D).transform
		var b := _local_aabb(ch, cx)
		if b.size == Vector3.ZERO:
			continue
		res = b if not has else res.merge(b)
		has = true
	return res


# одиночная кровать (длина по Z, подушка у -Z), центр основания на полу
static func bed(p: Node, blanket: Color) -> Node3D:
	var r := Node3D.new()
	p.add_child(r)
	box(r, Vector3(1.7, 0.35, 2.65), Vector3(0, 0.175, 0), Color(0.32, 0.33, 0.36))
	box(r, Vector3(1.55, 0.16, 2.45), Vector3(0, 0.43, 0), Color(0.82, 0.82, 0.78))
	box(r, Vector3(1.55, 0.08, 1.55), Vector3(0, 0.52, 0.4), blanket)
	box(r, Vector3(1.0, 0.14, 0.5), Vector3(0, 0.55, -1.0), Color(0.92, 0.92, 0.9))
	return r


static func radio(p: Node) -> void:
	_spawn(p, "радио", Vector3(1.0, 1.0, 0.8), Color(0.75, 0.3, 0.25))


static func console(p: Node) -> void:
	_spawn(p, "пульт_люка", Vector3(1.2, 1.2, 0.8), Color(0.2, 0.3, 0.38))


# ---------- декор ----------
static func generator(p: Node, pos: Vector3) -> Node3D:
	var g := pivot(p, pos)
	_spawn(g, "генератор", Vector3(2.0, 1.6, 1.6), Color(0.28, 0.36, 0.3))
	return g


static func crate(p: Node, pos: Vector3, s := 1.0) -> Node3D:
	var c := pivot(p, pos)
	var inst := _spawn(c, "ящик", Vector3.ONE, Color(0.55, 0.4, 0.22))
	inst.scale = Vector3(s, s, s)
	return c


static func barrel(p: Node, pos: Vector3, col: Color) -> Node3D:
	var b := pivot(p, pos)
	var inst := _spawn(b, "бочка", Vector3(0.7, 0.95, 0.7), col)
	_recolor(inst, "Body", col)
	_recolor(inst, "BodyDark", col.darkened(0.3))
	return b


static func locker(p: Node, pos: Vector3, col: Color) -> Node3D:
	var l := pivot(p, pos)
	var inst := _spawn(l, "шкафчик", Vector3(0.8, 1.9, 0.6), col)
	_recolor(inst, "Body", col)
	_recolor(inst, "BodyDark", col.darkened(0.5))
	return l


static func plant(p: Node, pos: Vector3) -> Node3D:
	var l := pivot(p, pos)
	_spawn(l, "растение", Vector3(0.6, 1.2, 0.6), Color(0.25, 0.6, 0.3))
	return l


static func warn_sign(p: Node, pos: Vector3) -> Node3D:
	var s := pivot(p, pos)
	_spawn(s, "знак_опасности", Vector3(1.0, 0.7, 0.1), Color(0.95, 0.75, 0.1))
	return s


static func wall_lamp(p: Node, pos: Vector3) -> Node3D:
	var l := pivot(p, pos)
	_spawn(l, "настенная_лампа", Vector3(0.9, 0.2, 0.4), Color(1.0, 0.85, 0.5))
	return l


static func door_post(p: Node, pos: Vector3) -> Node3D:
	var d := pivot(p, pos)
	_spawn(d, "дверная_стойка", Vector3(0.36, 2.0, 0.36), Color(0.25, 0.27, 0.3))
	return d


static func mapboard(p: Node, pos: Vector3, rot_y := 0.0) -> Node3D:
	var b := pivot(p, pos)
	b.rotation_degrees.y = rot_y
	_spawn(b, "карта_на_стене", Vector3(1.9, 1.3, 0.2), Color(0.16, 0.3, 0.2))
	return b


static func tv(p: Node, pos: Vector3, rot_y := 0.0) -> Node3D:
	var t := pivot(p, pos)
	t.rotation_degrees.y = rot_y
	_spawn(t, "телевизор", Vector3(1.5, 1.0, 0.2), Color(0.12, 0.12, 0.14))
	return t


static func pegboard(p: Node, pos: Vector3) -> Node3D:
	var b := pivot(p, pos)
	_spawn(b, "доска_инструментов", Vector3(0.2, 1.4, 2.3), Color(0.42, 0.32, 0.2))
	return b


static func rug(p: Node, pos: Vector3, size: Vector3, col: Color) -> Node3D:
	var r := pivot(p, Vector3(pos.x, 0, pos.z))
	var inst := _spawn(r, "ковер", Vector3(size.x, 0.03, size.z), col)
	inst.scale = Vector3(size.x, 1.0, size.z)
	_recolor(inst, "Rug", col)
	return r


static func table_set(p: Node, pos: Vector3) -> Node3D:
	var t := pivot(p, pos)
	_spawn(t, "стол", Vector3(3.4, 1.0, 1.2), Color(0.55, 0.4, 0.24))
	return t


static func cooler(p: Node, pos: Vector3) -> Node3D:
	var c := pivot(p, pos)
	_spawn(c, "кулер", Vector3(0.5, 1.5, 0.5), Color(0.85, 0.88, 0.9))
	return c


static func air_filter(p: Node, pos: Vector3) -> Node3D:
	var f := pivot(p, pos)
	_spawn(f, "фильтр_воздуха", Vector3(0.9, 1.2, 0.4), Color(0.35, 0.4, 0.42))
	return f


static func insul_panel(p: Node, pos: Vector3) -> Node3D:
	var b := pivot(p, pos)
	_spawn(b, "утепление", Vector3(2.6, 0.45, 0.6), Color(0.85, 0.65, 0.15))
	return b


static func coffee_machine(p: Node, pos: Vector3) -> Node3D:
	var c := pivot(p, pos)
	_spawn(c, "кофемашина", Vector3(0.4, 0.6, 0.4), Color(0.25, 0.26, 0.3))
	return c


static func anemometer(p: Node, pos: Vector3) -> Node3D:
	var m := pivot(p, pos)
	var inst := _spawn(m, "анемометр", Vector3(1.4, 3.8, 1.4), Color(0.6, 0.6, 0.62))
	return _node3d(_find(inst, "Rotor"), pivot(m, Vector3(0, 3.5, 0)))


static func hatch_cover(p: Node) -> Node3D:
	return _spawn(p, "крышка_люка", Vector3(12, 0.45, 6.2), Color(0.35, 0.37, 0.36))


# ---------- ворота бункера (рама + распашное полотно с окном; шарнир у левого края) ----------
static func gates(p: Node) -> Node3D:
	# Новые ворота собраны из двух моделей: «дверь2» — рама, «дверь1» — полотно.
	# Внутренний меш полотна уже имеет начало координат на петле, поэтому поворот
	# этого узла вокруг Y открывает ворота как обычную дверь.
	# Старая совмещённая модель — только запасной вариант.
	var leaf_scene := _scene("дверь1")
	if leaf_scene == null:
		var inst := _spawn(p, "ворота", Vector3(2.3, 2.6, 0.4), Color(0.45, 0.5, 0.55))
		return _node3d(_find(inst, "GateLeaf"), pivot(p, Vector3(0, 2.4, 0)))
	var frame := _spawn(p, "дверь2", Vector3(2.3, 2.6, 0.4), Color(0.45, 0.5, 0.55))
	# Новый ключ раскладки: старые сохранённые преобразования деталей не применяются.
	frame.set_meta("layout_revision", "door_20261120")
	var leaf_root := leaf_scene.instantiate() as Node3D
	leaf_root.set_meta("layout_revision", "door_20261120")
	p.add_child(leaf_root)
	# В импортированной сцене корень — обёртка, а сам меш лежит внутри и уже стоит на петле.
	return _node3d(_find(leaf_root, "GateLeaf_Mesh"), leaf_root)


# ---------- большие ворота для машины (рама + поднимающееся полотно без окна) ----------
static func auto_gates(p: Node) -> Node3D:
	var inst := _spawn(p, "ворота_машины", Vector3(6.1, 3.6, 0.4), Color(0.42, 0.47, 0.52))
	return _node3d(_find(inst, "AutoGateLeaf"), pivot(p, Vector3(0, 3.6, 0)))


# ---------- станции новых комнат (локальные координаты, центр = центр коллайдера) ----------
static func ghost(p: Node, size: Vector3) -> Node3D:
	var g := pivot(p, Vector3.ZERO)
	var y := -size.y / 2.0 + 0.04
	var col := Color(0.95, 0.75, 0.1)
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	box(g, Vector3(size.x, 0.05, 0.12), Vector3(0, y, -hz), col, true)
	box(g, Vector3(size.x, 0.05, 0.12), Vector3(0, y, hz), col, true)
	box(g, Vector3(0.12, 0.05, size.z), Vector3(-hx, y, 0), col, true)
	box(g, Vector3(0.12, 0.05, size.z), Vector3(hx, y, 0), col, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(g, Vector3(0.2, 0.5, 0.2), Vector3(sx * hx, y + 0.25, sz * hz), col, true)
	return g


static func station(body: Node3D, id: String, size: Vector3) -> Dictionary:
	var d := {}
	d["ghost"] = ghost(body, size)
	var m := pivot(body, Vector3.ZERO)
	d["model"] = m
	var inst := _spawn(m, ST_GLB[id], size, Color(0.5, 0.5, 0.5))
	var dummy := pivot(m, Vector3.ZERO)
	if id == "garden":
		d["plants"] = _node3d(_find(inst, "Plants"), dummy)
		d["fruit"] = _node3d(_find(inst, "Fruit"), dummy)
		d["lamp"] = _node3d(_find(inst, "Lamp"), dummy)
		d["irrig"] = _node3d(_find(inst, "Irrig"), dummy)
	return d
