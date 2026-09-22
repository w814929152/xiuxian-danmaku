class_name PirateArt
extends RefCounted
## ---------------------------------------------------------------
## PirateArt —— 星盗机械单位矢量绘制（星盗 / 星盗战将共用，纯静态）
##
## 太空歌剧题材下的敌方机械语法（AI 源图已永久丢失，故矢量重画）：
##   · 朝向：−X 是头（主光学核 / 前向捕捉锥 / 前伸传感针），+X 是尾（引擎尾焰 / 姿态喷口）。
##     CORE 白核只出现在朝左、贴近原点处 —— 它是唯一的要害指针，瞄圆心即命中。
##   · 体块层序（绘制顺序铁律）：
##     ① 引擎辉光 → ② +X 尾 → ③ DARK 外壳 → ④ MAIN 主体 → ⑤ DARK 结构线
##     → ⑥ GLOW 尖刺/顶冠 → ⑦ 装饰 → ⑧ CORE 主核。
##     受击白闪 / 力场环 / 血条由调用方在其后续画（层序保持在主体之上）。
##     +X 拖影必须先于主体（否则糊住主体）；CORE 主核必须最后（否则被尖刺盖住，
##     朝向指针失效）。
##   · 四色共用同一套体块语法，只换母题。星盗战将为独立重画的精英机几何
##     （不再与星盗同剪影），另有三个标记：双联挂架 / 双层壳 / 细节密度 ×2。
##   · 硬底线：每色有一块不透明 MAIN 实心块（玩家「该换哪件战甲」靠高饱和 MAIN
##     面积判断）；雾感 / 发光 / 半透明只允许加在实色之外。
##   · 动画只有两种：呼吸缩放 s = 1 + 0.04·sin(2.2t + φ)（φ 按实例随机、
##     不平移原点）与尾部尖端 y ±2px 抖动。禁止整体旋转、缩放 >8%、
##     主体轮廓顶点抖动 —— 会破坏玩家对位置的预判。
##   · ⚠️ 全绘制函数禁止出现 CANOPY 舱盖色 (0.62,0.86,0.98) —— 星盗没有驾驶舱。
## ---------------------------------------------------------------

# ================================================================ 星盗剪影
## 电浆星盗主体（六边，朝 −X 削尖）
const BODY_RED := [
	Vector2(-20.0, 0.0), Vector2(-9.0, -12.0), Vector2(11.0, -7.0),
	Vector2(14.0, 0.0), Vector2(11.0, 7.0), Vector2(-9.0, 12.0),
]
## 寒霜星盗主体
const BODY_BLUE := [
	Vector2(-19.0, 0.0), Vector2(-8.0, -13.0), Vector2(12.0, -9.0),
	Vector2(15.0, 0.0), Vector2(12.0, 9.0), Vector2(-8.0, 13.0),
]
## 引力星盗主体：八边牌（±17,±9 / ±9,±17 切角）
const BODY_YELLOW := [
	Vector2(17.0, 9.0), Vector2(9.0, 17.0), Vector2(-9.0, 17.0),
	Vector2(-17.0, 9.0), Vector2(-17.0, -9.0), Vector2(-9.0, -17.0),
	Vector2(9.0, -17.0), Vector2(17.0, -9.0),
]
## 电浆星盗散热鳍 ×3：每枚三角 3 顶点，基边贴主体上缘
const MANES_RED := [
	Vector2(-7.0, -11.5), Vector2(-2.0, -10.3), Vector2(-6.0, -18.5),
	Vector2(0.0, -9.75), Vector2(4.0, -8.75), Vector2(1.0, -16.5),
	Vector2(6.0, -8.25), Vector2(10.0, -7.25), Vector2(8.0, -15.0),
]
## 寒霜星盗前伸传感针 ×3（尖 (−31,−7)(−33,1)(−25,13)，基边在体内侧、宽 7）
const FROST_3 := [
	Vector2(-8.0, -10.0), Vector2(-8.0, -3.0), Vector2(-31.0, -7.0),
	Vector2(-9.0, -3.5), Vector2(-9.0, 3.5), Vector2(-33.0, 1.0),
	Vector2(-8.0, 3.0), Vector2(-8.0, 10.0), Vector2(-25.0, 13.0),
]
## 引力星盗 4 状态灯（方 4×4）
const NAILS_YELLOW := [
	Vector2(-12.0, -12.0), Vector2(12.0, -12.0),
	Vector2(-12.0, 12.0), Vector2(12.0, 12.0),
]
## 光子星盗副传感器 ×4 位置与半径（主光学核之外的第二组；配 DARK 眼窝后在白身上可读）
const EYES_WHITE := [
	Vector2(-2.0, -9.0), Vector2(-2.0, 9.0),
	Vector2(6.0, 7.0), Vector2(6.0, -7.0),
]
const EYES_R := [2.5, 2.5, 2.0, 2.0]

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


