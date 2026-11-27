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

# Единый набор обработанных 3D-иконок из пользовательского архива.
const UI_ICONS := {
	"metal": "res://assets/ui/icons/metal.png",
	"plastic": "res://assets/ui/icons/plastic.png",
	"wire": "res://assets/ui/icons/wire.png",
	"fuel": "res://assets/ui/icons/fuel.png",
	"rubber": "res://assets/ui/icons/wheels.png",
	"steel": "res://assets/ui/icons/steel.png",
	"chips": "res://assets/ui/icons/chips.png",
	"seeds": "res://assets/ui/icons/seeds.png",
	"potato": "res://assets/ui/icons/potato.png",
	"food": "res://assets/ui/icons/potato.png",
	"herbs": "res://assets/ui/icons/herbs.png",
	"medkit": "res://assets/ui/icons/medkit.png",
	"pack": "res://assets/ui/icons/pack.png",
	"magnet": "res://assets/ui/icons/gear.png",
	"drill": "res://assets/ui/icons/drill.png",
	"engine": "res://assets/ui/icons/engine.png",
	"wheels": "res://assets/ui/icons/wheels.png",
	"battery": "res://assets/ui/icons/chips.png",
	"tank": "res://assets/ui/icons/fuel.png",
	"gear": "res://assets/ui/icons/gear.png",
	"bottle": "res://assets/ui/icons/bottle.png",
}

var modal := ""
var pick_w := 0
var pick_pack := false
var pick_tool := ""

var _hud: Control
var _modal_root: Control
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
var _trader_btn: Button
var _pause_label: Label
var _hint_label: Label
var _toasts: VBoxContainer
var _npc_bar: PanelContainer
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
	_npc_camera = camera
	_npc_target = target
	_npc_story_title.text = "%s · %s" % [Game.visitor.name, Game.PROFS[Game.visitor.prof].name]
	_npc_story_text.text = "«%s»" % Game.visitor_story()
	_npc_story_scroll.scroll_vertical = 0
	_npc_bar.visible = true
	_npc_story.visible = true
	_place_npc_story()


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
	b.pressed.connect(cb)
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
	_trader_btn = _btn("Торговец у люка — торговать", _open_trader)
	_trader_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_trader_btn.position = Vector2(-120, 10)
	_trader_btn.visible = false
	_hud.add_child(_trader_btn)
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
	_npc_bar.offset_left = -200.0
	_npc_bar.offset_right = 200.0
	_npc_bar.offset_top = -64.0
	_npc_bar.offset_bottom = -14.0
	_npc_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var nb := HBoxContainer.new()
	nb.alignment = BoxContainer.ALIGNMENT_CENTER
	nb.add_theme_constant_override("separation", 16)
	_npc_bar.add_child(nb)
	nb.add_child(_btn("Пустить в бункер", _npc_accept))
	nb.add_child(_btn("Прогнать", _npc_refuse))
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
	_modal_root = Control.new()
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_root)
	_build_intro()
	if Game.has_save() and not Game.menu_skip and Game.end_state == "":
		open_modal("menu")  # меню продолжения при запуске


func _build_intro() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	var lines := [
		"ПКМ (можно зажать) — идти за курсором, Shift — бег · Стрелки — камера · Колесо — зум",
		"ЛКМ по предмету или E — открыть · Q/R или СКМ — поворот камеры",
		"Со 2-го дня к воротам приходят люди: у больного сопли, у маньяка нож в кармане",
		"Грядка → картошка · Кухня → еда и бензин · Верстак → постройки и улучшения",
		"Space — пауза · T — +1 час · J — журнал · H — помощь · M — звук · Esc — закрыть окно",
		"F — редактор всей сцены: список объектов, перенос, поворот, масштаб (+/−)",
	]
	for s in lines:
		var l := _lbl(s, 15, TXT, true)
		l.custom_minimum_size = Vector2(620, 0)  # без этого текст сжимается в вертикальный столбик
		v.add_child(l)
	cc.add_child(pc)
	cc.modulate.a = 0.0
	_modal_root.add_child(cc)
	_ignore_mouse(cc)
	var tw := create_tween()
	tw.tween_property(cc, "modulate:a", 1.0, 0.5)
	tw.tween_interval(10.0)
	tw.tween_property(cc, "modulate:a", 0.0, 1.0)
	tw.tween_callback(cc.queue_free)


