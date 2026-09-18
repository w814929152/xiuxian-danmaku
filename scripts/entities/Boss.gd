class_name Boss
extends Damageable
## 关卡 Boss · 血魔老祖
## 会周期性展开【属性法罩】：只有同色飞剑能造成全额伤害，异色衰减
## 法罩颜色只会从玩家选定的两件道袍中抽取 —— 逼迫玩家在战斗中换袍
##
## 三档难度（Game.boss_hp / boss_phases / boss_ward / bullet_scale / off_color_mul）：
##   简单  血 1000 · 两重法相 · 无法罩 · 弹幕 55% · 异色 100%
##   普通  血 2500 · 三重法相 · 无法罩 · 弹幕 80% · 异色 100%
##   困难  血 3600 · 三重法相 · 有法罩 · 弹幕 100% · 异色  60%
## 三档都会在血量降到三成时【狂暴】：周身泛红光，四色螺旋弹幕

signal boss_died()
signal hp_ratio(r: float)
signal phase_chg(p: int)
signal ward_chg(c: int)
## 进入狂暴（血量跌破 ENRAGE_AT）—— 由 Level 接去放横幅
signal enrage_started()

const MAX_HP := 3600        # 困难档血量，也是 max_hp 的默认值
const ENRAGE_AT := 0.30     # 血量降到三成 -> 狂暴
const ENRAGE_TICK := 0.09   # 狂暴螺旋的发射间隔（会再按弹幕密度放慢）

const POOL: Dictionary[int, Array] = {
	1: ["fan_red", "aim_blue", "rain_red"],
	2: ["ring_white", "spiral_rb", "rain_blue", "fan_red", "fan_yellow"],
	3: ["chaos", "spiral_rb", "ring_white", "homing", "rain_yellow"],
}
const DUR: Dictionary[String, float] = {
	"fan_red": 3.2, "aim_blue": 3.0, "rain_red": 3.0, "rain_blue": 3.0,
	"ring_white": 3.4, "spiral_rb": 4.2, "chaos": 4.4, "homing": 3.6,
	"fan_yellow": 3.0, "rain_yellow": 3.2,
}
const TICK: Dictionary[String, float] = {
	"fan_red": 0.60, "aim_blue": 0.55, "rain_red": 0.17, "rain_blue": 0.22,
	"ring_white": 0.80, "spiral_rb": 0.075, "chaos": 0.13, "homing": 0.45,
	"fan_yellow": 0.70, "rain_yellow": 0.20,
}

var hp: int = MAX_HP
## 本局真实血量上限（由难度决定）—— HUD 与阶段判定都用它，不要再用 MAX_HP 常量
var max_hp: int = MAX_HP
var phase := 1
var player_ref: Player = null
var player_robes: Array[int] = []
## 由 Level 显式注入：弹幕与特效的挂载容器
var world: Node2D = null
## 狂暴中：周身泛红光 + 四色螺旋弹幕
var enraged := false

var ward := -1
var _ward_t := 4.0
var _ward_anim := 0.0
## 难度参数在 _ready 里从 Game 取一次，之后不再查全局
var _phases := 3
var _has_ward := true
var _bullet_k := 1.0
var _off_color := 1.0

var _t := 0.0
var _st := "enter"
var _skill := ""
var _cast := 0.0
var _tick := 0.0
var _skill_t := 0.0
var _spiral := 0.0
var _sp4 := 0.0
var _sp4_t := 0.0
var _flash := 0.0
var _base_y := 360.0
var _home_x := 985.0
## 像素 sprite（魔道法相本体；法罩 / 狂暴等动态效果仍在 _draw 里画）
var _art: Sprite2D = null


func _ready() -> void:
	collision_layer = 4   # bit2 敌人
	collision_mask = 2    # bit1 玩家子弹
	z_index = 10
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 56.0
	cs.shape = sh
	add_child(cs)
	_art = ArtAssets.make_sprite("boss")
	add_child(_art)
	position = Vector2(Game.VIEW_W + 220.0, _base_y)
	max_hp = Game.boss_hp()
	hp = max_hp
	_phases = Game.boss_phases()
	_has_ward = Game.boss_ward()
	_bullet_k = Game.bullet_scale()
	_off_color = Game.off_color_mul()


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_ward_anim += delta
	match _st:
		"enter":
			position.x = move_toward(position.x, _home_x, 260.0 * delta)
			position.y = _base_y
			if absf(position.x - _home_x) < 2.0:
				_st = "fight"
				_next_skill()
		"idle":
			# 玩家已陨落：只飘着，不再开火 / 不再展开法罩
			_move(delta)
		"fight":
			_move(delta)
			_ward(delta)
			_attack(delta)
			_check_enrage()
			if enraged:
				_enrage_fire(delta)
	queue_redraw()


