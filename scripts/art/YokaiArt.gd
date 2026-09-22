class_name YokaiArt
extends RefCounted
## ---------------------------------------------------------------
## YokaiArt —— 异形妖怪矢量绘制（小妖 / 妖将共用，纯静态）
##
## 回滚到 9/16 混合版后重新确立的美术语法（AI 源图已永久丢失，故矢量重画）：
##   · 朝向：+X 是尾（飘带 / 火鬃 / 符带），−X 是头（口器 / 主核 / 前指棱）。
##     CORE 白核只出现在朝左、贴近原点处 —— 它是唯一的要害指针，瞄圆心即命中。
##   · 体块层序（绘制顺序铁律）：
##     ① 气息光晕 → ② +X 尾 → ③ DARK 外壳 → ④ MAIN 主体 → ⑤ DARK 结构线
##     → ⑥ GLOW 尖刺/顶冠 → ⑦ 装饰 → ⑧ CORE 主核。
##     受击白闪 / 法罡环 / 血条由调用方在其后续画（层序保持在主体之上）。
##     +X 拖影必须先于主体（否则糊住主体）；CORE 主核必须最后（否则被尖刺盖住，
##     朝向指针失效）。
##   · 四色共用同一套体块语法，只换母题。妖将主体 ≈ 小妖顶点 ×1.7（同剪影），
##     妖将另有三个标记：顶冠大角 / 双层壳 / 细节密度 ×2。
##   · 硬底线：每色有一块不透明 MAIN 实心块（玩家「该换哪件袍」靠高饱和 MAIN
##     面积判断）；雾感 / 发光 / 半透明只允许加在实色之外。
##   · 动画只有两种：呼吸缩放 s = 1 + 0.04·sin(2.2t + φ)（φ 按实例随机、
##     不平移原点）与尾部尖端 y ±2px 抖动。禁止整体旋转、缩放 >8%、
##     主体轮廓顶点抖动 —— 会破坏玩家对位置的预判。
## ---------------------------------------------------------------

# ================================================================ 小妖剪影
## 炎魔主体（妖将顶点 = 这里 ×1.7）
const BODY_RED := [
	Vector2(-20.0, 0.0), Vector2(-9.0, -12.0), Vector2(11.0, -7.0),
	Vector2(14.0, 0.0), Vector2(11.0, 7.0), Vector2(-9.0, 12.0),
]
## 冰妖主体
const BODY_BLUE := [
	Vector2(-19.0, 0.0), Vector2(-8.0, -13.0), Vector2(12.0, -9.0),
	Vector2(15.0, 0.0), Vector2(12.0, 9.0), Vector2(-8.0, 13.0),
]
## 戊土妖主体：八边牌（±17,±9 / ±9,±17 切角）
const BODY_YELLOW := [
	Vector2(17.0, 9.0), Vector2(9.0, 17.0), Vector2(-9.0, 17.0),
	Vector2(-17.0, 9.0), Vector2(-17.0, -9.0), Vector2(-9.0, -17.0),
	Vector2(9.0, -17.0), Vector2(17.0, -9.0),
]
## 炎魔背鬃 ×3：每枚三角 3 顶点，基边贴主体上缘
const MANES_RED := [
	Vector2(-7.0, -11.5), Vector2(-2.0, -10.3), Vector2(-6.0, -18.5),
	Vector2(0.0, -9.75), Vector2(4.0, -8.75), Vector2(1.0, -16.5),
	Vector2(6.0, -8.25), Vector2(10.0, -7.25), Vector2(8.0, -15.0),
]
## 冰妖前指霜棱 ×3（尖 (−31,−7)(−33,1)(−25,13)，基边在体内侧、宽 7）
const FROST_3 := [
	Vector2(-8.0, -10.0), Vector2(-8.0, -3.0), Vector2(-31.0, -7.0),
	Vector2(-9.0, -3.5), Vector2(-9.0, 3.5), Vector2(-33.0, 1.0),
	Vector2(-8.0, 3.0), Vector2(-8.0, 10.0), Vector2(-25.0, 13.0),
]
## 冰将顶冠：6 前指霜棱，扇形铺开、尖半径 ≤38（视觉上限 40 之内）
const FROST_6 := [
	Vector2(-9.0, -20.7), Vector2(-17.0, -13.3), Vector2(-24.0, -29.0),
	Vector2(-11.4, -13.9), Vector2(-16.6, -4.1), Vector2(-33.0, -19.0),
	Vector2(-12.8, -7.4), Vector2(-15.2, 3.4), Vector2(-37.0, -7.0),
	Vector2(-15.2, -3.4), Vector2(-12.8, 7.4), Vector2(-37.0, 5.0),
	Vector2(-16.6, 4.1), Vector2(-11.4, 13.9), Vector2(-33.0, 17.0),
	Vector2(-17.0, 13.3), Vector2(-9.0, 20.7), Vector2(-24.0, 27.0),
]
## 戊土妖 4 符钉（方 4×4）
const NAILS_YELLOW := [
	Vector2(-12.0, -12.0), Vector2(12.0, -12.0),
	Vector2(-12.0, 12.0), Vector2(12.0, 12.0),
]
## 清灵副眼 ×4 位置与半径（主目之外的第二组目；配 DARK 眼窝后在白身上可读）
const EYES_WHITE := [
	Vector2(-2.0, -9.0), Vector2(-2.0, 9.0),
	Vector2(6.0, 7.0), Vector2(6.0, -7.0),
]
const EYES_R := [2.5, 2.5, 2.0, 2.0]

