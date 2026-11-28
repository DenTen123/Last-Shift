extends Node
## Автозагрузка "Game": всё состояние и логика (время, погода, экспедиции, крафт, прокачка, гости).

signal changed
signal worker_left(i: int)
signal worker_back(i: int, ok: bool)
signal npc_arrived(npc_name: String, status: String)
signal npc_done(accepted: bool)
signal station_used(id: String)
signal reset_layout

const RAW := ["metal", "plastic", "wire", "fuel", "rubber"]
const RES := {"metal": "Металл", "plastic": "Пластик", "wire": "Провод", "fuel": "Топливо", "rubber": "Резина",
	"steel": "Сталь", "chips": "Платы", "seeds": "Семена", "potato": "Картошка", "food": "Еда", "herbs": "Травы", "medkit": "Аптечки"}
# Постройки для комнат: создаются на верстаке и появляются в комнате
const BUILD := {
	"garden": {"name": "Грядка", "desc": "Комната грядок: картошка и лечебные травы.", "cost": {"metal": 4, "plastic": 3, "rubber": 2}},
	"lamp": {"name": "Лампа роста", "desc": "Растения растут на 30% быстрее.", "cost": {"wire": 2, "plastic": 2, "chips": 1}, "needs": "garden"},
	"irrig": {"name": "Система полива", "desc": "Ещё на 30% быстрее и +1 к урожаю.", "cost": {"rubber": 3, "metal": 2, "wire": 1}, "needs": "garden"},
	"kitchen": {"name": "Кухня", "desc": "Картошка: в еду или в бензин (биотопливо).", "cost": {"metal": 5, "plastic": 2, "wire": 2}},
	"furnace": {"name": "Плавильная печь", "desc": "Переработка: сталь и топливные брикеты.", "cost": {"metal": 6, "fuel": 2, "plastic": 1}},
	"shredder": {"name": "Измельчитель", "desc": "Переработка: платы и пластик.", "cost": {"metal": 5, "wire": 3, "plastic": 1}},
	"medbed": {"name": "Медицинская кушетка", "desc": "Лечение травм, аптечки против болезни.", "cost": {"metal": 3, "plastic": 2, "wire": 1}},
	"medcab": {"name": "Аптечный шкаф", "desc": "Делает аптечки из трав.", "cost": {"metal": 2, "plastic": 3, "steel": 1}},
	"filter": {"name": "Фильтр воздуха", "desc": "Шанс заболеть после вылазки: 25% → 8%.", "cost": {"metal": 4, "chips": 1, "plastic": 2}},
	"insul": {"name": "Утепление люка", "desc": "Риск травмы на поверхности −40%.", "cost": {"rubber": 4, "metal": 3}},
	"coffee": {"name": "Кофемашина", "desc": "Каждое утро +12 выносливости всем дома.", "cost": {"metal": 3, "plastic": 2, "chips": 1}},
}
# Улучшения построек: два уровня для каждой (индекс = текущий уровень постройки − 1)
const UPGRADES := {
	"garden": [
		{"name": "Грядка ур.2 — быстрый рост", "desc": "растения зреют на 25% быстрее", "cost": {"metal": 4, "plastic": 3, "rubber": 2}},
		{"name": "Грядка ур.3 — большой урожай", "desc": "+2 картошки к каждому урожаю", "cost": {"metal": 6, "steel": 2, "chips": 1}},
	],
	"kitchen": [
		{"name": "Кухня ур.2 — скороварка", "desc": "рецепты на 40% быстрее", "cost": {"metal": 4, "wire": 2}},
		{"name": "Кухня ур.3 — конвейер", "desc": "+1 к выходу еды и топлива", "cost": {"metal": 6, "chips": 2, "steel": 1}},
	],
	"furnace": [
		{"name": "Печь ур.2 — жар", "desc": "переработка на 40% быстрее", "cost": {"metal": 5, "steel": 2}},
		{"name": "Печь ур.3 — рекуператор", "desc": "+1 к выходу стали и брикетов", "cost": {"metal": 8, "steel": 3, "chips": 2}},
	],
	"shredder": [
		{"name": "Измельчитель ур.2", "desc": "переработка на 40% быстрее", "cost": {"metal": 5, "wire": 2}},
		{"name": "Измельчитель ур.3", "desc": "+1 к выходу плат и пластика", "cost": {"metal": 7, "chips": 2, "steel": 1}},
	],
	"medbed": [
		{"name": "Кушетка ур.2", "desc": "лечение +50 за сеанс", "cost": {"metal": 4, "plastic": 3}},
		{"name": "Кушетка ур.3", "desc": "лечение +70 и +20 выносливости", "cost": {"metal": 6, "chips": 2, "steel": 1}},
	],
	"medcab": [
		{"name": "Шкаф ур.2", "desc": "аптечка: 1 травы вместо 2", "cost": {"plastic": 4, "steel": 1}},
		{"name": "Шкаф ур.3", "desc": "аптечка без пластика", "cost": {"chips": 2, "steel": 2}},
	],
}
const PROC := {
	"food": {"station": "kitchen", "name": "Еда из картошки", "cost": {"potato": 2}, "out": {"food": 4}, "min": 60},
	"biofuel": {"station": "kitchen", "name": "Бензин из картошки", "cost": {"potato": 3}, "out": {"fuel": 2}, "min": 90},
	"steel": {"station": "furnace", "name": "Выплавить сталь", "cost": {"metal": 3, "fuel": 1}, "out": {"steel": 1}, "min": 40},
	"briquette": {"station": "furnace", "name": "Топливные брикеты", "cost": {"rubber": 3}, "out": {"fuel": 2}, "min": 30},
	"chip": {"station": "shredder", "name": "Собрать плату", "cost": {"wire": 2, "plastic": 1}, "out": {"chips": 1}, "min": 30},
	"plastic": {"station": "shredder", "name": "Пластик из резины", "cost": {"rubber": 2}, "out": {"plastic": 1}, "min": 20},
}
const CROPS := {"potato": {"name": "Картошка", "out": {"potato": 6, "seeds": 1}}, "herbs": {"name": "Лечебные травы", "out": {"herbs": 3, "seeds": 1}}}
const MEDKIT_COST := {"herbs": 2, "plastic": 1}
const XP_NEED := [40, 90, 150, 230]  # опыт для ур.2, 3, 4, 5
const MIN_HP := 40
const PH := ["Ночь", "Утро", "День", "Вечер"]
const GEAR := {
	"pack": {"name": "Рюкзак", "desc": "вместимость +4", "cost": {"metal": 3, "plastic": 2}},
	"magnet": {"name": "Магнит", "desc": "чаще приносит металл и провод", "cost": {"metal": 2, "wire": 2}},
	"drill": {"name": "Бур", "desc": "чаще приносит топливо и резину", "cost": {"metal": 4, "rubber": 2}},
}
const CAR := {
	"engine": {"name": "Двигатель", "cost": {"metal": 6, "wire": 3, "fuel": 2, "steel": 2}},
	"wheels": {"name": "Колёса", "cost": {"rubber": 6, "metal": 2}},
	"battery": {"name": "Аккумулятор", "cost": {"wire": 4, "plastic": 3, "chips": 2}},
	"tank": {"name": "Топливный бак", "cost": {"fuel": 6, "plastic": 2, "steel": 1}},
}
const EXPEDITION_MIN := 180
const MIN_STAMINA := 30
const MAX_WORKERS := 10
const SAVE_PATH := "user://save.json"
const GEN_COST := {"metal": 2}

