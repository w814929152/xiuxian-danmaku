extends Node2D
## 自动化冒烟测试（headless 运行用，验证完毕即删除）
## 覆盖：三色免疫 / 护盾 / 十息回气 / 移速加成 / 关卡生成 / Boss 三阶段 / 法罩 / UI 全流程
## 追加：戊土（黄）免疫 / 符光过热（+20 每秒 · 100 封顶 · 停手 0.5 秒后 -30 每秒）/ 戊土弹 -30 / 符光持续伤害

var _fails: Array[String] = []
var _finished := false
## 妖将 killed 信号的接收记录（信号回调没法返回值，只能落到这里再断言）
var _elite_killed := false
var _elite_score := 0


func _ready() -> void:
	await _frames(2)
	await _test_ui_flow()
	await _test_player()
	await _test_yellow()
	await _test_pickup()
	await _test_elite()
	await _test_pool()
	await _test_level()
	await _test_boss()
	await _test_difficulty()
	await _test_score_persist()
	await _test_death()
	await _test_win()      # 击杀 Boss 会切换场景，必须放在最后
	_finish_all()


func _finish_all() -> void:
	print("[SELFTEST] fails = %d" % _fails.size())
	for s in _fails:
		print("[FAIL] " + s)
	print("[SELFTEST] DONE")
	Pool.clear()   # 对象池里的孤儿节点要在 quit 前回收，否则算作 RID 泄漏
	await _frames(1)
	get_tree().quit(1 if _fails.size() > 0 else 0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ck(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
	print("[ck] %s  %s" % ["PASS" if cond else "FAIL", msg])


## 走真实输入通道（parse_input_event -> _unhandled_input）
func _press(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = a
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


# ------------------------------------------------------------ UI 全流程
func _test_ui_flow() -> void:
	print("------ ui flow ------")
	var m := Main.new()
	add_child(m)
	await _frames(3)
	_ck(m.current is TitleScreen, "启动 -> 开始界面")

	# 菜单第二项：道袍库
	await _press("mv_down")
	await _press("confirm")
	_ck(m.current is RobeGallery, "菜单 ↓ + 确认 -> 道袍库")
	await _press("mv_right")
	await _press("pick_1")
	await _press("cancel")
	_ck(m.current is TitleScreen, "道袍库 ESC -> 回到开始界面")

	# 数字键 3 直达：游戏说明
	await _press("pick_2")
	_ck(m.current is HelpScreen, "数字键 3 -> 游戏说明")
	await _press("confirm")
	_ck(m.current is TitleScreen, "说明界面确认 -> 回到开始界面")

	# 菜单第一项：开始游戏 -> 先择难度
	await _press("confirm")
	_ck(m.current is DifficultySelect, "确认 -> 择难度界面")
	await _press("pick_1")                      # 数字键 2 = 普通
	_ck(Game.difficulty == Game.NORMAL, "数字键 2 -> 记下【普通】难度")
	_ck(m.current is RobeSelect, "择难度确认 -> 择道袍界面")

	await _press("pick_0")
	await _press("pick_2")
	await _press("confirm")
	await _frames(4)
	_ck(m.current is Level, "选满两件道袍 -> 进入关卡")
	_ck(Game.picked_robes == [Game.RED, Game.WHITE], "记录所选两色 = 赤炎 + 太清")

	var lv: Level = m.current as Level
	if lv != null:
		_ck(lv.finished.is_connected(m.show_result), "Main 已连接 Level.finished")
		_ck(lv.restart_requested.is_connected(m.restart_level),
			"Main 已连接 Level.restart_requested")
		await _press("pause")
		_ck(get_tree().paused, "P 键暂停生效")
		await _press("pause")
		_ck(not get_tree().paused, "P 键恢复生效")

	m.show_result(true)
	await _frames(3)
	_ck(m.current is ResultScreen, "结算界面可显示")
	m.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 玩家
func _test_player() -> void:
	print("------ player ------")
	Game.difficulty = Game.NORMAL
	var p := Player.new()
	p.world = self
	add_child(p)
	p.robes = [Game.WHITE, Game.RED]
	p.robe_idx = 0
	await _frames(2)
	_ck(p.color == Game.WHITE, "初始皮肤 = 太清(白)")

	var used := p.take_hit(Game.WHITE, 10)
	_ck(used == false, "白皮肤免疫白弹（弹幕穿过）")
	_ck(p.hp == Player.MAX_HP, "免疫后血量不变")

	p._invuln = 0.0
	p.take_hit(Game.RED, 6)
	_ck(p.shield == 4, "白皮肤护盾吸收 6 点 -> 剩 4")
	_ck(p.hp == Player.MAX_HP, "护盾吸收期间不掉血")

	p._invuln = 0.0
	p.take_hit(Game.BLUE, 8)
	_ck(p.shield == 0, "护盾耗尽")
	_ck(p.hp == Player.MAX_HP - 4, "溢出伤害 4 点扣血")

	p._invuln = 0.0
	p._no_hit = 10.5
	await _frames(3)
	_ck(p.shield == Player.SHIELD_MAX, "十息（10 秒）无伤 -> 护盾回满")

	p.do_swap()
	_ck(p.color == Game.RED, "空格切换 -> 赤炎(红)")
	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == false, "红皮肤免疫红弹")
	p._invuln = 0.0
	_ck(p.take_hit(Game.BLUE, 10) == true, "红皮肤吃蓝弹并扣血")

	# 移速：红 vs 蓝
	p.robes = [Game.RED, Game.BLUE]
	p.robe_idx = 0
	p.hp = Player.MAX_HP
	p.position = Vector2(300.0, 360.0)
	await _frames(2)
	Input.action_press("mv_right")
	var x0 := p.position.x
	await _frames(12)
	var d_red := p.position.x - x0
	p.do_swap()
	_ck(p.color == Game.BLUE, "切换 -> 玄冰(蓝)")
	var x1 := p.position.x
	await _frames(12)
	var d_blue := p.position.x - x1
	Input.action_release("mv_right")
	if d_red > 0.001:
		var ratio := d_blue / d_red
		_ck(ratio > 1.25, "蓝皮肤移速 +50%（实测 " + String.num(ratio, 2) + " 倍）")
	else:
		_ck(false, "移速测试无效：红皮肤位移为 0")

	p.queue_free()
	await _frames(2)


# ------------------------------------------------------------ 戊土（黄）
func _test_yellow() -> void:
	print("------ yellow / heat ------")
	Game.difficulty = Game.NORMAL
	var p := Player.new()
	p.world = self
	add_child(p)
	p.robes = [Game.YELLOW, Game.RED]
	p.robe_idx = 0
	await _frames(2)
	_ck(p.color == Game.YELLOW, "换上戊土符袍(黄)")

	p._invuln = 0.0
	_ck(p.take_hit(Game.YELLOW, 10) == false, "戊土符袍免疫戊土弹（弹幕穿过）")
	_ck(p.hp == Player.MAX_HP, "免疫戊土弹不掉血")

	# 过热：出光每秒 +20，封顶 100
	p.heat = 0.0
	p._firing = true
	p._update_heat(1.0)
	_ck(absf(p.heat - 20.0) < 0.01, "出光 1 秒 -> 过热值 +20")
	p._update_heat(4.5)
	_ck(absf(p.heat - Player.HEAT_MAX) < 0.01, "过热值封顶 100")
	_ck(not p.can_fire(), "过热满值 -> 无法出光")

	# 停火 0.5 秒后每秒 -30
	p._firing = false
	p._idle = 0.0
	p._update_heat(0.5)
	_ck(absf(p.heat - 85.0) < 0.01, "停火 0.5 秒后开始散热 -> 100 降至 85")
	_ck(not p.can_fire(), "未散到解锁阈值 -> 仍闭锁（防按住不放抖动）")
	p._update_heat(1.0)
	_ck(absf(p.heat - 55.0) < 0.01, "再散热 1 秒 -> 85 降至 55")
	_ck(p.can_fire(), "散到解锁阈值以下 -> 恢复出光")

	# 触及戊土弹 -> 立刻散去 30
	p.heat = 80.0
	p._invuln = 0.0
	p.take_hit(Game.YELLOW, 10)
	_ck(absf(p.heat - 50.0) < 0.01, "触及戊土弹 -> 过热值立刻 -30")
	p.queue_free()
	await _frames(2)

	# 戊土妖：会射出戊土符弹
	var ey := Enemy.new()
	ey.world = self
	add_child(ey)
	ey.setup(Game.YELLOW, "sine", 300.0, 1.0)
	ey._entered = true
	_ck(ey.max_hp == 30 and ey.fire_cd > 1.5, "戊土妖数值生效（血 30 / 射速偏慢）")
	ey._shoot()
	var ny := 0
	for ch in get_children():
		if ch is Danmaku and (ch as Danmaku).color == Game.YELLOW:
			ny += 1
	_ck(ny == 3, "戊土妖一次射出 3 枚戊土符弹")
	for ch in get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()
	ey.queue_free()
	await _frames(2)

	# 符光：持续结算伤害（不是弹丸，而是压在光柱上按 tick 掉血）
	var e := Enemy.new()
	e.world = self
	add_child(e)
	e.setup(Game.RED, "hover", 360.0, 1.0)
	e.position = Vector2(600.0, 360.0)
	await _frames(2)
	var bm := Beam.new()
	bm.world = self
	add_child(bm)
	bm.aim(0.0)
	bm.position = Vector2(650.0, 360.0)
	bm.turn_on()
	var hp0 := e.hp
	Engine.time_scale = 4.0
	await _frames(30)
	Engine.time_scale = 1.0
	var beamed := false
	if is_instance_valid(e):
		beamed = e.dead or e.hp < hp0
	else:
		beamed = true      # 已被 queue_free 说明确实被打死了
	_ck(beamed, "符光（激光）持续结算伤害")
	bm.turn_off()
	bm.queue_free()
	if is_instance_valid(e):
		e.queue_free()
	await _frames(2)


# ------------------------------------------------------------ 漂浮道具
## 一个只会互相碰撞的空白 Area2D，用来制造真实的 area_entered 回调
func _probe_area(p: Vector2) -> Area2D:
	var a := Area2D.new()
	add_child(a)
	var csx := CollisionShape2D.new()
	var shx := CircleShape2D.new()
	shx.radius = 20.0
	csx.shape = shx
	a.add_child(csx)
	a.collision_layer = 1
	a.collision_mask = 1
	a.position = p
	return a


func _test_pickup() -> void:
	print("------ pickup ------")
	# ---------- 道具本体 ----------
	var pk := Pickup.spawn(self, Pickup.T.HEAL, Vector2(400.0, 360.0))
	_ck(pk != null, "可生成漂浮道具")
	if pk == null:
		return
	# 入树是延后一帧的（见 Pickup.spawn 注释），_ready 里的碰撞设置要等它进树才生效
	await _frames(3)
	_ck(pk.collision_layer == 16, "道具在碰撞层 bit4（飞剑与敌弹都不会误触）")
	var px0 := pk.position.x
	await _frames(8)
	_ck(pk.position.x < px0, "道具向左漂浮")

	# 掉落常常发生在**物理回调里**（飞剑命中 -> 小妖死亡 -> 关卡掉落）。
	# 用一对真实重叠的 Area2D 把 Pickup.spawn 塞进 area_entered —— 那正是
	# "flushing queries" 阶段，能确定性复现
	# "Can't change this state while flushing queries"（否则只能靠 18% 概率撞上）。
	var pa := _probe_area(Vector2(300.0, 200.0))
	var pb := _probe_area(Vector2(300.0, 200.0))
	pa.area_entered.connect(func(_o: Area2D) -> void:
		Pickup.spawn(self, Pickup.T.HEAL, Vector2(300.0, 200.0)))
	await _frames(4)
	var from_phys := 0
	for ch0 in get_children():
		if ch0 is Pickup:
			from_phys += 1
	_ck(from_phys > 0, "物理回调里也能安全生成道具（入树已延后一帧）")
	pa.queue_free()
	pb.queue_free()

	# ---------- 四种效果 ----------
	var p := Player.new()
	p.world = self
	add_child(p)
	p.robes = [Game.WHITE, Game.RED]
	p.robe_idx = 0
	p.shield = 0        # 关掉罡气，扣血才可预期
	await _frames(2)

	# 回春丹
	p.hp = 50
	p.apply_pickup(Pickup.T.HEAL)
	_ck(p.hp == 70, "回春丹 -> 元神 +20")
	p.hp = 95
	p.apply_pickup(Pickup.T.HEAL)
	_ck(p.hp == Player.MAX_HP, "回春丹不会超出元神上限")

	# 剑影符
	_ck(p.rows() == 1, "太清罡袍基准单排弹道")
	p.apply_pickup(Pickup.T.MULTI)
	_ck(p.multi == 1 and p.rows() == 2, "剑影符 -> 弹道 +1")
	p.robe_idx = 1
	_ck(p.rows() == 3, "赤炎剑袍双排 + 剑影符 = 三排")
	p.robe_idx = 0

	# 增攻符
	_ck(p.sword_damage() == 10, "基准飞剑伤害 10")
	p.apply_pickup(Pickup.T.ATK)
	_ck(absf(p.atk_mul - 1.30) < 0.001, "增攻符 -> 攻击力 +30%")
	_ck(p.sword_damage() == 13, "飞剑伤害 10 -> 13")
	_ck(p.sword_size() > 1.0, "飞剑变大（外观与碰撞体同步）")
	_ck(p.beam_width() > 1.0, "符光变粗")
	_ck(absf(p.beam_dps() - 120.0 * 1.3) < 0.01, "符光每秒伤害同步提高到 156")

	# 层数封顶
	for _i in 8:
		p.apply_pickup(Pickup.T.MULTI)
		p.apply_pickup(Pickup.T.ATK)
	_ck(p.multi == Player.MULTI_MAX, "剑影符层数封顶 %d 层" % Player.MULTI_MAX)
	_ck(p.atk_up == Player.ATK_MAX, "增攻符层数封顶 %d 层" % Player.ATK_MAX)

	# 无量罩
	p.invinc = 0.0
	p.apply_pickup(Pickup.T.INVINC)
	_ck(absf(p.invinc - Player.INVINC_TIME) < 0.001, "无量罩 -> 无敌 6 秒")
	p.hp = 100
	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == false, "无量罩期间免伤（弹幕穿过）")
	_ck(p.hp == 100, "无量罩期间不掉血")
	p.invinc = 0.0
	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == true, "无量罩失效后恢复正常受击")
	_ck(p.hp == 90, "失效后正常扣血")

	# 戊土符袍：剑影符 -> 多一道符光，且**不额外增加过热值**
	p.robes = [Game.YELLOW, Game.RED]
	p.robe_idx = 0
	p.multi = 1
	await _frames(2)
	_ck(p.rows() == 2, "戊土符袍 + 剑影符 = 两道符光")
	p._beam_on()
	var on_n := 0
	for b in p._beams:
		if b.on:
			on_n += 1
	_ck(on_n == 2, "实际点亮两道符光")
	p._beam_off()
	var off_n := 0
	for b2 in p._beams:
		if b2.on:
			off_n += 1
	_ck(off_n == 0, "停手后符光全部熄灭")

	# 加排只加伤害，不加发热 —— 这是需求里明确点名的
	p.multi = 0
	p.heat = 0.0
	p._firing = true
	p._update_heat(1.0)
	var h1 := p.heat
	p.multi = 2
	p.heat = 0.0
	p._update_heat(1.0)
	var h2 := p.heat
	_ck(absf(h1 - 20.0) < 0.01, "单道出光 1 秒 -> 过热值 +20")
	_ck(absf(h1 - h2) < 0.01, "剑影符加排不额外增加过热值（%d -> %d）" % [int(h1), int(h2)])
	p._firing = false

	# ---------- 玩家碰到道具 ----------
	p.hp = 50
	p.position = pk.position
	for _i in 120:
		if p.hp != 50:
			break
		if is_instance_valid(pk):
			p.position = pk.position    # 道具在漂，玩家跟着它才能稳定压上
		await get_tree().process_frame
	_ck(p.hp == 70, "玩家碰到道具 -> 回复 20 点")
	_ck(not is_instance_valid(pk) or pk.is_queued_for_deletion(), "道具拾取后消失")
	p.queue_free()
	await _frames(2)

	# ---------- 掉落源 ----------
	Game.picked_robes = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	lv._running = false      # 别让波次真的跑起来，只测掉落
	await _frames(3)

	# 波次刷新：开局不预置，一次波次只补 WAVE_DROP 个（当前 1 个）
	var n0 := 0
	for ch in lv.get_children():
		if ch is Pickup:
			n0 += 1
	_ck(n0 == 0, "关卡开局不预置道具")
	lv._drop_wave()
	await _frames(3)
	var n1 := 0
	for c5 in lv.get_children():
		if c5 is Pickup:
			n1 += 1
	_ck(n1 - n0 == Level.WAVE_DROP,
		"每波结束刷新 %d 个道具（实测 %d 个）" % [Level.WAVE_DROP, n1 - n0])
	_ck(not lv.has_method("_heal"), "波次结束不再回血（_heal 已移除，元神只靠回春丹）")

	# 掉落是概率的：18% 连掉 60 次一次都不出的概率约 6e-6，够确定
	var hits := 0
	for _k in 60:
		var a0 := 0
		for c3 in lv.get_children():
			if c3 is Pickup:
				a0 += 1
		lv._on_enemy_killed(Vector2(600.0, 360.0), Game.RED, 100)
		await _frames(3)      # 掉落入树是延后一帧的
		var a1 := 0
		for c4 in lv.get_children():
			if c4 is Pickup:
				a1 += 1
		if a1 > a0:
			hits += 1
	_ck(hits > 0, "击杀小妖会掉落道具（60 次命中 %d 次）" % hits)
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 护法妖将（精英）
func _on_elite_probe(_pos: Vector2, _c: int, sc: int) -> void:
	_elite_killed = true
	_elite_score = sc


