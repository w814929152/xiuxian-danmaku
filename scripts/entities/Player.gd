class_name Player
extends Area2D
## 玩家 · 星舰战士
## 两件战甲随时按【空格】切换，战甲决定：免疫色 / 攻击形态 / 被动

signal stat_changed()
signal armor_changed(c: int)
signal player_died()

const MAX_HP := 100
## 光子护盾上限。护盾**不会**自动回复 —— 唯一充能入口是穿着光子盾甲（白）
## 吞下一枚光子弹（同色吸收），见 take_hit()。
const SHIELD_MAX := 20
## 光子盾甲每吸收一枚光子弹的充能量（钳到 SHIELD_MAX 为止）
const SHIELD_GAIN := 10
const BASE_SPEED := 340.0
const BLUE_MUL := 1.5          # 寒霜疾甲：移速 +50%
## 寒霜疾甲：吞下一枚寒霜弹后获得 0.5 秒闪避，期间不承受任何**弹幕**伤害。
## 只挡走 take_hit() 的弹幕通道 —— 殉爆者冲撞 / 冲击环是刻意绕过同色免疫的
## 物理通道（EnemyBrain 里直接扣 hp），不接入本状态。
const DODGE_TIME := 0.5
## 闪避期的机体透明度基准：整体变淡，只叠极轻呼吸。
## 不做高频闪烁 —— 闪避只有 0.5 秒，闪起来玩家根本读不清自己在哪里。
const DODGE_ALPHA := 0.28
const DODGE_BREATH := 0.06
const HIT_R := 11.0
const FIRE_CD := 0.105
const SWAP_CD := 0.20
const INVULN := 0.85

# ---------------------------------------------------------------- 引力束甲 · 引力束过热
const BEAM_DPS := 120.0        # 引力束每秒伤害
const HEAT_MAX := 100.0        # 过热值上限，满则无法出束
const HEAT_RISE := 20.0        # 出束时每秒累积
const HEAT_COOL_DELAY := 0.5   # 停火多久后开始散热
const HEAT_COOL := 30.0        # 散热速度（每秒）
const HEAT_VENT := 30.0        # 触到引力（黄）弹时立刻散去
## 解锁阈值：过热后必须散到这个数值以下才能重新出束。
## 不加这道闸门的话，按住不放会卡在「锁 0.5 秒 -> 亮 1 帧 -> 再锁」的抖动里
## （升温 20/s 远快于每帧的散热量，占空比只剩约 5%），引力束等于废掉。
const HEAT_REARM := 60.0

# ---------------------------------------------------------------- 道具增益
const HEAL_AMOUNT := 20       # 修复包：回复生命
const MULTI_MAX := 3          # 刃影模块：最多再叠 3 排弹道
const ATK_STEP := 0.30        # 增幅核心：每层 +30%
const ATK_MAX := 4            # 增幅核心：最多叠 4 层（+120%）
const INVINC_TIME := 6.0      # 力场罩：无敌 6 秒
## 增幅核心的视觉强度：光刃放大 / 引力束加粗都用这个系数
const ATK_VIS := 0.22

var hp: int = MAX_HP
## 光子护盾：开局为 0，靠吸收光子弹充能（上限 SHIELD_MAX，不自动回复）
var shield: int = 0
## 过热值：只在使用引力束甲（黄）出束时累积
var heat: float = 0.0
## 刃影模块层数 = 额外弹道排数（电浆基准双排，其余基准单排，引力基准一道束）
var multi: int = 0
## 增幅核心层数 = 攻击力 +30% × 层数
var atk_up: int = 0
## 力场罩剩余秒数（> 0 即处于无敌）
var invinc: float = 0.0
var _locked := false       # 过热闭锁：一旦满值，须散到 HEAT_REARM 以下才解锁
## 由 Level 显式注入：光刃与特效的挂载容器（不靠 get_parent 猜）
var world: Node2D = null
## 本局携带的两件战甲（进入关卡前选定，关卡内按空格轮换）
var armors: Array[int] = [Game.RED, Game.WHITE]
var armor_idx := 0
var alive := true

