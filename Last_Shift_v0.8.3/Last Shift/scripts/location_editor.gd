@tool
class_name LocationEditor
extends RefCounted
## Режим F: выбор, перенос, поворот и удаление предметов прямо в игре.

var host: BunkerWorld
var edit_mode := false
var edit_selected := {}
var edit_drag := false
var edit_drag_off := Vector3.ZERO
var edit_drag_plane := Plane(Vector3.UP, 0.0)
var edit_pick_point := Vector3.ZERO
var edit_prev_paused := false
var sel_box: MeshInstance3D
var edit_panel: PanelContainer
var edit_list: ItemList
var edit_entries: Array = []

func _init(h: BunkerWorld) -> void:
	host = h


func _pick_item(pos: Vector2) -> Dictionary:
	var from := host.camera.cam.project_ray_origin(pos)
	var dir := host.camera.cam.project_ray_normal(pos)
	var best := {}
	var best_d := INF
	for it in host.layout.editor_items:
		var n: Node3D = it.node
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		# Групповые AABB перехватывают клики в пустом пространстве.
		# Выбираем поверхность; группы по-прежнему доступны в списке.
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or absf(mi.global_transform.basis.determinant()) < 0.000001:
			continue
		var inverse := mi.global_transform.affine_inverse()
		var local_from := inverse * from
		var local_dir := inverse.basis * dir
		if mi.mesh.get_aabb().intersects_ray(local_from, local_dir) == null:
			continue
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(local_from, local_dir, faces[i], faces[i + 1], faces[i + 2])
			if hit == null:
				continue
			var d: float = from.distance_to(mi.global_transform * (hit as Vector3))
			if d < best_d:
				best_d = d
				best = it
				edit_pick_point = mi.global_transform * (hit as Vector3)
	return best


func _edit_panel_build() -> void:
	if edit_panel != null:
		edit_panel.show()
		return
	edit_panel = PanelContainer.new()
	edit_panel.position = Vector2(12, 82)
	edit_panel.custom_minimum_size = Vector2(310, 440)
	host.ui.add_child(edit_panel)
	var column := VBoxContainer.new()
	edit_panel.add_child(column)
	var title := Label.new()
	title.text = "Объекты сцены (включая скрытые)"
	column.add_child(title)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск объекта…"
	column.add_child(search)
	edit_list = ItemList.new()
	edit_list.custom_minimum_size = Vector2(300, 340)
	edit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(edit_list)
	search.text_changed.connect(_edit_list_refresh)
	edit_list.item_selected.connect(func(index: int):
		edit_selected = edit_entries[index]
		edit_drag = false
	)
	var show_button := Button.new()
	show_button.text = "Показать / скрыть выбранный"
	show_button.pressed.connect(func():
		if edit_selected != {} and is_instance_valid(edit_selected.node):
			var n: Node3D = edit_selected.node
			host.layout.set_user_hidden(n, n.visible)
			host.layout.layout_store()
	)
	column.add_child(show_button)
	_edit_list_refresh("")


func _edit_list_refresh(filter: String) -> void:
	edit_list.clear()
	edit_entries.clear()
	for it in host.layout.editor_items:
		if not is_instance_valid(it.node):
			continue
		var label := String(host.get_path_to(it.node))
		if filter != "" and not label.to_lower().contains(filter.to_lower()):
			continue
		edit_entries.append(it)
		edit_list.add_item(label)


func _enter_edit() -> void:
	edit_mode = true
	edit_prev_paused = Game.paused
	Game.paused = true
	_sel_box_init()
	_edit_panel_build()
	host.ui.toast("Редактор включён: ЛКМ — выбрать и тащить · F — выход")


func _exit_edit() -> void:
	if edit_panel != null:
		edit_panel.hide()
	edit_mode = false
	edit_selected = {}
	edit_drag = false
	if sel_box != null:
		sel_box.visible = false
	Game.paused = edit_prev_paused
	host.layout.layout_store()
	host.nav.build_astar()


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
	host.add_child(sel_box)


func _edit_move(it: Dictionary, delta: Vector3) -> void:
	var n: Node3D = it.node
	var mv: Node3D = it.mv
	if not is_instance_valid(mv):
		return
	mv.global_position += delta
	if it.pickable and n.has_meta("stand"):
		n.set_meta("stand", (n.get_meta("stand") as Vector3) + delta)


func _edit_update_box() -> void:
	if sel_box == null:
		return
	if edit_selected == {} or not is_instance_valid(edit_selected.node) or not (edit_selected.node as Node3D).visible:
		sel_box.visible = false
		return
	var n: Node3D = edit_selected.node
	var ab := host.layout.item_aabb(n)
	if ab.size == Vector3.ZERO:
		sel_box.visible = false
		return
	sel_box.visible = true
	sel_box.position = ab.get_center()
	sel_box.scale = ab.size + Vector3(0.12, 0.12, 0.12)


func edit_reset() -> void:
	for it in host.layout.editor_items:
		var mv: Node3D = it.mv
		if not is_instance_valid(mv):
			continue
		var delta: Vector3 = (it.orig as Vector3) - mv.position
		mv.position = it.orig
		mv.rotation = it.orig_r
		mv.scale = it.orig_s
		host.layout.set_user_hidden(it.node, false)
		(it.node as Node3D).visible = it.orig_visible
		if it.pickable and (it.node as Node3D).has_meta("stand"):
			(it.node as Node3D).set_meta("stand", ((it.node as Node3D).get_meta("stand") as Vector3) + delta)
	edit_selected = {}
	edit_drag = false
	if sel_box != null:
		sel_box.visible = false
	host.layout.layout_store()
	host.nav.build_astar()


