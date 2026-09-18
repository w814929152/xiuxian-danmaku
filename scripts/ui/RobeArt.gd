class_name RobeArt
extends RefCounted
## 道袍立绘：像素 sprite + 外圈氛围的纯静态绘制工具
##
## 游戏内玩家形象是 44x36 侧身朝右的像素道袍（ArtAssets.by_color("robe", c)），
## 界面立绘必须与之一致：本体由 sprite 纹理接管，本工具**不再画任何身体几何**，
## 只保留「长不在身上」的氛围层。总判据：sprite 上「长在身上的部件」必须唯一，
## 氛围元素只允许用本袍 MAIN/GLOW/DARK/CORE 或中性灰 —— 颜色是免疫属性的
## 第一识别维度，氛围层绝不引入新色相。
##
## 像素约定：
##   · s 是**整数倍率**（择袍界面 3 / 道袍库 6），配合调用方在 _ready 里设置的
##     TEXTURE_FILTER_NEAREST 逐像素放大，绝不做连续缩放；
##   · 对齐与动画都以画布中心 (22,18) 为轴 —— 画布中心即游戏内节点原点，
##     前后留白是作者有意分配的构图空间，四张卡并排时躯干才不会互相错位；
##   · bob / 脉冲一律量化取整成档位，连续值的亚像素抖动没有像素 idle 的味道；
##   · 禁止呼吸缩放（整数倍之间跳变是 +33%，会闪），呼吸感交给外环脉冲。
##
## 用法：RobeArt.draw(self, 中心点, 颜色枚举, 时间秒, 整数倍率)

## sprite 画布尺寸与画布中心（= 游戏内节点原点）
const TEX_SIZE := Vector2(44.0, 36.0)
const TEX_CENTER := Vector2(22.0, 18.0)

## 绕行光点椭圆轨道（源像素）：ry=18 时光点底缘刚好够不到择袍卡的标题字形顶
const ORBIT_RX := 26.0
const ORBIT_RY := 18.0

## 地面投影（源像素）：半宽 15 ≈ 0.7×图宽 的一半，高 2，贴在不透明脚底线 +17
const SHADOW_HALF_W := 15.0
const SHADOW_H := 2.0
const SHADOW_Y := 17.0

## 灵光外环半径（源像素）：道袍库面板里 30x6=180 恰好装下
## （顶 181 > 176 / 底 541 < 562 / 左右 145..505 都在面板内）
const RING_R := 30.0
## 外环只在道袍库倍率（6）下绘制：择袍卡面立绘中心到标题字形顶只有约 63px，
## 30x3=90 的外环放不下 —— 用倍率区分两处界面，签名保持不变
const RING_MIN_S := 6.0

## 外环粗细（源像素）与 alpha 系数：太清主守，「守」改由外环承担 -> 最厚最实；
## 赤炎的双剑形状已足够读 -> 最弱，避免氛围抢过身份部件
const RING_W: Array[float] = [1.0, 2.0, 3.0, 2.0]
const RING_A: Array[float] = [0.55, 0.75, 1.0, 0.8]

## 绕行灵光点数量：戊土 3 枚（替代被删除的符形），其余 2 枚；
## 剑从此专属赤炎 sprite 的手前双剑，绕行物一律是无形状的灵光点
const DOT_N: Array[int] = [2, 2, 2, 3]


