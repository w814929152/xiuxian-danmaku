class_name Level
extends Node2D
## 关卡流程：**按 `StageCfg` 的波次表数据驱动** —— 波数 3/4/4/5/5 随关变化，
## 每波的目标色 / 骚扰色 / 独有怪 / 压轴战将 / 出怪间隔全部读配置，不再写死三波。
## 波次跑完 -> 星盗旗舰（Boss），Boss 的血 / 阶段 / 护罩 / 弹幕密度由 `StageCfg` 决定。
##
## 道具两个来源：斩敌按概率掉落（`StageCfg.drop_chance(stage)`，L5 是 0.14）
##   + 每波结束刷新 `StageCfg.wave_drop(stage)` 个；斩战将另有保底一件（`_on_elite_killed`）
## 波次结束**不再回血** —— 生命只靠修复包补
##
## 配色三条铁律（设计 §E.1，一行不改）：
##   目标色 ∈ S（玩家两件战甲色，逼换甲）· 骚扰色 ∈ S'（补集，逼走位，恒 hover）
##   · 禁连续 ≥3 同色（第 1 关第 1 波教学波豁免；列阵组内豁免，见 `_fold_groups`）
## 独有怪**不自带随机色**：色由本文件统一从 S / S' 分配 —— 与 Elite / Boss 同一条设计原则。
##
## 关卡形式两种（提案 `design/levels/03-关卡节奏实测与驻留波提案.md` §3）：
##   · **推进波** —— 背景恒滚 `Background.SCROLL_NORMAL`，敌从右侧屏外飞入
##   · **驻留阵地波** —— 背景降到 `Background.SCROLL_HOLD`，敌屏内跃迁入场
##     （位表 `StageCfg.wave_hold`，每关 1~2 波、不碰第 1 波）
## 两者共用同一张波次表与同一段清场判定 —— 只换**空间形式**，不动数值。

## 关卡结束（胜 / 负）—— 由 Main 连接，Level 不反向找 Main
signal finished(win: bool)
## 玩家请求重来本关（转发自 HUD）
signal restart_requested()

## 单色连长上限 / 每波刷新道具数取自 StageCfg（StageCfg.MAX_RUN / wave_drop）。

## 关卡号 1..5 —— 由 Main 在 `add_child` **之前**注入（_ready 里就 _start，晚一步就打错关）
var stage: int = 1

var player: Player = null
var boss: Boss = null
var hud: HUD = null
var bg: Background = null
var score: int = 0
var wave_text: String = "出 击"
var paused: bool = false
var _running: bool = false
## 本局各波的「骚扰色」（∈ S'，玩家永远免疫不了，只负责走位承压）。
## S' 恒为 2 色：偶数波取 [0]、奇数波取 [1]（见 `_harass_of`）。
var _harass: Array[int] = []
## 独有怪首登横幅是否已放过（每关只放一次，时长 2.2s 用于教学）
var _uniq_intro := false
## 本关已出战的战将序号（0-based）—— 传给 `Elite.setup` 做**同关多只战将强制异色**。
## L3 / L4 / L5 各有两只战将；不编号就只能随机，约半数局两只同色、一甲打穿两场。
var _elite_seq := 0


func _ready() -> void:
	bg = Background.new()
	add_child(bg)

	player = Player.new()
	player.world = self
	player.armors = []
	for c in Game.picked_armors:
		player.armors.append(int(c))
	add_child(player)
	player.player_died.connect(_on_player_died)
	_plan_harass()          # 敌色依赖战甲，得等 armors 定下来才能排

	hud = HUD.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	hud.bind(player, stage)
	hud.pause_toggled.connect(_on_pause_toggled)
	hud.restart_requested.connect(_on_restart_requested)

	_start()


func _start() -> void:
	_running = true
	_run()


func wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout


# ---------------------------------------------------------------- 流程
## 空档 = 横幅显示时长 + 紧随的 wait()（两者叠加，玩家都还没动手）。
##   首波前 1.2 + 0.9 = 2.1s；后续每波 1.0 + 0.7 = 1.7s；Boss 前 1.2 + 0.9 = 2.1s
##   -> 合计 = 2.1 + (N-1)×1.7 + 2.1 = 7.6s(N=3) / 9.3s(N=4) / 11.0s(N=5)
## 横幅时长都留得比 wait 长一点 —— 让尾巴 0.3 秒压在下一波开头，
## 字还在淡出时敌已经进场，衔接不断档。
func _run() -> void:
	var n_waves := StageCfg.waves(stage)
	var b0 := _wave_banner(1)
	hud.show_banner(b0[0], b0[1], float(b0[2]))
	await wait(0.9)
	if not _running:
		return
	for i in n_waves:
		var n := i + 1
		if n > 1:
			var bn := _wave_banner(n)
			hud.show_banner(bn[0], bn[1], float(bn[2]))
			await wait(0.7)
			if not _running:
				return
		await _wave(n, StageCfg.wave_hp_scale(stage, n), StageCfg.wave_elite_type(stage, n))
		if not _running:
			return
		_drop_wave()
	var sub := "四色弹幕 + 属性护罩，破罩方能致胜" if StageCfg.boss_ward(stage) \
		else "四色弹幕 · 旗舰不展护罩，全力输出即可"
	hud.show_banner(StageCfg.boss_full_name(stage), sub, 2.4)
	await wait(0.9)
	if not _running:
		return
	await _boss_fight()


## 本波横幅：[标题, 副标题, 时长(秒)]
## 第 1 波点名报出本波主色与对应的那件战甲，把「换甲」教在第一次遭遇上；
## 独有怪首登那一波改报它的机制（2.2s，比常规 1.0s 长，留足教学时间）。
##
## 驻留阵地波：优先让位给「独有怪首登 / 战将压轴」这两条**教学与破罩提示**，
## 只在副标题里补一句「跃迁入场」—— 玩家真正要知道的是「敌会从屏内冒出来」，
## 一句话足够，为它盖掉「换甲破力场」这种硬提示不划算。
func _wave_banner(n: int) -> Array[String]:
	var out: Array[String] = []
	var hold := StageCfg.wave_hold(stage, n)
	if n <= 1:
		var t1: int = player.armors[1] if player.armors.size() > 1 else Game.WHITE
		out.append("%s · 第 一 波" % StageCfg.name_of(stage))
		out.append("换上【%s】—— 免疫同色弹幕，光刃伤害 +50%%" % Game.ARMOR_TITLE[t1])
		out.append("1.2")
		return out
	if StageCfg.wave_unique(stage, n) > 0 and not _uniq_intro:
		_uniq_intro = true
		var k := StageCfg.unique_kind_a(stage)
		if StageCfg.wave_unique_a(stage, n) <= 0:
			k = StageCfg.unique_kind_b(stage)
		out.append(EnemyKind.short_cn(k))
		out.append(_uniq_tip(k) + (" · 跃迁入场，就地清场" if hold else ""))
		out.append("2.2")
		return out
	if StageCfg.wave_elite(stage, n):
		out.append("第 %d 波 · 先锋" % n)
		out.append(("星盗跃迁入场 · " if hold else "") + _elite_pre_tip(StageCfg.wave_elite_type(stage, n)))
		out.append("1.0")
		return out
	if hold:
		out.append("第 %d 波 · 驻留" % n)
		out.append("星盗跃迁入场 · 清完本波方能推进")
		out.append("1.0")
		return out
	out.append("第 %d 波 · 星袭" % n)
	out.append("同色光刃伤害 + 50% · 异色敌只能硬躲")
	out.append("1.0")
	return out


## 精英波横幅的一句话预告（按种类；战将沿用「破力场」提示）
static func _elite_pre_tip(elite_type: int) -> String:
	match elite_type:
		EnemyKind.E.WARRIOR:
			return "战将至 · 换上同色战甲破其力场"
		EnemyKind.E.BASTION:
			return "弹幕堡垒将至 · 跟弹幕墙的缝隙走位"
		EnemyKind.E.SWARM:
			return "增殖指挥将至 · 先清召唤喽啰再打本体"
		EnemyKind.E.AEGIS:
			return "护盾冲锋将至 · 绕到侧后或换同色甲破盾"
		_:
			return "星盗精锐 · 破其色防"


## 独有怪首登的一句话机制提示（设计 §C 各条「唯一机制」）
static func _uniq_tip(k: int) -> String:
	match k:
		EnemyKind.K.DISMANTLER:
			return "死亡分裂两片 · 同色光刃可连带秒杀"
		EnemyKind.K.DEFECTOR:
			return "核心在两色间轮换 · 换色瞬间任意色 ×2.0"
		EnemyKind.K.PHALANX:
			return "三艘成墙齐射 · 墙缝规律平移，走缝可过"
		EnemyKind.K.LAYER:
			return "横穿布设引力雷 · 八秒自毁，压缩空间"
		EnemyKind.K.SIPHON:
			return "吸收一色并回血 · 换另一件战甲打疼它"
		EnemyKind.K.MARTYR:
			return "高速直冲 · 死或撞都爆出冲击环"
		EnemyKind.K.PHASER:
			return "每 2.6 秒无敌折跃 · 无敌期收手"
		_:
			return "星盗精锐 · 破其色防"