var _fire := 0.0
var _swap := 0.0
var _invuln := 0.0
var _flash := 0.0
var _immune := 0.0
## 寒霜疾甲 · 闪避剩余秒数（> 0 即处于闪避）
var _dodge := 0.0
var _time := 0.0
var _trail: Array[Vector2] = []
var _firing := false      # 本帧是否正在出光
var _idle := 0.0          # 已停火多久
## 引力束（首次出束时创建，常驻；叠了刃影模块会有多道）
var _beams: Array[Beam] = []

var color: int:
	get:
		if armors.is_empty():
			return Game.WHITE
		return armors[armor_idx % armors.size()]

## 过热闭锁中（满值 -> 未散到 HEAT_REARM 之前）无法出光
var overheated: bool:
	get:
		return _locked

## 攻击力倍率（增幅核心层数 × 30%）
var atk_mul: float:
	get:
		return 1.0 + ATK_STEP * float(atk_up)

## 力场罩生效中
var invincible: bool:
	get:
		return invinc > 0.0

## 寒霜疾甲 · 闪避生效中（期间弹幕穿身而过）
var dodging: bool:
	get:
		return _dodge > 0.0

## 寒霜疾甲 · 闪避剩余秒数（HUD 只读取展示，不自己算时间）
var dodge_left: float:
	get:
		return _dodge


func can_fire() -> bool:
	return alive and not overheated


## 当前实际弹道排数：电浆剑甲基准双排，其余基准单排（引力是一道束），
## 再加上刃影模块的层数。
func rows() -> int:
	return (2 if color == Game.RED else 1) + multi


## 单发伤害（受增幅核心影响）
func sword_damage() -> int:
	var base := 8 if color == Game.RED else 10
	return maxi(1, int(roundf(float(base) * atk_mul)))


## 光刃尺寸系数：增幅核心层数越多，剑身越大（碰撞体同步放大）
func sword_size() -> float:
	return 1.0 + ATK_VIS * float(atk_up)


## 引力束每秒伤害（受增幅核心影响）
func beam_dps() -> float:
	return BEAM_DPS * atk_mul


## 引力束粗细系数：增幅核心层数越多，光柱越粗
func beam_width() -> float:
	return 1.0 + ATK_VIS * float(atk_up)


func _ready() -> void:
	collision_layer = 1        # bit0 玩家
	collision_mask = 4 | 8 | 16  # bit2 敌人 / bit3 敌弹 / bit4 道具
	z_index = 12
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = HIT_R
	cs.shape = sh
	add_child(cs)
	position = Vector2(230.0, Game.VIEW_H * 0.5)


func _process(delta: float) -> void:
	if not alive:
		return
	_time += delta
	_fire = maxf(0.0, _fire - delta)
	_swap = maxf(0.0, _swap - delta)
	_invuln = maxf(0.0, _invuln - delta)
	_flash = maxf(0.0, _flash - delta)
	_immune = maxf(0.0, _immune - delta)
	_dodge = maxf(0.0, _dodge - delta)
	# 力场罩：与受击后的无敌帧（_invuln）是两套，互不干涉
	if invinc > 0.0:
		invinc = maxf(0.0, invinc - delta)

	_move(delta)
	_shoot()
	_update_heat(delta)
	_update_trail()

	# 无敌闪烁。闪避是更「实」的相位化解 —— 整体比无敌帧更淡，且优先级更高，
	# 否则吸弹后的 0.85 秒无敌帧会把闪避的读条盖掉，玩家看不出自己还在闪避中。
	var a := 1.0
	if _dodge > 0.0:
		a = DODGE_ALPHA + DODGE_BREATH * (0.5 + 0.5 * sin(_time * 8.0))
	elif _invuln > 0.0:
		a = 0.35 + 0.35 * (0.5 + 0.5 * sin(_time * 45.0))
	modulate.a = a
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event.is_action_pressed("swap"):
		if _swap <= 0.0:
			do_swap()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 移动
