class_name EliteAegis
extends EliteBase
## 护盾冲锋将 · 朝向重甲 —— 中后波登场的新精英（2026-09-22 主理人要求「增加精英怪」）
##
## 一句话：正面挂一面朝向护盾，只有绕到它侧/后方（上下走位避开护盾锥）才打得到本体。
##
## 与星盗战将（破罩）/ 堡垒将（弹幕）/ 指挥将（召唤）刻意互补：
##   · 战将考「换甲破力场」；指挥将考「清场决策」；冲锋将考「走位绕背 + 换甲」。
##
## 机制（朝向护盾）：
##   · 护盾覆盖 Aegis 朝向玩家的一侧（朝左锥形，半角 SHIELD_ARC = 55°）。
##   · 命中时按「攻击来向」分流（用 player_ref 相对本体的方向现算，无需改 Sword）：
##       - 从护盾锥内（正面）命中 -> 打在护盾上：同色全额 +50%、异色只剩 EnemyCfg.AEGIS_WARD_RESIST，
##         本体一点血不掉。换同色战甲可快速破盾。
##       - 从锥外（侧/背）命中 -> 玩家成功绕背，直接全额打本体（同色仍 +50%）。
##   · 护盾值归零 -> 破盾虚弱（EnemyCfg.AEGIS_BROKEN_TIME，本体任意色全额），虚弱结束重铸一次
##     （护盾单层，重铸次数 = 1，用尽永久破防 —— 与战将力场同一节奏）。
##
## 配色铁律（可行性）：护盾色 = 自身 color，**只从玩家战甲 S 抽取**（Level 分配）。
##   凭空给个玩家没带的色，正面就永远打不穿 = 死局。故护盾色恒 ∈ S。
##   绕背通道是「走位」的奖励，不依赖颜色 —— 不换甲也能靠走位打本体，只是更慢。
##
## 机动：缓慢逼近 + 周期性小幅冲刺（冲锋将的「冲」）。不走对象池。

## 本体生命（× hp_scale）
## 数值一律取自 EnemyCfg —— 本文件只留逻辑。

var ward := 0
var ward_max := 0
var layers := EnemyCfg.AEGIS_SHIELD_LAYERS
var broken := 0.0

var _t := 0.0
var _fire := 0.0
var _charge := 0.0
var _charging := false
var _flash := 0.0
var _base_y := 360.0
var _home_x := 940.0
var _entered := false
var _phase := randf() * TAU

## 护盾锥半角的余弦（正面 facing = 1，锥外 facing < 此值）
var _shield_cos := 1.0


## [param hp_scale] 波次强度系数；[param y] 巡游基准高度
func setup(hp_scale: float = 1.0, y: float = 360.0) -> void:
	max_hp = int(float(EnemyCfg.AEGIS_BASE_HP) * hp_scale)
	hp = max_hp
	ward_max = int(float(EnemyCfg.AEGIS_SHIELD_HP) * hp_scale)
	ward = ward_max
	layers = EnemyCfg.AEGIS_SHIELD_LAYERS
	broken = 0.0
	score = EnemyCfg.AEGIS_SCORE
	_base_y = y
	position = Vector2(Game.VIEW_W + 90.0, y)
	if player_armors.is_empty():
		color = randi() % 4
	else:
		color = player_armors[randi() % player_armors.size()]
	_shield_cos = cos(deg_to_rad(EnemyCfg.AEGIS_SHIELD_ARC_DEG))
	_fire = 1.3
	_charge = EnemyCfg.AEGIS_CHARGE_CD


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
## 缓慢逼近 + 周期性小幅冲锋（朝玩家方向突进一段）
func _motion(delta: float) -> void:
	var spd := EnemyCfg.AEGIS_SPEED
	if not _entered:
		position.x = move_toward(position.x, _home_x, spd * delta)
		if position.x <= _home_x + 4.0:
			_entered = true
	else:
		# 冲锋：朝玩家方向快速突进一小段，随后回落
		_charge -= delta
		if _charge <= 0.0 and not _charging:
			_charging = true
			_charge = EnemyCfg.AEGIS_CHARGE_TIME
		elif _charging:
			spd = EnemyCfg.AEGIS_SPEED * EnemyCfg.AEGIS_CHARGE_MUL
			if _charge <= 0.0:
				_charging = false
				_charge = EnemyCfg.AEGIS_CHARGE_CD
		position.x = move_toward(position.x, _home_x - 60.0, spd * delta)
	position.y = _base_y + sin(_t * 0.6 * TAU) * 48.0


