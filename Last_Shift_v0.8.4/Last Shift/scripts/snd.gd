extends Node
## Snd (автозагрузка): процедурные звуки, синтезируемые кодом — внешних аудиофайлов нет.
## Игровые события вызывают Snd.play("имя"); громкость хранится в user://settings.json.

const SETTINGS_PATH := "user://settings.json"

var volume := 0.7
var muted := false
var _sounds := {}
var _players: Array = []
var _fx := 0
var _amb: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.is_editor_hint():
		return  # в редакторе беззвучно
	_load_settings()
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_amb = AudioStreamPlayer.new()
	add_child(_amb)
	_sounds["click"] = _notes(0.09, [[0.0, 1400.0, 0.05, 0.5]], 55.0)
	_sounds["craft"] = _notes(0.24, [[0.0, 700.0, 0.07, 0.5], [0.09, 1100.0, 0.1, 0.5]], 18.0)
	_sounds["loot"] = _notes(0.24, [[0.0, 900.0, 0.06, 0.45], [0.08, 1400.0, 0.14, 0.5]], 16.0)
	_sounds["levelup"] = _notes(0.5, [[0.0, 660.0, 0.1, 0.5], [0.11, 880.0, 0.1, 0.5], [0.22, 1320.0, 0.2, 0.55]], 12.0)
	_sounds["win"] = _notes(1.15, [[0.0, 523.0, 0.26, 0.5], [0.18, 659.0, 0.26, 0.5], [0.36, 784.0, 0.26, 0.5], [0.54, 1047.0, 0.5, 0.55]], 10.0)
	_sounds["lose"] = _notes(1.5, [[0.0, 220.0, 0.36, 0.5], [0.3, 175.0, 0.36, 0.5], [0.6, 147.0, 0.4, 0.5], [0.92, 110.0, 0.55, 0.55]], 8.0)
	_sounds["radio"] = _notes(1.25, [[0.0, 523.0, 0.14, 0.45], [0.15, 587.0, 0.14, 0.45], [0.3, 659.0, 0.14, 0.45], [0.45, 523.0, 0.14, 0.45], [0.6, 659.0, 0.16, 0.45], [0.76, 784.0, 0.34, 0.5]], 9.0)
	_sounds["knock"] = _synth(0.75, _s_knock)
	_sounds["hatch"] = _synth(0.5, _s_hatch)
	_sounds["alarm"] = _notes(0.7, [[0.0, 880.0, 0.16, 0.5], [0.2, 880.0, 0.16, 0.5], [0.4, 660.0, 0.28, 0.5]], 10.0)
	_sounds["talk"] = _notes(0.16, [[0.0, 500.0, 0.05, 0.4], [0.06, 750.0, 0.08, 0.4]], 20.0)
	_amb.stream = _build_hum()
	_amb.play()
	_apply_volume()


func play(n: String) -> void:
	if _sounds.is_empty() or muted or volume <= 0.0 or not _sounds.has(n):
		return
	var p := _players[_fx] as AudioStreamPlayer
	_fx = (_fx + 1) % _players.size()
	p.stream = _sounds[n]
	p.volume_db = linear_to_db(volume * 0.9)
	p.play()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	muted = false
	_apply_volume()
	_save_settings()


func toggle_mute() -> bool:
	muted = not muted
	_apply_volume()
	_save_settings()
	return muted


func _apply_volume() -> void:
	var base := linear_to_db(maxf(volume, 0.02)) if (volume > 0.001 and not muted) else -80.0
	_amb.volume_db = base - 20.0
	for p in _players:
		(p as AudioStreamPlayer).volume_db = base - 3.0


# ---------- синтез ----------
func _synth(dur: float, fn: Callable, loop := false) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = clampf(fn.call(float(i) / rate, float(i) / float(n)), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	return _wav_from(data, rate, loop)


func _wav_from(data: PackedByteArray, rate: int, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w


func _notes(dur: float, notes: Array, decay := 14.0) -> AudioStreamWAV:
	# notes: [начало, частота, длина, громкость]
	var fn := func(t: float, _p: float) -> float:
		var v := 0.0
		for nt in notes:
			if t >= nt[0] and t < nt[0] + nt[2]:
				var lt: float = t - nt[0]
				v += sin(TAU * nt[1] * lt) * exp(-lt * decay) * nt[3]
		return v
	return _synth(dur, fn)


func _s_knock(t: float, _p: float) -> float:
	var v := 0.0
	for st in [0.0, 0.22, 0.44]:
		if t >= st and t < st + 0.18:
			var lt: float = t - st
			v += sin(TAU * 95.0 * lt) * exp(-lt * 28.0) * 0.9
			v += (randf() * 2.0 - 1.0) * exp(-lt * 60.0) * 0.12
	return v


func _s_hatch(t: float, _p: float) -> float:
	return sin(TAU * 210.0 * t) * exp(-t * 14.0) * 0.55 \
		+ sin(TAU * 440.0 * t) * exp(-t * 20.0) * 0.25 \
		+ (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.3


func _build_hum() -> AudioStreamWAV:
	var fn := func(t: float, _p: float) -> float:
		return sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.18 + sin(TAU * 165.0 * t) * 0.08
	return _synth(2.0, fn, true)


# ---------- настройки ----------
func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"volume": volume, "muted": muted}))


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				volume = clampf(float(d.get("volume", 0.7)), 0.0, 1.0)
				muted = bool(d.get("muted", false))
