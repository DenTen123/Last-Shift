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
const RECORD_PATH := "user://record.json"               # лучший выезд: день, время и спасённые люди
const GRAPHICS_PATH := "user://graphics.json"           # настройки графики (масштаб, сглаживание, тени, эффекты)
const GAME_DATA_PATH := "res://data/game_data.json"     # расширяемые данные: места вылазок и рецепты
const AWAKE_LIMIT := 2880        # 48 часов без сна — смерть
const VISITOR_WAIT := 720        # гость ждёт у люка 12 часов и уходит сам
const TRADER_STAY := 480         # торговец стоит у люка 8 часов
# условная ценность ресурсов — по ней считаются сделки с торговцем
const VALUE := {"metal": 1.0, "plastic": 1.3, "wire": 1.5, "fuel": 2.0, "rubber": 1.5, "steel": 4.0, "chips": 5.0,
	"food": 1.0, "seeds": 2.0, "herbs": 1.5, "medkit": 5.0, "potato": 0.6}
const TRADE_GET := {"metal": 4, "plastic": 3, "steel": 1, "chips": 1, "medkit": 1, "food": 4, "seeds": 2, "wire": 3}
const TRADE_GIVE := ["fuel", "rubber", "wire", "plastic", "metal", "food", "herbs", "potato"]
const GEN_COST := {"metal": 1, "wire": 1, "fuel": 1}
const GEN_TANK := 100.0                              # полный бак генератора, %
const GEN_BASE_HOURS := 40.0                         # полный бак при пустом наборе построек — 40 часов
const GEN_HUNGRY := ["lamp", "kitchen", "furnace", "shredder"]  # каждая постройка съедает 2 часа бака
const GEN_HUNGRY_HOURS := 2.0
const DARK_LIMIT := 1800                             # 30 часов после поломки — полная темнота и конец игры
# места на карте вылазок (доска в коридоре): risk — прибавка к шансу травмы, yield — множитель добычи
const SITES := {
	"waste": {"name": "Пустошь", "risk": 0.0, "yield": 1.0, "desc": "руины вокруг бункера: понемногу всего",
		"loot": {"metal": 3.0, "plastic": 2.5, "wire": 2.0, "fuel": 1.5, "rubber": 1.5}},
	"gas": {"name": "АЗС у трассы", "risk": 0.08, "yield": 1.1, "desc": "топливо и резина",
		"loot": {"fuel": 3.5, "rubber": 2.5, "metal": 1.0, "plastic": 1.0}},
	"warehouse": {"name": "Склад стройматериалов", "risk": 0.10, "yield": 1.15, "desc": "металл, пластик и немного стали",
		"loot": {"metal": 3.5, "plastic": 2.0, "wire": 1.5, "steel": 0.7}},
	"pharmacy": {"name": "Аптека", "risk": 0.12, "yield": 1.1, "desc": "аптечки, травы и еда",
		"loot": {"medkit": 0.5, "herbs": 2.5, "food": 2.0}},
	"mall": {"name": "Торговый центр", "risk": 0.16, "yield": 1.2, "desc": "много еды и семян, но тесно и опасно",
		"loot": {"food": 3.5, "seeds": 1.5, "plastic": 1.5, "chips": 0.5}},
	"grid": {"name": "Подстанция", "risk": 0.18, "yield": 1.25, "desc": "платы, провода и сталь",
		"loot": {"chips": 1.5, "wire": 3.0, "steel": 1.0, "metal": 1.0}},
}
const SCOUT_MIN := 180                               # разведка длится 3 часа
# поломки в бункере: стоимость деталей для ремонта
const INC_COST := {"leak": {"rubber": 1, "plastic": 1}, "wire": {"wire": 1, "metal": 1}, "door": {"metal": 1, "plastic": 1}}
const INC_KINDS := {"leak": "Протечка", "wire": "Замыкание", "door": "Дверь заклинило"}
const INC_DESC := {"leak": "Течёт труба: каждый час портится еда.", "wire": "Замыкание в щитке: генератор тратит топливо вдвое быстрее, искры спалили бы платы.",
	"door": "Дверь заклинило: пока не почините, вылазки невозможны."}
