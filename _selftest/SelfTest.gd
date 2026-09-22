extends Node2D
## 自动化冒烟测试（headless 运行用，验证完毕即删除）
## 覆盖：四色免疫 / 护盾充能（开局 0 · 吸弹 +10 · 上限 20 · 不自动回复）/
## 电浆剑甲充能（吸弹 +20 · 满 100 自动打出 3 倍贯穿激光）/
## 闪避 /
## 移速加成 / 关卡生成 / Boss 三阶段 / 护罩 / UI 全流程
## 追加：引力（黄）免疫 / 引力束过热（+20 每秒 · 100 封顶 · 停手 0.5 秒后 -30 每秒）/ 引力弹 -30 / 引力束持续伤害

var _fails: Array[String] = []
var _finished := false
## 战将 killed 信号的接收记录（信号回调没法返回值，只能落到这里再断言）
var _elite_killed := false
var _elite_score := 0
## 结算界面 swap_pressed 的接收记录（GDScript 的 lambda 捕获局部变量是值捕获，
## 信号回调里改写局部变量外面读不到 —— 落成员上才收得到）
var _swapped := false


func _ready() -> void:
	await _frames(2)
	await _test_ui_flow()
	await _test_player()
	await _test_red_charge()   # 电浆剑甲：充能 -> 攒满自动贯穿激光
	await _test_dodge()
	await _test_yellow()
	await _test_pickup()
	await _test_elite()
	await _test_elite_hues()   # 战将多色弹幕：铁律 + 色序 + 力场色占比
	_test_elite_new()          # 新精英（堡垒/指挥/护盾）：铁律 + 护盾方向判定
	await _test_pool()
	await _test_vector_static()   # 07 §2.4：敌方矢量活体静态检查 V0~V4
	await _test_wording()         # 术语红线：全库不得出现旧称
	_test_cfg_source()        # 配置集中：实体文件不许自带数值常量 + 文案同源
	await _test_level()
	await _test_wave_colors()
	await _test_boss()
	await _test_l3_vent()      # L3 散热期专项：倍率 + 阶段切换窗口（断崖修复的回归网）
	await _test_hold_wave()    # 驻留阵地波：形式对比 + 屏内跃迁入场（提案 §3 的回归网）
	await _test_score_persist()
	await _test_legacy_inherit()
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


## 等场上所有贯穿激光走完（结算 -> 收束 -> 归还对象池）。
## 一律**轮询等状态**而不是数帧：headless 的物理步进很稀疏（一道 0.3 秒的光柱
## 可能跨越好几个 idle 帧才结算），数帧必翻车。
func _drain_lances() -> void:
	for _i in 200:
		var pending := false
		for ch in get_children():
			if ch is Lance:
				pending = true
				break
		if not pending:
			return
		await get_tree().physics_frame


func _ck(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
	print("[ck] %s  %s" % ["PASS" if cond else "FAIL", msg])


## 清空当前所有飘字文案。Fx 走对象池会复用节点，靠「文本比对」会漏判；
## 先清空，之后凡是非空文案必然是刚飘出来的。
func _clear_pops() -> void:
	for ch in get_children():
		if ch is Fx:
			ch.text = ""


## 取当前仍在场上的飘字文案集合
func _pop_texts() -> Array:
	var out: Array = []
	for ch in get_children():
		if ch is Fx and not str(ch.text).is_empty():
			out.append(str(ch.text))
	return out


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

	# 菜单第二项：战甲库
	await _press("mv_down")
	await _press("confirm")
	_ck(m.current is ArmorGallery, "菜单 ↓ + 确认 -> 战甲库")
	await _press("mv_right")
	await _press("pick_1")
	await _press("cancel")
	_ck(m.current is TitleScreen, "战甲库 ESC -> 回到开始界面")

	# 数字键 3 直达：游戏说明
	await _press("pick_2")
	_ck(m.current is HelpScreen, "数字键 3 -> 游戏说明")
	await _press("confirm")
	_ck(m.current is TitleScreen, "说明界面确认 -> 回到开始界面")

	# 菜单第一项：开始游戏 -> 关卡选择（五关卡片，取代旧择难度）
	await _press("confirm")
	_ck(m.current is StageSelect, "确认 -> 关卡选择（五关星域）")
	await _press("pick_0")                      # 数字键 1 = 第 1 关（锈带星域，恒解锁）
	_ck(Game.current_stage == 1, "数字键 1 -> 记下【第 1 关】")
	_ck(m.current is ArmorSelect, "择关确认 -> 择战甲界面")

	await _press("pick_0")
	await _press("pick_2")
	await _press("confirm")
	await _frames(4)
	_ck(m.current is Level, "选满两件战甲 -> 进入关卡")
	_ck(Game.picked_armors == [Game.RED, Game.WHITE], "记录所选两色 = 电浆 + 光子")

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
	var p := Player.new()
	p.world = self
	add_child(p)
	p.armors = [Game.WHITE, Game.RED]
	p.armor_idx = 0
	await _frames(2)
	_ck(p.color == Game.WHITE, "初始皮肤 = 光子(白)")
	_ck(p.shield == 0, "护盾开局为 0（不再自带满盾）")
	_ck(PlayerCfg.SHIELD_MAX == 20, "护盾上限常量 = 20")
	_ck(PlayerCfg.SHIELD_GAIN == 10, "单次充能常量 = 10")

	# ---------- 充能：白甲吸收白弹 ----------
	# 白弹撞白甲走的是 take_hit() 的**同色吸收**分支：不掉血、弹幕消失，
	# 光子盾甲额外把这一发转成护盾充能。
	var used := p.take_hit(Game.WHITE, 10)
	_ck(used == true, "白皮肤吸收白弹（弹幕消失）")
	_ck(p.hp == PlayerCfg.MAX_HP, "吸收后血量不变")
	_ck(p.shield == PlayerCfg.SHIELD_GAIN, "白甲吸收光子弹 -> 护盾 0 -> 10")
	# 再钉一次**绝对值**：上面那条拿的是常量，常量本身被改小它照样绿
	_ck(p.shield == 10, "单次充能绝对值 = 10")

	p._invuln = 0.0
	p.take_hit(Game.WHITE, 10)
	_ck(p.shield == PlayerCfg.SHIELD_MAX, "再吸收一枚 -> 护盾 10 -> 20（满值）")
	_ck(p.shield == 20, "护盾上限绝对值 = 20")
	_ck(p.hp == PlayerCfg.MAX_HP, "充能期间不掉血")

	p._invuln = 0.0
	p.take_hit(Game.WHITE, 10)
	_ck(p.shield == PlayerCfg.SHIELD_MAX, "满值后继续吸收 -> 仍为 20（上限钳制，不溢出）")
	_ck(p.hp == PlayerCfg.MAX_HP, "满值吸收同样不掉血")

	# M8 回归闸：护盾未满但剩余容量不足 10 时（如 15/20），飘字必须写**实际增量**，
	# 而不是写死的 SHIELD_GAIN —— 「飘 +10 实际只加 5」是这里最容易写错的样子。
	p.shield = 15
	p._invuln = 0.0
	_clear_pops()
	p.take_hit(Game.WHITE, 10)
	_ck(p.shield == 20, "余量不足 10 时吸收 -> 钳到 20（不溢出到 25）")
	_ck(_pop_texts().has("护盾 +5"), "充能飘字写实际增量 -> 「护盾 +5」（非写死 +10）")
	# 满值后再吸：不得溢出，且飘「护盾已满」而非 +10
	_clear_pops()
	p._invuln = 0.0
	p.take_hit(Game.WHITE, 10)
	_ck(p.shield == 20, "满值吸收后护盾仍为 20")
	_ck(_pop_texts().has("护盾已满"), "满值吸收飘「护盾已满」")

	# ---------- 力场罩期间吸光子弹照样充能（任务 1 回归闸） ----------
	# 力场罩的语义是「弹幕穿过」，但裁决是「吞下的光子弹仍要转成护盾」——
	# 所以充能判定排在力场罩早退之前。这里钉三件事：
	#   ① 力场罩生效中吸白弹 -> 照常 +10（把充能挪回力场罩分支之后会变 0，此条即红）；
	#   ② 一发只充一次：若两条分支各充一次会是 20，shield == 10 这条即红；
	#   ③ 返回值仍为 false —— 力场罩是「穿过」不是「吸收」，充能不改变这个语义。
	p.shield = 0
	p._invuln = 0.0
	p.invinc = 5.0
	_clear_pops()
	var ff_used := p.take_hit(Game.WHITE, 10)
	_ck(p.shield == 10, "力场罩期间吸光子弹 -> 照常充能 10（不被六秒无敌吞掉）")
	_ck(p.shield != 20, "一发弹只充一次（力场罩分支与同色吸收分支不重复充能）")
	_ck(ff_used == false, "力场罩充能后弹幕仍穿过（返回值 false，语义不变）")
	_ck(p.hp == PlayerCfg.MAX_HP, "力场罩期间不掉血")
	_ck(_pop_texts().has("护盾 +10"), "力场罩期间充能飘字正常 -> 「护盾 +10」")
	p.invinc = 0.0
	p.shield = 20      # 还原到满值状态，衔接下面的异色减伤用例（它期望进入时盾为 20）

	# ---------- 护盾仍按既有规则为光子盾甲减伤 ----------
	p._invuln = 0.0
	p.take_hit(Game.RED, 12)
	_ck(p.shield == 8, "白甲吃异色弹：护盾吸收 12 点 -> 剩 8")
	_ck(p.hp == PlayerCfg.MAX_HP, "护盾吸收期间不掉血")

	p._invuln = 0.0
	p.take_hit(Game.BLUE, 12)
	_ck(p.shield == 0, "护盾耗尽")
	_ck(p.hp == PlayerCfg.MAX_HP - 4, "溢出伤害 4 点扣血")

	# ---------- 取消自动回复 ----------
	# 此刻护盾正好是 0 —— 旧机制「无伤一段时间后回满」最容易被重新接回来的入口。
	# 三道闸，缺一不可：
	#   ① 直接把 30 秒游戏时间喂给 _process：确定性，不靠帧率，足以越过旧的
	#      10 秒阈值（headless 帧率抖动极大，数帧凑时间在这里根本不可靠）；
	#   ② 再跑一段真实帧：① 只覆盖「回盾写在 _process 里」的情形，
	#      写在别处的定时逻辑还得靠真实帧循环去撞；
	#   ③ 源码闸：回盾用的常量与计时器本身就不该存在（照 _test_dodge ⑥ 的写法）。
	p._invuln = 0.0
	var hp_keep := p.hp
	p._process(30.0)
	_ck(p.shield == 0, "取消自动回复：推进 30 秒游戏时间后护盾仍为 0")
	_ck(p.hp == hp_keep, "推进游戏时间期间不掉血")
	for _i in 120:
		await get_tree().process_frame
		if p.shield != 0:
			break
	_ck(p.shield == 0, "取消自动回复：真实帧循环推进后护盾仍为 0")
	var psrc := _read("res://scripts/entities/Player.gd")
	_ck(not psrc.is_empty(), "读到 Player.gd 源码")
	_ck(not psrc.to_lower().contains("shield_regen"), "Player.gd 已无 SHIELD_REGEN（回盾常量）")
	_ck(not psrc.to_lower().contains("_no_hit"), "Player.gd 已无 _no_hit（无伤计时器）")

	# ---------- 只有穿着光子盾甲才充能 ----------
	p.do_swap()
	_ck(p.color == Game.RED, "空格切换 -> 电浆(红)")
	p._invuln = 0.0        # do_swap() 自带 0.18 秒换甲无敌帧，必须放在它**之后**清零
	var hp_r0 := p.hp
	_ck(p.take_hit(Game.WHITE, 10) == true, "红甲吃白弹 -> 正常受伤（不免疫）")
	_ck(p.hp == hp_r0 - 10, "红甲吃白弹扣血 10")
	_ck(p.shield == 0, "非光子盾甲吃白弹**不**充能（护盾仍为 0）")

	# M9 回归闸：护盾的**减伤**同样只认光子盾甲 —— 非白甲即便 shield > 0 也
	# 不得借护盾减伤（数值保留但不生效），更不得被消耗。
	p.shield = 20
	p._invuln = 0.0
	var hp_r1 := p.hp
	_ck(p.take_hit(Game.BLUE, 20) == true, "红甲（盾 20）吃蓝弹 -> 正常受伤结算")
	_ck(p.hp == hp_r1 - 20, "非白甲有盾吃异色弹 -> 全额扣血 20（护盾不减伤）")
	_ck(p.shield == 20, "非白甲受伤不消耗护盾（数值原样保留）")
	p.shield = 0        # 还原，免得污染后面的用例

	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == true, "红皮肤吸收红弹（弹幕消失）")
	p._invuln = 0.0
	_ck(p.take_hit(Game.BLUE, 10) == true, "红皮肤吃蓝弹并扣血")

	# 移速：红 vs 蓝
	p.armors = [Game.RED, Game.BLUE]
	p.armor_idx = 0
	p.hp = PlayerCfg.MAX_HP
	p.position = Vector2(300.0, 360.0)
	await _frames(2)
	Input.action_press("mv_right")
	var x0 := p.position.x
	await _frames(12)
	var d_red := p.position.x - x0
	p.do_swap()
	_ck(p.color == Game.BLUE, "切换 -> 寒霜(蓝)")
	var x1 := p.position.x
	await _frames(12)
	var d_blue := p.position.x - x1
	Input.action_release("mv_right")
	if d_red > 0.001:
		var ratio := d_blue / d_red
		_ck(ratio > 1.25, "蓝皮肤移速 +50%（实测 " + String.num(ratio, 2) + " 倍）")
	else:
		_ck(false, "移速测试无效：红皮肤位移为 0")

	# ---------- 同色吸收：走真实弹幕链路 ----------
	# 只断言 take_hit 的返回值是不够的 —— 真正要保证的是那颗弹真的从场上消失了。
	# 这里让一颗同色弹压在玩家身上，看它有没有被 _kill 掉。
	p._invuln = 0.0
	p.armors = [Game.RED, Game.BLUE]
	p.armor_idx = 0
	p.position = Vector2(400.0, 360.0)
	await _frames(2)
	var hp_before := p.hp
	var bd := Danmaku.spawn(self, Game.RED, p.position, Vector2.ZERO, 10, 9.0)
	_ck(bd != null, "同色吸收：测试弹生成成功")
	if bd != null:
		for _i in 12:
			if not bd._alive:
				break
			await get_tree().physics_frame
		_ck(not bd._alive, "同色弹被战甲吸收 -> 弹幕消失（不再穿过）")
	_ck(p.hp == hp_before, "吸收同色弹不掉血")
	# 对照组：力场罩期间仍是「穿过」而非吸收 —— 这条别被上面的改动带偏
	p._invuln = 0.0
	p.apply_pickup(Pickup.T.INVINC)
	var bi := Danmaku.spawn(self, Game.BLUE, p.position, Vector2.ZERO, 10, 9.0)
	_ck(bi != null, "力场罩对照：测试弹生成成功")
	if bi != null:
		for _j in 12:
			await get_tree().physics_frame
			if not bi._alive:
				break
		_ck(bi._alive, "力场罩期间弹幕仍穿过（未被吸收）")
		bi.dissolve()
	p.invinc = 0.0
	await _frames(2)

	p.queue_free()
	await _frames(2)