static func draw(ci: CanvasItem, pos: Vector2, c: int, t: float, s: float) -> void:
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var tex: Texture2D = ArtAssets.by_color("robe", c)
	var ring: bool = s >= RING_MIN_S

	# bob：振幅 1 源像素、周期 2.2s，sin 量化成 -1/0/+1 三档（像素 idle）
	var bob_q := roundf(sin(t * TAU / 2.2))
	var bob := Vector2(0.0, bob_q) * s
	# 外环脉冲：与 bob 错频（周期 1.7s），半径量化 ±1 源像素 ——
	# 取下限是因为道袍库面板上沿只剩 5px 余量，±2 会溢出面板边框
	var pr := roundf(sin(t * TAU / 1.7 + 1.3))
	var pa := 0.25 + 0.10 * sin(t * TAU / 1.7 + 2.1)

	# 外环柔光底盘（道袍库才有空间画外环）
	if ring:
		ci.draw_circle(pos, RING_R * s, Color(g.r, g.g, g.b, 0.05))

	# 玄冰遁袍：身后拖影线（画在 sprite 之下，被袍身自然遮住衔接处）
	if c == Game.BLUE and tex != null:
		_trail_lines(ci, pos, g, t, s, bob)

	# 绕行灵光点 · 后半程（角色朝右，轨道左侧即身后，画在 sprite 之下）
	var n: int = DOT_N[c]
	for i in n:
		var a: float = t * 1.5 + TAU * float(i) / float(n) + 0.7
		if cos(a) < 0.0:
			_orbit_dot(ci, pos + bob, g, Game.COLOR_CORE[c], a, s)

	# 地面投影：不随 bob 起落，宽度随 bob 反向 ±1 源像素（起则影窄、落则影宽）
	var sw: float = (SHADOW_HALF_W - bob_q) * s
	ci.draw_rect(Rect2(pos.x - sw, pos.y + (SHADOW_Y - SHADOW_H * 0.5) * s,
		sw * 2.0, SHADOW_H * s), Color(0.0, 0.0, 0.0, 0.25))

	# 道袍本体：按画布中心对齐。44/36 是偶数、s 是整数、bob 是整源像素，
	# top_left 恒为整数，不会有半像素
	if tex != null:
		var tl: Vector2 = pos.round() + bob - TEX_CENTER * s
		ci.draw_texture_rect(tex, Rect2(tl, TEX_SIZE * s), false)
	else:
		_fallback(ci, pos + bob, c, s)

	# 灵光外环弧线（仅道袍库）：半径脉冲 + alpha 呼吸
	if ring:
		var rw: float = RING_W[c] * s
		ci.draw_arc(pos, (RING_R + pr) * s, 0.0, TAU, 64,
			Color(m.r, m.g, m.b, pa * RING_A[c]), rw, true)

	# 绕行灵光点 · 前半程（画在 sprite 之上，绕到身前）
	for i in n:
		var a2: float = t * 1.5 + TAU * float(i) / float(n) + 0.7
		if cos(a2) >= 0.0:
			_orbit_dot(ci, pos + bob, g, Game.COLOR_CORE[c], a2, s)


## 玄冰拖影线：身后 3 条水平短线，长度 32 源像素（> 0.6×图宽），
## 无轮廓、alpha 峰值 0.20 —— 残影圈改线是因为「圈」是具象形状，
## 会和 sprite 自带的后掠飘带抢形状层语义
static func _trail_lines(ci: CanvasItem, pos: Vector2, g: Color, t: float,
		s: float, bob: Vector2) -> void:
	var ys := [-6.0, 0.0, 6.0]
	for i in ys.size():
		var y: float = ys[i]
		var a := 0.16 + 0.04 * sin(t * 2.0 + float(i) * 2.1)
		var p0 := Vector2(pos.x + bob.x - 40.0 * s, pos.y + bob.y + y * s)
		var p1 := Vector2(pos.x + bob.x - 8.0 * s, pos.y + bob.y + y * s)
		ci.draw_line(p0, p1, Color(g.r, g.g, g.b, a), s)


## 绕行灵光点：椭圆轨道上的一粒光，GLOW 外芯 + CORE 内芯
static func _orbit_dot(ci: CanvasItem, pos: Vector2, g: Color, k: Color,
		a: float, s: float) -> void:
	var p: Vector2 = pos + Vector2(cos(a) * ORBIT_RX, sin(a) * ORBIT_RY) * s
	ci.draw_circle(p, 2.0 * s, Color(g.r, g.g, g.b, 0.85))
	ci.draw_circle(p, s, Color(k.r, k.g, k.b, 0.9))


## 纹理缺失的兜底：最简人形剪影（只用品袍四色），界面不能变空白。
## 只求「有个修士站在那」，不追求细节 —— 正常情况永远走不到这
static func _fallback(ci: CanvasItem, pos: Vector2, c: int, s: float) -> void:
	var dk: Color = Game.COLOR_DARK[c]
	var m: Color = Game.COLOR_MAIN[c]
	var k: Color = Game.COLOR_CORE[c]
	ci.draw_rect(Rect2(pos.x - 8.0 * s, pos.y - 6.0 * s, 16.0 * s, 23.0 * s), dk)
	ci.draw_rect(Rect2(pos.x - 8.0 * s, pos.y - 6.0 * s, 16.0 * s, 23.0 * s),
		m, false, maxf(1.0, s))
	ci.draw_circle(pos + Vector2(2.0, -11.0) * s, 4.5 * s, k)