# Профессии гостей и их эффекты
const PROFS := {
	"engineer": {"name": "Инженер", "desc": "вылазки чаще приносят металл, провод и платы"},
	"mechanic": {"name": "Механик", "desc": "вылазки чаще приносят металл, резину и топливо"},
	"agronom": {"name": "Агроном", "desc": "сам сажает и собирает грядку"},
	"cook": {"name": "Повар", "desc": "еда из картошки +1"},
	"medic": {"name": "Медик", "desc": "лечение кушеткой и аптечкой сильнее"},
	"chemist": {"name": "Химик", "desc": "бензин из картошки и брикеты +1"},
	"radio_tech": {"name": "Радиотехник", "desc": "радио бодрит сильнее, платы +1"},
	"hunter": {"name": "Охотник", "desc": "может принести еду с поверхности"},
	"scout": {"name": "Разведчик", "desc": "тратит меньше сил, риск травмы ниже"},
	"teacher": {"name": "Учитель", "desc": "каждое утро +5 выносливости всем дома"},
	"drifter": {"name": "Бродяга", "desc": "без таланта, но крепкий и выносливый"},
}
# 12 персонажей, которые приходят к люку
const NPC_DEFS := [
	{"name": "Глеб", "prof": "engineer", "cap": 4, "eff": 1.1, "suit": Color(0.3, 0.45, 0.6)},
	{"name": "Степан", "prof": "engineer", "cap": 3, "eff": 1.0, "suit": Color(0.25, 0.4, 0.55)},
	{"name": "Марта", "prof": "agronom", "cap": 3, "eff": 1.2, "suit": Color(0.35, 0.55, 0.3)},
	{"name": "Пётр", "prof": "cook", "cap": 4, "eff": 0.9, "suit": Color(0.8, 0.6, 0.3)},
	{"name": "Нина", "prof": "medic", "cap": 3, "eff": 1.0, "suit": Color(0.85, 0.85, 0.9)},
	{"name": "Алла", "prof": "chemist", "cap": 3, "eff": 1.1, "suit": Color(0.4, 0.6, 0.55)},
	{"name": "Женя", "prof": "radio_tech", "cap": 3, "eff": 1.0, "suit": Color(0.5, 0.35, 0.6)},
	{"name": "Ольга", "prof": "hunter", "cap": 5, "eff": 1.0, "suit": Color(0.4, 0.35, 0.25)},
	{"name": "Данил", "prof": "scout", "cap": 4, "eff": 1.0, "suit": Color(0.3, 0.5, 0.45)},
	{"name": "Вера", "prof": "teacher", "cap": 3, "eff": 0.9, "suit": Color(0.6, 0.45, 0.5)},
	{"name": "Игорь", "prof": "mechanic", "cap": 5, "eff": 1.0, "suit": Color(0.55, 0.5, 0.45)},
	{"name": "Тимур", "prof": "drifter", "cap": 6, "eff": 0.85, "suit": Color(0.35, 0.33, 0.3)},
]
const NPC_OK_LOOKS := [
	"Чистая одежда, руки на виду, спокойный взгляд.",
	"Устал с дороги, но выглядит здоровым и открытым.",
	"Вежлив: снимает капюшон и показывает пустые руки.",
	"Ранец за спиной, глаза ясные, дышит ровно.",
]

