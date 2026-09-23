class_name Boss4
extends Boss
## ---------------------------------------------------------------
## L4 深渊之喉（星盗母舰）—— 相位壁 + 子核心分裂 + 增援召唤
##
## 为什么拆子类：ADR-3 的反转条件是「单个 Boss 的独有分支 > 60 行」。
##   L4 的**全部**差异化就是这套子核心机制（免伤 / 分裂 / 共享 / 召唤 / 暴露期），
##   塞进基类会让它长出第二个状态机；砍掉它 L4 就只剩一个换皮血包。
##   `Level._make_boss()` 已按关号探测 `res://scripts/entities/Boss4.gd`，无需改 Level。
##
## 规格**逐条照搬**设计总纲 §D.4，**本文件不自拟任何数值**（全部走 StageCfg）：
##   · 相位壁：子核心存活期间本体免伤 80%
##   · 分裂：P1 = 1 只 / P2 = 2 只 / P3 = 2 只
##   · 子核心可全额打击，与本体伤害共享 40%
##   · 子核心每 4.0s 召 2 只星盗（色 ∈ S'，骚扰性质），场上增援上限 6 只
##   · 子核心全灭 → 6.0s 暴露期（相位壁消失 / 本体全额 / 展属性护罩 ∈S）
##   · 暴露期结束 → 重新分裂
##   · 阶段切换（67% / 34%）：清屏 + 全部子核心自爆（白送一次暴露期）
##   · 狂暴（跌破 30%）：子核心常驻 2 只、召唤 4.0s → 2.0s、暴露期 6.0s → 4.5s
##
## ⚠ 死锁防线（主理人裁定，必须保留）：
##   狂暴后子核心「常驻不消失」，而暴露期原本由「子核心全灭」触发 ——
##   狂暴后这个条件**永远不成立**，Boss 会变成无敌。
##   解法：狂暴后改为**每 4.5s 强制开一次暴露期**（子核心仍在场，但相位壁落下、
##   本体全额受伤）。验证方法：狂暴状态下持续输出，Boss 血量必须能掉到 0。
## ---------------------------------------------------------------

const SHARE := 0.40             # 子核心 → 本体 的伤害共享比例
const SUMMON_N := 2             # 每次召唤几只
const MAX_REINFORCE := 6        # 场上增援上限（与 EnemyKind.MAX_REINFORCE 同值）
const RAGE_FORCE_EXPOSE_CD := 4.5   # 狂暴后强制暴露期间隔（死锁防线）

## 子核心：可全额打击的小型 Damageable，围绕本体公转
class SubCore extends Damageable:
	const R := 30.0
	var boss_ref: Boss4 = null
	var color := 0
	var _hp := 0
	var _a := 0.0        # 公转角
	var _flash := 0.0
	var dead := false

	func setup(b: Boss4, c: int, ang: float, hp: int) -> void:
		boss_ref = b
		color = c
		_a = ang
		_hp = hp
		dead = false
		_flash = 0.0
		set_process(true)
		visible = true
		queue_redraw()

	func _ready() -> void:
		collision_layer = 4   # bit2 敌人（光刃打得到）
		collision_mask = 0
		z_index = 11
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = R
		cs.shape = sh
		add_child(cs)

	func _process(delta: float) -> void:
		if boss_ref == null or not is_instance_valid(boss_ref) or dead:
			return
		_a += delta * 0.9
		# 轨道按 R_MAIN 比例化（§1.8 v4）：L4 @R_MAIN 77 × 1.95 = 150.15 ≈ 旧写死 150.0
		position = boss_ref.position + Vector2.RIGHT.rotated(_a) \
			* (StageCfg.boss_r_main(boss_ref.stage) * 1.95)
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

	func hit(dmg: int, _c: int) -> void:
		if dead or boss_ref == null or not is_instance_valid(boss_ref):
			return
		var real := maxi(1, dmg)
		_hp -= real
		_flash = 0.09
		# 伤害共享：打子核心**同时**掉本体血 40%（避免"白打"）。
		#   0.40 直接内联 —— 内部类不保证能读到外层 const。
		var shared := maxi(1, int(roundf(float(real) * 0.40)))
		boss_ref._hp_share_from_core(shared)
		if _hp <= 0:
			_die()

	func _die() -> void:
		if dead:
			return
		dead = true
		set_process(false)
		visible = false
		if boss_ref != null and is_instance_valid(boss_ref):
			Fx.burst(boss_ref.world, position, Game.COLOR_GLOW[color], 14, 260.0, 0.5)
			boss_ref._on_core_dead(self)
		_detach.call_deferred()

	func _detach() -> void:
		if get_parent() != null:
			get_parent().remove_child(self)
		queue_free()

	func _draw() -> void:
		if dead:
			return
		var m: Color = Game.COLOR_MAIN[color]
		var g: Color = Game.COLOR_GLOW[color]
		var k: Color = Game.COLOR_CORE[color]
		draw_circle(Vector2.ZERO, R + 6.0, Color(g.r, g.g, g.b, 0.18))
		draw_circle(Vector2.ZERO, R, Game.COLOR_DARK[color])
		draw_circle(Vector2.ZERO, R * 0.58, m)
		draw_circle(Vector2.ZERO, R * 0.30, k)
		if _flash > 0.0:
			draw_circle(Vector2.ZERO, R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.0))


