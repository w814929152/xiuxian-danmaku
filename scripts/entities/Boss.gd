class_name Boss
extends Damageable
## 关卡 Boss · 星盗旗舰（五个各不相同：熔核 / 霜噬 / 耀斑 / 深渊之喉 / 终焉）
## 会周期性展开【属性护罩】：只有同色光刃能造成全额伤害，异色衰减
## 护罩颜色只会从玩家选定的两件战甲中抽取 —— 逼迫玩家在战斗中换甲
##
## **五关改造后本文件不再有难度维度**：三档难度（简单 / 普通 / 困难）已移除，
##   一切参数由 `stage`（1..5）驱动，经 `StageCfg` 的带返回类型访问器注入。
##   （历史值：简单 1400 / 普通 2500 / 困难 3600 —— 已作废，勿再引用。）
##
## 护罩模式是**三态**而非布尔：`WardMode.NONE / ALWAYS / EXPOSED`
##   L2 / L3 = NONE（永不展罩）· L1 / L5 = ALWAYS（全程）· L4 = EXPOSED（仅暴露期，
##   由 `Boss4` 的子核心状态机置 `_exposed_win`）。
##
## 狂暴阈值逐关不同（L1~L4 = 30%、L5 = 25%），走 `StageCfg.enrage_at()`。
##
## 子类：`Boss4.gd`（L4 深渊之喉 · 子核心状态机）。**L5 不拆子类** —— 见架构文档
##   ADR-3 下的「L4 拆 / L5 不拆」小节：L5 四相全靠 `BossCfg._L5_P1.._L5_P4` +
##   `StageCfg.phase_marks()` 数据驱动，基类里只有 1 行 L5 专属分支。

signal boss_died()
signal hp_ratio(r: float)
signal phase_chg(p: int)
signal ward_chg(c: int)
## 进入狂暴（血量跌破本关阈值 `StageCfg.enrage_at(stage)`）—— 由 Level 接去放横幅。
##   逐关不同：L1~L4 = 30%，L5 = 25%（流程更长，狂暴点更晚）。
signal enrage_started()

const POOL: Dictionary[int, Array] = {
	1: ["fan_red", "aim_blue", "rain_red"],
	2: ["ring_white", "spiral_rb", "rain_blue", "fan_red", "fan_yellow"],
	3: ["chaos", "spiral_rb", "ring_white", "homing", "rain_yellow"],
}
const DUR: Dictionary[String, float] = {
	"fan_red": 3.2, "aim_blue": 3.0, "rain_red": 3.0, "rain_blue": 3.0,
	"ring_white": 3.4, "spiral_rb": 4.2, "chaos": 4.4, "homing": 3.6,
	"fan_yellow": 3.0, "rain_yellow": 3.2,
}
const TICK: Dictionary[String, float] = {
	"fan_red": 0.60, "aim_blue": 0.55, "rain_red": 0.17, "rain_blue": 0.22,
	"ring_white": 0.80, "spiral_rb": 0.075, "chaos": 0.13, "homing": 0.45,
	"fan_yellow": 0.70, "rain_yellow": 0.20,
}

## 本局真实血量上限 —— HUD 与阶段判定都用它。
## 铁律：血上限只用实例变量，不用常量（旧 const MAX_HP 已删）。
var max_hp := 0
var hp := 0
## 关卡号。0 = **未注入**（过渡期走旧难度访问器）· 1..5 = 五关（走 StageCfg）。
##
## ⚠ 为什么默认不是 1：Level 现在还没注入 stage，而 SelfTest 仍断言难度档血量
##   （简单 1400 / 困难 3600）与「简单档两阶段 = 1 条刻度」。若默认 1，门禁当场打红。
##   过渡期双路径，等 Level 注入 `boss.stage = N` 后自动切到 StageCfg 路径；
##   S9 迁移完 SelfTest 后，把默认值改成 1 并删掉 else 分支。
var stage: int = 0
## HUD / 横幅显示的全名，例如「熔核号 · 星盗先驱」
## 默认**空串**而不是「星盗旗舰」：五关路径下 _ready() 会立刻写入 StageCfg 的真名，
## 留一个非空兜底只会掩盖「stage 忘了注入」这类静默失败（R-02 同族）。
## HUD 侧禁止硬编码任何 Boss 名，一律读 boss.title。
var title: String = ""
## 短名，存档 / 调试 / 关卡卡面，例如「熔核号」。同上，默认空串。
var boss_name: String = ""
var phase := 1
var player_ref: Player = null
var player_armors: Array[int] = []
## 由 Level 显式注入：弹幕与特效的挂载容器
var world: Node2D = null
## 狂暴中：周身泛红光 + 各关专属的机制加压（见 StageCfg 的 *_rage 系列）
## 注：狂暴**不再**叠加一层专属弹幕（原「四色螺旋」已按用户要求移除）——
##   狂暴的压力改由各关自己的旋钮承担（护罩轮转加快 / 散热窗口缩短 / 召唤变密）。
var enraged := false

