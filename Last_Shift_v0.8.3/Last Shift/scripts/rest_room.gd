@tool
class_name RestRoom
extends RefCounted
## Комната отдыха: койки, кровати, сон сотрудников.

const M := preload("res://scripts/models.gd")
var host: BunkerWorld
var rest_boxes: Array = []   # пол, стены и земля комнаты отдыха: позиции задаёт код
var bunk_north: Node3D   # койка №1 модели «Койки» (северная, у стены)
var bunk_south: Node3D   # койка №2 (южная)
var bed_nodes: Array = []   # визуальные кровати №3–10 (первые две — модель «Койки»)
var sleep_st: Array = []    # 0 — не спит, 1 — идёт к кровати, 2 — лежит
var sleep_tw: Array = []
var sleep_init := true
var last_beds := -1

func _init(h: BunkerWorld) -> void:
	host = h


# Только проверка: показывает в «Выводе», что новая модель койек и расстановка загружены.
func rest_diag() -> void:
	if bunk_north == null or bunk_south == null:
		push_warning("Койки: не найдены узлы «койка_1»/«койка_2» — проверьте models/койки.glb.")
	print("Комната отдыха: койка_1=%s койка_2=%s, верхний ряд z=%.2f, нижний z=%.2f" % [bunk_north != null, bunk_south != null, WorldConfig.BED_TOP_Z, WorldConfig.BED_ZC + WorldConfig.BED_DZ])


func in_rest_group(n: Node, roots: Array) -> bool:
	for r in roots:
		if is_instance_valid(r) and (n == r or (r as Node).is_ancestor_of(n)):
			return true
	return false


# Комната отдыха расширена на восток до x=REST_X1: пол, стены, земля вокруг и до 10 кроватей.
func _rest_box(size: Vector3, pos: Vector3, col: Color, title := "") -> void:
	var m := M.box(host, size, pos, col)
	if title != "":
		m.name = title
	rest_boxes.append({"node": m, "pos": pos})


func build_rest_extension() -> void:
	var w := WorldConfig.REST_X1 - 14.0
	var d := WorldConfig.REST_Z1 - WorldConfig.REST_Z0
	var cx := (14.0 + WorldConfig.REST_X1) / 2.0
	var cz := (WorldConfig.REST_Z0 + WorldConfig.REST_Z1) / 2.0
	var earth := host.builder.earth_color()
	var wall := Color(0.4, 0.42, 0.45)
	rest_boxes.clear()
	_rest_box(Vector3(w, 0.2, d), Vector3(cx, WorldConfig.FLOOR - 0.1, cz), Color(0.26, 0.27, 0.29), "Пол комнаты отдыха")
	# южная стенка (низкая, как остальные южные) и земля с севера, востока и юго-востока
	_rest_box(Vector3(w, 0.9, 0.3), Vector3(cx, WorldConfig.FLOOR + 0.45, WorldConfig.REST_Z1), wall, "Стена комнаты отдыха (юг)")
	_rest_box(Vector3(w + 3.0, 3.24, WorldConfig.REST_Z0 + 10.0), Vector3(14.0 + (w + 3.0) / 2.0, -1.58, (WorldConfig.REST_Z0 - 10.0) / 2.0), earth, "Земля отдыха (север)")
	_rest_box(Vector3(3.0, 3.24, d), Vector3(WorldConfig.REST_X1 + 1.5, -1.58, cz), earth, "Земля отдыха (восток)")
	_rest_box(Vector3(2.0, 3.24, 8.0), Vector3(15.0, -1.58, 12.0), earth, "Земля отдыха (юго-восток)")
	# кровати №3–10 (первые две — модель «Койки» у восточной стены старой части)
	var cols := [Color(0.55, 0.3, 0.28), Color(0.28, 0.42, 0.55), Color(0.35, 0.5, 0.32), Color(0.6, 0.5, 0.25)]
	bed_nodes.clear()
	for i in range(2, 10):
		var slot := bed_slot(i)
		var bn := M.bed(host, cols[(i - 2) % cols.size()])
		bn.position = Vector3(slot.x, WorldConfig.FLOOR, slot.z)
		bn.name = "Кровать %d" % (i + 1)
		bed_nodes.append(bn)
	# старая «Койки» больше не должна перегораживать проход в пристройку
	var bunk := host.layout.item_by_name("Койки")
	if not bunk.is_empty():
		bunk.obs = Vector3.ZERO