var t: int
var res: Dictionary
var gear: Dictionary
var car: Dictionary
var workers: Array
var log_lines: Array
var paused := false
var modal_open := false
var end_state := ""
var why := ""
var acc := 0.0
var cinematic := false
var built: Dictionary
var upg: Dictionary
var crop: Dictionary
var npc_pool: Array
var visitor := {}  # {"name", "prof", "status": "ok"/"sick"/"maniac", "look", "def"}
var gen_broken := false
var menu_skip := false
var milestones := {}
var player_food := 80
var player_st := 100
var player_last_sleep := 1


func _ready() -> void:
	reset()


func reset() -> void:
	t = 420
	res = {"metal": 5, "plastic": 3, "wire": 3, "fuel": 2, "rubber": 2, "steel": 0, "chips": 0, "seeds": 3, "potato": 0, "food": 12, "herbs": 0, "medkit": 0}
	built = {"garden": false, "lamp": false, "irrig": false, "kitchen": false, "furnace": false, "shredder": false, "medbed": false, "medcab": false, "filter": false, "insul": false, "coffee": false}
	upg = {"garden": 0, "kitchen": 0, "furnace": 0, "shredder": 0, "medbed": 0, "medcab": 0}
	crop = {"state": "empty", "kind": "", "ready": 0}
	gear = {"pack": 0, "magnet": 0, "drill": 0}
	car = {"engine": false, "wheels": false, "battery": false, "tank": false}
	workers = []  # в первый день бункер пуст: гости приходят со 2-го дня
	npc_pool = range(NPC_DEFS.size())
	visitor = {}
	log_lines = ["День 1. Вы один. Обустройте бункер — со 2-го дня начнут стучаться гости."]
	paused = false
	modal_open = false
	end_state = ""
	why = ""
	acc = 0.0
	cinematic = false
	gen_broken = false
	menu_skip = false
	milestones = {}
	player_food = 80
	player_st = 100
	player_last_sleep = 1
	changed.emit()


func _process(delta: float) -> void:
	if paused or modal_open or cinematic or end_state != "":
		return
	acc += delta
	if acc >= 1.0:  # 1 секунда реального времени = 10 игровых минут
		acc -= 1.0
		advance(10)


func day() -> int:
	return t / 1440 + 1


func phase() -> int:
	return (t % 1440) / 360