var ward := -1
var _ward_t := 4.0
var _ward_anim := 0.0
## 难度参数在 _ready 里从 Game 取一次，之后不再查全局
var _phases := 3
## 护罩模式**三态**（不是 bool）—— 主理人终裁 2026-09-22：
##   旧代码 `_has_ward = boss_ward(s)` 只有 bool，分不出 ALWAYS / EXPOSED，
##   导致 L4（EXPOSED）退化成全程护罩：相位壁免伤 80% × 护罩异色 0.60 两条减伤叠加，
##   玩家在相位壁期基本零收益，且 L4「只在暴露期展罩」的差异化整个丢失。
var _ward_mode: int = StageCfg.WardMode.ALWAYS
## 暴露期标志位 —— 只有 `WardMode.EXPOSED`（L4 深渊之喉）才看它。
##   由子类 `Boss4` 的子核心状态机置位（子核心全灭 → 暴露期）。基类恒为 false，
##   即「没有子核心机制就没有暴露期」，不会误展护罩。
var _exposed_win := false
var _bullet_k := 1.0
var _off_color := 1.0
## 五关路径下由 StageCfg 注入的派生参数（旧难度路径保持零值 / 默认）
var _enrage_at := 0.30      # 由 _ready() 按 stage 覆写（StageCfg.enrage_at）
var _ward_cd := 0.0        # 护罩展开时长；0 = 沿用旧写法的 5.2s
var _ward_cd_rage := 0.0
var _ward_tell := 0.0      # 换色预告时长（秒）—— 读得出来，不靠背板
var _resist := 0.0         # 常驻减伤（与颜色无关）：L3 耀斑号 = 0.70
var _body_color := -1      # 本体固定色；-1 = 跟随护罩色（L1 熔核号 = 光子白）
## L3 耀斑号【散热期】：装甲舱盖打开 -> 任意颜色伤害 ×1.8（狂暴 ×2.4）
##   倍率由 StageCfg.heat_mul() 给，本类不硬编码；2026-09-22 由 ×3.0/×4.0 下调。
##   _heat_win = 本阶段散热时长（0 = 非 L3，不触发）；_heat_t = 剩余时长
var _heat_win := 0.0
var _heat_t := 0.0
## 狂暴散热期结束的近距离冲击环（半径 / 伤害）取自 BossCfg —— 本文件只留逻辑。
## 散热期中 —— **字段名 `venting` 已定为跨线契约**：
##   HUD 用 `Object.get("venting")` 读它（缺字段按「非散热期」降级，不会崩 HUD），
##   这是 L3「散热期高倍率」能被玩家看见的唯一通道，**改名必须先同步 HUD**。
## Boss 自己也在三处消费：hit() 决定倍率、_draw() 画舱盖打开、_attack() 停火。
var venting := false
## L5 终焉号【重构硬直】：阶段切换后 1.0s 完全停火（三次切换 = 三个呼吸点）
var _refit_t := 0.0

var _t := 0.0
var _st := "enter"
var _skill := ""
var _cast := 0.0
var _tick := 0.0
var _skill_t := 0.0
var _spiral := 0.0
var _flash := 0.0
var _base_y := 360.0
var _home_x := 985.0


func _ready() -> void:
	# 五关改造后**没有难度维度**，`stage` 必须在 add_child 之前由 Level 注入
	# （`Level._boss_fight()` 已这么做）。这里把「越界」钉成「不会发生」，
	#   而不是再留一条走旧 `Game.boss_hp()` 的兜底分支 —— 那条分支会让
	#   「五关参数到底从哪来」有两个答案，是真实踩过的坑。
	if stage < 1:
		stage = 1
	collision_layer = 4   # bit2 敌人
	collision_mask = 2    # bit1 玩家子弹
	z_index = 10
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	# 碰撞半径逐关不同（46/52/58/65/70，规格 §C.1）。
	# 本体/碰撞比（剪影最远角 × R_MAIN ÷ R_HIT，V5 口径）实测 1.19~1.22，非单调：
	# L1 1.217 → L2 1.212 → L3 1.206 → L4 1.193（最小）→ L5 1.224（最大，
	# 即最接近 1.34 上限、最紧的一关）。勿按「越往后越小」推断。
	# ⚠ 该比值 = (R_MAIN / R_HIT) × 剪影形状系数，两者都算：L3 曾因炮垒四角外突
	#   做到 1.456，而它的 R_MAIN/R_HIT 只有 1.207。改剪影形状必须重跑 V5。
	sh.radius = float(StageCfg.boss_radius(stage))
	cs.shape = sh
	add_child(cs)
	# 星盗旗舰：全矢量绘制（见 _draw），不再挂 boss.png 像素 sprite
	position = Vector2(Game.VIEW_W + 220.0, _base_y)
	# ---- 一切参数来自 StageCfg（设计总纲 §F 权威值），按 stage 注入 ----
	max_hp = StageCfg.boss_hp(stage)
	_phases = StageCfg.boss_phases(stage)
	_ward_mode = StageCfg.ward_mode(stage)
	_bullet_k = StageCfg.bullet_scale(stage)
	_off_color = StageCfg.off_color_mul(stage)
	_enrage_at = StageCfg.enrage_at(stage)
	_ward_cd = StageCfg.ward_cd(stage)
	_ward_cd_rage = StageCfg.ward_cd_rage(stage)
	_ward_tell = StageCfg.ward_telegraph(stage)
	_resist = StageCfg.resident_resist(stage)
	_body_color = StageCfg.body_color(stage)
	# 称号不硬编码：五关各有一个（熔核号 / 霜噬号 / 耀斑号 / 深渊之喉 / 终焉号）
	title = StageCfg.boss_full_name(stage)
	boss_name = StageCfg.boss_name(stage)
	# L3 散热期时长按阶段缩短（3.0 / 2.2 / 1.6），非 L3 返回 0 = 不触发
	_heat_win = StageCfg.heat_window(stage, 1)
	hp = max_hp


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_ward_anim += delta
	match _st:
		"enter":
			position.x = move_toward(position.x, _home_x, 260.0 * delta)
			position.y = _base_y
			if absf(position.x - _home_x) < 2.0:
				_st = "fight"
				_next_skill()
		"idle":
			# 玩家已陨落：只飘着，不再开火 / 不再展开护罩
			_move(delta)
		"fight":
			_move(delta)
			_ward(delta)
			_attack(delta)
			_check_enrage()
	queue_redraw()


