class_name EliteSwarm
extends EliteBase
## 增殖指挥将 · 召唤母舰 —— 中后波登场的新精英（2026-09-22 主理人要求「增加精英怪」）
##
## 一句话：周期性召唤同色喽啰增援的母舰，本体躲在召唤物后面，得先清场才能打疼它。
##
## 与星盗战将（破罩）/ 堡垒将（弹幕）刻意互补：
##   · 战将考「换甲破力场」；堡垒将考「弹幕走位」；指挥将考「清场优先级决策」。
##   · 本体血量中等，但常年有召唤物挡在前面 —— 忽视清场就会一直被喽啰消耗。
##
## 配色铁律（可行性）：召唤物的颜色恒 ∈ 玩家战甲 S（复用 Level 分配的 color）。
##   召唤物是正常喽啰（阻塞清场），玩家**必须**能清掉它们 —— 若召出玩家免疫不了的
##   颜色，就成了「清不掉、过不了波」的死局。故召唤色一律取自身 color（∈ S）。
##
## 机制：
##   · 每 EnemyCfg.SWARM_SUMMON_CD 秒召唤一批（EnemyCfg.SWARM_SUMMON_BATCH 只）同色喽啰，硬闸 MAX_REINFORCE 上限。
##   · 召唤物走 Spawner.enemy 生成（正常喽啰，阻塞清场、给分、可掉落）。
##   · 本体自身弹幕轻（两发点射），威胁来自它不断补充的召唤群。
##   · 血量中等（EnemyCfg.SWARM_BASE_HP 620）—— 清掉召唤物后能较快打穿本体。
##
## 外观：臃肿的母舰 chassis（独立简绘，共用 Game 调色板）。不走对象池。

## 本体生命（× hp_scale）
## 数值一律取自 EnemyCfg —— 本文件只留逻辑。

var _t := 0.0
var _fire := 0.0
var _summon := 0.0
var _flash := 0.0
var _base_y := 360.0
var _home_x := 940.0
var _entered := false
var _phase := randf() * TAU


## [param hp_scale] 波次强度系数；[param y] 巡游基准高度
func setup(hp_scale: float = 1.0, y: float = 360.0) -> void:
	max_hp = int(float(EnemyCfg.SWARM_BASE_HP) * hp_scale)
	hp = max_hp
	score = EnemyCfg.SWARM_SCORE
	_base_y = y
	position = Vector2(Game.VIEW_W + 90.0, y)
	if player_armors.is_empty():
		color = randi() % 4
	else:
		color = player_armors[randi() % player_armors.size()]
	_fire = 1.2
	_summon = EnemyCfg.SWARM_SUMMON_CD * 0.6   # 首次召唤稍快，避免开场太久无事发生


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
	_summoning(delta)
	queue_redraw()


# ---------------------------------------------------------------- 运动
func _motion(delta: float) -> void:
	if not _entered:
		position.x = move_toward(position.x, _home_x, EnemyCfg.SWARM_SPEED * delta)
		if position.x <= _home_x + 4.0:
			_entered = true
	else:
		position.x = _home_x + sin(_t * 0.45) * 34.0
	position.y = _base_y + sin(_t * 0.5 * TAU) * 54.0


# ---------------------------------------------------------------- 开火（轻弹幕）
func _firing(delta: float) -> void:
	if not _entered:
		return
	_fire -= delta
	if _fire > 0.0:
		return
	var cd := EnemyCfg.SWARM_FIRE_CD * (2.0 - StageCfg.bullet_scale(stage))
	_fire = cd * (0.85 + randf() * 0.3)
	var a := _aim().angle()
	_fire_shot(color, Vector2.RIGHT.rotated(a + 0.10), 250.0, 8.0, 8)
	_fire_shot(color, Vector2.RIGHT.rotated(a - 0.10), 250.0, 8.0, 8)


## 周期性召唤同色喽啰（硬闸 MAX_REINFORCE 上限，超上限不生成、不排队）
func _summoning(delta: float) -> void:
	if not _entered:
		return
	_summon -= delta
	if _summon > 0.0:
		return
	_summon = EnemyCfg.SWARM_SUMMON_CD
	_spawn_reinforce()


