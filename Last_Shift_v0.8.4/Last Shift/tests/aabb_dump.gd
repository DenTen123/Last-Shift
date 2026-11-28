extends SceneTree
## Разовый замер: локальные AABB моделей (кушетка, карта_на_стене).
## Запуск: godot --headless --path . --script res://tests/aabb_dump.gd

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	create_timer(20.0).timeout.connect(func(): quit(2))


func _run() -> void:
	for mname in ["кушетка", "updated/кушетка", "карта_на_стене", "метеостанция"]:
		var ps: PackedScene = load("res://models/%s.glb" % mname)
		if ps == null:
			print(mname, ": НЕ НАЙДЕНА")
			continue
		var inst := ps.instantiate() as Node3D
		root.add_child(inst)
		var aabb := _local(inst, Transform3D.IDENTITY)
		print("%s | pos=%s size=%s center=%s" % [mname, aabb.position, aabb.size, aabb.get_center()])
	quit(0)


func _local(n: Node, xf: Transform3D) -> AABB:
	var res := AABB()
	var has := false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		res = xf * (n as MeshInstance3D).get_aabb()
		has = true
	for ch in n.get_children():
		var cx := xf
		if ch is Node3D:
			cx = xf * (ch as Node3D).transform
		var b := _local(ch, cx)
		if b.size == Vector3.ZERO:
			continue
		res = b if not has else res.merge(b)
		has = true
	return res