func _move(delta: float) -> void:
	var d := Vector2.ZERO
	if Input.is_action_pressed("mv_left"):
		d.x -= 1.0
	if Input.is_action_pressed("mv_right"):
		d.x += 1.0
	if Input.is_action_pressed("mv_up"):
		d.y -= 1.0
	if Input.is_action_pressed("mv_down"):
		d.y += 1.0
	if d != Vector2.ZERO:
		d = d.normalized()
		var sp := BASE_SPEED * (BLUE_MUL if color == Game.BLUE else 1.0)
		position += d * sp * delta
	position = Game.clamp_view(position, 28.0)


# ---------------------------------------------------------------- 攻击
## 引力束甲走「按住持续出束」，其余战甲走「按冷却递光刃」
func _shoot() -> void:
	var firing := Input.is_action_pressed("shoot") \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_firing = false
	if color == Game.YELLOW:
		if firing and can_fire():
			_firing = true
			_beam_on()
		else:
			_beam_off()
		return
	_beam_off()
	if not firing:
		return
	if _fire > 0.0:
		return
	_fire = FIRE_CD
	_fire_swords()


## 一次齐射：排数取 rows()，沿竖直方向均匀铺开。
## 间距随排数收窄，最多铺到 ±50，免得 4 排以上飞出屏幕外。
func _fire_swords() -> void:
	var n := rows()
	var dmg := sword_damage()
	var size := sword_size()
	var gap := minf(34.0, 100.0 / maxf(1.0, float(n - 1)))
	for i in n:
		var oy := (float(i) - (float(n) - 1.0) * 0.5) * gap
		_spawn_sword(Vector2(26.0, oy), dmg, size)


# ---------------------------------------------------------------- 引力束
## 引力束甲叠了刃影模块 -> 多道引力束并排。
## 注意过热值**不随道数增加**：_update_heat() 只认「是否在出束」这一件事，
## 加排只加伤害，不加发热（这是需求里明确要求的）。
func _beam_on() -> void:
	if world == null:
		return
	var n := rows()
	while _beams.size() < n:
		var b := Beam.new()
		b.world = world
		add_child(b)
		_beams.append(b)
	for i in _beams.size():
		var bm: Beam = _beams[i]
		if i >= n:
			bm.turn_off()
			continue
		if not bm.on:
			bm.turn_on()
		bm.dps = beam_dps()
		bm.width_mul = beam_width()
		bm.aim(global_position.x, _beam_y(i, n))


func _beam_off() -> void:
	for i in _beams.size():
		var bm: Beam = _beams[i]
		if bm.on:
			bm.turn_off()


## 多道引力束在竖直方向均匀铺开：1 道居中，2 道上下，3 道加中线……
func _beam_y(i: int, n: int) -> float:
	if n <= 1:
		return 0.0
	var gap := minf(46.0, 200.0 / float(n - 1))
	return (float(i) - (float(n) - 1.0) * 0.5) * gap


# ---------------------------------------------------------------- 过热
## 出束 -> 每秒 +20；停火满 0.5 秒 -> 每秒 -30；触及引力弹 -> 立刻 -30
func _update_heat(delta: float) -> void:
	if _firing:
		_idle = 0.0
		heat = minf(HEAT_MAX, heat + HEAT_RISE * delta)
		if not _locked and heat >= HEAT_MAX:
			_locked = true
			Fx.pop(world, position + Vector2(0.0, -46.0), "过 热",
				Color(1.0, 0.55, 0.30), 20, 0.9)
			stat_changed.emit()
		return
	_idle += delta
	if _idle >= HEAT_COOL_DELAY and heat > 0.0:
		heat = maxf(0.0, heat - HEAT_COOL * delta)
		if _locked and heat <= HEAT_REARM:
			_locked = false
			stat_changed.emit()