## 由 Level 在玩家陨落时调用：收手罢战
func stand_down() -> void:
	if _st == "dying":
		return
	_st = "idle"
	ward = -1
	ward_chg.emit(-1)


func _move(delta: float) -> void:
	var fast := 1.0 if phase < _phases else 1.6
	position.y = _base_y + sin(_t * 0.42 * TAU * fast) * 132.0
	position.x = _home_x + sin(_t * 0.27 * TAU) * 62.0


# ------------------------------------------------------------ 可行性铁律（后续工程师必读）
## 【强制 ∈ S】任何带颜色的机制 —— **旗舰护罩 / 战将力场 / L4 子核心** —— 其色必须
## 取自玩家已选的两件战甲 S（`player_armors`）。**没有例外，也不是「可选项」**。
##
## 设计 §H.1 曾把「L4 子核心可能 ∈ S'」标为 ⚠️ 可选项，理由是「子核心无必须同色才能破，
## 异色全额，不是死局」。**主理人已裁定：不做可选项**，三条理由：
##   1. 玩家两件战甲是自选的，S' 是补集 —— 系统无法预知哪只子核心会落在玩家打不动的那一色；
##      「异色全额」只是把死局降级成「这一路白打」，体验上没有本质区别。
##   2. 必须与 L1 / L5 的护罩、L4 / L5 的战将力场**同一口径**，否则可行性断言要为
##      每个机制各写一条特例。
##   3. 强制 ∈ S 后，S0 那条常驻回归断言可以**一条覆盖全部带色机制**，断言面最干净。
##
## 定性照抄 Elite.gd 文件头：凭空给个玩家没带的颜色，破罩就成了死局 ——
## **那不是难度，是设计事故。**
##
## 实施时子核心取色（S5 接入 L4 子类时照此写）：
##   var sub_colors := player.armors.duplicate()   # 直接取玩家两件战甲的色，不另抽、不加权
## 并在 SelfTest 补一条断言：子核心色 ∈ 玩家战甲（与护罩 / 力场两条并列）。
# ------------------------------------------------------------ 属性护罩
func _ward(delta: float) -> void:
	# 三态分派：NONE 永不展 / ALWAYS 全程 / EXPOSED 只在暴露期展
	if _ward_mode == StageCfg.WardMode.NONE:
		return                 # L2 / L3：旗舰不展护罩
	if _ward_mode == StageCfg.WardMode.EXPOSED and not _exposed_win:
		return                 # L4：相位壁期不展护罩（相位壁是免伤，不是属性护罩）
	_ward_t -= delta
	if _ward_t > 0.0:
		return
	if ward >= 0:
		ward = -1
		_ward_t = 3.2 + randf() * 1.6
	else:
		if player_armors.is_empty():
			_ward_t = 3.0
			return
		ward = player_armors[randi() % player_armors.size()]
		# 护罩展开时长：五关路径取自 StageCfg（狂暴后更短）；旧路径沿用 5.2s
		if enraged and _ward_cd_rage > 0.0:
			_ward_t = _ward_cd_rage
		elif _ward_cd > 0.0:
			_ward_t = _ward_cd
		else:
			_ward_t = 5.2
		_ward_anim = 0.0
		Fx.ring(world, position, Game.COLOR_MAIN[ward], 60.0, 150.0, 0.45, 8.0)
	ward_chg.emit(ward)


# ------------------------------------------------------------ 弹幕编排
func _next_skill() -> void:
	# 五关路径取 BossCfg 的「本关本相」技能池；过渡期沿用旧的三阶段 POOL 表。
	# ⚠ 不能用三元表达式：POOL[phase] 是未类型化 Array，与 Array[String] 混在同一个
	#   `var pool :=` 里会让运行时报「Trying to assign an array of type Array to
	#   a variable of type Array[String]」—— 两条路径分开写，池子显式转成 Array[String]。
	var pool: Array[String] = []
	if stage >= 1:
		pool = BossCfg.pool(stage, phase)
	else:
		for sk in POOL[phase]:
			pool.append(str(sk))
	if pool.is_empty():
		push_warning("BossCfg.pool(%d, %d) 返回空池，回退 fan_red" % [stage, phase])
		_skill = "fan_red"
		_cast = BossCfg.dur_of(_skill)
		_tick = 0.25
		_skill_t = 0.0
		return
	var pick: String = str(pool[randi() % pool.size()])
	if pool.size() > 1 and pick == _skill:
		pick = pool[(pool.find(pick) + 1) % pool.size()]
	_skill = pick
	_cast = BossCfg.dur_of(_skill)
	_tick = 0.25
	_skill_t = 0.0