## 矩形按呼吸缩放 k 绘制（位置与尺寸一起缩放）—— 精英机结构件用
static func _rect_s(ci: CanvasItem, r: Rect2, col: Color, k: float) -> void:
	ci.draw_rect(Rect2(r.position * k, r.size * k), col)


## 闭多边形描边（首尾相接）
static func _outline(ci: CanvasItem, pts: PackedVector2Array, col: Color,
		w: float) -> void:
	var ring := PackedVector2Array(pts)
	ring.append(pts[0])
	ci.draw_polyline(ring, col, w, true)


## 三角形（a/b/c 为基准顶点，k 为呼吸缩放）——散热鳍 / 传感针共用
static func _tri_batch(ci: CanvasItem, pts: Array, k: float, col: Color) -> void:
	for i in int(pts.size() / 3.0):
		var a: Vector2 = pts[i * 3]
		var b: Vector2 = pts[i * 3 + 1]
		var c: Vector2 = pts[i * 3 + 2]
		ci.draw_colored_polygon(_tri(a, b, c, k), col)


# ================================================================ 星盗
## 星盗（碰撞半径 19，主体剪影壳 ≈ r20~22；尖刺 / 顶冠为允许探出的造型）
## [param phase] 呼吸 / 抖动的实例随机相位
## [param kind]  EnemyKind.K：0 = 通用星盗；其余为独有怪。
##   本批次只落签名 —— 形参带默认值，既有调用点零改动即可编译；
##   7 种独有怪的绘制分支在 S2 接入，接入前 kind 不影响外形。
static func draw_minion(ci: CanvasItem, c: int, t: float, phase: float, kind: int = 0) -> void:
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var k: Color = Game.COLOR_CORE[c]
	var dk: Color = Game.COLOR_DARK[c]
	var s := breath(t, phase)
	var jy := tail_jitter(t, phase)

	# ① 引擎辉光（GLOW a0.12；光子型多一层外雾）
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

	# ② +X 尾 / 引擎尾焰（GLOW a0.35，必须先于主体画）
	_tails(ci, c, s, jy, Color(g.r, g.g, g.b, 0.35))

	# ②b 背负型器官（环 / 翼 / 触须 / 分身残影）：压在主体之下，独有怪才画
	if kind != 0:
		_organ_back(ci, kind, c, t, phase, s, jy, g, dk, k)

	match c:
		Game.RED:
			# ③ 机体主装甲壳外壳（主体 ×1.12）
			ci.draw_colored_polygon(_poly(BODY_RED, 1.12 * s), dk)
			# ④ 主体
			ci.draw_colored_polygon(_poly(BODY_RED, s), Color(m.r, m.g, m.b, 1.0))
			# ⑥ 通讯桅杆 + 3 散热鳍
			ci.draw_colored_polygon(_tri(Vector2(-13.0, -6.0), Vector2(-29.0, -11.0),
				Vector2(-11.0, 0.0), s), Color(g.r, g.g, g.b, 0.85))
			_tri_batch(ci, MANES_RED, s, Color(g.r, g.g, g.b, 0.85))
			# ⑦b 外突型器官（炮列）：主体之上、CORE 之前，独有怪才画
			_organ_front(ci, kind, c, s, g, dk)
			# ⑧ 主光学核 + 前向捕捉锥（CORE 最后画）
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
			# ⑥ 3 根前伸传感针（兼朝向指针）
			_tri_batch(ci, FROST_3, s, Color(g.r, g.g, g.b, 0.85))
			# ⑦b 外突型器官（炮列）：主体之上、CORE 之前，独有怪才画
			_organ_front(ci, kind, c, s, g, dk)
			# ⑧ 主光学核（MAIN 圈 + CORE 芯）
			ci.draw_arc(Vector2(-6.0, 0.0) * s, 6.5 * s, 0.0, TAU, 20, m, 3.0, true)
			ci.draw_circle(Vector2(-6.0, 0.0) * s, 4.0 * s, k)
		Game.WHITE:
			# ③ 圆壳垫底
			ci.draw_circle(Vector2.ZERO, 18.0 * s, dk)
			# ④ 主体
			ci.draw_circle(Vector2.ZERO, 17.0 * s, Color(m.r, m.g, m.b, 1.0))
			# ⑦ 4 副传感器：主光学核之外的 4 枚（GLOW —— 副传感器不得抢 CORE 白核的唯一性）。
			#   先垫 DARK 眼窝：GLOW 直画在近白 MAIN 主体上会不可读
			for i in EYES_WHITE.size():
				var ev: Vector2 = EYES_WHITE[i]
				var er: float = EYES_R[i]
				ci.draw_circle(ev * s, (er + 1.3) * s, dk)
				ci.draw_circle(ev * s, er * s, Color(g.r, g.g, g.b, 0.9))
			# ⑦b 外突型器官（炮列）：主体之上、CORE 之前，独有怪才画
			_organ_front(ci, kind, c, s, g, dk)
			# ⑧ 主光学核（朝向指针）：DARK 眼窝 -> MAIN 圈 -> CORE 芯，保证在白身上可读
			ci.draw_circle(Vector2(-9.0, -6.0) * s, 8.4 * s, dk)
			ci.draw_arc(Vector2(-9.0, -6.0) * s, 6.8 * s, 0.0, TAU, 24, m, 3.0, true)
			ci.draw_circle(Vector2(-9.0, -6.0) * s, 4.2 * s, k)
		_:
			# ③ 八边牌外壳
			ci.draw_colored_polygon(_poly(BODY_YELLOW, 1.12 * s), dk)
			# ④ 主体
			ci.draw_colored_polygon(_poly(BODY_YELLOW, s), Color(m.r, m.g, m.b, 1.0))
			# ⑤ 三横一竖（机体刻痕）
			ci.draw_line(Vector2(-2.0, -6.0) * s, Vector2(10.0, -6.0) * s, dk, 3.0, true)
			ci.draw_line(Vector2(-2.0, 0.0) * s, Vector2(10.0, 0.0) * s, dk, 3.0, true)
			ci.draw_line(Vector2(-2.0, 6.0) * s, Vector2(10.0, 6.0) * s, dk, 3.0, true)
			ci.draw_line(Vector2(4.0, -8.0) * s, Vector2(4.0, 8.0) * s, dk, 3.0, true)
			# ⑥ 2 稳定翼（上下镜像）
			ci.draw_colored_polygon(_tri(Vector2(-7.0, -17.0), Vector2(-2.0, -29.0),
				Vector2(3.0, -17.0), s), Color(g.r, g.g, g.b, 0.85))
			ci.draw_colored_polygon(_tri(Vector2(-7.0, 17.0), Vector2(-2.0, 29.0),
				Vector2(3.0, 17.0), s), Color(g.r, g.g, g.b, 0.85))
			# ⑦ 4 状态灯（GLOW —— 不与 CORE 主核抢要害指针）
			for i in NAILS_YELLOW.size():
				var pv: Vector2 = NAILS_YELLOW[i]
				var p := pv * s
				ci.draw_rect(Rect2(p.x - 2.0 * s, p.y - 2.0 * s, 4.0 * s, 4.0 * s),
					Color(g.r, g.g, g.b, 0.8))
			# ⑦b 外突型器官（炮列）：主体之上、CORE 之前，独有怪才画
			_organ_front(ci, kind, c, s, g, dk)
			# ⑧ 主核 + 指针三角
			ci.draw_circle(Vector2(-6.0, 0.0) * s, 4.0 * s, k)
			ci.draw_colored_polygon(_tri(Vector2(-17.0, 0.0), Vector2(-10.0, -4.0),
				Vector2(-10.0, 4.0), s), Color(k.r, k.g, k.b, 0.9))