func _process(_delta: float) -> void:
	_pause_label.visible = Game.paused and Game.end_state == ""
	if _npc_bar.visible:
		if Game.visitor.is_empty() or Game.end_state != "":
			hide_npc_bar()
		else:
			_place_npc_story()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match e.physical_keycode:
		KEY_ESCAPE:
			if modal != "":
				_close()
		KEY_SPACE:
			if Game.end_state == "" and not Game.cinematic:
				Game.paused = not Game.paused
		KEY_T:
			if Game.end_state == "" and not Game.cinematic:
				Game.advance(60)
				toast("+1 час")
		KEY_J:
			modal = "" if modal == "log" else "log"
			refresh()
		KEY_M:
			var m := Snd.toggle_mute()
			toast("Звук: выкл" if m else "Звук: вкл")
		KEY_H:
			modal = "" if modal == "help" else "help"
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
	if Game.player_st < 50:
		_sleep_lbl.text = "Пора спать на койках: бодрость %d%%. Ещё %d ч без сна — и конец." % [Game.player_st, maxi(0, (Game.AWAKE_LIMIT - Game.player_awake) / 60)]
		_sleep_lbl.visible = true
	elif Game.player_food < 25:
		_sleep_lbl.text = "Вы голодны — поешьте (стеллаж/кухня)."
		_sleep_lbl.visible = true
	else:
		_sleep_lbl.visible = false
	_trader_btn.visible = not Game.trader.is_empty()


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
	if ev is InputEventMouseButton and ev.pressed:
		_close()


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
		"inv": _m_inventory(v)
		"bench": _m_bench(v)
		"car": _m_car(v)
		"bed": _m_bed(v)
		"radio": _m_radio(v)
		"trader": _m_trader(v)
		"exp": _m_exp(v)
		"garden": _m_garden(v)
		"kitchen": _m_proc(v, "kitchen")
		"furnace": _m_proc(v, "furnace")
		"shredder": _m_proc(v, "shredder")
		"medbed": _m_medbed(v)
		"medcab": _m_medcab(v)
		"gen": _m_gen(v)
		"menu": _m_menu(v)
		"log": _m_log(v)
		"help": _m_help(v)
		_:
			if modal.begins_with("need:"):
				_m_need(v, modal.substr(5))
	v.add_child(_btn("Закрыть", _close))
	var modal_width: float = 990.0 if wide_modal else 620.0
	var modal_height: float = 610.0 if wide_modal else 560.0
	sc.custom_minimum_size = Vector2(modal_width, minf(v.get_combined_minimum_size().y + 8.0, modal_height))
	_modal_sc = sc
	sc.scroll_vertical = int(_scroll)
	var set_scroll := func() -> void:
		if _modal_sc != null and is_instance_valid(_modal_sc):
			_modal_sc.scroll_vertical = int(_scroll)
	set_scroll.call_deferred()


func _m_menu(v: VBoxContainer) -> void:
	v.add_child(_lbl("Метеостанция Люк-30", 26, GOLD))
	var l := _lbl("Найдено сохранение — День %d. Продолжить или начать заново?" % Game.peek_save_day(), 16, TXT, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_btn("Продолжить", _menu_continue))
	row.add_child(_btn("Новая игра", _menu_new))


func _m_gen(v: VBoxContainer) -> void:
	v.add_child(_lbl("Генератор", 24, GOLD))
	if Game.gen_broken:
		var l := _lbl("Генератор сломан — свет в бункере тусклый и мигает. Уюта меньше, но люди живы.", 16, BAD, true)
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)
		v.add_child(_btn("Починить: %s (30 мин)" % Game.cost_text(Game.GEN_COST), _repair_gen, not Game.can(Game.GEN_COST)))
	else:
		v.add_child(_lbl("Генератор работает штатно — бункер освещён.", 16, TXT, true))
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