const REPAIR_MIN := 120                              # сотрудник чинит поломку 2 часа
# рецепты (готовятся на кухне): buff — какой временный эффект дают
const RECIPES := {
	"stew": {"name": "Похлёбка в дорогу", "cost": {"potato": 1, "food": 1}, "min": 30, "buff": "loot", "desc": "12 ч вылазки приносят +15% добычи"},
	"tea": {"name": "Травяной отвар", "cost": {"herbs": 2}, "min": 20, "buff": "immune", "desc": "24 ч никто не заболеет после вылазки"},
	"roast": {"name": "Горячий ужин", "cost": {"potato": 2, "herbs": 1}, "min": 40, "buff": "stamina", "desc": "всем дома +20 выносливости, вам +15 сытости"},
}
const LOOT_BUFF := 1.15                              # множитель добычи от похлёбки (как у музыки)
# личные просьбы сотрудников: что просят и чем благодарят в ответ
const REQ_POOL := {
	"engineer": [{"res": "wire", "n": 2}, {"res": "chips", "n": 1}, {"res": "metal", "n": 3}],
	"cook": [{"res": "potato", "n": 3}, {"res": "seeds", "n": 1}, {"res": "food", "n": 2}],
	"medic": [{"res": "herbs", "n": 2}, {"res": "medkit", "n": 1}],
	"chemist": [{"res": "rubber", "n": 2}, {"res": "plastic", "n": 2}, {"res": "fuel", "n": 1}],
	"radio_tech": [{"res": "wire", "n": 2}, {"res": "chips", "n": 1}],
	"hunter": [{"res": "food", "n": 1}, {"res": "potato", "n": 2}],
	"scout": [{"res": "rubber", "n": 1}, {"res": "plastic", "n": 1}],
	"teacher": [{"res": "seeds", "n": 1}, {"res": "food", "n": 1}],
	"drifter": [{"res": "food", "n": 2}, {"res": "fuel", "n": 1}],
	"mechanic": [{"res": "metal", "n": 2}, {"res": "rubber", "n": 2}, {"res": "fuel", "n": 1}],
}
const REQ_GIFT := {"engineer": "chips", "cook": "food", "medic": "herbs", "chemist": "fuel", "radio_tech": "chips",
	"hunter": "food", "scout": "wire", "teacher": "seeds", "drifter": "metal", "mechanic": "rubber"}
# ночные происшествия у ворот: незнакомец требует припасы
const GATE_DEMANDS := [
	{"res": "food", "n": 2, "who": "голодный беглец", "look": "Дрожит, смотрит на ваши окна голодными глазами.",
		"text": "У меня трое суток во рту ни крошки. Отдайте два пайка — и я уйду мирно."},
	{"res": "medkit", "n": 1, "who": "раненый человек", "look": "Висит на двери, нога в рваной повязке.",
		"text": "Нога гниёт. Дайте аптечку, и вы больше меня не увидите."},
	{"res": "fuel", "n": 1, "who": "незнакомец с канистрой", "look": "Стоит с пустой канистрой, глаза бегают.",
		"text": "Машина заглохла в трёх километрах. Канистра топлива — и мы в расчёте."},
	{"res": "food", "n": 3, "who": "шантажист", "look": "Широкие плечи, за поясом монтировка.",
		"text": "Склад у вас добрый. Три пайка сейчас — или ночью мы сами зайдём за ними."},
]
const GATE_WAIT := 240                               # незнакомец ждёт ответа 4 часа

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
const StaffDialogue = preload("res://scripts/staff_dialogue.gd")
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
var gen_fuel := GEN_TANK     # топливо в баке генератора, %: пустой бак — генератор глохнет
var gen_broken_at := 0       # когда генератор сломался: от него считается 30 часов до полной темноты
var incidents: Array = []    # поломки: {"id", "kind", "spot", "born", "loss", "loss_txt", "warned"}
var inc_seq := 0             # счётчик поломок (устойчивые id для маркеров и заданий)
var sites := {}              # карта вылазок: id места -> true (разведано)
var buffs := {"loot_until": 0, "immune_until": 0}  # временные бонусы от рецептов
var gate_event := {}         # ночное происшествие у ворот: {"res", "n", "who", "look", "text", "until"}
var gate_gift_at := 0        # когда у ворот найдут свёрток от довольного незнакомца
var record := {}             # плашка рекорда: {"day", "time", "workers"} — переживает сбросы и загрузки
var graphics := {"scale": 1.0, "msaa": 2, "shadows": true, "effects": true, "fullscreen": false}  # настройки графики
var sites_data := {}         # каталог мест вылазок: встроенный SITES + добавки из data/game_data.json
var recipes_data := {}       # каталог рецептов: встроенный RECIPES + добавки из data/game_data.json


func _ready() -> void:
	reset()
	load_graphics()
	load_game_data()


# ---------- места вылазок и рецепты (встроенные + data/game_data.json) ----------
# битые записи из файла пропускаются с предупреждением, каталоги не ломаются
func load_game_data(path := GAME_DATA_PATH) -> void:
	sites_data = SITES.duplicate(true)
	recipes_data = RECIPES.duplicate(true)
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Данные игры: файл %s не открылся — работаю на встроенных значениях." % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("Данные игры: %s — это не JSON-объект, работаю на встроенных значениях." % path)
		return
	var data: Dictionary = parsed
	var sites_in: Variant = data.get("sites", {})
	if sites_in is Dictionary:
		for sid in sites_in:
			var s: Variant = sites_in[sid]
			if _valid_site(s):
				sites_data[sid] = s
			else:
				push_warning("Данные игры: место «%s» пропущено — нужны name, risk ≥ 0, yield > 0 и непустой loot из известных ресурсов." % str(sid))
	var recipes_in: Variant = data.get("recipes", {})
	if recipes_in is Dictionary:
		for rid in recipes_in:
			var r: Variant = recipes_in[rid]
			if _valid_recipe(r):
				recipes_data[rid] = r
			else:
				push_warning("Данные игры: рецепт «%s» пропущен — нужны name, cost из известных ресурсов, min > 0, buff (loot/immune/stamina) и desc." % str(rid))


