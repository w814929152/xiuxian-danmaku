class_name Enemy
extends Damageable
## 星盗喽啰
## 外形与弹幕颜色一致：电浆星盗(红) · 寒霜星盗(蓝) · 光子星盗(白) · 引力星盗(黄)

signal killed(pos: Vector2, c: int, sc: int)

var color: int = Game.RED
var hp := 30
var max_hp := 30
var speed := 130.0
var pattern := "sine"
var fire_cd := 1.5
var score := 100
## 由 Level 显式注入：弹幕与特效的挂载容器
var world: Node2D = null
var player_ref: Player = null

var _t := 0.0
var _fire := 0.0
var _base_y := 360.0
var _amp := 70.0
var _freq := 0.55
var _home_x := 940.0
var _life := 16.0
var _entered := false
var _leaving := false
var _flash := 0.0
var dead := false
## 呼吸 / 尾抖的实例随机相位（YokaiArt 动画用）
var _phase := randf() * TAU


func setup(c: int, pat: String, y: float, hp_scale: float = 1.0) -> void:
	color = c
	pattern = pat
	position = Vector2(Game.VIEW_W + 70.0, y)
	_base_y = y
	# 按颜色做差异化
	match c:
		Game.RED:
			hp = int(26 * hp_scale)
			fire_cd = 1.45
			speed = 120.0
		Game.BLUE:
			hp = int(34 * hp_scale)
			fire_cd = 1.25
			speed = 165.0
		Game.YELLOW:
			hp = int(30 * hp_scale)
			fire_cd = 1.6
			speed = 140.0
		_:
			hp = int(42 * hp_scale)
			fire_cd = 1.9
			speed = 95.0
	max_hp = hp
	# 难度越低，星盗出手越慢（弹幕整体更稀疏）
	fire_cd *= 2.0 - Game.bullet_scale()
	_fire = 0.7 + randf() * 0.8


func _ready() -> void:
	collision_layer = 4   # bit2 敌人
	collision_mask = 2    # bit1 玩家子弹
	z_index = 10
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 19.0
	cs.shape = sh
	add_child(cs)


func _process(delta: float) -> void:
	if dead:
		return
	_t += delta
	_life -= delta
	_flash = maxf(0.0, _flash - delta)
	_motion(delta)
	_firing(delta)
	# 出界回收：多数星盗向左飞出左边界；hover 骚扰敌离场时是向右飞出右边界的，
	# 必须一并回收，否则它永远等不到 free，把 Level 的清场判定一直拖到上限。
	# 只认 _leaving（hover 独有的离场态），避免误删还在逼近 x≈940 的目标色。
	var out_right := _leaving and position.x > Game.VIEW_W + 90.0
	if position.x < -90.0 or out_right or position.y < -140.0 or position.y > Game.VIEW_H + 140.0:
		queue_free()
	queue_redraw()


func _motion(delta: float) -> void:
	match pattern:
		"straight":
			position.x -= speed * delta
		"sine":
			position.x -= speed * delta
			position.y = _base_y + sin(_t * _freq * TAU) * _amp
		"hover":
			if not _leaving:
				position.x = move_toward(position.x, _home_x, speed * 1.6 * delta)
				position.y = _base_y + sin(_t * 0.9) * 26.0
				if _life < 4.0:
					_leaving = true
			else:
				position.x += speed * 2.4 * delta
		"dive":
			if _t < 1.1 and player_ref != null and is_instance_valid(player_ref):
				position.y = move_toward(position.y, player_ref.position.y, 210.0 * delta)
			position.x -= speed * 1.35 * delta
	if position.x < Game.VIEW_W - 30.0:
		_entered = true


func _firing(_delta: float) -> void:
	if not _entered or _leaving:
		return
	_fire -= _delta
	if _fire > 0.0:
		return
	_fire = fire_cd * (0.8 + randf() * 0.5)
	_shoot()


func _aim() -> Vector2:
	if player_ref != null and is_instance_valid(player_ref):
		return (player_ref.position - position).normalized()
	return Vector2.LEFT


func _shoot() -> void:
	match color:
		Game.RED:
			# 电浆星盗：三连扇形
			var a := _aim().angle()
			for i in 3:
				_shot(color, Vector2.RIGHT.rotated(a + (i - 1) * 0.22), 265.0, 9.0, 10)
		Game.BLUE:
			# 寒霜星盗：精准点射
			_shot(color, _aim(), 340.0, 8.0, 10)
			_shot(color, _aim().rotated(0.05), 320.0, 8.0, 10)
		Game.YELLOW:
			# 引力星盗：能量弹三连（宽散射，慢而密）
			var ay := _aim().angle()
			for i in 3:
				_shot(color, Vector2.RIGHT.rotated(ay + (i - 1) * 0.40), 235.0, 10.0, 10)
		_:
			# 光子星盗：五向能量环
			for i in 5:
				_shot(color, Vector2.RIGHT.rotated(PI + (i - 2) * 0.34), 200.0, 10.0, 10)


func _shot(c: int, dirv: Vector2, sp: float, r: float, dmg: int) -> void:
	if world == null:
		return
	var dir := dirv.normalized()
	Danmaku.spawn(world, c, position + dir * 20.0, dir * sp, dmg, r)


func hit(dmg: int, c: int) -> void:
	if dead:
		return
	# 同源共振：同色光刃伤害 +50%
	var real := int(dmg * (1.5 if c == color else 1.0))
	hp -= real
	_flash = 0.09
	Fx.pop(self, Vector2(0.0, -26.0), str(real),
		Color(1.0, 0.85, 0.5) if c == color else Color(1.0, 1.0, 1.0), 15)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	Fx.burst(world, position, Game.COLOR_GLOW[color], 16, 300.0, 0.6)
	Fx.ring(world, position, Game.COLOR_MAIN[color], 6.0, 54.0, 0.4, 5.0)
	killed.emit(position, color, score)
	queue_free()


func _draw() -> void:
	# 异形星盗：四色四母题矢量绘制（YokaiArt，星盗/战将共用同一剪影家族）。
	# 层序 ①~⑧ 在 YokaiArt 内完成，这里只续画其后的覆盖层。
	YokaiArt.draw_minion(self, color, _t, _phase)
	# 受击白闪（层序 ⑨，最后覆盖）
	if _flash > 0.0:
		draw_circle(Vector2.ZERO, 26.0, Color(1.0, 1.0, 1.0, _flash * 2.5))