func fmt(tt: int) -> String:
	var m := tt % 1440
	return "%02d:%02d" % [m / 60, m % 60]


func weather(d: int, p: int) -> Dictionary:
	var rd := RandomNumberGenerator.new()
	rd.seed = hash("d%d" % d)
	var base: float = float([-8, 2, 10, 3][p]) + (rd.randf() - 0.5) * 24.0
	var r := RandomNumberGenerator.new()
	r.seed = hash("d%dp%d" % [d, p])
	var temp := int(round(base + (r.randf() - 0.5) * 12.0))
	var cloud := int(r.randf() * 100.0)
	var wind := int(r.randf() * r.randf() * 26.0)
	var k := 0
	if wind >= 16:
		k += 2
	if temp < -12 or temp > 34:
		k += 2
	if cloud > 85 and wind > 10:
		k += 1
	return {"temp": temp, "cloud": cloud, "wind": wind, "bad": k >= 2, "k": k}


func cur_weather() -> Dictionary:
	return weather(day(), phase())


func log_add(s: String) -> void:
	log_lines.push_front("Д%d %s — %s" % [day(), fmt(t), s])
	if log_lines.size() > 40:
		log_lines.resize(40)


func advance(minutes: int) -> void:
	for i in range(minutes / 10):
		_step()
		if end_state != "":
			break
	changed.emit()


func _step() -> void:
	t += 10
	if t % 60 == 0:
		_hourly()
	if t % 1440 == 360:
		_daily()
	if t % 1440 == 540:
		_maybe_knock()  # 9:00 — стук в люк
	_agronom_work()
	_maniac_check()
	if crop.state == "growing" and t >= crop.ready:
		crop.state = "ready"
		log_add("Урожай созрел: можно собирать.")
	for i in workers.size():
		var w: Dictionary = workers[i]
		if w.dead:
			continue
		if w.away == null:
			if not w.sick:
				w.st = mini(100, w.st + 1)
		elif t >= w.away.ret:
			_return(i)
	if workers.size() > 0 and workers.all(func(x): return x.dead):
		end_state = "lose"
		why = "Все сотрудники погибли."
	elif day() > 30:
		end_state = "lose"
		why = "Тридцать суток прошли, а машина не выехала."


# ---------- гости ----------
func _maybe_knock() -> void:
	if day() < 2 or visitor != {} or workers.size() >= MAX_WORKERS or npc_pool.is_empty():
		return
	var chance := 1.0 if day() == 2 else 0.8
	if randf() > chance:
		return
	var idx: int = npc_pool.pick_random()
	npc_pool.erase(idx)
	var d: Dictionary = NPC_DEFS[idx]
	var r := randf()
	var status := "ok"
	if r < 0.2:
		status = "maniac"
	elif r < 0.45:
		status = "sick"
	var look: String = NPC_OK_LOOKS[randi() % NPC_OK_LOOKS.size()]
	if status == "sick":
		look = "шмыгает носом, нос красный, вытирает сопли рукавом"
	elif status == "maniac":
		look = "правая рука в кармане — оттуда торчит нож со следами крови"
	visitor = {"name": d.name, "prof": d.prof, "status": status, "look": look, "def": idx}
	log_add("В дверь постучали: %s, %s. Просится в бункер." % [d.name, PROFS[d.prof].name])
	npc_arrived.emit(d.name, status)
	changed.emit()


func npc_accept() -> void:
	if visitor == {}:
		return
	var d: Dictionary = NPC_DEFS[visitor.def]
	workers.append({
		"name": d.name, "prof": d.prof, "cap": d.cap, "eff": d.eff,
		"st": 100, "hp": 100, "sick": visitor.status == "sick",
		"away": null, "dead": false, "xp": 0, "lvl": 1, "suit": d.suit,
		"maniac": visitor.status == "maniac",
		"kill_at": t + randi_range(150, 420),
	})
	if visitor.status == "sick":
		log_add("%s (%s) принят в бункер. Он болен — нужна аптечка." % [d.name, PROFS[d.prof].name])
	else:
		log_add("%s (%s) принят в бункер." % [d.name, PROFS[d.prof].name])
	visitor = {}
	npc_done.emit(true)
	changed.emit()
	if workers.size() >= MAX_WORKERS:
		log_add("★ Бункер полон: %d сотрудников — большая команда!" % workers.size())
		changed.emit()


