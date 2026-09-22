extends Node
## 一次性截帧工具（验证门 3，真窗口运行）：择甲界面 + 战甲库各取一帧。

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	var sel := ArmorSelect.new()
	add_child(sel)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_ui_select.png")
	print("CAPTURE_SAVED ui_select")
	sel.queue_free()
	await get_tree().process_frame

	var gal := ArmorGallery.new()
	add_child(gal)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("D:/demo/_rollback_ui_gallery.png")
	print("CAPTURE_SAVED ui_gallery")
	get_tree().quit()
