@tool
class_name StationController
extends RefCounted
## Станции (грядка, кухня, печь...): постройка, обновление, эффекты.

const M := preload("res://scripts/models.gd")
var host: BunkerWorld
var stations: Array = []
const STATIONS := [
	{"id": "garden", "title": "Грядка", "empty": "Пусто: нужна грядка", "pos": Vector3(-8, -2.6, 12.5), "size": Vector3(6.0, 0.8, 1.6), "stand": Vector3(-8, -2.1, 10.6), "act": "garden", "hint": "Грядка: посадить и собрать картошку."},
	{"id": "kitchen", "title": "Кухня", "empty": "Пусто: нужна кухня", "pos": Vector3(10.2, -2.1, -4.6), "size": Vector3(2.4, 1.4, 1.6), "stand": Vector3(10.2, -2.1, -2.9), "act": "kitchen", "hint": "Кухня: картошка — в еду или в бензин."},
	{"id": "furnace", "title": "Плавильная печь", "empty": "Пусто: нужна печь", "pos": Vector3(0.5, -2.1, 12.5), "size": Vector3(2.2, 1.8, 2.0), "stand": Vector3(0.5, -2.1, 10.4), "act": "furnace", "hint": "Плавильная печь: сталь и топливные брикеты."},
	{"id": "shredder", "title": "Измельчитель", "empty": "Пусто: нужен измельчитель", "pos": Vector3(3.8, -2.3, 13.0), "size": Vector3(2.0, 1.4, 1.6), "stand": Vector3(3.8, -2.1, 11.0), "act": "shredder", "hint": "Измельчитель: платы и пластик."},
	{"id": "medbed", "title": "Кушетка", "empty": "Пусто: нужна кушетка", "pos": Vector3(12.4, -2.55, 12.8), "size": Vector3(1.8, 0.9, 3.0), "obs": Vector2(2.75, 2.95), "obs_off": Vector2(0.145, 0.0), "stand": Vector3(10.4, -2.1, 12.8), "act": "medbed", "hint": "Больничная кушетка: лечение людей."},
	{"id": "medcab", "title": "Аптечный шкаф", "empty": "Пусто: нужен шкаф", "pos": Vector3(8.2, -2.0, 15.4), "size": Vector3(2.2, 2.0, 0.8), "stand": Vector3(8.2, -2.1, 13.8), "act": "medcab", "hint": "Аптечный шкаф: делает аптечки."},
]

func _init(h: BunkerWorld) -> void:
	host = h


func build_stations() -> void:
	var none := Color(0, 0, 0, 0)
	for d in STATIONS:
		var body := host.builder.pickable(d.title, d.size, d.pos, none, d.act, d.hint, d.stand, null, true)
		if d.has("obs"):
			# зона коллизии по реальному габариту модели (она крупнее и смещена от центра)
			host.layout.set_obstacle(d.title, d.obs, d.get("obs_off", Vector2.ZERO))
		var parts := M.station(body, d.id, d.size)
		stations.append({"body": body, "id": d.id, "d": d, "parts": parts})
		host.builder.hot_bodies[d.id] = body
	# дым из трубы печи — идёт, когда печь построена
	host.builder.furnace_smoke = GPUParticles3D.new()
	host.builder.furnace_smoke.position = Vector3(1.1, -1.0, 12.8)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.gravity = Vector3(0, 0.9, 0)
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color = Color(0.6, 0.6, 0.64)
	host.builder.furnace_smoke.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.5)
	mesh.material = m
	host.builder.furnace_smoke.draw_pass_1 = mesh
	host.builder.furnace_smoke.amount = 12
	host.builder.furnace_smoke.lifetime = 2.4
	host.builder.furnace_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.builder.furnace_smoke.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	host.builder.furnace_smoke.emitting = false
	host.add_child(host.builder.furnace_smoke)


func update_stations() -> void:
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


func on_station_used(id: String) -> void:
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
		var m := M.box(host, Vector3(0.16, 0.16, 0.16), pos + Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.1), randf_range(-0.25, 0.25)), col, true)
		var tw := host.create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position:y", m.position.y + randf_range(1.0, 1.6), 1.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3(0.1, 0.1, 0.1), 1.1)
		tw.chain().tween_callback(m.queue_free)
