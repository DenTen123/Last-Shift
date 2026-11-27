@tool
class_name StaffController
extends RefCounted
## Сотрудники и гости: появление, ходьба, прогулки.

const M := preload("res://scripts/models.gd")
var host: BunkerWorld
var wtw: Array = []          # текущая ходьба каждого сотрудника (Tween)
var wnodes: Array = []
var anim: Array = []
var visitor_node: Node3D = null
var trader_node: Node3D = null  # торговец у ворот: внутрь не заходит
var trader_lbl: Label3D = null
var _trader_walking := false
var _extras: Array = []  # ушедшие гости: анимируем, пока уходят
var visitor_lbl: Label3D = null
var wander_cd: Array = []

func _init(h: BunkerWorld) -> void:
	host = h


func sync_workers() -> void:
	while wnodes.size() < Game.workers.size():
		var i := wnodes.size()
		var w: Dictionary = Game.workers[i]
		var n := M.character(w.suit, Color(0.95, 0.8, 0.2))
		n.position = WorldConfig.IDLE_SPOTS[i]
		host.add_child(n)
		wnodes.append(n)
	while anim.size() < Game.workers.size():
		anim.append(false)
	while wander_cd.size() < Game.workers.size():
		wander_cd.append(randf_range(8.0, 40.0))
	for i in wnodes.size():
		if not anim[i]:
			var w: Dictionary = Game.workers[i]
			var show: bool = (not w.dead) and w.away == null
			# ставим на место только при появлении: иначе после прогулки выживший «прыгал» обратно
			if show and not wnodes[i].visible:
				wnodes[i].position = WorldConfig.IDLE_SPOTS[i]
				wnodes[i].rotation = Vector3.ZERO
			wnodes[i].visible = show
	sync_trader()


func on_npc_arrived(npc_name: String, status: String) -> void:
	Snd.play("knock")
	if visitor_node != null:
		visitor_node.queue_free()
	var d: Dictionary = Game.NPC_DEFS[Game.visitor.def]
	var n := M.character(d.suit, Color(0.95, 0.8, 0.2))
	var gb: Vector3 = (host.gates.door_body as Node3D).global_position
	var ow := host.gates.outward()
	# окно смещено на 0.5 м по локальной оси X ворот — гость встаёт ровно напротив него
	var lx := ((host.gates.door_body as Node3D).global_transform.basis.x as Vector3).normalized() * 0.5
	# гость стоит СНАРУЖИ ворот напротив смотрового окна, лицом к бункеру
	var spawn := Vector3(gb.x, WorldConfig.H, gb.z) + ow * 3.2
	spawn.y = host.gates.stair_spawn_y(spawn)
	n.position = spawn + lx
	n.rotation.y = atan2(ow.x, ow.z)
	host.add_child(n)
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
	if host.ui != null:
		host.ui.toast("Стук в ворота! Подойдите к воротам и посмотрите в окно (E).")


func on_npc_done(accepted: bool) -> void:
	var n := visitor_node
	visitor_node = null
	if host.ui != null:
		host.ui.hide_npc_bar()
	labels_visible(true)
	if accepted and n != null:
		host.gates.gate_move(true)
		wnodes.append(n)
		anim.append(true)
		var idx := wnodes.size() - 1
		# путь внутрь строим от текущих ворот (где бы их ни поставил редактор)
		var gb: Vector3 = (host.gates.door_body as Node3D).global_position
		var ow := host.gates.outward()
		var under: Vector3 = Vector3(gb.x, WorldConfig.H, gb.z)
		var inside: Vector3 = under - ow * 1.5
		var lxi := Vector3.ZERO
		if host.gates.door_body != null and is_instance_valid(host.gates.door_body):
			lxi = ((host.gates.door_body as Node3D).global_transform.basis.x as Vector3).normalized() * 0.5
		var p0 := under + ow * 3.2 + lxi
		p0.y = host.gates.stair_spawn_y(p0)
		var pts: Array = [p0, under, inside]
		pts.append_array(host.nav.path(inside, WorldConfig.IDLE_SPOTS[idx]))
		var seq := host.create_tween()
		seq.tween_interval(1.4)
		seq.tween_callback(func():
			_walk_tween(n, pts, 6.5).finished.connect(_npc_in_done.bind(idx)))
	elif n != null:
		var gbr: Vector3 = (host.gates.door_body as Node3D).global_position
		var owr := host.gates.outward()
		_extras.append(n)
		_walk_tween(n, [Vector3(gbr.x, WorldConfig.H, gbr.z) + owr * 6.0], 7.0).finished.connect(n.queue_free)
	if host.gates.door_cinematic:
		host.camera.restore_cam()
		host.gates.door_cinematic = false
		Game.cinematic = false