func _spawn_sword(off: Vector2, dmg: int, size: float = 1.0) -> void:
	if world == null:
		return
	Sword.spawn(world, color, position + off, dmg, Vector2(980.0, 0.0), size)


# ---------------------------------------------------------------- 换甲
func do_swap() -> void:
	if armors.size() < 2:
		return
	armor_idx = (armor_idx + 1) % armors.size()
	_swap = SWAP_CD
	_invuln = maxf(_invuln, 0.18)
	# 闪避是寒霜疾甲的附属能力：一脱甲就立刻失效（不留残余时间）
	_dodge = 0.0
	armor_changed.emit(color)
	stat_changed.emit()
	Fx.ring(world, position, Game.COLOR_MAIN[color], 6.0, 52.0, 0.32, 7.0)


# ---------------------------------------------------------------- 受伤
## 返回 true 表示弹幕应被消耗（被吸收 / 打中）；false 表示穿过
## （无敌帧 / 力场罩 / 寒霜疾甲闪避）
func take_hit(c: int, dmg: int) -> bool:
	if not alive or _invuln > 0.0:
		return false
	# 寒霜疾甲 · 闪避：这 0.5 秒里任何弹幕都穿身而过 ——
	# 返回 false 是刻意的：弹幕**不消失、继续飞**（true 才会被消耗），
	# 也不掉血、不消耗护盾、不进入受击后的无敌帧（闪避本身已经够用了）。
	if _dodge > 0.0:
		return false
	# 引力（黄）弹：不论身上是否引力束甲，触及即引走热气
	if c == Game.YELLOW and heat > 0.0:
		heat = maxf(0.0, heat - HEAT_VENT)
		Fx.pop(world, position + Vector2(0.0, -46.0), "散热 -%d" % int(HEAT_VENT),
			Game.COLOR_MAIN[Game.YELLOW], 16, 0.7)
		stat_changed.emit()
	# 力场罩：六秒内诸法不侵（放在扣血之前，所以既不扣血也不消耗护盾）
	if invinc > 0.0:
		_immune = 0.22
		Fx.ring(world, position, Game.COLOR_MAIN[randi() % 4], 17.0, 48.0, 0.26, 4.0)
		return false
	if c == color:
		# 同色吸收：战甲把这一枚吞下去（Danmaku 收到 true 会 _kill 消失），玩家不掉血。
		# 光环由「内 -> 外」翻成「外 -> 内」收拢：读起来是吸入，而不是弹开。
		_immune = 0.22
		Fx.ring(world, position, Game.COLOR_GLOW[c], 34.0, 8.0, 0.24, 3.0)
		# 寒霜疾甲专属：吸收的同时相位化解 -> 进入 0.5 秒闪避。
		# 其余三件战甲吸弹只有上面那圈收拢光环，不带闪避。
		if c == Game.BLUE:
			_dodge = DODGE_TIME
			Fx.ring(world, position, Game.COLOR_MAIN[Game.BLUE], 12.0, 46.0, 0.30, 3.0)
			Fx.pop(world, position + Vector2(0.0, -30.0), "闪避",
				Game.COLOR_GLOW[Game.BLUE], 16, 0.5)
		# 光子盾甲专属：吞下的光子弹不白吞 —— 转为护盾充能（+10，钳到上限）。
		# 这是护盾**唯一**的充能入口（自动回复已取消）。
		# 守卫把 c 与 color 两态都写全：上面 `c == color` 已保证同色，这里再钉一次
		# 「必须穿着光子盾甲」，免得有人把它挪到别的分支里去。
		if c == Game.WHITE and color == Game.WHITE:
			var before := shield
			shield = mini(SHIELD_MAX, shield + SHIELD_GAIN)
			stat_changed.emit()
			if shield > before:
				Fx.pop(world, position + Vector2(0.0, -32.0), "护盾 +%d" % (shield - before),
					Game.COLOR_GLOW[Game.WHITE], 16, 0.7)
			else:
				Fx.pop(world, position + Vector2(0.0, -32.0), "护盾已满",
					Game.COLOR_GLOW[Game.WHITE], 16, 0.7)
		return true

	if color == Game.WHITE and shield > 0:
		var ab := mini(shield, dmg)
		shield -= ab
		dmg -= ab
		Fx.ring(world, position, Color(1.0, 1.0, 1.0, 0.9), 18.0, 44.0, 0.32, 5.0)
		Fx.pop(world, position + Vector2(0.0, -32.0), "护盾 -%d" % ab,
			Color(0.90, 0.95, 1.0), 16)
	if dmg > 0:
		hp -= dmg
		_invuln = INVULN
		Fx.burst(world, position, Game.COLOR_MAIN[c], 14, 300.0, 0.5)
		Fx.pop(world, position + Vector2(0.0, -30.0), "-%d" % dmg,
			Color(1.0, 0.55, 0.5), 18)
	_flash = 0.25
	stat_changed.emit()
	if hp <= 0:
		hp = 0
		_die()
	return true


