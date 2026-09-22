extends Node2D
## 自动化冒烟测试（headless 运行用，验证完毕即删除）
## 覆盖：四色免疫 / 护盾充能（开局 0 · 吸弹 +10 · 上限 20 · 不自动回复）/
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
	await _test_dodge()
	await _test_yellow()
	await _test_pickup()
	await _test_elite()
	await _test_pool()
	await _test_vector_static()   # 07 §2.4：敌方矢量活体静态检查 V0~V4
	await _test_wording()         # 术语红线：全库不得出现旧称
	await _test_level()
	await _test_wave_colors()
	await _test_boss()
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
	_ck(Player.SHIELD_MAX == 20, "护盾上限常量 = 20")
	_ck(Player.SHIELD_GAIN == 10, "单次充能常量 = 10")

	# ---------- 充能：白甲吸收白弹 ----------
	# 白弹撞白甲走的是 take_hit() 的**同色吸收**分支：不掉血、弹幕消失，
	# 光子盾甲额外把这一发转成护盾充能。
	var used := p.take_hit(Game.WHITE, 10)
	_ck(used == true, "白皮肤吸收白弹（弹幕消失）")
	_ck(p.hp == Player.MAX_HP, "吸收后血量不变")
	_ck(p.shield == Player.SHIELD_GAIN, "白甲吸收光子弹 -> 护盾 0 -> 10")
	# 再钉一次**绝对值**：上面那条拿的是常量，常量本身被改小它照样绿
	_ck(p.shield == 10, "单次充能绝对值 = 10")

	p._invuln = 0.0
	p.take_hit(Game.WHITE, 10)
	_ck(p.shield == Player.SHIELD_MAX, "再吸收一枚 -> 护盾 10 -> 20（满值）")
	_ck(p.shield == 20, "护盾上限绝对值 = 20")
	_ck(p.hp == Player.MAX_HP, "充能期间不掉血")

	p._invuln = 0.0
	p.take_hit(Game.WHITE, 10)
	_ck(p.shield == Player.SHIELD_MAX, "满值后继续吸收 -> 仍为 20（上限钳制，不溢出）")
	_ck(p.hp == Player.MAX_HP, "满值吸收同样不掉血")

	# ---------- 护盾仍按既有规则为光子盾甲减伤 ----------
	p._invuln = 0.0
	p.take_hit(Game.RED, 12)
	_ck(p.shield == 8, "白甲吃异色弹：护盾吸收 12 点 -> 剩 8")
	_ck(p.hp == Player.MAX_HP, "护盾吸收期间不掉血")

	p._invuln = 0.0
	p.take_hit(Game.BLUE, 12)
	_ck(p.shield == 0, "护盾耗尽")
	_ck(p.hp == Player.MAX_HP - 4, "溢出伤害 4 点扣血")

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

	p._invuln = 0.0
	_ck(p.take_hit(Game.RED, 10) == true, "红皮肤吸收红弹（弹幕消失）")
	p._invuln = 0.0
	_ck(p.take_hit(Game.BLUE, 10) == true, "红皮肤吃蓝弹并扣血")

	# 移速：红 vs 蓝
	p.armors = [Game.RED, Game.BLUE]
	p.armor_idx = 0
	p.hp = Player.MAX_HP
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
func _test_dodge() -> void:
	print("------ dodge (寒霜疾甲) ------")
	var p := Player.new()
	p.world = self
	add_child(p)
	p.armors = [Game.BLUE, Game.RED]
	p.armor_idx = 0
	await _frames(2)
	_ck(p.color == Game.BLUE, "闪避用例：穿上寒霜疾甲(蓝)")
	_ck(is_equal_approx(Player.DODGE_TIME, 0.5), "闪避时长常量 = 0.5 秒")

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
	# 旧断言「闪避不打断十息回盾计时（_no_hit 未被清零）」随自动回复一起删除了 ——
	# 那条语义已不存在。换成一条**等价有力**的：闪避的 return false 发生在
	# 受击结算（_invuln = INVULN）之前，所以闪避不额外赠送 0.85 秒无敌帧；
	# 否则「闪避 0.5 秒 + 受击无敌 0.85 秒」会悄悄叠成 1.35 秒的免伤窗口。
	p._dodge = Player.DODGE_TIME
	p._invuln = 0.0
	var hp1b := p.hp
	_ck(p.take_hit(Game.YELLOW, 20) == false, "② 闪避期间吃黄弹 -> 穿透（返回 false）")
	_ck(p._invuln == 0.0, "② 闪避拦截发生在受击结算之前（不赠送受击无敌帧）")
	_ck(p.hp == hp1b, "② 闪避期间吃黄弹不掉血")

	# 真链路：让一颗异色弹压在闪避中的玩家身上 —— 它应当**穿过**而不是被吃掉
	p.position = Vector2(420.0, 360.0)
	p._dodge = Player.DODGE_TIME
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
			p._dodge = Player.DODGE_TIME       # 弹没了说明断言已失败，别让后续用例连锁失败
		dd.dissolve()
	await _frames(2)

	# ---------- ③ 0.5 秒后自动结束（轮询，不数帧）----------
	p._dodge = Player.DODGE_TIME
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
	p._dodge = Player.DODGE_TIME
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
		p.hp = Player.MAX_HP
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
	_ck(p.hp == Player.MAX_HP, "吸收引力弹不掉血")

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
	# 否则它永远等不到 free，清场判定会被一路拖到上限（同色潮每重必有 hover）。
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
	_ck(p.hp == Player.MAX_HP, "修复包不会超出生命上限")

	# 刃影模块
	_ck(p.rows() == 1, "光子盾甲基准单排弹道")
	p.apply_pickup(Pickup.T.MULTI)
	_ck(p.multi == 1 and p.rows() == 2, "刃影模块 -> 弹道 +1")
	p.armor_idx = 1
	_ck(p.rows() == 3, "电浆剑甲双排 + 刃影模块 = 三排")
	p.armor_idx = 0

	# 增幅核心
	_ck(p.sword_damage() == 10, "基准光刃伤害 10")
	p.apply_pickup(Pickup.T.ATK)
	_ck(absf(p.atk_mul - 1.30) < 0.001, "增幅核心 -> 攻击力 +30%")
	_ck(p.sword_damage() == 13, "光刃伤害 10 -> 13")
	_ck(p.sword_size() > 1.0, "光刃变大（外观与碰撞体同步）")
	_ck(p.beam_width() > 1.0, "引力束变粗")
	_ck(absf(p.beam_dps() - 120.0 * 1.3) < 0.01, "引力束每秒伤害同步提高到 156")

	# 层数封顶
	for _i in 8:
		p.apply_pickup(Pickup.T.MULTI)
		p.apply_pickup(Pickup.T.ATK)
	_ck(p.multi == Player.MULTI_MAX, "刃影模块层数封顶 %d 层" % Player.MULTI_MAX)
	_ck(p.atk_up == Player.ATK_MAX, "增幅核心层数封顶 %d 层" % Player.ATK_MAX)

	# 力场罩
	p.invinc = 0.0
	p.apply_pickup(Pickup.T.INVINC)
	_ck(absf(p.invinc - Player.INVINC_TIME) < 0.001, "力场罩 -> 无敌 6 秒")
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
	_ck(n1 - n0 == Level.WAVE_DROP,
		"每波结束刷新 %d 个道具（实测 %d 个）" % [Level.WAVE_DROP, n1 - n0])
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

	# ---------- 力场分层：异色刮痧，且破罡前本体不掉血 ----------
	var off := (e.color + 1) % 4
	var hp0 := e.hp
	var w0 := e.ward
	e.hit(100, off)
	var d_off := w0 - e.ward
	_ck(e.hp == hp0, "力场未破时本体不掉血")
	_ck(d_off == int(roundf(100.0 * Elite.WARD_RESIST)),
		"异色打力场只剩 %d%%（100 -> %d）" % [int(Elite.WARD_RESIST * 100.0), d_off])
	# 用 20 点试同色：100 点同色打出来是 150，会一击打爆 150 的力场 ——
	# 那测的就不是衰减比例而是「恰好破罡」了
	e.ward = w0
	e.hit(20, e.color)
	_ck(w0 - e.ward == 30, "同色打力场全额 +50%%（20 -> %d）" % (w0 - e.ward))

	# ---------- 破罡 -> 虚弱 ----------
	e.ward = 10
	e.hit(50, e.color)
	_ck(e.ward == 0 and e.broken > 0.0, "力场击破 -> 进入虚弱期")
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
	_ck(_elite_score == Elite.SCORE, "斩杀奖励 %d 分" % Elite.SCORE)
	_ck(e.dead, "死亡标记已置位（清场判定据此放行）")
	await _frames(2)

	# ---------- 关卡接入 ----------
	var lv := Level.new()
	add_child(lv)
	lv._running = false      # 别让波次真的跑起来，只测生成与掉落
	await _frames(3)
	var n0 := _count_pickups(lv)
	lv.stage = 4                 # 战将也要拿关卡号：难度参数由 StageCfg 按关给出
	lv._spawn_elite(1.15)
	await _frames(3)
	var el := _find_elite(lv)
	_ck(el != null, "关卡可生成星盗战将")
	if el != null:
		# 回归闸：`Elite.stage` 必须由 Level 在 add_child **之前**注入。
		# 一旦漏写或写晚，GDScript 是**运行时静默失败**（值丢掉、不报错），
		# 战将的弹幕密度就会退回到第 1 关 —— 这种错肉眼根本看不出来。
		_ck(el.stage == 4, "战将拿到关卡号（实测 %d）" % el.stage)
		_ck(el.player_armors.size() == 2, "战将拿到玩家战甲（力场只从中抽取）")
		_ck(el.max_hp > Elite.BASE_HP, "血量按波次系数缩放（第 2 重 %d）" % el.max_hp)
		_ck(lv._elite_alive(), "清场判定认得战将（在场即算未清空）")
		el.ward = 0
		el.hp = 1
		el.hit(50, el.color)
		await _frames(4)
		_ck(_count_pickups(lv) == n0 + 1, "斩杀战将必掉一件道具")
		_ck(not lv._elite_alive(), "战将阵亡后清场放行")
	lv.queue_free()
	await _frames(3)


