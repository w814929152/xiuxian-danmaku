class_name Elite
extends Damageable
## 护法妖将 —— 第 2 / 第 3 重妖潮的压轴精英怪
##
## 核心是【属性法罡】，可以理解为「会走位的老祖法罩」：
##   · 法罡存续时：同色飞剑全额（并享同源共振 +50%），异色只剩 WARD_RESIST；
##     **法罡不破，本体一点血都不掉** —— 不换袍就只能在罡上刮痧。
##   · 法罡色只从玩家已选的两件道袍中抽取（同老祖的法罩）。
##     这不是为了复刻机制，而是**可行性要求**：凭空给个玩家没带的颜色，
##     破罡就成了死局 —— 那不是难度，是设计事故。
##   · 打破一层 -> 虚弱期（BROKEN_TIME）：移速减半、出手放慢、本体任意颜色全额。
##   · 虚弱结束会重铸法罡，但 WARD_LAYERS 有限（用完即永久破防）。
##     无限重铸的话，「打不死」的挫败感会盖过「换袍破罡」的爽点。
## 击杀必掉一件道具（见 Level._on_elite_killed）。
##
## 外观：四色妖将 sprite（朝左直立人形，tools/build_enemies.py 烘焙）
## + 矢量法罡环 + 头顶双条（法罡 / 本体）。
## 不走对象池 —— 一局只有两只，多一层 reset 不值。

signal killed(pos: Vector2, c: int, sc: int)

## 本体元神（× hp_scale）
const BASE_HP := 480
## 单层法罡值（× hp_scale）
const WARD_HP := 150
## 法罡总层数：破一层虚弱一次，可重铸次数 = 层数 - 1
const WARD_LAYERS := 2
## 法罡存续时，异色飞剑只剩这个比例（老祖法罩是 0.60，这里更狠 —— 逼你换袍）
const WARD_RESIST := 0.35
## 破罡后的虚弱期（秒）
const BROKEN_TIME := 4.5
## 巡游速度
const SPEED := 150.0
## 基础出手间隔（还会再按弹幕密度放慢）
const FIRE_CD := 1.05
## 斩杀奖励
const SCORE := 800
## 碰撞半径（妖将 sprite 原生 84x84，圆只罩躯干核心，角与兵器在圆外属造型）
const R := 34.0

var color: int = Game.RED
var hp := 0
var max_hp := 0
## 当前法罡值 / 单层法罡上限
var ward := 0
var ward_max := 0
## 剩余可重铸层数
var layers := WARD_LAYERS
## 虚弱期剩余秒数（> 0 即处于法罡已破的虚弱状态）
var broken := 0.0
var score := SCORE
var dead := false
## 由 Level 显式注入：弹幕与特效的挂载容器
var world: Node2D = null
var player_ref: Player = null
## 法罡色只从这里抽（玩家的已选道袍）
var player_robes: Array[int] = []

var _t := 0.0
var _fire := 0.0
var _flash := 0.0
var _base_y := 360.0
var _home_x := 940.0
var _entered := false
## 像素 sprite（四色妖将由 ArtAssets 按法罡色切换，原生 84x84 不放大）
var _art: Sprite2D = null


## [param hp_scale] 波次强度系数；[param y] 巡游基准高度
func setup(hp_scale: float = 1.0, y: float = 360.0) -> void:
	max_hp = int(float(BASE_HP) * hp_scale)
	hp = max_hp
	ward_max = int(float(WARD_HP) * hp_scale)
	ward = ward_max
	layers = WARD_LAYERS
	broken = 0.0
	_base_y = y
	position = Vector2(Game.VIEW_W + 90.0, y)
	# 法罡色：只从玩家携带的道袍中抽 —— 保证一定破得了
	if player_robes.is_empty():
		color = randi() % 4
	else:
		color = player_robes[randi() % player_robes.size()]
	_fire = 1.2
	if _art != null:
		_art.texture = ArtAssets.by_color("elite", color)


func _ready() -> void:
	collision_layer = 4   # bit2 敌人
	collision_mask = 2    # bit1 玩家子弹
	z_index = 10
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = R
	cs.shape = sh
	add_child(cs)
	_art = ArtAssets.make_sprite("")
	add_child(_art)
	# 84x84 sprite 已按妖将原生尺寸烘焙（R=34 < 84/2，角与兵器在碰撞圆外属造型），
	# 不再做节点级放大 —— 旧的小妖图 x1.79 会把 2px 元素糊成 4px 块。


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
		position.x = move_toward(position.x, _home_x, SPEED * slow * delta)
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
	# 与小妖同一条规则：难度越低，出手越慢
	var cd := FIRE_CD * (2.0 - Game.bullet_scale())
	if broken > 0.0:
		cd *= 1.8
	_fire = cd * (0.85 + randf() * 0.3)
	_shoot()


func _aim() -> Vector2:
	if player_ref != null and is_instance_valid(player_ref):
		return (player_ref.position - position).normalized()
	return Vector2.LEFT


