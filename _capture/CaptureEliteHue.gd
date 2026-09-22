extends Node2D
## 战将多色弹幕实机截帧（真窗口运行，**不可 --headless** —— dummy 渲染驱动拿不到
## 视口纹理，会报 `Parameter "t" is null`）：
##   L1（单色）/ L3（双色）/ L5（四色）三只战将各占一行，等它们开火后截帧，
##   核对弹幕颜色数是否随关卡递增、力场色是否仍占多数。
## 色序明细打到 stdout（截图上会被弹幕糊住，读不准）。
## 产物落在 D:/demo/_elite_hues.png

const OUT := "D:/demo/"

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	var armors: Array[int] = [Game.RED, Game.WHITE]
	# 数组必须显式标注元素类型：否则 `rows[i]` 推断不出类型，报
	# "Cannot infer the type of st variable because the value doesn't have a set type"
	var rows: Array[int] = [1, 3, 5]
	var ys: Array[float] = [170.0, 360.0, 550.0]
	for i in rows.size():
		var st := rows[i]
		var e := Elite.new()
		e.stage = st                   # ★ add_child 之前注入（stage 决定弹幕色数）
		e.world = self
		add_child(e)
		e.player_armors = armors
		e.setup(1.0, ys[i])
		e.position = Vector2(1040.0, ys[i])
		e._home_x = 1040.0
		e._base_y = ys[i]
		e._entered = true              # 跳过入场，直接开火
		e._fire = 0.25 * float(i)      # 错开出手，免得三只同时喷、糊成一片
		# 力场保持满层：虚弱期只剩 3 发，看不出色数
		print("CAPTURE L%d | 色数 %d | 力场色 %s | 色序 %s"
			% [st, StageCfg.elite_hue_n(st), Game.COLOR_CN[e.color], _cn(e._hues)])
		var lb := Label.new()
		lb.text = "L%d · %d 色" % [st, StageCfg.elite_hue_n(st)]
		lb.position = Vector2(30.0, ys[i] - 14.0)
		lb.size = Vector2(200.0, 28.0)
		add_child(lb)
	await get_tree().create_timer(2.4).timeout
	await _snap(OUT + "_elite_hues.png")
	get_tree().quit()


func _cn(hues: Array[int]) -> String:
	var s := ""
	for c in hues:
		if not s.is_empty():
			s += " + "
		s += Game.COLOR_CN[c]
	return s


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE_SAVED ", path)
