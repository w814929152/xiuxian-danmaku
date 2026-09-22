class_name ArmorArt
extends RefCounted
## 战甲立绘：一个纯静态的绘制工具
##
## 「战甲库」要展示四件战甲的形制，直接复用 Player 节点会带来逻辑负担
## （它会移动、开火、判定碰撞）。这里把战士外形抽成静态绘制，
## 任何 CanvasItem 都能调用，和玩法逻辑彻底解耦。
##
## 用法：ArmorArt.draw(self, 中心点, 颜色枚举, 时间秒, 缩放)


## 战甲本体（六边形裁片，与 Player 的战甲同形）
const BODY := [
	Vector2(20.0, 0.0), Vector2(6.0, -11.0), Vector2(-14.0, -9.0),
	Vector2(-20.0, 0.0), Vector2(-14.0, 9.0), Vector2(6.0, 11.0),
]

## 绕身随身光刃
const SWORD := [
	Vector2(7.0, 0.0), Vector2(0.0, -2.2), Vector2(-7.0, 0.0), Vector2(0.0, 2.2),
]


static func draw(ci: CanvasItem, pos: Vector2, c: int, t: float, s: float) -> void:
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var k: Color = Game.COLOR_CORE[c]
	var dk: Color = Game.COLOR_DARK[c]
	var pulse := 0.5 + 0.5 * sin(t * 3.0)

	# 辉光外环
	ci.draw_circle(pos, (58.0 + 6.0 * pulse) * s, Color(g.r, g.g, g.b, 0.10))
	ci.draw_arc(pos, (48.0 + 4.0 * pulse) * s, 0.0, TAU, 40,
		Color(m.r, m.g, m.b, 0.45), 2.5 * s, true)

	# 寒霜疾甲：残影
	if c == Game.BLUE:
		for i in 3:
			var a := t * 1.6 + TAU * float(i) / 3.0
			var p := pos + Vector2(cos(a) * 30.0, sin(a) * 12.0) * s
			ci.draw_circle(p, (26.0 - float(i) * 5.0) * s, Color(g.r, g.g, g.b, 0.10))

	# 光子盾甲：护盾环
	if c == Game.WHITE:
		ci.draw_arc(pos, 62.0 * s, -PI * 0.5, -PI * 0.5 + TAU * 0.85, 44,
			Color(1.0, 1.0, 1.0, 0.80), 4.0 * s, true)
		ci.draw_circle(pos, 62.0 * s, Color(0.95, 0.98, 1.0, 0.06))

	# 引力束甲：绕身引力环（4 枚）
	if c == Game.YELLOW:
		for i in 4:
			var a := t * 1.1 + TAU * float(i) / 4.0
			var p := pos + Vector2.RIGHT.rotated(a) * (54.0 * s)
			var q := PackedVector2Array([
				p + Vector2(0.0, -7.0) * s, p + Vector2(7.0, 0.0) * s,
				p + Vector2(0.0, 7.0) * s, p + Vector2(-7.0, 0.0) * s,
			])
			ci.draw_colored_polygon(q, Color(k.r, k.g, k.b, 0.55))

	# 能量尾带（身后）
	var rb := PackedVector2Array()
	for i in 10:
		var u := float(i) / 9.0
		rb.append(pos + Vector2((-18.0 - u * 46.0) * s,
			sin(t * 4.0 - u * 4.0) * 8.0 * u * s))
	ci.draw_polyline(rb, Color(m.r, m.g, m.b, 0.5), 3.2 * s, true)

	# 电浆剑甲：前置双刃
	if c == Game.RED:
		for oy in [-17.0, 17.0]:
			var q := PackedVector2Array([
				pos + Vector2(16.0, oy) * s,
				pos + Vector2(-5.0, oy - 3.4) * s,
				pos + Vector2(-10.0, oy) * s,
				pos + Vector2(-5.0, oy + 3.4) * s,
			])
			ci.draw_colored_polygon(q, Color(m.r, m.g, m.b, 0.9))

	# 战甲本体
	var body := _poly(BODY, 0.0, pos, s)
	ci.draw_colored_polygon(body, dk)
	var ring := PackedVector2Array(body)
	ring.append(body[0])
	ci.draw_polyline(ring, m, 2.2 * s, true)

	# 腰带
	ci.draw_line(pos + Vector2(-11.0, 0.0) * s, pos + Vector2(6.0, 0.0) * s,
		Color(g.r, g.g, g.b, 0.85), 2.6 * s, true)

	# 头 / 头部装甲壳（与 Player._draw 一致）：DARK 壳 + CANOPY 驾驶舱玻璃（敌我识别主通道）
	ci.draw_circle(pos + Vector2(11.0, -1.0) * s, 6.2 * s, dk)
	ci.draw_arc(pos + Vector2(11.0, -1.0) * s, 6.2 * s, 0.0, TAU, 16, m, 1.6 * s, true)
	# 驾驶舱玻璃（CANOPY）：前向倾斜椭圆，朝 +X 前方
	var canopy := PackedVector2Array([
		pos + Vector2(16.0, -3.4) * s, pos + Vector2(12.0, -4.4) * s,
		pos + Vector2(9.0, 1.6) * s, pos + Vector2(13.0, 4.4) * s,
	])
	ci.draw_colored_polygon(canopy, Game.CANOPY)
	ci.draw_polyline(PackedVector2Array([canopy[0], canopy[1], canopy[2], canopy[3], canopy[0]]),
		Color(1.0, 1.0, 1.0, 0.55), 1.2 * s, true)
	# 座舱内照明高光（CORE）+ 前向传感器探针
	ci.draw_circle(pos + Vector2(12.6, -0.6) * s, 1.5 * s, k)
	ci.draw_circle(pos + Vector2(17.0, -1.0) * s, 1.2 * s, m)

	# 绕身光刃
	for i in 3:
		var a := t * 1.5 + TAU * float(i) / 3.0
		var p := pos + Vector2.RIGHT.rotated(a) * (64.0 * s)
		ci.draw_colored_polygon(_poly(SWORD, a + PI * 0.5, p, s),
			Color(m.r, m.g, m.b, 0.78))

	# 判定点
	ci.draw_circle(pos, 11.0 * s, Color(m.r, m.g, m.b, 0.14))
	ci.draw_circle(pos, 3.2 * s, Color(1.0, 1.0, 1.0, 0.95))


## 把基准多边形按 角度 / 位置 / 缩放 变换后输出
static func _poly(base: Array, ang: float, off: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in base.size():
		var p: Vector2 = base[i]
		out.append(off + p.rotated(ang) * s)
	return out
