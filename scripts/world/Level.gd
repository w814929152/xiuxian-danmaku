class_name Level
extends Node2D
## 关卡流程：三波星袭 -> 星盗始祖
## 第 2 / 第 3 波以【星盗战将】压轴（Elite.gd，属性力场逼玩家临阵换甲）
## 道具两个来源：斩敌按概率掉落（DROP_CHANCE）+ 每波结束刷新 WAVE_DROP 个
##   斩战将另有保底一件（_on_elite_killed）
## 波次结束**不再回血** —— 生命只靠修复包补

## 关卡结束（胜 / 负）—— 由 Main 连接，Level 不反向找 Main
signal finished(win: bool)
## 玩家请求重来本关（转发自 HUD）
signal restart_requested()

## 击杀星盗的掉落概率（实测：2000 次击杀掉落 373 次 = 18.65%，与配置一致）
const DROP_CHANCE := 0.18
## 每波星袭结束后额外刷新的道具数（每局固定 3 个）
const WAVE_DROP := 1

## 单色连长上限：允许 2 连，禁止连续 ≥3 同色。
## （第 1 波是刻意的一色到底 —— 教换甲的教学波，不受此限。）
const MAX_RUN := 2

## 每波「目标色」的只数（∈ 玩家战甲色，负责换甲增伤）。
## 三波的只数 = 5 / (5+2) / (5+3) = 20 —— 这个 20 是 P0-1 满分（9800）的基数，
## 动配额之前必须先把计分重算一遍。
const WAVE_TARGETS := 5

var player: Player = null
var boss: Boss = null
var hud: HUD = null
var bg: Background = null
var score: int = 0
var wave_text: String = "出 击"
var paused: bool = false
var _running: bool = false
## 本局两波的「骚扰色」（∈ S'，玩家永远免疫不了，只负责走位承压）。
## [0] 给第 2 波、[1] 给第 3 波，两波必定不同色 —— 第 3 波才凑齐四色。
var _harass: Array[int] = []


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
	hud.bind(player)
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
## 重标定前合计 15.3 秒，节奏被切成四段碎觉；现在压到 7.6 秒：
##   2.1 + 1.7 + 1.7 + 2.1 = 7.6
## 横幅时长都留得比 wait 长一点 —— 让尾巴 0.3 秒压在下一波开头，
## 字还在淡出时敌已经进场，衔接不断档。
func _run() -> void:
	# 第 1 波点名：直接报出本波主色与对应的那件战甲，把「换甲」教在第一次遭遇上。
	#（原来这行是操作提示 —— 那部分游戏说明里已有，横幅让给更关键的换甲教学。）
	var t1: int = player.armors[1] if player.armors.size() > 1 else Game.WHITE
	hud.show_banner("第 一 波 · %s 星袭" % Game.COLOR_CN[t1],
		"换上【%s】—— 免疫同色弹幕，光刃伤害 +50%%" % Game.ARMOR_TITLE[t1], 1.2)
	await wait(0.9)
	if not _running:
		return

	await _wave(1, 1.0)
	if not _running:
		return
	_drop_wave()
	hud.show_banner("第 二 波 · 双色交替", "同色光刃伤害 + 50% · 异色敌只能硬躲", 1.0)
	await wait(0.7)
	if not _running:
		return

	await _wave(2, 1.15, true)
	if not _running:
		return
	_drop_wave()
	hud.show_banner("第 三 波 · 先锋", "始祖将至 · 四色齐至", 1.0)
	await wait(0.7)
	if not _running:
		return

	await _wave(3, 1.3, true)
	if not _running:
		return
	_drop_wave()
	hud.show_banner("星盗始祖 · 现身", "护罩开启时 —— 唯有同色光刃可破，随时更换战甲", 1.2)
	await wait(0.9)
	if not _running:
		return
	await _boss_fight()


# ---------------------------------------------------------------- HUD 数据
## 分数与波次文字统一走这里推送给 HUD —— HUD 不反向读 Level
## 入参是「原始战果」，落账时统一乘难度计分倍率：
## HUD 实时分 / 结算分 / 品阶判定 / 最高分存档因此同源同值。
func _add_score(v: int) -> void:
	score += int(roundf(float(v) * Game.score_multiplier()))
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


## 本局两波的骚扰色：S' 洗牌后 [0] 给第 2 波、[1] 给第 3 波（跨局有变化）
func _plan_harass() -> void:
	var comp := _complement(player.armors)
	if comp.size() < 2:
		comp = [Game.RED, Game.WHITE, Game.BLUE, Game.YELLOW]
	comp.shuffle()
	_harass = comp


