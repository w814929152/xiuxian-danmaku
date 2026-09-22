class_name Beam
extends Area2D
## 引力束甲的持续引力束
##
## 常驻挂在 Player 身上（作为子节点随玩家移动），开火时开启、过热时关闭，
## 不做对象池 —— 全程只有这一道。
## 伤害按 tick 结算给所有压在光柱上的 Damageable，所以是「持续输出」而非弹丸。

## 结算间隔 / 光柱半高取自 PlayerCfg。

var color: int = Game.YELLOW
var dps := 120.0
## 由 Player 注入：命中特效的挂载容器
var world: Node2D = null
## 粗细系数：增幅核心层数越多，光柱越粗（碰撞体同步加宽，不只是好看）
var width_mul: float = 1.0
## 多道光束并排时各自的竖直偏移（由 Player 计算后传入）
var y_off: float = 0.0
var on := false
var length := 60.0
var _t := 0.0
var _acc := 0.0
var _shape: RectangleShape2D = null


func _ready() -> void:
	collision_layer = 2   # bit1: 玩家子弹
	collision_mask = 4    # bit2: 敌人
	z_as_relative = false
	z_index = 20
	var cs := CollisionShape2D.new()
	_shape = RectangleShape2D.new()
	_shape.size = Vector2(60.0, PlayerCfg.BEAM_HALF_H * 2.0)
	cs.shape = _shape
	add_child(cs)
	turn_off()


func turn_on() -> void:
	on = true
	visible = true
	monitoring = true
	set_physics_process(true)
	_acc = 0.0


func turn_off() -> void:
	on = false
	visible = false
	monitoring = false
	set_physics_process(false)


## 由 Player 每帧调用：光柱自玩家身前一直探到屏幕右缘。
## y_off 用于把叠出来的多道引力束沿竖直方向铺开。
func aim(player_x: float, y: float = 0.0) -> void:
	y_off = y
	length = maxf(60.0, Game.VIEW_W + 20.0 - player_x)
	if _shape != null:
		_shape.size = Vector2(length, PlayerCfg.BEAM_HALF_H * 2.0 * width_mul)
	position = Vector2(length * 0.5, y_off)


func _physics_process(delta: float) -> void:
	if not on:
		return
	_t += delta
	_acc += delta
	while _acc >= PlayerCfg.BEAM_TICK:
		_acc -= PlayerCfg.BEAM_TICK
		_tick()
	queue_redraw()


func _tick() -> void:
	var dmg := maxi(1, roundi(dps * PlayerCfg.BEAM_TICK))
	var found := false
	var hit_local := Vector2.ZERO
	for a in get_overlapping_areas():
		if not (a is Damageable):
			continue
		var d := a as Damageable
		if not is_instance_valid(d) or d.is_queued_for_deletion():
			continue
		d.hit(dmg, color)
		if not found:
			found = true
			hit_local = to_local(d.global_position)
	if found and world != null:
		Fx.burst(world, to_global(hit_local), Game.COLOR_GLOW[color], 4, 90.0, 0.2)


func _draw() -> void:
	var m: Color = Game.COLOR_MAIN[color]
	var g: Color = Game.COLOR_GLOW[color]
	var k: Color = Game.COLOR_CORE[color]
	var half := length * 0.5
	var w := width_mul
	var pulse := 0.5 + 0.5 * sin(_t * 18.0)

	# 由外到内四层，越里越亮（粗细随增幅核心放大）
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(g.r, g.g, g.b, 0.12), (26.0 + 4.0 * pulse) * w, true)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(g.r, g.g, g.b, 0.22), 16.0 * w, true)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0),
		Color(m.r, m.g, m.b, 0.75), 8.0 * w, true)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), k, 3.0 * w, true)

	# 顺光游走的符文
	for i in 6:
		var u := fmod(float(i) / 6.0 + _t * 0.5, 1.0)
		draw_circle(Vector2(-half + u * length, 0.0), 2.4 * w,
			Color(k.r, k.g, k.b, 0.7))

	# 光口（贴着玩家）
	draw_circle(Vector2(-half, 0.0), (12.0 + 2.0 * pulse) * w,
		Color(g.r, g.g, g.b, 0.20))
	draw_circle(Vector2(-half, 0.0), 4.5 * w, k)