# ================================================================ 妖将剪影
## 炎将主体（= 小妖炎魔 ×1.7）
const ELITE_BODY_RED := [
	Vector2(-34.0, 0.0), Vector2(-15.0, -21.0), Vector2(19.0, -12.0),
	Vector2(24.0, 0.0), Vector2(19.0, 12.0), Vector2(-15.0, 21.0),
]
## 冰将主体（= 小妖冰妖 ×1.7）
const ELITE_BODY_BLUE := [
	Vector2(-30.0, 0.0), Vector2(-13.0, -21.0), Vector2(19.0, -15.0),
	Vector2(24.0, 0.0), Vector2(19.0, 15.0), Vector2(-13.0, 21.0),
]
## 土将主体：八边牌（±28,±15 / ±15,±28）
const ELITE_BODY_YELLOW := [
	Vector2(28.0, 15.0), Vector2(15.0, 28.0), Vector2(-15.0, 28.0),
	Vector2(-28.0, 15.0), Vector2(-28.0, -15.0), Vector2(-15.0, -28.0),
	Vector2(15.0, -28.0), Vector2(28.0, -15.0),
]
## 土将 8 符钉（方 6×6，上下两排各 4 —— 避开 −X 要害指针与主核）
const ELITE_NAILS_YELLOW := [
	Vector2(-20.0, -20.0), Vector2(-6.0, -20.0),
	Vector2(6.0, -20.0), Vector2(20.0, -20.0),
	Vector2(-20.0, 20.0), Vector2(-6.0, 20.0),
	Vector2(6.0, 20.0), Vector2(20.0, 20.0),
]


## 呼吸缩放系数：幅度 4%，φ 按实例随机（由调用方持有），不平移原点
static func breath(t: float, phase: float) -> float:
	return 1.0 + 0.04 * sin(2.2 * t + phase)


## 尾部尖端 y 抖动：±2px（只抖尾尖，主体轮廓纹丝不动）
static func tail_jitter(t: float, phase: float) -> float:
	return sin(t * 5.0 + phase) * 2.0