# ---------------------------------------------------------------- HUD 数据
## 分数与波次文字统一走这里推送给 HUD —— HUD 不反向读 Level
## 入参是「原始战果」，落账时统一乘本关计分倍率：
## HUD 实时分 / 结算分 / 品阶判定 / 最高分存档因此同源同值。
func _add_score(v: int) -> void:
	score += int(roundf(float(v) * StageCfg.score_multiplier(stage)))
	if hud != null:
		hud.set_score(score)


func _set_wave(s: String) -> void:
	wave_text = s
	if hud != null:
		hud.set_wave(s)


# ---------------------------------------------------------------- 输入回调
func _on_pause_toggled(v: bool) -> void:
	paused = v
	get_tree().paused = v


func _on_restart_requested() -> void:
	get_tree().paused = false
	restart_requested.emit()


# ---------------------------------------------------------------- 星袭配色
# 敌色不再逐只 randi()%4，而是随玩家两件战甲 S 对称生成：
#   目标色 ∈ S   —— 逼换甲（同色光刃 +50%，且被战甲吸收）
#   骚扰色 ∈ S'  —— 逼走位（玩家永远免疫不了，远驻 hover 放弹）
# 独立随机会产出「连续 4 只同色」，玩家全程不用换甲，换甲这根支柱就漂没了；
# 所以走「配额 + 约束洗牌」，先把整波色序排好再按序放怪。
# ----------------------------------------------------------------