func _valid_site(s: Variant) -> bool:
	if not (s is Dictionary):
		return false
	var d: Dictionary = s
	if String(d.get("name", "")) == "":
		return false
	if not (d.get("risk", null) is float or d.get("risk", null) is int) or float(d.get("risk", -1.0)) < 0.0:
		return false
	if not (d.get("yield", null) is float or d.get("yield", null) is int) or float(d.get("yield", 0.0)) <= 0.0:
		return false
	var loot: Variant = d.get("loot", null)
	if not (loot is Dictionary) or (loot as Dictionary).is_empty():
		return false
	for k in loot:
		if not RES.has(k):
			return false  # неизвестный ресурс сломал бы добычу — запись целиком пропускается
		if not (loot[k] is float or loot[k] is int) or float(loot[k]) <= 0.0:
			return false
	return true


func _valid_recipe(r: Variant) -> bool:
	if not (r is Dictionary):
		return false
	var d: Dictionary = r
	if String(d.get("name", "")) == "" or String(d.get("desc", "")) == "":
		return false
	var cost: Variant = d.get("cost", null)
	if not (cost is Dictionary) or (cost as Dictionary).is_empty():
		return false
	for k in cost:
		if not RES.has(k):
			return false
		if not (cost[k] is float or cost[k] is int) or int(cost[k]) <= 0:
			return false
	if not (d.get("min", null) is float or d.get("min", null) is int) or int(d.get("min", 0)) <= 0:
		return false
	if not ["loot", "immune", "stamina"].has(String(d.get("buff", ""))):
		return false
	return true