## 第 n 波的出怪色序（长度即本波只数）
## [param armors] 玩家两件战甲色 S  [param h2] 第 2 波骚扰色  [param h3] 第 3 波骚扰色
static func _wave_colors(n: int, armors: Array[int], h2: int, h3: int) -> Array[int]:
	var a: int = armors[1] if armors.size() > 1 else Game.RED     # 主色（第 1 波整波都是它）
	var b: int = armors[0] if armors.size() > 0 else Game.WHITE   # 副色
	var seq: Array[int] = []
	seq.resize(WAVE_TARGETS)
	seq.fill(a)
	if n <= 1:
		return seq                    # 第 1 波：5 只全为主色，一色到底，教换甲
	if n == 2:
		seq = [a, b, a, b, a]        # 第 2 波：目标色严格交替（两色必换 4 次甲）
		return _insert_harass(seq, h2, _harass_count(2))
	# 第 3 波：目标色在两色间摆动，允许 2 连、禁止连续 ≥3 同色 —— 得自己判断何时换
	var na := 3 if randf() < 0.5 else 2
	seq = _alt_fill(a, b, na, WAVE_TARGETS - na, MAX_RUN)
	return _insert_harass(seq, h3, _harass_count(3))


## 每重的骚扰色只数（第 1 重不设骚扰色）
static func _harass_count(n: int) -> int:
	if n == 2:
		return 2
	if n >= 3:
		return 3
	return 0


## 每重的出怪间隔（三重递进收紧：0.62 -> 0.55 -> 0.50）
static func _wave_gap(n: int) -> float:
	if n <= 1:
		return 0.62
	if n == 2:
		return 0.55
	return 0.50


## 每重目标色的运动模式池（第 1 重不出现 dive —— 开局就俯冲太凶）
static func _wave_moves(n: int) -> Array[String]:
	if n <= 1:
		return ["straight", "sine"]
	return ["straight", "sine", "dive"]


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
## 连长超过 MAX_RUN 的空位直接跳过。
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
			if lrun + 1 + rrun > MAX_RUN:
				continue
			spots.append(p)
		if spots.is_empty():
			spots.append(seq.size())
		seq.insert(spots[randi() % spots.size()], h)
	return seq


## [param elite] 本波是否以【星盗战将】压轴（第 2 / 第 3 波各一只）
func _wave(n: int, scale: float, elite := false) -> void:
	_set_wave("第 %d 波 · 星袭" % n)
	if _harass.size() < 2:
		_plan_harass()
	var harass := -1
	if n == 2:
		harass = _harass[0]
	elif n >= 3:
		harass = _harass[1]
	var seq := _wave_colors(n, player.armors, _harass[0], _harass[1])
	var pats := _wave_moves(n)
	var gap := _wave_gap(n)
	for c in seq:
		if not _running:
			return
		_spawn_enemy(scale, c, harass, pats)
		await wait(gap)
	if elite:
		await wait(0.5)
		if not _running:
			return
		_spawn_elite(scale)
	# 等待清场。精英是硬性门槛 —— 星盗可以剩最后一只不等，战将没斩就别想进下一波。
	# 上限放宽到 26 秒：斩一只战将约 8~12 秒，14 秒的窗口会把它卡在半路。
	var limit := 26.0 if elite else 14.0
	var guard := 0.0
	while _running and guard < limit:
		await wait(0.3)
		guard += 0.3
		if _enemy_count() <= 1 and not _elite_alive():
			break


## [param c] 出怪色（由 _wave_colors 排定）
## [param harass] 本波骚扰色；c == harass 时强制 hover（远驻放弹、不追击），
##                harass < 0 表示本波没有骚扰色（第 1 波）
## [param pats] 本波目标色的运动模式池（骚扰色不走这里）
func _spawn_enemy(scale: float, c: int, harass: int, pats: Array[String]) -> void:
	var pat := "hover"
	if c != harass:
		pat = pats[randi() % pats.size()]
	var y := randf() * (Game.VIEW_H - 180.0) + 90.0
	var e := Enemy.new()
	e.world = self
	add_child(e)
	e.player_ref = player
	e.setup(c, pat, y, scale)
	e.killed.connect(_on_enemy_killed)


## 场上还有几只需要清掉的星盗（战将另算，见 _elite_alive）。
func _enemy_count() -> int:
	var n := 0
	for ch in get_children():
		if ch is Enemy:
			n += 1
	return n