func _m_bench(v: VBoxContainer) -> void:
	v.add_child(_lbl("МАСТЕРСКАЯ  /  СБОРКА И МОДЕРНИЗАЦИЯ", 12, DIM))
	v.add_child(_lbl("Верстак", 29, GOLD))
	v.add_child(_lbl("Собирайте снаряжение, детали машины и оборудование для комнат бункера.", 14, DIM, true))

	var stock := HBoxContainer.new()
	stock.add_theme_constant_override("separation", 8)
	v.add_child(stock)
	for id in ["metal", "plastic", "wire", "fuel", "rubber"]:
		_add_stock_chip(stock, id)

	_section_header(v, "01  /  СНАРЯЖЕНИЕ", "Инструменты и экипировка для вылазок")
	var gear_grid := _new_craft_grid(v)
	for id in Game.GEAR:
		var d: Dictionary = Game.GEAR[id]
		var owned: int = int(Game.gear[id])
		var desc: String = String(d.desc) + ("  ·  Уже создано: %d" % owned if owned > 0 else "")
		_add_craft_card(gear_grid, d.name, desc, d.cost, id, _craft.bind("gear", id), not Game.can(d.cost))

	_section_header(v, "02  /  ДЕТАЛИ МАШИНЫ", "Комплектующие для восстановления транспорта")
	var car_grid := _new_craft_grid(v)
	for id in Game.CAR:
		var d: Dictionary = Game.CAR[id]
		if Game.car[id]:
			_add_craft_card(car_grid, d.name, "Компонент установлен на автомобиль.", d.cost, id, Callable(), false, "УСТАНОВЛЕНО")
		else:
			_add_craft_card(car_grid, d.name, "Деталь автомобиля. После сборки будет установлена автоматически.", d.cost, id, _craft.bind("car", id), not Game.can(d.cost))

	_m_build(v)
	_m_upgrades(v)


func _m_build(v: VBoxContainer) -> void:
	_section_header(v, "03  /  ОБОРУДОВАНИЕ БУНКЕРА", "Стройте комнаты и полезные станции")
	var grid := _new_craft_grid(v)
	var bed_desc := "Кровать для одного сотрудника. Каждому жителю нужно отдельное место для сна."
	var bed_status := "МЕСТА: %d / %d" % [Game.beds, Game.MAX_BEDS] if Game.beds >= Game.MAX_BEDS else ""
	_add_craft_card(grid, "Кровать", bed_desc, Game.BED_COST, "gear", _build_bed, Game.beds >= Game.MAX_BEDS or not Game.can(Game.BED_COST), bed_status)

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
	_section_header(v, "04  /  МОДЕРНИЗАЦИЯ", "Улучшения открываются после постройки соответствующей станции")
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
	match id:
		"garden", "lamp":
			return "herbs"
		"irrig", "coffee":
			return "bottle"
		"kitchen":
			return "potato"
		"furnace":
			return "steel"
		"shredder":
			return "chips"
		"medbed", "medcab":
			return "medkit"
		"filter":
			return "plastic"
		"insul":
			return "wire"
	return "gear"


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