func npc_refuse() -> void:
	if visitor == {}:
		return
	log_add("%s ушёл искать другой бункер." % visitor.name)
	visitor = {}
	npc_done.emit(false)
	changed.emit()


func _agronom_work() -> void:
	if not built.garden:
		return
	for w in workers:
		if w.dead or w.away != null or w.prof != "agronom":
			continue
		if crop.state == "ready":
			harvest()
			return
		if crop.state == "empty" and res.seeds >= 1:
			plant("potato")
			return


func _maniac_check() -> void:
	for w in workers:
		if w.dead or w.away != null or not w.get("maniac", false):
			continue
		if t < w.kill_at:
			continue
		var victims: Array = workers.filter(func(x): return (not x.dead) and x != w and x.away == null)
		w.dead = true
		w.away = null
		if victims.size() > 0:
			var v: Dictionary = victims.pick_random()
			v.dead = true
			v.hp = 0
			v.away = null
			log_add("%s оказался маньяком: %s погиб. Маньяк сбежал в темноту." % [w.name, v.name])
		else:
			for k in ["metal", "fuel"]:
				res[k] = res[k] / 2
			log_add("%s оказался маньяком: обворовал бункер (половина металла и топлива) и сбежал." % w.name)


func has_prof(p: String) -> bool:
	for w in workers:
		if not w.dead and w.prof == p:
			return true
	return false


func _return(i: int) -> void:
	var w: Dictionary = workers[i]
	var a: Dictionary = w.away
	w.away = null
	if a.bad:
		w.dead = true
		log_add("%s не вернулся: на поверхности была опасная погода." % w.name)
		worker_back.emit(i, false)
		return
	var bag: Array = RAW.duplicate()
	if a.tool == "magnet":
		bag.append_array(["metal", "metal", "wire", "wire"])
	elif a.tool == "drill":
		bag.append_array(["fuel", "fuel", "rubber", "rubber"])
	match w.prof:
		"engineer":
			bag.append_array(["metal", "metal", "wire", "chips"])
		"mechanic":
			bag.append_array(["metal", "rubber", "rubber", "fuel"])
		"hunter":
			bag.append_array(["food", "food", "food"])
	var kind: String = bag.pick_random()
	var cap: int = w.cap + (4 if a.pack else 0)
	var n := maxi(1, int(round(cap * (0.4 + 0.6 * randf()) * w.eff)))
	res[kind] += n
	log_add("%s вернулся: %s ×%d." % [w.name, RES[kind], n])
	if randf() < 0.15:
		var bonus: String = RAW.pick_random()
		res[bonus] += 2
		log_add("%s наткнулся на тайник: %s +2!" % [w.name, RES[bonus]])
	Snd.play("loot")
	if randf() < a.risk:
		var dmg := randi_range(15, 40)
		w.hp = maxi(1, w.hp - dmg)
		log_add("%s получил травму (−%d здоровья)." % [w.name, dmg])
	if a.cold and not w.sick and randf() < (0.08 if built.filter else 0.25):
		w.sick = true
		log_add("%s заболел после вылазки." % w.name)
	_level_up(w, 25)
	worker_back.emit(i, true)


func _level_up(w: Dictionary, xp: int) -> void:
	var before: int = w.lvl
	w.xp += xp
	while w.lvl <= XP_NEED.size() and w.xp >= XP_NEED[w.lvl - 1]:
		w.lvl += 1
		w.cap += 1
		w.eff += 0.08
		log_add("%s вырос до %d-го уровня: +1 вместимость, добыча ×%.1f." % [w.name, w.lvl, w.eff])
		if w.lvl == XP_NEED.size() + 1:
			log_add("★ %s достиг 5-го уровня — настоящий мастер бункера!" % w.name)
	if w.lvl > before:
		Snd.play("levelup")


func xp_need(lvl: int) -> int:
	return XP_NEED[lvl - 1] if lvl <= XP_NEED.size() else -1


func can(cost: Dictionary) -> bool:
	for k in cost:
		if res[k] < cost[k]:
			return false
	return true


func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		parts.append("%s %d" % [RES[k], cost[k]])
	return ", ".join(parts)


