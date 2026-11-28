@tool
class_name WeatherSystem
extends RefCounted
## Окружение: свет по времени суток, осадки, ветер.
## Свет и окружение (WorldEnvironment, солнце, лампы) НЕ настраиваются кодом сами: значения берутся из пресетов
## времени суток (ночь / утро / день / вечер), которые вы настраиваете в редакторе Godot (см. SCENE_EDITOR.md).
## В игре между соседними пресетами идёт плавный переход. Если пресет не настраивали, действуют значения по умолчанию.
## Осадки (дождь/снег) и ветряк зависят от погоды и сглаживаются.

const DEFAULT_LIGHT := [0.12, 0.7, 1.1, 0.45]  # яркость по умолчанию: ночь, утро, день, вечер
const WEATHER_BLEND := 0.25  # погода меняется плавно в последней четверти фазы (1,5 ч из 6)
const SMOOTH_RATE := 1.6  # скорость, с которой картинка догоняет целевые значения

var host: BunkerWorld
var sun: DirectionalLight3D
var env: Environment
var anemo: Node3D
var wind_now := 0.0
var omnis: Array = []
var precips: Array = []
var precip_pms: Array = []
var _cur := {}  # сглаженные значения, которые видит игрок
var _tgt := {}  # целевые значения по текущему времени
var _p_snow := false
var _p_ratio := 0.0
var _presets: Array = []  # готовые пресеты четырёх фаз
var _applied := {}  # что уже выставлено на узлах (чтобы не дёргать свойства без надобности)

func _init(h: BunkerWorld) -> void:
	host = h


func build_env() -> void:
	invalidate_presets()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.74)
	env.fog_enabled = true
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	host.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	host.add_child(sun)


func build_precip() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 1.0, 10.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.gravity = Vector3(0, -30, 0)
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(0.55, 0.66, 0.82)
	precip_pms.append(pm)
	var pr := GPUParticles3D.new()
	pr.position = Vector3(-26, 9.0, 0)
	pr.amount = 800
	pr.lifetime = 1.1
	pr.process_material = pm
	pr.draw_pass_1 = mesh
	pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pr.visibility_aabb = AABB(Vector3(-16, -12, -14), Vector3(32, 30, 28))
	pr.emitting = false
	host.add_child(pr)
	precips.append(pr)
	_p_snow = false
	_p_ratio = 0.0


# ---------- пресеты времени суток ----------
# Значения по умолчанию для фазы p: то, что раньше выставлял код (теперь это просто стартовая точка для ваших правок)
func _defaults(p: int) -> Dictionary:
	var l: float = DEFAULT_LIGHT[p]
	var bg := Color(0.03, 0.035, 0.045).lerp(Color(0.11, 0.13, 0.16), clampf(l, 0.0, 1.0))
	var env_d := {"background_color": bg, "fog_light_color": bg, "fog_density": 0.003, "ambient_light_energy": 0.3 + 0.3 * l}
	var lights := {}
	lights[sun] = {"light_energy": maxf(l, 0.06), "light_color": WorldConfig.SUN_COLS[p]}
	var night := 1.0 - clampf(l * 1.3, 0.0, 1.0)
	for o in omnis:
		lights[o] = {"light_energy": 1.1 + night * 0.6}
	return {"env": env_d, "lights": lights}


# Пресет фазы p: умолчания + ваши значения из раскладки
func preset(p: int) -> Dictionary:
	var pre := _defaults(p)
	var user: Dictionary = host.layout.tod_user(p)
	var ue: Dictionary = user.get("env", {})
	for k in ue:
		pre.env[k] = host.layout.unpack_value(env.get(k), ue[k])
	var ul: Dictionary = user.get("lights", {})
	for lname in ul:
		var it: Dictionary = host.layout.item_by_name(lname)
		if it.is_empty() or not is_instance_valid(it.mv) or not (it.mv is Light3D):
			continue
		var lt := it.mv as Light3D
		if not pre.lights.has(lt):
			pre.lights[lt] = {}
		for k in ul[lname]:
			pre.lights[lt][k] = host.layout.unpack_value(lt.get(k), ul[lname][k])
	return pre


func invalidate_presets() -> void:
	_presets.clear()
	_applied.clear()


# Выставить пресет фазы целиком (редактор Godot: показать, как выглядит эта фаза)
func apply_preset_now(p: int) -> void:
	var pre := preset(p)
	for k in pre.env:
		env.set(k, pre.env[k])
	for lt in pre.lights:
		for k in pre.lights[lt]:
			(lt as Object).set(k, pre.lights[lt][k])


func _blend_props(obj: Object, da: Dictionary, db: Dictionary, f: float) -> void:
	var keys: Array = da.keys()
	for k in db:
		if not keys.has(k):
			keys.append(k)
	for k in keys:
		var va: Variant = da.get(k, db.get(k))
		var vb: Variant = db.get(k, va)
		var v: Variant
		if va is float and vb is float:
			v = lerpf(va, vb, f)
		elif va is Color and vb is Color:
			v = (va as Color).lerp(vb, f)
		elif va is Vector3 and vb is Vector3:
			v = (va as Vector3).lerp(vb, f)
		else:
			v = va if f < 0.5 else vb
		var ck := "%d:%s" % [obj.get_instance_id(), k]
		if not _applied.has(ck) or _applied[ck] != v:
			obj.set(k, v)
			_applied[ck] = v


