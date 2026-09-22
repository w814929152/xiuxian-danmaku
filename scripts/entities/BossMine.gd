class_name BossMine
extends Damageable
## ---------------------------------------------------------------
## 引力雷 —— L5 终焉号相④「mine_toss」投出的静态雷
##
## 用法：Boss._cast_step() 的 "mine_toss" 分支调 BossMine.spawn()，
## 雷落地后静止不动，**8 秒自毁**；被光刃打中则提前引爆（玩家可以主动清雷，
## 这正是「空间管理」的设计意图 —— 不清就把走位空间一点点吃掉）。
##
## 走对象池（Pool）：雷在一场里可能投出十几个，且天然「可被 setup() 完整重置」。
## 碰撞层 bit2 敌人（与星盗同层，光刃打得到）；**mask = 0** —— 它自己不检测任何东西，
## 伤害玩家走「引爆时按半径判定」，避免给它再开一条碰撞通路。
## ---------------------------------------------------------------

const POOL_KEY := "boss_mine"

const R := 16.0            # 碰撞半径 / 器形半径
const LIFE := 8.0          # 存在时长：8s 自毁（设计 §D L5 相④）
const ARM := 0.55          # 布设后的保险期，这段时间不判定玩家（防贴脸瞬爆）
const BLAST_R := 150.0     # 引爆半径
const DMG := 12            # 引爆伤害
const FADE := 1.2          # 最后这么多秒开始闪烁预警

## 由 Boss 显式注入：特效挂载容器 + 玩家引用（引爆判定用）
var world: Node2D = null
var player_ref: Player = null
var color: int = Game.YELLOW

var _t := 0.0
var _alive := false
var _flash := 0.0


static func _make() -> BossMine:
	return BossMine.new()


## 唯一生成入口。雷是 Boss 自己扔的，不走 EnemyKind / Spawner。
static func spawn(parent: Node2D, c: int, pos: Vector2, player: Player) -> BossMine:
	if parent == null or not is_instance_valid(parent):
		return null
	var m := Pool.acquire(POOL_KEY, parent, BossMine._make) as BossMine
	if m == null:
		return null
	m.world = parent
	m.setup(c, pos, player)
	return m


## 覆盖**全部**可变状态 —— 池化复用的铁律，漏一个就是幽灵雷
func setup(c: int, pos: Vector2, player: Player) -> void:
	color = c
	player_ref = player
	position = pos
	_t = 0.0
	_alive = true
	_flash = 0.0
	set_process(true)
	visible = true
	queue_redraw()


func _ready() -> void:
	collision_layer = 4   # bit2: 敌人（光刃打得到）
	collision_mask = 0    # 自己不检测任何东西，伤害走引爆半径判定
	z_index = 12
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = R
	cs.shape = sh
	add_child(cs)


func _process(delta: float) -> void:
	if not _alive:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if _t >= LIFE:
		_boom()
		return
	queue_redraw()


## 光刃打中 -> 提前引爆（玩家主动清雷的通路）
func hit(_dmg: int, _c: int) -> void:
	if not _alive:
		return
	_flash = 0.09
	_boom()


func _boom() -> void:
	if not _alive:
		return
	_alive = false
	set_process(false)
	visible = false
	if world != null and is_instance_valid(world):
		Fx.burst(world, position, Game.COLOR_GLOW[color], 16, 340.0, 0.65)
		Fx.ring(world, position, Game.COLOR_MAIN[color], 10.0, BLAST_R, 0.35, 7.0)
		Fx.shock(world, position, Game.COLOR_CORE[color], BLAST_R, 0.5)
	# 半径内判定玩家（ARM 之前不判，防刚落地就贴脸瞬爆）
	if _t >= ARM and player_ref != null and is_instance_valid(player_ref):
		if player_ref.position.distance_to(position) <= BLAST_R + R:
			player_ref.take_hit(color, DMG)
	_kill()


## 归还对象池（不 queue_free）。
## 摘除必须延后：Area2D 是 CollisionObject，Godot 禁止在物理回调里直接
## remove_child（Danmaku._kill 就是这条规矩的先例）—— 先置死，帧末再摘。
func _kill() -> void:
	_detach.call_deferred()


func _detach() -> void:
	Pool.release(POOL_KEY, self)


# ------------------------------------------------------------ 绘制（全矢量）
func _draw() -> void:
	if not _alive:
		return
	var m: Color = Game.COLOR_MAIN[color]
	var g: Color = Game.COLOR_GLOW[color]
	var k: Color = Game.COLOR_CORE[color]
	var dk: Color = Game.COLOR_DARK[color]
	# 引信：最后 FADE 秒开始快闪，越接近自毁闪得越急（读得出来，不靠背板）
	var left := LIFE - _t
	var blink := 1.0
	if left < FADE:
		blink = 0.45 + 0.55 * absf(sin(_t * (6.0 + 14.0 * (1.0 - left / FADE))))
	# ① 外圈引力场（越接近引爆越亮）
	draw_circle(Vector2.ZERO, R + 9.0, Color(g.r, g.g, g.b, 0.10 * blink))
	draw_arc(Vector2.ZERO, R + 6.0, 0.0, TAU, 24,
		Color(g.r, g.g, g.b, 0.35 * blink), 2.0, true)
	# ② 壳体（八边，机械雷）
	var shell := PackedVector2Array()
	for i in 8:
		shell.append(Vector2.RIGHT.rotated(TAU * float(i) / 8.0) * R)
	draw_colored_polygon(shell, dk)
	# ③ 核心（MAIN 底 + CORE 亮核，随引信脉动）
	draw_circle(Vector2.ZERO, R * 0.62, m)
	draw_circle(Vector2.ZERO, R * 0.34, Color(k.r, k.g, k.b, blink))
	# ④ 四向尖刺（读作「别踩」）
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var p0 := Vector2.RIGHT.rotated(a) * (R - 2.0)
		var p1 := Vector2.RIGHT.rotated(a) * (R + 11.0)
		draw_line(p0, p1, Color(m.r, m.g, m.b, 0.9), 3.0, true)
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, R + 4.0, Color(1.0, 1.0, 1.0, _flash * 2.0))