func craft(kind: String, id: String) -> void:
	var data: Dictionary
	match kind:
		"gear":
			data = GEAR[id]
		"car":
			data = CAR[id]
		_:
			data = BUILD[id]
	if kind == "build":
		if built[id]:
			return
		if data.has("needs") and not built[data.needs]:
			return
	if not can(data.cost):
		return
	for k in data.cost:
		res[k] -= data.cost[k]
	match kind:
		"gear":
			gear[id] += 1
			log_add("Создано: %s." % data.name)
		"car":
			car[id] = true
			log_add("Установлено: %s." % data.name)
		_:
			built[id] = true
			log_add("Построено: %s." % data.name)
	Snd.play("craft")
	changed.emit()


func upgrade(id: String) -> void:
	if not built[id] or upg[id] >= UPGRADES[id].size():
		return
	var u: Dictionary = UPGRADES[id][upg[id]]
	if not can(u.cost):
		return
	for k in u.cost:
		res[k] -= u.cost[k]
	upg[id] += 1
	log_add("Улучшено: %s." % u.name)
	Snd.play("craft")
	changed.emit()


func proc_time(id: String) -> int:
	var r: Dictionary = PROC[id]
	var m: float = r.min
	if upg[r.station] >= 1:
		m *= 0.6
	return int(round(m))


func proc_out(id: String) -> Dictionary:
	var r: Dictionary = PROC[id]
	var out: Dictionary = {}
	for k in r.out:
		out[k] = r.out[k] + (1 if upg[r.station] >= 2 else 0)
	match id:
		"food":
			if has_prof("cook"):
				out.food += 1
		"biofuel":
			if has_prof("chemist"):
				out.fuel += 1
		"briquette":
			if has_prof("chemist"):
				out.fuel += 1
		"chip":
			if has_prof("radio_tech"):
				out.chips += 1
	return out


func medkit_cost() -> Dictionary:
	var c: Dictionary = MEDKIT_COST.duplicate()
	if upg.medcab >= 1:
		c.herbs = 1
	if upg.medcab >= 2:
		c.erase("plastic")
	return c


func send(i: int, use_pack: bool, tool: String) -> bool:
	var w: Dictionary = workers[i]
	if w.dead or w.away != null or w.st < MIN_STAMINA or w.hp < MIN_HP or w.sick:
		return false
	var wx := cur_weather()
	w.st -= 20 if w.prof == "scout" else MIN_STAMINA
	var risk := 0.12 + 0.18 * float(wx.k)
	if built.insul:
		risk *= 0.6
	if w.prof == "scout":
		risk *= 0.75
	w.away = {
		"ret": t + EXPEDITION_MIN,
		"bad": wx.bad,
		"risk": risk,
		"cold": wx.temp < -8 or wx.wind >= 12,
		"pack": use_pack and gear.pack > 0,
		"tool": tool if tool != "" and gear[tool] > 0 else "",
	}
	log_add("%s вышел на поверхность через люк." % w.name)
	worker_left.emit(i)
	changed.emit()
	return true


func _check_dead(w: Dictionary) -> void:
	if w.hp <= 0 and not w.dead:
		w.dead = true
		w.away = null
		log_add("%s погиб: его не удалось спасти." % w.name)


func _hourly() -> void:
	for w in workers:
		if w.dead or w.away != null:
			continue
		if w.sick:
			w.hp -= 1
		else:
			w.hp = mini(100, w.hp + 1)
		_check_dead(w)


