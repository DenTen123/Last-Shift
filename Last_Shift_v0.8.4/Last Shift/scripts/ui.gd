extends CanvasLayer
## Минимальный HUD: постоянно видны только время и день.
## Остальное — по запросу: окна объектов, гости, журнал (J), помощь (H),
## всплывающие события и контекстные подсказки.

signal drive_requested

const GOLD := Color("e8b53a")
const TXT := Color("ffffff")
const DIM := Color("aebab2")
const BAD := Color("e0604f")
const OK := Color("5fbf7a")

# Иконки ищутся по id объекта: <id>.png в любой из этих папок.
# Нет файла с таким именем — место под иконку остаётся пустым.
# Чтобы добавить иконку, положи PNG с именем id (например kitchen.png, bed.png, rubber.png).
const ICON_DIRS := [
	"res://scripts/icons/",
	"res://assets/ui/icons/",
	"res://icons/",
]
const StaffDialogue = preload("res://scripts/staff_dialogue.gd")

# иконка каждой локации на карте (id из ICON_DIRS)
const SITE_ICONS := {"waste": "metal", "gas": "fuel", "warehouse": "steel", "pharmacy": "medkit", "mall": "food", "grid": "chips"}

var modal := ""
var selected: Array = []   # отмеченные галочками сотрудники для вылазки
var pick_pack := false
var pick_tool := ""
var pick_site := "waste"   # место вылазки на карте
var scout_w := 0          # сотрудник, выбранный для разведки

var _hud: Control
var _modal_root: Control
var _menu_layer: Control = null  # постоянный слой главного меню: настройки открываются поверх обложки
var _settings_from_menu := false # настройки открыты из главного меню — обложка остаётся фоном
var _time_label: Label
var _day_label: Label
var _sat_bar: ProgressBar
var _bod_bar: ProgressBar
var _sat_fill: StyleBoxFlat
var _bod_fill: StyleBoxFlat
var _sat_lbl: Label
var _bod_lbl: Label
var _sleep_lbl: Label
var _res_box: VBoxContainer
var _res_lbls: Dictionary = {}
var _wx_lbl: Label
var _npc_mode := 0         # 0 — гость, 1 — торговец, 2 — незнакомец у ворот
var _visitor_btns: Array = []
var _trader_btns: Array = []
var _gate_btns: Array = []
var _gate_give_btn: Button
var _pause_label: Label
var _hint_label: Label
var _toasts: VBoxContainer
var _npc_bar: PanelContainer
var _npc_accept_btn: Button
var _npc_story: PanelContainer
var _npc_story_scroll: ScrollContainer
var _npc_story_title: Label
var _npc_story_text: Label
var _npc_camera: Camera3D
var _npc_target: Node3D
var _modal_sc: ScrollContainer
var _last_top := ""
var _last_end := ""
var _scroll := 0.0
var _intro_pending := false  # вступительные подсказки покажем после выбора в главном меню


func _ready() -> void:
	_build_static()
	Game.changed.connect(_on_changed)
	_on_changed()


func open_modal(id: String) -> void:
	modal = id
	refresh()


# ---------- рассказ сбоку от модели; решение — внизу ----------
func show_npc_bar(camera: Camera3D, target: Node3D) -> void:
	if Game.visitor.is_empty():
		return
	_set_npc_mode(0)
	_npc_camera = camera
	_npc_target = target
	var pf: Dictionary = Game.PROFS[Game.visitor.prof]
	_npc_story_title.text = "%s · %s" % [Game.visitor.name, pf.name]
	_npc_story_text.text = "Профессия — %s: %s.\n\n«%s»" % [pf.name, pf.desc, Game.visitor_story()]
	_update_npc_accept()
	_npc_story_scroll.scroll_vertical = 0
	_npc_bar.visible = true
	_npc_story.visible = true
	_place_npc_story()


# Торговец у ворот: внутрь не заходит, только меняется через смотровое окно
func show_trader_bar(camera: Camera3D, target: Node3D) -> void:
	if Game.trader.is_empty():
		Game.npc_wait.emit()
		return
	_set_npc_mode(1)
	_npc_camera = camera
	_npc_target = target
	var left: int = maxi(1, (int(Game.trader.until) - Game.t) / 60)
	_npc_story_title.text = "Торговец"
	_npc_story_text.text = "Торговец не заходит в бункер: он стоит у ворот и меняет товары на ваши излишки через смотровое окно. Уйдёт примерно через %d ч." % left
	_npc_story_scroll.scroll_vertical = 0
	_npc_bar.visible = true
	_npc_story.visible = true
	_place_npc_story()


# Ночное происшествие: незнакомец требует припасы — отдать или прогнать
func show_gate_bar(camera: Camera3D, target: Node3D) -> void:
	if Game.gate_event.is_empty():
		Game.npc_wait.emit()
		return
	_set_npc_mode(2)
	_npc_camera = camera
	_npc_target = target
	var ge: Dictionary = Game.gate_event
	var left: int = maxi(1, (int(ge.until) - Game.t) / 60)
	_npc_story_title.text = "Незнакомец · %s" % ge.who
	_npc_story_text.text = "%s\n\n«%s»\n\nТребует: %s ×%d. Терпения хватит на ~%d ч: молчание он сочтёт за отказ." % [ge.look, ge.text, Game.RES[ge.res], int(ge.n), left]
	_gate_give_btn.text = "Отдать %s ×%d" % [Game.RES[ge.res], int(ge.n)]
	_gate_give_btn.disabled = not Game.can({String(ge.res): int(ge.n)})
	_npc_story_scroll.scroll_vertical = 0
	_npc_bar.visible = true
	_npc_story.visible = true
	_place_npc_story()


func _set_npc_mode(mode: int) -> void:
	_npc_mode = mode
	for b in _visitor_btns:
		(b as Button).visible = mode == 0
	for b in _trader_btns:
		(b as Button).visible = mode == 1
	for b in _gate_btns:
		(b as Button).visible = mode == 2


func _trader_trade() -> void:
	Game.npc_wait.emit()  # отходим от окна, камера возвращается
	open_modal("trader")


# Принять гостя можно только при свободной кровати и работающем генераторе
func _update_npc_accept() -> void:
	if _npc_accept_btn == null:
		return
	if Game.gen_broken:
		_npc_accept_btn.disabled = true
		_npc_accept_btn.text = "Ворота обесточены"
		_npc_accept_btn.tooltip_text = "Генератор сломан: электропривод ворот не работает. Почините генератор и вернитесь к окну."
		return
	var free := Game.free_beds()
	_npc_accept_btn.disabled = free < 1
	_npc_accept_btn.text = "Пустить в бункер" if free >= 1 else "Нет свободной кровати"
	_npc_accept_btn.tooltip_text = "Свободных кроватей: %d из %d. Новые кровати строятся на верстаке." % [maxi(free, 0), Game.beds]


func hide_npc_bar() -> void:
	_npc_bar.visible = false
	_npc_story.visible = false
	_npc_camera = null
	_npc_target = null


func _npc_screen_bounds(node: Node, bounds: Rect2) -> Rect2:
	if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh != null:
		var box: AABB = node.get_aabb()
		for i in 8:
			var point: Vector3 = node.global_transform * box.get_endpoint(i)
			if not _npc_camera.is_position_behind(point):
				bounds = bounds.expand(_npc_camera.unproject_position(point))
	for child in node.get_children():
		bounds = _npc_screen_bounds(child, bounds)
	return bounds


func _place_npc_story() -> void:
	if not is_instance_valid(_npc_camera) or not is_instance_valid(_npc_target):
		if _npc_mode == 1:
			Game.npc_wait.emit()
		else:
			hide_npc_bar()
		return
	var screen := get_viewport().get_visible_rect().size
	var point := _npc_camera.unproject_position(_npc_target.global_position)
	# Учитываем всю модель, включая нож и другие диагностические предметы.
	var protected := _npc_screen_bounds(_npc_target, Rect2(point, Vector2.ZERO)).grow(24.0)
	var bottom := screen.y - 92.0
	var right_x := maxf(16.0, protected.end.x)
	var left_width := minf(380.0, protected.position.x - 32.0)
	var right_width := minf(380.0, screen.x - right_x - 16.0)
	var area: Rect2
	if maxf(left_width, right_width) >= 220.0:
		var on_left := left_width >= right_width
		area = Rect2(16.0 if on_left else right_x, 92.0, left_width if on_left else right_width, bottom - 92.0)
	else:
		# На узком окне используем свободную полосу над или под моделью.
		var top_height := protected.position.y - 108.0
		var below_y := maxf(92.0, protected.end.y)
		var below_height := bottom - below_y
		area = Rect2(16.0, 92.0 if top_height >= below_height else below_y, screen.x - 32.0, maxf(top_height, below_height))
	# Если места физически нет, не накрываем персонажа текстом.
	_npc_story.visible = area.size.x >= 180.0 and area.size.y >= 100.0
	if not _npc_story.visible:
		return
	_npc_story.position = area.position
	_npc_story.size = Vector2(area.size.x, minf(360.0, area.size.y))


func set_hint(s: String) -> void:
	_hint_label.text = s
	_hint_label.visible = s != ""


func toast(s: String) -> void:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", _toast_style())
	var l := _lbl(s, 14, TXT, true)
	l.custom_minimum_size = Vector2(330, 0)
	pc.add_child(l)
	pc.modulate.a = 0.0
	_toasts.add_child(pc)
	var tw := create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.5)
	tw.tween_property(pc, "modulate:a", 0.0, 0.7)
	tw.tween_callback(pc.queue_free)
	while _toasts.get_child_count() > 5:
		var c: Node = _toasts.get_child(0)
		_toasts.remove_child(c)
		c.queue_free()


# ---------- помощники ----------
func _outl(l: Label) -> Label:
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


func _lbl(txt: String, size := 16, col := TXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(txt: String, cb: Callable, off := false) -> Button:
	var b := Button.new()
	b.text = txt
	b.disabled = off
	b.focus_mode = Control.FOCUS_NONE
	if not cb.is_null():
		b.pressed.connect(cb)  # часть кнопок только показывает состояние — действия у них нет
	b.pressed.connect(Snd.play.bind("click"))
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.13, 0.17, 0.15)
	n.set_corner_radius_all(7)
	n.content_margin_left = 12.0
	n.content_margin_right = 12.0
	n.content_margin_top = 6.0
	n.content_margin_bottom = 6.0
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.19, 0.25, 0.21)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(0.09, 0.12, 0.1)
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(0.08, 0.09, 0.09)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", TXT)
	b.add_theme_color_override("font_disabled_color", DIM)
	return b


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.075, 0.065, 0.96)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.9, 0.7, 0.1, 0.25)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


func _toast_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.055, 0.05, 0.82)
	sb.set_corner_radius_all(8)
	sb.border_width_left = 2
	sb.border_color = GOLD
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	return sb


func _ignore_mouse(n: Node) -> void:
	if n is Control and not (n is BaseButton):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


