extends Node2D
## 驻留阵地波实机截帧（真窗口运行，**不可 --headless** —— dummy 渲染驱动拿不到
## 视口纹理，会报 `Parameter "t" is null`）：
##   帧 1  推进波（L2 第 1 波）—— 敌从右侧屏外排队飞入，背景 46 px/s
##   帧 2  驻留波（L2 第 3 波）—— 敌在屏内跃迁落地，背景 8 px/s
## 两帧并排看，核对「空间形式」的对比是否读得出来。
## 产物落在 D:/demo/_hold_{push,warp}.png

const OUT := "D:/demo/"

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	await _wave_shot(1, "_hold_push.png", "推进波 · 第 1 波（背景 46 px/s · 右侧屏外飞入）")
	_clear()
	await _wave_shot(3, "_hold_warp.png", "驻留波 · 第 3 波（背景 8 px/s · 屏内跃迁入场）")
	get_tree().quit()


func _clear() -> void:
	for ch in get_children():
		ch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE_SAVED ", path)


## 跑指定波次并在中途截帧。
## `Level._wave()` 是协程 —— **不 await** 调用即可让它在后台自己按 gap 出怪，
## 我们同时等墙钟时间，到点拍照。
func _wave_shot(n: int, path: String, caption: String) -> void:
	Game.current_stage = 2
	var lv := Level.new()
	lv.stage = 2                 # ★ add_child 之前注入
	add_child(lv)
	lv._running = false          # 掐断 _ready 里那条自动 _run 链
	await get_tree().create_timer(1.2).timeout
	lv._running = true
	lv._wave(n, StageCfg.wave_hp_scale(2, n), false)
	await get_tree().create_timer(2.6).timeout

	# 角标：写清这一帧是哪种形态、背景滚速多少
	var lb := Label.new()
	lb.text = "%s\n实测滚速 %.0f px/s" % [caption, lv.bg.scroll_speed]
	lb.position = Vector2(40.0, 40.0)
	lb.size = Vector2(900.0, 70.0)
	add_child(lb)
	await get_tree().process_frame
	await _snap(OUT + path)
