extends Node2D
## 实机取帧：建关卡 -> 等若干秒 -> 把视口存成 PNG -> 退出
## 仅用于人工核对画面，不属于游戏逻辑，核对完连同 _capture 目录一起删掉。

const OUT_DIR := "D:/demo"


func _ready() -> void:
	Game.picked_robes = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	Engine.time_scale = 1.0

	await _wait(1.5)
	_shoot("a")

	await _wait(4.0)
	_shoot("b")

	await _wait(4.0)
	_shoot("c")

	get_tree().quit(0)


## 按真实游戏时间等待（不数帧：headless 帧率抖动极大）
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
