@tool
class_name SceneLayout
extends RefCounted
## Реестр предметов сцены, применение сохранённой раскладки, слежение за правками в редакторе Godot.

var host: BunkerWorld
var _edit_poll_acc := 0.0
# редактор локации
var editor_items: Array = []  # {"node", "name", "obs": Vector3(sx, sz, 0), "pickable", "orig", "orig_ry"}
# узлы, которые пользователь скрыл сам (Delete / кнопка / глаз в редакторе). Игровая логика
# (постройки, детали машины, «призраки») скрывает узлы по своим причинам — это НЕ пишется в раскладку.
var hidden_nodes: Array = []
var _owned := false
var _loaded_post_rev := 0
var _loaded_fix_rev := 0
# Свет и окружение настраиваются вручную в редакторе Godot отдельно для каждого времени суток (пресеты).
const PHASES := ["night", "morning", "day", "evening"]
const EDITOR_AMBIENT := 0.6
const LIGHT_PROPS := ["light_energy", "light_indirect_energy", "light_volumetric_fog_energy", "light_color",
	"light_specular", "light_angular_distance", "shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur"]
const OMNI_PROPS := ["omni_range", "omni_attenuation"]
const SPOT_PROPS := ["spot_range", "spot_angle", "spot_attenuation", "spot_angle_attenuation"]
const DIR_PROPS := ["directional_shadow_max_distance", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3", "rotation_degrees"]
const ENV_PROPS := ["background_color", "fog_light_color", "fog_density", "ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution", "glow_enabled", "glow_intensity",
	"glow_bloom", "glow_strength", "ssao_enabled", "ssao_radius", "ssao_intensity", "fog_enabled", "tonemap_mode",
	"tonemap_exposure", "tonemap_white", "adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation"]
var _extra_last: Dictionary = {}
var _tod: Dictionary = {}  # пресеты времени суток: фаза -> {"env": {...}, "lights": {имя предмета: {...}}}
# удалённые предметы: в редакторе их узлы вырезаются из сцены, поэтому пометку "del" храним отдельно и пишем обратно
var _deleted_loaded: Dictionary = {}

func reset_registry() -> void:
	editor_items.clear()
	hidden_nodes.clear()
	_owned = false


# Предмет «удалён» в редакторе Godot, если его вынули из дерева сцены (Delete) или освободили.
func _is_gone(it: Dictionary) -> bool:
	if not bool(it.get("seen", false)):
		return false
	var mv: Variant = it.mv
	if not is_instance_valid(it.node):
		return true
	return not is_instance_valid(mv) or not (mv as Node3D).is_inside_tree()


func _in_tree(it: Dictionary) -> bool:
	var mv: Variant = it.mv
	return is_instance_valid(it.node) and is_instance_valid(mv) and (mv as Node3D).is_inside_tree()


# Клик во вьюпорте Godot работает только через «гизмо» узла. Гизмо запрашивается в момент входа узла в дерево;
# если в этот момент сцена ещё не стала редактируемой, узел остаётся без гизмо: он виден и есть в списке,
# но по нему нельзя кликнуть. Здесь (когда edited_scene_root уже известен) такие узлы заново входят в дерево,
# на прежнем месте в порядке детей, чтобы индексы раскладки не сдвинулись.
func _collect_no_gizmo(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).get_gizmos().is_empty():
			out.append(c)
		_collect_no_gizmo(c, out)


func _ensure_gizmos() -> int:
	var list: Array = []
	_collect_no_gizmo(host, list)
	for n in list:
		var parent: Node = n.get_parent()
		var idx: int = n.get_index()
		parent.remove_child(n)
		parent.add_child(n)
		parent.move_child(n, idx)
	return list.size()


# Каждый узел сцены должен быть в доке «Сцена»: owner получают ВСЕ потомки, а не только зарегистрированные предметы.
func _own_subtree(n: Node, root: Node, stat: Dictionary) -> void:
	for c in n.get_children():
		if String(c.name).begins_with("@"):
			# безымянные узлы (@Node3D@123) нельзя найти в доке — даём понятное имя
			if c is MeshInstance3D:
				c.name = "Блок"
			elif c is CollisionShape3D:
				c.name = "Коллизия"
			elif c is Node3D:
				c.name = "Узел"
			else:
				c.name = c.get_class()
		if c.owner != root:
			c.owner = root
			stat.fixed += 1
		stat.total += 1
		_own_subtree(c, root, stat)


func _set_collision(n: Node, on: bool) -> void:
	if n is CollisionObject3D:
		var co := n as CollisionObject3D
		if on:
			if co.has_meta("orig_cl"):
				co.collision_layer = int(co.get_meta("orig_cl"))
				co.collision_mask = int(co.get_meta("orig_cm"))
		else:
			if not co.has_meta("orig_cl"):
				co.set_meta("orig_cl", co.collision_layer)
				co.set_meta("orig_cm", co.collision_mask)
			co.collision_layer = 0
			co.collision_mask = 0
	for c in n.get_children():
		_set_collision(c, on)


# deleted = true: предмет удалён (не просто скрыт): без видимости и без коллизий; в раскладку пишется "del"
func set_user_hidden(n: Node3D, hide: bool, deleted := false) -> void:
	var was_deleted := bool(n.get_meta("user_deleted", false))
	n.set_meta("user_hidden", hide)
	n.set_meta("user_deleted", hide and deleted)
	if deleted or was_deleted:
		_set_collision(n, not (hide and deleted))
	if hide:
		n.visible = false
		if not hidden_nodes.has(n):
			hidden_nodes.append(n)
	else:
		n.visible = true
		hidden_nodes.erase(n)


# вызывается каждый кадр и после синхронизации с Game: игровая логика не «воскрешает» скрытое вами
func enforce_hidden() -> void:
	for n in hidden_nodes:
		if is_instance_valid(n) and (n as Node3D).visible:
			(n as Node3D).visible = false


func editor_flush() -> void:
	# При сохранении сцены (Ctrl+S, F5, закрытие редактора) раскладка пишется ВСЕГДА и целиком,
	# а не только если слежение заметило изменение.
	if host == null or not host.is_inside_tree() or editor_items.is_empty():
		return
	layout_store()
	_extra_last = _extra_snapshot()

func _init(h: BunkerWorld) -> void:
	host = h


func item(n: Node3D, item_name: String, obs := Vector3.ZERO, pickable := false) -> void:
	n.name = WorldConfig.ITEM_RU.get(item_name, item_name)  # русское имя в доке «Сцена»
	# если тело вложено в другой узел (например, автомобиль) — двигать и считать
	# препятствие нужно по родителю, иначе коллайдер окажется не там
	var mv := n
	if pickable and n.get_parent() is Node3D and n.get_parent() != host:
		mv = n.get_parent()
	editor_items.append(_item_record(n, mv, item_name, obs, pickable))


# Зона коллизии предмета: размер (x, z) и смещение от центра узла (в его локальных осях)
func set_obstacle(item_name: String, size: Vector2, off := Vector2.ZERO) -> void:
	var rec := item_by_name(item_name)
	if rec.is_empty():
		return
	rec["obs"] = Vector3(size.x, size.y, 0.0)
	rec["obs_off"] = off


func _item_record(n: Node3D, mv: Node3D, key: String, obs := Vector3.ZERO, pickable := false) -> Dictionary:
	var rec := {"node": n, "mv": mv, "name": key, "obs": obs, "pickable": pickable,
		"orig": mv.position, "orig_r": mv.rotation, "orig_s": mv.scale, "orig_visible": n.visible}
	if mv is Light3D:
		rec["orig_energy"] = (mv as Light3D).light_energy
		rec["orig_color"] = (mv as Light3D).light_color
	return rec


# Базовые значения света в редакторе (после editor_look) — от них считаются множители для игры.
func rebase_light(l: Light3D) -> void:
	for it in editor_items:
		if it.mv == l:
			it["orig_energy"] = l.light_energy
			it["orig_color"] = l.light_color


func register_scene_items(parent: Node, prefix := "scene") -> void:
	# Индексы в исходном дереве стабильны между запусками; имена @Node3D@ — нет.
	var index := 0
	for child in parent.get_children():
		var key := "%s/%d" % [prefix, index]
		# Новая геометрия не должна получать преобразования старых деталей по индексу.
		# Явные ключи мебели и исходный файл раскладки остаются без изменений.
		if child.has_meta("layout_revision"):
			key += "/" + String(child.get_meta("layout_revision"))
		index += 1
		if child is Node3D and not child is Label3D:
			var registered := false
			for it in editor_items:
				if it.node == child or it.mv == child:
					registered = true
					break
			if not registered:
				editor_items.append(_item_record(child, child, key))
		register_scene_items(child, key)


# ================= редактирование в редакторе Godot =================
## Предметы выдаются в док «Сцена» (owner = корень сцены): их можно выбирать
## и двигать стандартным гизмо. Каждые 0.5 с изменения фиксируются в раскладке.
func editor_own_items() -> void:
	var root := host.get_tree().edited_scene_root
	if root == null:
		return
	_owned = true
	for it in editor_items:
		it.seen = _in_tree(it)
		it.saved_gone = false
		if not it.seen:
			continue
		var mv: Node3D = it.mv
		if is_instance_valid(mv):
			var ancestor: Node = mv
			while ancestor != host and ancestor != null:
				ancestor.owner = root
				ancestor = ancestor.get_parent()
			it.saved_p = mv.position
			it.saved_r = mv.rotation
			it.saved_s = mv.scale
			it.saved_hidden = not (it.node as Node3D).visible
	_extra_last = _extra_snapshot()
	var regizmo := _ensure_gizmos()
	var stat := {"total": 0, "fixed": 0}
	_own_subtree(host, root, stat)
	print("Сцена: узлов %d, предметов раскладки %d, владелец назначен %d узлам, без гизмо (клик во вьюпорте) пересоздано %d" % [stat.total, editor_items.size(), stat.fixed, regizmo])


func editor_poll(delta: float) -> void:
	_edit_poll_acc += delta
	if _edit_poll_acc < 0.2:
		return
	_edit_poll_acc = 0.0
	if not _owned:
		# edited_scene_root мог появиться позже одного кадра — тогда правки вообще не фиксировались
		editor_own_items()
		if not _owned:
			return
	if not host.is_inside_tree():
		return  # сцена не активна (вкладка другой сцены): её узлы временно вне дерева — это не удаление
	var dirty := false
	for it in editor_items:
		if not bool(it.get("seen", false)) and _in_tree(it):
			it.seen = true
			var mv0: Node3D = it.mv
			it.saved_p = mv0.position
			it.saved_r = mv0.rotation
			it.saved_s = mv0.scale
			it.saved_hidden = not (it.node as Node3D).visible
		if not bool(it.get("seen", false)) and (not is_instance_valid(it.mv) or not is_instance_valid(it.node)):
			continue  # предмет удалён раньше, чем был замечен (например, помечен "del" в раскладке)
		var gone := _is_gone(it)
		if gone != bool(it.get("saved_gone", false)):
			it.saved_gone = gone  # предмет удалили (или вернули через Ctrl+Z)
			dirty = true
		if gone:
			continue
		var mv: Node3D = it.mv
		var hidden: bool = not (it.node as Node3D).visible
		if bool(it.get("saved_hidden", false)) != hidden:
			it.saved_hidden = hidden
			dirty = true
		var sp: Vector3 = it.get("saved_p", mv.position)
		var sr: Vector3 = it.get("saved_r", mv.rotation)
		var ss: Vector3 = it.get("saved_s", mv.scale)
		if mv.position != sp or (mv.rotation - sr).length() > 0.0001 or mv.scale != ss:
			it.saved_p = mv.position
			it.saved_r = mv.rotation
			it.saved_s = mv.scale
			dirty = true
	var extra := _extra_snapshot()
	if extra != _extra_last:
		_extra_last = extra  # поменяли свет или окружение
		dirty = true
	if dirty:
		layout_store()


# ================= свет и окружение =================
func _pack(v: Variant) -> Variant:
	if v is Color:
		var c := v as Color
		return [c.r, c.g, c.b, c.a]
	if v is Vector3:
		var vv := v as Vector3
		return [vv.x, vv.y, vv.z]
	return v


func _unpack(cur: Variant, v: Variant) -> Variant:
	if cur is Color and v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	if cur is Vector3 and v is Array and (v as Array).size() == 3:
		var b: Array = v
		return Vector3(float(b[0]), float(b[1]), float(b[2]))
	if cur is int and v is float:
		return int(v)
	return v


func unpack_value(cur: Variant, v: Variant) -> Variant:
	return _unpack(cur, v)


func _light_props(l: Light3D) -> Array:
	var props: Array = LIGHT_PROPS.duplicate()
	if l is OmniLight3D:
		props.append_array(OMNI_PROPS)
	elif l is SpotLight3D:
		props.append_array(SPOT_PROPS)
	elif l is DirectionalLight3D:
		props.append_array(DIR_PROPS)
	return props


func _light_dump(l: Light3D) -> Dictionary:
	var d := {}
	for p in _light_props(l):
		d[p] = _pack(l.get(p))
	return d


func _env_dump() -> Dictionary:
	var d := {}
	var e: Environment = host.weather.env
	if e == null:
		return d
	for p in ENV_PROPS:
		d[p] = _pack(e.get(p))
	return d


# ---------- пресеты времени суток ----------
# Ваши значения для фазы p (пусто — значит действуют умолчания из WeatherSystem)
func tod_user(p: int) -> Dictionary:
	return _tod.get(PHASES[p], {})


# Живые значения узлов (то, что сейчас стоит в редакторе)
func _tod_dump() -> Dictionary:
	var lights := {}
	for it in editor_items:
		if is_instance_valid(it.mv) and it.mv is Light3D:
			lights[it.name] = _light_dump(it.mv)
	return {"env": _env_dump(), "lights": lights}


# Старая раскладка хранила одну общую настройку света: переносим её в каждую фазу,
# кроме яркости и цвета солнца и ламп (их раньше задавал код)
func _tod_from_legacy(data: Dictionary, items: Dictionary) -> Dictionary:
	var env_d: Dictionary = (data.get("env", {}) as Dictionary).duplicate(true)
	env_d.erase("ambient_light_energy")
	var lights := {}
	for it in editor_items:
		if not items.has(it.name) or not (items[it.name] as Dictionary).has("light") or not (it.mv is Light3D):
			continue
		var ld: Dictionary = (items[it.name].light as Dictionary).duplicate(true)
		if it.mv == host.weather.sun or host.weather.omnis.has(it.mv):
			ld.erase("light_energy")
			ld.erase("light_color")
		lights[it.name] = ld
	if env_d.is_empty() and lights.is_empty():
		return {}
	var out := {}
	for ph in PHASES:
		out[ph] = {"env": env_d.duplicate(true), "lights": lights.duplicate(true)}
	return out


# Редактор Godot: переключили фазу — сохраняем правки прежней и показываем новую
func tod_switch(old_phase: int, new_phase: int) -> void:
	if not Engine.is_editor_hint() or host.weather.env == null:
		return
	_tod[PHASES[old_phase]] = _tod_dump()
	host.weather.invalidate_presets()
	host.weather.apply_preset_now(new_phase)
	_extra_last = _extra_snapshot()
	layout_store()


func _extra_snapshot() -> Dictionary:
	if not Engine.is_editor_hint():
		return {}
	var lights := {}
	for it in editor_items:
		if is_instance_valid(it.mv) and it.mv is Light3D:
			lights[it.name] = _light_dump(it.mv)
	return {"lights": lights, "env": _env_dump()}


# ================= редактор локации (в игре, F) =================
func item_by_name(item_name: String) -> Dictionary:
	for it in editor_items:
		if it.name == item_name:
			return it
	return {}


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func item_aabb(n: Node3D) -> AABB:
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


func layout_store() -> void:
	var items := {}
	var editing := Engine.is_editor_hint()
	for it in editor_items:
		if _deleted_loaded.has(it.name):
			var still_deleted: bool = editing or not is_instance_valid(it.node) or not is_instance_valid(it.mv) \
				or bool((it.node as Node3D).get_meta("user_deleted", false))
			if still_deleted:
				items[it.name] = _deleted_loaded[it.name]
				continue
		if editing and _is_gone(it):
			var op: Vector3 = it.get("saved_p", it.orig)
			var orr: Vector3 = it.get("saved_r", it.orig_r)
			var osc: Vector3 = it.get("saved_s", it.orig_s)
			items[it.name] = {
				"del": true,
				"p": [op.x, op.y, op.z],
				"r": [rad_to_deg(orr.x), rad_to_deg(orr.y), rad_to_deg(orr.z)],
				"s": [osc.x, osc.y, osc.z],
			}
			continue
		if not is_instance_valid(it.mv):
			continue
		var mv: Node3D = it.mv
		if true:
			items[it.name] = {
				"p": [mv.position.x, mv.position.y, mv.position.z],
				"r": [rad_to_deg(mv.rotation.x), rad_to_deg(mv.rotation.y), rad_to_deg(mv.rotation.z)],
				"s": [mv.scale.x, mv.scale.y, mv.scale.z],
				# в редакторе Godot видимость целиком в ваших руках; в игре пишем только осознанное скрытие
				"hide": (not (it.node as Node3D).visible) if Engine.is_editor_hint() else bool((it.node as Node3D).get_meta("user_hidden", false)),
			}
			if not editing and bool((it.node as Node3D).get_meta("user_deleted", false)):
				items[it.name]["del"] = true
	var tod: Dictionary = _tod.duplicate(true)
	if editing and host.weather.env != null:
		tod[PHASES[host.edit_phase]] = _tod_dump()  # правки идут в пресет выбранной фазы
	host.store.layout_save({"v": 3, "rest_rev": WorldConfig.REST_REV, "post_rev": WorldConfig.POST_REV, "fix_rev": WorldConfig.FIX_REV, "items": items, "tod": tod})


func layout_apply() -> void:
	_layout_apply_saved()
	_post_layout()
	host.weather.invalidate_presets()
	if Engine.is_editor_hint():
		host.weather.apply_preset_now(host.edit_phase)
		_extra_last = _extra_snapshot()


# То, что должно действовать независимо от сохранённой раскладки.
func _post_layout() -> void:
	# Эти правки нужны только раскладкам, сохранённым до POST_REV. Как только раскладка пересохранена,
	# ваши положения люка, коек и земли применяются без подмены.
	if _loaded_post_rev != WorldConfig.POST_REV:
		_post_layout_legacy()
	if _loaded_fix_rev != WorldConfig.FIX_REV:
		_post_layout_fixes()
	host.rest.rest_diag()


# Исправления для раскладок, сохранённых до FIX_REV. Не трогают то, что вы уже переставили сами.
func _post_layout_fixes() -> void:
	# ворота для машины должны стоять поперёк дороги (раньше полотно и стойки лежали вдоль неё — прямо по ходу машины)
	var ag := item_by_name("Ворота для машины")
	if not ag.is_empty() and is_instance_valid(ag.mv) and absf(wrapf((ag.mv as Node3D).rotation.y, -PI, PI)) < 0.05:
		(ag.mv as Node3D).rotation.y = PI / 2.0
	# кофемашина висела в воздухе рядом с новым маленьким столиком: ставим её на столик
	var cf := item_by_name("coffee")
	if not cf.is_empty() and is_instance_valid(cf.mv) and ((cf.mv as Node3D).position as Vector3).distance_to(WorldConfig.COFFEE_POS_OLD) < 0.05:
		(cf.mv as Node3D).position = WorldConfig.COFFEE_POS


func _post_layout_legacy() -> void:
	# люк: шарнир с другой стороны, крышка открывается в обратную сторону
	if host.gates.hatch != null and is_instance_valid(host.gates.hatch):
		host.gates.hatch.position.x = -14.0
		host.gates.hatch.rotation.z = 0.0
		if host.gates.hatch.get_child_count() > 0:
			(host.gates.hatch.get_child(0) as Node3D).position.x = -6.0
	# «Койки» стояли у восточной стены старой части и перегораживали проход: переносим в пристройку
	var bunk := item_by_name("Койки")
	if not bunk.is_empty() and is_instance_valid(bunk.mv) and (bunk.mv as Node3D).position.x < 14.0:
		(bunk.mv as Node3D).position = Vector3(WorldConfig.BED_X0, (bunk.mv as Node3D).position.y, WorldConfig.BED_ZC)
		(bunk.mv as Node3D).rotation = Vector3.ZERO
		if bunk.node.has_meta("stand"):
			bunk.node.set_meta("stand", Vector3(WorldConfig.BED_X0 - 1.7, WorldConfig.H, WorldConfig.BED_ZC))
	# старая восточная стена земли мешает пристройке комнаты отдыха
	var old_earth := item_by_name("Земля 5")
	if not old_earth.is_empty() and is_instance_valid(old_earth.node):
		(old_earth.node as Node3D).visible = false


func _apply_deleted(mv: Node3D, n: Node3D) -> void:
	if Engine.is_editor_hint():
		# в редакторе предмет действительно убираем из сцены, как будто его удалили вручную
		if mv.is_inside_tree() and mv != host and mv.get_parent() != null:
			mv.get_parent().remove_child(mv)
			mv.queue_free()
		return
	# в игре объекты нужны другим системам (props, interactables), поэтому прячем и отключаем коллизии
	for t in [n, mv]:
		set_user_hidden(t, true, true)


func _layout_apply_saved() -> void:
	_loaded_post_rev = 0
	_loaded_fix_rev = 0
	hidden_nodes.clear()
	var data := host.store.layout_load()
	if data.is_empty():
		return
	_loaded_post_rev = int(data.get("post_rev", 0))
	_loaded_fix_rev = int(data.get("fix_rev", 0))
	var items: Dictionary = data.get("items", {})
	_deleted_loaded.clear()
	_tod = (data.get("tod", {}) as Dictionary).duplicate(true)
	if _tod.is_empty():
		_tod = _tod_from_legacy(data, items)
	# Старая раскладка хранила прежние позиции коек и стен комнаты отдыха. Пока раскладка не пересохранена
	# с текущей версией, эти объекты остаются там, где их ставит код; после первой правки (F или редактор)
	# версия записывается, и дальше ваши перемещения сохраняются как обычно.
	var reset_rest := int(data.get("rest_rev", 0)) != WorldConfig.REST_REV
	var rest_roots: Array = []
	if reset_rest:
		var bb: Node = host.builder.hot_bodies.get("bed", null)
		if bb != null:
			rest_roots.append(bb)
		for bn in host.rest.bed_nodes:
			rest_roots.append(bn)
		for rb in host.rest.rest_boxes:
			rest_roots.append(rb.node)
	for it in editor_items:
		if not items.has(it.name):
			continue
		if reset_rest and host.rest.in_rest_group(it.node, rest_roots):
			continue
		var rec: Dictionary = items[it.name]
		var mv: Node3D = it.mv
		var n: Node3D = it.node
		if not is_instance_valid(mv):
			continue
		if bool(rec.get("del", false)):
			_deleted_loaded[it.name] = rec
			_apply_deleted(mv, n)
			continue
		var p: Array = rec.p
		var np := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var delta := np - (mv.position as Vector3)
		var r: Array = rec.get("r", [0.0, float(rec.get("ry", 0.0)), 0.0])
		mv.position = np
		mv.rotation = Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2])))
		var sc: Array = rec.get("s", [mv.scale.x, mv.scale.y, mv.scale.z])
		mv.scale = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))
		# старое поле "hidden" игнорируем: оно смешивало ваше скрытие с «ещё не построено»
		var hide := bool(rec.get("hide", false))
		n.set_meta("user_hidden", hide)
		if hide:
			n.visible = false
			hidden_nodes.append(n)
		elif Engine.is_editor_hint():
			n.visible = true
		if it.pickable and n.has_meta("stand"):
			n.set_meta("stand", (n.get_meta("stand") as Vector3) + delta)