# ------------------------------------------------------------ 寒霜疾甲 · 闪避
## 需求：蓝甲被同色（寒霜）弹命中后获得 0.5 秒闪避，期间变淡且不承受弹幕伤害。
## 三条设计边界（用户已拍板，改动时别被"补全"冲动带偏）：
##   ① 闪避只挡走 take_hit() 的**弹幕**通道 —— 殉爆者冲撞 / 冲击环是刻意绕过
##      同色免疫的物理通道（EnemyBrain 直接扣 hp），**不**接入闪避；
##   ② 闪避是寒霜疾甲的附属能力，切甲立刻清零；
##   ③ 闪避期间撞上来的弹幕**不消失、继续飞** —— take_hit 返回 false。
## 另外：闪避只有 0.5 秒，headless 帧率抖动极大，一律**轮询状态**等它结束，
##      绝不靠数帧去凑时间。
# ------------------------------------------------------------ 电浆剑甲 · 贯穿激光
func _test_red_charge() -> void:
	print("------ red charge (电浆剑甲 · 贯穿激光) ------")
	_ck(PlayerCfg.CHARGE_GAIN == 20, "单次充能常量 = 20")
	_ck(PlayerCfg.CHARGE_MAX == 100, "能量上限常量 = 100")
	_ck(is_equal_approx(PlayerCfg.LANCE_MUL, 3.0), "激光倍率常量 = 3.0")
	_ck(PlayerCfg.CHARGE_MAX % PlayerCfg.CHARGE_GAIN == 0,
		"上限是充能量的整数倍（第 %d 发必定触发，不会卡在差一点点）"
			% (PlayerCfg.CHARGE_MAX / PlayerCfg.CHARGE_GAIN))

	var p := Player.new()
	p.world = self
	add_child(p)
	p.armors = [Game.RED, Game.BLUE]
	p.armor_idx = 0
	await _frames(2)
	_ck(p.color == Game.RED, "充能用例：穿上电浆剑甲(红)")
	_ck(p.charge == 0, "能量开局为 0")

	# ---------- ① 逐发充能 20 -> 40 -> 60 -> 80 ----------
	var hp0 := p.hp
	p._invuln = 0.0
	_clear_pops()
	_ck(p.take_hit(Game.RED, 10) == true, "① 红甲吸收红弹（弹幕消失）")
	_ck(p.charge == 20, "① 吸收一枚 -> 能量 0 -> 20（绝对值）")
	_ck(p.charge != 0, "① 充能确实发生（常量被改小这条不绿）")
	_ck(p.hp == hp0, "① 吸收同色弹不掉血")
	_ck(_pop_texts().has("能量 +20"), "① 充能飘字 -> 「能量 +20」")
	for expect in [40, 60, 80]:
		p._invuln = 0.0
		p.take_hit(Game.RED, 10)
		_ck(p.charge == expect, "① 累积充能 -> 能量 %d" % expect)

	# ---------- ② 攒满即**自动**打出并清零（不等玩家按键）----------
	p._invuln = 0.0
	_clear_pops()
	p.take_hit(Game.RED, 10)
	_ck(p.charge == 0, "② 攒满自动打出 -> 能量清零（不停在 100 上）")
	_ck(_pop_texts().has("贯穿激光"), "② 打出瞬间飘「贯穿激光」")

	# ---------- ③ 只在穿着电浆剑甲时充能 ----------
	p.do_swap()
	_ck(p.color == Game.BLUE, "③ 换甲 -> 寒霜(蓝)")
	p._invuln = 0.0        # do_swap() 自带 0.18 秒换甲无敌帧，必须在它**之后**清零
	p.charge = 0
	p.take_hit(Game.RED, 10)
	_ck(p.charge == 0, "③ 非电浆剑甲吃红弹**不**充能（能量仍为 0）")
	# 白甲吸白弹走的是护盾通道，不得顺带把能量也充上
	p.armors = [Game.WHITE, Game.RED]
	p.armor_idx = 0
	p.charge = 0
	p._invuln = 0.0
	p.take_hit(Game.WHITE, 10)
	_ck(p.charge == 0, "③ 白甲吸白弹只充护盾，不充激光能量")

	# ---------- ④ 力场罩期间吞红弹照充，且一发只充一次 ----------
	p.armors = [Game.RED, Game.BLUE]
	p.armor_idx = 0
	p.charge = 0
	p._invuln = 0.0
	p.invinc = 5.0
	var ff := p.take_hit(Game.RED, 10)
	_ck(p.charge == 20, "④ 力场罩期间吞红弹 -> 照常充能 20")
	_ck(p.charge != 40, "④ 一发弹只充一次（力场罩分支与同色吸收分支不重复充能）")
	_ck(ff == false, "④ 充能不改语义：力场罩下弹幕仍穿过（返回 false）")
	p.invinc = 0.0

	# ---------- ⑤ 闪避期间不充能（闪避早退排在充能之前）----------
	p._invuln = 0.0
	p.charge = 0
	p._dodge = PlayerCfg.DODGE_TIME
	p.take_hit(Game.RED, 10)
	_ck(p.charge == 0, "⑤ 闪避期间吞红弹不充能（早退发生在充能之前）")
	p._dodge = 0.0

	# ---------- ⑥ 伤害 = 单发光刃 × 3（走 Player.lance_damage 一处派生）----------
	_ck(p.lance_damage() == 24, "⑥ 激光伤害 = 单发光刃 8 × 3 = 24（绝对值）")
	p.atk_up = PlayerCfg.ATK_MAX
	_ck(p.lance_damage() == 33, "⑥ 满叠增幅核心 -> 11 × 3 = 33（倍率随增幅生效）")
	p.atk_up = 0

	# ---------- ⑦ 真链路：充到满 -> 自动打出 -> 贯穿同一排上的两个目标 ----------
	# 用**蓝色**敌人当靶：红光柱对它属异色，不吃「同源共振 +50%」，
	# 掉血量才等于 lance_damage() 本身，断言才敢写绝对值。
	#
	# ⚠️ 先排空在飞的光柱：② 打出的那道还挂在树上（headless 物理步进很稀疏，
	#    它要等两个物理帧才结算），不排空的话会先一步打到刚建好的靶子上，
	#    读数变成 34 -> 10。这里一律**轮询等状态**而不是数帧 —— 数帧在
	#    headless 下根本不可靠（帧率抖动可达一个数量级）。
	await _drain_lances()
	p.position = Vector2(300.0, 360.0)
	var e1 := Enemy.new()
	e1.world = self
	add_child(e1)
	e1.setup(Game.BLUE, "hover", 360.0, 1.0)
	e1.position = Vector2(600.0, 360.0)
	var e2 := Enemy.new()
	e2.world = self
	add_child(e2)
	e2.setup(Game.BLUE, "hover", 360.0, 1.0)
	e2.position = Vector2(880.0, 360.0)
	# 对照组：站在光柱**外**（纵向差 160px）的第三个目标必须毫发无损 ——
	# 这条守的是 LANCE_HALF_H 不被悄悄放大成「全屏 AOE」。
	var e3 := Enemy.new()
	e3.world = self
	add_child(e3)
	e3.setup(Game.BLUE, "hover", 520.0, 1.0)
	e3.position = Vector2(740.0, 520.0)
	await _frames(2)
	var hp1 := e1.hp
	var hp2 := e2.hp
	var hp3 := e3.hp
	_ck(hp1 == 34 and hp2 == 34, "⑦ 两个靶子满血入场（%d / %d）" % [hp1, hp2])
	_ck(hp1 > p.lance_damage() and hp2 > p.lance_damage(),
		"⑦ 靶子血量足以承住一击（不掉到 0，掉血量才读得准）")
	# 走真实充能链路：差一发满 -> 吞下第五颗电浆弹 -> 自动打出
	p.charge = PlayerCfg.CHARGE_MAX - PlayerCfg.CHARGE_GAIN
	p._invuln = 0.0
	_clear_pops()
	p.take_hit(Game.RED, 10)
	_ck(p.charge == 0, "⑦ 第五颗电浆弹 -> 自动打出并清零")
	_ck(_pop_texts().has("贯穿激光"), "⑦ 真链路同样飘「贯穿激光」")
	await _drain_lances()
	var d1 := hp1 - (e1.hp if is_instance_valid(e1) else 0)
	var d2 := hp2 - (e2.hp if is_instance_valid(e2) else 0)
	_ck(d1 == 24, "⑦ 近端目标掉血 24（实测 %d）" % d1)
	_ck(d2 == 24, "⑦ 远端目标同样掉血 24 -> 贯穿未被近端吃掉（实测 %d）" % d2)
	var d3 := hp3 - (e3.hp if is_instance_valid(e3) else 0)
	_ck(d3 == 0, "⑦ 光柱外的目标毫发无损（只打这一排，实测掉 %d）" % d3)

	# ---------- ⑧ 作战手册的激光条目由配置现拼（不写死数值）----------
	var red_line := ""
	for sec in HelpScreen._build_sections():
		for line in sec["l"]:
			var s := str(line)
			if s.contains("贯穿激光"):
				red_line = s
	_ck(red_line.contains("%d" % PlayerCfg.CHARGE_MAX),
		"⑧ 手册写了能量上限 %d（改配置文案跟着变，实测「%s」）"
			% [PlayerCfg.CHARGE_MAX, red_line])
	_ck(red_line.contains("%.0f 倍" % PlayerCfg.LANCE_MUL),
		"⑧ 手册写了 %.0f 倍伤害（实测「%s」）" % [PlayerCfg.LANCE_MUL, red_line])

	for ch in get_children():
		if ch is Enemy:
			(ch as Enemy).queue_free()
	p.queue_free()
	await _frames(3)


func _test_dodge() -> void:
	print("------ dodge (寒霜疾甲) ------")
	var p := Player.new()
	p.world = self
	add_child(p)
	p.armors = [Game.BLUE, Game.RED]
	p.armor_idx = 0
	await _frames(2)
	_ck(p.color == Game.BLUE, "闪避用例：穿上寒霜疾甲(蓝)")
	_ck(is_equal_approx(PlayerCfg.DODGE_TIME, 0.5), "闪避时长常量 = 0.5 秒")

	# ---------- ① 蓝色甲吃到蓝色弹 -> 进入闪避 ----------
	p._invuln = 0.0
	p._dodge = 0.0
	_ck(not p.dodging and p.dodge_left == 0.0, "① 初始不处于闪避")
	var hp0 := p.hp
	_ck(p.take_hit(Game.BLUE, 10) == true, "① 蓝甲吸收蓝弹（弹幕消失）")
	_ck(p.dodging, "① 蓝甲吸收同色弹 -> 进入闪避")
	_ck(p.dodge_left > 0.0, "① 闪避剩余时间 > 0（实测 %.2f 秒）" % p.dodge_left)
	_ck(p.hp == hp0, "① 吸收同色弹不掉血")

	# ---------- ② 闪避期间吃异色弹不掉血，且弹幕穿透继续飞 ----------
	var hp1 := p.hp
	_ck(p.take_hit(Game.RED, 20) == false,
		"② 闪避期间吃异色弹 -> take_hit 返回 false（弹幕穿透）")
	_ck(p.hp == hp1, "② 闪避期间不掉血")
	# 旧断言「闪避不打断十秒回盾计时（_no_hit 未被清零）」随自动回复一起删除了 ——
	# 那条语义已不存在。换成一条**等价有力**的：闪避的 return false 发生在
	# 受击结算（_invuln = INVULN）之前，所以闪避不额外赠送 0.85 秒无敌帧；
	# 否则「闪避 0.5 秒 + 受击无敌 0.85 秒」会悄悄叠成 1.35 秒的免伤窗口。
	p._dodge = PlayerCfg.DODGE_TIME
	p._invuln = 0.0
	var hp1b := p.hp
	_ck(p.take_hit(Game.YELLOW, 20) == false, "② 闪避期间吃黄弹 -> 穿透（返回 false）")
	_ck(p._invuln == 0.0, "② 闪避拦截发生在受击结算之前（不赠送受击无敌帧）")
	_ck(p.hp == hp1b, "② 闪避期间吃黄弹不掉血")

	# 真链路：让一颗异色弹压在闪避中的玩家身上 —— 它应当**穿过**而不是被吃掉
	p.position = Vector2(420.0, 360.0)
	p._dodge = PlayerCfg.DODGE_TIME
	await _frames(2)
	var dd := Danmaku.spawn(self, Game.RED, p.position, Vector2.ZERO, 10, 9.0)
	_ck(dd != null, "② 穿透链路：异色测试弹生成成功")
	if dd != null:
		for _i in 10:
			await get_tree().physics_frame
			if not p.dodging:
				break
		_ck(dd._alive, "② 闪避期间异色弹穿过玩家继续飞行（未被消耗）")
		if not dd._alive:
			p._dodge = PlayerCfg.DODGE_TIME       # 弹没了说明断言已失败，别让后续用例连锁失败
		dd.dissolve()
	await _frames(2)

	# ---------- ③ 0.5 秒后自动结束（轮询，不数帧）----------
	p._dodge = PlayerCfg.DODGE_TIME
	p._invuln = 0.0
	var ended := false
	for _i in 400:
		if not p.dodging:
			ended = true
			break
		await get_tree().process_frame
	_ck(ended, "③ 闪避在 0.5 秒后自动结束")
	# 结束后恢复正常受击（否则闪避变成了永久无敌）
	p._invuln = 0.0
	var hp2 := p.hp
	_ck(p.take_hit(Game.RED, 10) == true, "③ 闪避结束后恢复正常受击")
	_ck(p.hp == hp2 - 10, "③ 闪避结束后正常扣血")

	# ---------- ④ 切甲后闪避立刻失效 ----------
	p._invuln = 0.0
	p._dodge = PlayerCfg.DODGE_TIME
	_ck(p.dodging, "④ 闪避已置位")
	p.do_swap()
	_ck(p.color == Game.RED, "④ 切甲 -> 电浆(红)")
	_ck(not p.dodging and p.dodge_left == 0.0, "④ 切甲后闪避立刻失效")

	# ---------- ⑤ 非蓝色甲吃同色弹不触发闪避（四色全过一遍）----------
	for c in 4:
		if c == Game.BLUE:
			continue
		p.armors = [c, Game.RED if c != Game.RED else Game.WHITE]
		p.armor_idx = 0
		p._dodge = 0.0
		p._invuln = 0.0
		p.hp = PlayerCfg.MAX_HP
		await _frames(2)
		_ck(p.color == c, "⑤ 换上 %s" % Game.ARMOR_TITLE[c])
		_ck(p.take_hit(c, 10) == true, "⑤ %s 吸收同色弹（弹幕消失）" % Game.COLOR_CN[c])
		_ck(not p.dodging, "⑤ %s 吸收同色弹**不**触发闪避" % Game.COLOR_CN[c])
		p._invuln = 0.0

	# ---------- ⑥ 闪避不得接入物理伤害通道 ----------
	# 殉爆者冲撞与冲击环（EnemyBrain 里直接 `p.hp -= ...`）是刻意绕过同色免疫的：
	# 这两处一旦引用闪避，玩家就能用蓝甲白嫖撞伤 —— 设计边界变成静默回归。
	var eb := _read("res://scripts/entities/EnemyBrain.gd")
	# 前置断言：读文件失败会拿到空串，空串的 contains 永远 false —— 这条闸会在
	# 源码读不到时**永远 PASS 而毫无防护力**。先钉住「读到了」，闸才有意义。
	_ck(not eb.is_empty(), "⑥ 读到 EnemyBrain.gd 源码")
	# 两个坑叠在一起，缺一不可：
	# ① to_lower()：GDScript 的 contains() 区分大小写，DODGE / DODGE_TIME 这类大写
	#    形态不做归一就漏掉。
	# ② 匹配子串取 "dodg" 而非 "dodge"：四种形态 dodge/DODGE/dodging/DODGE_TIME 的
	#    公共前缀是 "dodg"；而 "dodging"（d-o-d-g-**i**-n-g）里**并不含**连续的
	#    "dodge"（d-o-d-g-**e**）。若写成 contains("dodge")，将来有人在物理通道写
	#    `if p.dodging:` 这条闸照样绿 —— 实测已确认漏判。用 "dodg" 才把四种形态
	#    一网打尽。本闸只扫 EnemyBrain.gd，该文件内 "dodg" 无任何合法出现，不会误伤。
	# 守的是「物理通道刻意不免疫闪避」这条用户明确裁决的设计边界。
	_ck(not eb.to_lower().contains("dodg"),
		"⑥ 闪避未接入物理伤害通道（EnemyBrain 全文不出现 dodge / DODGE / dodging / DODGE_TIME）")

	p.queue_free()
	await _frames(2)