# ---------- постоянный минимум ----------
func _build_static() -> void:
	_apply_graphics()
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_time_label = _outl(_lbl("00:00", 34, GOLD))
	_time_label.position = Vector2(16, 8)
	_hud.add_child(_time_label)
	_day_label = _outl(_lbl("День 1 из 30", 15, TXT))
	_day_label.position = Vector2(18, 52)
	_hud.add_child(_day_label)
	# жизненные показатели — всегда на экране (правый нижний угол)
	var vp := VBoxContainer.new()
	vp.anchor_left = 1.0
	vp.anchor_top = 1.0
	vp.anchor_right = 1.0
	vp.anchor_bottom = 1.0
	vp.offset_left = -184.0
	vp.offset_right = -14.0
	vp.offset_top = -136.0
	vp.offset_bottom = -12.0
	vp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vp.add_theme_constant_override("separation", 1)
	vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(vp)
	_sat_lbl = _outl(_lbl("Сытость 80%", 13, TXT))
	vp.add_child(_sat_lbl)
	_sat_bar = ProgressBar.new()
	_sat_bar.min_value = 0.0
	_sat_bar.max_value = 100.0
	_sat_bar.value = 80.0
	_sat_bar.show_percentage = false
	_sat_bar.custom_minimum_size = Vector2(0, 10)
	_sat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sat_fill = StyleBoxFlat.new()
	_sat_fill.bg_color = Color("5fbf7a")
	_sat_fill.set_corner_radius_all(3)
	_sat_bar.add_theme_stylebox_override("fill", _sat_fill)
	var sat_bg := StyleBoxFlat.new()
	sat_bg.bg_color = Color(0, 0, 0, 0.55)
	sat_bg.set_corner_radius_all(3)
	_sat_bar.add_theme_stylebox_override("background", sat_bg)
	vp.add_child(_sat_bar)
	_bod_lbl = _outl(_lbl("Бодрость 100%", 13, TXT))
	vp.add_child(_bod_lbl)
	_bod_bar = ProgressBar.new()
	_bod_bar.min_value = 0.0
	_bod_bar.max_value = 100.0
	_bod_bar.value = 100.0
	_bod_bar.show_percentage = false
	_bod_bar.custom_minimum_size = Vector2(0, 10)
	_bod_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bod_fill = StyleBoxFlat.new()
	_bod_fill.bg_color = Color("5fbf7a")
	_bod_fill.set_corner_radius_all(3)
	_bod_bar.add_theme_stylebox_override("fill", _bod_fill)
	var bod_bg := StyleBoxFlat.new()
	bod_bg.bg_color = Color(0, 0, 0, 0.55)
	bod_bg.set_corner_radius_all(3)
	_bod_bar.add_theme_stylebox_override("background", bod_bg)
	vp.add_child(_bod_bar)
	_sleep_lbl = _outl(_lbl("", 13, BAD))
	_sleep_lbl.visible = false
	_sleep_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vp.add_child(_sleep_lbl)
	_pause_label = _outl(_lbl("ПАУЗА — Space, чтобы продолжить", 30, GOLD))
	_pause_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pause_label.offset_top = 150.0
	_pause_label.offset_bottom = 200.0
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.visible = false
	_hud.add_child(_pause_label)
	_hint_label = _outl(_lbl("", 16, TXT))
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -46.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.visible = false
	_hud.add_child(_hint_label)
	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = 12.0
	_toasts.offset_right = 400.0
	_toasts.offset_top = -430.0
	_toasts.offset_bottom = -10.0
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_toasts)
	# панель решения по гостю — внизу по центру, вид на персонажа в окне не закрывает
	_npc_bar = PanelContainer.new()
	_npc_bar.add_theme_stylebox_override("panel", _panel_style())
	_npc_bar.anchor_left = 0.5
	_npc_bar.anchor_top = 1.0
	_npc_bar.anchor_right = 0.5
	_npc_bar.anchor_bottom = 1.0
	_npc_bar.offset_left = -300.0
	_npc_bar.offset_right = 300.0
	_npc_bar.offset_top = -64.0
	_npc_bar.offset_bottom = -14.0
	_npc_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var nb := HBoxContainer.new()
	nb.alignment = BoxContainer.ALIGNMENT_CENTER
	nb.add_theme_constant_override("separation", 16)
	_npc_bar.add_child(nb)
	_npc_accept_btn = _btn("Пустить в бункер", _npc_accept)
	nb.add_child(_npc_accept_btn)
	var wait_btn := _btn("Подумать", _npc_wait)
	var refuse_btn := _btn("Прогнать", _npc_refuse)
	nb.add_child(wait_btn)
	nb.add_child(refuse_btn)
	_visitor_btns = [_npc_accept_btn, wait_btn, refuse_btn]
	var trade_btn := _btn("Торговать", _trader_trade)
	var away_btn := _btn("Отойти", _npc_wait)
	nb.add_child(trade_btn)
	nb.add_child(away_btn)
	_trader_btns = [trade_btn, away_btn]
	_gate_give_btn = _btn("Отдать", _gate_give)
	var gate_refuse_btn := _btn("Прогнать", _gate_refuse)
	var gate_away_btn := _btn("Отойти", _npc_wait)
	nb.add_child(_gate_give_btn)
	nb.add_child(gate_refuse_btn)
	nb.add_child(gate_away_btn)
	_gate_btns = [_gate_give_btn, gate_refuse_btn, gate_away_btn]
	_set_npc_mode(0)
	_npc_bar.visible = false
	_hud.add_child(_npc_bar)
	_npc_story = PanelContainer.new()
	_npc_story.add_theme_stylebox_override("panel", _panel_style())
	_npc_story_scroll = ScrollContainer.new()
	_npc_story_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_npc_story.add_child(_npc_story_scroll)
	var story_box := VBoxContainer.new()
	story_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_box.add_theme_constant_override("separation", 12)
	_npc_story_scroll.add_child(story_box)
	story_box.add_child(_lbl("У СМОТРОВОГО ОКНА", 13, DIM))
	_npc_story_title = _lbl("", 20, GOLD, true)
	story_box.add_child(_npc_story_title)
	_npc_story_text = _lbl("", 18, TXT, true)
	story_box.add_child(_npc_story_text)
	story_box.add_child(_lbl("Прислушайтесь к словам и осмотрите гостя перед решением.", 14, DIM, true))
	_npc_story.visible = false
	_hud.add_child(_npc_story)
	# слой главного меню: между HUD и окнами — настройки открываются поверх обложки
	_menu_layer = Control.new()
	_menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_layer.visible = false
	add_child(_menu_layer)
	_modal_root = Control.new()
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_root)
	if not Game.menu_skip and Game.end_state == "":
		open_modal("menu")  # главное меню при запуске: рекорд, настройки, выход
		_intro_pending = true  # вступительные подсказки — после выбора в меню
	else:
		_start_intro()


func _start_intro() -> void:
	# панель подсказок внизу по центру и компактнее: центр экрана и персонажи не перекрыты
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.offset_bottom = -46.0  # строчка-подсказка «E — …» у нижнего края остаётся видна
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)
	var lines := [
		"ПКМ (можно зажать) — идти за курсором, Shift — бег · Q/R — поворот камеры",
		"ЛКМ по предмету или E — открыть · Q/R или СКМ — поворот камеры",
		"Со 2-го дня к воротам приходят люди: у больного сопли, у маньяка нож в кармане",
		"Грядка → картошка · Кухня → еда, бензин и рецепты · Верстак → постройки и улучшения",
		"Генератору нужна дозаправка: бака — на ~40 ч, постройки съедают по 2 ч · карта на стене — места вылазок",
		"Клик по сотруднику — разговор и его просьбы · поломки чините деталями",
		"Space — пауза · J — журнал · H — помощь · M — звук · Esc — закрыть окно",
		"F — редактор всей сцены: список объектов, перенос, поворот, масштаб (+/−)",
	]
	for s in lines:
		var l := _lbl(s, 13, TXT, true)
		l.custom_minimum_size = Vector2(520, 0)  # без этого текст сжимается в вертикальный столбик
		v.add_child(l)
	vb.add_child(pc)
	vb.modulate.a = 0.0
	_modal_root.add_child(vb)
	_ignore_mouse(vb)
	var tw := create_tween()
	tw.tween_property(vb, "modulate:a", 1.0, 0.5)
	tw.tween_interval(10.0)
	tw.tween_property(vb, "modulate:a", 0.0, 1.0)
	tw.tween_callback(vb.queue_free)


func _process(_delta: float) -> void:
	_pause_label.visible = Game.paused and Game.end_state == ""
	_hud.visible = modal != "menu" and modal != "settings"  # в главном меню и его настройках игровой HUD не нужен
	if _npc_bar.visible:
		if _npc_mode == 1:
			if Game.trader.is_empty() or Game.end_state != "":
				Game.npc_wait.emit()  # торговец ушёл: возвращаем камеру
			else:
				_place_npc_story()
		elif _npc_mode == 2:
			if Game.gate_event.is_empty() or Game.end_state != "":
				Game.npc_wait.emit()  # незнакомец ушёл: возвращаем камеру
			else:
				_place_npc_story()
		elif Game.visitor.is_empty() or Game.end_state != "":
			hide_npc_bar()
		else:
			_update_npc_accept()
			_place_npc_story()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.physical_keycode:
		KEY_ESCAPE:
			if modal == "settings":
				_back_to_menu()  # настройки из меню — Esc вернёт в меню
			elif modal != "" and modal != "menu":
				_close()  # главное меню закрывается только выбором
		KEY_SPACE:
			if Game.end_state == "" and not Game.cinematic:
				Game.paused = not Game.paused
		KEY_J:
			modal = "" if modal == "log" else "log"
			refresh()
		KEY_M:
			var m := Snd.toggle_mute()
			toast("Звук: выкл" if m else "Звук: вкл")
		KEY_H:
			modal = "" if modal == "help" else "help"
			refresh()
		KEY_P:
			modal = "" if modal == "profs" else "profs"
			refresh()


func _update_vitals() -> void:
	_sat_bar.value = Game.player_food
	_bod_bar.value = Game.player_st
	var sat_col: Color = OK if Game.player_food > 50 else (GOLD if Game.player_food > 25 else BAD)
	var bod_col: Color = OK if Game.player_st > 50 else (GOLD if Game.player_st > 25 else BAD)
	_sat_fill.bg_color = sat_col
	_bod_fill.bg_color = bod_col
	_sat_lbl.text = "Сытость %d%%" % Game.player_food
	_sat_lbl.add_theme_color_override("font_color", sat_col)
	_bod_lbl.text = "Бодрость %d%%" % Game.player_st
	_bod_lbl.add_theme_color_override("font_color", bod_col)
	if Game.gen_broken:
		var left := maxi(0, Game.DARK_LIMIT - (Game.t - Game.gen_broken_at))
		_sleep_lbl.text = "Генератор сломан: двери, печь и измельчитель обесточены. До полной темноты %d ч!" % ((left + 59) / 60)
		_sleep_lbl.visible = true
	elif Game.player_st < 50:
		_sleep_lbl.text = "Пора спать на койках: бодрость %d%%. Ещё %d ч без сна — и конец." % [Game.player_st, maxi(0, (Game.AWAKE_LIMIT - Game.player_awake) / 60)]
		_sleep_lbl.visible = true
	elif Game.player_food < 25:
		_sleep_lbl.text = "Вы голодны — поешьте (стеллаж/кухня)."
		_sleep_lbl.visible = true
	else:
		_sleep_lbl.visible = false


func _pump_toasts() -> void:
	var lines: Array = Game.log_lines
	if lines.is_empty():
		return
	if _last_top == "":
		_last_top = String(lines[0])
		return
	var fresh: Array = []
	for l in lines:
		if String(l) == _last_top or fresh.size() == 3:
			break
		fresh.append(String(l))
	if fresh.is_empty():
		return
	_last_top = fresh[0]
	for i in range(fresh.size() - 1, -1, -1):
		toast(fresh[i])


