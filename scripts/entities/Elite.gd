class_name Elite
extends EliteBase
## 星盗战将 —— 第 2 / 第 3 波星袭的压轴精英怪
##
## 核心是【属性力场】，可以理解为「会走位的旗舰护罩」：
##   · 力场存续时：同色光刃全额（并享同源共振 +50%），异色只剩 EnemyCfg.ELITE_WARD_RESIST；
##     **力场不破，本体一点血都不掉** —— 不换甲就只能在力场上刮痧。
##   · 力场色只从玩家已选的两件战甲中抽取（同旗舰的护罩）。
##     这不是为了复刻机制，而是**可行性要求**：凭空给个玩家没带的颜色，
##     破力场就成了死局 —— 那不是难度，是设计事故。
##   · 打破一层 -> 虚弱期（EnemyCfg.ELITE_BROKEN_TIME）：移速减半、出手放慢、本体任意颜色全额。
##   · 虚弱结束会重铸力场，但 EnemyCfg.ELITE_WARD_LAYERS 有限（用完即永久破防）。
##     无限重铸的话，「打不死」的挫败感会盖过「换甲破力场」的爽点。
##
## 弹幕是**多色**的（`_hues`，色数由 `StageCfg.elite_hue_n(stage)` 定）：
##   · 力场色恒占 ≥50%（偶数发），其余发在 [`力场色, S'①, S'②, S 另一色`] 的余项间轮转。
##   · 力场色之外的色**不参与破力场判定** —— 那是 `color` 一色的职责，别混。
##   · ⚠ 力场色（那个「必须换甲才能破」的色）**必须 ∈ S**；掺进来的 S' 色只是弹幕色，
##     吸不了也破不了，玩家只能走位 —— 铁律管的是前者，不是后者。
## 击杀必掉一件道具（见 Level._on_elite_killed）。
##
## 外观：星盗战将精英机（PirateArt 矢量绘制，独立重画的机械底盘）
## + 矢量力场环 + 头顶双条（力场 / 本体）。
## 不走对象池 —— 一局只有两只，多一层 reset 不值。
##
## 公共字段（killed 信号 / color / hp / max_hp / score / dead / stage / world /
## player_ref / _pop / _bar）已上移到 EliteBase —— 四只精英共用，本类只留力场专属态。

## 本体生命（× hp_scale）
## 数值一律取自 EnemyCfg —— 本文件只留逻辑。
## 碰撞半径 EnemyCfg.ELITE_R 由 EliteBase 提供（四只精英共用 34.0）

## 当前力场值 / 单层力场上限
var ward := 0
var ward_max := 0
## 剩余可重铸层数
var layers := EnemyCfg.ELITE_WARD_LAYERS
## 虚弱期剩余秒数（> 0 即处于力场已破的虚弱状态）
var broken := 0.0
## 力场色只从 EliteBase.player_armors 抽（玩家的已选战甲）
## 弹幕色序（含力场色），由 `setup` -> `_plan_hues()` 排定；长度 = `StageCfg.elite_hue_n`
var _hues: Array[int] = []

var _t := 0.0
var _fire := 0.0
var _flash := 0.0
var _base_y := 360.0
var _home_x := 940.0
var _entered := false
## 呼吸 / 尾抖的实例随机相位（PirateArt 动画用）
var _phase := randf() * TAU


## [param hp_scale] 波次强度系数；[param y] 巡游基准高度
## [param seq] 本关第几只战将（0-based）—— 用于**同关多只战将强制异色**。
##   L3 / L4 / L5 都是两只战将（L3 在第 3/4 波，L4 / L5 在第 4/5 波）。
##   力场色按出场序号取 S 的第 seq 色，**不再随机抽**：纯随机约 50% 概率两只同色，
##   玩家一件甲就能打穿两场，「换甲」这根支柱恰恰在最需要它的那两波上被稀释掉了
##   （总纲 §E.5-L4 注早有承诺，代码一直没做 —— 2026-09-22 补齐）。
##   |S| = 2 时：第 1 只取 S[0]、第 2 只取 S[1]，必然异色。
func setup(hp_scale: float = 1.0, y: float = 360.0, seq: int = 0) -> void:
	max_hp = int(float(EnemyCfg.ELITE_BASE_HP) * hp_scale)
	hp = max_hp
	ward_max = int(float(EnemyCfg.ELITE_WARD_HP) * hp_scale)
	ward = ward_max
	layers = EnemyCfg.ELITE_WARD_LAYERS
	broken = 0.0
	score = EnemyCfg.ELITE_SCORE
	_base_y = y
	position = Vector2(Game.VIEW_W + 90.0, y)
	# 力场色：只从玩家携带的战甲中取 —— 保证一定破得了（可行性铁律）
	if player_armors.is_empty():
		color = randi() % 4
	else:
		color = player_armors[seq % player_armors.size()]
	_plan_hues()
	_fire = 1.2


