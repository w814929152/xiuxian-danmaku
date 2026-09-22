extends Node
## 一次性截帧工具（验证门 3，真窗口运行、不可 --headless）：
## 真跑关卡约 4 秒（第一波星袭已进场交火）后取一帧存 PNG。

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	add_child(Level.new())
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_level.png")
	print("CAPTURE_SAVED level")
	get_tree().quit()