func edit_finish_drag() -> void:
	if edit_drag:
		edit_drag = false
		host.layout.layout_store()


func edit_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_F, KEY_ESCAPE:
				_exit_edit()
			KEY_Z:
				if edit_selected != {}:
					(edit_selected.mv as Node3D).rotation.y += deg_to_rad(15.0)
					host.layout.layout_store()
			KEY_X:
				if edit_selected != {}:
					(edit_selected.mv as Node3D).rotation.y -= deg_to_rad(15.0)
					host.layout.layout_store()
			KEY_DELETE:
				if edit_selected != {}:
					edit_finish_drag()
					host.layout.set_user_hidden(edit_selected.node, true, true)
					edit_selected = {}
					if sel_box != null:
						sel_box.visible = false
					host.layout.layout_store()
					host.nav.build_astar()
			KEY_EQUAL, KEY_MINUS:
				if edit_selected != {}:
					var mv: Node3D = edit_selected.mv
					mv.scale *= 1.1 if e.physical_keycode == KEY_EQUAL else 1.0 / 1.1
					host.layout.layout_store()
			KEY_BACKSPACE:
				edit_reset()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		host.camera.dist_target = clampf(host.camera.dist_target - 2.5, 9.0, 44.0)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		host.camera.dist_target = clampf(host.camera.dist_target + 2.5, 9.0, 44.0)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var it := _pick_item(e.position)
			edit_selected = it
			edit_drag = false
			if it != {}:
				var focus := host.get_viewport().gui_get_focus_owner()
				if focus != null:
					focus.release_focus()
				var n: Node3D = it.mv
				# Плоскость через точку захвата, а не удалённый центр GLB.
				edit_drag_plane = Plane(Vector3.UP, edit_pick_point.y)
				edit_drag_off = n.global_position - edit_pick_point
				edit_drag = true
			_edit_update_box()
		else:
			edit_finish_drag()
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		host.camera.yaw = clampf(host.camera.yaw - e.relative.x * 0.006, -1.2, 1.2)
		host.camera.pitch_deg = clampf(host.camera.pitch_deg - e.relative.y * 0.3, -78.0, -30.0)
		host.camera.rig.rotation.y = host.camera.yaw
		host.camera.pitch.rotation_degrees.x = host.camera.pitch_deg
	elif e is InputEventMouseMotion and edit_drag and edit_selected != {} and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var n: Node3D = edit_selected.mv
		var h: Variant = edit_drag_plane.intersects_ray(host.camera.cam.project_ray_origin(e.position), host.camera.cam.project_ray_normal(e.position))
		if h != null:
			var target: Vector3 = (h as Vector3) + edit_drag_off
			var np := n.global_position
			np.x = snappedf(target.x, 0.25) if e.shift_pressed else target.x
			np.z = snappedf(target.z, 0.25) if e.shift_pressed else target.z
			_edit_move(edit_selected, np - n.global_position)
			_edit_update_box()


func _edit_keys(dt: float) -> void:
	if host.get_viewport().gui_get_focus_owner() is LineEdit:
		return
	# камера
	if Input.is_physical_key_pressed(KEY_Q):
		host.camera.yaw += dt * 1.2
	if Input.is_physical_key_pressed(KEY_R):
		host.camera.yaw -= dt * 1.2
	host.camera.yaw = clampf(host.camera.yaw, -1.2, 1.2)
	host.camera.rig.rotation.y = host.camera.yaw
	host.camera.dist = lerpf(host.camera.dist, host.camera.dist_target, minf(1.0, 10.0 * dt))
	host.camera.cam.position.z = host.camera.dist
	# Во время переноса мышью высота фиксирована; клавиши не сдвигают захват.
	if edit_drag:
		return
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
		var d3 := host.camera.rig.transform.basis * Vector3(v.x, 0, v.z)
		d3.y = 0.0
		delta += d3.normalized() * 3.0 * dt
	if Input.is_physical_key_pressed(KEY_PAGEUP):
		delta.y += 1.2 * dt
	if Input.is_physical_key_pressed(KEY_PAGEDOWN):
		delta.y -= 1.2 * dt
	if delta != Vector3.ZERO:
		_edit_move(edit_selected, delta)


# Режим редактора: обновление выделения и подсказки на каждом кадре
func edit_tick(delta: float) -> void:
	_edit_keys(delta)
	_edit_update_box()
	if host.ui != null:
		var s := "РЕДАКТОР: ЛКМ — выбрать и тащить · стрелки — двигать · PgUp/PgDn — высота · Z/X — поворот · +/− — масштаб · Delete — убрать · Backspace — сброс · F/Esc — выход"
		if edit_selected != {} and is_instance_valid(edit_selected.node):
			s = "Выделено: %s · %s" % [(edit_selected.node as Node3D).name, s]
		host.ui.set_hint(s)


func toggle_edit() -> void:
	if edit_mode:
		_exit_edit()
	else:
		_enter_edit()
