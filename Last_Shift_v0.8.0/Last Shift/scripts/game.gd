extends Node
## Автозагрузка "Game": всё состояние и логика (время, погода, экспедиции, крафт, прокачка, гости).

signal changed
signal worker_left(i: int)
signal worker_back(i: int, ok: bool)
signal npc_arrived(npc_name: String, status: String)
signal npc_done(accepted: bool)
signal npc_wait  # игрок отошёл от окна, не решив, что делать с гостем
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
	"kitchen": {"name": "Кухня", "desc": "Картошка: в еду или в бензин (биотопливо).", "cost": {"metal": 5, "plastic": 2, "wire": 2, "fuel": 1}},
	"furnace": {"name": "Плавильная печь", "desc": "Переработка: сталь и топливные брикеты.", "cost": {"metal": 6, "fuel": 2, "plastic": 1}},
	"shredder": {"name": "Измельчитель", "desc": "Переработка: платы и пластик.", "cost": {"metal": 5, "wire": 3, "plastic": 1}},
	"medbed": {"name": "Медицинская кушетка", "desc": "Лечит травмы И болезни (2 часа на сеанс).", "cost": {"metal": 3, "plastic": 2, "wire": 1}},
	"medcab": {"name": "Аптечный шкаф", "desc": "Делает аптечки из трав.", "cost": {"metal": 2, "plastic": 3, "steel": 1}},
	"filter": {"name": "Фильтр воздуха", "desc": "Шанс заболеть после вылазки: 25% → 8%.", "cost": {"metal": 4, "chips": 1, "plastic": 2, "rubber": 2}},
	"insul": {"name": "Утепление люка", "desc": "Риск травмы на поверхности −40%.", "cost": {"rubber": 4, "metal": 3}},
	"coffee": {"name": "Кофемашина", "desc": "Каждое утро +12 выносливости всем дома.", "cost": {"metal": 3, "plastic": 2, "wire": 1, "chips": 1}},
}
# Улучшения построек: два уровня для каждой (индекс = текущий уровень постройки − 1)
const UPGRADES := {
	"garden": [
		{"name": "Грядка ур.2 — быстрый рост", "desc": "растения зреют на 25% быстрее", "cost": {"metal": 4, "plastic": 3, "rubber": 2}},
		{"name": "Грядка ур.3 — большой урожай", "desc": "+2 картошки к каждому урожаю", "cost": {"metal": 6, "steel": 2, "chips": 1}},
	],
	"kitchen": [
		{"name": "Кухня ур.2 — скороварка", "desc": "рецепты на 40% быстрее", "cost": {"metal": 4, "wire": 2, "fuel": 1}},
		{"name": "Кухня ур.3 — конвейер", "desc": "+1 к выходу еды и топлива", "cost": {"metal": 6, "chips": 2, "steel": 1}},
	],
	"furnace": [
		{"name": "Печь ур.2 — жар", "desc": "переработка на 40% быстрее", "cost": {"metal": 5, "steel": 2, "fuel": 2}},
		{"name": "Печь ур.3 — рекуператор", "desc": "+1 к выходу стали и брикетов", "cost": {"metal": 8, "steel": 3, "chips": 2}},
	],
	"shredder": [
		{"name": "Измельчитель ур.2", "desc": "переработка на 40% быстрее", "cost": {"metal": 5, "wire": 2, "rubber": 1}},
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
	"pack": {"name": "Рюкзак", "desc": "+4 к вместимости: вылазка приносит заметно больше (отметьте его при отправке)", "cost": {"metal": 2, "plastic": 2, "rubber": 2}},
	"magnet": {"name": "Магнит", "desc": "×1,5 металла и проводов в добыче", "cost": {"metal": 2, "wire": 2, "fuel": 1}},
	"drill": {"name": "Бур", "desc": "×1,5 топлива, резины и пластика в добыче", "cost": {"metal": 3, "rubber": 2, "fuel": 1}},
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
const MUSIC_COOLDOWN := 720                           # музыку можно включить раз в 12 часов, иначе «нет сигнала»
const MUSIC_WINDOW := 360                             # сколько минут после музыки сотрудник «вдохновлён» (6 ч)
const MUSIC_LOOT_BONUS := 1.15                         # +15% добычи с вылазки
const MAX_BEDS := 10                                  # максимум кроватей в комнате отдыха
const BED_COST := {"metal": 2, "plastic": 1, "rubber": 1}
const SLEEP_HOURS := 8                                # сон игрока — 8 часов
const SLEEP_MIN := SLEEP_HOURS * 60
const NIGHT_START := 22 * 60                          # сотрудники сами ложатся в 22:00, встают в 06:00
const SAVE_PATH := "user://save.json"
const AWAKE_LIMIT := 2880        # 48 часов без сна — смерть
const VISITOR_WAIT := 720        # гость ждёт у люка 12 часов и уходит сам
const TRADER_STAY := 480         # торговец стоит у люка 8 часов
# условная ценность ресурсов — по ней считаются сделки с торговцем
const VALUE := {"metal": 1.0, "plastic": 1.3, "wire": 1.5, "fuel": 2.0, "rubber": 1.5, "steel": 4.0, "chips": 5.0,
	"food": 1.0, "seeds": 2.0, "herbs": 1.5, "medkit": 5.0, "potato": 0.6}
const TRADE_GET := {"metal": 4, "plastic": 3, "steel": 1, "chips": 1, "medkit": 1, "food": 4, "seeds": 2, "wire": 3}
const TRADE_GIVE := ["fuel", "rubber", "wire", "plastic", "metal", "food", "herbs", "potato"]
const GEN_COST := {"metal": 1, "wire": 1, "fuel": 1}

# Профессии гостей и их эффекты
const PROFS := {
	"engineer": {"name": "Инженер", "desc": "вылазки чаще приносят металл, провод и платы"},
	"mechanic": {"name": "Механик", "desc": "вылазки чаще приносят металл, резину и топливо"},
	"cook": {"name": "Повар", "desc": "еда из картошки +1"},
	"medic": {"name": "Медик", "desc": "лечение кушеткой и аптечкой сильнее"},
	"chemist": {"name": "Химик", "desc": "бензин из картошки и брикеты +1"},
	"radio_tech": {"name": "Радиотехник", "desc": "платы +1 при сборке в измельчителе"},
	"hunter": {"name": "Охотник", "desc": "может принести еду с поверхности"},
	"scout": {"name": "Разведчик", "desc": "тратит меньше сил, риск травмы ниже"},
	"teacher": {"name": "Учитель", "desc": "каждое утро +5 выносливости всем дома"},
	"drifter": {"name": "Бродяга", "desc": "без таланта, но крепкий и выносливый"},
}
# 12 персонажей, которые приходят к люку
const NPC_DEFS := [
	{"name": "Глеб", "prof": "engineer", "cap": 4, "eff": 1.1, "suit": Color(0.3, 0.45, 0.6)},
	{"name": "Степан", "prof": "engineer", "cap": 3, "eff": 1.0, "suit": Color(0.25, 0.4, 0.55)},
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
const VisitorDialogue = preload("res://scripts/visitor_dialogue.gd")
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
var radio_music_at := -99999   # когда в последний раз включали музыку
var menu_skip := false
var milestones := {}
var player_food := 80
var player_st := 100
var player_last_sleep := 1
var beds := 2  # построено кроватей (в комнате отдыха можно до MAX_BEDS)
var player_awake := 0        # сколько минут вы уже не спите
var player_sleep_until := 0  # до какого момента идёт ваш сон
var starve_min := 0          # сколько минут подряд сытость на нуле
var visitor_until := 0       # когда гость у люка уйдёт сам
var last_status := "ok"      # статус предыдущего гостя (больные не идут подряд)
var trader := {}             # {"until": t, "deals": [{give, get, left}]}
var radio_call_at := 0       # когда снова можно вызвать торговца
var radio_signal_at := 0     # когда снова можно искать выживших
var radio_signal := false    # завтра к люку точно кто-то придёт


func _ready() -> void:
	reset()


func reset() -> void:
	t = 420
	res = {"metal": 5, "plastic": 3, "wire": 3, "fuel": 2, "rubber": 2, "steel": 0, "chips": 0, "seeds": 3, "potato": 0, "food": 12, "herbs": 0, "medkit": 1}
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
	radio_music_at = -99999
	menu_skip = false
	milestones = {}
	player_food = 80
	player_st = 100
	player_last_sleep = 1
	beds = 2
	player_awake = 0
	player_sleep_until = 0
	starve_min = 0
	visitor_until = 0
	last_status = "ok"
	trader = {}
	radio_call_at = 0
	radio_signal_at = 0
	radio_signal = false
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
	# Плохая погода: за сутки от 0 до 2 раз (из 4 периодов), заметно чаще, чем раньше.
	var cnt := RandomNumberGenerator.new()
	cnt.seed = hash("bad%d" % d)
	var roll := cnt.randf()
	var n_bad := 0
	if roll >= 0.2:
		n_bad = 1 if roll < 0.55 else 2
	var order: Array = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j: int = cnt.randi() % (i + 1)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var is_bad: bool = order.slice(0, n_bad).has(p)
	var r := RandomNumberGenerator.new()
	r.seed = hash("d%dp%d" % [d, p])
	var temp := int(round(base + (r.randf() - 0.5) * 12.0))
	var cloud := int(r.randf() * 100.0)
	var wind := int(r.randf() * r.randf() * 26.0)
	if is_bad:
		wind = maxi(wind, 16 + int(r.randf() * 8.0))  # сильный ветер = опасно
	else:
		wind = mini(wind, 15)
		temp = clampi(temp, -12, 34)
	var k := 0
	if wind >= 16:
		k += 2
	if temp < -12 or temp > 34:
		k += 2
	if cloud > 85 and wind > 10:
		k += 1
	return {"temp": temp, "cloud": cloud, "wind": wind, "bad": k >= 2, "k": k}


func weather_at(tt: int) -> Dictionary:
	return weather(tt / 1440 + 1, (tt % 1440) / 360)


# Вылазка длится 3 часа и может захватить смену погоды: опасно, если плохо в начале ИЛИ к возвращению.
func trip_weather(t0: int) -> Dictionary:
	var a := weather_at(t0)
	var b := weather_at(t0 + EXPEDITION_MIN)
	var w: Dictionary = (a if a.k >= b.k else b).duplicate()
	w.bad = a.bad or b.bad
	w.now_bad = a.bad
	w.later_bad = b.bad
	return w


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
	if t > player_sleep_until:
		player_awake += 10
		player_st = clampi(100 - player_awake * 100 / AWAKE_LIMIT, 0, 100)
		if player_awake >= AWAKE_LIMIT:
			end_state = "lose"
			why = "Вы не спали двое суток — организм не выдержал. Сон на койках спасает жизнь."
			log_add("Вы умерли от бессонницы. Надо было поспать на койках...")
			delete_save()
			return
	if visitor != {} and t >= visitor_until:
		_visitor_leaves()
	if not trader.is_empty() and t >= int(trader.until):
		log_add("Торговец собрал товар и ушёл по своим делам.")
		trader = {}
	# торговец приходит сам: каждый день в 13:00 с вероятностью 20%
	if t % 1440 == 780 and day() >= 2 and trader.is_empty() and randf() < 0.2:
		_spawn_trader(TRADER_STAY)
	if t % 60 == 0:
		_hourly()
	if t % 1440 == NIGHT_START:
		_night_begin()
	if t % 1440 == 360:
		_wake_up()
		_daily()
	if t % 1440 == 540:
		_maybe_knock()  # 9:00 — стук в люк
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
	var chance := 1.0 if (day() == 2 or radio_signal) else 0.8
	radio_signal = false
	if randf() > chance:
		return
	var idx: int = npc_pool.pick_random()
	npc_pool.erase(idx)
	var d: Dictionary = NPC_DEFS[idx]
	# первые дни — только здоровые люди; больные не приходят два раза подряд, маньяки — с 5-го дня
	var r := randf()
	var status := "ok"
	if day() >= 5 and r < 0.15:
		status = "maniac"
	elif day() >= 4 and r < 0.4 and last_status != "sick":
		status = "sick"
	last_status = status
	var look: String = NPC_OK_LOOKS[randi() % NPC_OK_LOOKS.size()]
	if status == "sick":
		look = "шмыгает носом, нос красный, вытирает сопли рукавом"
	elif status == "maniac":
		look = "правая рука в кармане — оттуда торчит нож со следами крови"
	visitor = {"name": d.name, "prof": d.prof, "status": status, "look": look, "def": idx}
	visitor_until = t + VISITOR_WAIT
	log_add("В дверь постучали: %s, %s. Просится в бункер." % [d.name, PROFS[d.prof].name])
	npc_arrived.emit(d.name, status)
	changed.emit()


func visitor_story() -> String:
	if visitor.is_empty():
		return ""
	# Индекс сохраняется в старых и новых сохранениях: рассказ не меняется при загрузке.
	return VisitorDialogue.build(String(visitor.name), String(visitor.status), int(visitor.def))


# Свободные кровати: принять гостя можно, только если для него есть кровать
func free_beds() -> int:
	return beds - living_workers()


func npc_accept() -> void:
	if visitor == {}:
		return
	if free_beds() < 1:
		log_add("Для %s нет свободной кровати. Постройте кровать на верстаке." % visitor.name)
		changed.emit()
		return
	var d: Dictionary = NPC_DEFS[visitor.def]
	workers.append({
		"name": d.name, "prof": d.prof, "cap": d.cap, "eff": d.eff,
		"st": 100, "hp": 100, "sick": visitor.status == "sick",
		"away": null, "dead": false, "xp": 0, "lvl": 1, "suit": d.suit,
		"maniac": visitor.status == "maniac",
		"kill_at": t + randi_range(150, 420),
		"bed": -1, "asleep": false, "nobed": false, "nosleep": 0, "music_at": -99999,
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


func _visitor_leaves() -> void:
	log_add("%s не дождался ответа и ушёл искать другой бункер." % visitor.name)
	visitor = {}
	npc_done.emit(false)
	changed.emit()


func npc_refuse() -> void:
	if visitor == {}:
		return
	log_add("%s ушёл искать другой бункер." % visitor.name)
	visitor = {}
	npc_done.emit(false)
	changed.emit()


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
	var loot := _loot(w, a)
	var parts: Array = []
	for k in loot:
		res[k] += loot[k]
		parts.append("%s ×%d" % [RES[k], loot[k]])
	log_add("%s вернулся: %s.%s" % [w.name, ", ".join(parts), " (+15% от музыки)" if a.get("music", false) else ""])
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


# Добыча — 1–3 РАЗНЫХ вида ресурсов (а не один вид на всю вылазку).
func _loot(w: Dictionary, a: Dictionary) -> Dictionary:
	var weights := {"metal": 3.0, "plastic": 2.5, "wire": 2.0, "fuel": 1.5, "rubber": 1.5}
	match w.prof:
		"engineer":
			weights["chips"] = 1.0
			weights.wire += 1.0
		"mechanic":
			weights.rubber += 1.0
			weights.fuel += 1.0
		"hunter":
			weights["food"] = 3.0
	var cap: int = w.cap + (4 if a.pack else 0)
	var n := maxi(1, int(round(cap * (0.5 + 0.6 * randf()) * w.eff)))
	var kinds := 1 if n < 2 else (2 if n < 4 else 3)
	var chosen: Array = []
	for _i in kinds:
		var total := 0.0
		for k in weights:
			if not chosen.has(k):
				total += weights[k]
		var roll := randf() * total
		for k in weights:
			if chosen.has(k):
				continue
			roll -= weights[k]
			if roll <= 0.0:
				chosen.append(k)
				break
	var shares: Array = []
	var ssum := 0.0
	for _k in chosen:
		var sh := 0.6 + randf()
		shares.append(sh)
		ssum += sh
	var out := {}
	for i in chosen.size():
		var k: String = chosen[i]
		var mult := 1.0
		if a.tool == "magnet" and (k == "metal" or k == "wire"):
			mult = 1.5
		elif a.tool == "drill" and (k == "fuel" or k == "rubber" or k == "plastic"):
			mult = 1.5
		var amount := n * float(shares[i]) / ssum * mult
		if a.get("music", false):
			# музыка: в среднем +15% к добыче (дробная часть выпадает случайно)
			amount *= MUSIC_LOOT_BONUS
			var whole := int(floor(amount))
			out[k] = maxi(1, whole + (1 if randf() < amount - float(whole) else 0))
		else:
			out[k] = maxi(1, int(round(amount)))
	return out


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
	if w.dead or w.away != null or w.get("asleep", false) or w.st < MIN_STAMINA or w.hp < MIN_HP or w.sick:
		return false
	var wx := trip_weather(t)
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
		"music": heard_music(w),
	}
	log_add("%s вышел на поверхность через люк%s." % [w.name, " под настроение от музыки" if w.away.music else ""])
	worker_left.emit(i)
	changed.emit()
	return true


func _check_dead(w: Dictionary) -> void:
	if w.hp <= 0 and not w.dead:
		w.dead = true
		w.away = null
		log_add("%s погиб: его не удалось спасти." % w.name)


func _hourly() -> void:
	# сытость падает каждый час; на нуле сутки — смерть
	player_food = maxi(0, player_food - 2)
	if player_food == 0:
		starve_min += 60
		if starve_min >= 1440:
			end_state = "lose"
			why = "Вы умерли от голода. Еда нужна каждый день."
			log_add("Вы умерли от голода.")
			delete_save()
			return
		if starve_min == 720:
			log_add("Вы страшно голодны — ешьте, иначе умрёте!")
	else:
		starve_min = 0
	if player_awake == 1440:
		log_add("Вы не спали сутки. Поспите на койках.")
	elif player_awake == 2160:
		log_add("Вы валитесь с ног: ещё 12 часов без сна — и вы умрёте!")
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
	if living_workers() > beds:
		log_add("Кроватей не хватает: %d из %d. Без кровати сотрудник гибнет после двух суток без сна." % [beds, living_workers()])
	if day() >= 3 and not gen_broken and randf() < 0.12:
		gen_broken = true
		log_add("Генератор сломался — свет тусклый и мигает. Почините: металл, провод и топливо.")
	# завтрак: съедается 1 еда (вы) и по 1 еде на каждого сотрудника
	if res.food >= 1:
		res.food -= 1
		player_food = mini(100, player_food + 55)
	else:
		log_add("Вам не хватило еды на завтрак — сытость будет падать, пока не найдёте еду.")
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
	if w.sick:
		w.sick = false
		log_add("%s вылечился на кушетке." % w.name)
	else:
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
	advance(SLEEP_MIN)


func rest_all() -> void:
	var any := false
	for w in workers:
		if not w.dead and w.away == null:
			w.st = mini(100, w.st + 40)
			any = true
	if any:
		log_add("Все дома легли спать. Выносливость выросла.")
		Snd.play("craft")
		advance(SLEEP_MIN)


func player_sleep() -> void:
	if player_st > 85:
		log_add("Вам не хочется спать (бодрость %d%%)." % player_st)
		changed.emit()
		return
	player_sleep_until = t + SLEEP_MIN
	player_last_sleep = day()
	log_add("Вы легли спать на %d ч." % SLEEP_HOURS)
	Snd.play("craft")
	advance(SLEEP_MIN)
	if end_state == "":
		player_awake = 0
		player_st = 100
		log_add("Вы выспались: бодрость 100%.")
		changed.emit()


func living_workers() -> int:
	var n := 0
	for w in workers:
		if not w.dead:
			n += 1
	return n


func build_bed() -> void:
	if beds >= MAX_BEDS or not can(BED_COST):
		return
	for k in BED_COST:
		res[k] -= BED_COST[k]
	beds += 1
	log_add("Построена кровать (%d из %d)." % [beds, MAX_BEDS])
	Snd.play("craft")
	changed.emit()


# 22:00 — сотрудники сами идут спать. Кровати достаются по порядку прихода;
# кому кровати не хватило, ночь проводит без сна.
func _night_begin() -> void:
	var rank := 0
	var asleep_n := 0
	var nobed_n := 0
	for w in workers:
		w.asleep = false
		w.nobed = false
		w.bed = -1
		if w.dead:
			continue
		if rank < beds:
			w.bed = rank
		rank += 1
		if w.away != null:
			continue
		if w.bed >= 0:
			w.asleep = true
			asleep_n += 1
		else:
			w.nobed = true
			nobed_n += 1
	if asleep_n > 0:
		log_add("Сотрудники легли спать (кроватей занято: %d)." % asleep_n)
	if nobed_n > 0:
		log_add("Не хватило кроватей: %d чел. остались без сна." % nobed_n)
	changed.emit()


# 06:00 — подъём. Выспавшиеся бодры; кто остался без кровати, копит бессонницу.
func _wake_up() -> void:
	for w in workers:
		if w.dead:
			continue
		if w.get("asleep", false):
			w.asleep = false
			w.nosleep = 0
			w.st = mini(100, w.st + 40)
		elif w.get("nobed", false):
			w.nobed = false
			w.nosleep = int(w.get("nosleep", 0)) + 1
			if w.nosleep >= 2:
				w.dead = true
				w.away = null
				log_add("%s погиб: двое суток без сна — для него не нашлось кровати." % w.name)
			else:
				log_add("%s не спал этой ночью: нет кровати. Ещё одна такая ночь — и он погибнет!" % w.name)
		w.bed = -1
	changed.emit()


func player_eat() -> void:
	if res.food < 1:
		return
	res.food -= 1
	player_food = mini(100, player_food + 40)
	log_add("Вы поели. Сытость восстановлена.")
	Snd.play("loot")
	advance(20)


# Радио: музыку слышат все сотрудники в бункере. Кто слышал её за последние 6 часов,
# того вылазка принесёт на 15% больше ресурсов (учитывается в момент выхода на поверхность).
# Через сколько минут снова появится сигнал (0 — музыку можно включить)
func music_cooldown_left() -> int:
	return maxi(0, MUSIC_COOLDOWN - (t - radio_music_at))


func radio() -> void:
	if music_cooldown_left() > 0:
		log_add("Радио: нет сигнала. Сигнал появится через %d ч." % ((music_cooldown_left() + 59) / 60))
		changed.emit()
		return
	radio_music_at = t
	var heard := 0
	for w in workers:
		if not w.dead and w.away == null:
			w["music_at"] = t
			heard += 1
	if heard > 0:
		log_add("Радио ловит старые песни. Слушали: %d. Следующая вылазка в ближайшие 6 часов принесёт на 15%% больше." % heard)
	else:
		log_add("Радио ловит старые песни, но слушать некому: в бункере никого нет.")
	Snd.play("radio")
	advance(30)


func heard_music(w: Dictionary) -> bool:
	return t - int(w.get("music_at", -99999)) < MUSIC_WINDOW


# Сколько минут ещё действует музыка у сотрудника (0 — не действует)
func music_left(w: Dictionary) -> int:
	return maxi(0, MUSIC_WINDOW - (t - int(w.get("music_at", -99999))))


func radio_seek_survivors() -> void:
	if t < radio_signal_at:
		return
	radio_signal_at = t + 1440
	radio_signal = true
	Snd.play("radio")
	log_add("Вы передали сигнал в эфир: завтра к люку наверняка кто-то придёт.")
	advance(30)


func _spawn_trader(stay: int) -> void:
	var deals: Array = []
	var gets: Array = TRADE_GET.keys()
	gets.shuffle()
	for g in gets.slice(0, 6):
		var gk: String = g
		var gn: int = TRADE_GET[gk]
		var gives: Array = TRADE_GIVE.filter(func(x): return x != gk)
		var give: String = gives.pick_random()
		var need := maxi(1, int(ceil(VALUE[gk] * gn * 1.25 / VALUE[give])))
		deals.append({"give": give, "give_n": need, "get": gk, "get_n": gn, "left": 2})
	trader = {"until": t + stay, "deals": deals}
	log_add("К воротам пришёл торговец! Он не заходит внутрь: подойдите к воротам, посмотрите в окно (E) и меняйтесь через него.")
	Snd.play("loot")
	changed.emit()


func trade(i: int) -> void:
	if trader.is_empty() or i < 0 or i >= trader.deals.size():
		return
	var d: Dictionary = trader.deals[i]
	var gn := int(d.give_n)
	var tn := int(d.get_n)
	if int(d.left) < 1 or res[d.give] < gn:
		return
	res[d.give] -= gn
	res[d.get] += tn
	d.left = int(d.left) - 1
	log_add("Обмен: −%s ×%d, +%s ×%d." % [RES[d.give], gn, RES[d.get], tn])
	Snd.play("loot")
	changed.emit()


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
		"t": t, "gen_broken": gen_broken, "radio_music_at": radio_music_at,
		"player_food": player_food, "player_st": player_st, "player_last_sleep": player_last_sleep, "beds": beds,
		"player_awake": player_awake, "player_sleep_until": player_sleep_until, "starve_min": starve_min,
		"visitor_until": visitor_until, "last_status": last_status, "trader": trader,
		"radio_call_at": radio_call_at, "radio_signal_at": radio_signal_at, "radio_signal": radio_signal,
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
	radio_music_at = int(data.get("radio_music_at", -99999))
	player_food = int(data.get("player_food", 80))
	player_st = int(data.get("player_st", 100))
	player_last_sleep = int(data.get("player_last_sleep", 1))
	beds = clampi(int(data.get("beds", 2)), 1, MAX_BEDS)
	player_awake = int(data.get("player_awake", 0))
	player_sleep_until = int(data.get("player_sleep_until", 0))
	starve_min = int(data.get("starve_min", 0))
	visitor_until = int(data.get("visitor_until", t + VISITOR_WAIT))
	last_status = String(data.get("last_status", "ok"))
	trader = data.get("trader", {}) if (data.get("trader", {}) is Dictionary) else {}
	radio_call_at = int(data.get("radio_call_at", 0))
	radio_signal_at = int(data.get("radio_signal_at", 0))
	radio_signal = bool(data.get("radio_signal", false))
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
			"bed": int(w.get("bed", -1)), "asleep": bool(w.get("asleep", false)),
			"nobed": bool(w.get("nobed", false)), "nosleep": int(w.get("nosleep", 0)),
			"away": ({"ret": int(away.ret), "bad": bool(away.bad), "risk": float(away.risk), "cold": bool(away.cold), "pack": bool(away.pack), "tool": String(away.tool), "music": bool(away.get("music", false))} if away_ok else null),
			"music_at": int(w.get("music_at", -99999)),
			"suit": Color.from_string(String(w.get("suit", "787878ff")), Color(0.5, 0.5, 0.5)),
		})
	# старые сохранения: убранные профессии → бродяга; гость и пул гостей сверяются по именам
	for w in workers:
		if not PROFS.has(w.prof):
			w.prof = "drifter"
	if not visitor.is_empty():
		var vi := _npc_index(String(visitor.get("name", "")))
		if vi < 0:
			visitor = {}
		else:
			visitor["def"] = vi
	var taken: Array = workers.map(func(x): return x.name)
	if not visitor.is_empty():
		taken.append(visitor.name)
	npc_pool = range(NPC_DEFS.size()).filter(func(i): return not taken.has(NPC_DEFS[i].name))
	changed.emit()
	return true


func _npc_index(npc_name: String) -> int:
	for i in NPC_DEFS.size():
		if NPC_DEFS[i].name == npc_name:
			return i
	return -1


func car_done() -> bool:
	return car.values().all(func(v): return v)


func drive_out() -> void:
	if car_done():
		end_state = "win"
		changed.emit()
