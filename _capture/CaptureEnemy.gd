extends Node2D
## 一次性截帧工具（验证门 3，真窗口运行）：
## 四色星盗 + 一只战将（带力场）排布入画，取一帧存 D:/demo/_rollback_check.png。
## 用于核对「异形星盗不是人」且四色可辨。

func _ready() -> void:
	# 深色底（贴近关卡背景的暗色调，检验色彩可读性）
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.10)
	bg.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 四色星盗：pattern=straight + speed=0 定格；world 留空 -> 不会出弹
	for i in 4:
		var e := Enemy.new()
		e.setup(i, "straight", 0.0)
		e.speed = 0.0
		e.position = Vector2(320.0 + 212.0 * float(i), 215.0)
		add_child(e)

	# 战将：力场色强制电浆，置于下排中央（带力场弧 + 双血条 + 身份文字）
	var el := Elite.new()
	el.player_armors = [Game.RED, Game.WHITE]
	el.setup(1.0, 480.0)
	el.color = Game.RED
	el._home_x = 640.0
	el._base_y = 480.0
	el.position = Vector2(640.0, 480.0)
	add_child(el)

	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_check.png")
	print("CAPTURE_SAVED enemy_check")

	# 第二帧：四色战将（各带力场），核对战将四色同剪影 + 顶冠 / 双层壳
	for ch in get_children():
		if not (ch is ColorRect):
			ch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 4:
		var ek := Elite.new()
		ek.player_armors = [Game.RED, Game.WHITE]
		ek.setup(1.0, 215.0)
		ek.color = i
		ek._home_x = 320.0 + 212.0 * float(i)
		ek._base_y = 215.0
		ek.position = Vector2(ek._home_x, 215.0)
		add_child(ek)
	# 下排补一只破力场状态的战将（裂环态核对）
	var eb := Elite.new()
	eb.player_armors = [Game.RED, Game.WHITE]
	eb.setup(1.0, 480.0)
	eb.color = Game.BLUE
	eb._home_x = 640.0
	eb._base_y = 480.0
	eb.position = Vector2(640.0, 480.0)
	eb.ward = 0
	add_child(eb)

	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_elite_check.png")
	print("CAPTURE_SAVED elite_check")
	get_tree().quit()