# ---------- настройки графики ----------
func load_graphics() -> void:
	if not FileAccess.file_exists(GRAPHICS_PATH):
		return
	var f := FileAccess.open(GRAPHICS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in graphics.keys():
			if data.has(k):
				graphics[k] = data[k]


func save_graphics() -> void:
	var f := FileAccess.open(GRAPHICS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(graphics))


func reset() -> void:
	t = 420
	res = {"metal": 5, "plastic": 3, "wire": 3, "fuel": 2, "rubber": 2, "steel": 0, "chips": 0, "seeds": 3, "potato": 0, "food": 12, "herbs": 0, "medkit": 1}
	built = {"garden": false, "lamp": false, "irrig": false, "kitchen": false, "furnace": false, "shredder": false, "medbed": false, "medcab": false, "filter": false, "insul": false, "coffee": false}
	upg = {"garden": 0, "kitchen": 0, "furnace": 0, "shredder": 0, "medbed": 0, "medcab": 0}
	crop = {"state": "empty", "kind": "", "ready": 0}
	gear = {"pack": 0, "magnet": 0, "drill": 0}
	car = {"engine": false, "wheels": false, "battery": false, "tank": false}
	# напарник с вами с самого первого дня: он сам предлагает осмотреться и показывает бункер
	workers = []
	var pi := _npc_index("Игорь")
	if pi >= 0:
		var d: Dictionary = NPC_DEFS[pi]
		workers.append({
			"name": d.name, "prof": d.prof, "cap": d.cap, "eff": d.eff,
			"st": 100, "hp": 100, "sick": false,
			"away": null, "dead": false, "xp": 0, "lvl": 1, "suit": d.suit,
			"maniac": false, "kill_at": -1,
			"bed": -1, "asleep": false, "nobed": false, "nosleep": 0, "music_at": -99999,
			"loyal": 0, "loyal50": false, "loyal90": false, "req": {}, "task": null, "talk_at": -99999, "last_chat": "",
		})
	npc_pool = range(NPC_DEFS.size())
	npc_pool.erase(pi)  # напарник уже в бункере — у ворот он не стучится
	visitor = {}
	log_lines = ["День 1. Вы и напарник Игорь. Давайте осмотримся — другие гости придут со 2-го дня.",
		"Генератору нужна дозаправка (1 топливо): бака хватает на ~40 часов, а постройки съедают время работы."]
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
	gen_fuel = GEN_TANK
	gen_broken_at = 0
	incidents = []
	inc_seq = 0
	sites = {"waste": true}
	buffs = {"loot_until": 0, "immune_until": 0}
	gate_event = {}
	gate_gift_at = 0
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
	# генератор тратит топливо (быстрее — чем больше построек): пустой бак — он глохнет
	if not gen_broken:
		gen_fuel = maxf(0.0, gen_fuel - 100.0 / (gen_runtime_hours() * 60.0) * 10.0 * (2.0 if inc_active("wire") else 1.0))
		if gen_fuel <= 0.0:
			_blackout("Генератор заглох: бак пуст.")
	# полная темнота через 30 часов без генератора — конец игры
	if gen_broken:
		var dark := t - gen_broken_at
		if dark >= DARK_LIMIT:
			end_state = "lose"
			why = "Свет погас полностью: 30 часов без генератора бункер не выдержал. Дозаправляйте вовремя — 1 топливо."
			log_add("В бункере стало темно окончательно. Конец.")
			delete_save()
			return
		if dark >= 900 and not milestones.has("dark_half"):
			milestones["dark_half"] = true
			log_add("Темнота сгущается: половина из 30 часов прошла, а генератор всё ещё сломан.")
		if dark >= 1440 and not milestones.has("dark_warn"):
			milestones["dark_warn"] = true
			log_add("Осталось 6 часов до полной темноты! Почините генератор (%s)." % cost_text(GEN_COST))
	# свёрток от довольного незнакомца
	if gate_gift_at > 0 and t >= gate_gift_at:
		gate_gift_at = 0
		var gift: String = ["food", "metal", "wire", "plastic"].pick_random()
		res[gift] += 2
		log_add("У ворот нашли свёрток: %s +2. Кто-то помнит добро." % RES[gift])
	# незнакомец у ворот потерял терпение
	if not gate_event.is_empty() and t >= int(gate_event.until):
		_gate_vandal("Вы не ответили — и ночью у ворот кто-то хозяйничал.")
	# ночные происшествия у ворот: 23:00 и 03:00
	if (t % 1440 == 1380 or t % 1440 == 180) and day() >= 3:
		_maybe_gate_event()
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
		var task: Variant = w.get("task", null)
		if task != null and t >= int(task.until):
			w.task = null
			_finish_repair(w, task)
		if w.away == null:
			if not w.sick and not regen_blocked():
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
	if gen_broken:
		log_add("Ворота обесточены: генератор не работает — %s ждёт у окна. Почините генератор, чтобы впустить." % visitor.name)
		changed.emit()
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
		"loyal": 0, "loyal50": false, "loyal90": false, "req": {}, "task": null, "talk_at": -99999, "last_chat": "",
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
	var scout_site := String(a.get("scout", ""))
	var loot := {}
	var parts: Array = []
	if scout_site != "":
		# разведка: дорога на карту + немного припасов по пути
		var was_new := not bool(sites.get(scout_site, false))
		sites[scout_site] = true
		for k in ["metal", "plastic", "fuel"]:
			if randf() < 0.6:
				loot[k] = 2
		for k in loot:
			res[k] += loot[k]
			parts.append("%s ×%d" % [RES[k], loot[k]])
		var head := "дорога к «%s» нанесена на карту" % sites_data[scout_site].name
		if not parts.is_empty():
			head += ", по пути собрал: " + ", ".join(parts)
		log_add("%s вернулся из разведки: %s." % [w.name, head])
		if was_new and not milestones.has("scout"):
			milestones["scout"] = true
			log_add("★ Первая разведка удалась: на карте появились новые места — проверьте доску в коридоре.")
		Snd.play("levelup" if was_new else "loot")
		_level_up(w, 15)
	else:
		loot = _loot(w, a)
		for k in loot:
			res[k] += loot[k]
			parts.append("%s ×%d" % [RES[k], loot[k]])
		var msg := "%s вернулся" % w.name
		if not parts.is_empty():
			msg += ": " + ", ".join(parts)
		else:
			msg += " с пустыми руками"
		if a.get("music", false):
			msg += " (+15% от музыки)"
		log_add(msg)
		if randf() < 0.15:
			var bonus: String = RAW.pick_random()
			res[bonus] += 2
			log_add("%s наткнулся на тайник: %s +2!" % [w.name, RES[bonus]])
		Snd.play("loot")
		_level_up(w, 25)
	if randf() < a.risk:
		var dmg := randi_range(15, 40)
		w.hp = maxi(1, w.hp - dmg)
		log_add("%s получил травму (−%d здоровья)." % [w.name, dmg])
	var immune := t < int(buffs.immune_until)
	if a.cold and not w.sick and not immune and randf() < (0.08 if built.filter else 0.25):
		w.sick = true
		log_add("%s заболел после вылазки." % w.name)
	elif a.cold and immune and not w.sick:
		log_add("Травяной отвар уберёг %s от болезни." % w.name)
	worker_back.emit(i, true)


# Добыча — 1–3 РАЗНЫХ вида ресурсов (а не один вид на всю вылазку); веса зависят от места на карте.
func _loot(w: Dictionary, a: Dictionary) -> Dictionary:
	var site: Dictionary = sites_data[String(a.get("site", "waste"))]
	var weights: Dictionary = site.loot.duplicate()
	match w.prof:
		"engineer":
			weights["chips"] = float(weights.get("chips", 0.0)) + 1.0
			weights["wire"] = float(weights.get("wire", 0.0)) + 1.0
		"mechanic":
			weights["rubber"] = float(weights.get("rubber", 0.0)) + 1.0
			weights["fuel"] = float(weights.get("fuel", 0.0)) + 1.0
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
		if t < int(buffs.loot_until):
			amount *= LOOT_BUFF  # походная похлёбка
		amount *= float(site.yield)
		var whole := int(floor(amount))
		out[k] = maxi(1, whole + (1 if randf() < amount - float(whole) else 0))
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


# Можно ли отправить сотрудника прямо сейчас (для галочек в окне экспедиции)
func sendable(i: int) -> bool:
	if i < 0 or i >= workers.size():
		return false
	var w: Dictionary = workers[i]
	return not w.dead and w.away == null and not w.get("asleep", false) and w.get("task", null) == null \
		and w.st >= MIN_STAMINA and w.hp >= MIN_HP and not w.sick


func send(i: int, use_pack: bool, tool: String, site := "waste") -> bool:
	var w: Dictionary = workers[i]
	if w.dead or w.away != null or w.get("asleep", false) or w.get("task", null) != null or w.st < MIN_STAMINA or w.hp < MIN_HP or w.sick:
		return false
	if gen_broken:
		log_add("Генератор обесточен: люк не откроется — почините генератор.")
		changed.emit()
		return false
	if inc_active("door"):
		log_add("Дверь заклинило — до ремонта вылазки невозможны.")
		changed.emit()
		return false
	if not bool(sites.get(site, false)):
		return false
	var wx := trip_weather(t)
	w.st -= 20 if w.prof == "scout" else MIN_STAMINA
	var risk := 0.12 + 0.18 * float(wx.k) + float(sites_data[site].risk)
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
		"site": site,
	}
	log_add("%s вышел на поверхность: %s%s." % [w.name, sites_data[site].name, " под настроение от музыки" if w.away.music else ""])
	worker_left.emit(i)
	changed.emit()
	return true