func _on_changed() -> void:
	_time_label.text = Game.fmt(Game.t)
	_day_label.text = "День %d из 30" % Game.day()
	_update_vitals()
	_pump_toasts()
	if Game.end_state != _last_end:
		_last_end = Game.end_state
		if Game.end_state != "":
			modal = ""
		refresh()
	elif modal != "":
		refresh()


func refresh() -> void:
	if _modal_sc != null and is_instance_valid(_modal_sc):
		_scroll = float(_modal_sc.scroll_vertical)
	for c in _modal_root.get_children():
		_modal_root.remove_child(c)
		c.queue_free()
	_modal_sc = null
	Game.modal_open = modal != ""
	if modal == "menu":
		_build_main_menu()  # меню живёт своим слоем: настройки открываются поверх обложки
		return
	var keep_menu := modal == "settings" and _settings_from_menu
	if not keep_menu and _menu_layer != null and is_instance_valid(_menu_layer):
		_menu_layer.visible = false
	if Game.end_state != "":
		_build_end()
	elif modal != "":
		_build_modal()


# ---------- окна ----------
func _build_end() -> void:
	Snd.play("win" if Game.end_state == "win" else "lose")
	Game.delete_save()
	var bg := ColorRect.new()
	bg.color = Color("101713")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	pc.custom_minimum_size = Vector2(600, 0)
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var win: bool = Game.end_state == "win"
	v.add_child(_lbl("Выезд" if win else "Конец", 40, GOLD))
	var txt: String = Game.why
	if win:
		txt = "Ворота для машины поднялись, и вы выехали на %d-й день. Вы выбрались!" % Game.day()
	var l := _lbl(txt, 18, TXT, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	var lost := 0
	for w in Game.workers:
		if w.dead:
			lost += 1
	v.add_child(_lbl("Принято сотрудников: %d · потеряно: %d" % [Game.workers.size(), lost], 15, DIM))
	v.add_child(_btn("Играть снова", _restart))


func _overlay_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and modal != "menu" and modal != "settings":
		_close()  # главное меню и его настройки не закрываются кликом мимо — только явным выбором


func _build_modal() -> void:
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.55)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.gui_input.connect(_overlay_click)
	_modal_root.add_child(ov)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	var wide_modal: bool = modal == "bench" or modal == "inv"
	pc.custom_minimum_size = Vector2(1020 if wide_modal else 640, 0)
	cc.add_child(pc)
	if wide_modal:
		# крестик справа сверху (верстак и стеллаж): закрывает окно
		var xb := _btn("✕", _close)
		xb.custom_minimum_size = Vector2(40, 40)
		xb.size = Vector2(40, 40)
		xb.tooltip_text = "Закрыть (Esc)"
		xb.add_theme_font_size_override("font_size", 20)
		_modal_root.add_child(xb)
		var place_x := func() -> void:
			if is_instance_valid(pc) and is_instance_valid(xb):
				xb.position = pc.global_position + Vector2(pc.size.x - 52.0, 10.0)
		pc.item_rect_changed.connect(place_x)
		place_x.call_deferred()
	var mg := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 14)
	pc.add_child(mg)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mg.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	match modal:
		"fc": _m_forecast(v)
		"profs": _m_profs(v)
		"inv": _m_inventory(v)
		"bench": _m_bench(v)
		"car": _m_car(v)
		"bed": _m_bed(v)
		"radio": _m_radio(v)
		"trader": _m_trader(v)
		"exp": _m_exp(v)
		"map": _m_map(v)
		"garden": _m_garden(v)
		"kitchen": _m_proc(v, "kitchen")
		"furnace": _m_proc(v, "furnace")
		"shredder": _m_proc(v, "shredder")
		"medbed": _m_medbed(v)
		"medcab": _m_medcab(v)
		"gen": _m_gen(v)
		"settings": _m_settings(v)
		"log": _m_log(v)
		"help": _m_help(v)
		_:
			if modal.begins_with("need:"):
				_m_need(v, modal.substr(5))
			elif modal.begins_with("talk:"):
				_m_talk(v, int(modal.substr(5)))
			elif modal.begins_with("inc:"):
				_m_inc(v, int(modal.substr(4)))
	if modal != "menu" and modal != "settings":
		v.add_child(_btn("Закрыть", _close))  # меню и его настройки закрываются только явным выбором
	var modal_width: float = 990.0 if wide_modal else 620.0
	var modal_height: float = 610.0 if wide_modal else 560.0
	sc.custom_minimum_size = Vector2(modal_width, minf(v.get_combined_minimum_size().y + 8.0, modal_height))
	_modal_sc = sc
	sc.scroll_vertical = int(_scroll)
	var set_scroll := func() -> void:
		if _modal_sc != null and is_instance_valid(_modal_sc):
			_modal_sc.scroll_vertical = int(_scroll)
	set_scroll.call_deferred()


# ---------- главное меню: обложка, рекорд, кнопки ----------
const MENU_COVER_PATH := "res://assets/menu/cover.png"

func _build_main_menu() -> void:
	for c in _menu_layer.get_children():
		_menu_layer.remove_child(c)
		c.queue_free()
	_menu_layer.visible = true
	var root: Control = _menu_layer
	var tex: Texture2D = load(MENU_COVER_PATH) if ResourceLoader.exists(MENU_COVER_PATH) else null
	if tex != null:
		var bg := TextureRect.new()
		bg.texture = tex
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		root.add_child(bg)
		# мягкие тени под кнопки (справа) и под плашку рекорда (слева внизу)
		root.add_child(_menu_shade(Vector2(0.35, 0.5), Vector2(1.0, 0.5), Color(0, 0, 0, 0.5)))
		root.add_child(_menu_shade(Vector2(0.5, 0.4), Vector2(0.5, 1.0), Color(0, 0, 0, 0.45)))
	else:
		# нет обложки — тёмный фон и заголовок текстом, чтобы меню не осталось пустым
		var bgc := ColorRect.new()
		bgc.color = Color("101713")
		bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(bgc)
		var ttl := _lbl("LAST SHIFT", 64, GOLD)
		ttl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		ttl.offset_top = 90.0
		ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(_outl(ttl))
	# столбик кнопок справа по центру
	var col := VBoxContainer.new()
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -404.0
	col.offset_right = -60.0
	col.offset_top = -124.0
	col.offset_bottom = 124.0
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(col)
	if Game.has_save():
		col.add_child(_menu_btn("Продолжить (день %d)" % Game.peek_save_day(), _menu_continue))
	col.add_child(_menu_btn("Новая игра", _menu_new))
	col.add_child(_menu_btn("Настройки", _menu_settings))
	col.add_child(_menu_btn("Выход", _quit_game))
	# плашка рекорда — слева внизу
	var rec: Dictionary = Game.load_record()
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", _card_style())
	plaque.anchor_left = 0.0
	plaque.anchor_top = 1.0
	plaque.anchor_right = 0.0
	plaque.anchor_bottom = 1.0
	plaque.offset_left = 28.0
	plaque.offset_top = -152.0
	plaque.offset_bottom = -30.0
	plaque.offset_right = 470.0
	root.add_child(plaque)
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	plaque.add_child(c)
	c.add_child(_lbl("РЕКОРД", 13, GOLD))
	if rec.is_empty():
		c.add_child(_lbl("Пока нет: выберитесь на машине — игра запомнит день выезда и сколько людей вы спасли с собой.", 14, DIM, true))
	else:
		var row_d := HBoxContainer.new()
		row_d.add_theme_constant_override("separation", 8)
		c.add_child(row_d)
		row_d.add_child(_art("map", 30))
		row_d.add_child(_lbl("Лучший выезд: день %s (%s)" % [int(rec.get("day", 0)), rec.get("time", "00:00")], 17, TXT))
		var row_w := HBoxContainer.new()
		row_w.add_theme_constant_override("separation", 8)
		c.add_child(row_w)
		row_w.add_child(_art("medkit", 30))
		row_w.add_child(_lbl("Спасено с собой: %d чел." % int(rec.get("workers", 0)), 17, OK))
	# версия в правом нижнем углу
	var ver := _lbl("Люк-30 · v0.8.3", 12, DIM)
	ver.anchor_left = 1.0
	ver.anchor_top = 1.0
	ver.anchor_right = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -240.0
	ver.offset_top = -30.0
	ver.offset_right = -16.0
	ver.offset_bottom = -8.0
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ver)


func _menu_btn(txt: String, cb: Callable) -> Button:
	var b := _btn(txt, cb)
	b.custom_minimum_size = Vector2(344, 50)
	b.add_theme_font_size_override("font_size", 19)
	return b


# Полупрозрачный градиент-затемнение поверх обложки (направление задают from/to в UV)
func _menu_shade(from: Vector2, to: Vector2, strength: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), strength])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# ---------- настройки ----------
func _m_settings(v: VBoxContainer) -> void:
	v.add_child(_lbl("Настройки", 24, GOLD))
	v.add_child(_lbl("Звук", 18, GOLD))
	v.add_child(_lbl("Громкость: %d%%" % roundi(Snd.volume * 100.0), 15, DIM))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.value = Snd.volume * 100.0
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(320, 22)
	sl.value_changed.connect(Snd.set_volume)
	v.add_child(sl)
	v.add_child(_btn("Звук вкл/выкл (M)", _toggle_sound))
	v.add_child(_lbl("Графика", 18, GOLD))
	var fs: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	v.add_child(_btn("Полный экран: %s" % ("вкл" if fs else "выкл"), _toggle_fullscreen))
	v.add_child(_lbl("Масштаб 3D: %d%% — ниже = быстрее на слабом ПК" % roundi(float(Game.graphics.get("scale", 1.0)) * 100.0), 15, DIM))
	var gs := HSlider.new()
	gs.min_value = 50.0
	gs.max_value = 100.0
	gs.step = 10.0
	gs.value = clampf(float(Game.graphics.get("scale", 1.0)) * 100.0, 50.0, 100.0)
	gs.focus_mode = Control.FOCUS_NONE
	gs.custom_minimum_size = Vector2(320, 22)
	gs.value_changed.connect(_set_gscale)
	v.add_child(gs)
	var msaa_names := {0: "выкл", 1: "×2", 2: "×4"}
	v.add_child(_btn("Сглаживание (MSAA): %s" % msaa_names.get(int(Game.graphics.get("msaa", 2)), "×4"), _cycle_msaa))
	v.add_child(_btn("Тени: %s" % ("вкл" if bool(Game.graphics.get("shadows", true)) else "выкл"), _toggle_shadows))
	v.add_child(_btn("Эффекты (свечение, SSAO, туман): %s" % ("вкл" if bool(Game.graphics.get("effects", true)) else "выкл"), _toggle_effects))
	v.add_child(_lbl("Настройки применяются сразу и сохраняются сами.", 13, DIM, true))
	v.add_child(_btn("Готово", _back_to_menu))