## 由 Level 在玩家陨落时调用：收手罢战
func stand_down() -> void:
	if _st == "dying":
		return
	_st = "idle"
	ward = -1
	ward_chg.emit(-1)


func _move(delta: float) -> void:
	var fast := 1.0 if phase < _phases else 1.6
	position.y = _base_y + sin(_t * 0.42 * TAU * fast) * 132.0
	position.x = _home_x + sin(_t * 0.27 * TAU) * 62.0


# ------------------------------------------------------------ 属性法罩
func _ward(delta: float) -> void:
	if not _has_ward:
		return                 # 简单 / 普通：老祖不展法罩
	_ward_t -= delta
	if _ward_t > 0.0:
		return
	if ward >= 0:
		ward = -1
		_ward_t = 3.2 + randf() * 1.6
	else:
		if player_robes.is_empty():
			_ward_t = 3.0
			return
		ward = player_robes[randi() % player_robes.size()]
		_ward_t = 5.2
		_ward_anim = 0.0
		Fx.ring(world, position, Game.COLOR_MAIN[ward], 60.0, 150.0, 0.45, 8.0)
	ward_chg.emit(ward)


# ------------------------------------------------------------ 弹幕编排
func _next_skill() -> void:
	var pool := POOL[phase]
	var pick: String = str(pool[randi() % pool.size()])
	if pool.size() > 1 and pick == _skill:
		pick = pool[(pool.find(pick) + 1) % pool.size()]
	_skill = pick
	_cast = DUR[_skill]
	_tick = 0.25
	_skill_t = 0.0


func _attack(delta: float) -> void:
	_cast -= delta
	_tick -= delta
	if _tick <= 0.0:
		_skill_t += 1.0
		_cast_step()
		# 弹幕密度：系数越小，同一套路的发射间隔越长
		_tick = TICK[_skill] / _bullet_k
	if _cast <= 0.0:
		_next_skill()


## 一次齐射的数量也按密度收缩（至少 1 发，不能归零）
func _n(base: int) -> int:
	return maxi(1, int(roundf(float(base) * _bullet_k)))


# ------------------------------------------------------------ 狂暴
func _check_enrage() -> void:
	if enraged or _st != "fight":
		return
	if float(hp) / float(max_hp) > ENRAGE_AT:
		return
	enraged = true
	_sp4_t = 0.0
	Fx.shock(world, position, Color(1.0, 0.22, 0.18), 660.0, 0.9)
	Fx.ring(world, position, Color(1.0, 0.28, 0.20), 40.0, 400.0, 0.70, 12.0)
	enrage_started.emit()


## 狂暴弹幕：四条旋臂各占一色，同角速度向外卷 —— 「四色螺旋」
func _enrage_fire(delta: float) -> void:
	_sp4_t -= delta
	if _sp4_t > 0.0:
		return
	_sp4_t = ENRAGE_TICK / _bullet_k
	_sp4 += 0.40
	for i in 4:
		_b(i, Vector2.RIGHT.rotated(_sp4 + TAU * float(i) / 4.0), 250.0, 9.0, 10, 0.0)


func _cast_step() -> void:
	match _skill:
		"fan_red":
			_fan(Game.RED, _n(11), 1.15, 255.0, 9.0)
		"aim_blue":
			for i in _n(3):
				_b(Game.BLUE, _aim().rotated((i - 1) * 0.06), 390.0, 8.0, 10, 0.0)
		"rain_red":
			_rain(Game.RED, _n(2), 0.0)
		"rain_blue":
			_rain(Game.BLUE, _n(2), 0.55)
		"fan_yellow":
			_fan(Game.YELLOW, _n(7), 1.00, 225.0, 10.0)
		"rain_yellow":
			_rain(Game.YELLOW, _n(2), 0.35)
		"ring_white":
			_ring(Game.WHITE, _n(24), 215.0, _skill_t * 0.22, 10.0)
		"spiral_rb":
			_spiral += 0.36
			_b(Game.RED, Vector2.RIGHT.rotated(_spiral), 235.0, 9.0, 10, 0.0)
			_b(Game.BLUE, Vector2.RIGHT.rotated(_spiral + PI), 235.0, 9.0, 10, 0.0)
		"chaos":
			for i in _n(3):
				var c: int = randi() % 4
				var a := randf() * TAU
				_b(c, Vector2.RIGHT.rotated(a), 180.0 + randf() * 130.0, 9.0, 10, 0.0)
		"homing":
			var c: int = ward if ward >= 0 else (randi() % 4)
			for i in _n(2):
				_b(c, _aim().rotated((i - 0.5) * 0.8), 205.0, 10.0, 10, 1.05)