## 星盗尾部：电浆 3 尾焰 / 寒霜 2 后摆鳍 / 光子 3 弧 / 引力 2 喷口
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


# ================================================================ 星盗战将
## 星盗战将（精英机，碰撞半径 34，造型 r ≤ 40，力场弧内缘 43 留 3px 呼吸）
## 独立重画的机械底盘（不再与星盗同剪影）：四色共用同一套几何，只换调色板。
## 敌我识别五条通道落点：
##   ① 无 CANOPY 舱盖色（敌方一致）；② CORE 光学窗在 −X（质心 −15.77）；
##   ③ 双联挂架在探针行 y=−30 切出两段（gap ≈ 27.9）；④ 单根下挂主炮（非对称）；
##   ⑤ 大体块（r≤40 vs 玩家 44×36、判定 r11）。
static func draw_elite(ci: CanvasItem, c: int, t: float, phase: float) -> void:
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]
	var k: Color = Game.COLOR_CORE[c]
	var dk: Color = Game.COLOR_DARK[c]
	var neu := Color(0.74, 0.78, 0.86)   # 装甲金属：四色通用结构件，不污染「颜色=属性」
	var s := breath(t, phase)
	var jy := tail_jitter(t, phase)

	# ② +X 尾 / 引擎尾焰（同母题 ×~1.25，控制在视觉上限 r40 内）
	_tails_elite(ci, c, s, jy, Color(g.r, g.g, g.b, 0.35))

	# --- 后层：双联挂架（GLOW）→ 保证探针行 y=−30 有 2 段（实测 rmax 均 ≤ 40）---
	ci.draw_colored_polygon(_poly([Vector2(-22.0, -16.0), Vector2(-12.0, -18.0),
		Vector2(-15.0, -37.0), Vector2(-20.0, -34.0)], s), Color(g.r, g.g, g.b, 0.85))  # PYLON_F 前塔（前倾）
	ci.draw_colored_polygon(_poly([Vector2(12.0, -18.0), Vector2(22.0, -16.0),
		Vector2(22.0, -33.0), Vector2(15.0, -36.0)], s), Color(g.r, g.g, g.b, 0.85))  # PYLON_R 后塔（后掠）
	# --- 后层：推进器壳 + 焰心（+X 尾）---
	_rect_s(ci, Rect2(26.0, -6.0, 10.0, 20.0), dk, s)   # THRUSTER 推进器壳
	_rect_s(ci, Rect2(34.0, -2.0, 4.0, 12.0), Color(g.r, g.g, g.b, 0.9), s)  # 焰心

	# --- 主体（MAIN 实心块，硬底线）---
	var hull_f := _poly([Vector2(-28.0, -2.0), Vector2(-12.0, -13.0),
		Vector2(6.0, -11.0), Vector2(6.0, 11.0), Vector2(-14.0, 17.0)], s)  # HULL_F 前部削尖舱（朝 −X）
	var hull_c := _poly([Vector2(2.0, -13.0), Vector2(28.0, -11.0),
		Vector2(26.0, 11.0), Vector2(4.0, 9.0)], s)                          # HULL_C 中部核心舱
	ci.draw_colored_polygon(hull_f, Color(m.r, m.g, m.b, 1.0))
	ci.draw_colored_polygon(hull_c, Color(m.r, m.g, m.b, 1.0))
	_outline(ci, hull_f, dk, 5.0)
	_outline(ci, hull_c, dk, 5.0)

	# --- 装甲 / 结构 ---
	ci.draw_colored_polygon(_poly([Vector2(-26.0, -4.0), Vector2(-12.0, -12.0),
		Vector2(-10.0, 3.0), Vector2(-24.0, 7.0)], s), dk)   # PLATE_F 前装甲板
	_rect_s(ci, Rect2(-10.0, -18.0, 12.0, 8.0), neu, s)      # SHOULDER_L 肩甲
	_rect_s(ci, Rect2(12.0, -18.0, 12.0, 8.0), neu, s)       # SHOULDER_R 肩甲
	_rect_s(ci, Rect2(-10.0, 13.0, 8.0, 15.0), dk, s)        # LEG_L 悬浮支架
	_rect_s(ci, Rect2(8.0, 13.0, 8.0, 15.0), dk, s)           # LEG_R
	_rect_s(ci, Rect2(-11.0, 26.0, 10.0, 4.0), Color(g.r, g.g, g.b, 0.9), s)  # FOOT_L 支架末端
	_rect_s(ci, Rect2(7.0, 26.0, 10.0, 4.0), Color(g.r, g.g, g.b, 0.9), s)   # FOOT_R

	# --- 武器：单根下挂主炮（外露 + 非对称 = 通道④）---
	_rect_s(ci, Rect2(-36.0, 4.0, 22.0, 8.0), neu, s)        # CANNON
	_rect_s(ci, Rect2(-38.0, 5.0, 4.0, 6.0), Color(g.r, g.g, g.b, 0.9), s)   # CANNON_M 炮口焰

	# --- 光学传感器（CORE，唯一 CORE 用途 = 通道②依据，最后画）---
	_rect_s(ci, Rect2(-22.0, 0.0, 9.0, 6.0), k, s)           # OPTIC_M 主光学窗
	_rect_s(ci, Rect2(-10.0, 2.0, 4.0, 3.0), k, s)           # OPTIC_S 副光学窗