# центр кровати №i (0–9) на высоте лежащего персонажа
func bed_slot(i: int) -> Vector3:
	if i < 2:
		var bn: Node3D = bunk_north if i == 0 else bunk_south
		if bn != null and is_instance_valid(bn) and bn.is_inside_tree():
			return bn.global_position + Vector3(0, 0.45, 0)
		return Vector3(WorldConfig.BED_X0, WorldConfig.FLOOR + 0.85, WorldConfig.BED_TOP_Z if i == 0 else WorldConfig.BED_ZC + WorldConfig.BED_DZ)
	var k := i - 2
	# верхние кровати (чётные k) прижаты к северной стене, нижние остаются на месте
	return Vector3(WorldConfig.BED_X0 + (1 + k / 2) * WorldConfig.BED_DX, WorldConfig.FLOOR + 0.85, WorldConfig.BED_TOP_Z if k % 2 == 0 else WorldConfig.BED_ZC + WorldConfig.BED_DZ)


# сотрудники сами идут к своим кроватям ночью и встают утром
func _sleep_sync() -> void:
	while sleep_st.size() < host.staff.wnodes.size():
		sleep_st.append(0)
		sleep_tw.append(null)
	for i in host.staff.wnodes.size():
		var w: Dictionary = Game.workers[i]
		var n: Node3D = host.staff.wnodes[i]
		var want: bool = bool(w.get("asleep", false)) and not w.dead and w.away == null
		if want and sleep_st[i] == 0:
			var bed: int = int(w.get("bed", -1))
			if bed < 0 or host.staff.anim[i]:
				continue
			var slot := bed_slot(bed)
			host.staff.anim[i] = true
			n.visible = true
			if sleep_init:
				n.position = slot
				n.rotation = Vector3(deg_to_rad(90.0), PI, 0.0)
				sleep_st[i] = 2
			else:
				var pts := host.nav.path(n.position, Vector3(slot.x, WorldConfig.H, slot.z))
				var tw := host.staff.walk_w(i, pts, 4.5)
				sleep_tw[i] = tw
				sleep_st[i] = 1
				tw.finished.connect(_sleep_lie.bind(i))
		elif not want and sleep_st[i] != 0:
			if sleep_tw[i] != null and (sleep_tw[i] as Tween).is_valid():
				(sleep_tw[i] as Tween).kill()
			sleep_tw[i] = null
			host.staff.kill_walk(i)
			sleep_st[i] = 0
			n.rotation = Vector3.ZERO
			if w.dead or w.away != null:
				host.staff.anim[i] = false
				continue
			n.position.y = WorldConfig.H
			var back := host.nav.path(n.position, WorldConfig.IDLE_SPOTS[i])
			host.staff.anim[i] = true
			var tw2 := host.staff.walk_w(i, back, 4.5)
			tw2.finished.connect(host.staff.wander_done.bind(i))
	sleep_init = false


func _sleep_lie(i: int) -> void:
	if i >= host.staff.wnodes.size() or sleep_st[i] != 1:
		return
	var w: Dictionary = Game.workers[i]
	var bed: int = int(w.get("bed", -1))
	if bed < 0:
		return
	var n: Node3D = host.staff.wnodes[i]
	n.rotation.y = wrapf(n.rotation.y, 0.0, TAU)  # чтобы ложился по короткой дуге, без оборота
	var tw := host.create_tween().set_parallel(true)
	tw.tween_property(n, "position", bed_slot(bed), 0.5)
	tw.tween_property(n, "rotation", Vector3(deg_to_rad(90.0), PI, 0.0), 0.5)
	sleep_st[i] = 2


# Видимость кроватей, сон сотрудников, пересчёт путей при смене числа кроватей
func sync_beds() -> void:
	for k in bed_nodes.size():
		(bed_nodes[k] as Node3D).visible = Game.beds > k + 2
	_sleep_sync()
	if Game.beds != last_beds:
		last_beds = Game.beds
		host.nav.build_astar()
