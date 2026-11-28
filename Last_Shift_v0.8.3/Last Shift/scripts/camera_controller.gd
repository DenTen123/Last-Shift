@tool
class_name CameraController
extends RefCounted
## Камера: фиксированный зум, поворот (Q/R, СКМ), центрирование на герое (C), возврат после кинематики.

var host: BunkerWorld
var rig: Node3D
var pitch: Node3D
var cam: Camera3D
var dist := 32.0
var dist_target := 32.0  # зум остаётся только для редактора локации (F)
var busy := false  # идёт кинематика или возврат камеры: ввод в неё не вмешивается
var _centered := false
var _c_down := false
var yaw := 0.0
var pitch_deg := -55.0
var _saved_cam := {}

func _init(h: BunkerWorld) -> void:
	host = h


func build_camera() -> void:
	rig = Node3D.new()
	rig.position = Vector3(0, WorldConfig.FLOOR, 4)
	host.add_child(rig)
	pitch = Node3D.new()
	pitch.rotation_degrees.x = pitch_deg
	rig.add_child(pitch)
	cam = Camera3D.new()
	cam.position.z = dist
	cam.fov = 50.0
	cam.far = 300.0
	pitch.add_child(cam)
	cam.make_current()


func floor_hit(pos: Vector2) -> Variant:
	var from := cam.project_ray_origin(pos)
	return Plane(Vector3.UP, WorldConfig.FLOOR).intersects_ray(from, cam.project_ray_normal(pos))


func restore_cam() -> void:
	busy = true
	var tw := host.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rig, "position", _saved_cam.p, 0.9).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(rig, "rotation:y", _saved_cam.yaw, 0.9)
	tw.tween_property(pitch, "rotation_degrees:x", _saved_cam.pitch, 0.9)
	tw.tween_property(cam, "position:z", _saved_cam.dist, 0.9)
	tw.chain().tween_callback(func():
		pitch_deg = _saved_cam.pitch
		yaw = _saved_cam.yaw
		dist = _saved_cam.dist
		busy = false)


func camera_input(delta: float) -> void:
	if busy:
		return
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += delta * 1.2
	if Input.is_physical_key_pressed(KEY_R):
		yaw -= delta * 1.2
	yaw = clampf(yaw, -1.2, 1.2)
	rig.rotation.y = yaw
	cam.position.z = dist
	if Input.is_physical_key_pressed(KEY_C):
		if not _c_down:
			_c_down = true
			_centered = not _centered
			if _centered:
				rig.position = Vector3(host.player.position.x, WorldConfig.FLOOR, host.player.position.z)
			else:
				rig.position = Vector3(0, WorldConfig.FLOOR, 4)
	else:
		_c_down = false
	rig.position.x = clampf(rig.position.x, -34.0, 34.0)
	rig.position.z = clampf(rig.position.z, -12.0, 18.0)
