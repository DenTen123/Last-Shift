@tool
class_name PathNavigator
extends RefCounted
## Препятствия, сетка A* и поиск путей.

var host: BunkerWorld
var obstacles: Array = []
var astar: AStarGrid2D
# ================= движение по ПКМ =================
const CS := 0.5
const GW := 86  # + клетки под пристройку комнаты отдыха на востоке
const GH := 49
const PLAYER_R := 0.4

func _init(h: BunkerWorld) -> void:
	host = h


func _obs(x: float, z: float, sx: float, sz: float) -> void:
	obstacles.append(Rect2(x - sx / 2.0, z - sz / 2.0, sx, sz))


func register_obstacles() -> void:
	# стены теперь — редактируемые куски: их препятствия считаются из позиций узлов
	for z in [-1.5, 1.5]:
		for x in [-2.0, 0.5, 3.5, 8.5, 11.5]:
			_obs(x, z, 0.3, 0.3)
	for z in [3.2, 5.8]:
		_obs(6, z, 0.3, 0.3)
	for x in [-9.5, -6.5, 2.8, 5.8, 8.5, 11.5]:
		_obs(x, 8.0, 0.3, 0.3)
	_obs(8.8, 17.3, 0.5, 2.9)
	_obs(11.2, 17.3, 0.5, 2.9)
	_obs(10, 18.55, 1.7, 0.5)


func cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi((p.x + 14.0) / CS), 0, GW - 1), clampi(roundi((p.z + 8.0) / CS), 0, GH - 1))


func cell_pos(c: Vector2i) -> Vector3:
	return Vector3(-14.0 + c.x * CS, WorldConfig.H, -8.0 + c.y * CS)


# кровати — твёрдые: по каждой построенной кровати своя область (проход между кроватями ряда остаётся)
func _bed_rects() -> Array:
	var out: Array = []
	for i in Game.beds:
		var c := host.rest.bed_slot(i)
		out.append(Rect2(c.x - 0.85, c.z - 1.325, 1.7, 2.65))
	return out


# Зоны коллизии предметов в плоскости XZ: учитывают поворот, масштаб и смещение центра
func _item_rects() -> Array:
	var out: Array = []
	for it in host.layout.editor_items:
		var ob: Vector3 = it.obs
		if ob.x <= 0.0:
			continue
		var mvn: Node3D = it.mv
		if not is_instance_valid(mvn) or not (it.node as Node).visible:
			continue
		var off: Vector2 = it.get("obs_off", Vector2.ZERO)
		var tf := mvn.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for kx in [-0.5, 0.5]:
			for kz in [-0.5, 0.5]:
				var p: Vector3 = tf * Vector3(off.x + ob.x * kx, 0.0, off.y + ob.y * kz)
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		out.append(Rect2(lo, hi - lo))
	return out


func build_astar() -> void:
	var bed_rects := _bed_rects()
	var item_rects := _item_rects()
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, GW, GH)
	astar.cell_size = Vector2(CS, CS)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for x in GW:
		for y in GH:
			var pt := cell_pos(Vector2i(x, y))
			var solid := pt.x < -13.6 or pt.z < -7.6 or pt.z > 15.6 or (pt.x > 13.6 and not (pt.x < WorldConfig.REST_X1 - 0.4 and pt.z > WorldConfig.REST_Z0 + 0.4 and pt.z < WorldConfig.REST_Z1 - 0.4))
			# тамбур южного входа проходим
			if solid and pt.x > 8.9 and pt.x < 11.1 and pt.z > 15.6 and pt.z < 18.4:
				solid = false
			if not solid:
				for r in obstacles:
					if (r as Rect2).grow(PLAYER_R).has_point(Vector2(pt.x, pt.z)):
						solid = true
						break
			if not solid:
				for br in bed_rects:
					if (br as Rect2).grow(PLAYER_R).has_point(Vector2(pt.x, pt.z)):
						solid = true
						break
			if not solid:
				for ir in item_rects:
					if (ir as Rect2).grow(PLAYER_R).has_point(Vector2(pt.x, pt.z)):
						solid = true
						break
			astar.set_point_solid(Vector2i(x, y), solid)


func _build_nav() -> void:
	register_obstacles()
	build_astar()


func _solid_at(p: Vector3) -> bool:
	if p.x < -13.4 or p.z < -7.4:
		return true
	if p.x > 13.4 and not (p.x < WorldConfig.REST_X1 - 0.2 and p.z > WorldConfig.REST_Z0 + 0.2 and p.z < WorldConfig.REST_Z1 - 0.2):
		return true
	if p.z > 15.4:
		return not (p.x > 8.9 and p.x < 11.1 and p.z < 18.3)  # тамбур проходим
	return astar.is_point_solid(cell(p))


func free_cell(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 12):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= GW or n.y >= GH:
					continue
				if astar.is_point_solid(n):
					continue
				var d := float(dx * dx + dy * dy)
				if d < bd:
					bd = d
					best = n
		if best.x >= 0:
			return best
	return c


func _los(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.2) + 1
	for i in range(n + 1):
		if astar.is_point_solid(cell(a.lerp(b, float(i) / float(n)))):
			return false
	return true


func path(a: Vector3, b: Vector3) -> Array:
	var ia := free_cell(cell(a))
	var ib0 := cell(b)
	var ib := free_cell(ib0)
	var raw: Array = []
	for c in astar.get_id_path(ia, ib):
		raw.append(cell_pos(c))
	if raw.is_empty():
		return []
	if ib == ib0:
		raw[raw.size() - 1] = Vector3(b.x, WorldConfig.H, b.z)
	var out: Array = []
	var i := 0
	while i < raw.size() - 1:
		var j: int = raw.size() - 1
		while j > i + 1 and not _los(raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	if out.is_empty():
		out.append(raw[raw.size() - 1])
	return out


func walk_ok(x: float, z: float) -> bool:
	if x < -13.4 or z < -7.4:
		return false
	if x > 13.4:
		return x < WorldConfig.REST_X1 - 0.4 and z > WorldConfig.REST_Z0 + 0.4 and z < WorldConfig.REST_Z1 - 0.4
	return true
