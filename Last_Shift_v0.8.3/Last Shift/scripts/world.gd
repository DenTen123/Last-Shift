@tool
class_name BunkerWorld
extends Node3D
## 3D-мир: только бункер в разрезе на тёмном фоне, рампа с люком, гости у люка.
## Управление: ПКМ (можно зажать) — идти за курсором (Shift — бег), камера фиксирована (без зума и стрелок),
## Q/R или СКМ — поворот камеры, ЛКМ/E — действие, C — камера к герою.
## F — редактор локации: двигать мебель, декор и станции.
## Это корень сцены и точка сборки: создаёт модули (scripts/world/*), связывает их сигналами Game
## и раздаёт кадровые обновления. Логики предметной области здесь нет.

const UI := preload("res://scripts/ui.gd")
const M := preload("res://scripts/models.gd")
var ui: CanvasLayer
# Редактор Godot: пресет какого времени суток сейчас показан и правится (свет и окружение настраиваются отдельно для каждого)
@export_enum("Ночь", "Утро", "День", "Вечер") var edit_phase: int = 2:
	set(v):
		if v == edit_phase:
			return
		var old := edit_phase
		edit_phase = v
		if layout != null and Engine.is_editor_hint() and is_inside_tree():
			layout.tod_switch(old, v)
var player: Node3D
var interactables: Array = []

# модули мира: каждый отвечает за одну область (подробности — в шапке файла модуля)
var store: LayoutStore
var layout: SceneLayout
var editor: LocationEditor
var camera: CameraController
var nav: PathNavigator
var rest: RestRoom
var gates: GateController
var staff: StaffController
var station_ctl: StationController
var weather: WeatherSystem
var builder: BunkerBuilder
var player_ctl: PlayerController
var incidents: IncidentController

func _init() -> void:
	store = LayoutStore.new(self)
	layout = SceneLayout.new(self)
	editor = LocationEditor.new(self)
	camera = CameraController.new(self)
	nav = PathNavigator.new(self)
	rest = RestRoom.new(self)
	gates = GateController.new(self)
	staff = StaffController.new(self)
	station_ctl = StationController.new(self)
	weather = WeatherSystem.new(self)
	builder = BunkerBuilder.new(self)
	player_ctl = PlayerController.new(self)
	incidents = IncidentController.new(self)


func _build_world_geometry() -> void:
	for c in get_children():
		c.free()
	# Реестры сбрасываются и при повторном построении предпросмотра.
	layout.reset_registry()
	interactables.clear()
	incidents.clear_markers()
	station_ctl.stations.clear()
	nav.obstacles.clear()
	weather.omnis.clear()
	weather.precips.clear()
	weather.precip_pms.clear()
	builder.props.clear()
	builder.hot_bodies.clear()
	builder.potato_crates.clear()
	weather.build_env()
	builder.build_bunker()
	builder.build_surface()
	builder.build_objects()
	station_ctl.build_stations()
	builder.build_actors()
	rest.build_rest_extension()  # строго после остальных: индексы сохранённой раскладки не сдвигаются
	layout.register_scene_items(self)


func refresh_editor_models() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	# Сохраняем правки гизмо перед пересозданием предпросмотра.
	layout.editor_poll(1.0)
	M.clear_scene_cache()
	_build_world_geometry()
	builder.editor_look()  # сначала «показать всё», затем применить ваше скрытие
	layout.layout_apply()
	layout.editor_own_items.call_deferred()


func _ready() -> void:
	# сцена строится кодом: и в редакторе (@tool), и в игре
	_build_world_geometry()
	if Engine.is_editor_hint():
		builder.editor_look()
		layout.layout_apply()  # показать в редакторе раскладку, сохранённую ранее
		layout.editor_own_items.call_deferred()  # ждём назначения edited_scene_root
		return
	nav.register_obstacles()
	layout.layout_apply()
	nav.build_astar()
	camera.build_camera()
	ui = UI.new()
	add_child(ui)
	ui.drive_requested.connect(gates.start_drive)
	Game.changed.connect(_on_changed)
	Game.worker_left.connect(staff.on_left)
	Game.worker_back.connect(staff.on_back)
	Game.npc_arrived.connect(staff.on_npc_arrived)
	Game.npc_done.connect(staff.on_npc_done)
	Game.npc_wait.connect(staff.on_npc_wait)
	Game.station_used.connect(station_ctl.on_station_used)
	Game.reset_layout.connect(editor.edit_reset)  # кнопка «Сбросить раскладку» в журнале
	if Game.visitor != {}:
		staff.on_npc_arrived(String(Game.visitor.name), String(Game.visitor.status))  # гость из сохранения
	_on_changed()


func _notification(what: int) -> void:
	# авто-пауза, когда окно игры теряет фокус
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not Engine.is_editor_hint():
		editor.edit_finish_drag()
		if Game.end_state == "" and not Game.cinematic and not Game.paused and ui != null:
			Game.paused = true
			ui.toast("Окно не в фокусе — пауза (Space — продолжить)")


func flush_layout() -> void:
	# вызывается плагином при сохранении сцены в редакторе
	if Engine.is_editor_hint() and is_inside_tree():
		layout.editor_flush()


func _on_changed() -> void:
	gates.sync_car()
	builder.sync_scene_props()
	staff.sync_workers()
	rest.sync_beds()
	station_ctl.update_stations()
	incidents.sync()
	weather.apply_weather()
	layout.enforce_hidden()


func _input(e: InputEvent) -> void:
	# Начинаем выбор вне GUI, но перенос получает события и над панелью.
	if Engine.is_editor_hint() or not editor.edit_mode or not editor.edit_drag:
		return
	if e is InputEventMouseMotion or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed):
		# Не оставляем захват после удаления узла или пропущенного отпускания.
		if editor.edit_selected.is_empty() or not is_instance_valid(editor.edit_selected.mv):
			editor.edit_finish_drag()
		elif e is InputEventMouseMotion and not (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			editor.edit_finish_drag()
		else:
			editor.edit_input(e)
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F and Game.end_state == "" and not Game.cinematic and not Game.modal_open:
		editor.toggle_edit()
		return
	if editor.edit_mode:
		editor.edit_input(e)
		return
	player_ctl.play_input(e)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		layout.editor_poll(delta)
		return
	if Game.end_state != "":
		return
	if editor.edit_mode:
		editor.edit_tick(delta)
		return
	if not Game.cinematic:
		camera.camera_input(delta)
	player_ctl.update_player(delta)
	staff.update_workers(delta)
	weather.update_weather_fx(delta)
	player_ctl.update_hover()
	layout.enforce_hidden()