# Разведка: короткий выход, открывает новое место на карте
func scout(i: int, site: String) -> bool:
	var w: Dictionary = workers[i]
	if w.dead or w.away != null or w.get("asleep", false) or w.get("task", null) != null or w.st < MIN_STAMINA or w.hp < MIN_HP or w.sick:
		return false
	if gen_broken:
		log_add("Генератор обесточен: люк не откроется — почините генератор.")
		changed.emit()
		return false
	if inc_active("door"):
		log_add("Дверь заклинило — до ремонта разведка невозможна.")
		changed.emit()
		return false
	if bool(sites.get(site, false)):
		return false
	var wx := trip_weather(t)
	w.st -= 20 if w.prof == "scout" else MIN_STAMINA
	w.away = {
		"ret": t + SCOUT_MIN,
		"bad": wx.bad,
		"risk": 0.10 + float(sites_data[site].risk) * 0.7,
		"cold": wx.temp < -8 or wx.wind >= 12,
		"scout": site,
	}
	log_add("%s вышел на разведку: дорога к «%s», вернётся через 3 часа." % [w.name, sites_data[site].name])
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
	_incidents_hourly()


# ---------- поломки в бункере ----------
func inc_active(kind: String) -> bool:
	for inc in incidents:
		if inc.kind == kind:
			return true
	return false


func regen_blocked() -> bool:
	# уют упал: любая поломка старше 12 часов лишает сотрудников восстановления сил
	for inc in incidents:
		if t - int(inc.born) >= 720:
			return true
	return false


func _incidents_hourly() -> void:
	# появление поломок: со 2-го дня, максимум две активные одновременно
	if day() >= 2 and incidents.size() < 2 and randf() < 0.12:
		inc_seq += 1
		var kind: String = INC_KINDS.keys().pick_random()
		incidents.append({"id": inc_seq, "kind": kind, "spot": randi() % 6, "born": t, "loss": 0, "loss_txt": ""})
		log_add("Поломка: %s. Почините деталями (подойдите к месту) или отправьте сотрудника." % INC_KINDS[kind])
		Snd.play("alarm")
	for inc in incidents:
		match inc.kind:
			"leak":
				if res.food > 0:
					res.food -= 1
					inc.loss += 1
					inc.loss_txt = "еда ×%d" % int(inc.loss)
			"wire":
				if randf() < 0.25:
					var k := "wire"
					if (res.chips > 0 and res.wire == 0) or (res.chips > 0 and randf() < 0.5):
						k = "chips"
					if res[k] > 0:
						res[k] -= 1
						inc.loss += 1
						inc.loss_txt = "%s ×%d" % [RES[k], int(inc.loss)]
		if t - int(inc.born) >= 720 and not inc.has("warned"):
			inc.warned = true
			log_add("Уют падает: %s давит на всех — силы дома больше не восстанавливаются." % String(INC_KINDS[inc.kind]).to_lower())


