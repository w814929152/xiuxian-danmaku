extends Node2D
## ---------------------------------------------------------------
## 节奏探针：实测五关 Boss 的「理想输出击杀耗时（TTK）」
##
## 跑法：
##   Godot_console --headless --path <项目> --quit-after 400000 \
##       res://_selftest/PaceProbe.tscn
##
## 为什么需要它：「单关时长是否过短」里，**波次那一半能纯算**（`StageCfg` 的
## 出怪间隔 × 格数是精确值），**Boss 那一半算不出来** —— 护罩轮转 / 散热窗口 /
## 相位壁 / 暴露期全是时间驱动的开关，平均倍率取决于战斗本身的时长（打得越久
## 轮转次数越多），只能跑一遍才知道。
##
## 口径（结论的边界，务必连同数字一起读）：
##   · 策略 A「完美换甲」：护罩色 ∈ 战甲时立刻切到该色（换甲无 CD，理论上限）
##   · 策略 B「不换甲」：恒用战甲[0]（设计 R4「不换甲能过但明显变慢」的下限）
##   · L4 一律「暴露期打本体 / 非暴露期打子核心」（这是最优解：裸打本体只有 20%）
##   · 计时从 Boss 进入 fight 状态起算，到 hp <= 0 止
##   · 探针玩家 100% 输出、永不走位、永不受伤 —— 所以测出来的是**下界**，
##     真实玩家只会更慢
##
## ⚠⚠ 打点粒度（2026-09-22 实测踩坑，改这块前先读完）：
##   `Boss.hit()` / `Boss4.hit()` 结尾都是 `maxi(1, int(roundf(dmg * mul)))` ——
##   **下限 1**。若按帧打点（headless ~145fps，95 DPS → 每帧 0.65 点，累积出来
##   n 恒为 1），那么 `1 × 0.60 = 0.6 → roundf → 1`、`1 × 0.20 = 0.2 → 1`，
##   **护罩异色 / 相位壁免伤 80% / 常驻减伤 70% 全部被这个下限抹平**，
##   五个 Boss 的 TTK 会一起退化成「血量 ÷ DPS」，L1 与 L5 的「换甲 vs 不换甲」
##   还会得出一模一样的数（实测踩过，见 WardDiag）。
##   真实光刃单发 10 点（×0.6 = 6）不受影响 —— 这是**探针的**粒度问题，不是游戏的。
##   故必须按 HIT_CHUNK 成块打：块内倍率误差 ≤ 2.8%。
## ---------------------------------------------------------------

## 两档 DPS：95 = 单排光刃·无增幅（10 dmg / 0.105s）；152 = 电浆剑甲双排（8×2 / 0.105s）
const DPS_A := 95.0
const DPS_B := 152.0
## 单次打击的伤害块（见上方「打点粒度」）：20 点 ×0.6 = 12 整，无取整损失
const HIT_CHUNK := 20
## 模拟倍速：只加快**墙钟**，游戏内时间照常走（delta 被放大，机制计时同步放大）。
## 纯 delta 驱动的逻辑不受影响，15 次测量从 ~10 分钟压到 ~2 分钟。
const TIME_SCALE := 6.0
## 单次测量的硬上限（秒，游戏内时间）：超过就判「打不动」，防止死循环
const TTK_CAP := 300.0

var _t := 0.0
var _acc := 0.0
var _dps := 95.0
var _perfect := true
var _lv: Level = null
var _boss: Boss = null
var _live := false


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _process(delta: float) -> void:
	if not _live or _boss == null or not is_instance_valid(_boss):
		return
	# 探针玩家不死：Boss 的弹幕照打，血量强行顶住（否则会走 player_died 分支）
	if _lv != null and _lv.player != null and is_instance_valid(_lv.player):
		_lv.player.hp = 1000000
	_t += delta
	_acc += _dps * delta
	var n := int(_acc / float(HIT_CHUNK))
	if n <= 0:
		return
	_acc -= float(n * HIT_CHUNK)
	n *= HIT_CHUNK
	var c: int = _lv.player.armors[0]
	if _perfect and _boss.ward >= 0 and _lv.player.armors.has(_boss.ward):
		c = _boss.ward
	# L4：暴露期本体全额 > 子核心（只共享 40%）；非暴露期反过来
	if _boss is Boss4 and not _boss._exposed_win:
		var b4 := _boss as Boss4
		for core in b4._cores:
			if core != null and is_instance_valid(core) and not core.dead:
				core.hit(n, c)
				return
	_boss.hit(n, c)


func _ready() -> void:
	await _frames(2)
	# ⚠ 固定随机种子 —— Boss 的护罩轮转间隔（3.2 + randf()*1.6）与护罩配色
	#   （player_armors[randi() % n]）都是随机的，「不换甲」那一档对序列极其敏感：
	#   实测同一份代码两次运行，L1 不换甲能差出 19.6 s vs 16.9 s（16%）。
	#   不固定种子的话，跨运行的数字没法比，改一个常量后看到的变化说不清是改动
	#   还是运气。固定后每次跑出同一组数，才谈得上「A/B 对比」。
	seed(20260922)
	Engine.time_scale = TIME_SCALE
	print("[PACE] ---------- 五关 Boss TTK 实测（理想输出下界，模拟 %d 倍速，固定种子）" % int(TIME_SCALE))
	# 策略 A：完美换甲，两档 DPS
	for s in 5:
		await _measure(s + 1, true, DPS_A)
		await _measure(s + 1, true, DPS_B)
	# 策略 B：不换甲，只跑基准 DPS（对照组，量化「换甲值多少时间」）
	for s in 5:
		await _measure(s + 1, false, DPS_A)

	Engine.time_scale = 1.0
	Pool.clear()
	await _frames(2)
	print("[PACE] DONE")
	get_tree().quit(0)


func _measure(stage: int, perfect: bool, dps: float) -> void:
	Game.current_stage = stage
	Game.picked_armors = [Game.RED, Game.BLUE]
	_lv = Level.new()
	add_child(_lv)
	await _frames(3)
	_lv._running = false          # 掐掉 _run() 的波次流程，只留 Boss
	await _frames(3)
	_lv._running = true
	_lv.stage = stage
	_lv._boss_fight()
	await _frames(30)
	_boss = _lv.boss
	if _boss == null or not is_instance_valid(_boss):
		print("[PACE] L%d 完美=%s DPS=%d | Boss 生成失败" % [stage, perfect, int(dps)])
		_lv.queue_free()
		await _frames(2)
		return
	# 入场动画期间不算时间（Boss 还没站到位，玩家打不着）
	var g := 0
	while _boss._st != "fight" and g < 900:
		await _frames(10)
		g += 10
	if _boss._st != "fight":
		print("[PACE] L%d 完美=%s DPS=%d | Boss 未进入 fight" % [stage, perfect, int(dps)])
		_lv.queue_free()
		await _frames(2)
		return
	_t = 0.0
	_acc = 0.0
	_dps = dps
	_perfect = perfect
	_live = true
	while _live and is_instance_valid(_boss) and _boss.hp > 0 and _t < TTK_CAP:
		await _frames(1)
	_live = false
	var left := _boss.hp if is_instance_valid(_boss) else -1
	print("[PACE] L%d | %s | DPS %d | TTK %.1f s | 剩余血量 %d" % [
		stage, "完美换甲" if perfect else "不换甲  ", int(dps), _t, left])
	_lv.queue_free()
	_boss = null
	await _frames(4)