func _daily() -> void:
	save_game(true)  # автосохранение каждое утро
	if day() in [7, 14, 21, 28]:
		log_add("★ %d дней в бункере — вы держитесь молодцом!" % day())
	var warns: Array = []
	for p in 4:
		if weather(day(), p).bad:
			warns.append(PH[p])
	if warns.size() > 0:
		log_add("Метеостанция: сегодня опасная погода (%s) — не выходите в это время." % ", ".join(warns))
	if day() >= 3 and not gen_broken and randf() < 0.12:
		gen_broken = true
		log_add("Генератор сломался — свет тусклый и мигает. Почините: 2 металла.")
	# жизненные показатели игрока: еда
	if res.food >= 1:
		res.food -= 1
		player_food = mini(100, player_food + 55)
	else:
		player_food = maxi(0, player_food - 45)
		log_add("Вам не хватило еды на завтрак — сытость падает.")
	# жизненные показатели игрока: сон (спать хотя бы раз в 2 дня, иначе смерть)
	if day() - player_last_sleep >= 2:
		end_state = "lose"
		why = "Вы не спали двое суток — организм не выдержал. Сон на койках спасает жизнь."
		log_add("Вы умерли от бессонницы. Надо было поспать на койках...")
		delete_save()
		return
	player_st = maxi(0, player_st - 45)
	if player_st <= 25:
		log_add("Вы еле стоите на ногах — поспите на койках сегодня, иначе завтра не проснётесь!")
	elif day() - player_last_sleep >= 1:
		log_add("Вы давно не спали — поспите сегодня на койках.")
	var st_bonus := 0
	if built.coffee:
		st_bonus += 12
	if has_prof("teacher"):
		for w in workers:
			if not w.dead and w.away == null and w.prof == "teacher":
				st_bonus += 5
				break
	if st_bonus > 0:
		var any := false
		for w in workers:
			if not w.dead and w.away == null:
				w.st = mini(100, w.st + st_bonus)
				any = true
		if any and built.coffee:
			log_add("Утренний заряд бодрости (кофемашина%s)." % (" и учитель" if has_prof("teacher") else ""))
	for w in workers:
		if w.dead:
			continue
		if res.food >= 1:
			res.food -= 1
		else:
			w.hp -= 15
			w.st = maxi(0, w.st - 20)
			log_add("%s голодает: не хватает еды." % w.name)
			_check_dead(w)
	# болезнь распространяется дома: больной может заразить здорового
	var sick_home: Array = workers.filter(func(x): return x.sick and not x.dead and x.away == null)
	if sick_home.size() > 0 and randf() < (0.02 if built.filter else 0.08):
		var healthy: Array = workers.filter(func(x): return (not x.dead) and (not x.sick) and x.away == null)
		if healthy.size() > 0:
			var v: Dictionary = healthy.pick_random()
			v.sick = true
			log_add("%s заразился от %s. Аптечка вылечит." % [v.name, (sick_home[0] as Dictionary).name])


func plant(kind: String) -> void:
	if not built.garden or crop.state != "empty" or res.seeds < 1:
		return
	res.seeds -= 1
	var mins := 1440.0
	if built.lamp:
		mins *= 0.7
	if built.irrig:
		mins *= 0.7
	if upg.garden >= 1:
		mins *= 0.75
	crop = {"state": "growing", "kind": kind, "ready": t + int(mins)}
	log_add("Посажено: %s." % CROPS[kind].name)
	changed.emit()


func harvest() -> void:
	if crop.state != "ready":
		return
	var out: Dictionary = CROPS[crop.kind].out
	for k in out:
		res[k] += out[k]
	if built.irrig:
		res[crop.kind] += 1
	if upg.garden >= 2:
		res[crop.kind] += 2
	log_add("Урожай собран: %s." % CROPS[crop.kind].name)
	station_used.emit("garden")
	if not milestones.has("harvest"):
		milestones["harvest"] = true
		log_add("★ Первый урожай собран — продовольственная цепочка работает!")
	crop = {"state": "empty", "kind": "", "ready": 0}
	changed.emit()


func process(id: String) -> void:
	var r: Dictionary = PROC[id]
	if not built[r.station] or not can(r.cost):
		return
	for k in r.cost:
		res[k] -= r.cost[k]
	var out: Dictionary = proc_out(id)
	for k in out:
		res[k] += out[k]
	log_add("Переработка: %s." % r.name)
	station_used.emit(r.station)
	advance(proc_time(id))


func make_medkit() -> void:
	var cost := medkit_cost()
	if not built.medcab or not can(cost):
		return
	for k in cost:
		res[k] -= cost[k]
	res.medkit += 1
	log_add("Приготовлена аптечка.")
	station_used.emit("medcab")
	advance(30)


func heal_bed(i: int) -> void:
	var w: Dictionary = workers[i]
	if not built.medbed or w.dead or w.away != null:
		return
	w.hp = mini(100, w.hp + 30 + 20 * upg.medbed + (20 if has_prof("medic") else 0))
	w.st = mini(100, w.st + 10 + (10 if upg.medbed >= 2 else 0))
	log_add("%s отлежался на кушетке." % w.name)
	advance(120)


func use_medkit(i: int) -> void:
	var w: Dictionary = workers[i]
	if res.medkit < 1 or w.dead or w.away != null:
		return
	res.medkit -= 1
	w.hp = mini(100, w.hp + (70 if has_prof("medic") else 50))
	w.sick = false
	log_add("%s получил аптечку." % w.name)
	changed.emit()


