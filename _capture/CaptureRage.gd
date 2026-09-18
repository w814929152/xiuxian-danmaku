extends Node2D
## 老祖狂暴的实机取帧：直接把老祖血量压到三成以下触发狂暴，连拍四帧
## （第一帧抓强闪，后面几帧里必有一帧落在「心跳」尖峰上）
## 仅用于人工核对画面，核对完连同本目录一起删掉。

const OUT_DIR := "D:/demo"


func _ready() -> void:
	Game.picked_robes = [Game.RED, Game.WHITE]
	Game.difficulty = Game.NORMAL
	var lv := Level.new()
	add_child(lv)
	lv._running = false          # 冻住妖潮流程，直接进 Boss 战
	await _wait(0.3)
	lv._boss_fight()
	if lv.player != null:
		lv.player.invinc = 999.0    # 别让它被打死 —— 死了老祖会收手，画面就不全了

	await _wait(2.6)             # 等老祖入场（约 2 秒）站定
	var b := lv.boss
	if b == null or not is_instance_valid(b):
		print("[CAPTURE] boss 生成失败")
		get_tree().quit(1)
		return
	b.hp = int(float(b.max_hp) * 0.22)
	await _wait(0.30)
	_shoot("rage_a")             # 强闪瞬间

	# 心跳周期 1.8s / 尖峰 0.2s：四帧跨 2.7s，必有一帧撞上尖峰
	await _wait(0.9)
	_shoot("rage_b")
	await _wait(0.9)
	_shoot("rage_c")
	await _wait(0.9)
	_shoot("rage_d")

	get_tree().quit(0)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shoot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/_frame_%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("[CAPTURE] %s -> %s err=%d" % [tag, path, err])