func _spawn_reinforce() -> void:
	if world == null:
		return
	# 硬闸：统计场上本指挥将召唤的喽啰（用 _reinforce 标记识别）
	var n := 0
	for ch in world.get_children():
		if ch is Enemy and (ch as Enemy)._reinforce and not (ch as Enemy).dead:
			n += 1
	if n >= EnemyKind.MAX_REINFORCE:
		return
	for i in EnemyCfg.SWARM_SUMMON_BATCH:
		if n + i >= EnemyKind.MAX_REINFORCE:
			break
		_spawn_one()


func _spawn_one() -> void:
	if world == null:
		return
	var e := Enemy.new()
	e.world = world
	e.kind = EnemyKind.K.GRUNT
	e.stage = stage
	e._phase = randf() * TAU
	# 召唤物从本体附近出现，向左右散开
	var ang := randf() * TAU
	var off := Vector2.RIGHT.rotated(ang) * 40.0
	world.add_child(e)
	# 召唤物血量按本体波次强度放大；color ∈ S 保证玩家清得掉
	e.setup(color, "sine", position.y + off.y, float(max_hp) / float(EnemyCfg.SWARM_BASE_HP))
	e._reinforce = true   # setup 会复位，故在其后置位
	e.position = position + off
	e.player_ref = player_ref
	e.score = EnemyKind.score_of(EnemyKind.K.GRUNT)
	e.killed.connect(_on_reinforce_killed)


## 召唤物死亡：母舰短暂回血（增殖的爽点 —— 清不干净它就回上来）
func _on_reinforce_killed(_pos: Vector2, _c: int, _sc: int) -> void:
	if dead or world == null:
		return
	var heal := int(float(max_hp) * EnemyCfg.SWARM_HEAL_RATIO)
	if heal <= 0:
		return
	hp = mini(max_hp, hp + heal)
	_pop(heal, Game.COLOR_MAIN[color], 15)


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
	Fx.burst(world, position, Game.COLOR_GLOW[color], 26, 340.0, 0.8)
	Fx.ring(world, position, Game.COLOR_MAIN[color], 8.0, 150.0, 0.55, 7.0)
	killed.emit(position, color, score)
	queue_free()


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	var g: Color = Game.COLOR_GLOW[color]
	var k: Color = Game.COLOR_CORE[color]
	var dk: Color = Game.COLOR_DARK[color]
	var neu := Color(0.74, 0.78, 0.86)
	var pulse := 0.5 + 0.5 * sin(_t * 2.6)

	# ① 引擎辉光
	draw_circle(Vector2(18.0, 0.0), 24.0 + 3.0 * pulse, Color(g.r, g.g, g.b, 0.12))

	# ② 臃肿母舰主体（椭舱 MAIN + DARK 描边）
	var body := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		var rx := 32.0 if absf(cos(a)) > 0.3 else 26.0
		body.append(Vector2(cos(a) * rx, sin(a) * 24.0))
	draw_colored_polygon(body, Color(m.r, m.g, m.b, 1.0))
	var ring := PackedVector2Array(body)
	ring.append(body[0])
	draw_polyline(ring, dk, 4.5, true)

	# ③ 召唤舱口 ×4（GLOW 圆舱，母舰「增殖」的视觉标识）
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var p := Vector2.RIGHT.rotated(a) * 22.0
		draw_circle(p, 4.5, Color(g.r, g.g, g.b, 0.9))

	# ④ 中部指挥舱（neu + CORE 主核）
	draw_circle(Vector2.ZERO, 12.0, Color(neu.r, neu.g, neu.b, 1.0))
	draw_circle(Vector2(-10.0, 0.0), 4.0, k)

	# ⑤ 尾焰
	draw_rect(Rect2(26.0, -5.0, 8.0, 10.0), Color(g.r, g.g, g.b, 0.85))

	# ⑥ 受击白闪
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, EnemyCfg.ELITE_R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.2))

	# ⑦ 头顶血条 + 身份
	var hr := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_bar(-48.0, -78.0, 96.0, 7.0, hr, Color(1.0, 0.34, 0.36))
	DrawUtil.txt(self, "增殖指挥将 · %s" % Game.COLOR_CN[color], Vector2(0.0, -86.0),
		15, m, HORIZONTAL_ALIGNMENT_CENTER)
