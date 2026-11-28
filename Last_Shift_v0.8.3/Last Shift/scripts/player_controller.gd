@tool
class_name PlayerController
extends RefCounted
## Герой: ввод, ходьба по клику, выбор и использование объектов.

const M := preload("res://scripts/models.gd")
var host: BunkerWorld
var path: Array = []
var pending_body: Node3D = null
var blocked_body: Node3D = null
var rmb_hold_walk := false
var hold_btn: MouseButton = MOUSE_BUTTON_RIGHT
var rmb_cd := 0.0
var walked := false
const HOT_ORDER := ["garden", "kitchen", "inv", "bench", "exp", "bed", "furnace", "shredder", "medbed", "medcab"]

func _init(h: BunkerWorld) -> void:
	host = h


func _screen_rect(n: Node3D) -> Rect2:
	if not n.is_visible_in_tree():
		return Rect2()  # мёртвый сотрудник или спрятанный объект не ловит клики
	var half: Vector3 = n.get_meta("size") * 0.5
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for ax in [-1.0, 1.0]:
		for ay in [-1.0, 1.0]:
			for az in [-1.0, 1.0]:
				var wp: Vector3 = n.global_transform * Vector3(ax * half.x, ay * half.y, az * half.z)
				if host.camera.cam.is_position_behind(wp):
					return Rect2()
				var sp := host.camera.cam.unproject_position(wp)
				mn = Vector2(minf(mn.x, sp.x), minf(mn.y, sp.y))
				mx = Vector2(maxf(mx.x, sp.x), maxf(mx.y, sp.y))
	return Rect2(mn, mx - mn).grow(6.0)


func _pick_at(pos: Vector2) -> Node3D:
	var best: Node3D = null
	var best_area := INF
	for n in host.interactables:
		var r := _screen_rect(n)
		if r.has_point(pos) and r.get_area() < best_area:
			best_area = r.get_area()
			best = n
	return best


func _dist_stand(n: Node3D) -> float:
	var st: Vector3 = n.get_meta("stand")
	return Vector2(host.player.position.x - st.x, host.player.position.z - st.z).length()


func _nearest(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for n in host.interactables:
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
	if act == "door":
		if Game.visitor == {} and Game.trader.is_empty():
			host.ui.toast("За воротами тихо — никого нет.")
			Snd.play("click")
		else:
			host.gates.look_door()
	elif act == "autogate":
		host.gates.on_auto_gate()
	else:
		host.ui.open_modal(act)


func _interact(n: Node3D) -> void:
	pending_body = n
	if _dist_stand(n) < 1.0:
		_trigger(n)
		return
	path = host.nav.path(host.player.position, n.get_meta("stand"))


# Ввод героя: горячие клавиши станций, E, клики по полу и объектам, СКМ — поворот камеры
func play_input(e: InputEvent) -> void:
	if Game.end_state != "" or Game.cinematic:
		return
	# на паузе (Space) героя не двигаем и ничего не открываем; камера (поворот) работает
	if Game.paused and (e is InputEventKey or (e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT))):
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
			var b: Node3D = host.builder.hot_bodies.get(HOT_ORDER[idx], null)
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
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT:
				if Game.modal_open:
					return
				rmb_hold_walk = false
				var obj := _pick_at(e.position)
				if obj != null:
					_interact(obj)
				else:
					_start_hold_walk(e.position, e.button_index)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		host.camera.yaw = clampf(host.camera.yaw - e.relative.x * 0.006, -1.2, 1.2)
		host.camera.pitch_deg = clampf(host.camera.pitch_deg - e.relative.y * 0.3, -78.0, -30.0)
		host.camera.rig.rotation.y = host.camera.yaw
		host.camera.pitch.rotation_degrees.x = host.camera.pitch_deg