func _attack(delta: float) -> void:
	# L5 终焉号【重构硬直】：阶段切换后 1.0s 完全停火 —— 三次切换 = 三个呼吸点
	if _refit_t > 0.0:
		_refit_t -= delta
		return
	# L3 耀斑号【散热期】：停火散热、装甲舱盖打开 —— 这是玩家唯一的输出窗口。
	#   散热期结束必须 _next_skill()（它会重置 _cast），否则 _cast 一直 <= 0，
	#   下一帧又进一次散热期 -> 无限散热。
	if _heat_t > 0.0:
		_heat_t -= delta
		if _heat_t <= 0.0:
			_heat_t = 0.0
			venting = false
			# 狂暴期【散热结束 = 喷一次近距离冲击环】：窗口不再是纯站桩输出位，
			#   打完必须撤（设计总纲 §D.3）。非狂暴不喷 —— 常态散热期是安全窗口。
			if enraged:
				Fx.ring(world, position, Game.COLOR_MAIN[Game.RED],
					40.0, BossCfg.HEAT_BLAST_R, 0.45, 11.0)
				# 半径内判定玩家（照 BossMine._boom() 的写法：距离判定，不走碰撞）
				var blast_p := _live_player()
				if blast_p != null:
					if blast_p.position.distance_to(position) <= BossCfg.HEAT_BLAST_R:
						blast_p.take_hit(Game.RED, BossCfg.HEAT_BLAST_DMG)
			_next_skill()
		return
	_cast -= delta
	_tick -= delta
	if _tick <= 0.0:
		_skill_t += 1.0
		_cast_step()
		# 弹幕密度：系数越小，同一套路的发射间隔越长
		_tick = BossCfg.tick_of(_skill) / _bullet_k
	if _cast <= 0.0:
		# 齐射结束：L3 进入散热期（停火），其余旗舰直接开下一轮
		var hw := StageCfg.heat_window(stage, phase) if stage >= 1 else 0.0
		if enraged and stage >= 1:
			hw = StageCfg.heat_window_rage(stage)
		if hw > 0.0:
			_enter_heat(hw)
		else:
			_next_skill()


## L3 耀斑号：进入散热期。时长随阶段缩短（3.0 / 2.2 / 1.6），狂暴后固定 1.2s。
func _enter_heat(w: float) -> void:
	_heat_t = w
	venting = true
	Fx.ring(world, position, Game.COLOR_GLOW[Game.RED], 40.0, 170.0, 0.45, 9.0)
	Fx.pop(self, Vector2(0.0, -84.0), "散热 %.1f 秒" % w,
		Game.COLOR_MAIN[Game.RED], 17)


## L5 终焉号相④：投出引力雷（8s 自毁；被光刃打中会提前引爆 —— 玩家可主动清场）
func _toss_mines(n: int) -> void:
	if world == null:
		return
	for _i in _n(n):
		var x := randf() * (Game.VIEW_W - 260.0) + 130.0
		var y := randf() * (Game.VIEW_H - 300.0) + 150.0
		BossMine.spawn(world, Game.YELLOW, Vector2(x, y), _live_player())


## 一次齐射的数量也按密度收缩（至少 1 发，不能归零）
func _n(base: int) -> int:
	return maxi(1, int(roundf(float(base) * _bullet_k)))


# ------------------------------------------------------------ 狂暴
func _check_enrage() -> void:
	if enraged or _st != "fight":
		return
	if float(hp) / float(max_hp) > _enrage_at:
		return
	enraged = true
	Fx.shock(world, position, Color(1.0, 0.22, 0.18), 660.0, 0.9)
	Fx.ring(world, position, Color(1.0, 0.28, 0.20), 40.0, 400.0, 0.70, 12.0)
	enrage_started.emit()