# ------------------------------------------------------------ 引力（黄）
func _test_yellow() -> void:
	print("------ yellow / heat ------")
	var p := Player.new()
	p.world = self
	add_child(p)
	p.armors = [Game.YELLOW, Game.RED]
	p.armor_idx = 0
	await _frames(2)
	_ck(p.color == Game.YELLOW, "换上引力束甲(黄)")

	p._invuln = 0.0
	_ck(p.take_hit(Game.YELLOW, 10) == true, "引力束甲吸收引力弹（弹幕消失）")
	_ck(p.hp == PlayerCfg.MAX_HP, "吸收引力弹不掉血")

	# 过热：出光每秒 +20，封顶 100
	p.heat = 0.0
	p._firing = true
	p._update_heat(1.0)
	_ck(absf(p.heat - 20.0) < 0.01, "出光 1 秒 -> 过热值 +20")
	p._update_heat(4.5)
	_ck(absf(p.heat - PlayerCfg.HEAT_MAX) < 0.01, "过热值封顶 100")
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

	# 触及引力弹 -> 立刻散去 30
	p.heat = 80.0
	p._invuln = 0.0
	p.take_hit(Game.YELLOW, 10)
	_ck(absf(p.heat - 50.0) < 0.01, "触及引力弹 -> 过热值立刻 -30")
	p.queue_free()
	await _frames(2)

	# 引力星盗喽啰：会射出引力弹
	var ey := Enemy.new()
	ey.world = self
	add_child(ey)
	ey.setup(Game.YELLOW, "sine", 300.0, 1.0)
	ey._entered = true
	_ck(ey.max_hp == 30 and ey.fire_cd > 1.5, "引力星盗喽啰数值生效（血 30 / 射速偏慢）")
	ey._shoot()
	var ny := 0
	for ch in get_children():
		if ch is Danmaku and (ch as Danmaku).color == Game.YELLOW:
			ny += 1
	_ck(ny == 3, "引力星盗喽啰一次射出 3 枚引力弹")
	for ch in get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()
	ey.queue_free()
	await _frames(2)

	# 引力束：持续结算伤害（不是弹丸，而是压在光柱上按 tick 掉血）
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
	_ck(beamed, "引力束（激光）持续结算伤害")
	bm.turn_off()
	bm.queue_free()
	if is_instance_valid(e):
		e.queue_free()
	await _frames(2)

	# hover 骚扰敌离场是向右飞出画面的：出右边界必须自我回收，
	# 否则它永远等不到 free，清场判定会被一路拖到上限（同色潮每波必有 hover）。
	var eh := Enemy.new()
	eh.world = self
	add_child(eh)
	eh.setup(Game.RED, "hover", 360.0, 1.0)
	eh._leaving = true
	eh.position = Vector2(Game.VIEW_W + 200.0, 360.0)
	await _frames(3)
	_ck(not is_instance_valid(eh), "hover 敌向右飞出画面 -> 自动回收")
	# 对照组：还在逼近 / 驻留的目标色绝不能被这条规则误删
	var ea := Enemy.new()
	ea.world = self
	add_child(ea)
	ea.setup(Game.BLUE, "hover", 360.0, 1.0)
	ea.position = Vector2(Game.VIEW_W - 60.0, 360.0)
	await _frames(3)
	_ck(is_instance_valid(ea), "未离场的 hover 敌不被误回收")
	if is_instance_valid(ea):
		ea.queue_free()
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
	_ck(pk.collision_layer == 16, "道具在碰撞层 bit4（光刃与敌弹都不会误触）")
	var px0 := pk.position.x
	await _frames(8)
	_ck(pk.position.x < px0, "道具向左漂浮")

	# 掉落常常发生在**物理回调里**（光刃命中 -> 星盗死亡 -> 关卡掉落）。
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
	p.armors = [Game.WHITE, Game.RED]
	p.armor_idx = 0
	p.shield = 0        # 护盾开局本就是 0，这里显式钉住：否则异色伤害会先被护盾吃掉，扣血不可预期
	await _frames(2)

	# 修复包
	p.hp = 50
	p.apply_pickup(Pickup.T.HEAL)
	_ck(p.hp == 70, "修复包 -> 生命 +20")
	p.hp = 95
	p.apply_pickup(Pickup.T.HEAL)
	_ck(p.hp == PlayerCfg.MAX_HP, "修复包不会超出生命上限")

	# 刃影模块
	_ck(p.rows() == 1, "光子盾甲基准单排弹道")
	p.apply_pickup(Pickup.T.MULTI)
	_ck(p.multi == 1 and p.rows() == 2, "刃影模块 -> 弹道 +1")
	p.armor_idx = 1
	_ck(p.rows() == 3, "电浆剑甲双排 + 刃影模块 = 三排")
	p.armor_idx = 0

	# 增幅核心
	# 绝对值锁定：只写 atk_mul == 1 + ATK_STEP 的话，STEP 被改小也照样绿
	_ck(absf(PlayerCfg.ATK_STEP - 0.10) < 0.0001, "增幅核心单层增幅恒为 +10%%（实测 %d%%）" % int(roundf(PlayerCfg.ATK_STEP * 100.0)))
	_ck(p.sword_damage() == 10, "基准光刃伤害 10")
	p.apply_pickup(Pickup.T.ATK)
	_ck(absf(p.atk_mul - 1.10) < 0.001, "增幅核心 -> 攻击力 +10%")
	_ck(p.sword_damage() == 11, "光刃伤害 10 -> 11")
	_ck(p.sword_size() > 1.0, "光刃变大（外观与碰撞体同步）")
	_ck(p.beam_width() > 1.0, "引力束变粗")
	_ck(absf(p.beam_dps() - 120.0 * 1.1) < 0.01, "引力束每秒伤害同步提高到 132")

	# 层数封顶
	for _i in 8:
		p.apply_pickup(Pickup.T.MULTI)
		p.apply_pickup(Pickup.T.ATK)
	_ck(p.multi == PlayerCfg.MULTI_MAX, "刃影模块层数封顶 %d 层" % PlayerCfg.MULTI_MAX)
	_ck(p.atk_up == PlayerCfg.ATK_MAX, "增幅核心层数封顶 %d 层" % PlayerCfg.ATK_MAX)
	_ck(absf(p.atk_mul - (1.0 + PlayerCfg.ATK_STEP * float(PlayerCfg.ATK_MAX))) < 0.0001,
		"满叠增幅封顶 +%d%%（实测 +%d%%）" % [
			int(roundf(PlayerCfg.ATK_STEP * float(PlayerCfg.ATK_MAX) * 100.0)),
			int(roundf((p.atk_mul - 1.0) * 100.0))])

	# 力场罩
	p.invinc = 0.0
	p.apply_pickup(Pickup.T.INVINC)
	_ck(absf(p.invinc - PlayerCfg.INVINC_TIME) < 0.001, "力场罩 -> 无敌 6 秒")
	p.hp = 100
	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == false, "力场罩期间免伤（弹幕穿过）")
	_ck(p.hp == 100, "力场罩期间不掉血")
	p.invinc = 0.0
	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == true, "力场罩失效后恢复正常受击")
	_ck(p.hp == 90, "失效后正常扣血")

	# 引力束甲：刃影模块 -> 多一道引力束，且**不额外增加过热值**
	p.armors = [Game.YELLOW, Game.RED]
	p.armor_idx = 0
	p.multi = 1
	await _frames(2)
	_ck(p.rows() == 2, "引力束甲 + 刃影模块 = 两道引力束")
	p._beam_on()
	var on_n := 0
	for b in p._beams:
		if b.on:
			on_n += 1
	_ck(on_n == 2, "实际点亮两道引力束")
	p._beam_off()
	var off_n := 0
	for b2 in p._beams:
		if b2.on:
			off_n += 1
	_ck(off_n == 0, "停手后引力束全部熄灭")

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
	_ck(absf(h1 - h2) < 0.01, "刃影模块加排不额外增加过热值（%d -> %d）" % [int(h1), int(h2)])
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
	Game.picked_armors = [Game.RED, Game.WHITE]
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
	# 每波刷新数归 StageCfg 管（Level 侧那份 WAVE_DROP 已删，避免同值双源）
	var wd := StageCfg.wave_drop(lv.stage)
	_ck(n1 - n0 == wd, "每波结束刷新 %d 个道具（实测 %d 个）" % [wd, n1 - n0])
	_ck(not lv.has_method("_heal"), "波次结束不再回血（_heal 已移除，生命只靠修复包）")

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
	_ck(hits > 0, "击杀星盗喽啰会掉落道具（60 次命中 %d 次）" % hits)
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 星盗战将（精英）
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
	Game.picked_armors = [Game.RED, Game.WHITE]
	var e := Elite.new()
	e.world = self
	add_child(e)
	e.player_armors = [Game.RED, Game.WHITE]
	e.setup(1.0)
	await _frames(2)
	_ck(e.color == Game.RED or e.color == Game.WHITE,
		"力场色只从玩家两件战甲中抽取（抽到 %s）" % Game.COLOR_CN[e.color])
	# S0 常驻回归（R-02）：Level 给 Elite 赋「玩家战甲」的字段名一旦与 Elite.gd 声明
	# 的不一致，GDScript 是**运行时静默失败** —— 力场色会退化成 randi()%4，
	# 也就是设计事故级死局（给到玩家没带的颜色 = 破不了力场）。
	# 这条断言把「静默失败」变成「红门禁」。
	_ck(e.player_armors.has(e.color),
		"战将力场色恒 ∈ 玩家战甲（R-02 回归，实测 %s）" % Game.COLOR_CN[e.color])
	_ck(e.collision_layer == 4 and e.collision_mask == 2,
		"战将与星盗喽啰同层（bit2，只吃 bit1 光刃）")
	_ck(e.ward == e.ward_max and e.hp == e.max_hp, "出场即带满层力场")
	_ck(e.max_hp > 400 and e.ward_max > 100,
		"血厚于星盗喽啰（本体 %d / 力场 %d）" % [e.max_hp, e.ward_max])

	# ---------- 力场分层：异色刮痧，且破力场前本体不掉血 ----------
	var off := (e.color + 1) % 4
	var hp0 := e.hp
	var w0 := e.ward
	e.hit(100, off)
	var d_off := w0 - e.ward
	_ck(e.hp == hp0, "力场未破时本体不掉血")
	_ck(d_off == int(roundf(100.0 * EnemyCfg.ELITE_WARD_RESIST)),
		"异色打力场只剩 %d%%（100 -> %d）" % [int(EnemyCfg.ELITE_WARD_RESIST * 100.0), d_off])
	# 用 20 点试同色：100 点同色打出来是 150，会一击打爆 150 的力场 ——
	# 那测的就不是衰减比例而是「恰好破力场」了
	e.ward = w0
	e.hit(20, e.color)
	_ck(w0 - e.ward == 30, "同色打力场全额 +50%%（20 -> %d）" % (w0 - e.ward))

	# ---------- 破力场 -> 虚弱 ----------
	e.ward = 10
	e.hit(50, e.color)
	_ck(e.ward == 0 and e.broken > 0.0, "力场击破 -> 进入虚弱期")
	_ck(e.layers == EnemyCfg.ELITE_WARD_LAYERS - 1, "破一层扣一次重铸机会（余 %d 次）" % e.layers)
	var h1 := e.hp
	e.hit(100, off)
	_ck(h1 - e.hp == 100, "虚弱期异色对本体全额（不再衰减）")
	var h2 := e.hp
	e.hit(100, e.color)
	_ck(h2 - e.hp == 150, "虚弱期同色仍有共振 +50%")

	# ---------- 重铸与永久破防 ----------
	e.broken = 0.001
	await _frames(4)
	_ck(e.ward == e.ward_max, "虚弱结束 -> 力场重铸（余 %d 次）" % e.layers)
	_ck(e.broken <= 0.0, "重铸后虚弱计时归零")
	e.ward = 0
	e.layers = 0
	e.broken = 0.001
	await _frames(4)
	_ck(e.ward == 0 and e.broken <= 0.0, "重铸次数用尽 -> 永久破防")

	# ---------- 走真实光刃链路：Sword 只认 Damageable ----------
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
		"光刃可命中战将（走 Damageable 判定，Sword 无需改动）")

	# ---------- 斩杀 ----------
	_elite_killed = false
	_elite_score = 0
	e.killed.connect(_on_elite_probe)
	e.hp = 40
	e.hit(60, e.color)
	_ck(_elite_killed, "斩杀战将 -> 发出 killed 信号")
	_ck(_elite_score == EnemyCfg.ELITE_SCORE, "斩杀奖励 %d 分" % EnemyCfg.ELITE_SCORE)
	_ck(e.dead, "死亡标记已置位（清场判定据此放行）")
	await _frames(2)

	# ---------- 关卡接入 ----------
	var lv := Level.new()
	add_child(lv)
	lv._running = false      # 别让波次真的跑起来，只测生成与掉落
	await _frames(3)
	var n0 := _count_pickups(lv)
	lv.stage = 4                 # 战将也要拿关卡号：难度参数由 StageCfg 按关给出
	lv._spawn_elite(1.15, EnemyKind.E.WARRIOR)
	await _frames(3)
	var el := _find_elite(lv)
	_ck(el != null, "关卡可生成星盗战将")
	if el != null:
		# 回归闸：`Elite.stage` 必须由 Level 在 add_child **之前**注入。
		# 一旦漏写或写晚，GDScript 是**运行时静默失败**（值丢掉、不报错），
		# 战将的弹幕密度就会退回到第 1 关 —— 这种错肉眼根本看不出来。
		_ck(el.stage == 4, "战将拿到关卡号（实测 %d）" % el.stage)
		_ck(el.player_armors.size() == 2, "战将拿到玩家战甲（力场只从中抽取）")
		_ck(el.max_hp > EnemyCfg.ELITE_BASE_HP, "血量按波次系数缩放（第 2 波 %d）" % el.max_hp)
		_ck(lv._elite_alive(), "清场判定认得战将（在场即算未清空）")
		el.ward = 0
		el.hp = 1
		el.hit(50, el.color)
		await _frames(4)
		_ck(_count_pickups(lv) == n0 + 1, "斩杀战将必掉一件道具")
		_ck(not lv._elite_alive(), "战将阵亡后清场放行")
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 战将多色弹幕
## ⚠ 回归断言**必须写在本文件**（门禁只跑 `SelfTest.tscn`）——
##   `MatrixProbe.tscn` / `PaceProbe.tscn` / `WardDiag.tscn` 都是手动跑的独立场景，
##   写在里面的断言一次都不会执行（2026-09-22 已实测证实过一次）。
##
## 覆盖「战将弹幕多色化」（2026-09-22 主理人要求「精英怪要可以发出多色弹幕」）：
##   ① 色数逐关递进、前两关恒单色（教学期不混色）
##   ② ★ **可行性铁律**：力场色（那个必须换甲才破的色）恒 ∈ 玩家战甲 S
##   ③ 掺进来的第二色起 ∉ S —— 玩家吸不了，只能走位
##   ④ 力场色在齐射里恒占 ≥50%（「为主」的落点）
##   ⑤ 色序无重复、长度 = 本关色数、首位必是力场色
func _mk_elite(st: int, armors: Array[int], seq: int = 0) -> Elite:
	var e := Elite.new()
	e.stage = st                  # ★ add_child 之前注入（stage 决定弹幕色数）
	e.world = self
	add_child(e)
	e.player_armors = armors
	e.setup(1.0, 360.0, seq)
	return e