## 场上是否还有活着的星盗战将（清场判定用）
func _elite_alive() -> bool:
	for ch in get_children():
		if ch is Elite and not (ch as Elite).dead:
			return true
	return false


## 压轴：星盗战将。力场色由 Elite 自己从玩家战甲里抽 —— 保证一定破得了
func _spawn_elite(scale: float) -> void:
	var e := Elite.new()
	e.world = self
	add_child(e)
	e.player_ref = player
	e.player_armors = player.armors
	e.setup(scale, randf() * (Game.VIEW_H - 300.0) + 150.0)
	e.killed.connect(_on_elite_killed)
	hud.show_banner("星 盗 战 将",
		"身披【%s】力场 —— 换上同色战甲方能速破" % Game.COLOR_CN[e.color], 2.2)


## 斩战将：厚赏 + 必掉一件道具（斩它是有代价的，不能让人空手）
func _on_elite_killed(pos: Vector2, c: int, sc: int) -> void:
	_add_score(sc)
	Fx.pop(self, pos, "+%d" % sc, Game.COLOR_MAIN[c], 24, 1.1)
	Pickup.spawn(self, Pickup.random_kind(), pos)


func _on_enemy_killed(pos: Vector2, c: int, sc: int) -> void:
	_add_score(sc)
	Fx.pop(self, pos, "+%d" % sc, Game.COLOR_MAIN[c], 18)
	if randf() < DROP_CHANCE:
		Pickup.spawn(self, Pickup.random_kind(), pos)


## 每波星袭结束：额外刷新 WAVE_DROP 个道具，散落在场景右段，逼玩家挪过去捡
func _drop_wave() -> void:
	for i in WAVE_DROP:
		var x := randf() * 540.0 + 460.0
		var y := randf() * (Game.VIEW_H - 240.0) + 120.0
		Pickup.spawn(self, Pickup.random_kind(), Vector2(x, y))


# ---------------------------------------------------------------- Boss
func _boss_fight() -> void:
	_set_wave("星盗始祖")
	bg.scroll_speed = 22.0
	boss = Boss.new()
	boss.world = self
	add_child(boss)
	boss.player_ref = player
	boss.player_armors = player.armors
	boss.phase_chg.connect(_on_boss_phase)
	boss.ward_chg.connect(_on_ward)
	boss.enrage_started.connect(_on_enrage)
	boss.boss_died.connect(_on_boss_died)
	hud.bind_boss(boss)
	var sub := "四色弹幕 + 属性护罩，破罩方能致胜" if Game.boss_ward() \
		else "四色弹幕 · 始祖不展护罩，全力输出即可"
	hud.show_banner("星 盗 始 祖", sub, 2.4)


func _on_enrage() -> void:
	hud.show_banner("狂 暴", "始祖周身泛起血光 · 四色螺旋弹幕", 1.8)


func _on_boss_phase(p: int) -> void:
	_add_score(600)
	hud.show_banner("第 %d 阶段" % p, "始祖切换阶段，弹幕更急", 1.6)


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


## 玩家已陨落：清弹、撤敌、让始祖收手。
## 不做这步的话，接下来这 1.5 秒里 Boss 仍会按套路开火，而 player_ref 指向的
## 玩家节点已经被 queue_free —— 把「已释放对象」赋给弹幕的 target 会直接报
## "Invalid assignment ... with value of type 'previously freed'"。
func _stop_field() -> void:
	for ch in get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()
		elif ch is Enemy:
			(ch as Enemy).queue_free()
		elif ch is Elite:
			(ch as Elite).queue_free()
		elif ch is Pickup:
			(ch as Pickup).queue_free()
	if boss != null and is_instance_valid(boss):
		boss.player_ref = null
		boss.stand_down()
	if bg != null:
		bg.scroll_speed = 6.0


func _finish(win: bool) -> void:
	_running = false
	Game.result_win = win
	Game.result_score = score
	Game.result_hp = player.hp if (player != null and is_instance_valid(player)) else 0
	# 先记下本局之前的最好成绩 —— 结算界面要拿它显示「历史最高」，
	# 而存档一旦刷新它就查不到了。
	Game.result_prev_high = Game.highscore_for(Game.difficulty)
	Game.result_is_new_high = score > Game.result_prev_high
	if Game.result_is_new_high:
		Game.save_highscore(Game.difficulty, score, Game.picked_armors,
			Game.rank_of(score), win)
	finished.emit(win)