## 星盗战将尾部：星盗同母题 ×~1.25（再大会捅穿力场弧内缘 43）
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


# ================================================================ 独有怪器官
## 中性装甲金属灰（材质色，零新增语义；绝不用作 ④ 主体实心块）
const NEUTRAL := Color(0.74, 0.78, 0.86)

## ②b 背负型器官：环 / 翼 / 触须 / 分身残影（压在主体之下，独有怪才画）
## 层序铁律：器官画在 ② 尾之后、③ 外壳之前；绝对禁止画到 ⑧ CORE 之后。
static func _organ_back(ci: CanvasItem, kind: int, c: int, t: float, phase: float,
		s: float, jy: float, g: Color, dk: Color, k: Color) -> void:
	var glow := Color(g.r, g.g, g.b, 0.85)
	match kind:
		EnemyKind.K.DISMANTLER:
			_organ_ring(ci, t, s, glow, k)
		EnemyKind.K.DEFECTOR:
			_organ_wings(ci, t, phase, s, g, dk)
		EnemyKind.K.LAYER:
			_organ_tentacles(ci, t, s, g, dk)
		EnemyKind.K.SIPHON:
			_organ_tubes(ci, t, s, g, dk)
		EnemyKind.K.MARTYR:
			_organ_trail(ci, t, phase, s, g)
		EnemyKind.K.PHASER:
			_organ_phantoms(ci, t, phase, s, g)