# ------------------------------------------------------------ 矢量活体静态检查（07 §2.4）
## 覆盖 PirateArt.gd（星盗喽啰 / 星盗战将）与 Boss.gd（星盗旗舰）的矢量渲染路径。
## V1 是主通道（舱盖色的有无）的活体保证，最高优先；V0/V2/V3/V4 守其余通道。
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


## V4-b：星盗战将 draw_elite 内所有顶点 / 矩形角点半径 ≤ 40（法罡弧内缘 43 留 3px）。
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
	_ck(_elite_budget(delite), "V4 星盗战将 r ≤ 40（法罡弧内缘 43 留 3px）")
	# V3 顶层轮廓：顶带双分离
	_ck(_elite_top_separation(delite), "V3 战将顶带探针行 y=−30 双分离（2 段 · gap ≥ 20）")


# ------------------------------------------------------------ 术语红线
## 科幻改版后旧称一律作废。这条扫描把「改一个漏一片」钉成硬失败。
## 注：禁用词用**拼接**书写 —— 否则本文件自己就会命中自己。
##
## ⚠ 已知的「合法同形词」，别照关键词结果误删：
##   · `StageSelect._phase_cn()` 返回「三重」= **Boss 阶段数**，与关卡数无关
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
	# 后的自我回收，否则每重都会白等清场上限。这里跑一遍真实离场流程验证计数归零。
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
				# 第 1 重：5 只全 = 第二件战甲色
				var ok1 := true
				for c in w1:
					if c != b:
						ok1 = false
				if not ok1 and f_w1.is_empty():
					f_w1 = cn
				# 第 2 重：目标色严格交替 + 骚扰色 2 只
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
				# 第 3 重：骚扰色 3 只，且必须是第 2 重没用过的那一色
				var n_h3 := 0
				var n_h2_in_w3 := 0
				for c in w3:
					if c == h3:
						n_h3 += 1
					elif c == h2:
						n_h2_in_w3 += 1
				if (n_h3 != 3 or n_h2_in_w3 != 0) and f_w3.is_empty():
					f_w3 = cn
				# 连长：第 2 / 3 重不许出现连续 ≥3 同色
				#（第 1 重是刻意的一色到底 —— 教换甲的教学重，不在约束内）
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
	_ck(f_w1.is_empty(), "六种组合：第 1 重 5 只全为第二件战甲色" + _bad(f_w1))
	_ck(f_alt.is_empty(), "六种组合：第 2 重目标色严格交替" + _bad(f_alt))
	_ck(f_w2.is_empty(), "六种组合：第 2 重骚扰色 2 只" + _bad(f_w2))
	_ck(f_w3.is_empty(), "六种组合：第 3 重骚扰色 3 只且换色（≠ 第 2 重）" + _bad(f_w3))
	_ck(f_run.is_empty(), "六种组合：第 2 / 3 重无连续 ≥3 同色" + _bad(f_run))
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
	_ck(h2v != h3v, "两重骚扰色不同（%s / %s）" % [Game.COLOR_CN[h2v], Game.COLOR_CN[h3v]])
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
	_ck(not Level._wave_moves(1).has("dive"), "第 1 重不出 dive（开局不俯冲）")
	_ck(Level._wave_moves(3).has("dive"), "第 3 重含 dive")
	# 出怪间隔一律从 StageCfg 推导 —— 写死 0.62 / 0.55 / 0.50 这类数字，
	# 下次改配置又会红，那是自己在制造「静默过时的用例」。
	for n in range(1, StageCfg.waves(1) + 1):
		_ck(is_equal_approx(Level._wave_gap(n), StageCfg.wave_gap(1, n)),
			"第 %d 重出怪间隔与 StageCfg 一致（%.2f）" % [n, Level._wave_gap(n)])
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
			lv.player.hp = Player.MAX_HP
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