## 基准多边形整体缩放 k（呼吸缩放走这里，一次乘清）
static func _poly(base: Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(base.size())
	for i in base.size():
		var p: Vector2 = base[i]
		out[i] = p * k
	return out


## 三角形（a/b/c 为基准顶点，k 为呼吸缩放）
static func _tri(a: Vector2, b: Vector2, c: Vector2, k: float) -> PackedVector2Array:
	return PackedVector2Array([a * k, b * k, c * k])


## 闭多边形描边（首尾相接）
static func _outline(ci: CanvasItem, pts: PackedVector2Array, col: Color,
		w: float) -> void:
	var ring := PackedVector2Array(pts)
	ring.append(pts[0])
	ci.draw_polyline(ring, col, w, true)


## 连续三顶点为一枚三角的顶点表整批绘制（背鬃 / 霜棱共用）
static func _tri_batch(ci: CanvasItem, pts: Array, k: float, col: Color) -> void:
	for i in int(pts.size() / 3.0):
		var a: Vector2 = pts[i * 3]
		var b: Vector2 = pts[i * 3 + 1]
		var c: Vector2 = pts[i * 3 + 2]
		ci.draw_colored_polygon(_tri(a, b, c, k), col)


# ================================================================ 小妖
## 小妖（碰撞半径 19，主体剪影壳 ≈ r20~22；尖刺 / 顶冠为允许探出的造型）
## [param phase] 呼吸 / 抖动的实例随机相位
static func draw_minion(ci: CanvasItem, c: int, t: float, phase: float) -> void:
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var k: Color = Game.COLOR_CORE[c]
	var dk: Color = Game.COLOR_DARK[c]
	var s := breath(t, phase)
	var jy := tail_jitter(t, phase)

	# ① 气息光晕（GLOW a0.12；清灵多一层外雾）
	match c:
		Game.RED:
			ci.draw_circle(Vector2.ZERO, 24.0 * s, Color(g.r, g.g, g.b, 0.12))
		Game.BLUE:
			ci.draw_circle(Vector2.ZERO, 22.0 * s, Color(g.r, g.g, g.b, 0.12))
		Game.WHITE:
			ci.draw_circle(Vector2.ZERO, 26.0 * s, Color(g.r, g.g, g.b, 0.06))
			ci.draw_circle(Vector2.ZERO, 23.0 * s, Color(g.r, g.g, g.b, 0.12))
		_:
			ci.draw_circle(Vector2.ZERO, 23.0 * s, Color(g.r, g.g, g.b, 0.12))

	# ② +X 尾 / 飘带（GLOW a0.35，必须先于主体画）
	_tails(ci, c, s, jy, Color(g.r, g.g, g.b, 0.35))

	match c:
		Game.RED:
			# ③ 兽首多边形外壳（主体 ×1.12）
			ci.draw_colored_polygon(_poly(BODY_RED, 1.12 * s), dk)
			# ④ 主体
			ci.draw_colored_polygon(_poly(BODY_RED, s), Color(m.r, m.g, m.b, 1.0))
			# ⑥ 独角 + 3 背鬃
			ci.draw_colored_polygon(_tri(Vector2(-13.0, -6.0), Vector2(-29.0, -11.0),
				Vector2(-11.0, 0.0), s), Color(g.r, g.g, g.b, 0.85))
			_tri_batch(ci, MANES_RED, s, Color(g.r, g.g, g.b, 0.85))
			# ⑧ 主核 + 口器指针（CORE 最后画）
			ci.draw_circle(Vector2(-7.0, 0.0) * s, 4.5 * s, k)
			ci.draw_colored_polygon(_tri(Vector2(-20.0, 0.0), Vector2(-13.0, -4.0),
				Vector2(-13.0, 4.0), s), Color(k.r, k.g, k.b, 0.9))
		Game.BLUE:
			# ③ 菱壳六边形外壳
			ci.draw_colored_polygon(_poly(BODY_BLUE, 1.12 * s), dk)
			# ④ 主体
			ci.draw_colored_polygon(_poly(BODY_BLUE, s), Color(m.r, m.g, m.b, 1.0))
			# ⑤ 结构线 ×2
			ci.draw_line(Vector2(-4.0, -11.0) * s, Vector2(8.0, -2.0) * s, dk, 2.0, true)
			ci.draw_line(Vector2(-4.0, 11.0) * s, Vector2(8.0, 2.0) * s, dk, 2.0, true)
			# ⑥ 3 前指霜棱（霜棱即朝向指针）
			_tri_batch(ci, FROST_3, s, Color(g.r, g.g, g.b, 0.85))
			# ⑧ 主核（MAIN 圈 + CORE 芯）
			ci.draw_arc(Vector2(-6.0, 0.0) * s, 6.5 * s, 0.0, TAU, 20, m, 3.0, true)
			ci.draw_circle(Vector2(-6.0, 0.0) * s, 4.0 * s, k)
		Game.WHITE:
			# ③ 圆壳垫底
			ci.draw_circle(Vector2.ZERO, 18.0 * s, dk)
			# ④ 主体
			ci.draw_circle(Vector2.ZERO, 17.0 * s, Color(m.r, m.g, m.b, 1.0))
			# ⑦ 4 目：主目之外的 4 枚副眼（GLOW —— 副眼不得抢 CORE 白核的唯一性）。
			#   副眼先垫 DARK 眼窝：GLOW 直画在近白 MAIN 主体上会不可读
			for i in EYES_WHITE.size():
				var ev: Vector2 = EYES_WHITE[i]
				var er: float = EYES_R[i]
				ci.draw_circle(ev * s, (er + 1.3) * s, dk)
				ci.draw_circle(ev * s, er * s, Color(g.r, g.g, g.b, 0.9))
			# ⑧ 主目（朝向指针）：DARK 眼窝 -> MAIN 圈 -> CORE 芯，保证在白身上可读
			ci.draw_circle(Vector2(-9.0, -6.0) * s, 8.4 * s, dk)
			ci.draw_arc(Vector2(-9.0, -6.0) * s, 6.8 * s, 0.0, TAU, 24, m, 3.0, true)
			ci.draw_circle(Vector2(-9.0, -6.0) * s, 4.2 * s, k)
		_:
			# ③ 八边牌外壳
			ci.draw_colored_polygon(_poly(BODY_YELLOW, 1.12 * s), dk)
			# ④ 主体
			ci.draw_colored_polygon(_poly(BODY_YELLOW, s), Color(m.r, m.g, m.b, 1.0))
			# ⑤ 三横一竖（符牌刻痕）
			ci.draw_line(Vector2(-2.0, -6.0) * s, Vector2(10.0, -6.0) * s, dk, 3.0, true)
			ci.draw_line(Vector2(-2.0, 0.0) * s, Vector2(10.0, 0.0) * s, dk, 3.0, true)
			ci.draw_line(Vector2(-2.0, 6.0) * s, Vector2(10.0, 6.0) * s, dk, 3.0, true)
			ci.draw_line(Vector2(4.0, -8.0) * s, Vector2(4.0, 8.0) * s, dk, 3.0, true)
			# ⑥ 2 钝岩角（上下镜像）
			ci.draw_colored_polygon(_tri(Vector2(-7.0, -17.0), Vector2(-2.0, -29.0),
				Vector2(3.0, -17.0), s), Color(g.r, g.g, g.b, 0.85))
			ci.draw_colored_polygon(_tri(Vector2(-7.0, 17.0), Vector2(-2.0, 29.0),
				Vector2(3.0, 17.0), s), Color(g.r, g.g, g.b, 0.85))
			# ⑦ 4 符钉（GLOW —— 不与 CORE 主核抢要害指针）
			for i in NAILS_YELLOW.size():
				var pv: Vector2 = NAILS_YELLOW[i]
				var p := pv * s
				ci.draw_rect(Rect2(p.x - 2.0 * s, p.y - 2.0 * s, 4.0 * s, 4.0 * s),
					Color(g.r, g.g, g.b, 0.8))
			# ⑧ 主核 + 指针三角
			ci.draw_circle(Vector2(-6.0, 0.0) * s, 4.0 * s, k)
			ci.draw_colored_polygon(_tri(Vector2(-17.0, 0.0), Vector2(-10.0, -4.0),
				Vector2(-10.0, 4.0), s), Color(k.r, k.g, k.b, 0.9))


## 小妖尾部：炎 3 火舌 / 冰 2 后摆鳍 / 清灵 3 弧 / 土 2 符带
static func _tails(ci: CanvasItem, c: int, s: float, jy: float, col: Color) -> void:
	match c:
		Game.RED:
			for i in 3:
				var by := -8.0 + 8.0 * float(i)          # 基边中点 y：-8 / 0 / 8
				var tx := 28.0
				if i == 1:
					tx = 32.0
				var tip := Vector2(tx, by * 1.75 + jy)   # 尖 (28,∓14)(32,0)
				ci.draw_colored_polygon(_tri(Vector2(10.0, by - 4.0),
					Vector2(10.0, by + 4.0), tip, s), col)
		Game.BLUE:
			for i in 2:
				var sgn := -1.0 + 2.0 * float(i)
				ci.draw_colored_polygon(_tri(Vector2(11.0, 2.0 * sgn),
					Vector2(11.0, 10.0 * sgn), Vector2(30.0, 10.0 * sgn + jy), s), col)
		Game.WHITE:
			for i in 3:
				var r := 10.0 + 4.0 * float(i)
				ci.draw_arc(Vector2(16.0, 0.0) * s, r * s, -PI / 3.0, PI / 3.0, 12,
					col, 3.0, true)
		_:
			for i in 2:
				var sgn := -1.0 + 2.0 * float(i)
				ci.draw_rect(Rect2(14.0 * s, (6.0 * sgn + jy * 0.5) * s,
					12.0 * s, 3.0 * s), col)


# ================================================================ 妖将
## 妖将（碰撞半径 34，主体剪影 ≤ r32，法罡弧内缘 43 留 3px 呼吸）
## 三标记：顶冠大角 / 双层壳 / 细节密度 ×2；主体 = 小妖顶点 ×1.7
static func draw_elite(ci: CanvasItem, c: int, t: float, phase: float) -> void:
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var k: Color = Game.COLOR_CORE[c]
	var dk: Color = Game.COLOR_DARK[c]
	var s := breath(t, phase)
	var jy := tail_jitter(t, phase)

	# ② +X 尾（同母题 ×~1.25，控制在视觉上限 r40 内）
	_tails_elite(ci, c, s, jy, Color(g.r, g.g, g.b, 0.35))

	match c:
		Game.RED:
			var body := _poly(ELITE_BODY_RED, s)
			# ③ 双层壳之外层（主体 ×1.12）
			ci.draw_colored_polygon(_poly(ELITE_BODY_RED, 1.12 * s), dk)
			# ④ 主体 + 体壁描边（双层壳之内层）
			ci.draw_colored_polygon(body, Color(m.r, m.g, m.b, 1.0))
			_outline(ci, body, dk, 5.0)
			# ⑥ 顶冠双大角 + 背鬃 ×1.7
			ci.draw_colored_polygon(_tri(Vector2(-23.0, -9.0), Vector2(-17.0, -16.0),
				Vector2(-40.0, -24.0), s), Color(g.r, g.g, g.b, 0.85))
			ci.draw_colored_polygon(_tri(Vector2(-23.0, 9.0), Vector2(-17.0, 16.0),
				Vector2(-40.0, 24.0), s), Color(g.r, g.g, g.b, 0.85))
			_tri_batch(ci, MANES_RED, 1.7 * s, Color(g.r, g.g, g.b, 0.85))
			# ⑦ 2 段弧（细节密度 ×2）
			for i in 2:
				var sgn := -1.0 + 2.0 * float(i)
				ci.draw_arc(Vector2.ZERO, 30.0 * s, sgn * PI * 0.5 - 0.9,
					sgn * PI * 0.5 + 0.9, 16, Color(g.r, g.g, g.b, 0.45), 5.0, true)
			# ⑧ 主核 + 口器指针
			ci.draw_circle(Vector2(-10.0, 0.0) * s, 7.0 * s, k)
			ci.draw_colored_polygon(_tri(Vector2(-34.0, 0.0), Vector2(-22.0, -7.0),
				Vector2(-22.0, 7.0), s), Color(k.r, k.g, k.b, 0.9))
		Game.BLUE:
			var body := _poly(ELITE_BODY_BLUE, s)
			# ③ 双层壳之外层
			ci.draw_colored_polygon(_poly(ELITE_BODY_BLUE, 1.12 * s), dk)
			# ④ 主体 + 体壁描边
			ci.draw_colored_polygon(body, Color(m.r, m.g, m.b, 1.0))
			_outline(ci, body, dk, 5.0)
			# ⑤ 结构线 ×1.7
			ci.draw_line(Vector2(-7.0, -19.0) * s, Vector2(14.0, -3.0) * s, dk, 5.0, true)
			ci.draw_line(Vector2(-7.0, 19.0) * s, Vector2(14.0, 3.0) * s, dk, 5.0, true)
			# ⑥ 顶冠 = 6 前指霜棱
			_tri_batch(ci, FROST_6, s, Color(g.r, g.g, g.b, 0.85))
			# ⑦ 2 副核（GLOW —— 副核不得抢 CORE 主核的唯一要害指针）
			for i in 2:
				var sgn := -1.0 + 2.0 * float(i)
				ci.draw_circle(Vector2(2.0, 18.0 * sgn) * s, 3.5 * s,
					Color(g.r, g.g, g.b, 0.85))
			# ⑧ 主核（MAIN 圈 + CORE 芯）
			ci.draw_arc(Vector2(-9.0, 0.0) * s, 11.0 * s, 0.0, TAU, 28, m, 5.0, true)
			ci.draw_circle(Vector2(-9.0, 0.0) * s, 6.5 * s, k)
		Game.WHITE:
			# ③ 双层壳之外层（圆 r32）
			ci.draw_circle(Vector2.ZERO, 32.0 * s, dk)
			# ④ 主体（圆 r30）+ 内壳壁
			ci.draw_circle(Vector2.ZERO, 30.0 * s, Color(m.r, m.g, m.b, 1.0))
			ci.draw_arc(Vector2.ZERO, 26.0 * s, 0.0, TAU, 48, dk, 4.0, true)
			# ⑦ 6 枚灵点环绕 r22（缓慢环绕的是装饰灵点，不是整体旋转）
			for i in 6:
				var a := t * 0.6 + TAU * float(i) / 6.0
				ci.draw_circle(Vector2.RIGHT.rotated(a) * (22.0 * s), 3.0 * s,
					Color(g.r, g.g, g.b, 0.8))
			# ⑧ 主目（朝向指针）：DARK 眼窝 -> MAIN 圈 -> CORE 芯（白身上必须可读）
			ci.draw_circle(Vector2(-14.0, -9.0) * s, 13.0 * s, dk)
			ci.draw_arc(Vector2(-14.0, -9.0) * s, 11.5 * s, 0.0, TAU, 28, m, 5.0, true)
			ci.draw_circle(Vector2(-14.0, -9.0) * s, 6.0 * s, k)
		_:
			var body := _poly(ELITE_BODY_YELLOW, s)
			# ③ 双层壳之外层（八边牌 ×1.12）
			ci.draw_colored_polygon(_poly(ELITE_BODY_YELLOW, 1.12 * s), dk)
			# ④ 主体 + 体壁描边
			ci.draw_colored_polygon(body, Color(m.r, m.g, m.b, 1.0))
			_outline(ci, body, dk, 5.0)
			# ⑤ 三横一竖 ×1.7
			ci.draw_line(Vector2(-3.0, -10.0) * s, Vector2(17.0, -10.0) * s, dk, 5.0, true)
			ci.draw_line(Vector2(-3.0, 0.0) * s, Vector2(17.0, 0.0) * s, dk, 5.0, true)
			ci.draw_line(Vector2(-3.0, 10.0) * s, Vector2(17.0, 10.0) * s, dk, 5.0, true)
			ci.draw_line(Vector2(7.0, -14.0) * s, Vector2(7.0, 14.0) * s, dk, 5.0, true)
			# ⑥ 顶冠双岩角（上下镜像）
			ci.draw_colored_polygon(_tri(Vector2(-11.0, -28.0), Vector2(-3.0, -40.0),
				Vector2(7.0, -28.0), s), Color(g.r, g.g, g.b, 0.85))
			ci.draw_colored_polygon(_tri(Vector2(-11.0, 28.0), Vector2(-3.0, 40.0),
				Vector2(7.0, 28.0), s), Color(g.r, g.g, g.b, 0.85))
			# ⑦ 8 符钉
			for i in ELITE_NAILS_YELLOW.size():
				var pv: Vector2 = ELITE_NAILS_YELLOW[i]
				var p := pv * s
				ci.draw_rect(Rect2(p.x - 3.0 * s, p.y - 3.0 * s, 6.0 * s, 6.0 * s),
					Color(g.r, g.g, g.b, 0.8))
			# ⑧ 主核 + 指针三角
			ci.draw_circle(Vector2(-9.0, 0.0) * s, 5.0 * s, k)
			ci.draw_colored_polygon(_tri(Vector2(-29.0, 0.0), Vector2(-17.0, -7.0),
				Vector2(-17.0, 7.0), s), Color(k.r, k.g, k.b, 0.9))


## 妖将尾部：小妖同母题 ×~1.25（再大会捅穿法罡弧内缘 43）
static func _tails_elite(ci: CanvasItem, c: int, s: float, jy: float,
		col: Color) -> void:
	match c:
		Game.RED:
			for i in 3:
				var by := -12.0 + 12.0 * float(i)        # 基边中点 y：-12 / 0 / 12
				var tx := 35.0
				if i == 1:
					tx = 40.0
				var tip := Vector2(tx, by * 1.46 + jy)   # 尖 (35,∓17.5)(40,0)
				ci.draw_colored_polygon(_tri(Vector2(14.0, by - 6.0),
					Vector2(14.0, by + 6.0), tip, s), col)
		Game.BLUE:
			for i in 2:
				var sgn := -1.0 + 2.0 * float(i)
				ci.draw_colored_polygon(_tri(Vector2(13.0, 3.0 * sgn),
					Vector2(13.0, 16.0 * sgn), Vector2(37.5, 12.5 * sgn + jy), s), col)
		Game.WHITE:
			for i in 3:
				var r := 12.0 + 4.0 * float(i)
				ci.draw_arc(Vector2(20.0, 0.0) * s, r * s, -PI / 3.0, PI / 3.0, 14,
					col, 5.0, true)
		_:
			for i in 2:
				var sgn := -1.0 + 2.0 * float(i)
				ci.draw_rect(Rect2(24.0 * s, (9.0 * sgn + jy * 0.5) * s,
					16.0 * s, 5.0 * s), col)