func _cast_step() -> void:
	match _skill:
		"fan_red":
			_fan(Game.RED, _n(11), 1.15, 255.0, 9.0)
		"aim_blue":
			for i in _n(3):
				_b(Game.BLUE, _aim().rotated((i - 1) * 0.06), 390.0, 8.0, 10, 0.0)
		"rain_red":
			_rain(Game.RED, _n(2), 0.0)
		"rain_blue":
			_rain(Game.BLUE, _n(2), 0.55)
		"fan_yellow":
			_fan(Game.YELLOW, _n(7), 1.00, 225.0, 10.0)
		"rain_yellow":
			_rain(Game.YELLOW, _n(2), 0.35)
		"ring_white":
			_ring(Game.WHITE, _n(24), 215.0, _skill_t * 0.22, 10.0)
		"ring_blue":
			# L5 相② 霜环·蓝：冰晶蓝同心环（30 发慢自转）。
			#   ⚠ 与 ring_white 唯一差别就是色参 —— 白弹不得出现在非白相，故不能复用它。
			_ring(Game.BLUE, _n(30), 215.0, _skill_t * 0.22, 10.0)
		"spiral_rb":
			_spiral += 0.36
			_b(Game.RED, Vector2.RIGHT.rotated(_spiral), 235.0, 9.0, 10, 0.0)
			_b(Game.BLUE, Vector2.RIGHT.rotated(_spiral + PI), 235.0, 9.0, 10, 0.0)
		"chaos":
			for i in _n(3):
				var c: int = randi() % 4
				var a := randf() * TAU
				_b(c, Vector2.RIGHT.rotated(a), 180.0 + randf() * 130.0, 9.0, 10, 0.0)
		"homing":
			var c: int = ward if ward >= 0 else (randi() % 4)
			for i in _n(2):
				_b(c, _aim().rotated((i - 0.5) * 0.8), 205.0, 10.0, 10, 1.05)
		# ---------------- 设计 §D 新增原语（五个旗舰各自的技能语法）----------------
		"ring_slow":
			# L2 霜噬号：慢自转同心环，玩家可预判
			_ring(Game.WHITE, _n(24), 215.0, _skill_t * 0.22, 10.0)
		"cross_ray":
			# L2：匀速旋转的 N 臂射线（4 臂 → 6 臂）
			_ray_arms(6 if phase >= 3 else 4)
		"grid_rain":
			# L4 深渊之喉：等距固定列的列雨（留缝，可穿）—— **默认白弹，不动**
			#   列数一律读 `StageCfg.grid_cols`（L4 P3 = 7），不再就地写条件表达式
			_grid_rain(StageCfg.grid_cols(stage, phase), Game.WHITE)
		"grid_rain_blue":
			# L2 霜噬号 / L5 相②：冰晶蓝版列雨（主理人裁定 2026-09-22：
			#   不改 `grid_rain` 本体以免波及 L4 P3，另开一个原语）。
			#   列数同样读 `StageCfg.grid_cols`（L2 P2 = 6 / L2 P3 = 8 / L5 四相 = 8）
			_grid_rain(StageCfg.grid_cols(stage, phase), Game.BLUE)
		"fan_blue":
			_fan(Game.BLUE, _n(13), 1.25, 240.0, 9.0)
		"aim_white":
			# L3 / L5：白色速射点射
			for i in _n(5):
				_b(Game.WHITE, _aim().rotated((i - 2) * 0.05), 420.0, 8.0, 10, 0.0)
		"spiral_wb":
			_spiral += 0.30
			_b(Game.WHITE, Vector2.RIGHT.rotated(_spiral), 235.0, 9.0, 10, 0.0)
			_b(Game.BLUE, Vector2.RIGHT.rotated(_spiral + PI), 235.0, 9.0, 10, 0.0)
		"spiral_ry":
			_spiral += 0.34
			_b(Game.RED, Vector2.RIGHT.rotated(_spiral), 240.0, 9.0, 10, 0.0)
			_b(Game.YELLOW, Vector2.RIGHT.rotated(_spiral + PI), 240.0, 9.0, 10, 0.0)
		"spiral_4":
			_spiral += 0.40
			for i in 4:
				_b(i, Vector2.RIGHT.rotated(_spiral + TAU * float(i) / 4.0),
					250.0, 9.0, 10, 0.0)
		"mine_toss":
			# L5 相④：投 2 枚引力雷（8s 自毁，可被光刃提前引爆）。
			#   雷是 Boss 自己扔的，走 BossMine 的对象池，不经过 EnemyKind / Spawner。
			_toss_mines(2)
		# ---------------- L5 四相「自解释技能名」（验收清单 §2.5.1，纯增量）----------------
		#   与原名参数冲突，故另开名字；下面 7 条只服务 L5，老招一行未改。
		"fan_red_w":
			# 相① 熔核·红：15 发 / 1.35rad 宽扇（L1 `fan_red` = 11发 / 1.15rad）
			_fan(Game.RED, _n(15), 1.35, 255.0, 9.0)
		"rain_red_3":
			# 相①：3 发红雨（L1 / L4 `rain_red` = 2 发）
			_rain(Game.RED, _n(3), 0.0)
		"ring_white_x2":
			# 相③ 光子·白：34 发【双环反向】—— 两圈各 17 发，自转方向相反
			_ring(Game.WHITE, _n(34), 215.0, _skill_t * 0.22, 10.0, true)
		"aim_white_6":
			# 相③：6 发白色速射点射（L3 `aim_white` = 5 发）
			for i in _n(6):
				_b(Game.WHITE, _aim().rotated((i - 2) * 0.05), 420.0, 8.0, 10, 0.0)
		"homing_white":
			# 相③：3 发追尾**白弹**（`homing` 取 ward 色 / 随机色，白相会漏白，故另开）
			for i in _n(3):
				_b(Game.WHITE, _aim().rotated((i - 1) * 0.8), 205.0, 10.0, 10, 1.05)
		"rain_yellow_3":
			# 相④ 引力·黄：3 发黄雨（L3 `rain_yellow` = 2 发）
			_rain(Game.YELLOW, _n(3), 0.35)
		"mine_toss_y":
			# 相④：2 枚黄雷（8s 自毁 = EnemyCfg.MINE_LIFE，可被光刃提前引爆）
			_toss_mines(2)


## 匀速旋转的 N 臂射线（L2 霜噬号「cross_ray」）
func _ray_arms(n: int) -> void:
	var base := _skill_t * 0.55
	for i in n:
		_b(Game.WHITE, Vector2.RIGHT.rotated(base + TAU * float(i) / float(n)),
			260.0, 9.0, 10, 0.0)


## 等距固定列的列雨（L2 / L4 / L5「grid_rain」）—— 列位固定，缝隙规律，可穿
func _grid_rain(n: int, c: int) -> void:
	if world == null:
		return
	for i in n:
		var x := 120.0 + float(i) * (Game.VIEW_W - 240.0) / float(maxi(1, n - 1))
		var b := Danmaku.spawn(world, c, Vector2(x, -30.0),
			Vector2(-110.0, 235.0), 10, 9.0)
		if b == null:
			return
		b.turn = 0.0
		b.target = _live_player()


## 玩家可能已经阵亡并被 queue_free —— 那时 player_ref 是一个「已释放」对象：
## 读它的属性会崩，把它赋给弹幕的 target 更是直接报
## "Invalid assignment ... with value of type 'previously freed'"。
## 凡是想把玩家引用交出去的地方，一律走这里拿干净的引用。
func _live_player() -> Player:
	if player_ref != null and is_instance_valid(player_ref):
		return player_ref
	return null


func _aim() -> Vector2:
	var p := _live_player()
	if p != null:
		return (p.position - position).normalized()
	return Vector2.LEFT


func _fan(c: int, n: int, spread: float, sp: float, r: float) -> void:
	var base := _aim().angle()
	for i in n:
		var k := 0.0 if n <= 1 else (float(i) / float(n - 1) - 0.5)
		_b(c, Vector2.RIGHT.rotated(base + k * spread), sp, r, 10, 0.0)