func _test_elite_hues() -> void:
	print("------ 战将多色弹幕 ------")
	var armors: Array[int] = [Game.RED, Game.WHITE]
	var comp := Level._complement(armors)

	# ---------- ① 配置层 ----------
	var f_seq := ""
	var cn := ""
	# ⚠ 关号是 1-based：`for s in STAGE_N` 是 0..4，会把 L1 算两遍、**L5 一次都问不到**
	#   （`_i()` 有 clampi 兜底不报错，所以静默少测一关）。这条今天已经踩第二次了。
	for s in range(1, StageCfg.STAGE_N + 1):
		var n := StageCfg.elite_hue_n(s)
		if not cn.is_empty():
			cn += " / "
		cn += "L%d:%d" % [s, n]
		if s > 1 and n < StageCfg.elite_hue_n(s - 1) and f_seq.is_empty():
			f_seq = "L%d(%d) < L%d(%d)" % [s, n, s - 1, StageCfg.elite_hue_n(s - 1)]
	_ck(f_seq.is_empty(), "色数逐关非递减（%s）" % cn + _bad(f_seq))
	_ck(StageCfg.elite_hue_n(1) == 1 and StageCfg.elite_hue_n(2) == 1,
		"前两关恒单色（教学期不混色，实测 %d / %d）"
			% [StageCfg.elite_hue_n(1), StageCfg.elite_hue_n(2)])
	_ck(StageCfg.elite_hue_n(3) == 2 and StageCfg.elite_hue_n(5) == 4,
		"L3 双色 / L5 四色（实测 %d / %d）"
			% [StageCfg.elite_hue_n(3), StageCfg.elite_hue_n(5)])

	# ---------- ②~⑤ 逐关 × 每关摇 24 只（色是随机的，只跑一次盖不住）----------
	var f_s := ""       # 铁律：力场色 ∉ S
	var f_len := ""     # 色序长度 / 首位
	var f_out := ""     # 掺进来的色落在 S 里（那就吸得掉了，不成其为骚扰色）
	var f_dup := ""     # 色序有重复
	var f_main := ""    # 力场色占比 < 50%
	for s in range(1, StageCfg.STAGE_N + 1):
		var want := StageCfg.elite_hue_n(s)
		for _rep in 24:
			# 力场色已改为**按出场序号**取（强制异色），不再随机 —— 要让两件战甲色
			# 都被覆盖到，就得自己轮 seq，否则 24 次全抽到同一色、等于只测了一半
			var e := _mk_elite(s, armors, _rep % armors.size())
			if not armors.has(e.color) and f_s.is_empty():
				f_s = "L%d 抽到 %s" % [s, Game.COLOR_CN[e.color]]
			if e._hues.size() != want and f_len.is_empty():
				f_len = "L%d 期望 %d 实测 %d" % [s, want, e._hues.size()]
			elif e._hues[0] != e.color and f_len.is_empty():
				f_len = "L%d 色序首位不是力场色（%s）" % [s, str(e._hues)]
			var seen := {}
			var n_s := 0    # 色序里 ∈ S 但非力场色的个数
			var n_c := 0    # 色序里 ∈ S' 的个数
			for i in e._hues.size():
				var c: int = e._hues[i]
				if seen.has(c) and f_dup.is_empty():
					f_dup = "L%d -> %s" % [s, str(e._hues)]
				seen[c] = true
				if i <= 0:
					continue
				if armors.has(c):
					n_s += 1
					# 玩家的副甲色只在色数 > 1+|S'| 时才够数动用，且**只能补在末尾**
					if i != e._hues.size() - 1 and f_out.is_empty():
						f_out = "L%d 第 %d 色 %s ∈ S 却不在末尾（%s）" \
							% [s, i + 1, Game.COLOR_CN[c], str(e._hues)]
				else:
					n_c += 1
			# 掺色优先用 S'：能用几个用几个，不够数才轮到玩家的副甲色
			var want_c := mini(want - 1, comp.size())
			if n_c != want_c and f_out.is_empty():
				f_out = "L%d 掺了 %d 个 S' 色，应为 %d（%s）" % [s, n_c, want_c, str(e._hues)]
			if n_s > 1 and f_out.is_empty():
				f_out = "L%d 混入 %d 个 ∈ S 的非力场色（最多 1 个）" % [s, n_s]
			# 力场色占比：七向扇射（7 发）与十四向环（14 发）两种齐射都验
			for total in [7, 14]:
				var main := 0
				for i in total:
					if e._shot_color(i) == e.color:
						main += 1
				if main * 2 < total and f_main.is_empty():
					f_main = "L%d 齐射 %d 发中力场色仅 %d 发" % [s, total, main]
			e.queue_free()
	await _frames(3)
	_ck(f_s.is_empty(), "★ 可行性铁律：战将力场色恒 ∈ 玩家战甲 S" + _bad(f_s))
	_ck(f_len.is_empty(), "色序长度 = 本关色数，且首位必是力场色" + _bad(f_len))
	_ck(f_out.is_empty(), "掺色优先用 S'（吸不了，逼走位）；副甲色仅补在末尾（S' = %s）"
		% _armor_cn(comp) + _bad(f_out))
	_ck(f_dup.is_empty(), "色序内无重复色" + _bad(f_dup))
	_ck(f_main.is_empty(), "力场色在齐射中恒占 ≥50%（「为主」的落点）" + _bad(f_main))

	# ---------- 同关多只精英强制「相邻」异色 ----------
	# 力场色改按出场序号取 S 的第 seq 色。随机抽的话约半数局两只同色 ——
	# 玩家一件甲打穿两场，「换甲」恰恰在最需要它的那两波上被稀释。
	# ⚠ 四只精英上线后，同关精英数已不止两只（实测 L2×2 / L3×3 / L4×3 / L5×4），
	#   而 |S| = 2 —— seq 轮转下第 1、3 只必然同色，**全互异在数学上不可能**。
	#   这里守的是「相邻两只异色」：换甲的紧迫感来自「下一只换了色」，不是全场不重色。
	var f_pair := ""
	var f_pair_s := ""
	var pair_cn := ""
	for s in range(1, StageCfg.STAGE_N + 1):
		var n_e := 0
		for n in range(1, StageCfg.waves(s) + 1):
			if StageCfg.wave_elite(s, n):
				n_e += 1
		if n_e < 2:
			continue
		if not pair_cn.is_empty():
			pair_cn += " / "
		pair_cn += "L%d×%d" % [s, n_e]
		# 采样 30 次：确定性分配每次都必异色；改回随机则 30 次里几乎必有一次撞同色
		for _rep in 30:
			var ea := _mk_elite(s, armors, 0)
			var eb := _mk_elite(s, armors, 1)
			if not armors.has(ea.color) and f_pair_s.is_empty():
				f_pair_s = "L%d 第 1 只抽到 %s ∉ S" % [s, Game.COLOR_CN[ea.color]]
			if not armors.has(eb.color) and f_pair_s.is_empty():
				f_pair_s = "L%d 第 2 只抽到 %s ∉ S" % [s, Game.COLOR_CN[eb.color]]
			if ea.color == eb.color and f_pair.is_empty():
				f_pair = "L%d 两只战将同为 %s" % [s, Game.COLOR_CN[ea.color]]
			ea.queue_free()
			eb.queue_free()
		# 接线：Level 必须真的把递增的序号传下去（只改 Elite 不改 Level，这里就会红）
		var lv := Level.new()
		lv.stage = s
		add_child(lv)
		lv._running = false
		await _frames(3)
		for _k in n_e:
			lv._spawn_elite(1.0, EnemyKind.E.WARRIOR)
		await _frames(2)
		var cs: Array[int] = []
		for ch in lv.get_children():
			if ch is Elite:
				cs.append((ch as Elite).color)
		if cs.size() != n_e and f_pair.is_empty():
			f_pair = "L%d 期望 %d 只战将实测 %d" % [s, n_e, cs.size()]
		# 相邻异色（|S| = 2 时全互异不可能，隔一只同色是设计内的）
		for i in range(1, cs.size()):
			if cs[i] == cs[i - 1] and f_pair.is_empty():
				f_pair = "L%d 第 %d 只与第 %d 只同色（%s）" % [s, i, i + 1, str(cs)]
		lv.queue_free()
		await _frames(2)
	await _frames(3)
	_ck(f_pair.is_empty(), "同关多只精英强制「相邻」异色（涉及 %s）" % pair_cn + _bad(f_pair))
	_ck(f_pair_s.is_empty(), "强制异色不改铁律：每只战将力场色仍 ∈ S" + _bad(f_pair_s))


# ------------------------------------------------------------ 新精英（堡垒 / 指挥 / 护盾）
## 2026-09-22 主理人要求「增加精英怪」新增三只。这里守：
##   ① 三只都能生成、色防色恒 ∈ 玩家战甲 S（可行性铁律，与战将同口径）
##   ② 弹幕堡垒将：无护罩，任意色都能全额打本体（纯 DPS 检验）
##   ③ 护盾冲锋将：★ 朝向护盾方向判定 —— 正面（玩家在左）异色打在护盾上、
##      侧面（玩家上/下）全额打本体。**锁死护盾方向 bug**（曾漏负号导致护盾形同虚设）。
func _mk_elite_type(st: int, armors: Array[int], etype: int) -> EliteBase:
	match etype:
		EnemyKind.E.BASTION:
			var b := EliteBastion.new()
			b.stage = st
			b.world = self
			add_child(b)
			b.player_armors = armors
			b.setup(1.0)
			return b
		EnemyKind.E.SWARM:
			var s2 := EliteSwarm.new()
			s2.stage = st
			s2.world = self
			add_child(s2)
			s2.player_armors = armors
			s2.setup(1.0)
			return s2
		EnemyKind.E.AEGIS:
			var a := EliteAegis.new()
			a.stage = st
			a.world = self
			add_child(a)
			a.player_armors = armors
			a.setup(1.0)
			return a
	return null


func _test_elite_new() -> void:
	print("------ 新精英（堡垒 / 指挥 / 护盾）------")
	var armors: Array[int] = [Game.RED, Game.WHITE]

	# ---------- ① 可行性铁律：三只色防色恒 ∈ S ----------
	var f_s := ""
	for st in range(1, StageCfg.STAGE_N + 1):
		for et in [EnemyKind.E.BASTION, EnemyKind.E.SWARM, EnemyKind.E.AEGIS]:
			var e := _mk_elite_type(st, armors, et)
			if e == null:
				continue
			if not armors.has(e.color) and f_s.is_empty():
				f_s = "L%d %s 色 %s ∉ S" % [st, et, Game.COLOR_CN[e.color]]
			e.queue_free()
	_ck(f_s.is_empty(), "★ 可行性铁律：新精英色防色恒 ∈ 玩家战甲 S" + _bad(f_s))

	# ---------- ② 弹幕堡垒将：无护罩，异色也全额打本体 ----------
	var b := _mk_elite_type(3, armors, EnemyKind.E.BASTION) as EliteBastion
	if b != null:
		var off := (b.color + 1) % 4
		var hp0 := b.hp
		b.hit(100, off)
		_ck(hp0 - b.hp == 100, "堡垒将无护罩：异色全额打本体（100 -> 掉 %d）" % (hp0 - b.hp))
		var hp_after_off := b.hp
		b.hit(100, b.color)
		# 堡垒将无护罩：同色走正常 +50%% 加成（100 -> 150），异色全额（100）。
		# 这里专门确认「同色不叠加任何护盾/护罩逻辑」——就是纯粹的 +50%%。
		# ⚠ 文案里的 % 必须写成 %%%%（GDScript % 格式化会把裸 % 当格式符，报 String formatting error）。
		_ck(hp_after_off - b.hp == 150, "堡垒将同色 +50%% 全额（无护罩，不叠加护盾逻辑，掉 %d）" % (hp_after_off - b.hp))
		b.queue_free()

	# ---------- ③ 护盾冲锋将：朝向护盾方向判定（锁死方向 bug）----------
	var a := _mk_elite_type(4, armors, EnemyKind.E.AEGIS) as EliteAegis
	if a != null:
		a.position = Vector2(600.0, 300.0)
		a.ward = a.ward_max
		var w0 := a.ward
		var h0 := a.hp
		# 模拟「玩家在正面（左方）」：护盾存续时异色应打在护盾上（本体不掉血）
		var off := (a.color + 1) % 4
		a.player_ref = _elite_dummy_player(Vector2(100.0, 300.0))
		a.hit(100, off)
		_ck(a.hp == h0, "护盾冲锋将：正面（玩家在左）异色打在护盾上，本体不掉血")
		_ck(a.ward < w0, "护盾冲锋将：正面异色消耗护盾（ward %d -> %d）" % [w0, a.ward])
		# 正面同色破盾更快（+50%）
		var w1 := a.ward
		a.hit(100, a.color)
		_ck(a.ward < w1, "护盾冲锋将：正面同色破盾更快（ward %d -> %d）" % [w1, a.ward])
		# 模拟「玩家在侧面（正上方）」：绕开护盾锥，全额打本体
		a.ward = a.ward_max
		var h1 := a.hp
		a.player_ref = _elite_dummy_player(Vector2(600.0, 100.0))
		a.hit(100, off)
		_ck(a.hp < h1, "护盾冲锋将：侧面（玩家上/下）绕开护盾，全额打本体（掉 %d）" % (h1 - a.hp))
		# 变异闸：正面异色若被误判成绕背，本体就会掉血 —— 这条专门抓「漏负号」回归
		a.player_ref = _elite_dummy_player(Vector2(100.0, 300.0))
		a.ward = a.ward_max
		var h2 := a.hp
		a.hit(100, off)
		_ck(a.hp == h2, "护盾冲锋将：正面异色绝不穿透到本体（方向判定回归闸）")
		a.queue_free()

	# ---------- 指挥将：能生成、色 ∈ S 已在 ① 覆盖；召唤走硬闸，这里只验本体可全额打 ----------
	var s2 := _mk_elite_type(3, armors, EnemyKind.E.SWARM) as EliteSwarm
	if s2 != null:
		var hs0 := s2.hp
		s2.hit(100, s2.color)
		_ck(s2.hp < hs0, "指挥将本体可被全额打（无护罩，召唤机制不影响本体受伤）")
		s2.queue_free()