func _inc_index(id: int) -> int:
	for j in incidents.size():
		if incidents[j].id == id:
			return j
	return -1


func fix_incident(id: int) -> void:
	var idx := _inc_index(id)
	if idx < 0:
		return
	var inc: Dictionary = incidents[idx]
	var cost: Dictionary = INC_COST[inc.kind]
	if not can(cost):
		return
	for k in cost:
		res[k] -= cost[k]
	var lost := "" if int(inc.loss) == 0 else " Потери: %s." % String(inc.loss_txt)
	incidents.remove_at(idx)
	log_add("Вы устранили %s (30 мин).%s" % [String(INC_KINDS[inc.kind]).to_lower(), lost])
	Snd.play("craft")
	advance(30)


func send_repair(i: int, id: int) -> bool:
	if i < 0 or i >= workers.size() or _inc_index(id) < 0:
		return false
	var w: Dictionary = workers[i]
	if w.dead or w.away != null or w.get("asleep", false) or w.get("task", null) != null:
		return false
	w.task = {"inc": id, "until": t + REPAIR_MIN}
	log_add("%s взялся за ремонт: %s (2 ч)." % [w.name, String(INC_KINDS[incidents[_inc_index(id)].kind]).to_lower()])
	changed.emit()
	return true


func _finish_repair(w: Dictionary, task: Variant) -> void:
	# поломку могли успеть починить вручную — тогда просто спасибо
	var idx := _inc_index(int(task.inc))
	if idx < 0:
		log_add("%s закончил обход — поломку уже устранили." % w.name)
		return
	var inc: Dictionary = incidents[idx]
	var lost := "" if int(inc.loss) == 0 else " Потери: %s." % String(inc.loss_txt)
	incidents.remove_at(idx)
	log_add("%s устранил %s (2 ч).%s" % [w.name, String(INC_KINDS[inc.kind]).to_lower(), lost])
	_level_up(w, 20)
	Snd.play("craft")


func _daily() -> void:
	save_game(true)  # автосохранение каждое утро
	if day() in [7, 14, 21, 28]:
		log_add("★ %d дней в бункере — вы держитесь молодцом!" % day())
	if living_workers() > beds:
		log_add("Кроватей не хватает: %d из %d. Без кровати сотрудник гибнет после двух суток без сна." % [beds, living_workers()])
	if day() >= 3 and not gen_broken and randf() < 0.12:
		_blackout("Генератор сломался сам.")
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
	# личные просьбы: у свободных сотрудников без просьбы они появляются со временем
	for w in workers:
		if w.dead or w.away != null or day() < 2:
			continue
		var req: Variant = w.get("req", null)
		if req == null or (req as Dictionary).is_empty():
			if randf() < 0.4:
				_assign_request(w)


func _assign_request(w: Dictionary) -> void:
	var pool: Array = REQ_POOL.get(w.prof, [{"res": "food", "n": 1}])
	var r: Dictionary = pool.pick_random()
	w.req = {"res": r.res, "n": r.n}
	log_add("%s просит: %s ×%d. Подойдите и поговорите с ним." % [w.name, RES[r.res], r.n])


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
	if gen_broken and (r.station == "furnace" or r.station == "shredder"):
		log_add("Нет электричества: %s стоит — почините генератор." % ("плавильная печь" if r.station == "furnace" else "измельчитель"))
		changed.emit()
		return
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
	gen_broken_at = 0
	milestones.erase("dark_half")
	milestones.erase("dark_warn")
	gen_fuel = GEN_TANK
	log_add("Генератор починен и заправлен под завязку — свет вернулся, двери и печи снова работают.")
	Snd.play("craft")
	advance(30)


# Поломка генератора: обесточены двери, печь и измельчитель, свет гаснет 30 часов до конца игры
func _blackout(prefix: String) -> void:
	gen_broken = true
	gen_broken_at = t
	log_add("%s Ворота и люк обесточены, печь и измельчитель стоят, свет над грядкой погас. До полной темноты — 30 часов: почините генератор (%s)." % [prefix, cost_text(GEN_COST)])
	Snd.play("alarm")
	changed.emit()


# Насколько бункер погрузился в темноту: 0 — свет горит, 1 — полная тьма
func darkness_factor() -> float:
	if not gen_broken:
		return 0.0
	return clampf(float(t - gen_broken_at) / float(DARK_LIMIT), 0.0, 1.0)