func _shoot() -> void:
	var a := _aim().angle()
	if broken > 0.0:
		# 虚弱：零星三连，给玩家一个喘息窗口
		for i in 3:
			_shot(color, Vector2.RIGHT.rotated(a + (i - 1) * 0.32), 195.0, 9.0, 10)
		return
	match color:
		Game.RED:
			# 炎将：七向扇射
			for i in 7:
				_shot(color, Vector2.RIGHT.rotated(a + (i - 3) * 0.19), 270.0, 9.0, 10)
		Game.BLUE:
			# 冰将：五连速射
			for i in 5:
				_shot(color, Vector2.RIGHT.rotated(a + (i - 2) * 0.06), 365.0, 8.0, 10)
		Game.YELLOW:
			# 土将：慢速宽散射符牌
			for i in 3:
				_shot(color, Vector2.RIGHT.rotated(a + (i - 1) * 0.44), 230.0, 10.0, 10)
		_:
			# 清灵将：十四向灵环（缓慢自转）
			for i in 14:
				_shot(color, Vector2.RIGHT.rotated(_t * 0.6 + TAU * float(i) / 14.0),
					205.0, 10.0, 10)


func _shot(c: int, dirv: Vector2, sp: float, r: float, dmg: int) -> void:
	if world == null:
		return
	var dir := dirv.normalized()
	Danmaku.spawn(world, c, position + dir * (R + 6.0), dir * sp, dmg, r)


# ---------------------------------------------------------------- 受击
func hit(dmg: int, c: int) -> void:
	if dead:
		return
	var same := (c == color)
	# 法罡未破 -> 异色刮痧；法罡已破 -> 任意颜色全额（同色另有共振 +50%）
	var mul := 1.5 if same else (WARD_RESIST if ward > 0 else 1.0)
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


## 飘字挂在 world 而不是自己身上：
## 自己被 queue_free 时，挂在身上的池化 Fx 会跟着被 free，
## 池里却还留着它的引用 —— 下次取出来就是一个已释放对象。
func _pop(v: int, col: Color, size: int) -> void:
	var host := world if (world != null and is_instance_valid(world)) else self
	Fx.pop(host, position + Vector2(0.0, -44.0), str(v), col, size)


func _break_ward() -> void:
	broken = BROKEN_TIME
	layers -= 1
	Fx.ring(world, position, Game.COLOR_MAIN[color], R, 130.0, 0.5, 6.0)
	Fx.burst(world, position, Game.COLOR_GLOW[color], 22, 320.0, 0.7)
	Fx.pop(world, position + Vector2(0.0, -70.0), "法 罡 破",
		Color(1.0, 0.92, 0.55), 21, 1.1)


## 虚弱期结束：还有余层就重铸，否则永久破防
func _recast() -> void:
	if layers <= 0:
		return
	ward = ward_max
	Fx.ring(world, position, Game.COLOR_MAIN[color], 140.0, R + 10.0, 0.45, 5.0)
	Fx.pop(world, position + Vector2(0.0, -70.0), "法罡重铸",
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

	# 本命气息
	draw_circle(Vector2.ZERO, R + 16.0 + 6.0 * pulse, Color(g.r, g.g, g.b, 0.10))

	if ward > 0:
		# 法罡：双层弧 + 八枚游走符点，透明度随剩余值衰减
		var wr := clampf(float(ward) / float(maxi(1, ward_max)), 0.0, 1.0)
		var a := (0.45 + 0.35 * pulse) * (0.45 + 0.55 * wr)
		draw_circle(Vector2.ZERO, R + 12.0, Color(m.r, m.g, m.b, 0.10 * wr + 0.03))
		draw_arc(Vector2.ZERO, R + 12.0, 0.0, TAU, 48, Color(m.r, m.g, m.b, a), 6.0, true)
		draw_arc(Vector2.ZERO, R + 4.0, 0.0, TAU, 48, Color(k.r, k.g, k.b, a * 0.5),
			2.5, true)
		for i in 8:
			var ang := _t * 1.1 + TAU * float(i) / 8.0
			var p := Vector2.RIGHT.rotated(ang) * (R + 12.0)
			draw_circle(p, 3.6, Color(k.r, k.g, k.b, a))
	else:
		# 法罡已破：一圈黯淡的裂环 —— 一眼看出「现在能打疼它」
		for i in 6:
			var a0 := _t * 0.4 + TAU * float(i) / 6.0
			draw_arc(Vector2.ZERO, R + 8.0, a0, a0 + 0.34, 12,
				Color(0.78, 0.82, 0.95, 0.5), 3.5, true)

	if _flash > 0.0:
		draw_circle(Vector2.ZERO, R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.4))
	_bars()


## 头顶双条：上条法罡、下条本体，外加一行身份
func _bars() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	if ward_max > 0:
		var wr := clampf(float(ward) / float(ward_max), 0.0, 1.0)
		_bar(-48.0, -84.0, 96.0, 6.0, wr, Color(m.r, m.g, m.b, 0.95))
	var hr := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	_bar(-48.0, -75.0, 96.0, 7.0, hr, Color(1.0, 0.34, 0.36))
	DrawUtil.txt(self, "护法妖将 · %s" % Game.COLOR_CN[color], Vector2(0.0, -92.0),
		15, m, HORIZONTAL_ALIGNMENT_CENTER)


func _bar(x: float, y: float, w: float, h: float, ratio: float, col: Color) -> void:
	draw_rect(Rect2(x - 1.0, y - 1.0, w + 2.0, h + 2.0), Color(0.02, 0.02, 0.05, 0.55))
	draw_rect(Rect2(x, y, w, h), Color(0.05, 0.05, 0.10, 0.60))
	draw_rect(Rect2(x, y, maxf(0.0, w) * clampf(ratio, 0.0, 1.0), h), col)