# нажали на пол: идём туда, а пока кнопка зажата — следуем за курсором
func _start_hold_walk(pos: Vector2, btn: MouseButton) -> void:
	var h: Variant = host.camera.floor_hit(pos)
	if h != null and host.nav.walk_ok(h.x, h.z) and (h.z < 15.4 or (h.x > 9.0 and h.x < 11.0 and h.z < 18.2)):
		hold_btn = btn
		rmb_hold_walk = true
		rmb_cd = 0.0
		pending_body = null
		path = host.nav.path(host.player.position, h)


# пока зажата кнопка мыши (ЛКМ или ПКМ), персонаж идёт к курсору
func _rmb_follow(delta: float) -> void:
	if not rmb_hold_walk:
		return
	if not Input.is_mouse_button_pressed(hold_btn) or Game.modal_open or Game.cinematic or Game.end_state != "" or host.editor.edit_mode:
		rmb_hold_walk = false
		return
	rmb_cd -= delta
	if rmb_cd > 0.0:
		return
	rmb_cd = 0.08
	var h: Variant = host.camera.floor_hit(host.get_viewport().get_mouse_position())
	if h != null and host.nav.walk_ok(h.x, h.z) and (h.z < 15.4 or (h.x > 9.0 and h.x < 11.0 and h.z < 18.2)):
		if Vector2(h.x - host.player.position.x, h.z - host.player.position.z).length() > 0.3:
			pending_body = null
			path = host.nav.path(host.player.position, h)


func _move_player(delta: float) -> void:
	if path.is_empty() and pending_body == null and host.nav.astar != null:
		var pc := host.nav.cell(host.player.position)
		if host.nav.astar.is_point_solid(pc):
			var fc := host.nav.free_cell(pc)
			if fc != pc:
				var fp := host.nav.cell_pos(fc)
				if Vector2(fp.x - host.player.position.x, fp.z - host.player.position.z).length() < 1.6:
					host.player.position = Vector3(fp.x, WorldConfig.H, fp.z)
	if pending_body != null and _dist_stand(pending_body) < 1.0:
		_trigger(pending_body)
		return
	if path.is_empty():
		return
	var target: Vector3 = path[0]
	var d := Vector3(target.x - host.player.position.x, 0, target.z - host.player.position.z)
	if d.length() < 0.12:
		path.pop_front()
		if path.is_empty() and pending_body != null:
			_trigger(pending_body)
		return
	var spd_mult := 1.0
	if Game.player_food <= 0:
		spd_mult = 0.7  # голодный ходишь медленнее
	if Game.player_st < 25:
		spd_mult = 0.55  # без сна еле ногами перебираешь
	var spd := (10.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.5) * spd_mult
	host.player.position += d.normalized() * minf(spd * delta, d.length())
	host.player.rotation.y = lerp_angle(host.player.rotation.y, atan2(-d.x, -d.z), minf(1.0, 14.0 * delta))


# Ходьба героя, анимация героя
func update_player(delta: float) -> void:
	walked = false
	if Game.paused:
		path.clear()
		pending_body = null
		rmb_hold_walk = false
	else:
		_rmb_follow(delta)
		_move_player(delta)
	var tt := Time.get_ticks_msec() / 1000.0
	M.animate(host.player, tt, walked or not path.is_empty())
	if blocked_body != null and _dist_stand(blocked_body) > 2.4:
		blocked_body = null


# Подписи объектов при наведении и подсказка внизу экрана
func update_hover() -> void:
	# подписи объектов всегда белые и видимые; при наведении — толще обводка
	var hovered: Node3D = null
	if not Game.modal_open and not Game.cinematic:
		hovered = _pick_at(host.get_viewport().get_mouse_position())
	for n in host.interactables:
		if not n.has_meta("label"):
			continue
		var l: Label3D = n.get_meta("label")
		l.modulate = Color(1, 1, 1, 1)
		l.outline_size = 22 if n == hovered else 10
	if host.ui != null:
		var txt := ""
		if not Game.modal_open and not Game.cinematic:
			if hovered != null:
				txt = String(hovered.get_meta("hint"))
			else:
				var nb := _nearest(1.6)
				if nb != null:
					txt = "E — " + String(nb.get_meta("hint"))
		host.ui.set_hint(txt)
