extends Node
## 一次性截帧工具（真窗口运行）：HelpScreen 右列排版复核用。
## 背景：右列「漂浮道具」末行曾与底部提示「ESC / Enter 返回开始界面」叠印，
## 修完行距后用本场景取帧确认不再重叠。

func _ready() -> void:
	var help := HelpScreen.new()
	add_child(help)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_shield2_help.png")
	print("CAPTURE_SAVED help_shield2")
	get_tree().quit()