# ---------- обслуживание генератора ----------
# На сколько часов хватает полного бака: лампа грядки, кухня, печь и измельчитель съедают по 2 часа
func gen_runtime_hours() -> float:
	var h := GEN_BASE_HOURS
	for k in GEN_HUNGRY:
		if built.get(k, false):
			h -= GEN_HUNGRY_HOURS
	return maxf(h, 8.0)


func gen_hours() -> int:
	return int(gen_fuel * gen_runtime_hours() / 100.0)


func gen_refuel() -> void:
	if gen_broken or res.fuel < 1 or gen_fuel >= GEN_TANK - 1.0:
		return
	res.fuel -= 1
	gen_fuel = GEN_TANK
	log_add("Генератор заправлен под завязку: бак 100%.")
	Snd.play("craft")
	advance(20)


# ---------- разговоры и личные просьбы ----------
func talk_ready(i: int) -> bool:
	if i < 0 or i >= workers.size():
		return false
	var w: Dictionary = workers[i]
	return not w.dead and t >= int(w.get("talk_at", -99999)) + 180


func talk(i: int) -> void:
	if i < 0 or i >= workers.size():
		return
	var w: Dictionary = workers[i]
	if w.dead or t < int(w.get("talk_at", -99999)) + 180:
		return
	w.talk_at = t
	w.loyal = int(w.get("loyal", 0)) + 1
	w.last_chat = StaffDialogue.chat_line(String(w.prof), String(w.name))
	Snd.play("talk")
	changed.emit()


func fulfill_request(i: int) -> void:
	if i < 0 or i >= workers.size():
		return
	var w: Dictionary = workers[i]
	var req: Variant = w.get("req", null)
	if w.dead or req == null or (req as Dictionary).is_empty():
		return
	var cost := {String(req.res): int(req.n)}
	if not can(cost):
		return
	for k in cost:
		res[k] -= cost[k]
	w.req = {}
	w.loyal = int(w.get("loyal", 0)) + 10
	_level_up(w, 25)
	if randf() < 0.5:
		var g: String = REQ_GIFT.get(w.prof, "food")
		var n := 2 if float(VALUE[g]) >= 2.0 else 3
		res[g] += n
		log_add("%s благодарит: принёс в ответ %s ×%d. Лояльность %d." % [w.name, RES[g], n, int(w.loyal)])
	else:
		log_add("%s благодарит: теперь он держится за бункер (лояльность %d)." % [w.name, int(w.loyal)])
	if int(w.loyal) >= 50 and not bool(w.get("loyal50", false)):
		w.loyal50 = true
		w.eff = float(w.eff) + 0.05
		log_add("★ %s вам доверяет: его добыча теперь ×%.2f." % [w.name, float(w.eff)])
	if int(w.loyal) >= 90 and not bool(w.get("loyal90", false)):
		w.loyal90 = true
		w.cap += 1
		log_add("★ %s предан бункеру: +1 вместимость." % w.name)
	Snd.play("loot")
	changed.emit()


# ---------- готовка по рецептам ----------
func cook(id: String) -> void:
	var r: Dictionary = recipes_data[id]
	if not built.kitchen or not can(r.cost):
		return
	for k in r.cost:
		res[k] -= r.cost[k]
	match r.buff:
		"loot":
			buffs.loot_until = t + 720
		"immune":
			buffs.immune_until = t + 1440
		"stamina":
			for w in workers:
				if not w.dead and w.away == null:
					w.st = mini(100, w.st + 20)
			player_food = mini(100, player_food + 15)
	log_add("Приготовлено: %s — %s." % [r.name, r.desc])
	Snd.play("craft")
	station_used.emit("kitchen")
	advance(int(round(float(r.min) * (0.6 if upg.kitchen >= 1 else 1.0))))


# ---------- происшествия у ворот ----------
func _maybe_gate_event() -> void:
	if randf() > 0.35 or not gate_event.is_empty() or visitor != {} or not trader.is_empty():
		return
	var d: Dictionary = GATE_DEMANDS.pick_random()
	gate_event = {
		"res": d.res, "n": d.n, "who": d.who, "look": d.look, "text": d.text,
		"until": t + GATE_WAIT,
	}
	log_add("Стук в ворота: %s требует %s ×%d. Решайте, пока он не потерял терпение." % [d.who, RES[d.res], d.n])
	Snd.play("knock")
	changed.emit()


func gate_give() -> void:
	if gate_event.is_empty():
		return
	var cost := {String(gate_event.res): int(gate_event.n)}
	if not can(cost):
		return
	for k in cost:
		res[k] -= cost[k]
	log_add("Вы передали %s ×%d через смотровое окно. %s уходит." % [RES[gate_event.res], int(gate_event.n), gate_event.who])
	if randf() < 0.35:
		gate_gift_at = t + randi_range(180, 600)
		log_add("«Я этого не забуду», — говорит он и скрывается в темноте.")
	gate_event = {}
	Snd.play("loot")
	changed.emit()