# Применяем сохранённую графику при старте (тени и эффекты подтягивает weather через пресеты)
func _apply_graphics() -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(float(Game.graphics.get("scale", 1.0)), 0.5, 1.0)
	vp.msaa_3d = int(Game.graphics.get("msaa", 2))
	if bool(Game.graphics.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _set_gscale(v: float) -> void:
	Game.graphics.scale = clampf(v, 0.5, 1.0) / 100.0
	get_viewport().scaling_3d_scale = float(Game.graphics.scale)
	Game.save_graphics()


func _cycle_msaa() -> void:
	var order: Array = [0, 1, 2]  # выкл, ×2, ×4
	var cur: int = int(Game.graphics.get("msaa", 2))
	var idx := order.find(cur)
	Game.graphics.msaa = order[(idx + 1) % order.size()]
	get_viewport().msaa_3d = int(Game.graphics.msaa)
	Game.save_graphics()
	refresh()


func _toggle_shadows() -> void:
	Game.graphics.shadows = not bool(Game.graphics.get("shadows", true))
	Game.save_graphics()
	refresh()


func _toggle_effects() -> void:
	Game.graphics.effects = not bool(Game.graphics.get("effects", true))
	Game.save_graphics()
	refresh()


func _m_gen(v: VBoxContainer) -> void:
	v.add_child(_lbl("Генератор", 24, GOLD))
	if Game.gen_broken:
		var left := maxi(0, Game.DARK_LIMIT - (Game.t - Game.gen_broken_at))
		var l := _lbl("Генератор сломан: ворота и люк обесточены, плавильная печь и измельчитель стоят, лампа над грядкой погасла. До полной темноты и конца игры — %d ч." % ((left + 59) / 60), 16, BAD, true)
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)
		var db := ProgressBar.new()
		db.min_value = 0.0
		db.max_value = 100.0
		db.value = Game.darkness_factor() * 100.0
		db.show_percentage = false
		db.custom_minimum_size = Vector2(0, 12)
		var dfill := StyleBoxFlat.new()
		dfill.bg_color = BAD
		dfill.set_corner_radius_all(3)
		db.add_theme_stylebox_override("fill", dfill)
		var dbg := StyleBoxFlat.new()
		dbg.bg_color = Color(0, 0, 0, 0.55)
		dbg.set_corner_radius_all(3)
		db.add_theme_stylebox_override("background", dbg)
		v.add_child(db)
		v.add_child(_lbl("Темнота: %d%%" % int(Game.darkness_factor() * 100.0), 13, DIM))
		v.add_child(_btn("Починить: %s (30 мин) — вернёт свет, двери и печи" % Game.cost_text(Game.GEN_COST), _repair_gen, not Game.can(Game.GEN_COST)))
		return
	var hours := Game.gen_hours()
	var col: Color = OK if Game.gen_fuel > 50.0 else (GOLD if Game.gen_fuel > 20.0 else BAD)
	v.add_child(_lbl("Топливо в баке: %d%% — хватит примерно на %d ч." % [int(Game.gen_fuel), maxi(hours, 1)], 17, col, true))
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 100.0
	pb.value = Game.gen_fuel
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	v.add_child(pb)
	v.add_child(_btn("Дозаправить: 1 топливо → 100%% (20 мин)", _gen_refuel, Game.res.fuel < 1 or Game.gen_fuel >= Game.GEN_TANK - 1.0))
	var h := _lbl("Полного бака хватает на %d ч при нынешних постройках (без них — 40 ч): лампа грядки, кухня, плавильная печь и измельчитель съедают по 2 часа каждый. Без дозаправки генератор заглохнет, и это будет по вашей вине: без света двери и люк обесточены, печь и измельчитель стоят, а через 30 часов бункер погрузится в полную темноту — конец. Пока идёт замыкание, топливо уходит вдвое быстрее." % int(Game.gen_runtime_hours()), 13, DIM, true)
	h.custom_minimum_size = Vector2(560, 0)
	v.add_child(h)
	v.add_child(_lbl("Иногда (с 3-го дня) генератор ломается сам — следите за светом.", 14, DIM, true))


func _m_forecast(v: VBoxContainer) -> void:
	v.add_child(_lbl("Метеостанция", 24, GOLD))
	var l := _lbl("Прогноз точный. Вылазка длится 3 часа: опасно, если плохая погода в момент выхода ИЛИ к возвращению — сотрудник не вернётся.", 15, TXT, true)
	l.custom_minimum_size = Vector2(580, 0)
	v.add_child(l)
	for d in [Game.day(), Game.day() + 1]:
		if d > 30:
			break
		v.add_child(_lbl("День %d" % d, 18, GOLD))
		var g := GridContainer.new()
		g.columns = 5
		g.add_theme_constant_override("h_separation", 18)
		v.add_child(g)
		for h in ["Время", "t°", "Облака", "Ветер", "Выход"]:
			g.add_child(_lbl(h, 15, DIM))
		for p in 4:
			var w: Dictionary = Game.weather(d, p)
			var now: bool = d == Game.day() and p == Game.phase()
			g.add_child(_lbl(Game.PH[p] + (" (сейчас)" if now else ""), 15))
			g.add_child(_lbl("%d°" % w.temp, 15))
			g.add_child(_lbl("%d%%" % w.cloud, 15))
			g.add_child(_lbl("%d м/с" % w.wind, 15))
			g.add_child(_lbl("опасно" if w.bad else "можно", 15, BAD if w.bad else OK))


func _m_inventory(v: VBoxContainer) -> void:
	v.add_child(_lbl("СКЛАД  /  УЧЁТ ЗАПАСОВ", 12, DIM))
	v.add_child(_lbl("Стеллаж", 29, GOLD))
	v.add_child(_lbl("Все найденные, произведённые и сохранённые припасы бункера.", 14, DIM, true))

	_section_header(v, "СЫРЬЁ", "Материалы для ремонта и базового производства")
	var raw_grid := GridContainer.new()
	raw_grid.columns = 4
	raw_grid.add_theme_constant_override("h_separation", 10)
	raw_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(raw_grid)
	for id in ["metal", "plastic", "wire", "fuel", "rubber"]:
		_add_resource_card(raw_grid, id)

	_section_header(v, "КОМПОНЕНТЫ И ПРИПАСЫ", "Результаты переработки, урожай и медицинские запасы")
	var supply_grid := GridContainer.new()
	supply_grid.columns = 4
	supply_grid.add_theme_constant_override("h_separation", 10)
	supply_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(supply_grid)
	for id in ["steel", "chips", "seeds", "potato", "food", "herbs", "medkit"]:
		_add_resource_card(supply_grid, id)

	var food_note := _info_card("РАСХОД ЕДЫ", "Каждое утро в 06:00 вы и каждый сотрудник съедаете по 1 еде. При нулевом запасе падают сытость, здоровье и силы.", Color("d7aa43"))
	v.add_child(food_note)
	var eat_row := HBoxContainer.new()
	eat_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.add_child(eat_row)
	eat_row.add_child(_btn("Поесть сейчас  ·  +40 сытости  ·  1 еда", _eat_self, Game.res.food < 1 or Game.player_food >= 100))

	_section_header(v, "ЛИЧНОЕ СНАРЯЖЕНИЕ", "Предметы, которые можно взять с собой в вылазку")
	var gear_grid := GridContainer.new()
	gear_grid.columns = 3
	gear_grid.add_theme_constant_override("h_separation", 10)
	gear_grid.add_theme_constant_override("v_separation", 10)
	v.add_child(gear_grid)
	for id in Game.GEAR:
		var d: Dictionary = Game.GEAR[id]
		_add_owned_card(gear_grid, d.name, "Количество: %d" % int(Game.gear[id]), d.desc, id)


const BENCH_CATS := [
	["gear", "Снаряжение"],
	["car", "Детали машины"],
	["build", "Оборудование бункера"],
	["upg", "Модернизация"],
]
var _bench_cat := "gear"


func _m_bench(v: VBoxContainer) -> void:
	v.add_child(_lbl("МАСТЕРСКАЯ  /  СБОРКА И МОДЕРНИЗАЦИЯ", 12, DIM))
	v.add_child(_lbl("Верстак", 29, GOLD))
	v.add_child(_lbl("Выберите категорию, чтобы увидеть, что можно собрать.", 14, DIM, true))

	var stock := HBoxContainer.new()
	stock.add_theme_constant_override("separation", 8)
	v.add_child(stock)
	for id in ["metal", "plastic", "wire", "fuel", "rubber"]:
		_add_stock_chip(stock, id)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for c in BENCH_CATS:
		var tab := _btn(String(c[1]), _set_bench_cat.bind(String(c[0])))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _bench_cat == c[0]:
			_style_tab_active(tab)
		tabs.add_child(tab)

	match _bench_cat:
		"gear": _m_bench_gear(v)
		"car": _m_bench_car(v)
		"build": _m_build(v)
		"upg": _m_upgrades(v)


func _set_bench_cat(cat: String) -> void:
	_bench_cat = cat
	_scroll = 0.0
	refresh()


func _style_tab_active(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.30, 0.23, 0.07)
	n.set_corner_radius_all(7)
	n.set_border_width_all(2)
	n.border_color = GOLD
	n.content_margin_left = 12.0
	n.content_margin_right = 12.0
	n.content_margin_top = 6.0
	n.content_margin_bottom = 6.0
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, n)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)


func _m_bench_gear(v: VBoxContainer) -> void:
	_section_header(v, "СНАРЯЖЕНИЕ", "Инструменты и экипировка для вылазок")
	var gear_grid := _new_craft_grid(v)
	for id in Game.GEAR:
		var d: Dictionary = Game.GEAR[id]
		var owned: int = int(Game.gear[id])
		var desc: String = String(d.desc) + ("  ·  Уже создано: %d" % owned if owned > 0 else "")
		_add_craft_card(gear_grid, d.name, desc, d.cost, id, _craft.bind("gear", id), not Game.can(d.cost))


func _m_bench_car(v: VBoxContainer) -> void:
	_section_header(v, "ДЕТАЛИ МАШИНЫ", "Комплектующие для восстановления транспорта")
	var car_grid := _new_craft_grid(v)
	for id in Game.CAR:
		var d: Dictionary = Game.CAR[id]
		if Game.car[id]:
			_add_craft_card(car_grid, d.name, "Компонент установлен на автомобиль.", d.cost, id, Callable(), false, "УСТАНОВЛЕНО")
		else:
			_add_craft_card(car_grid, d.name, "Деталь автомобиля. После сборки будет установлена автоматически.", d.cost, id, _craft.bind("car", id), not Game.can(d.cost))


func _m_build(v: VBoxContainer) -> void:
	_section_header(v, "ОБОРУДОВАНИЕ БУНКЕРА", "Стройте комнаты и полезные станции")
	var grid := _new_craft_grid(v)
	var bed_desc := "Кровать для одного сотрудника. Каждому жителю нужно отдельное место для сна."
	var bed_status := "МЕСТА: %d / %d" % [Game.beds, Game.MAX_BEDS] if Game.beds >= Game.MAX_BEDS else ""
	_add_craft_card(grid, "Кровать", bed_desc, Game.BED_COST, "bed", _build_bed, Game.beds >= Game.MAX_BEDS or not Game.can(Game.BED_COST), bed_status)

	for id in Game.BUILD:
		var d: Dictionary = Game.BUILD[id]
		var icon_id: String = _build_icon(id)
		if Game.built[id]:
			var level: int = int(Game.upg.get(id, 0)) + 1
			_add_craft_card(grid, d.name, d.desc, d.cost, icon_id, Callable(), false, "ПОСТРОЕНО  ·  УР. %d" % level)
			continue
		var locked: bool = d.has("needs") and not Game.built[d.needs]
		var description: String = String(d.desc)
		if locked:
			description += "  ·  Сначала постройте: %s" % Game.BUILD[d.needs].name
		_add_craft_card(grid, d.name, description, d.cost, icon_id, _craft.bind("build", id), locked or not Game.can(d.cost))