## 造一个孤立的 Player 当「玩家位置参照」—— Aegis 的朝向判定只读 player_ref.position
func _elite_dummy_player(pos: Vector2) -> Player:
	var p := Player.new()
	add_child(p)
	# ⚠ position 必须在 add_child **之后**设：Player._ready() 会把 position 重置到 (230, 中)。
	#   若写在 add_child 前，_ready 会覆盖掉，导致 Aegis 朝向判定读到错误来向（2026-09-22 修）。
	p.position = pos
	return p


# ------------------------------------------------------------ 矢量活体静态检查（07 §2.4）
## 覆盖 PirateArt.gd（星盗喽啰 / 星盗战将）与 Boss.gd（星盗旗舰）的矢量渲染路径。
## V1 是主通道（舱盖色的有无）的活体保证，最高优先；V0/V2/V3/V4 守其余通道。
## 配置集中化的回归网 —— **数值只能住在 Cfg 里**。
## 三条：
##   ① 实体文件不许再自己定义数值常量（源码级扫描，防有人图省事往回加）；
##   ② 飘字 / 说明文案由配置现拼（改了 ATK_STEP，文案必须跟着变）；
##   ③ 同值双源已消除（雷的寿命、每波掉落数各只剩一处）。
func _test_cfg_source() -> void:
	print("------ 配置集中 ------")
	var rules: Array[String] = [
		"res://scripts/entities/Player.gd|const MAX_HP",
		"res://scripts/entities/Player.gd|const ATK_STEP",
		"res://scripts/entities/Player.gd|const HEAT_MAX",
		"res://scripts/entities/Pickup.gd|const LIFE",
		"res://scripts/entities/Pickup.gd|const WEIGHT",
		"res://scripts/entities/Elite.gd|const BASE_HP",
		"res://scripts/entities/Elite.gd|const WARD_HP",
		"res://scripts/entities/EnemyBrain.gd|const MARTYR_DMG",
		"res://scripts/entities/EnemyBrain.gd|const DEFECTOR_SWAP",
		"res://scripts/entities/BossMine.gd|const LIFE",
		"res://scripts/entities/Boss.gd|const HEAT_BLAST_DMG",
		"res://scripts/world/Level.gd|const WAVE_DROP",
		"res://scripts/world/Level.gd|const MAX_RUN",
	]
	var f_def := ""
	for r in rules:
		var parts := r.split("|")
		var src := _read(parts[0])
		if src.is_empty():
			if f_def.is_empty():
				f_def = "读不到 " + parts[0]
			continue
		if src.contains(parts[1]) and f_def.is_empty():
			f_def = "%s 仍定义「%s」—— 数值应迁到 Cfg" % [parts[0].get_file(), parts[1]]
	_ck(f_def.is_empty(), "实体文件不再自带数值常量（PlayerCfg / PickupCfg / EnemyCfg 是唯一来源）"
		+ _bad(f_def))

	# ② 文案由配置派生：改了配置，飘字与说明必须同时跟着变
	var tip_atk := PickupCfg.tip(Pickup.T.ATK)
	_ck(tip_atk == "攻击 +%d%%" % int(roundf(PlayerCfg.ATK_STEP * 100.0)),
		"增幅核心飘字由配置派生（实测「%s」）" % tip_atk)
	_ck(PickupCfg.tip(Pickup.T.HEAL) == "生命 +%d" % PlayerCfg.HEAL_AMOUNT, "修复包飘字同源")
	# 手册要守的是「**调用了 tip()**」这个事实，而不是拼出来的字符串 ——
	# 只比字符串的话，写死一个当前同值的文案照样绿。
	var help_src := _read("res://scripts/ui/HelpScreen.gd")
	_ck(help_src.contains("PickupCfg.tip(Pickup.T.ATK)"),
		"作战手册的道具条目由 PickupCfg.tip 现拼（不写死数值）")
	var help_line := ""
	for sec in HelpScreen._build_sections():
		var lines: Array = sec["l"]
		for line in lines:
			var s := str(line)
			if s.contains("增幅核心"):
				help_line = s
	_ck(help_line.contains(tip_atk),
		"作战手册实测条目与配置一致（「%s」）" % help_line)

	# ③ 双源已消除
	_ck(is_equal_approx(EnemyCfg.MINE_LIFE, 8.0)
		and not _read("res://scripts/entities/EnemyBrain.gd").contains("LAYER_MINE_LIFE"),
		"雷的寿命单一来源（EnemyCfg.MINE_LIFE = %.0f 秒）" % EnemyCfg.MINE_LIFE)
	_ck(StageCfg.wave_drop(1) == 1
		and not _read("res://scripts/world/Level.gd").contains("WAVE_DROP"),
		"每波刷新道具数单一来源（StageCfg.wave_drop）")


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## 去掉 GDScript 行内注释（保留字符串内的 #），供 V1 只扫真实代码 / 字面量。
## GDScript 无块注释，行注释一律从首个未入串的 # 起到行尾。
func _strip_comments(text: String) -> String:
	var out := ""
	for ln in text.split("\n"):
		var in_str := false
		var cut := ln.length()
		var i := 0
		while i < ln.length():
			var ch := ln[i]
			if ch == "\"":
				in_str = not in_str
			elif ch == "#" and not in_str:
				cut = i
				break
			i += 1
		out += ln.substr(0, cut) + "\n"
	return out


## V1：源码（去注释后）不得出现 CANOPY 舱盖色 —— 三通道同时匹配。
## 命中即 fail（敌方一致：星盗喽啰 / 星盗旗舰都没有驾驶舱）。
## 注：头部注释里解释规则用的色值/常量名会被 _strip_comments 去掉，不误判。
func _canopy_hits(text: String) -> int:
	var code := _strip_comments(text)
	var hits := 0
	# 通道一：CANOPY 常量引用 / 8-bit 字面量 (158,219,250)
	if code.contains("CANOPY") or code.contains("158,219,250") or code.contains("158, 219, 250"):
		hits += 1
	# 通道二：逐个 Color(...) 字面量比对 (0.62,0.86,0.98) 容差 0.02
	var re := RegEx.new()
	re.compile("Color\\s*\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)")
	for m in re.search_all(code):
		var r := float(m.get_string(1))
		var g := float(m.get_string(2))
		var b := float(m.get_string(3))
		var d := sqrt((r - 0.62) * (r - 0.62) + (g - 0.86) * (g - 0.86) + (b - 0.98) * (b - 0.98))
		if d < 0.02:
			hits += 1
	return hits


## 截取某个 static func 的函数体（从签名行到下一个同级 func 之前）
func _func_body(text: String, name: String) -> String:
	var key := "func " + name
	var i := text.find(key)
	if i < 0:
		return ""
	var start := i
	var j := text.find("\nfunc ", start + 1)
	if j < 0:
		j = text.length()
	return text.substr(start, j - start)


## V2：以 CORE 色（k）为锚的绘制调用，锚点 x 必须 < 0（朝向指针只指 −X）。
## 逐行扫描：凡是用 k 作色的行，其 Vector2 / Rect2 坐标 x 必须 < 0。
## 只用于 PirateArt 的 draw_minion / draw_elite（Boss 核心居中对称，不在 V2 范围）。
func _cores_left(text: String) -> bool:
	for ln in text.split("\n"):
		var uses_k := ln.contains(", k)") or ln.contains("Color(k") or ln.contains(", k,")
		if not uses_k:
			continue
		var re := RegEx.new()
		re.compile("(?:Vector2|Rect2)\\s*\\(\\s*(-?[0-9.]+)")
		for m in re.search_all(ln):
			var x := float(m.get_string(1))
			if x >= 0.0:
				return false
	return true


## V4-a：星盗喽啰主体多边形（BODY_*）顶点半径 ≤ 22（碰撞 19 的擦弹余量）。
func _minion_budget() -> bool:
	for body in [PirateArt.BODY_RED, PirateArt.BODY_BLUE, PirateArt.BODY_YELLOW]:
		for v in body:
			if v.length() > 22.0:
				return false
	return true


## V4-b：星盗战将 draw_elite 内所有顶点 / 矩形角点半径 ≤ 40（力场弧内缘 43 留 3px）。
func _elite_budget(body: String) -> bool:
	var vmax := 0.0
	var re_v := RegEx.new()
	re_v.compile("Vector2\\s*\\(\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)")
	for m in re_v.search_all(body):
		vmax = maxf(vmax, Vector2(float(m.get_string(1)), float(m.get_string(2))).length())
	var re_r := RegEx.new()
	re_r.compile("Rect2\\s*\\(\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)")
	for m in re_r.search_all(body):
		var x := float(m.get_string(1))
		var y := float(m.get_string(2))
		var w := float(m.get_string(3))
		var h := float(m.get_string(4))
		vmax = maxf(vmax, Vector2(x, y).length())
		vmax = maxf(vmax, Vector2(x + w, y + h).length())
	return vmax <= 40.0


## V3：星盗战将顶带 PYLON_F / PYLON_R 在探针行 y=−30 求交 → 2 段、每段有实宽、gap ≥ 20，
## 且无顶点恰好落在探针行上（否则读作单峰，通道③失效）。
func _elite_top_separation(body: String) -> bool:
	# 抓出 draw_elite 里所有 _poly([...]) 多边形字面量，挑含顶冠尖（y ≤ −33）的两个当挂架
	var polys: Array = []
	var re := RegEx.new()
	re.compile("_poly\\s*\\(\\s*\\[([^\\]]+)\\]")
	for m in re.search_all(body):
		var pts := _parse_vec2_array(m.get_string(1))
		if pts.is_empty():
			continue
		var has_tip := false
		for v in pts:
			if v.y <= -33.0:
				has_tip = true
		if has_tip:
			polys.append(pts)
	if polys.size() < 2:
		return false
	# 对每个挂架多边形求与 y=−30 的交点区间
	var intervals: Array = []
	for pts in polys:
		var xs := []
		for i in pts.size():
			# polys 是未类型化 Array，循环变量 pts 会退化成 Variant；
			# 下标取值必须显式标注类型，否则 `:=` 推断不出来（本项目已知坑）
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y < -30.0) == (b.y < -30.0):
				continue          # 两端在探针行同侧（或恰在线上）→ 不穿越
			if absf(a.y - (-30.0)) < 0.001 or absf(b.y - (-30.0)) < 0.001:
				return false      # 顶点恰好落在探针行 → 判失败
			var t := (-30.0 - a.y) / (b.y - a.y)
			xs.append(a.x + t * (b.x - a.x))
		if xs.size() >= 2:
			xs.sort()
			intervals.append({"lo": xs[0], "hi": xs[xs.size() - 1]})
	if intervals.size() < 2:
		return false
	# 取最靠上的两段（顶带），每段须有实宽（≥ 3），两段 gap ≥ 20
	intervals.sort_custom(func(p, q): return p["hi"] < q["hi"])
	var top2: Array = intervals.slice(0, 2)
	for iv in top2:
		if float(iv["hi"] - iv["lo"]) < 3.0:
			return false
	var gap := float(top2[1]["lo"] - top2[0]["hi"])
	return gap >= 20.0


