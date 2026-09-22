extends Node2D
## ---------------------------------------------------------------
## 五关 × 全阶段实测矩阵探针（**只覆盖 headless 可自动化的部分**）
##
## 设计判定表：`design/levels/02-五关验收清单.md`
## 跑法：
##   Godot_console --headless --path <项目> --quit-after N res://_selftest/MatrixProbe.tscn
##
## ⚠ 本探针**不假装覆盖**下列项，它们必须人工跑（headless 看不到、掐不了表）：
##   · 一切视觉项（弹幕主色读出来是蓝还是白 / 护罩边缘预告闪不闪 / 舱盖开没开）
##   · 一切掐表项（单关时长 ~60s / 波次 gap / 呼吸窗口 1.2s 的手感）
##   · 一切手感项（R4「不换甲能过但明显变慢」的耗时差）
##   · §3 七种独有怪的行为（eng-monsters 的文件，且行为需肉眼辨认）
##   · §5.2 L4 EXPOSED 死锁（子核心机制**尚未落地**，见 _t_l4_status）
## ---------------------------------------------------------------

var _fails: Array[String] = []


func _ck(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
	print("[ck] %s  %s" % ["PASS" if cond else "FAIL", msg])


func _eq(actual: int, expect: int, msg: String) -> void:
	_ck(actual == expect, "%s（期望 %d / 实测 %d）" % [msg, expect, actual])


func _eqf(actual: float, expect: float, msg: String) -> void:
	_ck(absf(actual - expect) < 0.001, "%s（期望 %.2f / 实测 %.2f）" % [msg, expect, actual])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	print("[ck] ---------- §1.4 计分与品阶（零容差）")
	_t_score()
	print("[ck] ---------- §2 逐关 Boss 参数")
	_t_stage_params()
	print("[ck] ---------- §2.5.1 L5 四相编排规则")
	_t_l5_pools()
	print("[ck] ---------- §4 不可回归项（可自动化部分）")
	_t_regression()
	print("[ck] ---------- §5.2 L4 EXPOSED + 死锁防线")
	_t_l4_status()
	await _t_l4_deadlock()
	print("[ck] ---------- §5.3 L3 散热期行为（模拟）")
	await _t_l3_heat()

	# 退出前清一次对象池（把池化的 Danmaku / BossMine 实例还回去）。
	#   ⚠ 这**消除不了**那条 `15 ObjectDB instances were leaked` —— 用 `--verbose` 查过，
	#   泄漏的 15 个全是 `GDScript` / `GDScriptNativeClass` **脚本对象**（refcount 1~9），
	#   不是节点、也不是池实例：headless 退出时脚本仍被类注册表 / Autoload 持有，属
	#   Godot 的正常退出态，与被测代码无关。别再往"产品泄漏"方向排查。
	Pool.clear()
	await _frames(2)
	print("[MATRIX] fails = %d" % _fails.size())
	for f in _fails:
		print("[FAIL] %s" % f)
	print("[MATRIX] DONE")
	get_tree().quit(1 if _fails.size() > 0 else 0)


# ============================================================ §1.4
func _t_score() -> void:
	var mx := [8850, 11715, 13800, 17550, 21420]
	var cu := [4860, 6440, 7590, 9650, 11780]
	var ag := [7080, 9372, 11040, 14040, 17136]
	var gd := [8490, 11240, 13240, 16840, 20560]
	for s in 5:
		var i := s + 1
		_eq(StageCfg.theoretical_max(i), mx[s], "L%d 落账满分" % i)
		_eq(StageCfg.rank_copper(i), cu[s], "L%d 铜勋阈值" % i)
		_eq(StageCfg.rank_silver(i), ag[s], "L%d 银勋阈值（精确整数，不得抹整）" % i)
		_eq(StageCfg.rank_gold(i), gd[s], "L%d 金勋阈值" % i)
	# 银勋取整口径：L2 9372 / L5 17136，不得抹成 9370 / 17130
	_ck(StageCfg.rank_silver(2) % 10 != 0, "L2 银勋 9372 未被抹成整十")
	_ck(StageCfg.rank_silver(5) % 10 != 0, "L5 银勋 17136 未被抹成整十")
	# 品阶按关独立：同一分数在不同关必须得到不同品阶
	_ck(StageCfg.rank_index(1, 8000) != StageCfg.rank_index(5, 8000),
		"品阶按关独立（同 8000 分在 L1 / L5 品阶不同）")


# ============================================================ §2 逐关 Boss 参数
func _t_stage_params() -> void:
	# L1 熔核号：全程护罩是教学载体（§4 #1）
	_eq(StageCfg.boss_hp(1), 1600, "L1 血量")
	_eq(StageCfg.boss_phases(1), 2, "L1 阶段数")
	_ck(StageCfg.boss_ward(1), "L1 有属性护罩（全程 · 教学载体）")
	_eqf(StageCfg.ward_cd(1), 6.5, "L1 护罩轮转 CD")
	_eqf(StageCfg.ward_cd_rage(1), 3.5, "L1 狂暴后 CD")
	_eqf(StageCfg.ward_telegraph(1), 1.5, "L1 换色预告")
	_eqf(StageCfg.off_color_mul(1), 0.60, "L1 异色倍率")
	_eqf(StageCfg.bullet_scale(1), 0.55, "L1 弹幕密度")
	_eqf(StageCfg.enrage_at(1), 0.30, "L1 狂暴阈值")
	_ck(StageCfg.phase_marks(1) == [0.50], "L1 阶段刻度 [0.50]")

	# L2 霜噬号：永不展护罩
	_eq(StageCfg.boss_hp(2), 2400, "L2 血量")
	_eq(StageCfg.boss_phases(2), 3, "L2 阶段数")
	_ck(not StageCfg.boss_ward(2), "L2 永不展属性护罩")
	_eqf(StageCfg.off_color_mul(2), 1.00, "L2 异色倍率恒 1.0")
	_eqf(StageCfg.bullet_scale(2), 0.80, "L2 弹幕密度")

	# L3 耀斑号：常驻减伤 + 散热窗口
	_eq(StageCfg.boss_hp(3), 3200, "L3 血量")
	_eq(StageCfg.boss_phases(3), 3, "L3 阶段数")
	_ck(not StageCfg.boss_ward(3), "L3 不展属性护罩（减伤是常驻无色的）")
	_eqf(StageCfg.resident_resist(3), 0.70, "L3 常态减伤 70%")
	_eqf(StageCfg.heat_window(3, 1), 3.0, "L3 P1 散热窗口")
	_eqf(StageCfg.heat_window(3, 2), 2.2, "L3 P2 散热窗口")
	_eqf(StageCfg.heat_window(3, 3), 1.6, "L3 P3 散热窗口")
	_eqf(StageCfg.heat_window_rage(3), 1.2, "L3 狂暴散热窗口")
	_eqf(StageCfg.heat_mul(3, false), 3.0, "L3 散热倍率")
	_eqf(StageCfg.heat_mul(3, true), 4.0, "L3 狂暴散热倍率")
	_eqf(StageCfg.bullet_scale(3), 0.85, "L3 弹幕密度")
	# 非 L3 一律 0 = 不触发
	_eqf(StageCfg.heat_window(1, 1), 0.0, "非 L3 散热窗口为 0")
	_eqf(StageCfg.resident_resist(5), 0.0, "L5 无常态减伤")

	# L4 深渊之喉
	_eq(StageCfg.boss_hp(4), 4200, "L4 血量")
	_eq(StageCfg.boss_phases(4), 3, "L4 阶段数")
	_eqf(StageCfg.bullet_scale(4), 0.95, "L4 弹幕密度")

	# L5 终焉号：四相
	_eq(StageCfg.boss_hp(5), 6000, "L5 血量（3600 撑不住四相）")
	_eq(StageCfg.boss_phases(5), 4, "L5 阶段数 = 4（§4 #9）")
	_eqf(StageCfg.ward_cd(5), 5.0, "L5 护罩轮转 CD")
	_eqf(StageCfg.ward_cd_rage(5), 3.5, "L5 狂暴后 CD")
	_eqf(StageCfg.off_color_mul(5), 0.55, "L5 异色倍率（全游戏最狠）")
	_eqf(StageCfg.bullet_scale(5), 1.00, "L5 弹幕密度")
	_eqf(StageCfg.enrage_at(5), 0.25, "L5 狂暴阈值（比其他 Boss 晚）")
	var m5 := StageCfg.phase_marks(5)
	_ck(m5 == [0.75, 0.50, 0.25], "L5 阶段刻度 [0.75, 0.50, 0.25]（实测 %s）" % str(m5))


# ============================================================ §2.5.1 四相编排规则
func _t_l5_pools() -> void:
	var p1 := BossCfg.pool(5, 1)
	var p2 := BossCfg.pool(5, 2)
	var p3 := BossCfg.pool(5, 3)
	var p4 := BossCfg.pool(5, 4)
	print("[info] L5 相① = %s" % str(p1))
	print("[info] L5 相② = %s" % str(p2))
	print("[info] L5 相③ = %s" % str(p3))
	print("[info] L5 相④ = %s" % str(p4))

	# 规则 5：ring_white 是白弹，不得出现在非白相（相③ 才是白相）
	_ck(not p2.has("ring_white"), "相② 不含 ring_white（这就是「相②偏白」的根因）")
	_ck(not p1.has("ring_white"), "相① 不含 ring_white")
	_ck(not p4.has("ring_white"), "相④ 不含 ring_white")
	# ⚠ 这条原写 `p3.has("ring_white")`：相③ 的「34发双环反向」已改名 `ring_white_x2`
	#   （L5 参数与 L1 / L3 的 `ring_white` 冲突，按纯增量另开名），旧断言从此一直红、
	#   且不再测任何有意义的东西 —— 改成「首招是 ring_white 系列白环」，不过时也不放水。
	_ck(p3[0].begins_with("ring_white"),
		"相③（白相）首招是白环 ring_white*（实测 %s）" % p3[0])
	# 规则 4：spiral_4 只允许相④
	_ck(not p1.has("spiral_4") and not p2.has("spiral_4") and not p3.has("spiral_4"),
		"spiral_4 不出现在相①②③")
	_ck(p4.has("spiral_4"), "spiral_4 只出现在相④（终相信号）")
	# 相② 修复后三招全蓝
	_ck(p2.has("fan_blue") and p2.has("grid_rain_blue") and p2.has("ring_blue"),
		"相② 三招 = fan_blue / grid_rain_blue / ring_blue（实测 %s）" % str(p2))
	_ck(p2[0] == "fan_blue", "相② 首招是 fan_blue（首招决定第一印象）")
	# 每个池都能拿到节奏参数（兜底不算过）
	for sk in p2:
		_ck(BossCfg._DUR.has(sk) and BossCfg._TICK.has(sk),
			"相② 技能 %s 已登记 DUR / TICK（不走兜底）" % sk)
	# L4 相③ 的 spiral_4 例外：**未修**，这里只如实报，不判 PASS
	var l4p3 := BossCfg.pool(4, 3)
	print("[info] L4 P3 = %s（含 spiral_4 = %s —— 与「只允许相④」冲突，待设计给替代招）"
		% [str(l4p3), str(l4p3.has("spiral_4"))])


# ============================================================ §4 不可回归项
func _t_regression() -> void:
	# #1 L1 全程护罩
	_ck(StageCfg.ward_mode(1) == StageCfg.WardMode.ALWAYS, "§4-1 L1 护罩模式 = ALWAYS")
	# #9 L5 四阶段 + 3 刻度
	_ck(StageCfg.boss_phases(5) == 4 and StageCfg.phase_marks(5).size() == 3,
		"§4-9 L5 = 4 阶段 / 3 条刻度")
	# #10 品阶按关独立
	_ck(StageCfg.rank_index(1, 5000) != StageCfg.rank_index(5, 5000), "§4-10 品阶按关独立")
	# #13 L5 掉落 0.14 不是 0.18
	_eqf(StageCfg.drop_chance(5), 0.14, "§4-13 L5 掉落率")
	_eqf(StageCfg.drop_chance(1), 0.18, "§4-13 L1 掉落率（对照组）")
	# 清场 guard 上限
	_eqf(StageCfg.clear_guard(1, false), 14.0, "L1 无战将波 guard")
	_eqf(StageCfg.clear_guard(5, true), 32.0, "L5 战将波 guard")
	# 波数
	var wv := [3, 4, 4, 5, 5]
	for s in 5:
		_eq(StageCfg.waves(s + 1), wv[s], "L%d 波数" % (s + 1))


# ============================================================ §5.2 L4 现状
func _t_l4_status() -> void:
	_ck(StageCfg.ward_mode(4) == StageCfg.WardMode.EXPOSED,
		"L4 配置层 = EXPOSED（仅暴露期展罩）")
	_eqf(StageCfg.sub_core_resist(4), 0.80, "L4 相位壁免伤 80%")
	_eqf(StageCfg.sub_core_share(4), 0.40, "L4 伤害共享 40%")
	_eqf(StageCfg.summon_cd(4), 4.0, "L4 召唤间隔 4.0s")
	_eqf(StageCfg.expose_time(4), 6.0, "L4 暴露期 6.0s")
	_ck(ResourceLoader.exists("res://scripts/entities/Boss4.gd"),
		"L4 子类 Boss4.gd 已落地（Level._make_boss 会自动探测）")


## §5.2 死锁防线：**必须实际打死一次**
## 狂暴后子核心常驻不消失 → 「子核心全灭」永不成立 → 若无强制暴露期 Boss 无敌。
## 验证：把 Boss 打到狂暴，然后持续输出，血量必须能掉到 0。
func _t_l4_deadlock() -> void:
	Game.current_stage = 4
	Game.picked_armors = [Game.RED, Game.BLUE]
	var lv := Level.new()
	add_child(lv)
	await _frames(3)
	lv._running = false
	await _frames(3)
	lv._running = true
	lv.stage = 4
	lv._boss_fight()
	await _frames(90)
	var b: Boss = lv.boss
	if b == null or not is_instance_valid(b):
		_ck(false, "L4 Boss 生成失败")
		return
	# ⚠ 必须从屏幕外飘到站位才进 fight —— 不能按帧数折算秒数（headless ~140fps）
	var g0 := 0
	while b._st != "fight" and g0 < 900:
		await _frames(10)
		g0 += 10
	_ck(b._st == "fight", "L4 Boss 入场到位进入 fight（等了 %d 帧）" % g0)
	_ck(b is Boss4, "L4 走到 Boss4 子类")
	var b4 := b as Boss4
	_eq(b4.max_hp, 4200, "L4 Boss4 血量")
	_ck(not b4._cores.is_empty(), "L4 开局已分裂子核心（%d 只）" % b4._cores.size())
	# 子核心配色：两只都 ∈ S，且各取 armors[0] / armors[1]
	var ok_in_s := true
	for core in b4._cores:
		if not b4.player_armors.has(core.color):
			ok_in_s = false
	_ck(ok_in_s, "L4 子核心配色严格 ∈ S（不得有 S' 的死局色）")
	# 相位壁：子核心存活时本体只吃 20%
	var hp0 := b4.hp
	b4.hit(100, Game.RED)
	var d_wall := hp0 - b4.hp
	_eq(d_wall, 20, "相位壁期：100 → 落 20（免伤 80%）")
	# ---- 打到狂暴 ----
	# 先把血量降到狂暴线以下，并让 phase / 阶段切换**先结算完**
	# （阶段切换本身会白送一次暴露期，那是正确行为，不能污染后面的强制暴露期测试）
	b4.hp = int(roundf(float(b4.max_hp) * 0.25))
	b4._check_phase()
	b4._check_enrage()
	_ck(b4.enraged,
		"已触发狂暴（_st=%s / 血量比 %.2f / 阈值 %.2f）"
		% [b4._st, float(b4.hp) / float(b4.max_hp), b4._enrage_at])
	# 清掉阶段切换白送的那次暴露期，回到「相位壁期」这个待测起点
	b4._exit_expose()
	# 狂暴后子核心**常驻不消失**：确认场上仍有子核心（全灭条件不会成立）
	if b4._cores.is_empty():
		b4._split_cores()
	_ck(not b4._cores.is_empty(), "狂暴后子核心常驻（%d 只 —— 全灭条件永不成立）"
		% b4._cores.size())
	# 相位壁仍在 → 伤害被压到 20%
	var hp_w := b4.hp
	b4.hit(100, Game.RED)
	var d_w := hp_w - b4.hp
	_eq(d_w, 20, "狂暴 + 子核心在场：100 → 落 20（相位壁未落）")

	# ---- 死锁防线：等强制暴露期自己开（不手动清子核心、不手改标志位）----
	_ck(not b4._exposed_win, "起始状态：不在暴露期")
	var g1 := 0
	while not b4._exposed_win and g1 < 1200:
		await _frames(10)
		g1 += 10
	_ck(b4._exposed_win,
		"🔴 死锁防线：狂暴后**自动**开出暴露期（等了 %d 帧，子核心仍 %d 只）"
		% [g1, b4._cores.size()])
	# 暴露期内相位壁落下 → 本体全额受伤
	var hp_e := b4.hp
	b4.hit(100, Game.RED)
	var d_e := hp_e - b4.hp
	_eq(d_e, 100, "暴露期内：100 → 落 100（相位壁消失，本体全额）")

	# ---- 最终判据：狂暴后持续输出，Boss 血量必须能掉到 0 ----
	var guard := 0
	while b4.hp > 0 and guard < 600:
		b4.hit(100, Game.RED)
		b4.hit(100, Game.BLUE)
		await _frames(4)
		guard += 1
	_ck(b4.hp <= 0,
		"🔴 死锁防线终判：狂暴后持续输出能打死 Boss（血量 %d / 循环 %d 次）"
		% [b4.hp, guard])
	lv.queue_free()
	await _frames(4)


# ============================================================ §5.3 L3 散热期行为
func _t_l3_heat() -> void:
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
	await _frames(90)
	var b: Boss = lv.boss
	if b == null or not is_instance_valid(b):
		_ck(false, "L3 Boss 生成失败")
		return
	_eq(b.max_hp, 3200, "L3 Boss 实例血量")
	_eqf(b._resist, 0.70, "L3 Boss 实例常驻减伤")
	_ck(b._heat_win > 0.0, "L3 Boss 已装载散热窗口时长（%.2f）" % b._heat_win)

	# 手动进一次散热期，验三件事 + 不叠共振
	b._enter_heat(StageCfg.heat_window(3, 1))
	_ck(b.venting, "① 散热期：venting 置位（舱盖打开）")
	# ② 停火：记录散热前的 _skill_t，跑若干帧后应完全不变
	var t0 := b._skill_t
	await _frames(20)
	_ck(absf(b._skill_t - t0) < 0.001, "② 散热期：停火（_skill_t 未推进）")
	# ③ ×3.0 且**不叠共振**：同色 / 异色两次伤害必须一样
	var hp_a := b.hp
	b.hit(100, Game.RED)
	var d_red := hp_a - b.hp
	var hp_b := b.hp
	b.hit(100, Game.BLUE)
	var d_blue := hp_b - b.hp
	_ck(d_red == d_blue,
		"③ 散热期不叠共振：同色 %d / 异色 %d 必须相等" % [d_red, d_blue])
	# 主理人终裁（2026-09-22）：常驻减伤 与 散热倍率是**互斥分支，不是连乘**。
	#   ×3.0 是**最终倍率**，不是叠在减伤上的系数。100 原始伤害：
	#   常态落 30（常驻减伤 70%）/ 散热期落 300（净 ×3.0）/ 狂暴散热期落 400。
	_eq(d_red, 300, "③ 散热期 100 伤害 → 净 ×3.0 → 落 300（常驻减伤解除）")
	# 复位：等窗口**真的**走完（headless 帧率 ~140fps，不能用帧数折算秒数）
	var waited := 0
	while b.venting and waited < 1200:
		await _frames(10)
		waited += 10
	_ck(not b.venting, "复位：venting 归位（舱盖合上，等了 %d 帧）" % waited)

	var hp_c := b.hp
	b.hit(100, Game.RED)
	var d_norm := hp_c - b.hp
	_eq(d_norm, 30, "复位：倍率回 ×0.3（100 → 落 30）")
	lv.queue_free()
	await _frames(4)