func _count_pickups(n: Node) -> int:
	var k := 0
	for ch in n.get_children():
		if ch is Pickup:
			k += 1
	return k


func _find_elite(n: Node) -> Elite:
	for ch in n.get_children():
		if ch is Elite:
			return ch as Elite
	return null


func _test_elite() -> void:
	print("------ elite ------")
	Game.picked_robes = [Game.RED, Game.WHITE]
	var e := Elite.new()
	e.world = self
	add_child(e)
	e.player_robes = [Game.RED, Game.WHITE]
	e.setup(1.0)
	await _frames(2)
	_ck(e.color == Game.RED or e.color == Game.WHITE,
		"法罡色只从玩家两件道袍中抽取（抽到 %s）" % Game.COLOR_CN[e.color])
	_ck(e.collision_layer == 4 and e.collision_mask == 2,
		"妖将与小妖同层（bit2，只吃 bit1 飞剑）")
	_ck(e.ward == e.ward_max and e.hp == e.max_hp, "出场即带满层法罡")
	_ck(e.max_hp > 400 and e.ward_max > 100,
		"血厚于小妖（本体 %d / 法罡 %d）" % [e.max_hp, e.ward_max])

	# ---------- 法罡分层：异色刮痧，且破罡前本体不掉血 ----------
	var off := (e.color + 1) % 4
	var hp0 := e.hp
	var w0 := e.ward
	e.hit(100, off)
	var d_off := w0 - e.ward
	_ck(e.hp == hp0, "法罡未破时本体不掉血")
	_ck(d_off == int(roundf(100.0 * Elite.WARD_RESIST)),
		"异色打法罡只剩 %d%%（100 -> %d）" % [int(Elite.WARD_RESIST * 100.0), d_off])
	# 用 20 点试同色：100 点同色打出来是 150，会一击打爆 150 的法罡 ——
	# 那测的就不是衰减比例而是「恰好破罡」了
	e.ward = w0
	e.hit(20, e.color)
	_ck(w0 - e.ward == 30, "同色打法罡全额 +50%%（20 -> %d）" % (w0 - e.ward))

	# ---------- 破罡 -> 虚弱 ----------
	e.ward = 10
	e.hit(50, e.color)
	_ck(e.ward == 0 and e.broken > 0.0, "法罡击破 -> 进入虚弱期")
	_ck(e.layers == Elite.WARD_LAYERS - 1, "破一层扣一次重铸机会（余 %d 次）" % e.layers)
	var h1 := e.hp
	e.hit(100, off)
	_ck(h1 - e.hp == 100, "虚弱期异色对本体全额（不再衰减）")
	var h2 := e.hp
	e.hit(100, e.color)
	_ck(h2 - e.hp == 150, "虚弱期同色仍有共振 +50%")

	# ---------- 重铸与永久破防 ----------
	e.broken = 0.001
	await _frames(4)
	_ck(e.ward == e.ward_max, "虚弱结束 -> 法罡重铸（余 %d 次）" % e.layers)
	_ck(e.broken <= 0.0, "重铸后虚弱计时归零")
	e.ward = 0
	e.layers = 0
	e.broken = 0.001
	await _frames(4)
	_ck(e.ward == 0 and e.broken <= 0.0, "重铸次数用尽 -> 永久破防")

	# ---------- 走真实飞剑链路：Sword 只认 Damageable ----------
	e.position = Vector2(600.0, 300.0)
	e._base_y = 300.0
	e._home_x = 600.0
	e._entered = true
	var w1 := e.ward
	var h3 := e.hp
	Sword.spawn(self, e.color, e.position, 10, Vector2(900.0, 0.0), 1.0)
	for _i in 8:
		if e.ward < w1 or e.hp < h3:
			break
		await get_tree().physics_frame
	_ck(e.ward < w1 or e.hp < h3,
		"飞剑可命中妖将（走 Damageable 判定，Sword 无需改动）")

	# ---------- 斩杀 ----------
	_elite_killed = false
	_elite_score = 0
	e.killed.connect(_on_elite_probe)
	e.hp = 40
	e.hit(60, e.color)
	_ck(_elite_killed, "斩杀妖将 -> 发出 killed 信号")
	_ck(_elite_score == Elite.SCORE, "斩杀奖励 %d 分" % Elite.SCORE)
	_ck(e.dead, "死亡标记已置位（清场判定据此放行）")
	await _frames(2)

	# ---------- 关卡接入 ----------
	var lv := Level.new()
	add_child(lv)
	lv._running = false      # 别让波次真的跑起来，只测生成与掉落
	await _frames(3)
	var n0 := _count_pickups(lv)
	lv._spawn_elite(1.15)
	await _frames(3)
	var el := _find_elite(lv)
	_ck(el != null, "关卡可生成护法妖将")
	if el != null:
		_ck(el.player_robes.size() == 2, "妖将拿到玩家道袍（法罡只从中抽取）")
		_ck(el.max_hp > Elite.BASE_HP, "血量按波次系数缩放（第 2 重 %d）" % el.max_hp)
		_ck(lv._elite_alive(), "清场判定认得妖将（在场即算未清空）")
		el.ward = 0
		el.hp = 1
		el.hit(50, el.color)
		await _frames(4)
		_ck(_count_pickups(lv) == n0 + 1, "斩杀妖将必掉一件道具")
		_ck(not lv._elite_alive(), "妖将阵亡后清场放行")
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 对象池 / 烘焙
func _test_pool() -> void:
	print("------ pool ------")
	var d1 := Danmaku.spawn(self, Game.RED, Vector2(100.0, 100.0),
		Vector2(-200.0, 0.0), 10, 9.0)
	_ck(d1 != null, "对象池可生成弹幕")
	if d1 == null:
		return
	var id1 := d1.get_instance_id()
	d1.dissolve()
	await _frames(3)
	var d2 := Danmaku.spawn(self, Game.BLUE, Vector2(300.0, 200.0),
		Vector2(-200.0, 0.0), 10, 9.0)
	_ck(d2 != null and d2.get_instance_id() == id1,
		"弹幕归还后被复用（同一实例，未重新 new）")
	_ck(d2 != null and d2.color == Game.BLUE and d2.life == 9.0 and d2.radius == 9.0,
		"复用时状态被完整重置（颜色 / 寿命 / 半径）")
	if d2 != null:
		d2.dissolve()
	await _frames(3)

	var bg := Background.new()
	add_child(bg)
	await _frames(2)
	_ck(bg.baked(), "背景山脊 / 星野已烘焙为周期纹理")
	bg.queue_free()
	await _frames(2)