func _m_upgrades(v: VBoxContainer) -> void:
	_section_header(v, "МОДЕРНИЗАЦИЯ", "Улучшения открываются после постройки соответствующей станции")
	var grid := _new_craft_grid(v)
	var any := false
	for id in Game.UPGRADES:
		if not Game.built[id]:
			continue
		any = true
		var level: int = int(Game.upg[id])
		var icon_id: String = _build_icon(id)
		if level >= Game.UPGRADES[id].size():
			_add_craft_card(grid, Game.BUILD[id].name, "Все доступные улучшения уже установлены.", {}, icon_id, Callable(), false, "МАКСИМАЛЬНЫЙ УРОВЕНЬ")
			continue
		var upgrade_data: Dictionary = Game.UPGRADES[id][level]
		_add_craft_card(grid, upgrade_data.name, upgrade_data.desc, upgrade_data.cost, icon_id, _upgrade.bind(id), not Game.can(upgrade_data.cost))
	if not any:
		v.add_child(_info_card("ПОКА НЕТ ДОСТУПНЫХ УЛУЧШЕНИЙ", "Сначала постройте одну из станций: грядку, кухню, печь, измельчитель или медицинский блок.", Color("8b9b91")))


func _build_icon(id: String) -> String:
	return id  # иконка постройки = <id>.png; нет файла — пусто


func _new_craft_grid(parent: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	return grid


func _section_header(parent: VBoxContainer, title: String, subtitle: String) -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.add_theme_constant_override("margin_top", 8)
	parent.add_child(wrap)
	wrap.add_child(_lbl(title, 15, GOLD))
	wrap.add_child(_lbl(subtitle, 12, DIM, true))
	var line := HSeparator.new()
	line.modulate = Color(0.88, 0.69, 0.3, 0.35)
	wrap.add_child(line)


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17231c")
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.83, 0.69, 0.39, 0.22)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	style.shadow_color = Color(0, 0, 0, 0.20)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


func _new_card(min_size: Vector2) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = min_size
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style())
	return card


var _icon_cache: Dictionary = {}


func _icon_texture(id: String) -> Texture2D:
	if id == "":
		return null
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	for dir in ICON_DIRS:
		var path: String = String(dir) + id + ".png"
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				break
	_icon_cache[id] = tex
	return tex


func _art(id: String, side: float) -> TextureRect:
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(side, side)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _icon_texture(id)
	return art


func _add_resource_card(parent: GridContainer, id: String) -> void:
	var card := _new_card(Vector2(0, 104))
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	row.add_child(_art(id, 66))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(_lbl(String(Game.RES[id]).to_upper(), 11, DIM, true))
	info.add_child(_lbl(str(Game.res[id]), 27, GOLD))
	info.add_child(_lbl("В наличии", 11, DIM))
	row.add_child(info)


func _add_stock_chip(parent: HBoxContainer, id: String) -> void:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", _card_style())
	parent.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)
	row.add_child(_art(id, 34))
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(_lbl(String(Game.RES[id]), 10, DIM))
	info.add_child(_lbl(str(Game.res[id]), 15, TXT))
	row.add_child(info)


func _add_owned_card(parent: GridContainer, title: String, count_text: String, description: String, icon_id: String) -> void:
	var card := _new_card(Vector2(0, 112))
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	row.add_child(_art(icon_id, 70))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_lbl(title, 15, TXT, true))
	info.add_child(_lbl(count_text, 13, GOLD))
	info.add_child(_lbl(description, 11, DIM, true))
	row.add_child(info)


func _cost_row(cost: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	for id in cost:
		var part := HBoxContainer.new()
		part.add_theme_constant_override("separation", 2)
		var icon := _art(String(id), 22)
		part.add_child(icon)
		part.add_child(_lbl(str(cost[id]), 12, Color("e7d7a5")))
		row.add_child(part)
	return row


func _add_craft_card(parent: GridContainer, title: String, description: String, cost: Dictionary, icon_id: String, callback: Callable, disabled: bool, status: String = "") -> void:
	var card := _new_card(Vector2(0, 156))
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	card.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)
	top.add_child(_art(icon_id, 82))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_lbl(title, 16, TXT, true))
	var detail := _lbl(description, 12, DIM, true)
	detail.custom_minimum_size = Vector2(0, 38)
	info.add_child(detail)
	top.add_child(info)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(footer)
	if status != "":
		var state := _lbl("✓  " + status, 12, OK, true)
		state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(state)
	else:
		footer.add_child(_cost_row(cost))
		var space := Control.new()
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(space)
		var action := _btn("СОБРАТЬ", callback, disabled)
		action.custom_minimum_size = Vector2(112, 34)
		action.add_theme_font_size_override("font_size", 12)
		footer.add_child(action)


func _info_card(title: String, description: String, accent: Color) -> PanelContainer:
	var card := _new_card(Vector2(0, 70))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)
	column.add_child(_lbl(title, 12, accent))
	column.add_child(_lbl(description, 13, DIM, true))
	return card