var _cores: Array[SubCore] = []
var _reinforce: Array[Enemy] = []
var _summon_t := 0.0
var _expose_t := 0.0
var _rage_force_t := 0.0
## 暴露期标志位 `_exposed_win` 声明在**基类** Boss 上（基类 `_ward()` 的三态分派读它），
##   这里**不得重复声明**（GDScript 不允许子类重名成员），直接复用基类的。


## **公开派生量：子核心暴露期**（02 §7.2 缓解口径）。
##   三个绘制层（⑥ 机库牵引闸门 / ⑦c 能量索 / ⑨ 护罩弧）**都读这一个布尔量**，
##   而不是各自从 `_cores.is_empty()` 推 —— 后者会让「闸门关了但护罩没开」
##   「能量索还在但护罩已开」这类传达**互斥玩法信息**的帧出现（打子核心 vs 换甲破罩）。
##   `BossArt` 不 import `Boss4`（循环依赖），走 `Object.has_method()` + `Object.call()` 读它，
##   读不到就降级读基类字段 `_exposed_win`，再读不到按「非暴露期」画基础形态，不会崩绘制。
func is_exposed() -> bool:
	return _exposed_win


func _ready() -> void:
	super._ready()
	# 只在 EXPOSED 模式（L4）启用子核心；其它关号万一走到这里也不误开
	if _ward_mode == StageCfg.WardMode.EXPOSED:
		_split_cores()


## 先跑子核心状态机，再走基类攻击循环 —— 这样基类里的 early return
## （重构硬直 / 散热期）不会把子核心逻辑一起跳过。
func _attack(delta: float) -> void:
	_tick_cores(delta)
	super._attack(delta)


## 本体陨落时**必须**把子核心一并清掉：否则它们会作为孤儿节点留在场上
## （既挡视线又泄漏 ObjectDB）。设计 §D.4 没写这条，属实现必然而非设计变更。
func _die() -> void:
	for core in _cores:
		if core != null and is_instance_valid(core) and not core.dead:
			core.dead = true
			core.set_process(false)
			core.visible = false
			core._detach.call_deferred()
	_cores.clear()
	_exposed_win = false
	super._die()


func _tick_cores(delta: float) -> void:
	if _st != "fight":
		return
	# ① 暴露期倒计时
	if _expose_t > 0.0:
		_expose_t -= delta
		if _expose_t <= 0.0:
			_exit_expose()
	# ② 狂暴死锁防线：子核心常驻时全灭条件永不成立，改为定时强制开暴露期
	if enraged and not _exposed_win:
		_rage_force_t -= delta
		if _rage_force_t <= 0.0:
			_rage_force_t = RAGE_FORCE_EXPOSE_CD
			_enter_expose()
	# ③ 增援召唤
	if not _cores.is_empty():
		_summon_t -= delta
		if _summon_t <= 0.0:
			_summon_t = StageCfg.summon_cd_rage(stage) if enraged \
				else StageCfg.summon_cd(stage)
			_summon()


# ------------------------------------------------------------ 子核心生命周期
## 分裂：P1 = 1 只 / P2 = 2 只 / P3 = 2 只（狂暴后恒 2 只）
func _split_cores() -> void:
	var n := 2 if (phase >= 2 or enraged) else 1
	# 配色铁律：**两只都 ∈ S** —— A = armors[0]、B = armors[1]。
	#   |S| 正好是 2，这样既严格 ∈ S（不会破罩死局），视觉上仍是两种不同颜色，
	#   完整保留设计「一红一蓝」的对比意图。一只都不许进 S'。
	var pool: Array[int] = []
	for c in player_armors:
		pool.append(int(c))
	if pool.is_empty():
		pool = [Game.RED, Game.BLUE]     # 兜底：拿不到战甲时不凭空造死局
	for i in n:
		var c: int = pool[i % pool.size()]
		var core := SubCore.new()
		core.setup(self, c, TAU * float(i) / float(n), 260)
		if world != null:
			world.add_child(core)
			_cores.append(core)
		else:
			core.queue_free()
	_exposed_win = false
	_summon_t = StageCfg.summon_cd(stage)


func _on_core_dead(core: SubCore) -> void:
	_cores.erase(core)
	# 暴露期触发条件：**子核心全灭**（不是计时、不是血量）
	if _cores.is_empty():
		_enter_expose()