## S' = 四色里玩家没选的那些色（armors 恒为 2 个不同色，故恒为 2 个）
static func _complement(armors: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for c in Game.COLOR_CN.size():
		if not armors.has(c):
			out.append(c)
	return out


## 本局各波的骚扰色：S' 洗牌后偶数波取 [0]、奇数波取 [1]（跨局有变化）
func _plan_harass() -> void:
	var comp := _complement(player.armors)
	if comp.size() < 2:
		comp = [Game.RED, Game.WHITE, Game.BLUE, Game.YELLOW]
	comp.shuffle()
	_harass = comp


## 第 n 波的骚扰色（S' 两色按波号轮换取用）
static func _harass_of(n: int, h2: int, h3: int) -> int:
	if n <= 0:
		return -1
	return h2 if n % 2 == 0 else h3


## 本波「骚扰位」的格数 = 骚扰色喽啰 + 骚扰色配额的独有怪（列阵者 / 敷设者）
static func _harass_slots(st: int, n: int) -> int:
	var c := StageCfg.wave_harass(st, n)
	var ka := StageCfg.unique_kind_a(st)
	if ka != StageCfg.NO_KIND and EnemyKind.quota(ka) == EnemyKind.Q.HARASS:
		c += StageCfg.wave_unique_a(st, n)
	var kb := StageCfg.unique_kind_b(st)
	if kb != StageCfg.NO_KIND and EnemyKind.quota(kb) == EnemyKind.Q.HARASS:
		c += StageCfg.wave_unique_b(st, n)
	return c


## 本波「非骚扰位」里属于独有怪的格数（目标色配额 + 不占配额的中性怪）
static func _uniq_s_count(st: int, n: int) -> int:
	var c := 0
	var ka := StageCfg.unique_kind_a(st)
	if ka != StageCfg.NO_KIND and EnemyKind.quota(ka) != EnemyKind.Q.HARASS:
		c += StageCfg.wave_unique_a(st, n)
	var kb := StageCfg.unique_kind_b(st)
	if kb != StageCfg.NO_KIND and EnemyKind.quota(kb) != EnemyKind.Q.HARASS:
		c += StageCfg.wave_unique_b(st, n)
	return c


## 第 n 波的出怪色序（长度 = 本波格数 = `StageCfg.wave_slots(st, n)`）
## [param armors] 玩家两件战甲色 S  [param h2] / [param h3] S' 两色
## [param st] 关卡号（默认第 1 关 —— 5 / 7 / 8 只数就是第 1 关的三波）
##
## 独有怪**不参与配色决策**：它只是"占位格上的一个 kind 标记"，该格颜色仍由色序决定，
## 且按设计 §E.3 占**非骚扰位的最后几格**（`_wave_kinds` 依此回填种类）。
static func _wave_colors(n: int, armors: Array[int], h2: int, h3: int,
		st: int = 1) -> Array[int]:
	var a: int = armors[1] if armors.size() > 1 else Game.RED     # 主色
	var b: int = armors[0] if armors.size() > 0 else Game.WHITE   # 副色
	var h := _harass_of(n, h2, h3)
	var n_s := StageCfg.wave_targets(st, n) + _uniq_s_count(st, n)
	var seq: Array[int] = []
	if n <= 1 and st <= 1:
		# 第 1 关第 1 波：教学波，整波一色到底，禁连规则豁免
		seq.resize(n_s)
		seq.fill(a)
		return seq
	if n % 2 == 0:
		# 偶数波：目标色严格交替（每只都得换甲）
		for i in n_s:
			seq.append(a if i % 2 == 0 else b)
	else:
		# 奇数波：目标色在两色间摆动，允许 2 连、禁止连续 ≥3 同色 —— 得自己判断何时换
		var half := n_s / 2
		var ca := half if randf() < 0.5 else n_s - half
		seq = _alt_fill(a, b, ca, n_s - ca, StageCfg.MAX_RUN)
	return _insert_harass(seq, h, _harass_slots(st, n))


## 本波每格的 kind —— 与 `_wave_colors` 的返回值**位置一一对应**。
## 分流口径（设计 §E.3）：独有怪占「非骚扰位」的最后几格；
## 骚扰色配额的独有怪（列阵者 / 敷设者）占「骚扰位」的最后几格。
static func _wave_kinds(colors: Array[int], harass: int, n: int,
		st: int = 1) -> Array[int]:
	var s_uni: Array[int] = []
	var h_uni: Array[int] = []
	_push_uni(s_uni, h_uni, StageCfg.unique_kind_a(st), StageCfg.wave_unique_a(st, n))
	_push_uni(s_uni, h_uni, StageCfg.unique_kind_b(st), StageCfg.wave_unique_b(st, n))
	var n_s := StageCfg.wave_targets(st, n)
	var n_h := StageCfg.wave_harass(st, n)
	var kinds: Array[int] = []
	var i_s := 0
	var i_h := 0
	for c in colors:
		if c == harass:
			if i_h < n_h or h_uni.is_empty():
				kinds.append(EnemyKind.K.GRUNT)
			else:
				kinds.append(h_uni[clampi(i_h - n_h, 0, h_uni.size() - 1)])
			i_h += 1
		else:
			if i_s < n_s or s_uni.is_empty():
				kinds.append(EnemyKind.K.GRUNT)
			else:
				kinds.append(s_uni[clampi(i_s - n_s, 0, s_uni.size() - 1)])
			i_s += 1
	return kinds


## 按配额把本关独有怪分流到「骚扰位尾」或「非骚扰位尾」
static func _push_uni(s_uni: Array[int], h_uni: Array[int], k: int, cnt: int) -> void:
	if k == StageCfg.NO_KIND or cnt <= 0:
		return
	var dst := h_uni if EnemyKind.quota(k) == EnemyKind.Q.HARASS else s_uni
	for _i in cnt:
		dst.append(k)


## 列阵者组折叠（设计 §H.2-5 / 架构 §B.4）：
## 1 组 3 艘在色序里**只占 1 格**，组内同色**豁免**「禁连续 ≥3 同色」
## —— 整组是"一堵墙"，不是一个颜色序列。
## 因此「禁 ≥3 同色」**必须**校验这条折叠后的序列：先展开成 3 艘再校验，
## 一列阵就会被自己的组内同色判成违规。
static func _fold_groups(colors: Array[int], kinds: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for i in colors.size():
		var k: int = kinds[i] if i < kinds.size() else EnemyKind.K.GRUNT
		if k == EnemyKind.K.PHALANX and not out.is_empty() and out[-1] == colors[i]:
			continue          # 把这一组并进前一格 —— 组内同色不计连长
		out.append(colors[i])
	return out


## 一格要出几艘（列阵者 1 格 = 1 组 3 艘成墙；其余 1 艘）
static func _ships_of(kind: int) -> int:
	return 3 if kind == EnemyKind.K.PHALANX else 1


## 组内第 i 艘的 y 偏移（竖墙，间距 130px）
static func _ship_off(i: int, ships: int) -> float:
	if ships <= 1:
		return 0.0
	return (float(i) - (float(ships) - 1.0) * 0.5) * 130.0


## 每波目标色的运动模式池（第 1 波不出现 dive —— 开局就俯冲太凶）
static func _wave_moves(n: int, st: int = 1) -> Array[String]:
	var out: Array[String] = []
	out.append("straight")
	out.append("sine")
	if n > 1:
		out.append("dive")
	return out


## 每波出怪间隔（读 `StageCfg`，不再按波号写死）
static func _wave_gap(n: int, st: int = 1) -> float:
	return StageCfg.wave_gap(st, n)


## 序列里最长的一段同色连长
static func _max_run(seq: Array[int]) -> int:
	var best := 0
	var run := 0
	var prev := -1
	for c in seq:
		if c == prev:
			run += 1
		else:
			run = 1
			prev = c
		if run > best:
			best = run
	return best


## 从 {a×ca, b×cb} 里随机排一队，要求同色连长 ≤ max_run。
## 用「重排到合规为止」而不是逐位贪心：贪心会把余量逼进死角
## （例如 B,B,A 之后只剩 A、A，却已两连 —— 5 只排不满）。
static func _alt_fill(a: int, b: int, ca: int, cb: int, max_run: int) -> Array[int]:
	for _try in 24:
		var pool: Array[int] = []
		for _i in ca:
			pool.append(a)
		for _j in cb:
			pool.append(b)
		pool.shuffle()
		if _max_run(pool) <= max_run:
			return pool
	# 兜底：每次连续铺不超过 max_run 只就换色，一定排得满
	var seq: Array[int] = []
	var ra := ca
	var rb := cb
	while ra + rb > 0:
		var first := a if ra >= rb else b
		var second := b if first == a else a
		for _k in max_run:
			if first == a and ra > 0:
				seq.append(a)
				ra -= 1
			elif first == b and rb > 0:
				seq.append(b)
				rb -= 1
		for _m in max_run:
			if second == a and ra > 0:
				seq.append(a)
				ra -= 1
			elif second == b and rb > 0:
				seq.append(b)
				rb -= 1
	return seq


## 把 count 只骚扰色插进已合规的目标色序列，位置随机，但插进去会让骚扰色
## 连长超过 StageCfg.MAX_RUN 的空位直接跳过。
## 注意不能只判「左右都是 h」：已有 HH 时往它左侧插一格，左边是别的色、
## 右边是单个 H，照样凑出 HHH —— 得把插入点左右的连长都算进去。
static func _insert_harass(seq: Array[int], h: int, count: int) -> Array[int]:
	for _k in count:
		var spots: Array[int] = []
		for p in seq.size() + 1:
			var lrun := 0
			var i := p - 1
			while i >= 0 and seq[i] == h:
				lrun += 1
				i -= 1
			var rrun := 0
			var j := p
			while j < seq.size() and seq[j] == h:
				rrun += 1
				j += 1
			if lrun + 1 + rrun > StageCfg.MAX_RUN:
				continue
			spots.append(p)
		if spots.is_empty():
			spots.append(seq.size())
		seq.insert(spots[randi() % spots.size()], h)
	return seq


## [param elite_type] 本波压轴精英的种类（EnemyKind.E；0 = 本波无精英）。
##   战将（WARRIOR）力场色由 Elite 自己从玩家战甲里抽；其余种类由 _spawn_elite 分派。
##
## **驻留阵地波**（`StageCfg.wave_hold`）：背景降到 `Background.SCROLL_HOLD`、
## 敌人改走屏内跃迁入场（`_spawn_slot` 的 warp 分支）。清场判定与推进波**完全同一段**，
## 一行未改 —— 提案 §3.1 的硬要求：只换「空间形式」，不动血量 / 弹幕 / 配色 / 计分。
func _wave(n: int, scale: float, elite_type := 0) -> void:
	var hold := StageCfg.wave_hold(stage, n)
	if bg != null:
		bg.scroll_speed = Background.SCROLL_HOLD if hold else Background.SCROLL_NORMAL
	_set_wave("第 %d 波 · %s" % [n, "驻留" if hold else "星袭"])
	if _harass.size() < 2:
		_plan_harass()
	var harass := _harass_of(n, _harass[0], _harass[1])
	var colors := _wave_colors(n, player.armors, _harass[0], _harass[1], stage)
	var kinds := _wave_kinds(colors, harass, n, stage)
	# 列阵组折叠：展开成 3 艘之前先校验（组内豁免），否则一列阵就会被判违规。
	# 第 1 关第 1 波是教学波，整波一色到底，不在约束内。
	if (n > 1 or stage > 1) and _max_run(_fold_groups(colors, kinds)) > StageCfg.MAX_RUN:
		push_warning("Level: 第 %d 关第 %d 波色序出现连续 %d 同色（已折叠列阵组）" % [
			stage, n, _max_run(_fold_groups(colors, kinds))
		])
	var pats := _wave_moves(n, stage)
	var gap := _wave_gap(n, stage)
	for i in colors.size():
		if not _running:
			return
		_spawn_slot(scale, colors[i], kinds[i], harass, pats, hold)
		await wait(gap)
	if elite_type != 0:
		await wait(0.5)
		if not _running:
			return
		_spawn_elite(scale, elite_type)
	# 等待清场。精英是硬性门槛 —— 星盗可以剩最后一只不等，精英没斩就别想进下一波。
	# 上限按 `StageCfg.clear_guard(stage, elite)` 取：各关只数不同，写死会卡在半路。
	var has_elite := elite_type != 0
	var limit := StageCfg.clear_guard(stage, has_elite)
	var guard := 0.0
	while _running and guard < limit:
		await wait(0.3)
		guard += 0.3
		if _enemy_count() <= 1 and not _elite_alive():
			break
	# 驻留波结束 -> 背景恢复推进速度（下一波 / Boss 自己会再设，这里是兜底）。
	#   ⚠ 不走这条的提前 return 都是「关卡已终止」（玩家阵亡 / 通关），那时滚速由
	#     `_stop_field` 接管，不能被这里覆盖回 46。
	if bg != null:
		bg.scroll_speed = Background.SCROLL_NORMAL


## 出怪唯一入口 —— 一律走 `Spawner.enemy(...)`（world 显式注入，禁用 get_parent）。
## [param c] 本格色（由 `_wave_colors` 排定）
## [param kind] 本格的星盗种类（`_wave_kinds` 排定；GRUNT = 通用喽啰）
## [param harass] 本波骚扰色；c == harass 时强制 hover（远驻放弹、不追击），
##                harass < 0 表示本波没有骚扰色
## [param pats] 本波目标色的运动模式池（骚扰色不走这里）
## [param warp] 屏内跃迁入场（驻留阵地波）；列阵者整组共用同一个 x，见下方
func _spawn_slot(scale: float, c: int, kind: int, harass: int,
		pats: Array[String], warp := false) -> void:
	var pat := "hover"
	if c != harass:
		pat = pats[randi() % pats.size()]
	var y := randf() * (Game.VIEW_H - 180.0) + 90.0
	var ships := _ships_of(kind)
	# 跃迁 x 取屏宽 55%~95%：够靠右（不糊在玩家脸上），又留得出反应距离。
	# **一格算一次** —— 列阵者 3 艘成竖墙，各自随机会把墙拆散。
	var wx := -1.0
	if warp:
		wx = Game.VIEW_W * (0.55 + randf() * 0.40)
	for i in ships:
		var yy := clampf(y + _ship_off(i, ships), 90.0, Game.VIEW_H - 90.0)
		var e := Spawner.enemy(self, kind, c, pat, yy, scale, stage, wx)
		if e == null:
			return
		e.player_ref = player
		# 分值由本文件按种类钉死（设计 §G.2）—— 满分表 `_MAX` 就是按这张表算的
		e.score = EnemyKind.score_of(kind)
		e.killed.connect(_on_enemy_killed)


## 通用星盗的便捷入口（保留原签名：既有自测调用点零改动）
func _spawn_enemy(scale: float, c: int, harass: int, pats: Array[String]) -> void:
	_spawn_slot(scale, c, EnemyKind.K.GRUNT, harass, pats)


## 场上还有几只需要清掉的星盗（战将另算，见 `_elite_alive`）。
## `no_block_clear` 单位（拆解者小片 / 引力雷 / 增援）**不计** —— 它们不阻塞清场，
## 只靠自身兜底回收；算进去会把清场一路拖到 guard 上限。
func _enemy_count() -> int:
	var n := 0
	for ch in get_children():
		if ch is Enemy and not (ch as Enemy).no_block_clear:
			n += 1
	return n


## 场上是否还有活着的精英（战将 / 堡垒 / 指挥 / 护盾，清场判定用）。
## 四只精英都继承 EliteBase —— 一律认 `ch is EliteBase`。
func _elite_alive() -> bool:
	for ch in get_children():
		if ch is EliteBase and not (ch as EliteBase).dead:
			return true
	return false


## 压轴精英：按 `elite_type`（EnemyKind.E）分派到具体子类。
## 四只精英机制完全不同（破罩 / 弹幕墙 / 召唤 / 朝向护盾），各自成类；
## 这里只做「new → 注入 world/stage/player → setup → 连 killed」的统一编排。
## 力场/护盾色（战将、护盾）由各子类自己从 player_armors 抽 —— 保证一定破得了。
func _spawn_elite(scale: float, elite_type: int) -> void:
	var e: EliteBase = _make_elite(elite_type)
	if e == null:
		return
	e.stage = stage                     # ★ add_child 之前注入（与 Spawner.enemy 同一口径）
	e.world = self
	add_child(e)
	e.player_ref = player
	e.player_armors = player.armors
	# 战将传本关出场序号（两只按序号各取 S 的一色，强制异色）；其余种类忽略 seq
	if elite_type == EnemyKind.E.WARRIOR:
		(e as Elite).setup(scale, randf() * (Game.VIEW_H - 300.0) + 150.0, _elite_seq)
		_elite_seq += 1
	else:
		e.setup(scale, randf() * (Game.VIEW_H - 300.0) + 150.0)
	e.killed.connect(_on_elite_killed)
	hud.show_banner(_elite_banner_name(elite_type), _elite_tip(elite_type, e.color), 2.2)


## 按种类 new 出对应精英实例（探测不到就返回 null —— 前向兼容，日后加子类自动接上）
func _make_elite(elite_type: int) -> EliteBase:
	match elite_type:
		EnemyKind.E.WARRIOR:
			return Elite.new()
		EnemyKind.E.BASTION:
			return EliteBastion.new()
		EnemyKind.E.SWARM:
			return EliteSwarm.new()
		EnemyKind.E.AEGIS:
			return EliteAegis.new()
		_:
			return null
	return null


## 精英横幅标题（种类名）
func _elite_banner_name(elite_type: int) -> String:
	match elite_type:
		EnemyKind.E.WARRIOR:
			return "星 盗 战 将"
		EnemyKind.E.BASTION:
			return "弹 幕 堡 垒"
		EnemyKind.E.SWARM:
			return "增 殖 指 挥"
		EnemyKind.E.AEGIS:
			return "护 盾 冲 锋"
		_:
			return "星 盗 精 锐"


## 精英横幅副标题（一句话机制提示 + 配色提示）
func _elite_tip(elite_type: int, c: int) -> String:
	var col := "【%s】" % Game.COLOR_CN[c]
	match elite_type:
		EnemyKind.E.WARRIOR:
			var t := "身披 %s 力场 —— 换上同色战甲方能速破" % col
			if StageCfg.elite_hue_n(stage) > 1:
				t += " · 弹幕混色，异色唯有走位"
			return t
		EnemyKind.E.BASTION:
			return "厚甲无罩 · 弹幕织墙，跟缝隙走位 · 主色 %s 可吸" % col
		EnemyKind.E.SWARM:
			return "周期性召唤 %s 喽啰 · 先清场再打本体" % col
		EnemyKind.E.AEGIS:
			return "正面 %s 护盾 · 绕到侧后或换同色甲破之" % col
		_:
			return "星盗精锐 · 破其色防"


## 斩战将：厚赏 + 必掉一件道具（斩它是有代价的，不能让人空手）
func _on_elite_killed(pos: Vector2, c: int, sc: int) -> void:
	_add_score(sc)
	Fx.pop(self, pos, "+%d" % sc, Game.COLOR_MAIN[c], 24, 1.1)
	Pickup.spawn(self, Pickup.random_kind(), pos)


func _on_enemy_killed(pos: Vector2, c: int, sc: int) -> void:
	_add_score(sc)
	Fx.pop(self, pos, "+%d" % sc, Game.COLOR_MAIN[c], 18)
	if randf() < StageCfg.drop_chance(stage):
		Pickup.spawn(self, Pickup.random_kind(), pos)


## 每波星袭结束：额外刷新 `StageCfg.wave_drop(stage)` 个道具，散落在场景右段，
## 逼玩家挪过去捡
func _drop_wave() -> void:
	for i in StageCfg.wave_drop(stage):
		var x := randf() * 540.0 + 460.0
		var y := randf() * (Game.VIEW_H - 240.0) + 120.0
		Pickup.spawn(self, Pickup.random_kind(), Vector2(x, y))


# ---------------------------------------------------------------- Boss
## 旗舰实例：按关号探测子类，探测不到就走基类。结论（ADR-3 判据实测后已定）：
##   · **L4 拆了** —— `Boss4.gd`：子核心是有状态的状态机（免伤 / 分裂 / 共享 / 召唤 /
##     暴露期），必须持有自己的状态，塞进基类会长出第二个状态机。
##   · **L5 不拆** —— `Boss.gd` 752 行里 L5 专属分支只有 1 行（列数判据 `stage >= 5`），
##     离 ADR-3 的反转阈值（独有分支 > 60 行）差两个数量级；四相重构 / 每相独立池 /
##     护罩轮转全靠 `BossCfg._L5_P1.._L5_P4` + `StageCfg.phase_marks()` 数据驱动，
##     拆个空壳子类反而把数据驱动倒退回代码分支。
## 探测机制**保留**：零成本的前向兼容 —— 日后 `Boss5.gd` 若出现，此处自动接上，无需改动。
static func _make_boss(st: int) -> Boss:
	var path := "res://scripts/entities/Boss%d.gd" % st
	if st >= 4 and ResourceLoader.exists(path):
		var sc: Variant = load(path)
		if sc is Script:
			var made: Variant = (sc as Script).new()
			if made is Boss:
				return made as Boss
	return Boss.new()


func _boss_fight() -> void:
	_set_wave(StageCfg.boss_name(stage))
	bg.scroll_speed = Background.SCROLL_BOSS
	boss = _make_boss(stage)
	boss.world = self
	boss.stage = stage                                   # ★ 必须在 add_child 之前
	boss.title = StageCfg.boss_full_name(stage)
	boss.boss_name = StageCfg.boss_name(stage)
	add_child(boss)
	boss.player_ref = player
	boss.player_armors = player.armors
	boss.phase_chg.connect(_on_boss_phase)
	boss.ward_chg.connect(_on_ward)
	boss.enrage_started.connect(_on_enrage)
	boss.boss_died.connect(_on_boss_died)
	hud.bind_boss(boss)
	var sub := "四色弹幕 + 属性护罩，破罩方能致胜" if StageCfg.boss_ward(stage) \
		else "四色弹幕 · 旗舰不展护罩，全力输出即可"
	hud.show_banner(StageCfg.boss_full_name(stage), sub, 2.4)


func _on_enrage() -> void:
	hud.show_banner("狂 暴", "%s 周身泛起赤光 · 攻势全面升级" % StageCfg.boss_name(stage),
		1.8)


func _on_boss_phase(p: int) -> void:
	_add_score(600)
	hud.show_banner("第 %d 阶段" % p, "旗舰切换阶段，弹幕更急", 1.6)


func _on_ward(c: int) -> void:
	if c < 0 or player == null or not is_instance_valid(player):
		return
	if player.color != c:
		Fx.pop(self, player.position + Vector2(0.0, -52.0), "护罩 · %s" % Game.COLOR_CN[c],
			Game.COLOR_MAIN[c], 20, 1.1)


func _on_boss_died() -> void:
	_add_score(5000)
	_set_wave("凯 旋")
	await wait(1.3)
	_finish(true)


func _on_player_died() -> void:
	_running = false
	_set_wave("阵 亡")
	_stop_field()
	await wait(1.5)
	_finish(false)


## 玩家已陨落：清弹、撤敌、让旗舰收手。
## 不做这步的话，接下来这 1.5 秒里 Boss 仍会按套路开火，而 player_ref 指向的
## 玩家节点已经被 queue_free —— 把「已释放对象」赋给弹幕的 target 会直接报
## "Invalid assignment ... with value of type 'previously freed'"。
func _stop_field() -> void:
	for ch in get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()
		elif ch is Enemy:
			(ch as Enemy).queue_free()
		elif ch is EliteBase:
			(ch as EliteBase).queue_free()
		elif ch is Pickup:
			(ch as Pickup).queue_free()
	if boss != null and is_instance_valid(boss):
		boss.player_ref = null
		boss.stand_down()
	# 阵亡慢镜：比驻留波（8 px/s）还慢一档，是「画面濒死」的表演，别与 SCROLL_HOLD 混用
	if bg != null:
		bg.scroll_speed = 6.0


func _finish(win: bool) -> void:
	_running = false
	Game.result_win = win
	Game.result_score = score
	Game.result_hp = player.hp if (player != null and is_instance_valid(player)) else 0
	# 先记下本局之前的最好成绩 —— 结算界面要拿它显示「历史最高」，
	# 而存档一旦刷新它就查不到了。关卡纪录一律走 progress.json（"L1".."L5"）。
	Game.result_prev_high = Game.stage_highscore(stage)
	Game.result_is_new_high = score > Game.result_prev_high
	# 通关 -> 解锁下一关（**先解锁再存档**，结算界面的「解锁行」才读得到）
	Game.unlock_after(stage, win)
	if Game.result_is_new_high:
		# 注意：这里**不传 win** —— 通关与否由 `unlocked` 承载（见 Game.save_stage 注释）。
		# 传进去的话，一局「输了但分数更高」会把该关的通关事实改成没通关。
		Game.save_stage(stage, score, Game.picked_armors)
	finished.emit(win)