## 玩家可能已经阵亡并被 queue_free —— 那时 player_ref 是一个「已释放」对象：
## 读它的属性会崩，把它赋给弹幕的 target 更是直接报
## "Invalid assignment ... with value of type 'previously freed'"。
## 凡是想把玩家引用交出去的地方，一律走这里拿干净的引用。
func _live_player() -> Player:
	if player_ref != null and is_instance_valid(player_ref):
		return player_ref
	return null


func _aim() -> Vector2:
	var p := _live_player()
	if p != null:
		return (p.position - position).normalized()
	return Vector2.LEFT


func _fan(c: int, n: int, spread: float, sp: float, r: float) -> void:
	var base := _aim().angle()
	for i in n:
		var k := 0.0 if n <= 1 else (float(i) / float(n - 1) - 0.5)
		_b(c, Vector2.RIGHT.rotated(base + k * spread), sp, r, 10, 0.0)


func _ring(c: int, n: int, sp: float, off: float, r: float) -> void:
	for i in n:
		_b(c, Vector2.RIGHT.rotated(off + TAU * float(i) / float(n)), sp, r, 10, 0.0)


## 天降灵雨：从屏幕上方落下并向左横扫
func _rain(c: int, n: int, turn: float) -> void:
	if world == null:
		return
	for i in n:
		var x := randf() * (Game.VIEW_W - 120.0) + 60.0
		var b := Danmaku.spawn(world, c, Vector2(x, -30.0), Vector2(-110.0, 235.0),
			10, 9.0)
		if b == null:
			return
		b.turn = turn
		b.target = _live_player()


func _b(c: int, dirv: Vector2, sp: float, r: float, dmg: int, turn: float) -> void:
	if world == null:
		return
	var dir := dirv.normalized()
	var b := Danmaku.spawn(world, c, position + dir * 52.0, dir * sp, dmg, r)
	if b == null:
		return
	b.turn = turn
	b.target = _live_player()


# ------------------------------------------------------------ 受击 / 阶段
func hit(dmg: int, c: int) -> void:
	if _st == "dying":
		return
	var mul := 1.0
	if ward >= 0:
		# 异色衰减由难度决定：简单 / 普通没有法罩，困难 = 60%
		mul = 1.0 if c == ward else _off_color
	var real := maxi(1, int(roundf(float(dmg) * mul)))
	hp -= real
	_flash = 0.09
	hp_ratio.emit(clampf(float(hp) / float(max_hp), 0.0, 1.0))
	if ward >= 0:
		if mul >= 1.0:
			Fx.pop(self, Vector2(0.0, -70.0), "破罩 %d" % real,
				Game.COLOR_MAIN[ward], 17)
		else:
			Fx.pop(self, Vector2(0.0, -70.0), "抗性 %d" % real,
				Color(0.62, 0.66, 0.75), 15)
	if hp <= 0:
		hp = 0
		_die()
		return
	_check_phase()


func _check_phase() -> void:
	var r := float(hp) / float(max_hp)
	var p := 1
	if _phases <= 2:
		if r <= 0.5:
			p = 2
	elif r <= 0.34:
		p = 3
	elif r <= 0.67:
		p = 2
	if p != phase:
		phase = p
		_on_phase()


## HUD 画阶段刻度用：两重就一条线，三重两条
func phase_marks() -> Array[float]:
	if _phases <= 2:
		return [0.5]
	return [0.34, 0.67]


func _on_phase() -> void:
	_clear_bullets()
	ward = -1
	_ward_t = 2.4
	ward_chg.emit(-1)
	_cast = 1.3
	_tick = 1.3
	_skill = "ring_white"
	Fx.shock(world, position, Color(1.0, 1.0, 1.0), 640.0, 0.9)
	Fx.ring(world, position, Game.COLOR_MAIN[Game.WHITE], 40.0, 420.0, 0.7, 12.0)
	phase_chg.emit(phase)