func _m_need(v: VBoxContainer, id: String) -> void:
	var d: Dictionary = Game.BUILD[id]
	v.add_child(_lbl("Пустая комната", 24, GOLD))
	var l := _lbl("Здесь нужно установить: %s." % d.name, 18, TXT, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	var l2 := _lbl(d.desc, 15, DIM, true)
	l2.custom_minimum_size = Vector2(560, 0)
	v.add_child(l2)
	var l3 := _lbl("Создай на верстаке в мастерской. Нужно: %s." % Game.cost_text(d.cost), 15, TXT, true)
	l3.custom_minimum_size = Vector2(560, 0)
	v.add_child(l3)


func _m_garden(v: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(_art("garden", 56))
	head.add_child(_lbl("Грядка (ур.%d)" % (Game.upg.garden + 1), 24, GOLD))
	var c: Dictionary = Game.crop
	var info := ""
	if c.state == "empty":
		info = "Пусто. Семян: %d" % Game.res.seeds
	elif c.state == "growing":
		info = "Растёт (%s), созреет в %s, день %d." % [Game.CROPS[c.kind].name, Game.fmt(c.ready), c.ready / 1440 + 1]
	else:
		info = "Созрело: %s." % Game.CROPS[c.kind].name
	var l := _lbl(info, 16, TXT, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	var b := _lbl("Ускорители: лампа %s · полив %s · ур.2 %s" % ["есть" if Game.built.lamp else "нет", "есть" if Game.built.irrig else "нет", "есть" if Game.upg.garden >= 1 else "нет"], 14, DIM, true)
	b.custom_minimum_size = Vector2(560, 0)
	v.add_child(b)
	if c.state == "empty":
		for k in Game.CROPS:
			var pb := _btn("Посадить: %s (1 семя)" % Game.CROPS[k].name, _plant.bind(k), Game.res.seeds < 1)
			pb.icon = _icon_texture(k)
			pb.add_theme_constant_override("icon_max_width", 26)
			v.add_child(pb)
	elif c.state == "ready":
		var hb := _btn("Собрать урожай", _harvest)
		hb.icon = _icon_texture(c.kind)
		hb.add_theme_constant_override("icon_max_width", 26)
		v.add_child(hb)


func _m_proc(v: VBoxContainer, station: String) -> void:
	var title := "Плавильная печь"
	if station == "shredder":
		title = "Измельчитель"
	elif station == "kitchen":
		title = "Кухня"
	v.add_child(_lbl("%s (ур.%d)" % [title, Game.upg[station] + 1], 24, GOLD))
	if station == "kitchen":
		var l := _lbl("Картошка с грядки: часть — в еду, часть — в бензин.", 15, TXT, true)
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)
		var pe := _btn("Поесть (вам): 1 еда → +40 сытости (20 мин)", _eat_self, Game.res.food < 1)
		pe.add_theme_color_override("font_color", BAD if Game.player_food < 40 else TXT)
		v.add_child(pe)
		v.add_child(_lbl("Ваша сытость: %d%%" % Game.player_food, 14, DIM))
	for id in Game.PROC:
		var r: Dictionary = Game.PROC[id]
		if r.station == station:
			v.add_child(_btn("%s: %s → %s (%d мин)" % [r.name, Game.cost_text(r.cost), Game.cost_text(Game.proc_out(id)), Game.proc_time(id)], _do_process.bind(id), not Game.can(r.cost)))
	if station == "kitchen":
		_section_header(v, "РЕЦЕПТЫ", "Блюда из продуктов дают временные бонусы всему бункеру")
		for id in Game.recipes_data:
			var rec: Dictionary = Game.recipes_data[id]
			var mins := int(round(float(rec.min) * (0.6 if Game.upg.kitchen >= 1 else 1.0)))
			v.add_child(_btn("%s: %s (%d мин) — %s" % [rec.name, Game.cost_text(rec.cost), mins, rec.desc], _cook.bind(id), not Game.can(rec.cost)))
		var bl := _lbl("Действуют: похлёбка %s · отвар %s" % [_buff_left(Game.buffs.loot_until), _buff_left(Game.buffs.immune_until)], 13, DIM, true)
		bl.custom_minimum_size = Vector2(560, 0)
		v.add_child(bl)


func _buff_left(until: int) -> String:
	if Game.t >= until:
		return "нет"
	return "(ещё %d ч)" % ((until - Game.t + 59) / 60)


func _m_medbed(v: VBoxContainer) -> void:
	v.add_child(_lbl("Больничная кушетка (ур.%d)" % (Game.upg.medbed + 1), 24, GOLD))
	v.add_child(_lbl("Аптечек: %d" % Game.res.medkit, 15, DIM))
	if Game.workers.is_empty():
		v.add_child(_lbl("Пока нет сотрудников.", 15, DIM))
		return
	for i in Game.workers.size():
		var w: Dictionary = Game.workers[i]
		var tag := " (болен)" if w.sick else ""
		v.add_child(_lbl("%s: здоровье %d%s" % [w.name, w.hp, tag], 16, TXT))
		var away: bool = w.dead or w.away != null
		var row := HBoxContainer.new()
		v.add_child(row)
		row.add_child(_btn("Кушетка: +%d здоровья и лечит болезнь (2 ч)" % [30 + 20 * Game.upg.medbed + (20 if Game.has_prof("medic") else 0)], _heal.bind(i), away or (w.hp >= 100 and not w.sick)))
		row.add_child(_btn("Аптечка: сразу +50 и лечит болезнь", _use_medkit.bind(i), away or Game.res.medkit < 1))


func _m_medcab(v: VBoxContainer) -> void:
	v.add_child(_lbl("Аптечный шкаф (ур.%d)" % (Game.upg.medcab + 1), 24, GOLD))
	v.add_child(_lbl("Аптечек: %d" % Game.res.medkit, 16, TXT))
	v.add_child(_btn("Приготовить аптечку: %s (30 мин)" % Game.cost_text(Game.medkit_cost()), Game.make_medkit, not Game.can(Game.medkit_cost())))


func _m_car(v: VBoxContainer) -> void:
	v.add_child(_lbl("Автомобиль", 24, GOLD))
	for k in Game.CAR:
		var ok: bool = Game.car[k]
		v.add_child(_lbl("%s: %s" % [Game.CAR[k].name, "готово" if ok else "нет"], 16, OK if ok else BAD))
	v.add_child(_btn("Выехать по рампе", _drive, not Game.car_done()))
	if not Game.car_done():
		v.add_child(_lbl("Нужны все четыре детали.", 15, DIM))


func _tasks() -> Array:
	var out: Array = []
	if not Game.built.garden:
		out.append("Постройте грядку (верстак → Постройки для комнат)")
	if Game.workers.is_empty():
		out.append("Бункер пуст — со 2-го дня придут гости: принимайте здоровых специалистов")
	if Game.built.garden and Game.crop.state == "empty" and Game.res.seeds < 1:
		out.append("Нет семян — вернутся с каждого урожая; посадите, когда появятся")
	elif Game.built.garden and Game.crop.state == "empty" and Game.res.seeds >= 1:
		out.append("Посадите картошку на грядке")
	if Game.crop.state == "ready":
		out.append("Соберите урожай")
	if not Game.built.kitchen:
		out.append("Постройте кухню: картошка → еда и бензин")
	if Game.workers.size() > 0 and Game.res.food < Game.workers.size() + 1:
		out.append("Еды мало — переработайте картошку в еду на кухне")
	var car_cnt := 0
	for k in Game.CAR:
		if Game.car[k]:
			car_cnt += 1
	if Game.car_done():
		out.append("Машина готова — выезжайте по рампе!")
	elif Game.workers.size() > 0:
		out.append("Детали машины: %d/4 — добывайте ресурсы вылазками (клавиша 5)" % car_cnt)
	if Game.gen_broken:
		var left := maxi(0, Game.DARK_LIMIT - (Game.t - Game.gen_broken_at))
		out.append("СРОЧНО: генератор сломан — %d ч до полной темноты и конца игры. Почините: %s" % [((left + 59) / 60), Game.cost_text(Game.GEN_COST)])
	elif not Game.gen_broken and Game.gen_fuel < 25.0:
		out.append("Генератор почти пуст (%d%%) — дозаправьте (1 топливо у генератора)" % int(Game.gen_fuel))
	if not Game.incidents.is_empty():
		var kinds: Array = []
		for inc in Game.incidents:
			kinds.append(Game.INC_KINDS[inc.kind].to_lower())
		out.append("Поломка в бункере: %s — почините деталями или отправьте сотрудника" % ", ".join(kinds))
	var askers: Array = []
	for w in Game.workers:
		if w.dead:
			continue
		var req: Variant = w.get("req", null)
		if req != null and not (req as Dictionary).is_empty():
			askers.append(w.name)
	if not askers.is_empty():
		out.append("Личные просьбы: %s — подойдите и поговорите" % ", ".join(askers))
	if Game.t < int(Game.buffs.loot_until) or Game.t < int(Game.buffs.immune_until):
		out.append("Кухня: действует бонус от блюда (%s)" % ("вылазки +15%" if Game.t < int(Game.buffs.loot_until) else "защита от болезней"))
	if not Game.built.kitchen:
		out.append("Постройте кухню: рецепты дают бонусы бункеру")
	if out.is_empty():
		out.append("Всё идёт по плану — следите за погодой и гостями")
	return out


func _m_bed(v: VBoxContainer) -> void:
	v.add_child(_lbl("Койки", 24, GOLD))
	var info := _lbl("Кроватей: %d из %d. Сотрудники сами ложатся спать в 22:00 и встают в 06:00 (+40 выносливости). Новых гостей можно пускать, только пока есть свободные кровати (сейчас свободно: %d)." % [Game.beds, Game.MAX_BEDS, maxi(Game.free_beds(), 0)], 15, TXT, true)
	info.custom_minimum_size = Vector2(560, 0)
	v.add_child(info)
	var tired: bool = Game.player_st <= 85
	var ps := _btn("Спать (вам): %d ч → бодрость 100%%%s" % [Game.SLEEP_HOURS, "" if tired else " — не хочется (бодрость %d%%)" % Game.player_st], _sleep_self, not tired)
	if Game.player_st < 40:
		ps.add_theme_color_override("font_color", BAD)
	v.add_child(ps)
	v.add_child(_lbl("Ваша бодрость падает, пока вы не спите: за сутки на половину, 48 часов без сна — смерть. Лечь можно, когда бодрость 85% или ниже.", 13, DIM, true))
	v.add_child(_btn("Построить кровать: %s (%d/%d)" % [Game.cost_text(Game.BED_COST), Game.beds, Game.MAX_BEDS], _build_bed, Game.beds >= Game.MAX_BEDS or not Game.can(Game.BED_COST)))
	if Game.workers.is_empty():
		v.add_child(_lbl("Сотрудников пока нет.", 15, DIM))
		return
	v.add_child(_lbl("Сотрудники", 18, GOLD))
	var rank := 0
	for w in Game.workers:
		if w.dead:
			continue
		var has_bed: bool = rank < Game.beds
		rank += 1
		var st := "кровать есть" if has_bed else "КРОВАТИ НЕТ"
		if w.get("asleep", false):
			st = "спит"
		elif int(w.get("nosleep", 0)) > 0:
			st = "не спал %d ноч. — ОПАСНО" % int(w.get("nosleep", 0))
		var extra := ""
		if w.get("task", null) != null:
			extra += " · ремонт до %s" % Game.fmt(int(w.task.until))
		if int(w.get("loyal", 0)) > 0:
			extra += " · лояльность %d" % int(w.loyal)
		v.add_child(_lbl("%s — выносливость %d · %s%s" % [w.name, w.st, st, extra], 15, OK if has_bed else BAD))


func _m_radio(v: VBoxContainer) -> void:
	v.add_child(_lbl("Радио", 24, GOLD))
	var cd := Game.music_cooldown_left()
	if cd > 0:
		v.add_child(_btn("Нет сигнала (появится через %d ч)" % ((cd + 59) / 60), _radio_music, true))
	else:
		v.add_child(_btn("Слушать музыку (30 мин): вылазки на ближайшие 6 часов приносят +15%", _radio_music))
	var mh := _lbl("Музыку слышат все сотрудники в бункере. Кто слышал её за последние 6 часов до выхода на поверхность, принесёт с вылазки на 15% больше ресурсов. Музыку можно включать не чаще раза в 12 часов, иначе — нет сигнала.", 13, DIM, true)
	mh.custom_minimum_size = Vector2(560, 0)
	v.add_child(mh)
	var heard: Array = []
	for w in Game.workers:
		if not w.dead and w.away == null and Game.heard_music(w):
			heard.append("%s (ещё %d ч)" % [w.name, (Game.music_left(w) + 59) / 60])
	if not heard.is_empty():
		var hl2 := _lbl("Под музыку: " + ", ".join(heard), 14, OK, true)
		hl2.custom_minimum_size = Vector2(560, 0)
		v.add_child(hl2)
	var sig_wait: int = Game.radio_signal_at - Game.t
	var sg_txt := "Передать сигнал выживших (30 мин): завтра к люку точно придут"
	if Game.radio_signal:
		sg_txt = "Сигнал передан — ждите гостя завтра в 9:00"
	elif sig_wait > 0:
		sg_txt = "Сигнал выживших — через %d ч" % ((sig_wait + 59) / 60)
	v.add_child(_btn(sg_txt, _radio_signal, sig_wait > 0 or Game.radio_signal))
	var hl := _lbl("Торговец приходит к воротам сам: каждый день в 13:00 с вероятностью 20%, стоит снаружи 8 часов и внутрь не заходит. Чтобы торговать, подойдите к воротам и посмотрите в окно (E). Меняет излишки топлива, резины, проводов на металл, пластик, платы, сталь, аптечки.", 13, DIM, true)
	hl.custom_minimum_size = Vector2(560, 0)
	v.add_child(hl)


func _m_trader(v: VBoxContainer) -> void:
	v.add_child(_lbl("Торговец", 24, GOLD))
	if Game.trader.is_empty():
		v.add_child(_lbl("Торговца у люка сейчас нет.", 15, DIM))
		return
	var left: int = int(Game.trader.until) - Game.t
	v.add_child(_lbl("Уйдёт через %d ч. Обмен без денег: вы отдаёте излишки, он даёт нужное. Каждую сделку можно сделать 2 раза." % maxi(1, left / 60), 14, DIM, true))
	for i in Game.trader.deals.size():
		var d: Dictionary = Game.trader.deals[i]
		var gn := int(d.give_n)
		var txt := "%s ×%d  →  %s ×%d  (осталось: %d)" % [Game.RES[d.give], gn, Game.RES[d.get], int(d.get_n), int(d.left)]
		v.add_child(_btn(txt, _trade.bind(i), int(d.left) < 1 or Game.res[d.give] < gn))


# ---------- карта вылазок на доске в коридоре ----------
func _m_map(v: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(_art("map", 56))
	head.add_child(_lbl("Карта вылазок", 24, GOLD))
	var l := _lbl("Дороги на поверхности. Чем дальше место, тем больше добыча и риск. Неизведанные тропы открывает разведка: 3 часа и любой свободный сотрудник.", 14, DIM, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	_section_header(v, "ОТКРЫТЫЕ МЕСТА", "Выберите место — сотрудника отправьте в окне экспедиции (пульт люка, клавиша 5)")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	for sid in Game.sites_data:
		if not bool(Game.sites.get(sid, false)):
			continue
		var s: Dictionary = Game.sites_data[sid]
		var card := _new_card(Vector2(0, 96))
		g.add_child(card)
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 4)
		card.add_child(c)
		var rowt := HBoxContainer.new()
		rowt.add_theme_constant_override("separation", 8)
		c.add_child(rowt)
		rowt.add_child(_art(SITE_ICONS.get(sid, "map"), 44))
		rowt.add_child(_lbl(s.name, 16, TXT))
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rowt.add_child(sp)
		rowt.add_child(_btn("Сюда", _pick_site_go.bind(sid)))
		c.add_child(_lbl("%s · риск +%.0f%% · добыча ×%.1f" % [s.desc, float(s.risk) * 100.0, float(s.yield)], 12, DIM, true))
	_section_header(v, "НЕИЗВЕДАННОЕ", "Разведка: 3 часа, риск травмы ниже, чем у вылазки. Кто пойдёт — выберите ниже")
	var any_und := false
	for sid in Game.sites_data:
		if bool(Game.sites.get(sid, false)):
			continue
		any_und = true
		var s2: Dictionary = Game.sites_data[sid]
		v.add_child(_btn("Разведать «%s» (3 ч): %s" % [s2.name, s2.desc], _scout.bind(sid)))
	if not any_und:
		v.add_child(_lbl("Все дороги на карте разведаны.", 14, OK))
	if Game.workers.is_empty():
		v.add_child(_lbl("Разведывать некому: сотрудников пока нет.", 13, DIM))
		return
	v.add_child(_lbl("Кто пойдёт на разведку", 16, GOLD))
	scout_w = clampi(scout_w, 0, Game.workers.size() - 1)
	for i in Game.workers.size():
		var w: Dictionary = Game.workers[i]
		var st := " — потерян" if w.dead else (" — снаружи" if w.away != null else "")
		v.add_child(_btn(("▶ " if scout_w == i else "") + "%s — %s (ур.%d)%s" % [w.name, Game.PROFS[w.prof].name, w.lvl, st], _pick_scout.bind(i), w.dead))
	if Game.inc_active("door"):
		var dj := _lbl("Дверь заклинило: пока не почините, никто не выйдет на поверхность.", 14, BAD, true)
		dj.custom_minimum_size = Vector2(560, 0)
		v.add_child(dj)


# ---------- разговор с сотрудником ----------
func _m_talk(v: VBoxContainer, i: int) -> void:
	if i < 0 or i >= Game.workers.size():
		return
	var w: Dictionary = Game.workers[i]
	if w.dead:
		v.add_child(_lbl("Собеседник", 24, GOLD))
		v.add_child(_lbl("%s погиб. Разговорить его больше нельзя." % w.name, 15, BAD, true))
		return
	v.add_child(_lbl("Разговор: %s" % w.name, 24, GOLD))
	var pf: Dictionary = Game.PROFS[w.prof]
	v.add_child(_lbl("%s · %s — %s" % [w.name, pf.name, pf.desc], 15, DIM, true))
	if w.away != null:
		v.add_child(_lbl("%s сейчас снаружи — вернётся в %s." % [w.name, Game.fmt(int(w.away.ret))], 15, TXT, true))
		return
	var st := _lbl("«%s»" % StaffDialogue.story(String(w.name)), 16, TXT, true)
	st.custom_minimum_size = Vector2(560, 0)
	v.add_child(st)
	var req: Variant = w.get("req", null)
	if req != null and not (req as Dictionary).is_empty():
		var rd: Dictionary = req
		var rl := _lbl("Просьба %s: «принесите %s ×%d»." % [w.name, Game.RES[rd.res], int(rd.n)], 16, GOLD, true)
		rl.custom_minimum_size = Vector2(560, 0)
		v.add_child(rl)
		var can_give: bool = Game.can({String(rd.res): int(rd.n)})
		var give_btn := _btn("Отдать %s ×%d — благодарность и лояльность" % [Game.RES[rd.res], int(rd.n)], _fulfill.bind(i), not can_give)
		if can_give:
			give_btn.add_theme_color_override("font_color", OK)
		v.add_child(give_btn)
	else:
		v.add_child(_lbl("Сейчас личных просьб нет: загляните позже.", 14, DIM))
	var chat_btn := _btn("Просто поговорить (+1 лояльности, раз в 3 ч)", _chat.bind(i), not Game.talk_ready(i))
	v.add_child(chat_btn)
	if String(w.get("last_chat", "")) != "":
		var cl := _lbl("%s: «%s»" % [w.name, w.last_chat], 15, OK, true)
		cl.custom_minimum_size = Vector2(560, 0)
		v.add_child(cl)
	var lb := _lbl("Лояльность: %d. Доверие (50+) ускоряет его добычу, преданность (90+) даёт +1 вместимость. Выполненная просьба — +10 лояльности и подарок." % int(w.get("loyal", 0)), 13, DIM, true)
	lb.custom_minimum_size = Vector2(560, 0)
	v.add_child(lb)


# ---------- ремонт поломки ----------
func _m_inc(v: VBoxContainer, id: int) -> void:
	var inc := {}
	for g in Game.incidents:
		if g.id == id:
			inc = g
	if inc.is_empty():
		v.add_child(_lbl("Поломка устранена — здесь всё в порядке.", 16, OK))
		return
	v.add_child(_lbl(Game.INC_KINDS[inc.kind], 24, BAD))
	var d := _lbl(Game.INC_DESC[inc.kind], 16, TXT, true)
	d.custom_minimum_size = Vector2(560, 0)
	v.add_child(d)
	if int(inc.loss) > 0:
		v.add_child(_lbl("Уже потеряно: %s." % inc.loss_txt, 15, BAD))
	var cost: Dictionary = Game.INC_COST[inc.kind]
	v.add_child(_btn("Починить самому: %s (30 мин)" % Game.cost_text(cost), _fix_inc.bind(int(inc.id)), not Game.can(cost)))
	v.add_child(_lbl("Или отправьте сотрудника (2 ч, +опыт):", 15, TXT))
	var any := false
	for i in Game.workers.size():
		var w: Dictionary = Game.workers[i]
		if w.dead or w.away != null or w.get("asleep", false) or w.get("task", null) != null:
			continue
		any = true
		v.add_child(_btn("%s — отправить на ремонт" % w.name, _send_repair.bind(i, int(inc.id))))
	if not any:
		v.add_child(_lbl("Все заняты, спят или в вылазке.", 13, DIM))
	var h := _lbl("Если поломка простоит 12 часов, уют упадёт: силы дома перестанут восстанавливаться. Протечка портит еду, замыкание — провода и платы.", 13, DIM, true)
	h.custom_minimum_size = Vector2(560, 0)
	v.add_child(h)


func _radio_music() -> void:
	Game.radio()


func _radio_signal() -> void:
	Game.radio_seek_survivors()


func _trade(i: int) -> void:
	Game.trade(i)


func _open_trader() -> void:
	open_modal("trader")


func _build_bed() -> void:
	Game.build_bed()


func _sleep_self() -> void:
	Game.player_sleep()


func _m_exp(v: VBoxContainer) -> void:
	var wx: Dictionary = Game.trip_weather(Game.t)
	v.add_child(_lbl("Экспедиция", 24, GOLD))
	var verdict := "безопасно, вернётся"
	if wx.now_bad:
		verdict = "ОПАСНО прямо сейчас — не вернётся"
	elif wx.later_bad:
		verdict = "ОПАСНО: к возвращению (через 3 ч) погода испортится — не вернётся"
	var l := _lbl("Сейчас: %s, %d°, ветер %d м/с. Вылазка длится 3 часа — %s." % [Game.PH[Game.phase()], Game.cur_weather().temp, Game.cur_weather().wind, verdict], 15, BAD if wx.bad else OK, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	# место на карте: открыто только разведанное
	if not bool(Game.sites.get(pick_site, false)):
		pick_site = "waste"
	var site: Dictionary = Game.sites_data[pick_site]
	var row_sites := HBoxContainer.new()
	row_sites.add_theme_constant_override("separation", 6)
	v.add_child(row_sites)
	for sid in Game.sites_data:
		if not bool(Game.sites.get(sid, false)):
			continue
		var b := _btn(("▶ " if pick_site == sid else "") + Game.sites_data[sid].name, _pick_site.bind(sid))
		b.icon = _icon_texture(SITE_ICONS.get(sid, "map"))
		b.add_theme_constant_override("icon_max_width", 22)
		if pick_site == sid:
			_style_tab_active(b)
		row_sites.add_child(b)
	var sd := _lbl("%s: %s Риск травмы +%.0f%%, добыча ×%.1f." % [site.name, site.desc, float(site.risk) * 100.0, float(site.yield)], 14, DIM, true)
	sd.custom_minimum_size = Vector2(560, 0)
	v.add_child(sd)
	if Game.t < int(Game.buffs.loot_until):
		var bf := _lbl("Походная похлёбка действует: добыча +15%% (ещё %d ч)." % ((int(Game.buffs.loot_until) - Game.t + 59) / 60), 14, OK, true)
		bf.custom_minimum_size = Vector2(560, 0)
		v.add_child(bf)
	if Game.inc_active("door"):
		var dj := _lbl("Дверь заклинило: сначала почините её — вылазки закрыты.", 15, BAD, true)
		dj.custom_minimum_size = Vector2(560, 0)
		v.add_child(dj)
	if Game.workers.is_empty():
		var lw := _lbl("Пока нет сотрудников: бункер пуст. Со 2-го дня к воротам начнут приходить люди — принимай здоровых специалистов.", 15, DIM, true)
		lw.custom_minimum_size = Vector2(560, 0)
		v.add_child(lw)
		return
	v.add_child(_lbl("Кого отправить — отметьте галочками", 18, GOLD))
	# выбор чистится сам: кто-то мог уйти, заболеть или уснуть
	selected = selected.filter(func(i): return Game.sendable(i))
	for i in Game.workers.size():
		var w: Dictionary = Game.workers[i]
		if Game.sendable(i):
			var mark := "☑ " if selected.has(i) else "☐ "
			var row_w := _btn("%s%s — %s (ур.%d): вместимость %d, добыча ×%.1f, выносливость %d, здоровье %d" % [mark, w.name, Game.PROFS[w.prof].name, w.lvl, w.cap, w.eff, w.st, w.hp], _toggle_w.bind(i))
			if selected.has(i):
				row_w.add_theme_color_override("font_color", OK)
			v.add_child(row_w)
		else:
			var why := ""
			if w.dead:
				why = "потерян"
			elif w.away != null:
				why = "снаружи, вернётся в %s" % Game.fmt(int(w.away.ret))
			elif w.get("asleep", false):
				why = "спит"
			elif w.get("task", null) != null:
				why = "чинит поломку"
			elif w.sick:
				why = "болен — нужно лечение"
			elif w.st < Game.MIN_STAMINA:
				why = "нет выносливости"
			else:
				why = "ранен — нужно лечение"
			v.add_child(_btn("☐ %s — %s: %s" % [w.name, Game.PROFS[w.prof].name, why], Callable(), true))
	v.add_child(_lbl("Снаряжение", 18, GOLD))
	var gh := _lbl("Рюкзак: +4 вместимости (больше добычи). Магнит: ×1,5 металла и проводов. Бур: ×1,5 топлива, резины и пластика. Вылазка приносит 1–3 разных ресурса; расходуется только отметка на этот выход — само снаряжение не пропадает.", 13, DIM, true)
	gh.custom_minimum_size = Vector2(560, 0)
	v.add_child(gh)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_btn(("▶ " if pick_pack else "") + "Рюкзак ×%d" % Game.gear.pack, _toggle_pack, Game.gear.pack == 0))
	for t in ["magnet", "drill"]:
		row.add_child(_btn(("▶ " if pick_tool == t else "") + "%s ×%d" % [Game.GEAR[t].name, Game.gear[t]], _toggle_tool.bind(t), Game.gear[t] == 0))
	var n_ready := selected.size()
	var sbtn := _btn("Отправить отмеченных (%d)" % n_ready, _send, n_ready < 1)
	if n_ready > 0:
		sbtn.add_theme_color_override("font_color", OK)
	v.add_child(sbtn)
	var hint := _lbl("Отмеченные выходят все разом одной кнопкой: +25 опыта каждому. Рюкзак и инструмент применяются ко всем отмеченным. Музыка (+15% добычи) действует на тех, кто её слышал.", 13, DIM, true)
	hint.custom_minimum_size = Vector2(560, 0)
	v.add_child(hint)


func _m_log(v: VBoxContainer) -> void:
	v.add_child(_lbl("Журнал", 24, GOLD))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_btn("Сохранить игру", _save_game))
	row.add_child(_btn("Загрузить игру", _load_game))
	row.add_child(_btn("Сбросить раскладку", _reset_layout))
	row.add_child(_btn("Профессии (P)", _open_profs))
	v.add_child(_lbl("Автосохранение — каждое утро в 6:00.", 13, DIM))
	v.add_child(_lbl("Задачи", 18, GOLD))
	for s in _tasks():
		var tk := _lbl("· " + s, 15, TXT, true)
		tk.custom_minimum_size = Vector2(560, 0)
		v.add_child(tk)
	var car_cnt := 0
	for k in Game.CAR:
		if Game.car[k]:
			car_cnt += 1
	v.add_child(_lbl("Детали машины: %d из 4 · Гостей принято: %d из %d" % [car_cnt, Game.NPC_DEFS.size() - Game.npc_pool.size(), Game.NPC_DEFS.size()], 15, TXT))
	var stock := ""
	for k in Game.RES:
		stock += "%s %d · " % [Game.RES[k], Game.res[k]]
	var l := _lbl(stock, 15, TXT, true)
	l.custom_minimum_size = Vector2(580, 0)
	v.add_child(l)
	var gear := ""
	for k in Game.GEAR:
		gear += "%s ×%d · " % [Game.GEAR[k].name, Game.gear[k]]
	var g := _lbl("Снаряжение: " + gear, 14, DIM, true)
	g.custom_minimum_size = Vector2(580, 0)
	v.add_child(g)
	v.add_child(_lbl("Экипаж", 18, GOLD))
	if Game.workers.is_empty():
		v.add_child(_lbl("Бункер пуст: сотрудников нет. Ждите гостей у люка.", 15, DIM, true))
	for p in Game.workers:
		var s: String
		if p.dead:
			s = "потерян"
		elif p.away != null:
			s = "снаружи, вернётся в %s" % Game.fmt(p.away.ret)
		else:
			s = "дома · выносливость %d · здоровье %d%s" % [p.st, p.hp, " (болен)" if p.sick else ""]
		var xp_txt := ""
		if p.lvl <= Game.XP_NEED.size():
			xp_txt = " · опыт %d/%d" % [p.xp, Game.xp_need(p.lvl)]
		var m := _lbl("%s — %s: %s (ур.%d%s) · %s" % [p.name, Game.PROFS[p.prof].name, Game.PROFS[p.prof].desc, p.lvl, xp_txt, s], 15, TXT, true)
		m.custom_minimum_size = Vector2(580, 0)
		v.add_child(m)
	v.add_child(_lbl("Громкость: %d%%" % roundi(Snd.volume * 100.0), 15, DIM))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.value = Snd.volume * 100.0
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(320, 22)
	sl.value_changed.connect(Snd.set_volume)
	v.add_child(sl)
	row.add_child(_btn("Звук вкл/выкл (M)", _toggle_sound))
	v.add_child(_lbl("Вы", 18, GOLD))
	var pv := _lbl("Сытость %d%% · бодрость %d%% · без сна: %d ч" % [Game.player_food, Game.player_st, Game.player_awake / 60], 15, BAD if (Game.player_st < 30 or Game.player_food < 25) else TXT, true)
	pv.custom_minimum_size = Vector2(560, 0)
	v.add_child(pv)
	v.add_child(_lbl("События", 18, GOLD))
	var logbox := RichTextLabel.new()
	logbox.custom_minimum_size = Vector2(580, 240)
	logbox.text = "\n".join(Game.log_lines)
	logbox.focus_mode = Control.FOCUS_NONE
	v.add_child(logbox)


# Справочник профессий: что даёт каждая и кто из них сейчас в бункере
func _m_profs(v: VBoxContainer) -> void:
	v.add_child(_lbl("Профессии", 24, GOLD))
	var intro := _lbl("Профессия гостя видна в окне у ворот. Эффект работает, пока такой сотрудник жив.", 14, DIM, true)
	intro.custom_minimum_size = Vector2(560, 0)
	v.add_child(intro)
	for id in Game.PROFS:
		var pf: Dictionary = Game.PROFS[id]
		var who: Array = []
		for w in Game.workers:
			if not w.dead and w.prof == id:
				who.append(w.name)
		var t := _lbl("%s — %s" % [pf.name, pf.desc], 16, TXT, true)
		t.custom_minimum_size = Vector2(560, 0)
		v.add_child(t)
		if not who.is_empty():
			v.add_child(_lbl("   сейчас в бункере: " + ", ".join(who), 13, OK))


func _open_profs() -> void:
	modal = "profs"
	refresh()


func _m_help(v: VBoxContainer) -> void:
	v.add_child(_lbl("Управление", 24, GOLD))
	var lines := [
		"ПКМ — идти к точке; пока ПКМ зажата, персонаж идёт за курсором · Shift — бежать",
		"ЛКМ по предмету или E — открыть · зажмите ЛКМ или ПКМ на полу — персонаж идёт за курсором · на паузе (Space) ходить и действовать нельзя",
		"1–9, 0 — быстрый переход: грядка / кухня / склад / верстак / экспедиция / койки / печь / измельчитель / кушетка / аптека",
		"Q/R или зажатая СКМ — поворот камеры (камера фиксирована: без зума и стрелок)",
		"C — камера к персонажу и обратно · Space — пауза",
		"J — журнал · P — профессии · H — помощь · Esc — закрыть окно",
		"Сон: ваша бодрость падает, пока вы не спите (48 часов без сна — смерть); койка даёт 8 часов сна и полную бодрость. Сотрудники сами ложатся в 22:00. Каждому нужна своя кровать: пустить гостя в бункер можно, только если есть свободная. Еда: каждое утро вы и каждый сотрудник съедаете по 1 еде; без еды сутки на нуле сытости — смерть",
		"M — звук вкл/выкл · Автосохранение каждое утро · Сохранение/загрузка — в журнале (J)",
		"F — редактор локации: ЛКМ выбрать и тащить, стрелки — точно, PgUp/PgDn — высота, Z/X — поворот, Delete — убрать, Backspace — сброс. Раскладка сохраняется сама",
		"В редакторе Godot: предметы видны в доке «Сцена» внутри World — выбирай и двигай гизмо (W/E), сохраняется само",
		"Генератор: дозаправка (1 топливо), бака — 40 ч; лампа грядки, кухня, печь и измельчитель съедают по 2 ч каждый. Пустой бак или поломка обесточивают двери и печи, через 30 часов темноты — конец игры",
		"Поломки (течь, замыкание, дверь): найдите маркер в бункере, E — чинить деталями или отправить сотрудника на 2 ч",
		"Карта на стене в коридоре: места вылазок с риском и наградой; разведка (3 ч) открывает новые",
		"Клик по сотруднику — разговор: личные просьбы дают подарок и лояльность, а лояльность — бонусы",
		"Кухня: рецепты из продуктов дают временные плюсы (добыча +15%, защита от болезней, выносливость)",
		"Ночью к воротам стучат незнакомцы: отдать требуемое, прогнать или промолчать — решайте быстро",
		"С 3-го дня генератор иногда ломается сам: держите металл, провод и топливо на ремонт — темнота ведёт к концу игры",
		"Больные дома могут заразить других — лечите на кушетке или аптечкой, фильтр воздуха снижает риск. Торговец иногда приходит к воротам (посмотрите в окно, E); выживших можно позвать через радио",
	]
	for s in lines:
		var l := _lbl(s, 16, TXT, true)
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)
	v.add_child(_lbl("Как играть", 24, GOLD))
	var tips := [
		"Со 2-го дня к воротам приходят люди и просятся в бункер: смотри на приметы.",
		"У больного сопли и красный нос (можно вылечить аптечкой). У маньяка нож с кровью в кармане — гнать!",
		"Профессии и что они дают — в окне «Профессии» (клавиша P, а также в журнале и в окне гостя у ворот).",
		"Радио: музыка в бункере. Кто слышал её за последние 6 часов, того вылазка приносит на 15% больше ресурсов.",
		"Грядка даёт картошку и травы. Кухня превращает картошку в еду или бензин, а рецепты — в бонусы.",
		"На верстаке: снаряжение, детали машины, постройки и улучшения построек (до ур.3).",
		"Машина готова (4/4 деталей) — подойди к большим воротам для машины и открой их (E): выезд и победа.",
		"Сотрудники растут в уровнях за успешные вылазки: +1 вместимость и добыча.",
		"Генератор ест топливо каждый час: дозаправляйте за 1 топливо, иначе бункер начнёт гаснуть — 30 часов до конца.",
		"Поломки сами не проходят: протечка портит еду, замыкание жжёт топливо вдвое, дверь закрывает вылазки.",
		"Разведка по карте открывает АЗС, аптеку, склад и другие места — больше добычи, больше риска.",
		"Поговорите с каждым сотрудником: у всех есть история и личная просьба.",
	]
	for s in tips:
		var l := _lbl(s, 15, DIM, true)
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)