## rev = true 时打【双环反向】（相③ `ring_white_x2`）：n 发拆成**两圈各 n/2**，
##   一圈随 off 正向自转、一圈随 -off 反向自转 —— **总发数不变**（34 发 = 两圈各 17）。
##   这是**加一个带默认值的形参**，不是重写：rev 默认 false，
##   `ring_white` / `ring_blue` / `ring_slow` 三个老调用点一行没动，行为完全不变。
func _ring(c: int, n: int, sp: float, off: float, r: float, rev := false) -> void:
	if not rev:
		for i in n:
			_b(c, Vector2.RIGHT.rotated(off + TAU * float(i) / float(n)), sp, r, 10, 0.0)
		return
	var half := maxi(1, n / 2)
	for i in half:
		var a := TAU * float(i) / float(half)
		_b(c, Vector2.RIGHT.rotated(off + a), sp, r, 10, 0.0)
		# 第二圈错开半格（PI / half），两圈不会在开火瞬间完全重合
		_b(c, Vector2.RIGHT.rotated(-off + a + PI / float(half)), sp, r, 10, 0.0)


## 天降灵雨：从屏幕上方落下并向左横扫
func _rain(c: int, n: int, turn: float) -> void:
	if world == null:
		return
	for i in n:
		var x := randf() * (Game.VIEW_W - 120.0) + 60.0
		var b := Danmaku.spawn(world, c, Vector2(x, -30.0), Vector2(-110.0, 235.0),
			10, 9.0)
		if b == null:
			return
		b.turn = turn
		b.target = _live_player()


func _b(c: int, dirv: Vector2, sp: float, r: float, dmg: int, turn: float) -> void:
	if world == null:
		return
	var dir := dirv.normalized()
	var b := Danmaku.spawn(world, c, position + dir * 52.0, dir * sp, dmg, r)
	if b == null:
		return
	b.turn = turn
	b.target = _live_player()


# ------------------------------------------------------------ 受击 / 阶段
func hit(dmg: int, c: int) -> void:
	if _st == "dying":
		return
	var mul := 1.0
	if ward >= 0:
		# 异色衰减由难度决定：简单 / 普通没有护罩，困难 = 60%
		mul = 1.0 if c == ward else _off_color
	# 常驻减伤 与 散热倍率 是**互斥分支，不是连乘**（主理人终裁 2026-09-22）。
	#   理由：散热期是「玩家唯一的输出窗口」，若写成 0.3 × 1.8 = 净 0.54，会出现
	#   「专门等到散热期打，伤害还不如打杂兵」—— 与奖励窗口的语义直接冲突。
	#   设计 §D.3「复位回 ×0.3」里的 ×1.8 指的是**最终倍率**，不是叠在减伤上的系数。
	#   L3 耀斑号：常态 0.3（常驻减伤 70%）/ 散热期 1.8 / 狂暴散热期 2.4。
	if venting:
		mul = StageCfg.heat_mul(stage, enraged)
	elif _resist > 0.0:
		mul *= 1.0 - _resist
	var real := maxi(1, int(roundf(float(dmg) * mul)))
	hp -= real
	_flash = 0.09
	hp_ratio.emit(clampf(float(hp) / float(max_hp), 0.0, 1.0))
	if ward >= 0:
		if mul >= 1.0:
			Fx.pop(self, Vector2(0.0, -70.0), "击穿 %d" % real,
				Game.COLOR_MAIN[ward], 17)
		else:
			Fx.pop(self, Vector2(0.0, -70.0), "抗性 %d" % real,
				Color(0.62, 0.66, 0.75), 15)
	if hp <= 0:
		hp = 0
		_die()
		return
	_check_phase()


## 阶段判定一律从「刻度线」推导 —— 与 HUD 画的线同源，绝不各写一套阈值。
## 刻度线 [m1, m2, m3]（由高到低）：当前血量比 r 每跌破一条，阶段 +1。
##   L1 [0.50]        → 2 阶段
##   L2~L4 [0.34,0.67] → 3 阶段
##   L5 [0.75,0.50,0.25] → 4 阶段
func _check_phase() -> void:
	var r := float(hp) / float(max_hp)
	var p := 1
	for m in phase_marks():
		if r <= m:
			p += 1
	if p != phase:
		phase = p
		_on_phase()


## HUD 画阶段刻度用：**1~3 条可变**（五关阶段数不同，HUD 不得写死两条）
func phase_marks() -> Array[float]:
	if stage >= 1:
		return StageCfg.phase_marks(stage)
	if _phases <= 2:
		return [0.5]
	return [0.34, 0.67]