## ⑦b 外突型器官：炮列（主体之上、CORE 之前；仅列阵者）
static func _organ_front(ci: CanvasItem, kind: int, _c: int, s: float, g: Color,
		_dk: Color) -> void:
	if kind != EnemyKind.K.PHALANX:
		return
	# 短炮 ×2（−X 侧舷上下，中轴留空让开 CORE ±15° 扇区）
	# 3 艘成墙时，同批同色的三艘炮口在同一垂直线上连成弹幕墙
	var neu := NEUTRAL
	ci.draw_rect(Rect2(-20.0 * s, -13.0 * s, 4.0 * s, 9.0 * s), neu)
	ci.draw_rect(Rect2(-20.0 * s, 4.0 * s, 4.0 * s, 9.0 * s), neu)
	ci.draw_rect(Rect2(-24.0 * s, -12.0 * s, 4.0 * s, 3.0 * s), Color(g.r, g.g, g.b, 0.9))
	ci.draw_rect(Rect2(-24.0 * s, 5.0 * s, 4.0 * s, 3.0 * s), Color(g.r, g.g, g.b, 0.9))


## ① 拆解者 · 环：锯齿拆解环 ×1，缺口朝 +X，顺时针 1.4 rad/s；环外 6 枚锯齿
static func _organ_ring(ci: CanvasItem, t: float, s: float, glow: Color, k: Color) -> void:
	var rot := t * 1.4
	var r := 31.0 * s
	var gap := 0.10 * PI
	var pts := PackedVector2Array()
	var seg := 28
	for i in seg:
		var a := TAU * float(i) / float(seg)
		if a < gap or a > TAU - gap:
			continue
		var p := Vector2(cos(a), sin(a)) * r
		p = p.rotated(rot)
		pts.append(p)
	ci.draw_polyline(pts, glow, 4.0, true)
	# 环外 6 枚锯齿（小三角，随环旋转）
	for i in 6:
		var a := TAU * float(i) / 6.0 + rot
		var base := Vector2(cos(a), sin(a)) * r
		var tip := Vector2(cos(a), sin(a)) * (r + 5.0)
		var perp := Vector2(-sin(a), cos(a)) * 2.5
		ci.draw_colored_polygon(PackedVector2Array([base - perp, base + perp, tip]), glow)
	# CORE 描边：仅描器官外缘 1px（要害指针语法，不抢主体 CORE 唯一性）
	ci.draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 32, Color(k.r, k.g, k.b, 0.55), 1.0, true)


## ② 变节者 · 翼：±Y 各一片棱晶折面翼，翼尖朝 +X，后掠；换色折射闪（≤2Hz）
static func _organ_wings(ci: CanvasItem, t: float, phase: float, s: float, g: Color,
		dk: Color) -> void:
	var pulse := 0.6 + 0.3 * sin(t * 5.0 + phase)   # ≤2Hz 折射闪
	var col := Color(g.r, g.g, g.b, pulse)
	for i in 2:
		var sgn: float = -1.0 + 2.0 * float(i)
		var r0 := Vector2(4.0, -8.0 * sgn) * s
		var r1 := Vector2(17.0, -13.0 * sgn) * s
		var tip := Vector2(30.0, -18.0 * sgn) * s
		var inner := Vector2(15.0, -5.0 * sgn) * s
		ci.draw_colored_polygon(PackedVector2Array([r0, r1, tip, inner]), col)
		# 折面刻痕（读作 3 段折面）
		ci.draw_line(r1, Vector2(24.0, -15.0 * sgn) * s, dk, 1.5, true)


