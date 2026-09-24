extends SceneTree

## Prancha de quadros de uma cena gravada pela sessão gráfica: 12 quadros
## igualmente espaçados em grade 4x3, 320 px de largura cada.
## Uso: godot --headless --path . --script tests/visual_contact_sheet.gd -- DIR CENA SAIDA.png

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("uso: DIR CENA SAIDA.png")
		quit(2)
		return
	var dir := DirAccess.open(args[0])
	if dir == null:
		quit(1)
		return
	var frames: Array = []
	for file in dir.get_files():
		if file.begins_with(args[1] + "_") and file.ends_with(".jpg") and file.trim_prefix(args[1] + "_").trim_suffix(".jpg").is_valid_int():
			frames.append(file)
	frames.sort()
	if frames.is_empty():
		quit(1)
		return
	var picks: Array = []
	for i in 12:
		picks.append(frames[mini(frames.size() - 1, int(float(i) * frames.size() / 12.0))])
	var tile_w := 320
	var first := Image.load_from_file(args[0].path_join(picks[0]))
	var tile_h := int(float(first.get_height()) * tile_w / first.get_width())
	var sheet := Image.create(tile_w * 4, tile_h * 3, false, Image.FORMAT_RGB8)
	for i in picks.size():
		var image := Image.load_from_file(args[0].path_join(picks[i]))
		image.convert(Image.FORMAT_RGB8)
		image.resize(tile_w, tile_h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(image, Rect2i(0, 0, tile_w, tile_h), Vector2i((i % 4) * tile_w, (i / 4) * tile_h))
	sheet.save_png(args[2])
	print("CONTACT_SHEET scene=%s frames=%d out=%s" % [args[1], frames.size(), args[2]])
	quit(0)