func _on_phase() -> void:
	_clear_bullets()
	ward = -1
	_ward_t = 2.4
	ward_chg.emit(-1)
	_cast = 1.3
	_tick = _cast
	# 阶段切换的【宣告环】：主题色由 `StageCfg.phase_theme_color` 给，
	#   —— 不写 `stage >= 5` 之类的硬编码分支，那是把数据驱动倒退回代码分支。
	#   -1 = 无主题色（L1~L4）→ 完全沿用原 `ring_white` 路径，行为一个字节都不变；
	#   >= 0（L5 四相红/蓝/白/黄）→ 就地用 `_ring()` 打该色宣告环，_skill 留空：
	#     若仍留 "ring_white"，黄相开局会先放一轮白环，把「首招决定第一印象」毁掉。
	#     留空后 _cast_step() 对空串没有分支（不开火），1.3s 后由 _next_skill() 接本相编排。
	var theme := StageCfg.phase_theme_color(stage, phase)
	_skill = "ring_white"
	if theme >= 0:
		_skill = ""
		# 24 发 / 0.22rad 起始偏移 —— 与原 `ring_white` 首轮同款，只是换色。
		#   ⚠ 必须延后一帧（见 `_theme_ring`）：`hit()` 可能是在物理 `area_entered`
		#   回调里进来的，那一刻物理服务器正在 flushing queries，就地生成弹幕会报
		#   「Can't change this state while flushing queries」。
		_theme_ring.call_deferred(theme)
	# L5 终焉号「四相重构」：1.0s **完全停火**的硬直（长流程的三个呼吸点）。
	#   走显式状态机 _refit_t，而不是把时长塞进 _cast —— 后者会被散热期倒计时抢跑。
	if stage >= 1 and StageCfg.boss_phases(stage) >= 4:
		_refit_t = 1.0
		Fx.shock(world, position, Game.COLOR_MAIN[Game.WHITE], 720.0, 1.0)
	# L3 耀斑号：阶段切换立刻给一次强制散热，作为阶段奖励（设计 §D.3）。
	#   必须走 _enter_heat()：它才会置 venting，hit() 的散热倍率依赖这个标志位。
	#   ⚠ 时长按**新阶段**给（此处 phase 已更新，见 _check_phase），不要硬编码
	#     heat_window(stage, 1)：那样两次切换各白送 3.0s（共 6.0s），按旧 ×3.0
	#     计是 1710 点白送伤害 —— 超过 3200 总血的一半，L3 难度断崖的第二根因。
	#     按阶段递减给（P2 2.2s / P3 1.6s）既符合「散热窗口随阶段缩短」的设计，
	#     也与齐射后散热同源；狂暴期切换给 rage 窗口 1.2s。
	if stage >= 1 and StageCfg.resident_resist(stage) > 0.0:
		var hw := StageCfg.heat_window_rage(stage) if enraged else StageCfg.heat_window(stage, phase)
		if hw > 0.0:
			_enter_heat(hw)
	Fx.shock(world, position, Color(1.0, 1.0, 1.0), 640.0, 0.9)
	Fx.ring(world, position, Game.COLOR_MAIN[Game.WHITE], 40.0, 420.0, 0.7, 12.0)
	phase_chg.emit(phase)


## 阶段宣告环（延后一帧发射）。
##   为什么延后：`hit()` 最常由玩家光刃的 `area_entered` 信号打进来 —— 那一刻物理服务器
##   正在 flushing queries，就地 `Danmaku.spawn()` 会逐发报
##   「Can't change this state while flushing queries」。（L5 判定圈放大到 70 后，
##   光刃命中阶段线的概率显著上升，这个隐患才暴露成 48 条 ERROR —— 与绘制无关。）
##   延后一帧 = 同样的 24 发、同样的角度与速度，只是晚 16ms 出现。
func _theme_ring(c: int) -> void:
	if _st == "dying" or not is_instance_valid(self):
		return
	_ring(c, _n(24), 215.0, 0.22, 10.0)


func _clear_bullets() -> void:
	var p := world
	if p == null:
		return
	for ch in p.get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()


func _die() -> void:
	_st = "dying"
	ward = -1
	ward_chg.emit(-1)
	hp_ratio.emit(0.0)
	_clear_bullets()
	set_process(false)
	for i in 16:
		var off := Vector2(randf() - 0.5, randf() - 0.5) * 140.0
		Fx.burst(world, position + off, Game.COLOR_GLOW[i % 4], 18, 340.0, 0.7)
		await get_tree().create_timer(0.12).timeout
	Fx.shock(world, position, Color(1.0, 1.0, 1.0), 900.0, 1.2)
	boss_died.emit()
	queue_free()