## 排弹幕色序：[力场色, S'①, S'②, S 的另一色]，再按本关色数截断。
## 顺序有讲究 —— **先掺玩家永远吸不了的 S'**（逼走位，与骚扰色喽啰同款），
## L5 才把玩家的副甲色拉进来（那一关吸弹与破力场开始互相排斥）。
## 每只战将只在 setup 排一次：同一只的色序稳定，玩家读得出规律；
## S' 内部洗牌则让两只战将（L4 / L5 各两只）不至于同序。
func _plan_hues() -> void:
	var comp: Array[int] = []     # S'：四色里玩家没带的
	var s2 := -1                  # S 里不是力场色的那一色
	for c in Game.COLOR_CN.size():
		if player_armors.has(c):
			if c != color:
				s2 = c
		else:
			comp.append(c)
	comp.shuffle()
	var n := StageCfg.elite_hue_n(stage)
	var out: Array[int] = [color]
	for c in comp:
		if out.size() >= n:
			break
		out.append(c)
	if s2 >= 0 and out.size() < n:
		out.append(s2)
	_hues = out


func _ready() -> void:
	collision_layer = 4   # bit2 敌人
	collision_mask = 2    # bit1 玩家子弹
	z_index = 10
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = EnemyCfg.ELITE_R
	cs.shape = sh
	add_child(cs)


func _process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if broken > 0.0:
		broken -= delta
		if broken <= 0.0:
			broken = 0.0
			_recast()
	_motion(delta)
	_firing(delta)
	queue_redraw()


# ---------------------------------------------------------------- 运动
func _motion(delta: float) -> void:
	var slow := 1.0 if broken <= 0.0 else 0.5
	if not _entered:
		position.x = move_toward(position.x, _home_x, EnemyCfg.ELITE_SPEED * slow * delta)
		if absf(position.x - _home_x) < 3.0:
			_entered = true
	else:
		position.x = _home_x + sin(_t * 0.5) * 46.0
	var amp := 72.0 if broken > 0.0 else 108.0
	var fq := 0.35 if broken > 0.0 else 0.62
	position.y = _base_y + sin(_t * fq * TAU) * amp
	if position.x < Game.VIEW_W - 40.0:
		_entered = true


# ---------------------------------------------------------------- 开火
func _firing(delta: float) -> void:
	if not _entered:
		return
	_fire -= delta
	if _fire > 0.0:
		return
	# 与星盗同一条规则：关卡越靠后 bullet_scale 越大，出手越快
	var cd := EnemyCfg.ELITE_FIRE_CD * (2.0 - StageCfg.bullet_scale(stage))
	if broken > 0.0:
		cd *= 1.8
	_fire = cd * (0.85 + randf() * 0.3)
	_shoot()


## 第 i 发弹的颜色：**偶数发恒为力场色**（力场色占 ≥50%，「为主」的落点），
## 奇数发在其余色间轮转。用确定性分配而不是逐发随机 —— 随机可能摇出整轮同色，
## 那既抹掉了「多色」的观感，也可能摇出整轮骚扰色、把换甲收益一次性做没。
func _shot_color(i: int) -> int:
	if _hues.size() <= 1:
		return color
	if i % 2 == 0:
		return color
	return _hues[1 + (i / 2) % (_hues.size() - 1)]


func _shoot() -> void:
	var a := _aim().angle()
	if broken > 0.0:
		# 虚弱：零星三连，给玩家一个喘息窗口
		for i in 3:
			_fire_shot(_shot_color(i), Vector2.RIGHT.rotated(a + (i - 1) * 0.32), 195.0, 9.0, 10)
		return
	match color:
		Game.RED:
			# 电浆战将：七向扇射
			for i in 7:
				_fire_shot(_shot_color(i), Vector2.RIGHT.rotated(a + (i - 3) * 0.19),
					270.0, 9.0, 10)
		Game.BLUE:
			# 寒霜战将：五连速射
			for i in 5:
				_fire_shot(_shot_color(i), Vector2.RIGHT.rotated(a + (i - 2) * 0.06),
					365.0, 8.0, 10)
		Game.YELLOW:
			# 引力战将：慢速宽散射能量弹
			for i in 3:
				_fire_shot(_shot_color(i), Vector2.RIGHT.rotated(a + (i - 1) * 0.44),
					230.0, 10.0, 10)
		_:
			# 光子战将：十四向能量环（缓慢自转）
			for i in 14:
				_fire_shot(_shot_color(i),
					Vector2.RIGHT.rotated(_t * 0.6 + TAU * float(i) / 14.0),
					205.0, 10.0, 10)