# ---------------------------------------------------------------- 开火
func _firing(delta: float) -> void:
	if not _entered:
		return
	_fire -= delta
	if _fire > 0.0:
		return
	var cd := EnemyCfg.AEGIS_FIRE_CD * (2.0 - StageCfg.bullet_scale(stage))
	if broken > 0.0:
		cd *= 1.6
	_fire = cd * (0.85 + randf() * 0.3)
	# 三向扇射（冲锋将近战压迫）
	var a := _aim().angle()
	for i in 3:
		_fire_shot(color, Vector2.RIGHT.rotated(a + (i - 1) * 0.28), 240.0, 9.0, 9)


# ---------------------------------------------------------------- 受击
## 朝向护盾判定：正面（护盾锥内）打在护盾上，侧/背（锥外）直接打本体
func hit(dmg: int, c: int) -> void:
	if dead:
		return
	var same := (c == color)
	# 攻击来向：从本体指向攻击者（player_ref）的水平方向。横版里光刃恒向右飞，
	# 玩家上下走位决定「打在护盾上」还是「绕到侧/背」。用 player_ref 现算，不改 Sword。
	var facing := _attack_facing()
	# 护盾存续 且 攻击落在护盾锥内（正面）-> 打在护盾上
	if ward > 0 and facing >= _shield_cos:
		var real := maxi(1, int(roundf(float(dmg) * (1.5 if same else EnemyCfg.AEGIS_WARD_RESIST))))
		_flash = 0.09
		ward -= real
		_pop(real, Game.COLOR_MAIN[color] if same else Color(0.66, 0.70, 0.80), 15)
		if ward <= 0:
			ward = 0
			_break_ward()
		return
	# 侧/背命中（绕背成功）或护盾已破 -> 打本体全额
	var real := maxi(1, int(roundf(float(dmg) * (1.5 if same else 1.0))))
	_flash = 0.09
	hp -= real
	_pop(real, Color(1.0, 0.85, 0.5) if same else Color(1.0, 1.0, 1.0), 16)
	if hp <= 0:
		hp = 0
		_die()


## 攻击来向相对本体朝向（-X = 面向玩家）的 facing 值：
##   1.0 = 正对玩家（正面，护盾挡）；0.0 = 正上/正下方（锥外，绕背）；< 0 = 背后
## ⚠ 取 **-d.x**：玩家在左方（Aegis 正面）时 d.x = -1，取负得 facing = 1 → 判为正面打护盾。
##   原先漏了负号（return d.x），导致正面 facing=-1 被误判成绕背、护盾形同虚设（2026-09-22 修）。
func _attack_facing() -> float:
	if player_ref != null and is_instance_valid(player_ref):
		var d := (player_ref.position - position).normalized()
		return -d.x
	# 无玩家信息时按正面处理（保守，护盾挡）
	return 1.0


func _break_ward() -> void:
	broken = EnemyCfg.AEGIS_BROKEN_TIME
	layers -= 1
	Fx.ring(world, position, Game.COLOR_MAIN[color], EnemyCfg.ELITE_R, 130.0, 0.5, 6.0)
	Fx.burst(world, position, Game.COLOR_GLOW[color], 20, 300.0, 0.7)
	Fx.pop(world, position + Vector2(0.0, -70.0), "护 盾 破",
		Color(1.0, 0.92, 0.55), 21, 1.1)


func _recast() -> void:
	if layers <= 0:
		return
	ward = ward_max
	Fx.ring(world, position, Game.COLOR_MAIN[color], 140.0, EnemyCfg.ELITE_R + 10.0, 0.45, 5.0)
	Fx.pop(world, position + Vector2(0.0, -70.0), "护盾重铸",
		Game.COLOR_MAIN[color], 18, 0.9)


