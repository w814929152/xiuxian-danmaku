extends Node2D
## UI 取帧：择道袍界面 + 道袍库各截一帧 -> 人工核对 RobeArt 新画法
## 不属于游戏逻辑，核对完连同 _capture 目录一起删。

const OUT_DIR := "D:/demo"


func _ready() -> void:
	# 择道袍界面：Main.show_select 的组装方式（直接 new，无前置状态）。
	# 预置两件已择，让截图带上选中描边 / 壹贰徽记的完整卡面状态
	var sel := RobeSelect.new()
	sel.picked = [Game.RED, Game.WHITE]
	add_child(sel)
	await _wait(1.2)
	_shoot("_ui_select")
	sel.queue_free()
	await get_tree().process_frame

	# 道袍库：Main.show_gallery 的组装方式；「已择」标记读 Game.picked_robes
	Game.picked_robes = [Game.RED, Game.WHITE]
	var gal := RobeGallery.new()
	add_child(gal)
	await _wait(1.2)
	_shoot("_ui_gallery")

	get_tree().quit(0)


## 按真实游戏时间等待（不数帧：帧率抖动会让 bob / 脉冲相位不可控）
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _shoot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("[CAPTURE] %s -> %s err=%d size=%dx%d" % [
		tag, path, err, img.get_width(), img.get_height()])
