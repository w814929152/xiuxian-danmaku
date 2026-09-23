extends Node2D
## L4 三角化错误定位（一次性诊断，可删）：Boss 隐藏（不走引擎 `_draw()`），但**逐帧推进**
##   让子核心真的移动，再手工调 BossArt —— 覆盖「触须绷紧指向子核心」的全部角度组合。

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	var b := Boss.new()
	b.stage = 4
	b.phase = 3
	var pa: Array[int] = [Game.RED, Game.WHITE]
	b.player_armors = pa
	b.world = self
	b._home_x = 600.0
	b._base_y = 360.0
	b.visible = true
	add_child(b)
	await get_tree().process_frame
	print("[L4DIAG] === live_start")
	for _k in 6:
		await get_tree().process_frame
	print("[L4DIAG] === live_end")
	get_tree().quit()