# ---------------------------------------------------------------- 拾取
## 施加一个道具效果，返回给玩家看的飘字（空串 = 不提示）。
## 效果挂在玩家身上，所以入口放这里；道具只负责认出玩家并调用。
func apply_pickup(k: int) -> String:
	match k:
		Pickup.T.HEAL:
			if hp >= MAX_HP:
				return "生命已满"
			hp = mini(MAX_HP, hp + HEAL_AMOUNT)
			stat_changed.emit()
			return "生命 +%d" % HEAL_AMOUNT
		Pickup.T.MULTI:
			if multi >= MULTI_MAX:
				return "弹道已满"
			multi += 1
			stat_changed.emit()
			return "弹道 +1 · 共 %d 排" % rows()
		Pickup.T.ATK:
			if atk_up >= ATK_MAX:
				return "攻击已满"
			atk_up += 1
			stat_changed.emit()
			return "攻击 +%d%%" % int(ATK_STEP * 100.0)
		Pickup.T.INVINC:
			invinc = maxf(invinc, INVINC_TIME)
			stat_changed.emit()
			return "力场罩 · %.0f 秒" % INVINC_TIME
	return ""


func _die() -> void:
	alive = false
	modulate.a = 1.0
	_beam_off()
	Fx.burst(world, position, Color(1.0, 1.0, 1.0), 36, 420.0, 0.9)
	Fx.shock(world, position, Color(1.0, 1.0, 1.0), 280.0, 0.8)
	player_died.emit()
	set_process(false)
	queue_free()


# ---------------------------------------------------------------- 绘制
func _update_trail() -> void:
	if color == Game.BLUE:
		_trail.push_front(position)
		if _trail.size() > 9:
			_trail.pop_back()
	elif _trail.size() > 0:
		_trail.clear()