func _gate_vandal(prefix: String) -> void:
	# недовольный незнакомец мстит: сливает топливо генератора или тащит припасы
	if randf() < 0.5 and gen_fuel > 5.0:
		var stolen := minf(gen_fuel, 25.0)
		gen_fuel -= stolen
		log_add("%s Они слили топливо из генератора (−%d%%)." % [prefix, int(stolen)])
	else:
		var k := "food"
		if res.food <= 0 and res.metal > 0:
			k = "metal"
		if res[k] > 0:
			var n := mini(int(res[k]), randi_range(1, 3))
			res[k] -= n
			log_add("%s Утащили %s ×%d." % [prefix, RES[k], n])
		else:
			log_add("%s Запасов, к счастью, не тронули." % prefix)
	gate_event = {}
	changed.emit()


func gate_refuse() -> void:
	if gate_event.is_empty():
		return
	if randf() < 0.55:
		log_add("Вы отказали. %s ругается на прощание и уходит." % gate_event.who)
		gate_event = {}
	else:
		_gate_vandal("Вы отказали — и ночью у ворот кто-то хозяйничал.")
	Snd.play("click")
	changed.emit()


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
		"t": t, "gen_broken": gen_broken, "gen_broken_at": gen_broken_at, "radio_music_at": radio_music_at,
		"player_food": player_food, "player_st": player_st, "player_last_sleep": player_last_sleep, "beds": beds,
		"player_awake": player_awake, "player_sleep_until": player_sleep_until, "starve_min": starve_min,
		"visitor_until": visitor_until, "last_status": last_status, "trader": trader,
		"radio_call_at": radio_call_at, "radio_signal_at": radio_signal_at, "radio_signal": radio_signal,
		"gen_fuel": gen_fuel, "incidents": incidents, "inc_seq": inc_seq,
		"sites": sites, "buffs": buffs, "gate_event": gate_event, "gate_gift_at": gate_gift_at,
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
	# старые сохранения без метки поломки: даём полные 30 часов темноты с момента загрузки
	gen_broken_at = int(data.get("gen_broken_at", t if bool(data.get("gen_broken", false)) else 0))
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
	gen_fuel = float(data.get("gen_fuel", GEN_TANK))
	inc_seq = int(data.get("inc_seq", 0))
	incidents = []
	for inc in data.get("incidents", []):
		incidents.append({"id": int(inc.id), "kind": String(inc.kind), "spot": int(inc.spot), "born": int(inc.born),
			"loss": int(inc.get("loss", 0)), "loss_txt": String(inc.get("loss_txt", "")), "warned": bool(inc.get("warned", false))})
	sites = {"waste": true}
	for k in data.get("sites", {}):
		sites[k] = bool(data.sites[k])
	var bl: Dictionary = data.get("buffs", {})
	buffs = {"loot_until": int(bl.get("loot_until", 0)), "immune_until": int(bl.get("immune_until", 0))}
	gate_event = data.get("gate_event", {}) if (data.get("gate_event", {}) is Dictionary) else {}
	gate_gift_at = int(data.get("gate_gift_at", 0))
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
			"away": ({"ret": int(away.ret), "bad": bool(away.bad), "risk": float(away.risk), "cold": bool(away.cold),
				"pack": bool(away.pack), "tool": String(away.tool), "music": bool(away.get("music", false)),
				"site": String(away.get("site", "waste")), "scout": String(away.get("scout", ""))} if away_ok else null),
			"music_at": int(w.get("music_at", -99999)),
			"loyal": int(w.get("loyal", 0)), "loyal50": bool(w.get("loyal50", false)), "loyal90": bool(w.get("loyal90", false)),
			"req": (w.req if (w.get("req", null) is Dictionary) else {}),
			"task": (w.task if (w.get("task", null) is Dictionary) else null),
			"talk_at": int(w.get("talk_at", -99999)), "last_chat": String(w.get("last_chat", "")),
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


# ---------- рекорд: лучший выезд и спасённые люди ----------
func load_record() -> Dictionary:
	if not record.is_empty():
		return record
	if not FileAccess.file_exists(RECORD_PATH):
		return {}
	var f := FileAccess.open(RECORD_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		record = data
	return record


# Пишем только если результат лучше: раньше день, при равном дне — больше спасённых
func save_record() -> void:
	var day_n := day()
	var saved_n := living_workers()
	var old := load_record()
	var better: bool = old.is_empty() or day_n < int(old.get("day", 999)) \
		or (day_n == int(old.get("day", 999)) and saved_n > int(old.get("workers", 0)))
	if not better:
		return
	record = {"day": day_n, "time": fmt(t), "workers": saved_n}
	var f := FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(record))


func drive_out() -> void:
	if car_done():
		save_record()
		end_state = "win"
		changed.emit()