func _die() -> void:
	dead = true
	Fx.burst(world, position, Game.COLOR_GLOW[color], 26, 360.0, 0.8)
	Fx.ring(world, position, Game.COLOR_MAIN[color], 8.0, 150.0, 0.55, 7.0)
	Fx.shock(world, position, Game.COLOR_MAIN[color], 500.0, 0.9)
	killed.emit(position, color, score)
	queue_free()


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	var g: Color = Game.COLOR_GLOW[color]
	var k: Color = Game.COLOR_CORE[color]
	var dk: Color = Game.COLOR_DARK[color]
	var neu := Color(0.74, 0.78, 0.86)
	var pulse := 0.5 + 0.5 * sin(_t * 3.2)

	# ① 引擎辉光
	draw_circle(Vector2(18.0, 0.0), 24.0 + 3.0 * pulse, Color(g.r, g.g, g.b, 0.12))

	# ② 重甲主体（方舱 MAIN + DARK 描边，比战将更敦实）
	var body := PackedVector2Array([
		Vector2(-30.0, -16.0), Vector2(-6.0, -20.0), Vector2(20.0, -14.0),
		Vector2(24.0, 0.0), Vector2(20.0, 14.0), Vector2(-6.0, 20.0),
		Vector2(-30.0, 16.0),
	])
	draw_colored_polygon(body, Color(m.r, m.g, m.b, 1.0))
	var ring := PackedVector2Array(body)
	ring.append(body[0])
	draw_polyline(ring, dk, 5.0, true)

	# ③ 前置护盾臂（-X 侧，neu 装甲 + GLOW 护盾面）—— 朝向护盾的视觉锚点
	draw_rect(Rect2(-44.0, -14.0, 16.0, 28.0), Color(neu.r, neu.g, neu.b, 1.0))
	draw_rect(Rect2(-46.0, -10.0, 4.0, 20.0), Color(g.r, g.g, g.b, 0.9))

	# ④ 冲锋喷口 ×2（+X 尾，GLOW）
	draw_rect(Rect2(24.0, -12.0, 8.0, 8.0), Color(g.r, g.g, g.b, 0.85))
	draw_rect(Rect2(24.0, 4.0, 8.0, 8.0), Color(g.r, g.g, g.b, 0.85))

	# ⑤ 主光学核（CORE，朝向指针，最后画）
	draw_circle(Vector2(-14.0, 0.0), 4.5, k)

	# ⑥ 受击白闪
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, EnemyCfg.ELITE_R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.2))

	# ⑦ 护罩 / 破盾裂环 + 双血条 + 身份
	if ward > 0:
		var wr := clampf(float(ward) / float(maxi(1, ward_max)), 0.0, 1.0)
		var a := (0.45 + 0.35 * pulse) * (0.45 + 0.55 * wr)
		# 护盾锥：朝左（-X）的扇形弧，半角 EnemyCfg.AEGIS_SHIELD_ARC_DEG —— 一眼看出「正面有盾、侧后可绕」
		var half := deg_to_rad(EnemyCfg.AEGIS_SHIELD_ARC_DEG)
		draw_arc(Vector2.ZERO, EnemyCfg.ELITE_R + 12.0, PI - half, PI + half, 32,
			Color(m.r, m.g, m.b, a), 6.0, true)
		draw_arc(Vector2.ZERO, EnemyCfg.ELITE_R + 4.0, PI - half, PI + half, 32,
			Color(k.r, k.g, k.b, a * 0.5), 2.5, true)
	else:
		for i in 6:
			var a0 := _t * 0.4 + TAU * float(i) / 6.0
			draw_arc(Vector2.ZERO, EnemyCfg.ELITE_R + 8.0, a0, a0 + 0.34, 12,
				Color(0.78, 0.82, 0.95, 0.5), 3.5, true)
	_bars()


## 头顶双条：上条护盾、下条本体，外加一行身份
func _bars() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	if ward_max > 0:
		var wr := clampf(float(ward) / float(ward_max), 0.0, 1.0)
		_bar(-48.0, -84.0, 96.0, 6.0, wr, Color(m.r, m.g, m.b, 0.95))
	var hr := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_bar(-48.0, -75.0, 96.0, 7.0, hr, Color(1.0, 0.34, 0.36))
	DrawUtil.txt(self, "护盾冲锋将 · %s" % Game.COLOR_CN[color], Vector2(0.0, -92.0),
		15, m, HORIZONTAL_ALIGNMENT_CENTER)
