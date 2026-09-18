extends Node2D
## 护法妖将的实机取帧：法罡完整 / 法罡过半 / 破罡虚弱 三种状态各一帧
## 仅用于人工核对画面，核对完连同本目录一起删掉。

const OUT_DIR := "D:/demo"


func _ready() -> void:
	Game.picked_robes = [Game.RED, Game.WHITE]
	Game.difficulty = Game.NORMAL
	var lv := Level.new()
	add_child(lv)
	lv._running = false          # 冻住妖潮流程，画面里只留妖将
	await _wait(0.3)

	lv._spawn_elite(1.15)
	var e := _find(lv)
	if e != null:
		e._home_x = 700.0
		e._base_y = 330.0
		e.position = Vector2(700.0, 330.0)
		e._entered = true         # 跳过入场，直接站到取景位

	await _wait(1.6)             # 等它开出第一轮弹幕，顺便让开场横幅散掉
	_shoot("elite_a")            # 法罡完整

	if e != null:
		e.ward = int(float(e.ward_max) * 0.45)
	await _wait(0.5)
	_shoot("elite_b")            # 法罡过半（环变淡、血条见底）

	if e != null:
		e.ward = 0
		e.broken = 4.0
		e.layers = 0
		e.hp = int(float(e.max_hp) * 0.55)
	await _wait(0.5)
	_shoot("elite_c")            # 破罡虚弱（裂环 + 本体掉血）

	get_tree().quit(0)


func _find(n: Node) -> Elite:
	for ch in n.get_children():
		if ch is Elite:
			return ch as Elite
	return null


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shoot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/_frame_%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("[CAPTURE] %s -> %s err=%d size=%dx%d" % [
		tag, path, err, img.get_width(), img.get_height()])
