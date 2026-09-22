extends Node2D
## 五关改造实机截帧（真窗口运行，**不可 --headless**）：
##   帧 1  五艘旗舰横排 —— 核对「每个关卡的 Boss 都不同」
##   帧 2  七种独有怪 + 通用星盗 —— 核对七种怪各自的器官外形
##   帧 3  关卡选择界面 —— 核对五张卡与锁态
## 产物落在 D:/demo/_five_{bosses,monsters,stage}.png

const OUT := "D:/demo/"

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	await _bosses()
	_clear()
	await _monsters()
	_clear()
	await _stage_select()
	get_tree().quit()


func _clear() -> void:
	for ch in get_children():
		ch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _bg() -> void:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.05, 0.09)
	r.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.name = "BG"
	add_child(r)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE_SAVED ", path)


## 帧 1：五艘旗舰。L4 走 Boss4 子类（子核心），其余走基类。
func _bosses() -> void:
	_bg()
	var xs := [150.0, 400.0, 650.0, 900.0, 1150.0]
	var ys := [230.0, 430.0]
	# 各关摆出标志器官最完整的相位：L1 双环 / L2 全展翼 / L3 八炮塔 / L4 六触须 / L5 三残影
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
		b._base_y = ys[i % 2]
		add_child(b)
		bs.append(b)
		# 直接就位：enter 状态从场外驶入（x=1500 起，260px/s），L1 要 5.2s 才能到
		# x=150 —— 只等 3.5s 会拍到空位。
		b.position = Vector2(xs[i], ys[i % 2])
	# 入战那一帧 _next_skill() 会重置 _cast / _tick，停火必须在其后再设，
	# 否则五个 Boss 同时开火，弹幕会把本体糊住
	await get_tree().process_frame
	await get_tree().process_frame
	for k in bs.size():
		var bb: Boss = bs[k]
		if is_instance_valid(bb):
			bb._cast = 99.0
			bb._tick = 99.0
			bb._ward_t = 0.5     # 让 L1 / L5 的护罩弧（8 段虚线）在截帧前展开
		var lb := Label.new()
		lb.text = "%d  %s" % [k + 1, StageCfg.boss_full_name(k + 1)]
		lb.position = Vector2(xs[k] - 90.0, ys[k % 2] + 95.0)
		lb.size = Vector2(180.0, 30.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lb)
	# 等旗舰从场外走进各自的 home 位
	await get_tree().create_timer(3.5).timeout
	await _snap(OUT + "_five_bosses.png")


## 帧 2：七种独有怪（kind 1..7）+ 一只通用星盗（kind 0）做对照。
func _monsters() -> void:
	_bg()
	var names := ["通用", "拆解者", "变节者", "列阵者",
		"敷设者", "虹吸者", "殉爆者", "相位者"]
	for k in 8:
		var col := k % 2                      # 交替红 / 白，避免整排同色看不出器官
		var x := 120.0 + 145.0 * float(k)
		var y := 220.0 if k < 4 else 460.0
		var e := Spawner.enemy(self, k, col, "straight", y, 1.0, 1)
		if e == null:
			continue
		e.position = Vector2(x, y)
		e.speed = 0.0
		var lb := Label.new()
		lb.text = names[k]
		lb.position = Vector2(x - 70.0, y + 60.0)
		lb.size = Vector2(140.0, 26.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lb)
	await get_tree().create_timer(1.2).timeout
	await _snap(OUT + "_five_monsters.png")


## 帧 3：关卡选择界面（五张卡，含未解锁的锁态）。
func _stage_select() -> void:
	Game.unlocked = 3                         # 只开前三关，核对后两关的锁态表现
	var sel := StageSelect.new()
	add_child(sel)
	await get_tree().create_timer(1.2).timeout
	await _snap(OUT + "_five_stage.png")
