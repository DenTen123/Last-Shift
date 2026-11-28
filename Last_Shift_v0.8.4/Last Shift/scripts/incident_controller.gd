@tool
class_name IncidentController
extends RefCounted
## Поломки в бункере: маркеры-«горячие точки» над местом аварии (течь, замыкание, заклинившая дверь).
## Маркеры кликабельны: E открывает окно ремонта. В редакторе Godot не создаются.

const M := preload("res://scripts/models.gd")
var host: BunkerWorld
var markers: Array = []  # {"id", "node"}

# места аварий: высота pos — над полом бункера (FLOOR), stand — точка (x, z), куда встаёт игрок
const SPOTS := [
	{"pos": Vector3(-12.0, 1.0, 3.0), "stand": Vector2(-10.5, 3.0)},
	{"pos": Vector3(-4.0, 1.1, -6.3), "stand": Vector2(-4.0, -4.8)},
	{"pos": Vector3(2.0, 1.2, 14.6), "stand": Vector2(2.0, 13.2)},
	{"pos": Vector3(11.6, 1.1, 6.0), "stand": Vector2(10.1, 6.0)},
	{"pos": Vector3(8.6, 1.1, -6.4), "stand": Vector2(8.6, -5.0)},
	{"pos": Vector3(4.2, 1.2, 3.6), "stand": Vector2(4.2, 2.2)},
]

func _init(h: BunkerWorld) -> void:
	host = h


func sync() -> void:
	if Engine.is_editor_hint():
		return
	# убрать маркеры исчезнувших аварий: сразу вычищаем из interactables,
	# иначе клик по queue_free-узлу роняет движок до конца кадра
	var alive: Array = []
	for m in markers:
		var found := false
		for inc in Game.incidents:
			if inc.id == m.id:
				found = true
				break
		if found:
			alive.append(m)
		elif is_instance_valid(m.node):
			host.interactables.erase(m.node)
			m.node.queue_free()
	markers = alive
	for inc in Game.incidents:
		if _marker(int(inc.id)) != null:
			continue
		_spawn_marker(inc)


func clear_markers() -> void:
	for m in markers:
		if is_instance_valid(m.node):
			host.interactables.erase(m.node)
			m.node.queue_free()
	markers.clear()


func _marker(id: int) -> Node3D:
	for m in markers:
		if m.id == id and is_instance_valid(m.node):
			return m.node
	return null


func _spawn_marker(inc: Dictionary) -> void:
	var spot: Dictionary = SPOTS[clampi(int(inc.spot), 0, SPOTS.size() - 1)]
	var body := Node3D.new()
	body.position = Vector3(spot.pos.x, WorldConfig.FLOOR + float(spot.pos.y), spot.pos.z)
	var col := Color(0.4, 0.6, 0.95) if inc.kind == "leak" else (Color(0.95, 0.62, 0.15) if inc.kind == "wire" else Color(0.85, 0.25, 0.2))
	M.box(body, Vector3(0.42, 0.42, 0.42), Vector3(0, 0.35, 0), col, true)
	var l := Label3D.new()
	l.text = Game.INC_KINDS[inc.kind] + "!"
	l.font_size = 44
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 12
	l.modulate = col
	l.position = Vector3(0, 1.05, 0)
	body.add_child(l)
	body.set_meta("label", l)
	body.set_meta("act", "inc:%d" % int(inc.id))
	body.set_meta("hint", "%s: нажмите E, чтобы открыть окно ремонта." % Game.INC_KINDS[inc.kind])
	var st: Vector2 = spot.stand
	body.set_meta("stand", Vector3(st.x, WorldConfig.H, st.y))
	body.set_meta("size", Vector3(1.0, 1.5, 1.0))
	_fx(body, String(inc.kind))
	host.add_child(body)
	host.interactables.append(body)
	markers.append({"id": inc.id, "node": body})


func _fx(body: Node3D, kind: String) -> void:
	var pm := ParticleProcessMaterial.new()
	if kind == "leak":
		pm.direction = Vector3(0, -1, 0)
		pm.gravity = Vector3(0, -6.0, 0)
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 0.9
		pm.color = Color(0.45, 0.65, 0.9)
	elif kind == "wire":
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 65.0
		pm.gravity = Vector3(0, -2.0, 0)
		pm.initial_velocity_min = 1.2
		pm.initial_velocity_max = 2.6
		pm.color = Color(1.0, 0.8, 0.3)
	else:
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 40.0
		pm.gravity = Vector3(0, -0.5, 0)
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.0
		pm.color = Color(0.62, 0.62, 0.62)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.75)
	mesh.material = m
	var pr := GPUParticles3D.new()
	pr.process_material = pm
	pr.draw_pass_1 = mesh
	pr.amount = 14
	pr.lifetime = 1.2
	pr.position = Vector3(0, 0.4, 0)
	pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pr.emitting = true
	body.add_child(pr)
