extends Node
## 一次性截帧工具（真窗口运行）：HelpScreen 左列「战甲」节加了电浆剑甲两行
## （充能 +20 / 满 100 贯穿激光），复核左列末行与底部提示不叠印。

func _ready() -> void:
	var help := HelpScreen.new()
	add_child(help)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_lance_help.png")
	print("CAPTURE_SAVED help_lance")
	get_tree().quit()
