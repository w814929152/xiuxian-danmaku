extends Node2D
## 一次性截帧工具（02 §2.2「敌我识别」两个最坏场景判据的**实地验证**，真窗口运行，
##   **不可 --headless**）：
##   玩家战甲（1×，带 CANOPY 舱盖）置屏幕左，五艘机甲化 Boss 缩略排右 ——
##   核对六条区分维度里最硬的四条：
##     ① 体量（玩家本体 40×22px vs Boss 直径 112~168px，面积 ≥8×）
##     ② 朝向（玩家 **+X 是头** / Boss **−X 是头**，方向相反）
##     ③ 明暗（玩家暗身亮边 / Boss 亮身暗边）
##     ④ 传感器（玩家 1 枚前向倾斜玻璃 + 白描边 / Boss ≥3 枚成阵、DARK 槽、无描边）
##   产物：D:/demo/_boss_iff.png

const OUT := "D:/demo/"

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	await _iff()
	await _exposed()
	get_tree().quit()


func _iff() -> void:
	_bg()
	# 「我」侧基准：玩家机甲 **1×**（不放大，保持实测 40×22px 本体口径）
	var p := Player.new()
	p.position = Vector2(170.0, 360.0)
	add_child(p)
	_lb("玩家战甲 1×（+X 是头）", Vector2(80.0, 430.0))

	# 「敌」侧：五艘 Boss。02 §6.3 摆标志器官最完整相位
	#   L1 双环 / L2 全展翼 / L3 八炮塔 / L4 六触须 / L5 三残影
	#   ⚠ 统一 ×0.55 缩排：L5 残影外缘 ~392px，1× 排不下五艘（帧宽 1280）
	var xs := [540.0, 800.0, 1060.0, 680.0, 1020.0]
	var ys := [210.0, 210.0, 210.0, 520.0, 520.0]
	var show := [2, 3, 3, 3, 4]
	var bs: Array[Boss] = []
	for i in 5:
		var s := i + 1
		var b: Boss
		if s == 4:
			b = Boss4.new()
		else:
			b = Boss.new()
		b.stage = s
		b.phase = show[i]          # 须在 add_child 前设：Boss4 按相位分裂子核心
		b.player_armors = [Game.RED, Game.WHITE]
		b.world = self
		b._home_x = xs[i]
		b._base_y = ys[i]
		add_child(b)
		b.position = Vector2(xs[i], ys[i])
		b.scale = Vector2(0.55, 0.55)
		bs.append(b)
		_lb("L%d %s ×0.55" % [s, StageCfg.boss_name(s)],
			Vector2(xs[i] - 90.0, ys[i] + 90.0))
	# 停火 + 让 L1 / L5 的护罩弧（8 段虚线）在截帧前展开
	await get_tree().process_frame
	await get_tree().process_frame
	for k in bs.size():
		var bb: Boss = bs[k]
		if is_instance_valid(bb):
			bb._cast = 99.0
			bb._tick = 99.0
			bb._ward_t = 0.5
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "_boss_iff.png")
	print("CAPTURE_SAVED ", OUT + "_boss_iff.png")


## 帧 2：L4 **暴露期** 三层联动同帧核对（02 §7.2 最高风险点）——
##   闸门**关闭**（闸齿内收 + 腔内 DARK 实心）+ 能量索**断裂**（残端无 GLOW）
##   + 护罩弧**展开**。三者必须同一帧同相位，否则传达的是互斥玩法信息。
func _exposed() -> void:
	for ch in get_children():
		ch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_bg()
	var b := Boss4.new()
	b.stage = 4
	b.phase = 3
	b.player_armors = [Game.RED, Game.WHITE]
	b.world = self
	b._home_x = 640.0
	b._base_y = 360.0
	add_child(b)
	b.position = Vector2(640.0, 360.0)
	# 直接置暴露态：`is_exposed()` 是三个绘制层的唯一真值源
	b._exposed_win = true
	b.ward = Game.RED
	b._ward_t = 99.0
	b._cast = 99.0
	b._tick = 99.0
	_lb("L4 暴露期：闸门关 · 能量索断 · 护罩开", Vector2(400.0, 560.0))
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "_boss_l4_exposed.png")
	print("CAPTURE_SAVED ", OUT + "_boss_l4_exposed.png")


func _bg() -> void:
	var r := ColorRect.new()
	r.color = Color(0.05, 0.05, 0.10)
	r.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.name = "BG"
	add_child(r)


func _lb(t: String, pos: Vector2) -> void:
	var lb := Label.new()
	lb.text = t
	lb.position = pos
	lb.size = Vector2(190.0, 28.0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(lb)
