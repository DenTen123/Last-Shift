extends SceneTree
## Замена иконок на новые рендеры: кадрирует по контенту, квадрат 128x128.
## Запуск: godot --headless --path . --script res://tests/icon_swap.gd

const JOBS := [
	["D:/Загрузки/Измельчитель.png", "shredder.png"],
	["D:/Загрузки/Готовая Кровать.png", "bed.png"],
	["D:/Загрузки/Готовая кушетка.png", "medbed.png"],
	["D:/Загрузки/Печка.png", "furnace.png"],
]
const OUT_DIR := "C:/Users/admin/.zcode/workspace/default/last_shift_v082_work/extracted/Last_Shift_v0.8.2/Last Shift/scripts/icons"


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	create_timer(30.0).timeout.connect(func(): quit(2))


func _run() -> void:
	for j in JOBS:
		var img := Image.load_from_file(j[0])
		if img == null:
			print("НЕ НАЙДЕН: ", j[0])
			continue
		var icon := _crop_square(img)
		icon.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var err := icon.save_png(OUT_DIR + "/" + j[1])
		print("OK " if err == OK else "ОШИБКА ", j[1])
	quit(0)


# обрезка по границам не-чёрного содержимого + поля, приведение к квадрату
func _crop_square(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in h:
		for x in w:
			var p := src.get_pixel(x, y)
			if maxf(p.r, maxf(p.g, p.b)) > 0.1:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return src.duplicate()  # картинка пустая — вернуть как есть
	var margin := int(maxf(hi.x - lo.x, hi.y - lo.y) * 0.04) + 2
	lo = Vector2i(maxi(lo.x - margin, 0), maxi(lo.y - margin, 0))
	hi = Vector2i(mini(hi.x + margin, w - 1), mini(hi.y + margin, h - 1))
	var side := maxi(hi.x - lo.x, hi.y - lo.y)  # квадрат по большей стороне
	var c := (lo + hi) / 2
	lo = Vector2i(maxi(c.x - side / 2, 0), maxi(c.y - side / 2, 0))
	var rect := Rect2i(lo, Vector2i(side, side))
	var out := src.get_region(rect)
	return out