func _icon_texture(id: String) -> Texture2D:
	var path: String = String(UI_ICONS.get(id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


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
	v.add_child(_lbl("Грядка (ур.%d)" % (Game.upg.garden + 1), 24, GOLD))
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
	if Game.has_prof("agronom"):
		v.add_child(_lbl("Агроном сам сажает и собирает урожай.", 14, OK, true))
	var b := _lbl("Ускорители: лампа %s · полив %s · ур.2 %s" % ["есть" if Game.built.lamp else "нет", "есть" if Game.built.irrig else "нет", "есть" if Game.upg.garden >= 1 else "нет"], 14, DIM, true)
	b.custom_minimum_size = Vector2(560, 0)
	v.add_child(b)
	if c.state == "empty":
		for k in Game.CROPS:
			v.add_child(_btn("Посадить: %s (1 семя)" % Game.CROPS[k].name, _plant.bind(k), Game.res.seeds < 1))
	elif c.state == "ready":
		v.add_child(_btn("Собрать урожай", _harvest))


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
	elif Game.built.garden and Game.crop.state == "empty" and Game.res.seeds >= 1 and not Game.has_prof("agronom"):
		out.append("Посадите картошку на грядке")
	if Game.crop.state == "ready" and not Game.has_prof("agronom"):
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
	if out.is_empty():
		out.append("Всё идёт по плану — следите за погодой и гостями")
	return out


func _m_bed(v: VBoxContainer) -> void:
	v.add_child(_lbl("Койки", 24, GOLD))
	var info := _lbl("Кроватей: %d из %d. Сотрудники сами ложатся спать в 22:00 и встают в 06:00 (+40 выносливости). Без кровати двое суток без сна — и сотрудник погибает." % [Game.beds, Game.MAX_BEDS], 15, TXT, true)
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
		v.add_child(_lbl("%s — выносливость %d · %s" % [w.name, w.st, st], 15, OK if has_bed else BAD))


func _m_radio(v: VBoxContainer) -> void:
	v.add_child(_lbl("Радио", 24, GOLD))
	var amt := 25 if Game.has_prof("radio_tech") else 15
	v.add_child(_btn("Слушать музыку (30 мин): сотрудникам +%d выносливости, вам +10%% бодрости" % amt, _radio_music))
	var sig_wait: int = Game.radio_signal_at - Game.t
	var sg_txt := "Передать сигнал выживших (30 мин): завтра к люку точно придут"
	if Game.radio_signal:
		sg_txt = "Сигнал передан — ждите гостя завтра в 9:00"
	elif sig_wait > 0:
		sg_txt = "Сигнал выживших — через %d ч" % ((sig_wait + 59) / 60)
	v.add_child(_btn(sg_txt, _radio_signal, sig_wait > 0 or Game.radio_signal))
	var hl := _lbl("Торговец заходит сам: каждый день в 13:00 с вероятностью 20%, стоит у люка 8 часов. Меняет излишки топлива, резины, проводов на металл, пластик, платы, сталь, аптечки.", 13, DIM, true)
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
	if Game.workers.is_empty():
		var lw := _lbl("Пока нет сотрудников: бункер пуст. Со 2-го дня к воротам начнут приходить люди — принимай здоровых специалистов.", 15, DIM, true)
		lw.custom_minimum_size = Vector2(560, 0)
		v.add_child(lw)
		return
	v.add_child(_lbl("Кого отправить", 18, GOLD))
	for i in Game.workers.size():
		var w: Dictionary = Game.workers[i]
		var st := " — потерян" if w.dead else (" — снаружи" if w.away != null else "")
		v.add_child(_btn("%s%s — %s (ур.%d): вместимость %d, добыча ×%.1f, выносливость %d, здоровье %d%s" % ["▶ " if i == pick_w else "", w.name, Game.PROFS[w.prof].name, w.lvl, w.cap, w.eff, w.st, w.hp, " (болен)" if w.sick else ""], _pick.bind(i), w.dead))
	v.add_child(_lbl("Снаряжение", 18, GOLD))
	var gh := _lbl("Рюкзак: +4 вместимости (больше добычи). Магнит: ×1,5 металла и проводов. Бур: ×1,5 топлива, резины и пластика. Вылазка приносит 1–3 разных ресурса; расходуется только отметка на этот выход — само снаряжение не пропадает.", 13, DIM, true)
	gh.custom_minimum_size = Vector2(560, 0)
	v.add_child(gh)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_btn(("▶ " if pick_pack else "") + "Рюкзак ×%d" % Game.gear.pack, _toggle_pack, Game.gear.pack == 0))
	for t in ["magnet", "drill"]:
		row.add_child(_btn(("▶ " if pick_tool == t else "") + "%s ×%d" % [Game.GEAR[t].name, Game.gear[t]], _toggle_tool.bind(t), Game.gear[t] == 0))
	pick_w = clampi(pick_w, 0, Game.workers.size() - 1)
	var w: Dictionary = Game.workers[pick_w]
	var can_go: bool = not w.dead and w.away == null and not w.get("asleep", false) and w.st >= Game.MIN_STAMINA and w.hp >= Game.MIN_HP and not w.sick
	v.add_child(_btn("Отправить", _send, not can_go))
	var hint := _lbl("Успешная вылазка: +25 опыта. Уровень даёт +1 вместимость и добычу.", 13, DIM, true)
	hint.custom_minimum_size = Vector2(560, 0)
	v.add_child(hint)
	if not w.dead and w.away == null:
		if w.sick:
			v.add_child(_lbl("Болен: вылечите на кушетке или аптечкой.", 15, BAD, true))
		elif w.hp < Game.MIN_HP:
			v.add_child(_lbl("Ранен (нужно здоровье %d+): лечение в больничном кабинете." % Game.MIN_HP, 15, BAD, true))
		elif w.st < Game.MIN_STAMINA:
			v.add_child(_lbl("Слишком устал (нужно %d+)." % Game.MIN_STAMINA, 15, BAD))


func _m_log(v: VBoxContainer) -> void:
	v.add_child(_lbl("Журнал", 24, GOLD))
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_btn("Сохранить игру", _save_game))
	row.add_child(_btn("Загрузить игру", _load_game))
	row.add_child(_btn("Сбросить раскладку", _reset_layout))
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
		var m := _lbl("%s — %s (ур.%d%s) · %s" % [p.name, Game.PROFS[p.prof].name, p.lvl, xp_txt, s], 15, TXT, true)
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