# ---------- действия ----------
func _restart() -> void:
	modal = ""
	Game.reset()
	get_tree().reload_current_scene()


func _close() -> void:
	modal = ""
	refresh()


func _toggle_sound() -> void:
	var m := Snd.toggle_mute()
	toast("Звук: выкл" if m else "Звук: вкл")
	refresh()


func _save_game() -> void:
	if Game.save_game():
		toast("Сохранено — день %d" % Game.day())
		refresh()


func _load_game() -> void:
	if Game.load_game():
		Game.menu_skip = true
		get_tree().reload_current_scene()


func _menu_continue() -> void:
	Game.menu_skip = true
	Game.load_game()
	get_tree().reload_current_scene()


func _menu_new() -> void:
	Game.menu_skip = true
	modal = ""
	refresh()  # сначала закрываем меню: reset сразу запустит осмотр напарника
	Game.delete_save()
	Game.reset()
	if _intro_pending:
		_intro_pending = false
		_start_intro()


func _menu_settings() -> void:
	_settings_from_menu = modal == "menu"
	open_modal("settings")


func _back_to_menu() -> void:
	_settings_from_menu = false
	open_modal("menu")


func _quit_game() -> void:
	get_tree().quit()


func _toggle_fullscreen() -> void:
	var target: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_WINDOWED \
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		else DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(target)
	Game.graphics.fullscreen = target == DisplayServer.WINDOW_MODE_FULLSCREEN
	Game.save_graphics()
	refresh()


