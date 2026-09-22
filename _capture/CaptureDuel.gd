extends Node2D
## 一次性截帧工具（RT-09 扫尾验证门，真窗口运行）：
## 帧1：玩家机甲 vs 白色（光子）战将同框，间距 300px——
##      最易混淆配色组合下核对 CANOPY 座舱敌我信道 + 双排光刃炮口 vs 战将炮垒可读性。
## 帧2：HelpScreen 全页——核对末行基线不越界（无重叠/裁切）。
## 产物：D:/demo/_rollback_duel.png 、 D:/demo/_rollback_help.png

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.10)
	bg.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 玩家：默认电浆剑甲（RED/WHITE 双甲），world=null 不会出弹
	var p := Player.new()
	p.position = Vector2(340.0, 480.0)
	add_child(p)

	# 白色战将：距玩家 300px（200~400px 常规交战距离），world 留空不出弹
	var el := Elite.new()
	el.player_armors = [Game.RED, Game.WHITE]
	el.setup(1.0, 480.0)
	el.color = Game.WHITE
	el._home_x = 640.0
	el._base_y = 480.0
	el.position = Vector2(640.0, 480.0)
	add_child(el)

	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_duel.png")
	print("CAPTURE_SAVED duel")
	p.queue_free()
	el.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# 帧2：HelpScreen 全页
	var help := HelpScreen.new()
	add_child(help)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_help.png")
	print("CAPTURE_SAVED help")
	get_tree().quit()