## ④ 敷设者 · 触须：4 条自 +X 侧根部向 +Y 下垂，末端各挂 1 枚雷（细 2px）
static func _organ_tentacles(ci: CanvasItem, t: float, s: float, g: Color, dk: Color) -> void:
	var glow := Color(g.r, g.g, g.b, 0.85)
	var sway := sin(t * 2.0) * 2.0
	for i in 4:
		var bx: float = 8.0 + 5.0 * float(i)
		var by: float = -5.0 + 3.3 * float(i)
		var root := Vector2(bx, by) * s
		var mid := Vector2(bx + 8.0 + sway, by + 13.0) * s
		var tip := Vector2(bx + 4.0 + sway, by + 26.0) * s
		ci.draw_polyline(PackedVector2Array([root, mid, tip]), glow, 2.0, true)
		# 末端挂雷：DARK 底 + GLOW 环
		ci.draw_circle(tip, 3.5 * s, dk)
		ci.draw_arc(tip, 5.0 * s, 0.0, TAU, 14, glow, 1.5, true)


## ⑤ 虹吸者 · 触须（次级区分：2 条中空虹吸管向 −Y 上扬，粗 4px，末端喇叭口）
static func _organ_tubes(ci: CanvasItem, t: float, s: float, g: Color, dk: Color) -> void:
	var glow := Color(g.r, g.g, g.b, 0.85)
	var sway := sin(t * 2.4) * 2.0
	for i in 2:
		var sgn: float = -1.0 + 2.0 * float(i)
		var bx: float = 6.0
		var by: float = 3.0 * sgn
		var bot := Vector2(bx - 2.0, by) * s
		var top := Vector2(bx + 4.0 + sway, by - 26.0) * s
		# 中空管：两条平行线成管（粗 4px + 内芯 2px）
		ci.draw_line(bot, top, glow, 4.0, true)
		ci.draw_line(bot + Vector2(3.0, 0.0) * s, top + Vector2(3.0, 0.0) * s, glow, 2.0, true)
		# 末端喇叭口（三角 6×6）
		var horn := Vector2(top.x, top.y - 6.0)
		ci.draw_colored_polygon(PackedVector2Array([top - Vector2(3.0, 0.0) * s,
			top + Vector2(3.0, 0.0) * s, horn]), glow)


## ⑥ 殉爆者 · 分身（次级区分：1 条正后方 +X 拖影，α0.45，呼吸滞后 0.08s 紧跟）
static func _organ_trail(ci: CanvasItem, t: float, phase: float, s: float, g: Color) -> void:
	var lag := breath(t - 0.08, phase)
	var p := Vector2(26.0, 0.0) * s * lag
	var col := Color(g.r, g.g, g.b, 0.45)
	var hx := _poly([Vector2(-9.0, -7.0), Vector2(2.0, -5.0), Vector2(6.0, 0.0),
		Vector2(2.0, 5.0), Vector2(-9.0, 7.0)], 1.0)
	for j in hx.size():
		hx[j] = hx[j] + p
	ci.draw_colored_polygon(hx, col)


## ⑦ 相位者 · 分身（次级区分：2 条 ±Y 闪影，α0.28，呼吸滞后 0.25s 松散）
static func _organ_phantoms(ci: CanvasItem, t: float, phase: float, s: float,
		g: Color) -> void:
	var col := Color(g.r, g.g, g.b, 0.28)
	for i in 2:
		var sgn: float = -1.0 + 2.0 * float(i)
		var lag := breath(t - 0.25, phase + sgn * 0.5)
		var p := Vector2(0.0, 30.0 * sgn) * s * lag
		var hx := PackedVector2Array()
		hx.append(p + Vector2(-6.0, -5.0))
		hx.append(p + Vector2(3.0, -4.0))
		hx.append(p + Vector2(7.0, 0.0))
		hx.append(p + Vector2(3.0, 4.0))
		hx.append(p + Vector2(-6.0, 5.0))
		ci.draw_colored_polygon(hx, col)