func _repair_gen() -> void:
	Game.repair_generator()
	refresh()


func _gen_refuel() -> void:
	Game.gen_refuel()
	refresh()


func _pick_site(sid: String) -> void:
	pick_site = sid
	refresh()


func _pick_site_go(sid: String) -> void:
	pick_site = sid
	open_modal("exp")


func _pick_scout(i: int) -> void:
	scout_w = i
	refresh()


func _scout(sid: String) -> void:
	if Game.scout(scout_w, sid):
		modal = ""
		refresh()


func _cook(id: String) -> void:
	Game.cook(id)


func _fulfill(i: int) -> void:
	Game.fulfill_request(i)
	refresh()


func _chat(i: int) -> void:
	Game.talk(i)
	refresh()


func _fix_inc(id: int) -> void:
	Game.fix_incident(id)
	refresh()


func _send_repair(i: int, id: int) -> void:
	Game.send_repair(i, id)
	refresh()


func _gate_give() -> void:
	Game.gate_give()
	Game.npc_wait.emit()  # уходим от окна: камера возвращается


func _gate_refuse() -> void:
	Game.gate_refuse()
	Game.npc_wait.emit()


func _npc_accept() -> void:
	if Game.free_beds() < 1:
		toast("Нет свободной кровати: постройте её на верстаке, затем вернитесь к воротам.")
		return
	hide_npc_bar()
	Game.npc_accept()


func _npc_wait() -> void:
	Game.npc_wait.emit()


func _npc_refuse() -> void:
	hide_npc_bar()
	Game.npc_refuse()


func _craft(kind: String, id: String) -> void:
	Game.craft(kind, id)


func _upgrade(id: String) -> void:
	Game.upgrade(id)


func _toggle_w(i: int) -> void:
	if selected.has(i):
		selected.erase(i)
	else:
		selected.append(i)
	refresh()


func _toggle_pack() -> void:
	pick_pack = not pick_pack
	refresh()


func _toggle_tool(t: String) -> void:
	pick_tool = "" if pick_tool == t else t
	refresh()


func _send() -> void:
	if selected.is_empty():
		return
	if Game.inc_active("door"):
		toast("Дверь заклинило: сначала почините её — вылазки закрыты.")
		return
	if not bool(Game.sites.get(pick_site, false)):
		return
	var failed: Array = []
	for i in selected:
		if not Game.send(i, pick_pack, pick_tool, pick_site):
			failed.append(String(Game.workers[i].name))
	if failed.size() > 0:
		toast("Не вышли: " + ", ".join(failed))
	selected.clear()
	refresh()


func _reset_layout() -> void:
	Game.reset_layout.emit()
	toast("Раскладка сброшена — всё на заводских местах")


func _eat_self() -> void:
	Game.player_eat()


func _rest(i: int) -> void:
	Game.rest(i)


func _rest_all() -> void:
	Game.rest_all()


func _drive() -> void:
	modal = ""
	refresh()
	drive_requested.emit()


func _plant(kind: String) -> void:
	Game.plant(kind)


func _harvest() -> void:
	Game.harvest()


func _do_process(id: String) -> void:
	Game.process(id)


func _heal(i: int) -> void:
	Game.heal_bed(i)


func _use_medkit(i: int) -> void:
	Game.use_medkit(i)