func _draw() -> void:
	var c := color
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var k: Color = Game.COLOR_CORE[c]
	var dk: Color = Game.COLOR_DARK[c]
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)

	# 寒霜疾甲：残影
	for i in _trail.size():
		var p := to_local(_trail[i])
		var a := 0.22 * (1.0 - float(i) / float(_trail.size()))
		draw_circle(p, 12.0 - i, Color(g.r, g.g, g.b, a))

	# 灵光外环
	draw_circle(Vector2.ZERO, 26.0 + 3.0 * pulse, Color(g.r, g.g, g.b, 0.10))
	draw_arc(Vector2.ZERO, 23.0 + 2.5 * pulse, 0.0, TAU, 32,
		Color(m.r, m.g, m.b, 0.45), 2.0, true)

	# 力场罩：六秒无敌 —— 四色流转的护体罩 + 逆向游走的能量点
	if invinc > 0.0:
		var ia := 0.70 + 0.30 * sin(_time * 8.0)
		if invinc < 1.2:                     # 将散时急促闪烁，给玩家收尾提示
			ia *= 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 26.0))
		var rr := 41.0 + 3.0 * sin(_time * 5.0)
		for i in 4:
			var a0 := _time * 2.4 + TAU * float(i) / 4.0
			var cc: Color = Game.COLOR_MAIN[i]
			draw_arc(Vector2.ZERO, rr, a0, a0 + TAU * 0.25, 14,
				Color(cc.r, cc.g, cc.b, 0.85 * ia), 5.0, true)
		draw_circle(Vector2.ZERO, rr, Color(0.78, 0.90, 1.0, 0.07 * ia))
		for i in 8:
			var a2 := -_time * 1.8 + TAU * float(i) / 8.0
			var gl: Color = Game.COLOR_GLOW[i % 4]
			draw_circle(Vector2.RIGHT.rotated(a2) * rr, 3.4,
				Color(gl.r, gl.g, gl.b, 0.8 * ia))

	# 光子盾甲：护盾环
	if c == Game.WHITE and shield > 0:
		var sr := float(shield) / float(SHIELD_MAX)
		draw_arc(Vector2.ZERO, 30.0, -PI * 0.5, -PI * 0.5 + TAU * sr, 40,
			Color(1.0, 1.0, 1.0, 0.85), 4.0, true)
		draw_circle(Vector2.ZERO, 30.0, Color(0.95, 0.98, 1.0, 0.06))

	# 绕身光刃
	for i in 3:
		var a := _time * 2.2 + TAU * float(i) / 3.0
		var p := Vector2.RIGHT.rotated(a) * 34.0
		var sq := PackedVector2Array([
			Vector2(7.0, 0.0), Vector2(0.0, -2.2), Vector2(-7.0, 0.0), Vector2(0.0, 2.2)
		])
		var tr := Transform2D(a + PI * 0.5, p)
		draw_set_transform_matrix(tr)
		draw_colored_polygon(sq, Color(m.r, m.g, m.b, 0.75))
		draw_set_transform_matrix(Transform2D.IDENTITY)

	# 前置光刃：电浆剑甲基准双排；叠了刃影模块之后按实际排数显示
	# （引力束甲出的是引力束不是光刃，不画）
	if c != Game.YELLOW and (c == Game.RED or multi > 0):
		var n := rows()
		var fgap := minf(34.0, 100.0 / maxf(1.0, float(n - 1)))
		for i in n:
			var oy := (float(i) - (float(n) - 1.0) * 0.5) * fgap
			var sq := PackedVector2Array([
				Vector2(14.0, oy), Vector2(-4.0, oy - 3.0),
				Vector2(-8.0, oy), Vector2(-4.0, oy + 3.0)
			])
			draw_colored_polygon(sq, Color(m.r, m.g, m.b, 0.9))

	# 引力束甲：绕身引力符
	if c == Game.YELLOW:
		for i in 3:
			var a := _time * 1.6 + TAU * float(i) / 3.0
			var p := Vector2.RIGHT.rotated(a) * 30.0
			var q := PackedVector2Array([
				Vector2(5.0, 0.0), Vector2(0.0, -5.0),
				Vector2(-5.0, 0.0), Vector2(0.0, 5.0)
			])
			draw_set_transform_matrix(Transform2D(a, p))
			draw_colored_polygon(q, Color(k.r, k.g, k.b, 0.55))
			draw_set_transform_matrix(Transform2D.IDENTITY)

	# 引力束甲：过热环（满环即滞）
	if c == Game.YELLOW and heat > 0.0:
		var hr := clampf(heat / HEAT_MAX, 0.0, 1.0)
		var hc := Color(1.0, 0.35, 0.20) if overheated else Color(1.0, 0.78, 0.20)
		draw_arc(Vector2.ZERO, 38.0, -PI * 0.5, -PI * 0.5 + TAU * hr, 40,
			Color(hc.r, hc.g, hc.b, 0.9), 4.0, true)

	# 能量尾带
	var rb := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		rb.append(Vector2(-18.0 - t * 34.0, sin(_time * 6.0 - t * 4.0) * 7.0 * t))
	draw_polyline(rb, Color(m.r, m.g, m.b, 0.55), 3.0, true)

	# 战甲本体（人形机甲 · 机身主装甲，侧视前倾；几何沿用已验证骨架）
	var body := PackedVector2Array([
		Vector2(20.0, 0.0), Vector2(6.0, -11.0), Vector2(-14.0, -9.0),
		Vector2(-20.0, 0.0), Vector2(-14.0, 9.0), Vector2(6.0, 11.0)
	])
	draw_colored_polygon(body, dk)
	var ring := PackedVector2Array(body)
	ring.append(body[0])
	draw_polyline(ring, m, 2.0, true)
	# 头 / 头部装甲壳：DARK 壳 + CANOPY 驾驶舱玻璃（敌我识别主通道，朝 +X 前方）
	# + 前向传感器探针（侧视关键，删了头就是个圆）+ CORE 座舱内照明高光
	draw_circle(Vector2(11.0, -1.0), 6.0, dk)
	draw_arc(Vector2(11.0, -1.0), 6.0, 0.0, TAU, 16, m, 1.6, true)
	# 驾驶舱玻璃（CANOPY）：前向倾斜的椭圆，读作「座舱」而非「子弹」
	var canopy := PackedVector2Array([
		Vector2(16.0, -3.4), Vector2(12.0, -4.4), Vector2(9.0, 1.6), Vector2(13.0, 4.4)
	])
	draw_colored_polygon(canopy, Game.CANOPY)
	draw_polyline(PackedVector2Array([canopy[0], canopy[1], canopy[2], canopy[3], canopy[0]]),
		Color(1.0, 1.0, 1.0, 0.55), 1.2, true)
	# 座舱内照明高光（CORE）：提升 CANOPY 明度跳脱度，帮玩家在弹幕里一眼看到「友军脸」
	draw_circle(Vector2(12.6, -0.6), 1.5, k)
	# 前向传感器探针（NOSE）：头部装甲壳前缘的 1px 凸起
	draw_circle(Vector2(17.0, -1.0), 1.2, m)

	# 判定点
	draw_circle(Vector2.ZERO, HIT_R, Color(m.r, m.g, m.b, 0.13))
	draw_circle(Vector2.ZERO, 3.2, Color(1.0, 1.0, 1.0, 0.95))

	# 寒霜疾甲 · 闪避：一圈向外推的相位残影环。
	# 与「同色吸收」那圈由外向内**收拢**的光环方向相反、颜色更亮 —— 玩家据此区分
	# 「我只是吸了一发」和「我现在 0.5 秒内打不中」。
	if _dodge > 0.0:
		var ph := 1.0 - _dodge / DODGE_TIME          # 0（刚触发）-> 1（即将结束）
		var pr := 20.0 + ph * 26.0
		# 下限 0.35 是刻意的，别当冗余 maxf 删掉：闪避最后约 10%（剩余 ~0.05 秒）时，
		# 衰减公式 0.80*(1-ph) 已降到约 0.08，残影环几乎不可见；而此刻机身仍是约 0.29
		# 的半透明鬼影、且马上要恢复受击 —— 正是玩家最隐形、又最需要定位锚的窗口。
		# 不留这个下限，环会在最该被看见时彻底消失，叠上亮色弹幕时最难辨认自己。
		var pa := maxf(0.35, 0.80 * (1.0 - ph))
		draw_arc(Vector2.ZERO, pr, 0.0, TAU, 32, Color(g.r, g.g, g.b, pa), 3.0, true)
		draw_arc(Vector2.ZERO, pr * 0.72, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, pa * 0.5), 2.0, true)

	# 免疫闪环
	if _immune > 0.0:
		var a := _immune / 0.22
		draw_arc(Vector2.ZERO, 16.0 + (1.0 - a) * 20.0, 0.0, TAU, 28,
			Color(g.r, g.g, g.b, a), 3.0, true)
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, 30.0, Color(1.0, 0.4, 0.4, _flash * 0.5))
