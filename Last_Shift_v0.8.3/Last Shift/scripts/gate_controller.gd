@tool
class_name GateController
extends RefCounted
## Люк, ворота, окно в воротах и машина (выезд).

var host: BunkerWorld
var car: Node3D
var car_wheels: Node3D
var car_engine: Node3D
var car_battery: Node3D
var car_tank: Node3D
var car_cabin: Node3D
var hatch: Node3D
var hatch_held: Array = []   # держит ли сотрудник люк открытым
var hatch_tween: Tween
var hatch_users := 0
var door_body: Node3D = null
var auto_gates_body: Node3D = null
var auto_leaf: Node3D = null
var auto_gate_tween: Tween
var door_cinematic := false
var gates_leaf: Node3D = null
var gate_tween: Tween
# ================= гости =================
var _center_cache := Vector3(1e9, 0.0, 0.0)

func _init(h: BunkerWorld) -> void:
	host = h


func _bunker_center() -> Vector3:
	# центр жилых комнат — от него считаем, какая сторона ворот наружная
	if _center_cache.x > 1e8:
		var s := Vector3.ZERO
		for p in WorldConfig.IDLE_SPOTS:
			s += p
		_center_cache = s / float(WorldConfig.IDLE_SPOTS.size())
	return _center_cache


func outward() -> Vector3:
	# наружное направление ворот: от центра бункера к воротам, по доминирующей оси.
	# работает при любом переносе/повороте ворот в редакторе
	var gb: Vector3 = (door_body as Node3D).global_position
	var c := _bunker_center()
	var d := Vector3(gb.x - c.x, 0.0, gb.z - c.z)
	if absf(d.x) >= absf(d.z):
		return Vector3(signf(d.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(d.z))


func stair_spawn_y(p: Vector3) -> float:
	# высота ступеней у западного въезда: гость/рабочий стоит НА ступени, а не в воздухе
	if p.z <= -6.0 or p.z >= 6.0 or p.x <= -26.0 or p.x >= -12.0:
		return WorldConfig.H
	var k := clampi(int((p.x + 26.0) / 2.0), 0, 5)
	return -0.5 * float(k + 1) + 0.9


# ================= люк и экспедиции =================
func _tween_hatch(deg: float) -> void:
	if hatch_tween:
		hatch_tween.kill()
	hatch_tween = host.create_tween()
	hatch_tween.tween_property(hatch, "rotation:z", deg_to_rad(deg), 1.5)


func hatch_acquire() -> void:
	hatch_users += 1
	_tween_hatch(-75.0)
	Snd.play("hatch")


func hatch_release() -> void:
	hatch_users = maxi(0, hatch_users - 1)
	if hatch_users == 0:
		host.get_tree().create_timer(1.0).timeout.connect(_hatch_try_close)


func _hatch_try_close() -> void:
	if hatch_users == 0:
		_tween_hatch(0.0)


func hatch_hold(i: int) -> void:
	while hatch_held.size() <= i:
		hatch_held.append(false)
	if not hatch_held[i]:
		hatch_held[i] = true
		hatch_acquire()


func hatch_drop(i: int) -> void:
	if i < hatch_held.size() and hatch_held[i]:
		hatch_held[i] = false
		hatch_release()


# ================= финальный выезд =================
const CAR_AXLE := 1.6                        # половина базы машины: от центра до оси колёс

var _driving := false
var _car_from := Vector2(-8.0, 2.0)  # где стояла машина перед выездом (x, z)
var _departed := false
var _riders: Array = []
var _riders_left := 0
var _cam_tween: Tween


# Сначала все выжившие и герой идут к машине и садятся, потом открываются ворота и она уезжает
func start_drive() -> void:
	if _driving:
		return
	_driving = true
	_departed = false
	_car_from = Vector2(car.position.x, car.position.z)  # машину могли переставить в редакторе
	Game.cinematic = true
	host.player_ctl.path.clear()
	host.player_ctl.pending_body = null
	host.staff.labels_visible(false)
	_auto_gate_move(true)
	# камера плавно переезжает к машине
	_cam_tween = host.create_tween()
	_cam_tween.tween_property(host.camera.rig, "position", Vector3(car.position.x, WorldConfig.FLOOR, car.position.z), 1.2).set_ease(Tween.EASE_IN_OUT)
	_riders.clear()
	var slot := 0
	# герой
	var hp := _board_points(host.player.position, slot)
	slot += 1
	var ptw := host.staff._walk_tween(host.player, hp, 6.5)
	ptw.tween_interval(0.01)
	_riders.append(host.player)
	ptw.finished.connect(_rider_in.bind(host.player))
	# сотрудники, которые сейчас в бункере
	for i in host.staff.wnodes.size():
		var w: Dictionary = Game.workers[i]
		if w.dead or w.away != null:
			continue
		var n: Node3D = host.staff.wnodes[i]
		# спящих поднимаем с кровати
		if i < host.rest.sleep_st.size() and host.rest.sleep_st[i] != 0:
			if host.rest.sleep_tw[i] != null and (host.rest.sleep_tw[i] as Tween).is_valid():
				(host.rest.sleep_tw[i] as Tween).kill()
			host.rest.sleep_tw[i] = null
			host.rest.sleep_st[i] = 0
			n.rotation = Vector3.ZERO
			n.position.y = WorldConfig.H
		n.visible = true
		host.staff.anim[i] = true
		var pts := _board_points(n.position, slot)
		slot += 1
		var tw := host.staff.walk_w(i, pts, 6.5)
		_riders.append(n)
		tw.finished.connect(_rider_in.bind(n))
	_riders_left = _riders.size()
	# страховка: если кто-то застрял по дороге, всё равно уезжаем
	host.get_tree().create_timer(9.0).timeout.connect(_depart)


# Путь к машине: к её борту (с южной стороны), затем внутрь
func _board_points(from: Vector3, slot: int) -> Array:
	var side := Vector3(_car_from.x + (float(slot % 5) - 2.0) * 0.55, WorldConfig.H, _car_from.y + 2.1 + float(slot / 5) * 0.6)
	var pts: Array = host.nav.path(from, side)
	pts.append(Vector3(_car_from.x + (float(slot % 5) - 2.0) * 0.3, WorldConfig.H, _car_from.y + 0.7))
	return pts


func _rider_in(n: Node3D) -> void:
	if is_instance_valid(n):
		n.visible = false  # сел в машину
	_riders_left -= 1
	if _riders_left <= 0:
		_depart()


func _depart() -> void:
	if _departed:
		return
	_departed = true
	for n in _riders:
		if is_instance_valid(n):
			(n as Node3D).visible = false
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	var tw := host.create_tween()
	tw.tween_interval(0.8)  # ворота уже открыты (поднимаются с начала посадки)
	tw.tween_method(_drive_step, 0.0, 1.0, 9.0)
	tw.finished.connect(_drive_end)


# Высота дороги в точке x: пол у x=-14, поверхность у x=-26 (рампа длиной 12 м и подъёмом 3 м)
func _ramp_h(x: float) -> float:
	return 3.0 * clampf((-14.0 - x) / 12.0, 0.0, 1.0)


func _drive_step(s: float) -> void:
	var k := s * s * 0.6 + s * 0.4  # плавный разгон
	var x := lerpf(_car_from.x, -34.0, k)
	# высота и наклон — по обеим осям колёс, поэтому машина идёт по склону, а не сквозь него
	var hf := _ramp_h(x - CAR_AXLE)
	var hr := _ramp_h(x + CAR_AXLE)
	car.position = Vector3(x, WorldConfig.FLOOR + (hf + hr) * 0.5, lerpf(_car_from.y, 2.75, minf(s * 4.0, 1.0)))
	car.rotation.z = -atan2(hf - hr, CAR_AXLE * 2.0)
	host.camera.rig.position = car.position


func _drive_end() -> void:
	Game.cinematic = false
	Game.drive_out()


func look_door() -> void:
	# кинематика: камера подходит к воротам (где бы они ни стояли) и смотрит
	# в смотровое окно на гостя; подписи объектов прячем, чтобы ничего не мешало
	if door_cinematic:
		return
	door_cinematic = true
	Game.cinematic = true
	host.camera._saved_cam = {"p": host.camera.rig.position, "yaw": host.camera.yaw, "pitch": host.camera.pitch_deg, "dist": host.camera.dist}
	host.player_ctl.path.clear()
	host.player_ctl.pending_body = null
	host.staff.labels_visible(false)
	var ow := outward()
	# мировая позиция смотрового окна — дырка в полотне (окно в 0.5 м от центра ворот)
	var wp := (door_body as Node3D).global_transform * Vector3(0.5, 1.35, 0.0)
	var look_pos := wp - ow * 0.55
	var look_yaw := atan2(-ow.x, -ow.z)
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(host.camera.rig, "position", look_pos, 1.1).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(host.camera.rig, "rotation:y", look_yaw, 1.1)
	tw.tween_property(host.camera.pitch, "rotation_degrees:x", -2.0, 1.1)
	tw.tween_property(host.camera.cam, "position:z", 1.2, 1.1)
	tw.chain().tween_interval(0.9)
	tw.chain().tween_callback(func():
		if not Game.visitor.is_empty():
			host.ui.show_npc_bar(host.camera.cam, host.staff.visitor_node)
		elif not Game.gate_event.is_empty():
			host.ui.show_gate_bar(host.camera.cam, host.staff.stranger_node)
		else:
			host.ui.show_trader_bar(host.camera.cam, host.staff.trader_node))


func gate_move(is_open: bool) -> void:
	if gates_leaf == null or not is_instance_valid(gates_leaf):
		return
	if gate_tween:
		gate_tween.kill()
	gate_tween = host.create_tween()
	# Полотно поворачивается вокруг петли у левого края: 0° — закрыто, 92° — внутрь.
	var target := deg_to_rad(92.0) if is_open else 0.0
	gate_tween.tween_property(gates_leaf, "rotation:y", target, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Snd.play("hatch")


func _auto_gate_move(up: bool) -> void:
	if auto_leaf == null or not is_instance_valid(auto_leaf):
		return
	if auto_gate_tween:
		auto_gate_tween.kill()
	auto_gate_tween = host.create_tween()
	auto_gate_tween.tween_property(auto_leaf, "position:y", 4.0 if up else 0.0, 1.6).set_ease(Tween.EASE_IN_OUT)
	Snd.play("hatch")


func on_auto_gate() -> void:
	if Game.gen_broken:
		host.ui.toast("Ворота для машины обесточены: сначала почините генератор.")
		Snd.play("click")
		return
	if not Game.car_done():
		var cnt: int = Game.car.values().count(true)
		host.ui.toast("Машина не готова: детали %d из 4 (верстак). Ворота откроются, когда она будет собрана." % cnt)
		Snd.play("click")
		return
	start_drive()


func sync_car() -> void:
	car_wheels.visible = Game.car.wheels
	car_engine.visible = Game.car.engine
	car_battery.visible = Game.car.battery
	car_tank.visible = Game.car.tank
	car_cabin.visible = Game.car_done()