# ------------------------------------------------------------ 关卡
func _test_level() -> void:
	print("------ level ------")
	Game.picked_robes = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	_ck(lv.player != null and is_instance_valid(lv.player), "关卡创建玩家")
	_ck(lv.hud != null, "关卡创建 HUD")
	_ck(lv.player.robes.size() == 2, "玩家携带两件道袍")

	Engine.time_scale = 4.0
	Input.action_press("shoot")
	Input.action_press("mv_up")
	await _frames(150)
	Input.action_release("mv_up")
	Input.action_press("mv_down")
	await _frames(150)
	Input.action_release("mv_down")
	_ck(lv.get_child_count() > 3, "关卡内已生成敌人 / 特效节点")
	Input.action_release("shoot")

	# 直接推进到 Boss
	lv._running = false
	await _frames(3)
	lv._running = true
	lv._boss_fight()
	await _frames(60)
	_ck(lv.boss != null and is_instance_valid(lv.boss), "Boss 已入场")
	lv.queue_free()
	Engine.time_scale = 1.0
	await _frames(3)


# ------------------------------------------------------------ Boss
func _test_boss() -> void:
	print("------ boss ------")
	Game.difficulty = Game.HARD      # 属性法罩只有困难档才有
	Game.picked_robes = [Game.RED, Game.BLUE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(3)
	lv._running = true
	lv._boss_fight()
	await _frames(60)
	var b := lv.boss
	if b == null or not is_instance_valid(b):
		_ck(false, "Boss 生成失败")
		return
	_ck(b.player_robes.size() == 2, "Boss 拿到玩家道袍（法罩只从中抽取）")

	Engine.time_scale = 2.0
	Input.action_press("shoot")
	var seen := {}
	var ward_seen := 0
	var last_ward := -2
	for i in 1400:
		if i % 45 == 0 and lv.player != null and is_instance_valid(lv.player):
			lv.player.do_swap()
			lv.player.hp = Player.MAX_HP
		if not is_instance_valid(b):
			break
		seen[b.phase] = true
		if b.ward != last_ward:
			last_ward = b.ward
			if b.ward >= 0:
				ward_seen += 1
		if i % 5 == 0:
			var c: int = b.ward if b.ward >= 0 else lv.player.color
			b.hit(26, c)
		if b.hp <= 260:
			break
		await get_tree().process_frame
	Input.action_release("shoot")
	Engine.time_scale = 1.0
	_ck(seen.has(2), "Boss 进入第 2 阶段")
	_ck(seen.has(3), "Boss 进入第 3 阶段")
	_ck(ward_seen >= 1, "属性法罩已展开（%d 次）" % ward_seen)
	_ck(lv.player != null and is_instance_valid(lv.player), "玩家在 Boss 战中存活")
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 难度与狂暴
func _test_difficulty() -> void:
	print("------ difficulty ------")

	# ---- 简单：血 1000 / 两重法相 / 无法罩
	Game.difficulty = Game.EASY
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(2)
	lv._running = true
	lv._boss_fight()
	Engine.time_scale = 4.0
	await _frames(20)
	var b := lv.boss
	if b == null or not is_instance_valid(b):
		_ck(false, "简单档 Boss 生成失败")
		Engine.time_scale = 1.0
		lv.queue_free()
		return
	# 老祖要从屏幕外飘到站位才进 fight。headless 帧率约 140fps（浮动很大），
	# 按帧数折算游戏时间会差好几倍 —— 改成轮询状态而不是数帧。
	for _i in 400:
		if b._st == "fight":
			break
		await get_tree().process_frame
	_ck(b._st == "fight", "简单：老祖入场到位（进入 fight）")
	_ck(b.max_hp == 1400, "简单：老祖血量 1400（提血后够走完三幕）")
	_ck(b.phase_marks().size() == 1, "简单：两重法相（一条阶段刻度）")
	await _frames(300)          # 跨过首个法罩周期（约 4 秒）
	Engine.time_scale = 1.0
	_ck(b.ward < 0, "简单：老祖始终不展法罩")
	lv.queue_free()
	await _frames(3)

	# ---- 困难：血 3600 / 三重法相 / 有法罩 / 异色 60% / 狂暴
	Game.difficulty = Game.HARD
	var lv2 := Level.new()
	add_child(lv2)
	await _frames(3)
	lv2._running = false
	await _frames(2)
	lv2._running = true
	lv2._boss_fight()
	Engine.time_scale = 4.0
	await _frames(20)
	var b2 := lv2.boss
	if b2 == null or not is_instance_valid(b2):
		_ck(false, "困难档 Boss 生成失败")
		Engine.time_scale = 1.0
		lv2.queue_free()
		Game.difficulty = Game.NORMAL
		return
	for _i in 400:
		if b2._st == "fight":
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_ck(b2._st == "fight", "困难：老祖入场到位（进入 fight）")
	_ck(b2.max_hp == 3600, "困难：老祖血量 3600")
	_ck(b2.phase_marks().size() == 2, "困难：三重法相（两条阶段刻度）")

	# 异色 / 同色的伤害差（同步连打，不让 _ward 有机会改颜色）
	b2.ward = Game.RED
	var h0 := b2.hp
	b2.hit(100, Game.BLUE)
	_ck(h0 - b2.hp == 60, "困难：法罩下异色伤害衰减到 60%")
	b2.ward = Game.RED
	var h1 := b2.hp
	b2.hit(100, Game.RED)
	_ck(h1 - b2.hp == 100, "困难：同色伤害不衰减")
	b2.ward = -1

	# 狂暴：血量压到三成以下
	b2.hp = int(float(b2.max_hp) * 0.25)
	for _i in 200:
		if b2.enraged:
			break
		await get_tree().process_frame
	_ck(b2.enraged, "困难：血量跌破三成 -> 老祖狂暴")

	# 只留狂暴螺旋：把常规套路的计时器顶到很远，避免其它弹幕混进来
	b2._cast = 9999.0
	b2._tick = 9999.0
	for ch in lv2.get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()
	await _frames(3)
	Engine.time_scale = 2.0
	await _frames(24)
	Engine.time_scale = 1.0
	var cols := {}
	for ch in lv2.get_children():
		if ch is Danmaku:
			cols[(ch as Danmaku).color] = true
	_ck(cols.size() == 4, "狂暴：四色螺旋弹幕（实测 %d 色）" % cols.size())

	lv2.queue_free()
	await _frames(3)
	Game.difficulty = Game.NORMAL


# ------------------------------------------------------------ 计分 / 品阶 / 最高分 / 换袍再来
## 覆盖：难度计分倍率、品阶阈值、最高分本地持久化、结算界面 swap_pressed
## 最高分存档是玩家的真实用户数据 —— 测试前后原样备份还原，不污染
func _test_score_persist() -> void:
	print("------ score / rank / highscore ------")
	var backup: Dictionary = Game.highscores.duplicate(true)

	# ---- 难度计分倍率 ----
	Game.difficulty = Game.EASY
	_ck(absf(Game.score_multiplier() - 1.00) < 0.001, "简单：计分倍率 1.00")
	Game.difficulty = Game.NORMAL
	_ck(absf(Game.score_multiplier() - 1.15) < 0.001, "普通：计分倍率 1.15")
	Game.difficulty = Game.HARD
	_ck(absf(Game.score_multiplier() - 1.35) < 0.001, "困难：计分倍率 1.35")

	# ---- 关卡实际落账：走的是 _add_score，与 HUD / 结算同源 ----
	Game.picked_robes = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	lv._running = false
	await _frames(3)
	lv.score = 0
	lv._add_score(100)
	_ck(lv.score == 135, "困难：原始 100 分 × 1.35 -> 落账 135（实测 %d）" % lv.score)
	Game.difficulty = Game.EASY
	lv.score = 0
	lv._add_score(100)
	_ck(lv.score == 100, "简单：原始 100 分 × 1.00 -> 落账 100（实测 %d）" % lv.score)
	lv.queue_free()
	await _frames(3)

	# ---- 品阶阈值（针对加权后的分数）----
	_ck(Game.rank_of(5999) == "黄品 · 炼气", "品阶：5999 -> 黄品 · 炼气")
	_ck(Game.rank_of(6000) == "玄品 · 筑基", "品阶：6000 -> 玄品 · 筑基")
	_ck(Game.rank_of(9000) == "地品 · 金丹", "品阶：9000 -> 地品 · 金丹")
	_ck(Game.rank_of(12500) == "天品 · 元婴", "品阶：12500 -> 天品 · 元婴")
	Game.difficulty = Game.HARD
	var hard_max := int(roundf(9800.0 * Game.score_multiplier()))
	_ck(hard_max >= 12500, "顶档可及：困难满分 9800 × 1.35 = %d ≥ 12500" % hard_max)
	Game.difficulty = Game.NORMAL
	var norm_max := int(roundf(9800.0 * Game.score_multiplier()))
	_ck(norm_max < 12500 and norm_max >= 9000,
		"普通满分 9800 × 1.15 = %d -> 止步地品" % norm_max)

	# ---- 最高分持久化 ----
	Game.highscores = {}
	_ck(Game.highscore_for(Game.NORMAL) == 0, "无存档 -> 最高分 0")
	Game.save_highscore(Game.NORMAL, 8000, [Game.RED, Game.WHITE], Game.rank_of(8000), true)
	_ck(Game.highscore_for(Game.NORMAL) == 8000, "写入 -> 最高分 8000")
	_ck(Game.highscore_for(Game.HARD) == 0, "最高分按难度分档（困难档仍为 0）")
	Game.save_highscore(Game.NORMAL, 5000, [Game.RED, Game.WHITE], Game.rank_of(5000), true)
	_ck(Game.highscore_for(Game.NORMAL) == 8000, "低分不覆盖 -> 仍为 8000")
	Game.save_highscore(Game.NORMAL, 11000, [Game.RED, Game.WHITE], Game.rank_of(11000), true)
	_ck(Game.highscore_for(Game.NORMAL) == 11000, "高分覆盖 -> 11000")
	Game._load_highscores()      # 真的落盘了吗 —— 重读一次就知道
	_ck(Game.highscore_for(Game.NORMAL) == 11000, "重读 user://highscores.json -> 仍是 11000")
	var rec: Variant = Game.highscores["1"]
	_ck(typeof(rec) == TYPE_DICTIONARY, "存档条目为 Dictionary（score / robes / rank / win）")

	# ---- _finish 的破纪录判定 ----
	Game.highscores = {}
	Game.difficulty = Game.NORMAL
	var lv2 := Level.new()
	add_child(lv2)
	lv2._running = false
	await _frames(3)
	lv2.score = 7777
	lv2._finish(true)
	_ck(Game.result_is_new_high, "首局 7777 分 -> 破纪录置位")
	_ck(Game.result_prev_high == 0, "首局：历史最高为 0")
	_ck(Game.result_score == 7777, "结算分 = 关卡分 7777")
	_ck(Game.highscore_for(Game.NORMAL) == 7777, "结算时写入最高分 7777")
	lv2.queue_free()
	await _frames(3)

	var lv3 := Level.new()
	add_child(lv3)
	lv3._running = false
	await _frames(3)
	lv3.score = 1000
	lv3._finish(true)
	_ck(not Game.result_is_new_high, "次局 1000 分 -> 未破纪录（标记复位）")
	_ck(Game.result_prev_high == 7777, "次局：历史最高读回 7777")
	_ck(Game.highscore_for(Game.NORMAL) == 7777, "低分不写入 -> 最高分仍为 7777")
	lv3.queue_free()
	await _frames(3)

	# ---- 结算界面：T 换袍再来 ----
	var rs := ResultScreen.new()
	rs.win = true
	add_child(rs)
	await _frames(3)
	_ck(rs.has_signal("swap_pressed"), "结算界面具备 swap_pressed 信号")
	var swapped := false
	rs.swap_pressed.connect(func() -> void:
		swapped = true
	)
	await _press("swap_again")
	_ck(swapped, "结算界面 T 键 -> 发出 swap_pressed")
	rs.queue_free()
	await _frames(3)

	Game.highscores = backup
	Game._write_highscores()
	Game.difficulty = Game.NORMAL


# ------------------------------------------------------------ 玩家陨落收尾
## 玩家一死，player_ref 就成了「已释放」对象。Boss 若继续按套路开火，
## 会把这个已释放对象赋给弹幕的 target —— 赋值当场就会报
## "Invalid assignment ... with value of type 'previously freed'"。
func _test_death() -> void:
	print("------ death ------")
	Game.difficulty = Game.NORMAL
	Game.picked_robes = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(2)
	lv._running = true
	lv._boss_fight()
	Engine.time_scale = 4.0
	await _frames(20)
	var b := lv.boss
	var p := lv.player
	if b == null or not is_instance_valid(b) or p == null:
		_ck(false, "Boss / 玩家生成失败")
		Engine.time_scale = 1.0
		lv.queue_free()
		return
	# 必须等老祖真的进入 fight 再判「收手」，否则入场阶段 _st 本来就不是 fight，
	# 断言会白给（这也是一开始差点漏掉的点）
	for _i in 400:
		if b._st == "fight":
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_ck(b._st == "fight", "老祖入场到位，正在开火")
	if is_instance_valid(p):
		p.hp = 1
		p._invuln = 0.0
		p.take_hit(Game.BLUE, 99)      # 身上是赤炎袍，吃蓝弹 -> 直接陨落
	await _frames(3)
	_ck(not is_instance_valid(p) or not p.alive, "玩家被打死")
	_ck(b._st != "fight", "玩家陨落 -> 老祖收手（不再按套路开火）")
	_ck(b._live_player() == null, "老祖不再持有已释放的玩家引用")
	# 让老祖持有一个「已释放」的玩家引用再开火 —— 这是原报错的精确复现条件。
	# 只要 _b() 里直接写 `b.target = player_ref`，这一炮就会炸。
	var dummy := Player.new()
	dummy.alive = false            # 不让它跑逻辑，只当个会被 free 的靶子
	lv.add_child(dummy)
	await _frames(2)
	b.player_ref = dummy
	dummy.queue_free()
	await _frames(3)
	_ck(b._live_player() == null, "player_ref 指向已释放节点 -> _live_player() 返回 null")
	# 注意：这一炮是「冒烟」而非硬断言 —— 赋值报错时 Godot 会直接跳过赋值，
	# target 反而保持 null，断言照样通过。真正的闸门是跑完日志里没有 ERROR。
	b._b(Game.YELLOW, Vector2.LEFT, 200.0, 10.0, 10, 1.05)
	var stale := 0
	for ch in lv.get_children():
		if ch is Danmaku and (ch as Danmaku).target != null:
			stale += 1
	_ck(stale == 0, "持有已释放引用时开火 -> 弹幕 target 仍为 null")
	b.player_ref = null
	# 死亡后继续跑一大段：只要还有一次开火就会往 target 塞已释放对象
	Engine.time_scale = 4.0
	await _frames(200)
	Engine.time_scale = 1.0
	_ck(b._st != "fight", "陨落后持续跑帧 -> 老祖始终未再开火")
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 通关结算链路
## 击杀 Boss -> Level 发出 finished(true) -> Main 切结算界面
func _test_win() -> void:
	print("------ win ------")
	Engine.time_scale = 8.0
	Game.difficulty = Game.NORMAL
	Game.picked_robes = [Game.WHITE, Game.RED]
	var lv := Level.new()
	_finished = false
	lv.finished.connect(func(w: bool) -> void:
		_finished = w
	)
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(2)
	lv._running = true
	lv._boss_fight()
	await _frames(60)
	var b := lv.boss
	if b == null or not is_instance_valid(b):
		_ck(false, "Boss 生成失败")
		return
	print("[ck] ----  击杀 Boss（验证胜利结算链路）")
	b.hp = 60
	b.hit(9999, b.ward if b.ward >= 0 else Game.RED)
	# Boss 死亡动画 16 × 0.12s + 结算等待 1.3s，time_scale=8 下约 40 帧
	await _frames(140)
	Engine.time_scale = 1.0
	_ck(_finished, "击杀 Boss -> Level 发出 finished(true)")
	_ck(Game.result_win, "记录胜利 result_win = true")
	_ck(Game.result_score > 0, "结算分数 > 0")
	lv.queue_free()
	await _frames(3)