# ---------- торговец: приходит к воротам, стоит снаружи и уходит; внутрь не заходит ----------
func _trader_point(dist: float) -> Vector3:
	var gb: Vector3 = (host.gates.door_body as Node3D).global_position
	var ow := host.gates.outward()
	var lx := ((host.gates.door_body as Node3D).global_transform.basis.x as Vector3).normalized()
	var p := Vector3(gb.x, WorldConfig.H, gb.z) + ow * dist - lx * 1.3  # левее гостя, чтобы не стоять в одной точке
	p.y = host.gates.stair_spawn_y(p)
	return p


func sync_trader() -> void:
	if host.gates.door_body == null or not is_instance_valid(host.gates.door_body):
		return
	var has: bool = not Game.trader.is_empty()
	var present: bool = trader_node != null and is_instance_valid(trader_node)
	if has and not present:
		_trader_arrive()
	elif not has and present:
		_trader_leave()


func _trader_arrive() -> void:
	var n := M.character(Color(0.32, 0.28, 0.4), Color(0.95, 0.8, 0.2))
	var ow := host.gates.outward()
	n.rotation.y = atan2(ow.x, ow.z)
	host.add_child(n)
	var l := Label3D.new()
	l.text = "Торговец"
	l.font_size = 36
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 10
	l.position = Vector3(0, 1.55, 0)
	n.add_child(l)
	trader_node = n
	trader_lbl = l
	var spot := _trader_point(3.2)
	# только что пришёл — идёт к воротам; торговец из сохранения уже стоит на месте
	if int(Game.trader.until) - Game.t > Game.TRADER_STAY - 30:
		n.position = _trader_point(14.0)
		_trader_walking = true
		Snd.play("knock")
		_walk_tween(n, [_trader_point(8.0), spot], 4.5).finished.connect(func(): _trader_walking = false)
		if host.ui != null:
			host.ui.toast("К воротам пришёл торговец. Подойдите к воротам и посмотрите в окно (E).")
	else:
		n.position = spot


func _trader_leave() -> void:
	var n := trader_node
	trader_node = null
	trader_lbl = null
	_trader_walking = false
	if n == null or not is_instance_valid(n):
		return
	_extras.append(n)
	_walk_tween(n, [_trader_point(8.0), _trader_point(14.0)], 4.5).finished.connect(n.queue_free)


# Игрок отошёл от окна, ничего не решив: гость ждёт у ворот, пока не истечёт время ожидания
func on_npc_wait() -> void:
	if host.ui != null:
		host.ui.hide_npc_bar()
	labels_visible(true)
	if host.gates.door_cinematic:
		host.camera.restore_cam()
		host.gates.door_cinematic = false
		Game.cinematic = false


func _npc_in_done(i: int) -> void:
	anim[i] = false
	host.gates.gate_move(false)


func wander_done(i: int) -> void:
	anim[i] = false


func _walk_tween(node: Node3D, pts: Array, speed: float) -> Tween:
	var tw := host.create_tween()
	var cur: Vector3 = node.position
	var cur_ang := node.rotation.y
	for p in pts:
		var a: Vector3 = cur
		var b: Vector3 = p
		if absf(b.x - a.x) + absf(b.z - a.z) > 0.001:
			# поворот по кратчайшей дуге и одновременно с шагом, без остановки на каждой точке
			var ang := atan2(-(b.x - a.x), -(b.z - a.z))
			ang = cur_ang + wrapf(ang - cur_ang, -PI, PI)
			cur_ang = ang
			tw.tween_property(node, "rotation:y", ang, 0.15)
			tw.parallel().tween_property(node, "position", b, maxf(a.distance_to(b) / speed, 0.15))
		else:
			tw.tween_property(node, "position", b, 0.05)
		cur = b
	return tw


