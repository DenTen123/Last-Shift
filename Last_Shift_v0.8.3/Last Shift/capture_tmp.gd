extends SceneTree

var world: Node

func _initialize() -> void:
	_start.call_deferred()

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("user://shots/%s.png" % name)
	print("SHOT ", name, " ", img.get_width(), "x", img.get_height())

func _add_worker() -> void:
	Game.workers.clear()
	Game.workers.append({
		"name": "Глеб", "prof": "engineer", "cap": 4, "eff": 1.1,
		"st": 100, "hp": 100, "sick": false, "away": null, "dead": false,
		"xp": 0, "lvl": 1, "suit": Color(0.3, 0.45, 0.6),
		"maniac": false, "kill_at": 999999, "bed": 0, "asleep": false,
		"nobed": false, "nosleep": 0,
	})
	Game.npc_pool = [1, 2, 3]
	Game.changed.emit()

func _start() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var packed := load("res://main.tscn") as PackedScene
	world = packed.instantiate()
	root.add_child(world)
	for i in 30:
		await process_frame
	# Let the intro overlay fade.
	await create_timer(11.0).timeout
	for i in 10:
		await process_frame
	_shot("01_main")

	_add_worker()
	await create_timer(0.5).timeout
	var ui = world.ui
	ui.open_modal("exp")
	await create_timer(0.8).timeout
	_shot("02_exp_modal")

	ui.pick_pack = true
	ui.refresh()
	await create_timer(0.5).timeout
	_shot("03_exp_ready")

	var ok: bool = Game.send(0, true, "")
	print("SEND ", ok)
	ui.modal = ""
	ui.refresh()
	await create_timer(0.8).timeout
	_shot("04_sent")

	# Fast-forward the 180-minute expedition for the still.
	if ok:
		Game.advance(180)
	await create_timer(1.0).timeout
	_shot("05_result")

	# Rest room, data-driven bed count.
	world.camera.rig.position = Vector3(18.5, -3.0, 3.2)
	world.camera.rig.rotation.y = -0.15
	world.camera.pitch.rotation_degrees.x = -55.0
	world.camera.pitch_deg = -55.0
	world.camera.dist_target = 18.0
	world.camera.dist = 18.0
	world.camera.cam.position.z = 18.0
	Game.beds = 2
	world.rest.sync_beds()
	await create_timer(1.3).timeout
	_shot("06_beds_before")

	Game.beds = 3
	world.rest.sync_beds()
	await create_timer(1.3).timeout
	_shot("07_beds_after")

	Game.beds = 2
	world.rest.sync_beds()
	await create_timer(0.5).timeout

	print("DONE")
	quit(0)
