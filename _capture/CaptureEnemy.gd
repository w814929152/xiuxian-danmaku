extends Node2D
## 敌我识别 / 四色区分的实机取帧：四色小妖各一只 + 一只妖将，摆开后截一帧
## 仅用于人工核对画面，核对完连同本目录一起删掉。
## 必须用真窗口跑（不能 --headless）：dummy 驱动拿不到视口纹理。

const OUT_DIR := "D:/demo"


func _ready() -> void:
	# 四色小妖一排（朝左 —— 与朝右的玩家相对，是敌我识别的视觉基准）
	var xs := [340.0, 540.0, 740.0, 940.0]
	for i in 4:
		var e := Enemy.new()
		e.world = self
		add_child(e)
		e.setup(i, "straight", 200.0, 1.0)
		e.position = Vector2(xs[i], 200.0)
		e.speed = 0.0          # 冻住不跑位
		e._fire = 999.0        # 摆拍不开火，画面只留本体

	# 妖将：摆在小妖下方（入场即会转入巡游，小幅摆动不影响核对）
	var el := Elite.new()
	el.world = self
	add_child(el)
	el.player_robes = [Game.RED, Game.WHITE]
	el.setup(1.0, 500.0)
	el._home_x = 640.0
	el._base_y = 500.0
	el.position = Vector2(640.0, 500.0)
	el._fire = 999.0

	await _wait(0.8)           # 等纹理就位 / 首帧渲染
	_shoot("enemy_check")
	get_tree().quit(0)


## 按真实游戏时间等待（不数帧：帧率抖动会让取帧时机不稳）
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shoot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/_%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("[CAPTURE] %s -> %s err=%d size=%dx%d" % [
		tag, path, err, img.get_width(), img.get_height()])