func _enter_expose() -> void:
	if _st == "dying":
		return
	_exposed_win = true                  # ← 基类 _ward() 靠它展罩
	var dur: float = StageCfg.expose_time_rage(stage) if enraged \
		else StageCfg.expose_time(stage)
	_expose_t = dur
	_rage_force_t = RAGE_FORCE_EXPOSE_CD
	Fx.ring(world, position, Game.COLOR_MAIN[Game.WHITE], 40.0, 380.0, 0.6, 10.0)
	Fx.pop(self, Vector2(0.0, -84.0), "相位壁落下 · 暴露 %.1f 秒" % dur,
		Game.COLOR_MAIN[Game.WHITE], 17)


func _exit_expose() -> void:
	_expose_t = 0.0
	_exposed_win = false
	# 狂暴后子核心**仍常驻**（不再消失），但暴露期已由定时强制兜住，不会死锁
	_split_cores()


## 子核心 → 本体的伤害共享（只掉血，不触发阶段/狂暴重算之外的副作用）
func _hp_share_from_core(amount: int) -> void:
	if _st == "dying":
		return
	hp = maxi(0, hp - amount)
	hp_ratio.emit(clampf(float(hp) / float(max_hp), 0.0, 1.0))
	if hp <= 0:
		hp = 0
		_die()
		return
	_check_phase()
	_check_enrage()


# ------------------------------------------------------------ 受击：相位壁
## 子核心存活 → 相位壁展开，本体免伤 80%；全灭（暴露期）→ 本体全额 + 护罩
func hit(dmg: int, c: int) -> void:
	if _st == "dying":
		return
	var mul := 1.0
	if ward >= 0:
		mul = 1.0 if c == ward else _off_color
	if not _cores.is_empty() and not _exposed_win:
		# 相位壁：**免伤**不是属性护罩，不触可行性铁律
		mul *= 1.0 - StageCfg.sub_core_resist(stage)
	var real := maxi(1, int(roundf(float(dmg) * mul)))
	hp -= real
	_flash = 0.09
	hp_ratio.emit(clampf(float(hp) / float(max_hp), 0.0, 1.0))
	if real >= int(roundf(float(dmg) * 0.9)):
		Fx.pop(self, Vector2(0.0, -70.0), "击穿 %d" % real,
			Game.COLOR_MAIN[ward] if ward >= 0 else Color(0.8, 0.85, 0.95), 17)
	else:
		Fx.pop(self, Vector2(0.0, -70.0), "相位壁 %d" % real,
			Color(0.62, 0.66, 0.75), 15)
	if hp <= 0:
		hp = 0
		_die()
		return
	_check_phase()
	_check_enrage()


# ------------------------------------------------------------ 阶段切换 / 狂暴
## 阶段切换：清屏 + **全部子核心自爆**（白送一次暴露期）
func _on_phase() -> void:
	_clear_bullets()
	for core in _cores:
		if core != null and is_instance_valid(core) and not core.dead:
			core._die()
	_cores.clear()
	ward = -1
	_ward_t = 2.4
	ward_chg.emit(-1)
	_cast = 1.3
	_tick = _cast
	_skill = "ring_white"
	Fx.shock(world, position, Color(1.0, 1.0, 1.0), 640.0, 0.9)
	Fx.ring(world, position, Game.COLOR_MAIN[Game.WHITE], 40.0, 420.0, 0.7, 12.0)
	phase_chg.emit(phase)
	_enter_expose()


# ------------------------------------------------------------ 增援召唤
## 每 4.0s（狂暴 2.0s）召 2 只星盗，色 ∈ S'（骚扰性质），场上上限 6 只
func _summon() -> void:
	if world == null:
		return
	# 先清掉已离场的引用
	var alive: Array[Enemy] = []
	for e in _reinforce:
		if e != null and is_instance_valid(e):
			alive.append(e)
	_reinforce = alive
	if _reinforce.size() >= MAX_REINFORCE:
		return
	var others := _complement_colors()
	if others.is_empty():
		return
	for i in SUMMON_N:
		if _reinforce.size() >= MAX_REINFORCE:
			break
		var c: int = others[randi() % others.size()]
		var y := randf() * (Game.VIEW_H - 300.0) + 150.0
		var e := Spawner.enemy(world, EnemyKind.K.GRUNT, c, "hover", y,
			StageCfg.stage_hp_scale(stage), stage)
		if e == null:
			return
		e.no_block_clear = true        # 增援拖不住清场（设计 §E.3）
		_reinforce.append(e)


## S 的补集 S'：四色里玩家**没有**的那两色
func _complement_colors() -> Array[int]:
	var out: Array[int] = []
	for c in 4:
		if not player_armors.has(c):
			out.append(c)
	return out