## 解析 "[Vector2(x,y), Vector2(x,y), ...]" 字面量为 Vector2 数组
## ⚠ 返回类型必须写成 Array[Vector2]：未类型化 Array 的下标是 Variant，
##   下游 `var a := pts[i]` 会当场报「Cannot infer the type」（本项目已知坑）。
func _parse_vec2_array(s: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var re := RegEx.new()
	re.compile("Vector2\\s*\\(\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)")
	for m in re.search_all(s):
		out.append(Vector2(float(m.get_string(1)), float(m.get_string(2))))
	return out


func _test_vector_static() -> void:
	print("------ vector static (07 §2.4) ------")
	var pa := _read("res://scripts/art/PirateArt.gd")
	var boss := _read("res://scripts/entities/Boss.gd")
	var bossart := _read("res://scripts/art/BossArt.gd")   # Boss 真正的矢量绘制现走 BossArt
	_ck(not pa.is_empty() and not boss.is_empty() and not bossart.is_empty(),
		"矢量静态检查：读到 PirateArt.gd / Boss.gd / BossArt.gd 源码")
	if pa.is_empty() or boss.is_empty() or bossart.is_empty():
		return
	# V1 ⭐ 主通道：CANOPY 舱盖色禁入敌方矢量
	# BossArt 的规则说明注释里会出现 CANOPY 字面量 —— _canopy_hits 内置注释剥离器，
	# 只扫去注释后的真实代码 / Color 字面量，不误判头部规则说明。
	_ck(_canopy_hits(pa) == 0, "V1 PirateArt 无 CANOPY 舱盖色（敌方一致，主通道活体保证）")
	_ck(_canopy_hits(boss) == 0, "V1 Boss 无 CANOPY 舱盖色（星盗旗舰 · 敌方一致）")
	_ck(_canopy_hits(bossart) == 0, "V1 BossArt 无 CANOPY 舱盖色（五关 Boss 矢量主路径）")
	# V0 颜色可辨识：MAIN 实心块底线
	var dminion := _func_body(pa, "draw_minion")
	var delite := _func_body(pa, "draw_elite")
	_ck(dminion.find("Game.COLOR_MAIN") >= 0, "V0 draw_minion 有不透明 MAIN 实心块")
	_ck(delite.find("Game.COLOR_MAIN") >= 0, "V0 draw_elite 有不透明 MAIN 实心块")
	# V2 朝向：CORE 锚点全在 −X
	_ck(_cores_left(pa), "V2 星盗喽啰 / 战将 CORE 锚点全在 −X（朝向指针）")
	# V4 体量：剪影预算
	_ck(_minion_budget(), "V4 星盗喽啰主体 r ≤ 22（碰撞 19 擦弹余量）")
	_ck(_elite_budget(delite), "V4 星盗战将 r ≤ 40（力场弧内缘 43 留 3px）")
	# V3 顶层轮廓：顶带双分离
	_ck(_elite_top_separation(delite), "V3 战将顶带探针行 y=−30 双分离（2 段 · gap ≥ 20）")
	# V5 逐关擦弹余量（07 §1.8 v4，Boss 五关专用）：单位剪影最远角半径 × R_MAIN / R_HIT ≤ 1.34
	_ck(_boss_clearance_ratio(bossart),
		"V5 Boss 五关擦弹余量比 ≤ 1.34（最远角 × R_MAIN ÷ R_HIT）")
	# V5b 屏幕安全：器官外缘 ≤ 295px（Boss 常驻 x=985，右缘不越 1280）
	_ck(_boss_screen_safe(bossart),
		"V5b Boss 器官外缘 ≤ 295px（常驻 x=985 不越屏右 1280）")
	# V6 节点比例化（07 §1.8 v4）：反应堆节点不得写死 17.0/11.0，须走 rr_big/rr_small
	_ck(boss.contains("rr_big") and boss.contains("rr_small"),
		"V6 Boss 反应堆节点已比例化（rr_big / rr_small 存在）")
	_ck(not (boss.contains("17.0 if i == ward") or boss.contains("17.0 if i==ward")),
		"V6 Boss 反应堆节点无写死 17.0/11.0")
	# V7 外挂件贴装（07 §2.4，L3 炮垒专用）：bx / 炮塔间距 / 装甲带必须跟着 SIL_BATTERY 联动，
	#   否则动剪影忘挂件就画断件（炮塔悬空、炮塔出舷、装甲带越界）。三条判据一次算清。
	_ck(_boss_attachments(bossart),
		"V7 L3 炮垒外挂件贴装（bx=−X顶点 / 炮塔不出舷 / 装甲带内缩不越界）")


## V5：Boss 五关擦弹余量比。取每关单位剪影（SIL_*）的最远角半径，
##   × StageCfg.boss_r_main(s) ÷ StageCfg.boss_r_hit(s)，五关各算一次，一律 ≤ 1.34。
##   剪影是「单位半径 1 = R_MAIN」，运行时乘 r，故最远角半径 = max(length(v)) × R_MAIN。
##   ⚠ 口径：V5 量的是 SIL_* **本体多边形**（顶点外接半径），**不含** draw_body 外那层
##     r×1.06~1.07 的暗色描边（`draw_colored_polygon(_poly(SIL_*, r*1.06), dk)`）——
##     描边才是玩家看到的真正外缘，含描边实际视觉死区约再大 6~7%（L3 修完约 1.28）。
##     五关口径一致（都只算本体），1.28 仍在 1.34 以内，故先不改口径；后来人勿误读成含描边。
##   L3 SIL_BATTERY 已等比缩 ×0.8285（team-lead 终裁坐标），收角后余量比 ≈1.206，全五关通过。
func _boss_clearance_ratio(bossart: String) -> bool:
	# 五关顺序对应 SIL_ 与逐关标量（与 StageCfg 下标 0=第1关 一致）
	var sil_names := ["SIL_CORE", "SIL_WING", "SIL_BATTERY", "SIL_MAW", "SIL_THRONE"]
	var r_main := [56.0, 63.0, 70.0, 77.0, 84.0]
	var r_hit := [46.0, 52.0, 58.0, 65.0, 70.0]
	const LIMIT := 1.34
	var worst := 0.0
	var worst_s := -1
	for s in 5:
		var rmax := _sil_max_radius(bossart, sil_names[s])
		if rmax <= 0.0:
			return false   # 剪影没解析到 → 视为失败
		var ratio: float = rmax * r_main[s] / r_hit[s]
		if ratio > worst:
			worst = ratio
			worst_s = s   # 只在刷新最大值时更新，避免循环结束恒等于 4
		if ratio > LIMIT:
			return false
	print("    [V5] 最紧关 L%d 余量比 = %.3f（≤ %.2f）" % [worst_s + 1, worst, LIMIT])
	return true


## V5b：屏幕安全。取每关单位剪影的最大 +X 外突（×1.07 描边外缘），
##   × R_MAIN 必须 ≤ 295px（Boss 常驻 x=985，右缘 985+295=1280=VIEW_W）。
func _boss_screen_safe(bossart: String) -> bool:
	var sil_names := ["SIL_CORE", "SIL_WING", "SIL_BATTERY", "SIL_MAW", "SIL_THRONE"]
	var r_main := [56.0, 63.0, 70.0, 77.0, 84.0]
	const MAX_OUT := 295.0
	for s in 5:
		var maxx := _sil_max_x(bossart, sil_names[s])
		if maxx <= 0.0:
			return false
		# ×1.07 = draw_body 描边外缘（BossArt 里 _poly(SIL_*, r*1.06/1.07)）
		var out: float = maxx * r_main[s] * 1.07
		if out > MAX_OUT:
			return false
	return true


## 解析 BossArt 里 `const SIL_NAME := [ Vector2(...), ... ]` 的最远角半径（顶点长度最大值）。
func _sil_max_radius(text: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("const\\s+" + name + "\\s*:=\\s*\\[([^\\]]+)\\]")
	var m := re.search(text)
	if m == null:
		return 0.0
	var vmax := 0.0
	for v in _parse_vec2_array(m.get_string(1)):
		vmax = maxf(vmax, v.length())
	return vmax


## 同上，但取最大 +X 外突（x 分量最大值），供 V5b 屏幕安全用。
func _sil_max_x(text: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("const\\s+" + name + "\\s*:=\\s*\\[([^\\]]+)\\]")
	var m := re.search(text)
	if m == null:
		return 0.0
	var maxx := 0.0
	for v in _parse_vec2_array(m.get_string(1)):
		maxx = maxf(maxx, v.x)
	return maxx


## V7：L3 炮垒外挂件贴装检查（07 §2.4）。bx / 炮塔间距 / 装甲带三处挂件必须跟着
##   SIL_BATTERY 联动 —— 动剪影忘挂件就画断件（炮塔悬空、炮塔出舷、装甲带越界）。
##   bx / off / 装甲带都是函数局部变量，拿不到常量，只能源码文本扫描（_func_body 够用）。
##   三条判据：
##     ① _turret 的 bx 系数 = SIL_BATTERY 的 −X 顶点 x（贴装面不悬空）
##     ② 炮塔间距 (base+step·(n/2−1))+0.055 ≤ 舷半高（−X 顶点 |y|），按 n=4/6/8 三档各算
##     ③ 装甲带 x0 > −X 顶点 x（内缩）且右端 x0+w < 舰体右界（max x）
func _boss_attachments(bossart: String) -> bool:
	# 解析 SIL_BATTERY 的 −X 顶点 x（最小 x）、右界（最大 x）、−X 顶点 |y|（舷半高）
	var re_sil := RegEx.new()
	re_sil.compile("const\\s+SIL_BATTERY\\s*:=\\s*\\[([^\\]]+)\\]")
	var ms := re_sil.search(bossart)
	if ms == null:
		return false
	var minx := 0.0
	var maxx := 0.0
	var half_h := 0.0
	var first := true
	for v in _parse_vec2_array(ms.get_string(1)):
		if first:
			minx = v.x
			maxx = v.x
			first = false
		minx = minf(minx, v.x)
		maxx = maxf(maxx, v.x)
		if absf(v.x - minx) < 0.001:
			half_h = maxf(half_h, absf(v.y))   # −X 顶点 |y| = 舷半高
	# ① _turret 的 bx 系数必须 = −X 顶点 x
	var bt := _func_body(bossart, "_turret")
	var re_bx := RegEx.new()
	re_bx.compile("bx\\s*:=\\s*(-?[0-9.]+)\\s*\\*\\s*r")
	var mb := re_bx.search(bt)
	if mb == null:
		return false
	if absf(float(mb.get_string(1)) - minx) > 0.001:
		return false
	# ② _l3_guns 炮塔间距：按 n=4/6/8 三档，(base+step·(n/2−1))+0.055 ≤ 舷半高
	var bl := _func_body(bossart, "_l3_guns")
	var re_off := RegEx.new()
	re_off.compile("\\(\\s*([0-9.]+)\\s*\\+\\s*([0-9.]+)\\s*\\*\\s*float\\(j\\)\\s*\\)")
	var mo := re_off.search(bl)
	if mo == null:
		return false
	var base := float(mo.get_string(1))
	var step := float(mo.get_string(2))
	for n in [4, 6, 8]:
		var tip: float = base + step * float(n / 2 - 1) + 0.055
		if tip > half_h + 0.001:
			return false
	# ③ 装甲带：x0 > −X 顶点 x（内缩）且右端 x0+w < 舰体右界
	var bd := _func_body(bossart, "draw_battery")
	var re_arm := RegEx.new()
	re_arm.compile("Rect2\\(\\s*(-?[0-9.]+)\\s*\\*\\s*r\\s*,\\s*yy\\s*,\\s*([0-9.]+)\\s*\\*\\s*r")
	var ma := re_arm.search(bd)
	if ma == null:
		return false
	var x0 := float(ma.get_string(1))
	var w := float(ma.get_string(2))
	if x0 <= minx:        # 必须内缩（x0 在 −X 顶点内侧，更不负）
		return false
	if x0 + w > maxx:     # 右端不越舰体右界
		return false
	return true


# ------------------------------------------------------------ 术语红线
## 科幻改版后旧称一律作废。这条扫描把「改一个漏一片」钉成硬失败。
## 注：禁用词用**拼接**书写 —— 否则本文件自己就会命中自己。
##
## ⚠ 已知的「合法同形词」，别照关键词结果误删：
##   · `StageSelect._phase_cn()` 返回「三阶段」= **Boss 阶段数**，与关卡数无关
##   · `Level.gd` 顶部与 `_wave_colors` 注释里的「三波」= L1 确实只有 3 波
##   · `StageCfg` / `Game` 注释里的「三档」= 品阶三档 / 旧难度三档，都是史实陈述
## 判断口径：**关卡数**一律以 `StageCfg.STAGE_N`（= 5）为准；
## 其余「三」若指阶段 / 波次 / 品阶 / 旧档，先核语义再动手。
func _test_wording() -> void:
	print("------ wording ------")
	var banned := ["母舰" + "核心", "无人" + "兵器"]
	var paths := _script_paths()
	_ck(paths.size() >= 20, "术语扫描：枚举到 %d 个 .gd 源文件" % paths.size())
	var hits: Array[String] = []
	for p in paths:
		var t := _read(p)
		if t.is_empty():
			continue
		for w in banned:
			if t.contains(w):
				hits.append("%s（%s）" % [p, w])
	_ck(hits.is_empty(), "全库 %d 个 .gd 无旧称（命中 %d 处：%s）"
		% [paths.size(), hits.size(), "、".join(hits)])


## 递归枚举 res://scripts 与 res://_selftest 下的全部 .gd 源文件
func _script_paths() -> Array[String]:
	var out: Array[String] = []
	_collect_scripts("res://scripts", out)
	_collect_scripts("res://_selftest", out)
	return out


func _collect_scripts(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			var full := dir + "/" + n
			if d.current_is_dir():
				_collect_scripts(full, out)
			elif n.ends_with(".gd"):
				out.append(full)
		n = d.get_next()
	d.list_dir_end()


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
	Game.picked_armors = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	_ck(lv.player != null and is_instance_valid(lv.player), "关卡创建玩家")
	_ck(lv.hud != null, "关卡创建 HUD")
	_ck(lv.player.armors.size() == 2, "玩家携带两件战甲")

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

	# _enemy_count 是「全场计数」（不做视野过滤）：必须能看到 hover 骚扰敌飞出右边界
	# 后的自我回收，否则每波都会白等清场上限。这里跑一遍真实离场流程验证计数归零。
	var lv2 := Level.new()
	add_child(lv2)
	await _frames(3)
	lv2._running = false
	for ch in lv2.get_children():
		if ch is Enemy:
			(ch as Enemy).queue_free()
	await _frames(3)
	var hpats: Array[String] = ["straight", "sine"]
	lv2._spawn_enemy(1.0, Game.BLUE, Game.BLUE, hpats)   # c == harass -> 强制 hover
	var n_before := lv2._enemy_count()
	for ch in lv2.get_children():
		if ch is Enemy:
			(ch as Enemy)._life = 3.5          # 低于 4 秒 -> 下一帧转入离场
			(ch as Enemy).position.x = Game.VIEW_W - 120.0
	Engine.time_scale = 4.0
	await _frames(40)
	Engine.time_scale = 1.0
	var n_after := lv2._enemy_count()
	_ck(n_before == 1 and n_after == 0,
		"hover 骚扰敌离场后 _enemy_count 归零（离场前 %d / 离场后 %d）" % [n_before, n_after])
	lv2.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 星袭「同色潮」配色
## 断言文案里挂反例组合；没反例就返回空串
func _bad(s: String) -> String:
	if s.is_empty():
		return ""
	return "  <- 反例 " + s


func _armor_cn(armors: Array[int]) -> String:
	var s := ""
	for c in armors:
		if not s.is_empty():
			s += " + "
		s += Game.COLOR_CN[c]
	return s


## 五关计分倍率串（只在断言消息里用，不参与判定）
func _mul_cn() -> String:
	var s := ""
	for i in StageCfg.STAGE_N:
		if not s.is_empty():
			s += " < "
		s += "%.2f" % StageCfg.score_multiplier(i + 1)
	return s


## 目标色序列是否严格在 a / b 两色之间交替（序列里不含骚扰色）
func _strict_alt(tgt: Array[int], a: int, b: int) -> bool:
	for c in tgt:
		if c != a and c != b:
			return false
	for i in tgt.size() - 1:
		if tgt[i] == tgt[i + 1]:
			return false
	return true


## 配色随玩家战甲 S 对称生成：目标色 ∈ S、骚扰色 ∈ S'。
## 六种战甲组合 × 每种摇 20 次（序列生成带随机，只跑一次盖不住）。
func _test_wave_colors() -> void:
	print("------ wave colors ------")
	var f_cnt := ""
	var f_w1 := ""
	var f_alt := ""
	var f_w2 := ""
	var f_w3 := ""
	var f_run := ""
	var f_union := ""
	for a in 4:
		for b in 4:
			if b <= a:
				continue
			var armors: Array[int] = [a, b]
			var cn := _armor_cn(armors)
			var comp := Level._complement(armors)
			if comp.size() != 2:
				_ck(false, "S' 补集应为 2 色（%s 实测 %d）" % [cn, comp.size()])
				continue
			var h2: int = comp[0]
			var h3: int = comp[1]
			for _rep in 20:
				var w1 := Level._wave_colors(1, armors, h2, h3)
				var w2 := Level._wave_colors(2, armors, h2, h3)
				var w3 := Level._wave_colors(3, armors, h2, h3)
				# 只数 5 / 7 / 8 = 20：这是 P0-1 满分（9800）的基数，不能漂
				if w1.size() != 5 or w2.size() != 7 or w3.size() != 8:
					if f_cnt.is_empty():
						f_cnt = cn
				# 第 1 波：5 只全 = 第二件战甲色
				var ok1 := true
				for c in w1:
					if c != b:
						ok1 = false
				if not ok1 and f_w1.is_empty():
					f_w1 = cn
				# 第 2 波：目标色严格交替 + 骚扰色 2 只
				var tgt2: Array[int] = []
				var n_h2 := 0
				for c in w2:
					if c == h2:
						n_h2 += 1
					else:
						tgt2.append(c)
				if n_h2 != 2 and f_w2.is_empty():
					f_w2 = cn
				if not _strict_alt(tgt2, a, b) and f_alt.is_empty():
					f_alt = cn + " -> " + str(tgt2)
				# 第 3 波：骚扰色 3 只，且必须是第 2 波没用过的那一色
				var n_h3 := 0
				var n_h2_in_w3 := 0
				for c in w3:
					if c == h3:
						n_h3 += 1
					elif c == h2:
						n_h2_in_w3 += 1
				if (n_h3 != 3 or n_h2_in_w3 != 0) and f_w3.is_empty():
					f_w3 = cn
				# 连长：第 2 / 3 波不许出现连续 ≥3 同色
				#（第 1 波是刻意的一色到底 —— 教换甲的教学波，不在约束内）
				if Level._max_run(w2) > 2 or Level._max_run(w3) > 2:
					if f_run.is_empty():
						f_run = cn
				# 三波并集 = 全 4 色
				var seen := {}
				for c in w1:
					seen[c] = true
				for c in w2:
					seen[c] = true
				for c in w3:
					seen[c] = true
				if seen.size() != 4 and f_union.is_empty():
					f_union = "%s -> %d 色" % [cn, seen.size()]
	_ck(f_cnt.is_empty(), "六种组合：只数 5 / 7 / 8 合计 20（分数基数不变）" + _bad(f_cnt))
	_ck(f_w1.is_empty(), "六种组合：第 1 波 5 只全为第二件战甲色" + _bad(f_w1))
	_ck(f_alt.is_empty(), "六种组合：第 2 波目标色严格交替" + _bad(f_alt))
	_ck(f_w2.is_empty(), "六种组合：第 2 波骚扰色 2 只" + _bad(f_w2))
	_ck(f_w3.is_empty(), "六种组合：第 3 波骚扰色 3 只且换色（≠ 第 2 波）" + _bad(f_w3))
	_ck(f_run.is_empty(), "六种组合：第 2 / 3 波无连续 ≥3 同色" + _bad(f_run))
	_ck(f_union.is_empty(), "六种组合：三波敌色并集 = 全 4 色" + _bad(f_union))

	# ---------- 骚扰色恒 hover ----------
	var lv := Level.new()
	add_child(lv)
	lv._running = false
	await _frames(3)
	lv.player.armors = [Game.RED, Game.WHITE]
	lv._plan_harass()
	var h2v: int = lv._harass[0]
	var h3v: int = lv._harass[1]
	_ck(h2v != h3v, "两波骚扰色不同（%s / %s）" % [Game.COLOR_CN[h2v], Game.COLOR_CN[h3v]])
	_ck(h2v != Game.RED and h2v != Game.WHITE, "骚扰色 ∈ S'（玩家永远免疫不了）")
	var pats: Array[String] = ["straight", "sine", "dive"]
	lv._spawn_enemy(1.0, h2v, h2v, pats)
	lv._spawn_enemy(1.0, h3v, h3v, pats)
	await _frames(2)
	var hover_n := 0
	var other_n := 0
	for ch in lv.get_children():
		if ch is Enemy:
			if (ch as Enemy).pattern == "hover":
				hover_n += 1
			else:
				other_n += 1
	_ck(hover_n == 2 and other_n == 0,
		"骚扰色强制 hover（hover %d / 非 hover %d）" % [hover_n, other_n])
	# 目标色走模式池，不会误落 hover
	lv._spawn_enemy(1.0, Game.RED, h2v, pats)
	await _frames(2)
	var tp := ""
	for ch2 in lv.get_children():
		if ch2 is Enemy and (ch2 as Enemy).color == Game.RED:
			tp = (ch2 as Enemy).pattern
	_ck(tp != "hover" and pats.has(tp), "目标色走 straight / sine / dive（实测 %s）" % tp)
	lv.queue_free()
	await _frames(3)

	# ---------- 递进参数 ----------
	_ck(not Level._wave_moves(1).has("dive"), "第 1 波不出 dive（开局不俯冲）")
	_ck(Level._wave_moves(3).has("dive"), "第 3 波含 dive")
	# 出怪间隔一律从 StageCfg 推导 —— 写死 0.62 / 0.55 / 0.50 这类数字，
	# 下次改配置又会红，那是自己在制造「静默过时的用例」。
	for n in range(1, StageCfg.waves(1) + 1):
		_ck(is_equal_approx(Level._wave_gap(n), StageCfg.wave_gap(1, n)),
			"第 %d 波出怪间隔与 StageCfg 一致（%.2f）" % [n, Level._wave_gap(n)])
	# 递进语义：越往后越密（这条才是真正要守的不变量）
	_ck(Level._wave_gap(1) > Level._wave_gap(2) and Level._wave_gap(2) > Level._wave_gap(3),
		"出怪间隔逐波收紧（%.2f > %.2f > %.2f）"
			% [Level._wave_gap(1), Level._wave_gap(2), Level._wave_gap(3)])


# ------------------------------------------------------------ Boss
func _test_boss() -> void:
	print("------ boss ------")
	Game.current_stage = 5           # 五关：Boss 参数由关卡号驱动
	Game.picked_armors = [Game.RED, Game.BLUE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(3)
	lv._running = true
	# 【五关改造】Boss 参数已改由关卡号驱动（lv.stage），不再有难度维度。
	#   本用例要覆盖「多阶段 + 有护罩 + 护罩色 ∈ S」，取 L5 终焉号：
	#   4 阶段（刻度 [0.75,0.50,0.25]）+ 全程护罩 ∈S —— 能同时盖住下面 4 条断言。
	lv.stage = 5
	lv._boss_fight()
	await _frames(60)
	var b := lv.boss
	if b == null or not is_instance_valid(b):
		_ck(false, "Boss 生成失败")
		return
	_ck(b.player_armors.size() == 2, "Boss 拿到玩家战甲（护罩只从中抽取）")

	Engine.time_scale = 2.0
	Input.action_press("shoot")
	var seen := {}
	var ward_seen := 0
	var ward_bad := 0            # S0 常驻回归（R-02）：护罩色越界次数
	var last_ward := -2
	for i in 1400:
		if i % 45 == 0 and lv.player != null and is_instance_valid(lv.player):
			lv.player.do_swap()
			lv.player.hp = PlayerCfg.MAX_HP
		if not is_instance_valid(b):
			break
		seen[b.phase] = true
		if b.ward != last_ward:
			last_ward = b.ward
			if b.ward >= 0:
				ward_seen += 1
				# Level 给 Boss 赋「玩家战甲」的字段名一旦与 Boss.gd 声明的不一致，
				# 赋值会被静默丢弃 -> 护罩色退化成 randi()%4 -> 破罩死局。
				# 这里把静默失败钉成硬断言。
				if not lv.player.armors.has(b.ward):
					ward_bad += 1
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
	_ck(ward_seen >= 1, "属性护罩已展开（%d 次）" % ward_seen)
	_ck(ward_seen >= 1 and ward_bad == 0,
		"Boss 护罩色恒 ∈ 玩家战甲（R-02 回归，越界 %d / %d 次）" % [ward_bad, ward_seen])
	_ck(lv.player != null and is_instance_valid(lv.player), "玩家在 Boss 战中存活")
	lv.queue_free()
	await _frames(3)


## L3 耀斑号【散热期】专项（2026-09-22 新增，配合 L3 难度断崖修复）
##
## ⚠⚠ **不要把这类断言写进 `MatrixProbe.gd`** —— 那是**独立场景**，而门禁跑的
##   `SelfTest.tscn` **并不加载它**，写在里面的断言一次都不会执行。2026-09-22 实踩：
##   先在 MatrixProbe 里改了散热倍率断言并新增一条「阶段切换不得硬编码 P1 窗口」
##   的元断言，跑门禁 fails=0；做变异测试把实现改回旧值，门禁**仍是 fails=0** ——
##   不是断言不敏感，是它压根没跑。门禁的唯一入口是本文件的 `_ready()` 调用链，
##   **断言必须落在本文件**。
##
## 覆盖两件事（都是 2026-09-22 L3 曲线断崖修复的落点）：
##   ① 倍率：常态 ×0.3（常驻减伤 70%）/ 散热期 ×1.8 / 狂暴 ×2.4（原 ×3.0 / ×4.0）
##   ② 阶段切换白送的散热窗口**按新阶段给**（P2 2.2s / P3 1.6s），不得恒取 P1 的
##      3.0s —— 那是断崖的第二根因（两次切换各 3.0s，按旧倍率约 1710 点白送，
##      超过 3200 总血的一半）。
func _test_l3_vent() -> void:
	print("------ L3 散热期 ------")
	# 配置层：不依赖战斗流程，最稳
	_ck(absf(StageCfg.heat_mul(3, false) - 1.8) < 0.001, "L3 散热倍率 = ×1.8")
	_ck(absf(StageCfg.heat_mul(3, true) - 2.4) < 0.001, "L3 狂暴散热倍率 = ×2.4")
	_ck(absf(StageCfg.resident_resist(3) - 0.70) < 0.001, "L3 常驻减伤 70%")
	_ck(StageCfg.heat_mul(1, false) == 1.0 and StageCfg.heat_mul(5, false) == 1.0,
		"非 L3 的散热倍率为 1.0（本次下调不波及 L1 / L2 / L4 / L5）")

	Game.current_stage = 3
	Game.picked_armors = [Game.RED, Game.BLUE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(3)
	lv._running = true
	lv.stage = 3
	lv._boss_fight()
	var b := lv.boss
	# Boss 有 enter 进场动画，且不能靠数帧折算游戏时间（headless 帧率抖动极大）
	for _i in 400:
		if b != null and is_instance_valid(b) and b._st == "fight":
			break
		await get_tree().process_frame
	if b == null or not is_instance_valid(b):
		_ck(false, "L3 Boss 生成失败")
		lv.queue_free()
		return
	_ck(b.ward < 0, "L3 全程不展属性护罩（减伤是常驻的、无色的）")

	# 常态：100 → 落 30
	var hp0 := b.hp
	b.hit(100, Game.RED)
	_ck(hp0 - b.hp == 30, "常态 100 伤害 → 落 30（常驻减伤 70%）")

	# 散热期：100 → 落 180（净 ×1.8），且**不叠共振**（同色 / 异色必须一致）
	b._enter_heat(StageCfg.heat_window(3, 1))
	_ck(b.venting, "散热期：venting 置位（舱盖打开）")
	var hp_a := b.hp
	b.hit(100, Game.RED)
	var d_red := hp_a - b.hp
	var hp_b := b.hp
	b.hit(100, Game.BLUE)
	var d_blue := hp_b - b.hp
	_ck(d_red == 180, "散热期 100 伤害 → 落 180（净 ×1.8，常驻减伤解除）")
	_ck(d_red == d_blue,
		"散热期不叠共振：同色 %d / 异色 %d 必须相等" % [d_red, d_blue])

	# 阶段切换白送的窗口：按新阶段给，**不**恒取 P1 的 3.0s
	b.venting = false
	b._heat_t = 0.0
	b.phase = 2
	b._on_phase()
	_ck(absf(b._heat_t - 2.2) < 0.001,
		"切 P2：白送散热 = P2 窗口 2.2s（恒为 3.0s 即回归 L3 断崖）")
	b.venting = false
	b._heat_t = 0.0
	b.phase = 3
	b._on_phase()
	_ck(absf(b._heat_t - 1.6) < 0.001, "切 P3：白送散热 = P3 窗口 1.6s")

	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 驻留阵地波
## ⚠ 这类回归断言**必须写在本文件**（门禁跑的是 `SelfTest.tscn`）。
##   `MatrixProbe.tscn` / `PaceProbe.tscn` / `WardDiag.tscn` 都是手动跑的独立场景，
##   写在那里的断言一次都不会执行 —— 2026-09-22 的变异测试已经证实过一次。
##
## 覆盖「驻留阵地波」（提案 `design/levels/03-关卡节奏实测与驻留波提案.md` §3）：
##   ① 位表：每关 1~2 波、不碰第 1 波（那是教学波）
##   ② 背景：驻留期降到 `Background.SCROLL_HOLD`，波结束恢复 `SCROLL_NORMAL`
##   ③ 入场：驻留波敌人**屏内跃迁**（x ∈ 55%~95% 视宽），列阵者整组共用同一个 x
##   ④ 零回归：默认（warp_x < 0）仍是右侧屏外飞入，七种独有怪逐一验过
func _test_hold_wave() -> void:
	print("------ 驻留阵地波 ------")

	# ---------- ① 位表 ----------
	var f_w1 := ""
	var f_too_few := ""
	var f_too_many := ""
	var hold_cn := ""
	for s in StageCfg.STAGE_N:
		var st := s + 1
		if StageCfg.wave_hold(st, 1) and f_w1.is_empty():
			f_w1 = "第 %d 关" % st
		var k := 0
		# ⚠ 波号是 1-based：`for n in waves(st)` 是 0..N-1，会漏掉最后一波
		#   （L4 的第 5 波就是这么被漏掉的 —— 打印出「L4:1」才抓到）
		for n in range(1, StageCfg.waves(st) + 1):
			if StageCfg.wave_hold(st, n):
				k += 1
				hold_cn += "L%d-%d " % [st, n]
		if k <= 0 and f_too_few.is_empty():
			f_too_few = "第 %d 关" % st
		if k > 2 and f_too_many.is_empty():
			f_too_many = "第 %d 关（%d 波）" % [st, k]
	_ck(f_w1.is_empty(), "第 1 波永不驻留（教学波必须保持推进形态）" + _bad(f_w1))
	_ck(f_too_few.is_empty(), "每关至少一波驻留（%s）" % hold_cn + _bad(f_too_few))
	_ck(f_too_many.is_empty(), "每关至多两波驻留（别把关卡整段停住）" + _bad(f_too_many))

	# ---------- ② 滚速三档 ----------
	_ck(Background.SCROLL_HOLD < Background.SCROLL_BOSS
			and Background.SCROLL_BOSS < Background.SCROLL_NORMAL,
		"滚速三档有序：驻留 %.0f < Boss %.0f < 推进 %.0f"
			% [Background.SCROLL_HOLD, Background.SCROLL_BOSS, Background.SCROLL_NORMAL])
	_ck(Background.SCROLL_HOLD > 0.0,
		"驻留波不降成硬 0（画面整个停住会看着像卡死）")

	# ---------- ③ 实战：L2 第 3 波是驻留波 ----------
	Game.current_stage = 2
	Game.picked_armors = [Game.RED, Game.WHITE]
	_ck(StageCfg.wave_hold(2, 3), "前哨：L2 第 3 波确为驻留波（换表就要改这条）")
	var lv := Level.new()
	lv.stage = 2                 # ★ add_child 之前注入（_ready 里就 _start）
	add_child(lv)
	lv._running = false          # 掐断 _ready 里那条 _run 链，免得跟手动跑的波次抢场
	Engine.time_scale = 8.0
	await _frames(30)            # 等它自然退出（首个 wait 是 0.9s）
	Engine.time_scale = 1.0
	lv._running = true
	# 不 await：协程同步跑到第一个 await（首只出怪后）即挂起，此刻滚速已切好
	lv._wave(3, StageCfg.wave_hp_scale(2, 3), false)
	_ck(is_equal_approx(lv.bg.scroll_speed, Background.SCROLL_HOLD),
		"驻留波期间背景降到 SCROLL_HOLD（实测 %.0f）" % lv.bg.scroll_speed)
	_ck(lv.wave_text.find("驻留") >= 0,
		"驻留波 HUD 波次文字标「驻留」（实测「%s」）" % lv.wave_text)
	var in_n := 0
	var out_n := 0
	for ch in lv.get_children():
		if ch is Enemy:
			if (ch as Enemy).position.x < Game.VIEW_W:
				in_n += 1
			else:
				out_n += 1
	_ck(in_n >= 1 and out_n == 0,
		"驻留波：敌人跃迁落在屏内（屏内 %d / 屏外 %d）" % [in_n, out_n])

	# 清完场 -> 背景恢复推进速度（清场判定与推进波完全同一段，这里顺带验它仍生效）
	Engine.time_scale = 8.0
	var restored := false
	for _i in 400:
		for ch2 in lv.get_children():
			if ch2 is Enemy:
				(ch2 as Enemy).queue_free()
		await get_tree().process_frame
		if is_equal_approx(lv.bg.scroll_speed, Background.SCROLL_NORMAL):
			restored = true
			break
	Engine.time_scale = 1.0
	_ck(restored, "驻留波清场后背景恢复 SCROLL_NORMAL（实测 %.0f）" % lv.bg.scroll_speed)
	lv.queue_free()
	await _frames(3)

	# ---------- ④ 跃迁几何 + 零回归 ----------
	var lv2 := Level.new()
	lv2.stage = 4                # L4 有列阵者之外的两种独有怪；列阵者属 L3，手搓指定即可
	add_child(lv2)
	lv2._running = false
	await _frames(3)
	var pats: Array[String] = ["straight", "sine", "dive"]

	# 列阵者 1 格 = 3 艘成竖墙：整组必须共用同一个跃迁 x，否则墙就散了
	lv2._spawn_slot(1.0, Game.RED, EnemyKind.K.PHALANX, -1, pats, true)
	var wall: Array[float] = []
	for ch3 in lv2.get_children():
		if ch3 is Enemy:
			wall.append((ch3 as Enemy).position.x)
	_ck(wall.size() == 3, "列阵者仍是 3 艘成墙（实测 %d 艘）" % wall.size())
	var same_x := wall.size() == 3
	for x in wall:
		if not is_equal_approx(x, wall[0]) or x < Game.VIEW_W * 0.55 \
				or x > Game.VIEW_W * 0.95:
			same_x = false
	_ck(same_x, "列阵组整组共用同一个跃迁 x（实测 %s）" % str(wall))
	for ch4 in lv2.get_children():
		if ch4 is Enemy:
			(ch4 as Enemy).queue_free()
	await _frames(3)

	# 零回归：默认（warp_x < 0）仍是右侧屏外飞入 —— 七种独有怪逐一验过
	var off_n := 0
	var all_n := 0
	for s2 in StageCfg.STAGE_N:
		for k in StageCfg.unique_kinds(s2 + 1):
			var e := Spawner.enemy(lv2, k, Game.RED, "straight", 300.0, 1.0, s2 + 1)
			if e == null:
				continue
			all_n += 1
			if e.position.x > Game.VIEW_W:
				off_n += 1
			e.queue_free()
	_ck(all_n == 7 and off_n == 7,
		"七种独有怪默认仍从右侧屏外飞入（%d/%d）" % [off_n, all_n])
	lv2.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 计分 / 品阶 / 最高分 / 换甲再来
## 覆盖：关卡计分倍率、每关品阶（独立完成度）、关卡最高分持久化、结算界面 swap_pressed
## 关卡进度存档（user://progress.json）是玩家的真实用户数据 —— 测试前后原样备份还原，不污染
func _test_score_persist() -> void:
	print("------ score / rank / highscore ------")
	var backup_unlocked := Game.unlocked
	var backup_best: Dictionary = Game.stage_best.duplicate(true)

	# ---- 计分倍率：由 StageCfg 按关给出，且逐关递增 ----
	_ck(is_equal_approx(StageCfg.score_multiplier(1), 1.00),
		"第 1 关计分倍率 1.00（基准）")
	var inc := true
	for s in range(2, StageCfg.STAGE_N + 1):
		if StageCfg.score_multiplier(s) <= StageCfg.score_multiplier(s - 1):
			inc = false
	_ck(inc, "五关计分倍率逐关递增（%s）" % _mul_cn())

	# ---- 关卡实际落账：走的是 _add_score，与 HUD / 结算同源 ----
	Game.picked_armors = [Game.RED, Game.WHITE]
	var lv := Level.new()
	add_child(lv)
	lv._running = false
	await _frames(3)
	for s in StageCfg.STAGE_N:
		lv.stage = s + 1
		lv.score = 0
		lv._add_score(100)
		_ck(lv.score == int(roundf(100.0 * StageCfg.score_multiplier(s + 1))),
			"第 %d 关：原始 100 分 × %.2f -> 落账 %d（实测 %d）"
				% [s + 1, StageCfg.score_multiplier(s + 1),
					int(roundf(100.0 * StageCfg.score_multiplier(s + 1))), lv.score])
	lv.queue_free()
	await _frames(3)

	# ---- 品阶：每关独立完成度（铜 ≥55% / 银 ≥80% / 金 ≥96%）----
	for s in StageCfg.STAGE_N:
		var st := s + 1
		var m := StageCfg.theoretical_max(st)
		_ck(Game.completion_of(m, st) >= 0.999,
			"第 %d 关：理论满分 %d -> 完成度 100%%" % [st, m])
		_ck(Game.rank_of_stage(m, st) == "金勋 · 星帅",
			"第 %d 关：满分可达金勋（实测 %s）" % [st, Game.rank_of_stage(m, st)])
		_ck(Game.rank_of_stage(int(float(m) * 0.5), st) == "铁勋 · 星兵",
			"第 %d 关：五成分止步铁勋（实测 %s）"
				% [st, Game.rank_of_stage(int(float(m) * 0.5), st)])
	# 品阶不再跨关可比 —— 同一个分数在不同关的完成度本就不同
	var mid := int(float(StageCfg.theoretical_max(1)) * 0.9)
	_ck(not is_equal_approx(Game.completion_of(mid, 1),
			Game.completion_of(mid, StageCfg.STAGE_N)),
		"同一分数在不同关完成度不同（品阶不跨关可比）")

	# ---- 关卡最高分持久化（progress.json）----
	Game.stage_best = {}
	_ck(Game.stage_highscore(1) == 0, "无存档 -> 本关最高分 0")
	Game.save_stage(1, 8000, [Game.RED, Game.WHITE])
	_ck(Game.stage_highscore(1) == 8000, "写入 -> 第 1 关最高分 8000")
	_ck(Game.stage_highscore(2) == 0, "最高分按关卡分档（第 2 关仍为 0）")
	Game.save_stage(1, 5000, [Game.RED, Game.WHITE])
	_ck(Game.stage_highscore(1) == 8000, "低分不覆盖 -> 仍为 8000")
	Game.save_stage(1, 11000, [Game.RED, Game.WHITE])
	_ck(Game.stage_highscore(1) == 11000, "高分覆盖 -> 11000")
	Game._load_progress()        # 真的落盘了吗 —— 重读一次就知道
	_ck(Game.stage_highscore(1) == 11000, "重读 user://progress.json -> 仍是 11000")
	var rec: Variant = Game.stage_best[Game.stage_key(1)]
	_ck(typeof(rec) == TYPE_DICTIONARY, "存档条目为 Dictionary（score / robes / rank）")
	# 回归闸：最高分条目**不存 win**。通关事实由 unlocked 承载 —— 存进去的话，
	# 一局「输了但分数更高」会把"我通关过这一关"改成"没通关过"。
	_ck(typeof(rec) == TYPE_DICTIONARY and not (rec as Dictionary).has("win"),
		"本关纪录不含 win 字段（通关事实由 unlocked 承载）")

	# ---- _finish 的破纪录判定（按关卡）----
	Game.stage_best = {}
	Game.current_stage = 1
	var lv2 := Level.new()
	add_child(lv2)
	lv2.stage = 1
	lv2._running = false
	await _frames(3)
	lv2.score = 7777
	lv2._finish(true)
	_ck(Game.result_is_new_high, "首局 7777 分 -> 破纪录置位")
	_ck(Game.result_prev_high == 0, "首局：本关历史最高为 0")
	_ck(Game.result_score == 7777, "结算分 = 关卡分 7777")
	_ck(Game.stage_highscore(1) == 7777, "结算时写入本关最高分 7777")
	lv2.queue_free()
	await _frames(3)

	var lv3 := Level.new()
	add_child(lv3)
	lv3.stage = 1
	lv3._running = false
	await _frames(3)
	lv3.score = 1000
	lv3._finish(true)
	_ck(not Game.result_is_new_high, "次局 1000 分 -> 未破纪录（标记复位）")
	_ck(Game.result_prev_high == 7777, "次局：本关历史最高读回 7777")
	# `save_stage` 只在刷新纪录时才写盘 —— 这条守的是「低分不刷新本关最高分」
	_ck(Game.stage_highscore(1) == 7777, "低分不刷新 -> 本关最高分仍为 7777")
	lv3.queue_free()
	await _frames(3)

	# ---- 结算界面：T 换甲再来 ----
	var rs := ResultScreen.new()
	rs.win = true
	add_child(rs)
	await _frames(3)
	_ck(rs.has_signal("swap_pressed"), "结算界面具备 swap_pressed 信号")
	_ck(InputMap.has_action("swap_again"), "输入映射已注册 swap_again")
	var kt := InputEventKey.new()
	kt.keycode = KEY_T
	kt.physical_keycode = KEY_T
	_ck(InputMap.event_is_action(kt, "swap_again"), "T 键已绑定 swap_again（T 未被占用）")
	_swapped = false
	rs.swap_pressed.connect(func() -> void:
		_swapped = true
	)
	await _press("swap_again")
	_ck(_swapped, "结算界面 T 键 -> 发出 swap_pressed")
	rs.queue_free()
	await _frames(3)

	# 还原玩家真实进度：先恢复内存态，再整体写回 user://progress.json
	Game.stage_best = backup_best
	Game.unlocked = backup_unlocked
	Game._write_progress()


# ------------------------------------------------------------ 老档继承（ADR-05 §3.3）
## 方案 A：**只继承解锁到第几关，不继承分数**。
##   档 → 关：简单→L1 / 普通→L2 / 困难→L3
##   有分数 = 玩过 -> unlocked ≥ 该关；win=true = 通关过 -> 再多开一关；**封顶 L3**。
## 这里直接喂内存态 `highscores` 调用，不碰 user:// 上的真实存档文件。
func _test_legacy_inherit() -> void:
	print("------ legacy inherit ------")
	var backup_hs: Dictionary = Game.highscores.duplicate(true)
	var backup_unlocked := Game.unlocked
	var backup_best: Dictionary = Game.stage_best.duplicate(true)

	_ck(Game.LEGACY_MAX_UNLOCK == 3, "老档继承封顶 L3")
	# 1. 空旧档 -> 全新开局
	Game.highscores = {}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.unlocked == 1, "无旧档 -> unlocked = 1")
	# 2. 玩过简单（无 win）-> 仍只有第 1 关
	Game.highscores = {"0": {"score": 100, "robes": [Game.RED, Game.WHITE], "win": false}}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.unlocked == 1, "玩过简单（未通关）-> unlocked = 1")
	# 3. 通关简单 -> 2
	Game.highscores = {"0": {"score": 100, "robes": [Game.RED, Game.WHITE], "win": true}}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.unlocked == 2, "通关简单 -> unlocked = 2")
	# 4. 通关普通 -> 3
	Game.highscores = {"1": {"score": 100, "robes": [Game.RED, Game.WHITE], "win": true}}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.unlocked == 3, "通关普通 -> unlocked = 3")
	# 5. 玩过困难（无 win）-> 3
	Game.highscores = {"2": {"score": 100, "robes": [Game.RED, Game.WHITE], "win": false}}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.unlocked == 3, "玩过困难（未通关）-> unlocked = 3")
	# 6. 通关困难 -> 仍是 3（封顶吸收，不得推出 L4）
	Game.highscores = {"2": {"score": 100, "robes": [Game.RED, Game.WHITE], "win": true}}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.unlocked == 3, "通关困难 -> unlocked 封顶仍为 3（不得推出 L4）")
	# 7. 分数一个都不搬 —— stage_best 必须原样为空
	Game.stage_best = {}
	Game.highscores = {
		"0": {"score": 8000, "win": true},
		"1": {"score": 9000, "win": true},
		"2": {"score": 12000, "win": true},
	}
	Game.unlocked = 1
	Game._inherit_unlocked_from_legacy()
	_ck(Game.stage_best.is_empty(), "老档继承：一个分数都不搬（stage_best 仍为空）")
	_ck(Game.stage_highscore(3) == 0, "老档继承：第 3 关最高分仍为 0")

	Game.highscores = backup_hs
	Game.stage_best = backup_best
	Game.unlocked = backup_unlocked


