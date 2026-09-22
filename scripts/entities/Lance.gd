class_name Lance
extends Area2D
## 电浆剑甲的贯穿激光（一次性）
##
## 能量攒满（PlayerCfg.CHARGE_MAX）即由 Player 自动打出：一道自玩家身前
## 横贯到屏幕右缘的光柱，对光柱上压着的**所有** Damageable 各结算一次伤害
## （贯穿，不因命中第一个目标而消失），随后播放短促的收束视觉再归还对象池。
##
## ⚠️ 结算时机的坑：`get_overlapping_areas()` 读的是**上一次物理步进**的结果，
##    生成当帧查必然是空的 —— 所以必须等一次完整步进（见 _physics_process 的
##    _frames_alive >= 2）。只等 1 帧的话，从弹幕碰撞回调里生成的光柱会打空。
##
## 走 Pool 对象池 —— 与 Sword / Danmaku 同制式，**不做 queue_free**。

const POOL_KEY := "lance"
## 结算前要等几个物理帧：1 帧 = 生成当帧（重叠表还没算），2 帧 = 步进后第一帧
const STRIKE_DELAY_FRAMES := 2

var color: int = Game.RED
var damage := 24
## 由生成方（Player）注入：命中特效的挂载容器
var world: Node2D = null
var life := 0.25
var _t := 0.0
var _alive := false
var _struck := false
var _frames_alive := 0
var _len := 60.0
var _shape: RectangleShape2D = null


static func _make() -> Node:
	return Lance.new()


## 唯一生成入口：p 是玩家位置，光柱自该处一直探到屏幕右缘
static func spawn(parent: Node2D, c: int, p: Vector2, d: int) -> Lance:
	var s := Pool.acquire(POOL_KEY, parent, Lance._make) as Lance
	if s == null:
		return null
	s.world = parent
	s._alive = true
	s.setup(c, p, d)
	return s


func _ready() -> void:
	collision_layer = 2   # bit1: 玩家子弹
	collision_mask = 4    # bit2: 敌人
	# 压在玩家（z=12）之下：光口那一端的光晕不会糊住机体，玩家始终看得见自己
	z_index = 11
	var cs := CollisionShape2D.new()
	_shape = RectangleShape2D.new()
	_shape.size = Vector2(60.0, PlayerCfg.LANCE_HALF_H * 2.0)
	cs.shape = _shape
	add_child(cs)
	visible = false


## 池化复用：必须覆盖上一次留下的全部状态（含碰撞体尺寸 —— _len 随玩家位置变）
func setup(c: int, p: Vector2, d: int) -> void:
	color = c
	damage = d
	_t = 0.0
	_struck = false
	_frames_alive = 0
	life = PlayerCfg.LANCE_LIFE
	_len = maxf(60.0, Game.VIEW_W + 40.0 - p.x)
	if _shape != null:
		_shape.size = Vector2(_len, PlayerCfg.LANCE_HALF_H * 2.0)
	position = Vector2(p.x + _len * 0.5, p.y)
	modulate = Color.WHITE
	visible = true
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	# 等一次完整的物理步进再结算（理由见文件头）：
	# 此刻 get_overlapping_areas() 才是准的，能一次命中光柱上压着的所有目标。
	_frames_alive += 1
	if not _struck and _frames_alive >= STRIKE_DELAY_FRAMES:
		_struck = true
		_strike()
	_t += delta
	if _t >= life:
		_kill()
	queue_redraw()


## 贯穿：一帧内打光柱上的所有目标，不因命中而中断
func _strike() -> void:
	for a in get_overlapping_areas():
		if not (a is Damageable):
			continue
		var d := a as Damageable
		if not is_instance_valid(d) or d.is_queued_for_deletion():
			continue
		d.hit(damage, color)
		if world != null:
			Fx.burst(world, d.global_position, Game.COLOR_GLOW[color], 6, 150.0, 0.3)


## 归还对象池（不 queue_free）
## 同 Danmaku / Sword：Area2D 不能在物理回调里直接摘除，延后到帧末。
func _kill() -> void:
	if not _alive:
		return
	_alive = false
	visible = false
	_detach.call_deferred()


func _detach() -> void:
	Pool.release(POOL_KEY, self)


func _draw() -> void:
	var g: Color = Game.COLOR_GLOW[color]
	var m: Color = Game.COLOR_MAIN[color]
	var k: Color = Game.COLOR_CORE[color]
	var half := _len * 0.5
	# 由生到灭收束：宽度与透明度一起衰减，读作「一闪而过的贯穿」
	var fade := clampf(1.0 - _t / life, 0.0, 1.0)
	var w := 1.0 + 0.6 * fade
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(g.r, g.g, g.b, 0.16 * fade), 52.0 * w, true)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(g.r, g.g, g.b, 0.32 * fade), 28.0 * w, true)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(m.r, m.g, m.b, 0.85 * fade), 13.0 * w, true)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(k.r, k.g, k.b, fade), 5.0 * w, true)
	# 光口（贴着玩家那一端）
	draw_circle(Vector2(-half, 0.0), (20.0 + 6.0 * fade) * w,
		Color(g.r, g.g, g.b, 0.28 * fade))
	draw_circle(Vector2(-half, 0.0), 6.0 * w, Color(k.r, k.g, k.b, fade))