func _clear_bullets() -> void:
	var p := world
	if p == null:
		return
	for ch in p.get_children():
		if ch is Danmaku:
			(ch as Danmaku).dissolve()


func _die() -> void:
	_st = "dying"
	ward = -1
	ward_chg.emit(-1)
	hp_ratio.emit(0.0)
	_clear_bullets()
	set_process(false)
	for i in 16:
		var off := Vector2(randf() - 0.5, randf() - 0.5) * 140.0
		Fx.burst(world, position + off, Game.COLOR_GLOW[i % 4], 18, 340.0, 0.7)
		await get_tree().create_timer(0.12).timeout
	Fx.shock(world, position, Color(1.0, 1.0, 1.0), 900.0, 1.2)
	boss_died.emit()
	queue_free()


# ------------------------------------------------------------ 绘制
func _draw() -> void:
	var bc := ward if ward >= 0 else Game.WHITE
	var m: Color = Game.COLOR_MAIN[bc]
	var g: Color = Game.COLOR_GLOW[bc]
	var k: Color = Game.COLOR_CORE[bc]
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	if phase >= _phases:
		pulse = 0.5 + 0.5 * sin(_t * 8.0)

	# 本体气息
	draw_circle(Vector2.ZERO, 132.0 + 8.0 * pulse, Color(g.r, g.g, g.b, 0.07))

	# 狂暴：周身泛红光 + 逆向游走的血色符点
	if enraged:
		var ea := 0.5 + 0.5 * sin(_t * 9.0)
		draw_circle(Vector2.ZERO, 158.0 + 12.0 * ea, Color(1.0, 0.16, 0.10, 0.10))
		draw_circle(Vector2.ZERO, 140.0 + 8.0 * ea, Color(1.0, 0.22, 0.14, 0.14))
		draw_arc(Vector2.ZERO, 146.0, 0.0, TAU, 56,
			Color(1.0, 0.30, 0.20, 0.45 + 0.35 * ea), 6.0, true)
		for i in 10:
			var ang := -_t * 2.2 + TAU * float(i) / 10.0
			var p := Vector2.RIGHT.rotated(ang) * (152.0 + 14.0 * sin(_t * 5.0 + i))
			draw_circle(p, 4.2, Color(1.0, 0.42, 0.26, 0.7))

	# 属性法罩
	if ward >= 0:
		var a := 0.55 + 0.35 * sin(_ward_anim * 7.0)
		draw_circle(Vector2.ZERO, 118.0, Color(m.r, m.g, m.b, 0.07))
		draw_arc(Vector2.ZERO, 118.0, 0.0, TAU, 56, Color(m.r, m.g, m.b, a), 9.0, true)
		draw_arc(Vector2.ZERO, 106.0, 0.0, TAU, 56, Color(k.r, k.g, k.b, a * 0.55), 3.0, true)
		# 法罩符文
		for i in 8:
			var ang := _ward_anim * 1.2 + TAU * float(i) / 8.0
			var p := Vector2.RIGHT.rotated(ang) * 118.0
			draw_circle(p, 4.5, Color(k.r, k.g, k.b, a))

	# 四色法珠（当前法罩色的珠子放大）
	for i in 4:
		var ang := _t * 0.85 + TAU * float(i) / 4.0
		var p := Vector2.RIGHT.rotated(ang) * 96.0
		var cm: Color = Game.COLOR_MAIN[i]
		var rr := 17.0 if i == ward else 11.0
		draw_circle(p, rr + 6.0, Color(Game.COLOR_GLOW[i].r, Game.COLOR_GLOW[i].g,
			Game.COLOR_GLOW[i].b, 0.20))
		draw_circle(p, rr, cm)
		draw_circle(p, rr * 0.42, Game.COLOR_CORE[i])

	# 躯干 / 双角 / 法眼：由 _art（魔道法相像素 sprite）呈现

	# 末阶狂气
	if phase >= _phases:
		for i in 12:
			var ang := -_t * 1.6 + TAU * float(i) / 12.0
			var p := Vector2.RIGHT.rotated(ang) * (140.0 + 12.0 * sin(_t * 6.0 + i))
			draw_circle(p, 5.0, Color(1.0, 0.35, 0.25, 0.55))

	if _flash > 0.0:
		draw_circle(Vector2.ZERO, 70.0, Color(1.0, 1.0, 1.0, _flash * 2.2))