# ---------------------------------------------------------------- 受击
func hit(dmg: int, c: int) -> void:
	if dead:
		return
	var same := (c == color)
	# 力场未破 -> 异色刮痧；力场已破 -> 任意颜色全额（同色另有共振 +50%）
	var mul := 1.5 if same else (EnemyCfg.ELITE_WARD_RESIST if ward > 0 else 1.0)
	var real := maxi(1, int(roundf(float(dmg) * mul)))
	_flash = 0.09
	if ward > 0:
		ward -= real
		_pop(real, Game.COLOR_MAIN[color] if same else Color(0.66, 0.70, 0.80), 15)
		if ward <= 0:
			ward = 0
			_break_ward()
		return
	hp -= real
	_pop(real, Color(1.0, 0.85, 0.5) if same else Color(1.0, 1.0, 1.0), 16)
	if hp <= 0:
		hp = 0
		_die()


func _break_ward() -> void:
	broken = EnemyCfg.ELITE_BROKEN_TIME
	layers -= 1
	Fx.ring(world, position, Game.COLOR_MAIN[color], EnemyCfg.ELITE_R, 130.0, 0.5, 6.0)
	Fx.burst(world, position, Game.COLOR_GLOW[color], 22, 320.0, 0.7)
	Fx.pop(world, position + Vector2(0.0, -70.0), "力 场 破",
		Color(1.0, 0.92, 0.55), 21, 1.1)


## 虚弱期结束：还有余层就重铸，否则永久破防
func _recast() -> void:
	if layers <= 0:
		return
	ward = ward_max
	Fx.ring(world, position, Game.COLOR_MAIN[color], 140.0, EnemyCfg.ELITE_R + 10.0, 0.45, 5.0)
	Fx.pop(world, position + Vector2(0.0, -70.0), "力场重铸",
		Game.COLOR_MAIN[color], 18, 0.9)


func _die() -> void:
	dead = true
	Fx.burst(world, position, Game.COLOR_GLOW[color], 26, 360.0, 0.8)
	Fx.ring(world, position, Game.COLOR_MAIN[color], 8.0, 150.0, 0.55, 7.0)
	Fx.shock(world, position, Game.COLOR_MAIN[color], 520.0, 0.9)
	killed.emit(position, color, score)
	queue_free()


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	var g: Color = Game.COLOR_GLOW[color]
	var k: Color = Game.COLOR_CORE[color]
	var pulse := 0.5 + 0.5 * sin(_t * 3.4)

	# ① 自身气息（r38~40，力场弧内缘 43 内留呼吸）
	draw_circle(Vector2.ZERO, 38.0 + 2.0 * pulse, Color(g.r, g.g, g.b, 0.10))

	# ②~⑧ 异形本体（PirateArt：层序铁律在内部完成，CORE 主核最后画）
	PirateArt.draw_elite(self, color, _t, _phase)

	# ⑨ 受击白闪（覆盖本体，读反馈）
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, EnemyCfg.ELITE_R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.4))

	# ⑩ 力场 / 裂环 + 双血条 + 身份文字 —— 永远保持在主体之上
	if ward > 0:
		# 力场：双层弧 + 八枚游走能量点，透明度随剩余值衰减
		var wr := clampf(float(ward) / float(maxi(1, ward_max)), 0.0, 1.0)
		var a := (0.45 + 0.35 * pulse) * (0.45 + 0.55 * wr)
		draw_circle(Vector2.ZERO, EnemyCfg.ELITE_R + 12.0, Color(m.r, m.g, m.b, 0.10 * wr + 0.03))
		draw_arc(Vector2.ZERO, EnemyCfg.ELITE_R + 12.0, 0.0, TAU, 48, Color(m.r, m.g, m.b, a), 6.0, true)
		draw_arc(Vector2.ZERO, EnemyCfg.ELITE_R + 4.0, 0.0, TAU, 48, Color(k.r, k.g, k.b, a * 0.5),
			2.5, true)
		for i in 8:
			var ang := _t * 1.1 + TAU * float(i) / 8.0
			var p := Vector2.RIGHT.rotated(ang) * (EnemyCfg.ELITE_R + 12.0)
			draw_circle(p, 3.6, Color(k.r, k.g, k.b, a))
	else:
		# 力场已破：一圈黯淡的裂环 —— 一眼看出「现在能打疼它」
		for i in 6:
			var a0 := _t * 0.4 + TAU * float(i) / 6.0
			draw_arc(Vector2.ZERO, EnemyCfg.ELITE_R + 8.0, a0, a0 + 0.34, 12,
				Color(0.78, 0.82, 0.95, 0.5), 3.5, true)

	_bars()


## 头顶双条：上条力场、下条本体，外加一行身份
func _bars() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	if ward_max > 0:
		var wr := clampf(float(ward) / float(ward_max), 0.0, 1.0)
		_bar(-48.0, -84.0, 96.0, 6.0, wr, Color(m.r, m.g, m.b, 0.95))
	var hr := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_bar(-48.0, -75.0, 96.0, 7.0, hr, Color(1.0, 0.34, 0.36))
	DrawUtil.txt(self, "星盗战将 · %s" % Game.COLOR_CN[color], Vector2(0.0, -92.0),
		15, m, HORIZONTAL_ALIGNMENT_CENTER)