func kill_walk(i: int) -> void:
	while wtw.size() <= i:
		wtw.append(null)
	if wtw[i] != null and (wtw[i] as Tween).is_valid():
		(wtw[i] as Tween).kill()
	wtw[i] = null


# ходьба сотрудника i: старая ходьба (прогулка, вход, выход) обрывается
func walk_w(i: int, pts: Array, speed: float) -> Tween:
	kill_walk(i)
	var tw := _walk_tween(wnodes[i], pts, speed)
	tw.tween_interval(0.01)
	wtw[i] = tw
	return tw


func on_left(i: int) -> void:
	kill_walk(i)
	anim[i] = true
	var n: Node3D = wnodes[i]
	n.rotation.x = 0.0
	n.rotation.z = 0.0
	if not n.visible:
		n.position = WorldConfig.IDLE_SPOTS[i]
		n.visible = true
	host.gates.hatch_hold(i)
	var start: Vector3 = n.position
	# выход через дверь для людей и вверх по лестнице (северная полоса въезда);
	# если сотрудник ещё не дошёл до бункера с прошлой вылазки — разворачиваем его с того места, где он стоит
	var pts: Array = []
	if start.x > -13.5:
		pts = host.nav.path(start, Vector3(-13, WorldConfig.H, 0))
		pts.append(Vector3(-14, WorldConfig.H, -2.75))
	for rp in [Vector3(-26, 0.9, -2.75), Vector3(-30, 0.9, -2.75)]:
		if rp.x < start.x - 0.05:
			pts.append(rp)
	walk_w(i, pts, 7.0).finished.connect(_out_done.bind(i))


func _out_done(i: int) -> void:
	wnodes[i].visible = false
	anim[i] = false
	host.gates.hatch_drop(i)


func on_back(i: int, ok: bool) -> void:
	if not ok:
		host.gates.hatch_acquire()
		host.get_tree().create_timer(3.0).timeout.connect(host.gates.hatch_release)
		return
	kill_walk(i)
	host.gates.hatch_hold(i)
	anim[i] = true
	var n: Node3D = wnodes[i]
	n.rotation.x = 0.0
	n.rotation.z = 0.0
	n.visible = true
	n.position = Vector3(-30, 0.9, -2.75)
	var pts: Array = [Vector3(-26, 0.9, -2.75), Vector3(-14, WorldConfig.H, -2.75)]
	pts.append_array(host.nav.path(Vector3(-13, WorldConfig.H, 0), WorldConfig.IDLE_SPOTS[i]))
	walk_w(i, pts, 7.0).finished.connect(_in_done.bind(i))


func _in_done(i: int) -> void:
	anim[i] = false
	host.gates.hatch_drop(i)
	host._on_changed()


func labels_visible(v: bool) -> void:
	for n in host.interactables:
		if n.has_meta("label"):
			(n.get_meta("label") as Label3D).visible = v
	if visitor_lbl != null and is_instance_valid(visitor_lbl):
		visitor_lbl.visible = v
	if trader_lbl != null and is_instance_valid(trader_lbl):
		trader_lbl.visible = v


# Анимация сотрудников и их прогулки по бункеру
func update_workers(delta: float) -> void:
	var tt := Time.get_ticks_msec() / 1000.0
	for i in wnodes.size():
		M.animate(wnodes[i], tt, anim[i] and not (i < host.rest.sleep_st.size() and host.rest.sleep_st[i] == 2))
	if trader_node != null and is_instance_valid(trader_node):
		M.animate(trader_node, tt, _trader_walking)
	for e in _extras.duplicate():
		if is_instance_valid(e):
			M.animate(e, tt, true)
		else:
			_extras.erase(e)
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
				var spot: Vector3 = WorldConfig.IDLE_SPOTS[randi() % WorldConfig.IDLE_SPOTS.size()]
				if spot.distance_to((wnodes[i] as Node3D).position) > 1.0:
					var pts := host.nav.path((wnodes[i] as Node3D).position, spot)
					if pts.size() > 0:
						anim[i] = true
						walk_w(i, pts, 4.5).finished.connect(wander_done.bind(i))