func _m_help(v: VBoxContainer) -> void:
	v.add_child(_lbl("Управление", 24, GOLD))
	var lines := [
		"ПКМ — идти к точке; пока ПКМ зажата, персонаж идёт за курсором · Shift — бежать",
		"ЛКМ по предмету или E — открыть · зажмите ЛКМ или ПКМ на полу — персонаж идёт за курсором · на паузе (Space) ходить и действовать нельзя",
		"1–9, 0 — быстрый переход: грядка / кухня / склад / верстак / экспедиция / койки / печь / измельчитель / кушетка / аптека",
		"Стрелки — двигать камеру · колесо — зум · Q/R или зажатая СКМ — поворот камеры",
		"C — камера к персонажу · Space — пауза · T — пропустить час",
		"J — журнал · H — помощь · Esc — закрыть окно",
		"Сон: ваша бодрость падает, пока вы не спите (48 часов без сна — смерть); койка даёт 8 часов сна и полную бодрость. Сотрудники сами ложатся в 22:00: без кровати двое суток без сна — и они гибнут. Еда: каждое утро вы и каждый сотрудник съедаете по 1 еде; без еды сутки на нуле сытости — смерть",
		"M — звук вкл/выкл · Автосохранение каждое утро · Сохранение/загрузка — в журнале (J)",
		"F — редактор локации: ЛКМ выбрать и тащить, стрелки — точно, PgUp/PgDn — высота, Z/X — поворот, Delete — убрать, Backspace — сброс. Раскладка сохраняется сама",
		"В редакторе Godot: предметы видны в доке «Сцена» внутри World — выбирай и двигай гизмо (W/E), сохраняется само",
		"С 3-го дня генератор иногда ломается: свет тускнеет — почините (металл, провод, топливо)",
		"Больные дома могут заразить других — лечите на кушетке или аптечкой, фильтр воздуха снижает риск. Торговец иногда заходит сам (кнопка вверху экрана); выживших можно позвать через радио",
	]
	for s in lines:
		var l := _lbl(s, 16, TXT, true)
		l.custom_minimum_size = Vector2(560, 0)
		v.add_child(l)
	v.add_child(_lbl("Как играть", 24, GOLD))
	var tips := [
		"Со 2-го дня к воротам приходят люди и просятся в бункер: смотри на приметы.",
		"У больного сопли и красный нос (можно вылечить аптечкой). У маньяка нож с кровью в кармане — гнать!",
		"Профессии: инженер и механик — ресурсы для машины, агроном — грядка, повар и химик — еда и бензин, медик лечит, радиотехник — радио и платы, охотник — еда, разведчик — безопасные вылазки, учитель — бодрость.",
		"Грядка даёт картошку и травы. Кухня превращает картошку в еду или бензин.",
		"На верстаке: снаряжение, детали машины, постройки и улучшения построек (до ур.3).",
		"Машина готова (4/4 деталей) — подойди к большим воротам для машины и открой их (E): выезд и победа.",
		"Сотрудники растут в уровнях за успешные вылазки: +1 вместимость и добыча.",
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
	Game.delete_save()
	Game.reset()
	modal = ""
	refresh()


func _repair_gen() -> void:
	Game.repair_generator()
	refresh()


func _npc_accept() -> void:
	hide_npc_bar()
	Game.npc_accept()


func _npc_refuse() -> void:
	hide_npc_bar()
	Game.npc_refuse()


func _craft(kind: String, id: String) -> void:
	Game.craft(kind, id)


func _upgrade(id: String) -> void:
	Game.upgrade(id)


func _pick(i: int) -> void:
	pick_w = i
	refresh()


func _toggle_pack() -> void:
	pick_pack = not pick_pack
	refresh()


func _toggle_tool(t: String) -> void:
	pick_tool = "" if pick_tool == t else t
	refresh()


func _send() -> void:
	if Game.send(pick_w, pick_pack, pick_tool):
		modal = ""
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