func rest(i: int) -> void:
	var w: Dictionary = workers[i]
	if w.dead or w.away != null:
		return
	w.st = mini(100, w.st + 40)
	log_add("%s поспал. Выносливость выросла." % w.name)
	advance(120)


func rest_all() -> void:
	var any := false
	for w in workers:
		if not w.dead and w.away == null:
			w.st = mini(100, w.st + 40)
			any = true
	if any:
		log_add("Все дома легли спать. Выносливость выросла.")
		Snd.play("craft")
		advance(120)


func player_sleep() -> void:
	player_st = 100
	player_last_sleep = day()
	log_add("Вы выспались. Бодрость восстановлена — и вы проживёте ещё день.")
	Snd.play("craft")
	advance(120)


func player_eat() -> void:
	if res.food < 1:
		return
	res.food -= 1
	player_food = mini(100, player_food + 40)
	log_add("Вы поели. Сытость восстановлена.")
	Snd.play("loot")
	advance(20)


func radio() -> void:
	var amt := 15 if has_prof("radio_tech") else 8
	for w in workers:
		if not w.dead and w.away == null:
			w.st = mini(100, w.st + amt)
	log_add("Радио ловит старые песни. Все дома бодрее (+%d выносливости)." % amt)
	Snd.play("radio")
	advance(30)


func repair_generator() -> void:
	if not gen_broken or not can(GEN_COST):
		return
	for k in GEN_COST:
		res[k] -= GEN_COST[k]
	gen_broken = false
	log_add("Генератор починен — свет вернулся.")
	Snd.play("craft")
	advance(30)


# ---------- сохранение ----------
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func peek_save_day() -> int:
	if not has_save():
		return 1
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return 1
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		return int(data.get("t", 420)) / 1440 + 1
	return 1


func save_game(_auto := false) -> bool:
	if end_state != "" or cinematic:
		return false
	var data := {
		"t": t, "gen_broken": gen_broken,
		"player_food": player_food, "player_st": player_st, "player_last_sleep": player_last_sleep,
		"res": res.duplicate(), "gear": gear.duplicate(), "car": car.duplicate(),
		"built": built.duplicate(), "upg": upg.duplicate(), "crop": crop.duplicate(),
		"visitor": visitor.duplicate(), "log": log_lines.duplicate(),
		"workers": [],
	}
	for w in workers:
		var ww: Dictionary = w.duplicate()
		ww.suit = (ww.suit as Color).to_html()
		data.workers.append(ww)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return false
	reset()
	menu_skip = true
	t = int(data.get("t", 420))
	gen_broken = bool(data.get("gen_broken", false))
	player_food = int(data.get("player_food", 80))
	player_st = int(data.get("player_st", 100))
	player_last_sleep = int(data.get("player_last_sleep", 1))
	for k in data.res:
		res[k] = int(data.res[k])
	for k in data.gear:
		gear[k] = int(data.gear[k])
	for k in data.car:
		car[k] = bool(data.car[k])
	for k in data.built:
		built[k] = bool(data.built[k])
	for k in data.upg:
		upg[k] = int(data.upg[k])
	crop = {"state": String(data.crop.state), "kind": String(data.crop.kind), "ready": int(data.crop.ready)}
	visitor = data.visitor if (data.visitor is Dictionary) else {}
	log_lines = []
	for l in data.log:
		log_lines.append(String(l))
	workers = []
	for w in data.workers:
		var away: Dictionary = w.away if (w.away is Dictionary) else {}
		var away_ok := not away.is_empty()
		workers.append({
			"name": String(w.name), "prof": String(w.prof),
			"cap": int(w.cap), "eff": float(w.eff),
			"st": int(w.st), "hp": int(w.hp),
			"sick": bool(w.sick), "dead": bool(w.dead),
			"xp": int(w.xp), "lvl": int(w.lvl),
			"maniac": bool(w.get("maniac", false)),
			"kill_at": int(w.get("kill_at", -1)),
			"away": ({"ret": int(away.ret), "bad": bool(away.bad), "risk": float(away.risk), "cold": bool(away.cold), "pack": bool(away.pack), "tool": String(away.tool)} if away_ok else null),
			"suit": Color.from_string(String(w.get("suit", "787878ff")), Color(0.5, 0.5, 0.5)),
		})
	changed.emit()
	return true


func car_done() -> bool:
	return car.values().all(func(v): return v)


func drive_out() -> void:
	if car_done():
		end_state = "win"
		changed.emit()
