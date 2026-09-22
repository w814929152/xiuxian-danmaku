extends Node2D
## 一次性截帧工具（美术验证）：四色弹幕并排各 5 颗，验证白模 modulate 染色。

func _ready() -> void:
	var colors: Array[int] = [Game.RED, Game.BLUE, Game.WHITE, Game.YELLOW]
	for i in colors.size():
		for j in 5:
			Danmaku.spawn(self, colors[i],
				Vector2(140.0 + j * 64.0, 110.0 + i * 90.0),
				Vector2.ZERO, 0, 9.0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_danmaku_4color.png")
	print("CAPTURE_SAVED danmaku_4color")
	get_tree().quit()