# ------------------------------------------------------------ 玩家陨落收尾
## 玩家一死，player_ref 就成了「已释放」对象。Boss 若继续按套路开火，
## 会把这个已释放对象赋给弹幕的 target —— 赋值当场就会报
## "Invalid assignment ... with value of type 'previously freed'"。
func _test_death() -> void:
	print("------ death ------")
	Game.picked_armors = [Game.RED, Game.WHITE]
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
	# 必须等星盗旗舰真的进入 fight 再判「收手」，否则入场阶段 _st 本来就不是 fight，
	# 断言会白给（这也是一开始差点漏掉的点）
	for _i in 400:
		if b._st == "fight":
			break
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_ck(b._st == "fight", "星盗旗舰入场到位，正在开火")
	if is_instance_valid(p):
		p.hp = 1
		p._invuln = 0.0
		p.take_hit(Game.BLUE, 99)      # 身上是电浆剑甲，吃蓝弹 -> 直接陨落
	await _frames(3)
	_ck(not is_instance_valid(p) or not p.alive, "玩家被打死")
	_ck(b._st != "fight", "玩家陨落 -> 星盗旗舰收手（不再按套路开火）")
	_ck(b._live_player() == null, "星盗旗舰不再持有已释放的玩家引用")
	# 让星盗旗舰持有一个「已释放」的玩家引用再开火 —— 这是原报错的精确复现条件。
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
	_ck(b._st != "fight", "陨落后持续跑帧 -> 星盗旗舰始终未再开火")
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 通关结算链路
## 击杀 Boss -> Level 发出 finished(true) -> Main 切结算界面
func _test_win() -> void:
	print("------ win ------")
	Engine.time_scale = 8.0
	Game.picked_armors = [Game.WHITE, Game.RED]
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