func _apply_time_of_day() -> void:
	if _presets.is_empty():
		for p in 4:
			_presets.append(preset(p))
	var x := float(_cur.x)  # непрерывная позиция по кругу фаз; опорные точки — середины фаз
	var k0 := int(floor(x))
	var f := smoothstep(0.0, 1.0, x - float(k0))
	var pa: Dictionary = _presets[posmod(k0, 4)]
	var pb: Dictionary = _presets[posmod(k0 + 1, 4)]
	# генератор обесточен: внутренний свет и ambient гаснут за 30 часов до полной темноты (солнце на поверхности не трогаем)
	var dim := 1.0 - 0.95 * Game.darkness_factor()
	var fx := bool(Game.graphics.get("effects", true))  # пользовательские эффекты: свечение, SSAO, туман
	var ea: Dictionary = (pa.env as Dictionary).duplicate()
	var eb: Dictionary = (pb.env as Dictionary).duplicate()
	if ea.has("ambient_light_energy"):
		ea["ambient_light_energy"] = float(ea["ambient_light_energy"]) * dim
	if eb.has("ambient_light_energy"):
		eb["ambient_light_energy"] = float(eb["ambient_light_energy"]) * dim
	if not fx:
		for k in ["glow_enabled", "ssao_enabled", "fog_enabled"]:
			ea[k] = false
			eb[k] = false
	_blend_props(env, ea, eb, f)
	var lts: Array = pa.lights.keys()
	for lt in pb.lights:
		if not lts.has(lt):
			lts.append(lt)
	for lt in lts:
		if not is_instance_valid(lt):
			continue
		var la: Dictionary = (pa.lights.get(lt, pb.lights.get(lt, {})) as Dictionary).duplicate()
		var lb: Dictionary = (pb.lights.get(lt, la) as Dictionary).duplicate()
		if lt != sun:
			if la.has("light_energy"):
				la["light_energy"] = float(la["light_energy"]) * dim
			if lb.has("light_energy"):
				lb["light_energy"] = float(lb["light_energy"]) * dim
		elif not bool(Game.graphics.get("shadows", true)):
			la["shadow_enabled"] = false  # тени солнца отключены в настройках графики
			lb["shadow_enabled"] = false
		_blend_props(lt, la, lb, f)


# ---------- погода (осадки, ветер) ----------
func _target() -> Dictionary:
	var tt: int = Game.t
	var ph := tt / 360
	var u := float(tt % 360) / 360.0
	var w0: Dictionary = Game.weather_at(ph * 360)
	var w1: Dictionary = Game.weather_at((ph + 1) * 360)
	var wf := 0.0
	if u > 1.0 - WEATHER_BLEND:
		wf = smoothstep(0.0, 1.0, (u - (1.0 - WEATHER_BLEND)) / WEATHER_BLEND)
	return {
		"x": float(tt) / 360.0 - 0.5,
		"cloud": lerpf(float(w0.cloud), float(w1.cloud), wf),
		"wind": lerpf(float(w0.wind), float(w1.wind), wf),
		"temp": lerpf(float(w0.temp), float(w1.temp), wf),
		"storm": lerpf(1.0 if w0.bad else 0.0, 1.0 if w1.bad else 0.0, wf),
	}


# Вызывается при изменении состояния игры: обновляет цель, картинка подтягивается в update_weather_fx
func apply_weather() -> void:
	_tgt = _target()
	if _cur.is_empty():
		_cur = _tgt.duplicate()
		_apply_all(0.0)


func _approach(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTH_RATE * delta)
	for key in ["x", "cloud", "wind", "temp", "storm"]:
		_cur[key] = lerpf(float(_cur[key]), float(_tgt[key]), k)


func _set_precip_mode(snowy: bool) -> void:
	for pm in precip_pms:
		if snowy:
			pm.gravity = Vector3(0, -2.4, 0)
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.4
			pm.scale_min = 0.9
			pm.scale_max = 1.8
			pm.spread = 15.0
			pm.color = Color(0.95, 0.96, 1.0)
		else:
			pm.gravity = Vector3(0, -30, 0)
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.scale_min = 0.5
			pm.scale_max = 1.0
			pm.spread = 6.0
			pm.color = Color(0.55, 0.66, 0.82)
	for pr in precips:
		pr.lifetime = 3.2 if snowy else 1.1


func _apply_all(delta: float) -> void:
	_apply_time_of_day()
	var cl := float(_cur.cloud)
	wind_now = float(_cur.wind)
	var storm := float(_cur.storm)
	# осадки над площадкой люка: дождь или снег; вид осадков меняется только когда прежние затухли
	var want_snow := float(_cur.temp) <= 0.0
	var ratio := clampf((cl - 40.0) / 60.0, 0.0, 1.0)
	ratio = minf(ratio + 0.25 * storm, 1.0) * smoothstep(42.0, 50.0, cl)
	if want_snow != _p_snow:
		ratio = 0.0
		if _p_ratio < 0.03:
			_p_snow = want_snow
			_set_precip_mode(_p_snow)
	var kp := 1.0 if delta <= 0.0 else 1.0 - exp(-1.2 * delta)
	_p_ratio = lerpf(_p_ratio, ratio, kp)
	if ratio == 0.0 and _p_ratio < 0.01:
		_p_ratio = 0.0
	for pm in precip_pms:
		pm.direction = Vector3(wind_now / 26.0 * 0.6, -1.0, 0.12).normalized()
	for pr in precips:
		pr.emitting = _p_ratio > 0.0
		pr.amount_ratio = _p_ratio


# Каждый кадр: плавный переход между пресетами времени суток, осадки, ветряк
func update_weather_fx(delta: float) -> void:
	if _cur.is_empty():
		apply_weather()
	_approach(delta)
	_apply_all(delta)
	if anemo != null:
		anemo.rotation.y += delta * (1.0 + wind_now * 0.4)
