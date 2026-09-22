class_name EliteBastion
extends EliteBase
## 弹幕堡垒将 · 移动炮台 —— 中后波登场的新精英（2026-09-22 主理人要求「增加精英怪」）
##
## 一句话：缓慢逼近的厚甲炮台，用高密度环形弹幕织成「墙」，玩家靠弹幕缝隙走位。
##
## 与星盗战将（破罩）刻意互补：
##   · 战将考「换甲破力场」；堡垒将**没有护罩**，是纯 DPS + 弹幕走位检验。
##   · 血量比战将更厚（EnemyCfg.BASTION_BASE_HP 900 vs 480）—— 但它不设色防，任意色都能全额打。
##
## 配色铁律（可行性）：堡垒将**没有必须打破的色防**，弹幕主色就是它自身的 color（∈ S）。
##   玩家换上同色战甲即可吸收其弹幕（寒霜疾甲闪避 / 光子盾甲充盾），
##   不换也能硬躲 —— 不存在「打不破」的死局，故不触铁律。
##   color 由 Level 从玩家战甲 S 里分配（与战将同一口径）。
##
## 弹幕：双层错相环 —— 外圈 12 发缓慢自转、内圈 6 发反向旋转。
##   两层转速不同，织出的「墙」缝隙一直在动，玩家不能站桩，得跟着缝走。
##   全部主色（color），可被同色甲吸收 —— 换甲在这里是「省力」而非「活命」。
##
## 外观：厚重六边装甲炮台（PirateArt 之外的独立简绘，共用 Game 调色板）。
## 不走对象池 —— 一局只出一两只。

## 本体生命（× hp_scale）—— 比战将厚，补偿它没有护罩
## 数值一律取自 EnemyCfg —— 本文件只留逻辑。

var _t := 0.0
var _fire := 0.0
var _flash := 0.0
var _base_y := 360.0
var _home_x := 940.0
var _entered := false
var _phase := randf() * TAU


## [param hp_scale] 波次强度系数；[param y] 巡游基准高度
func setup(hp_scale: float = 1.0, y: float = 360.0) -> void:
	max_hp = int(float(EnemyCfg.BASTION_BASE_HP) * hp_scale)
	hp = max_hp
	score = EnemyCfg.BASTION_SCORE
	_base_y = y
	position = Vector2(Game.VIEW_W + 90.0, y)
	# 弹幕主色：只从玩家携带的战甲中取（可行性铁律，与战将同口径）
	if player_armors.is_empty():
		color = randi() % 4
	else:
		color = player_armors[randi() % player_armors.size()]
	_fire = 1.4


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
	_motion(delta)
	_firing(delta)
	queue_redraw()


# ---------------------------------------------------------------- 运动
## 缓慢逼近到墙的 X 位（不飞出左界），到位后小幅上下浮动
func _motion(delta: float) -> void:
	if not _entered:
		position.x = move_toward(position.x, _home_x, EnemyCfg.BASTION_SPEED * delta)
		if position.x <= _home_x + 4.0:
			_entered = true
	else:
		position.x = _home_x + sin(_t * 0.4) * 30.0
	position.y = _base_y + sin(_t * 0.55 * TAU) * 60.0


# ---------------------------------------------------------------- 开火
func _firing(delta: float) -> void:
	if not _entered:
		return
	_fire -= delta
	if _fire > 0.0:
		return
	# 关卡越靠后 bullet_scale 越大，出手越快
	var cd := EnemyCfg.BASTION_FIRE_CD * (2.0 - StageCfg.bullet_scale(stage))
	_fire = cd * (0.9 + randf() * 0.25)
	_fire_wall()


## 双层错相环：外圈 12 发缓慢自转 + 内圈 6 发反向旋转。
## 两层转速不同，弹幕缝隙持续移动 —— 站桩必被击中，得跟着缝走。
## 全部主色（color ∈ S），可被同色甲吸收。
func _fire_wall() -> void:
	var spin := _t * 0.5
	# 外圈：12 发，慢速，织成「墙」的主体
	for i in 12:
		var a := spin + TAU * float(i) / 12.0
		_fire_shot(color, Vector2.RIGHT.rotated(a), 175.0, 9.0, 9)
	# 内圈：6 发，反向快转，填补外圈缝隙，逼玩家精确走位
	for i in 6:
		var a := -spin * 1.6 + TAU * float(i) / 6.0
		_fire_shot(color, Vector2.RIGHT.rotated(a), 210.0, 7.0, 9)


# ---------------------------------------------------------------- 受击
## 无护罩：任意色全额（同色仍有共振 +50%）
func hit(dmg: int, c: int) -> void:
	if dead:
		return
	var same := (c == color)
	var real := maxi(1, int(roundf(float(dmg) * (1.5 if same else 1.0))))
	_flash = 0.09
	hp -= real
	_pop(real, Color(1.0, 0.85, 0.5) if same else Color(1.0, 1.0, 1.0), 16)
	if hp <= 0:
		hp = 0
		_die()


func _die() -> void:
	dead = true
	Fx.burst(world, position, Game.COLOR_GLOW[color], 26, 360.0, 0.8)
	Fx.ring(world, position, Game.COLOR_MAIN[color], 8.0, 160.0, 0.55, 7.0)
	Fx.shock(world, position, Game.COLOR_MAIN[color], 480.0, 0.9)
	killed.emit(position, color, score)
	queue_free()


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	var g: Color = Game.COLOR_GLOW[color]
	var k: Color = Game.COLOR_CORE[color]
	var dk: Color = Game.COLOR_DARK[color]
	var neu := Color(0.74, 0.78, 0.86)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)

	# ① 引擎辉光（+X 尾）
	draw_circle(Vector2(20.0, 0.0), 26.0 + 3.0 * pulse, Color(g.r, g.g, g.b, 0.12))

	# ② 厚重六边装甲壳（外圈 DARK 描边 + 主装甲 MAIN）
	var hex := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0 - PI / 6.0
		hex.append(Vector2.RIGHT.rotated(a) * 30.0)
	draw_colored_polygon(hex, Color(m.r, m.g, m.b, 1.0))
	var ring := PackedVector2Array(hex)
	ring.append(hex[0])
	draw_polyline(ring, dk, 5.0, true)

	# ③ 环形炮口 ×6（外缘 GLOW 炮管，内嵌 CORE 炮膛）—— 弹幕墙的发射源
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := Vector2.RIGHT.rotated(a) * 30.0
		draw_circle(p, 5.0, Color(g.r, g.g, g.b, 0.9))
		draw_circle(p, 2.4, k)

	# ④ 中部装甲舱 + 肩甲（neu 结构件，不污染属性色）
	draw_circle(Vector2.ZERO, 15.0, Color(neu.r, neu.g, neu.b, 1.0))
	draw_rect(Rect2(-26.0, -6.0, 10.0, 12.0), dk)
	draw_rect(Rect2(16.0, -6.0, 10.0, 12.0), dk)

	# ⑤ 主光学核（CORE，朝向指针，最后画）
	draw_circle(Vector2(-12.0, 0.0), 4.5, k)

	# ⑥ 受击白闪
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, EnemyCfg.ELITE_R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.2))

	# ⑦ 头顶本体血条 + 身份
	var hr := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_bar(-48.0, -78.0, 96.0, 7.0, hr, Color(1.0, 0.34, 0.36))
	DrawUtil.txt(self, "弹幕堡垒将 · %s" % Game.COLOR_CN[color], Vector2(0.0, -86.0),
		15, m, HORIZONTAL_ALIGNMENT_CENTER)