# ------------------------------------------------------------ 绘制
## **画什么已外置到 `BossArt`**（规格 §C.0-1）：本函数只做两件事 ——
##   ① 编排层序（气息 → ②b 背负器官 → ③④ 本体 → ⑦b 外突器官 → 机制联动 → 覆盖层）；
##   ② 画**跨 Boss 通用**的覆盖层（狂暴 / 护罩 / 反应堆节点 / 散热 / 白闪）。
## 覆盖层半径一律 `r × 系数`（§C.0-2 系数表），`r = StageCfg.boss_r_main(stage)`
## = 56/63/70/77/84 —— 五个旗舰的主半径本就不同，写死数值会让小 Boss 撑爆、大 Boss 缩水。
func _draw() -> void:
	var r := float(StageCfg.boss_r_main(stage))
	# 气息取本体色（逐关固定，见 BossArt.boss_main_c）；护罩色单独取，见下方护罩段
	var bod_c := BossArt.boss_main_c(stage)
	var g := BossArt.glow_col(bod_c)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	if phase >= _phases:
		pulse = 0.5 + 0.5 * sin(_t * 8.0)

	# ① 本体气息（×1.90）
	draw_circle(Vector2.ZERO, r * 1.90 + 8.0 * pulse, Color(g.r, g.g, g.b, 0.07))

	# ②b 背负型标志器官：L1 环 / L2 翼 / L4 触须 / L5 残影
	BossArt.draw_sig_back(self, pulse)
	# ③④ 本体：正六边核心舱 / 菱形舰体 / 长方炮垒 / 宽厚母舰 / 纺锤
	BossArt.draw_body(self, pulse)
	# ⑦b 外突型标志器官：L3 炮列
	BossArt.draw_sig_front(self, pulse)
	# 机制联动：L3 暗甲壳弧 + 散热缺口 / L4 触须连索 / L5 血色虚线环
	BossArt.draw_mechanic(self, pulse)

	# 狂暴：周身泛红光（×2.25 / ×2.00）+ **6 枚三角符标**逆向游走。
	#   三角 vs 圆点 = 形状通道（§E.2）：狂暴不能只靠"泛红光"这一条颜色通道。
	if enraged:
		var ea := 0.5 + 0.5 * sin(_t * 9.0)
		draw_circle(Vector2.ZERO, r * 2.25 + 12.0 * ea, Color(1.0, 0.16, 0.10, 0.10))
		draw_circle(Vector2.ZERO, r * 2.00 + 8.0 * ea, Color(1.0, 0.22, 0.14, 0.14))
		for i in 6:
			var ang := -_t * 1.8 + TAU * float(i) / 6.0
			var p := Vector2.RIGHT.rotated(ang) * (r * 2.00 + 14.0 * sin(_t * 5.0 + i))
			var d := Vector2.RIGHT.rotated(ang)
			var sd := d.rotated(PI * 0.5) * 6.0
			draw_colored_polygon(PackedVector2Array([p + d * 8.0, p - d * 5.0 + sd,
				p - d * 5.0 - sd]), Color(1.0, 0.30, 0.18, 0.85))

	# 属性护罩：**8 段虚线弧**（段间 0.16 rad 缺口）+ 8 枚符点顺时针游走。
	#   "有缺口弧 / 完全无弧"是纯形状二值判据（§E.1），色盲玩家也能读。
	#   护罩色 = `ward`（L2 / L3 是 WardMode.NONE，永远不进这个分支）。
	if ward >= 0:
		var wm: Color = Game.COLOR_MAIN[ward]
		var wk: Color = Game.COLOR_CORE[ward]
		var a := 0.55 + 0.35 * sin(_ward_anim * 7.0)
		draw_circle(Vector2.ZERO, r * 1.70, Color(wm.r, wm.g, wm.b, 0.07))
		for i in 8:
			var a0 := _ward_anim * 1.2 + TAU * float(i) / 8.0 + 0.08
			var a1 := _ward_anim * 1.2 + TAU * float(i + 1) / 8.0 - 0.08
			draw_arc(Vector2.ZERO, r * 1.70, a0, a1, 12,
				Color(wm.r, wm.g, wm.b, a), 9.0, true)
		draw_arc(Vector2.ZERO, r * 1.52, 0.0, TAU, 56,
			Color(wk.r, wk.g, wk.b, a * 0.55), 3.0, true)
		# 护罩符点
		for i in 8:
			var ang := _ward_anim * 1.2 + TAU * float(i) / 8.0
			var p := Vector2.RIGHT.rotated(ang) * (r * 1.70)
			draw_circle(p, 4.5, Color(wk.r, wk.g, wk.b, a))
		# 护罩开启：本体外缘 2px CORE 白描边（§E.1 边缘通道）
		BossArt.draw_body_rim(self, Game.COLOR_CORE[Game.WHITE], 2.0)

	# 四色反应堆节点（当前护罩色的节点放大）——尺寸按 R_MAIN 比例化（§1.8 v4）：
	#   旧写法写死 17/11，五关 R_MAIN 56→84 会让 L1 撑爆、L5 缩水。比值 1.545 锁死，
	#   钳位保可读性下限；L3 @R_MAIN 70 恰 = 旧值 17/11，零回归。
	var rr_big   := clampf(r * 0.2429, 14.0, 22.0)   # 旧 17/70 = 0.2429
	var rr_small := rr_big / 1.545                    # 旧 17/11 = 1.545，比值必须锁死
	for i in 4:
		var ang := _t * 0.85 + TAU * float(i) / 4.0
		var p := Vector2.RIGHT.rotated(ang) * (r * 1.37)
		var cm: Color = Game.COLOR_MAIN[i]
		var rr := rr_big if i == ward else rr_small
		draw_circle(p, rr + 6.0, Color(Game.COLOR_GLOW[i].r, Game.COLOR_GLOW[i].g,
			Game.COLOR_GLOW[i].b, 0.20))
		draw_circle(p, rr, cm)
		draw_circle(p, rr * 0.42, Game.COLOR_CORE[i])

	# L3 散热期：装甲舱盖打开 —— 亮环 + 内核高亮，玩家读得出「现在打它值钱」
	if _heat_t > 0.0:
		var ha := 0.5 + 0.5 * sin(_t * 12.0)
		draw_arc(Vector2.ZERO, r * 1.23, 0.0, TAU, 40,
			Color(1.0, 0.85, 0.35, 0.55 + 0.35 * ha), 5.0, true)
		draw_circle(Vector2.ZERO, r * 0.63, Color(1.0, 0.90, 0.45, 0.20))

	# L3 散热期：露出的内核必须一眼看得见 ——
	#   否则玩家不知道「现在才该打」，高倍率窗口就白给了。
	if venting:
		draw_arc(Vector2.ZERO, r * 1.23, 0.0, TAU, 40,
			Color(1.0, 0.55, 0.25, 0.80), 6.0, true)
		draw_circle(Vector2.ZERO, r * 0.43,
			Color(1.0, 0.72, 0.35, 0.50 + 0.35 * pulse))

	# 末阶狂气
	if phase >= _phases:
		for i in 12:
			var ang := -_t * 1.6 + TAU * float(i) / 12.0
			var p := Vector2.RIGHT.rotated(ang) * (r * 2.00 + 12.0 * sin(_t * 6.0 + i))
			draw_circle(p, 5.0, Color(1.0, 0.35, 0.25, 0.55))

	# 受击白闪（×1.00）
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, r, Color(1.0, 1.0, 1.0, _flash * 2.2))
