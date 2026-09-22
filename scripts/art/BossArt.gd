class_name BossArt
extends RefCounted
## ---------------------------------------------------------------
## BossArt —— 五个旗舰的矢量绘制（纯静态，与 `PirateArt` 同构）
##
## 规格来源：`design/art/01-五关视觉差异化规格.md` §C
##   （C.0 三条跨 Boss 统一决定 / C.1 规格总表 / C.2 逐个规格）。本文件不自拟数值。
##
##   · 朝向沿用全项目语法：**−X 是头（要害扇区），+X 是尾**。
##     五个旗舰的 CORE 要害核一律落在中轴偏 −X 处，不得挪到 +X。
##   · 层序由 `Boss._draw()` 编排，本文件只提供各层的画法：
##     ① 气息 → ②b 背负器官（环 / 翼 / 触须 / 残影）→ ③④ 本体
##     → ⑦b 外突器官（L3 炮列）→ 机制联动 → 覆盖层（狂暴 / 护罩 / 白闪）。
##   · 尺寸：主半径 `R_MAIN` 走 `StageCfg.boss_r_main(stage)`（56/63/70/77/84）。
##     **本文件不复制这张表**，所有器官尺寸一律 `r × 系数`（§C.0-2），
##     这样改一个半径不会牵动十几处硬编码。
##   · 每关一块不透明 MAIN 实心块是硬底线（玩家靠高饱和 MAIN 面积判断"该换哪件战甲"）；
##     L5 是唯一例外 —— 它的本体是**中性钢灰**（不绑定四色），四色只在能量纹上轮转。
##   · 状态读取一律走 `Object.get()` 字符串访问：BossArt **不 import Boss / Boss4**
##     （循环依赖），L4 子核心的私有状态（`_cores` / `_exposed_win` / `_summon_t`）也这样读，
##     读不到就降级画基础形态 —— 与 HUD 读 `venting` 同一模式。
##   · 可访问性（§E）：
##     - L3「常驻减伤暗甲壳弧」与「护罩弧」三处全反：DARK vs MAIN / 静止 vs 游走 / 断续 vs 连续；
##     - 狂暴不只有泛红光：L1 环缺口加大 + 加速、L2 翼尖霜刃、L4 触须红覆描、
##       L5 残影 α 0.30→0.55 + 12 段血色虚线环（形状 / 明度通道）；
##     - 狂暴另有 6 枚**三角**符标（vs 常态圆点），见 `Boss._draw()`（§E.2）；
##     - 所有周期性闪烁 ≤ 2Hz（A1 光敏安全）。
##   · ⚠️ 全绘制函数禁止出现 CANOPY 舱盖色 (0.62,0.86,0.98) —— 星盗没有驾驶舱。
## ---------------------------------------------------------------

# ================================================================ 常量
## 装甲金属（四色通用结构件，不污染「颜色 = 属性」）
const NEUTRAL := Color(0.74, 0.78, 0.86)
const NEUTRAL_DK := Color(0.24, 0.27, 0.34)
## L5 终焉号本体：中性亮钢灰（不绑定四色）+ 它的暗部 / 外发光
const STEEL := Color(0.62, 0.66, 0.74)
const STEEL_DARK := Color(0.17, 0.19, 0.26)
const STEEL_GLOW := Color(0.84, 0.88, 0.96)
## 血色（狂暴 / 断裂的通用告警色）
const RAGE := Color(1.00, 0.28, 0.18)

## 逐关本体主色（§C.1）：0=RED 1=BLUE 2=WHITE 3=YELLOW；**-1 = 中性钢灰**（L5 不绑定四色）。
##   裸 int 而非 `Game.RED` 枚举 —— 本文件既有坑：枚举 / 单例成员进不了推断数组。
const _MAIN_C := [2, 1, 0, 3, -1]
## 逐关能量纹色（§C.1）：仅 L4 = RED（引力黄本体 + 电浆红能量纹）；其余 -1 = 无
const _ACCENT_C := [-1, -1, -1, 0, -1]

# ---- 本体剪影（单位半径 1 = R_MAIN，运行时乘 r）----
## L1 熔核号：正六边核心舱（对称无尖角）
const SIL_CORE := [
	Vector2(1.00, 0.0), Vector2(0.50, 0.866), Vector2(-0.50, 0.866),
	Vector2(-1.00, 0.0), Vector2(-0.50, -0.866), Vector2(0.50, -0.866),
]
## L2 霜噬号：菱形舰体（−X 略尖，+X 钝）
const SIL_WING := [
	Vector2(-1.00, 0.0), Vector2(-0.34, -0.46), Vector2(0.30, -0.58),
	Vector2(0.84, -0.26), Vector2(0.84, 0.26), Vector2(0.30, 0.58),
	Vector2(-0.34, 0.46),
]
## L3 耀斑号：长方形炮垒（纵向长，−X 舷留给一列炮塔）
const SIL_BATTERY := [
	Vector2(-0.78, -0.92), Vector2(0.42, -0.96), Vector2(0.76, -0.58),
	Vector2(0.76, 0.58), Vector2(0.42, 0.96), Vector2(-0.78, 0.92),
]
## L4 深渊之喉：宽厚六边母舰（−X 侧开深渊之口）
const SIL_MAW := [
	Vector2(-0.58, -0.70), Vector2(0.34, -0.92), Vector2(0.94, -0.36),
	Vector2(0.94, 0.36), Vector2(0.34, 0.92), Vector2(-0.58, 0.70),
]
## L5 终焉号：纺锤形（−X 尖、+X 钝）
const SIL_THRONE := [
	Vector2(-1.02, 0.0), Vector2(-0.52, -0.30), Vector2(0.10, -0.44),
	Vector2(0.66, -0.32), Vector2(0.80, 0.0), Vector2(0.66, 0.32),
	Vector2(0.10, 0.44), Vector2(-0.52, 0.30),
]

# ================================================================ 状态读取
## BossArt 只认 `Node2D`，一切状态走 `Object.get()` 字符串访问 —— 不 import
## `Boss` / `Boss4`，既避开循环依赖，也让「字段缺失」降级成「画基础形态」而不是崩绘制。
static func _gi(b: Node2D, key: String, dflt: int) -> int:
	if b == null or not is_instance_valid(b):
		return dflt
	var v: Variant = b.get(key)
	if v is int or v is float:
		return int(v)
	return dflt


static func _gf(b: Node2D, key: String, dflt: float) -> float:
	if b == null or not is_instance_valid(b):
		return dflt
	var v: Variant = b.get(key)
	if v is int or v is float:
		return float(v)
	return dflt


static func _gb(b: Node2D, key: String) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var v: Variant = b.get(key)
	return v is bool and bool(v)


## 主半径 R_MAIN（56/63/70/77/84）—— 本文件一切尺寸的基准
static func r_main_of(b: Node2D) -> float:
	return float(StageCfg.boss_r_main(_gi(b, "stage", 1)))


## 本关本体主色；-1 = 中性钢灰
static func boss_main_c(s: int) -> int:
	var i := clampi(s, 1, StageCfg.STAGE_N) - 1
	var v: int = _MAIN_C[i]
	return v


## 本关能量纹色；-1 = 无能量纹
static func boss_accent_c(s: int) -> int:
	var i := clampi(s, 1, StageCfg.STAGE_N) - 1
	var v: int = _ACCENT_C[i]
	return v


static func main_col(c: int) -> Color:
	return STEEL if c < 0 else Game.COLOR_MAIN[c]


static func glow_col(c: int) -> Color:
	return STEEL_GLOW if c < 0 else Game.COLOR_GLOW[c]


static func core_col(c: int) -> Color:
	return Color(1.0, 1.0, 1.0) if c < 0 else Game.COLOR_CORE[c]


static func dark_col(c: int) -> Color:
	return STEEL_DARK if c < 0 else Game.COLOR_DARK[c]


## 换色预告中：护罩展开着 + 剩余时长已进预告窗（§C.2-L1「环由连续弧变 8 段虚线弧」）
##   读不到 `_ward_tell` / `_ward_t`（非 Boss 实例）时恒 false —— 降级成"不预告"。
static func _is_tell(b: Node2D) -> bool:
	var tell := _gf(b, "_ward_tell", 0.0)
	if tell <= 0.0:
		return false
	if _gi(b, "ward", -1) < 0:
		return false
	return _gf(b, "_ward_t", 99.0) <= tell


# ================================================================ 几何工具
## 单位剪影 × r
static func _poly(base: Array, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(base.size())
	for i in base.size():
		var p: Vector2 = base[i]
		out[i] = p * r
	return out


## 闭多边形描边（首尾相接）
static func _outline(ci: Node2D, pts: PackedVector2Array, col: Color, w: float) -> void:
	var ring := PackedVector2Array(pts)
	ring.append(pts[0])
	ci.draw_polyline(ring, col, w, true)


## 断续弧（段间 gap 弧度缺口）—— 护罩弧 / 暗甲壳弧 / 血色虚线环共用
## [param segs] 段数　[param gap] 段间缺口（弧度）　[param off] 起始角（游走用）
## [param span] 总跨度；< TAU 时留一个大缺口（L1 环缺口 / L3 散热缺口都靠它）
static func _dash_arc(ci: Node2D, rad: float, col: Color, w: float, segs: int,
		gap: float, off: float, span: float = TAU) -> void:
	var step := span / float(segs)
	for i in segs:
		var a0 := off + float(i) * step + gap * 0.5
		var a1 := off + float(i + 1) * step - gap * 0.5
		if a1 <= a0:
			continue
		ci.draw_arc(Vector2.ZERO, rad, a0, a1, 12, col, w, true)


## 要害核（CORE）：DARK 眼窝 -> CORE 芯 -> 纯白高光。
##   白身上（L1）也读得出，靠的就是这圈 DARK 眼窝 —— 五个旗舰共用同一读法。
static func _core_socket(ci: Node2D, r: float, c: int, pulse: float, ox: float) -> void:
	var dk := dark_col(c)
	var k := core_col(c)
	var cr := r * 0.20 + 1.6 * pulse
	ci.draw_circle(Vector2(ox, 0.0), cr + r * 0.07, dk)
	ci.draw_circle(Vector2(ox, 0.0), cr, k)
	ci.draw_circle(Vector2(ox, 0.0), cr * 0.42, Color(1.0, 1.0, 1.0, 0.9))


# ================================================================ 分派
## ②b 背负型标志器官（压在主体之下）
static func draw_sig_back(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		1:
			_l1_rings(b, pulse)
		2:
			_l2_wings(b, pulse)
		4:
			_l4_tentacles(b, pulse)
		5:
			_l5_echoes(b, pulse)
		_:
			pass        # L3 的炮列是外突型器官，画在 ⑦b


## ③④ 本体（五关剪影各不相同）
static func draw_body(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		1:
			draw_core(b, pulse)
		2:
			draw_wing(b, pulse)
		3:
			draw_battery(b, pulse)
		4:
			draw_maw(b, pulse)
		_:
			draw_throne(b, pulse)


## ⑦b 外突型标志器官（主体之上、CORE 之前）
static func draw_sig_front(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		3:
			_l3_guns(b, pulse)
		_:
			pass


## 机制联动（C.2 每个 Boss 的「机制 → 视觉」通道）
static func draw_mechanic(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		3:
			_l3_shell(b, pulse)
		4:
			_l4_tethers(b, pulse)
		5:
			_l5_rage_ring(b, pulse)
		_:
			pass        # L1 的换色预告已在环上表达（_l1_rings 读 _is_tell）


## 本体外缘描边（护罩开启时 2px CORE 白描边 —— §E.1 边缘通道）
static func draw_body_rim(b: Node2D, col: Color, w: float) -> void:
	var r := r_main_of(b)
	_outline(b, _poly(_sil(_gi(b, "stage", 1)), r), col, w)


static func _sil(st: int) -> Array:
	match st:
		1:
			return SIL_CORE
		2:
			return SIL_WING
		3:
			return SIL_BATTERY
		4:
			return SIL_MAW
		_:
			return SIL_THRONE


# ================================================================ L1 熔核号 · 环
## 匀速自转的熔炉冷却环：**环色 = 当前 ward 色，环就是护罩指示器**（§C.2-L1）。
##   · 环半径 ×1.28、环宽 5px、缺口朝 +X、3 枚 CORE 符点顺时针 1.1 rad/s
##   · 相②：加第 2 圈（×1.45，逆向自转）
##   · 换色预告（1.5s）：连续弧 → 8 段虚线弧 + 加速旋转
##   · 狂暴：缺口加大 + 自转角速度 ×1.8
static func _l1_rings(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var ward: int = _gi(b, "ward", -1)
	var tell := _is_tell(b)
	# ward < 0（护罩未启）回落到光子白 —— 环不能变成"无色的环"
	var rc := Game.WHITE if ward < 0 else ward
	var col: Color = Game.COLOR_MAIN[rc]
	var kcol: Color = Game.COLOR_CORE[rc]
	var spd := 1.1
	if tell:
		spd *= 2.2
	if rage:
		spd *= 1.8
	var spin := t * spd
	var gap := 0.90 if rage else 0.50
	var span := TAU - gap
	var r1 := r * 1.28
	if tell:
		_dash_arc(b, r1, col, 5.0, 8, 0.16, spin, span)
	else:
		b.draw_arc(Vector2.ZERO, r1, spin + gap * 0.5, spin + span + gap * 0.5,
			44, col, 5.0, true)
	# 环上 3 枚符点（顺时针 1.1 rad/s）
	for i in 3:
		var a := spin + TAU * float(i) / 3.0
		b.draw_circle(Vector2.RIGHT.rotated(a) * r1, 4.6, kcol)
	# 相②：第 2 圈 ×1.45，逆向自转
	if ph >= 2:
		var r2 := r * 1.45
		if tell:
			_dash_arc(b, r2, col, 4.0, 8, 0.16, -spin * 1.2, span)
		else:
			b.draw_arc(Vector2.ZERO, r2, -spin + gap * 0.5,
				-spin + span + gap * 0.5, 44, col, 4.0, true)


## L1 本体：正六边核心舱（光子白，本体恒白；NEUTRAL 结构件 20%）
static func draw_core(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(1)
	var m := main_col(c)
	var g := glow_col(c)
	var dk := dark_col(c)
	# ③ DARK 外壳（×1.07）
	b.draw_colored_polygon(_poly(SIL_CORE, r * 1.07), dk)
	# ④ MAIN 主体（硬底线：不透明 MAIN 实心块）
	b.draw_colored_polygon(_poly(SIL_CORE, r), m)
	# ⑤ NEUTRAL 结构件：6 条辐条 + 内框六边
	_outline(b, _poly(SIL_CORE, r * 0.62), NEUTRAL, 2.0)
	for i in 6:
		var a := TAU * float(i) / 6.0
		b.draw_line(Vector2.RIGHT.rotated(a) * (r * 0.62),
			Vector2.RIGHT.rotated(a) * (r * 0.95), NEUTRAL, 2.0, true)
	# ⑥ 熔炉辉环（GLOW，读作"炉子在烧"）
	b.draw_arc(Vector2.ZERO, r * 0.40, 0.0, TAU, 28, Color(g.r, g.g, g.b, 0.55),
		4.0, true)
	# ⑧ CORE 要害核
	_core_socket(b, r, c, pulse, -r * 0.16)


# ================================================================ L2 霜噬号 · 翼
## 两侧三段霜晶折翼：翼根在 ±Y、翼尖朝 **+X**（−X 是要害指针，不许再往前加尖出物）。
##   · 展开角随阶段 25° → 55° → 80°（收拢 = 窗口关闭，全展 = 窗口打开）
##   · 只有 L2 是 `WardMode.NONE` —— **永不画护罩弧**，开合节拍就是它的窗口语言
##   · 狂暴：翼尖各伸出 4 枚 GLOW 三角霜刃（共 8 枚），随呼吸同步张合
static func _l2_wings(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(2)
	var g := glow_col(c)
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var deg := 25.0
	if ph >= 3:
		deg = 80.0
	elif ph == 2:
		deg = 55.0
	# 翼随呼吸同步张合（±4°，0.35Hz —— 远低于 2Hz 光敏线）
	var beat := sin(t * 2.2) * deg_to_rad(4.0)
	var spread := deg_to_rad(deg) + beat
	for k in 2:
		var sg: float = -1.0 + 2.0 * float(k)
		var a := sg * spread
		var dir := Vector2.RIGHT.rotated(a)
		var perp := dir.rotated(PI * 0.5)
		var root := Vector2(-0.16 * r, sg * 0.50 * r)
		var j1 := root + dir * (r * 0.32) - perp * (sg * 0.06 * r)
		var j2 := root + dir * (r * 0.62) + perp * (sg * 0.06 * r)
		var tip := root + dir * (r * 0.85)
		var w1 := r * 0.24
		var w2 := r * 0.16
		# 翼膜（GLOW α0.55）+ 翼骨（NEUTRAL）
		var memb := PackedVector2Array([root, j1 + perp * w1, j2 + perp * w2,
			tip, j2 - perp * w2 * 0.70, j1 - perp * w1 * 0.70])
		b.draw_colored_polygon(memb, Color(g.r, g.g, g.b, 0.55))
		b.draw_polyline(PackedVector2Array([root, j1, j2, tip]), NEUTRAL, 4.0, true)
		if not rage:
			continue
		# 狂暴：翼尖 4 枚 GLOW 三角霜刃（两侧共 8 枚）
		var open := 0.75 + 0.25 * sin(t * 2.2)
		for i in 4:
			var aa := a + (-0.34 + 0.22 * float(i)) * open
			var d := Vector2.RIGHT.rotated(aa)
			var p0 := tip + d * (r * 0.05)
			var p1 := tip + d * (r * 0.26)
			var pw := d.rotated(PI * 0.5) * (r * 0.055)
			b.draw_colored_polygon(PackedVector2Array([p0 + pw, p1, p0 - pw]),
				Color(g.r, g.g, g.b, 0.9))


## L2 本体：菱形舰体（寒霜蓝 + NEUTRAL 25%）；甲板散热面随翼展开露出更多 GLOW
static func draw_wing(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(2)
	var m := main_col(c)
	var g := glow_col(c)
	var dk := dark_col(c)
	var ph := _gi(b, "phase", 1)
	b.draw_colored_polygon(_poly(SIL_WING, r * 1.07), dk)
	b.draw_colored_polygon(_poly(SIL_WING, r), m)
	# ⑤ 结构线 ×2（寒霜四色结构线语言，§E.5 硬约束：器官不得覆盖它）
	b.draw_line(Vector2(-0.34, -0.46) * r, Vector2(0.55, -0.10) * r, dk, 2.0, true)
	b.draw_line(Vector2(-0.34, 0.46) * r, Vector2(0.55, 0.10) * r, dk, 2.0, true)
	# 甲板散热面：展开度越高露得越多（= "窗口打开"的形状读数）
	var open := clampf(float(ph - 1) / 2.0, 0.0, 1.0)
	for i in 2:
		var yy: float = (-0.22 + 0.44 * float(i)) * r
		b.draw_rect(Rect2(-0.52 * r, yy - r * 0.06, 0.62 * r, 0.12 * r),
			Color(g.r, g.g, g.b, 0.18 + 0.45 * open))
	# ⑧ CORE 要害核
	_core_socket(b, r, c, pulse, -r * 0.30)


# ================================================================ L3 耀斑号 · 炮列
## −X 舷一列炮塔（4 / 6 / 8 门随阶段，中轴留空让开 CORE），炮管 NEUTRAL、炮口 GLOW。
##   散热期：全部炮口喷 GLOW 焰 —— 与「甲壳缺口 + 白光」一起构成三重冗余。
static func _l3_guns(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(3)
	var g := glow_col(c)
	var ph := _gi(b, "phase", 1)
	var vent := _gb(b, "venting")
	var n := 4
	if ph >= 3:
		n = 8
	elif ph == 2:
		n = 6
	var half := n / 2
	for j in half:
		var off: float = (0.20 + 0.22 * float(j)) * r
		for k in 2:
			var sg: float = -1.0 + 2.0 * float(k)
			_turret(b, r, sg * off, g, vent)


## 单门炮塔：炮塔座 + 炮管 + 炮口（散热期喷焰）
static func _turret(ci: Node2D, r: float, y: float, g: Color, vent: bool) -> void:
	var bx := -0.78 * r
	ci.draw_rect(Rect2(bx - r * 0.16, y - r * 0.055, r * 0.20, r * 0.11), NEUTRAL)
	ci.draw_circle(Vector2(bx - r * 0.18, y), r * 0.055, Color(g.r, g.g, g.b, 0.95))
	if vent:
		ci.draw_circle(Vector2(bx - r * 0.32, y), r * 0.13,
			Color(g.r, g.g, g.b, 0.30))
		ci.draw_circle(Vector2(bx - r * 0.24, y), r * 0.075,
			Color(g.r, g.g, g.b, 0.90))


## L3 三态（§C.2-L3 / §E.4）—— 与「护罩弧」在**颜色 / 运动 / 断续形态三处全反**：
##   常驻减伤 70% = 8 段断续暗甲壳弧、`COLOR_DARK`、**静止不游走**、半径 ×1.80
##   散热期       = 裂开 1.2 rad 大缺口，缺口固定朝 −X（正对玩家），缺口内露 CORE 白光
##   （对照）护罩 = MAIN 色、连续…这里 L2/L3 是 `WardMode.NONE`，永不展护罩
static func _l3_shell(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(3)
	var dk: Color = Game.COLOR_DARK[c]
	var vent := _gb(b, "venting")
	var rad := r * 1.80
	if not vent:
		_dash_arc(b, rad, dk, 7.0, 8, 0.16, 0.0)
		return
	# 散热期：缺口固定朝 −X（PI ± 0.6 = 1.2 rad）
	var g0 := PI - 0.6
	var g1 := PI + 0.6
	for i in 8:
		var a0 := TAU * float(i) / 8.0 + 0.08
		var a1 := TAU * float(i + 1) / 8.0 - 0.08
		if a1 > g0 and a0 < g1:
			continue
		b.draw_arc(Vector2.ZERO, rad, a0, a1, 12, dk, 7.0, true)
	# 缺口内的 CORE 白光：白弧 + 朝 −X 的楔形辉光（"现在能打疼"的方向指示）
	var kw: Color = Game.COLOR_CORE[Game.WHITE]
	b.draw_arc(Vector2.ZERO, rad, g0, g1, 20,
		Color(kw.r, kw.g, kw.b, 0.50 + 0.30 * pulse), 9.0, true)
	var w0 := Vector2.RIGHT.rotated(g0) * rad
	var w1 := Vector2.RIGHT.rotated(g1) * rad
	b.draw_colored_polygon(PackedVector2Array([w0, Vector2(-r * 1.05, 0.0), w1]),
		Color(kw.r, kw.g, kw.b, 0.16))


## L3 本体：长方形炮垒（电浆红 + NEUTRAL 30%，**强制 ≥3px CORE 白描边** ——
##   红对比仅 2.38:1 的补偿；红本体在没有描边时会与暗背景糊成一片）
static func draw_battery(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(3)
	var m := main_col(c)
	var g := glow_col(c)
	var dk := dark_col(c)
	var sil := _poly(SIL_BATTERY, r)
	b.draw_colored_polygon(_poly(SIL_BATTERY, r * 1.06), dk)
	b.draw_colored_polygon(sil, m)
	_outline(b, sil, core_col(Game.WHITE), 3.0)
	# ⑤ NEUTRAL 结构件 30%：横向装甲带 ×3
	for i in 3:
		var yy: float = (-0.55 + 0.55 * float(i)) * r
		b.draw_rect(Rect2(-0.62 * r, yy, 1.28 * r, 0.07 * r), NEUTRAL)
	# +X 推进舱（NEUTRAL 壳 + GLOW 焰心）
	b.draw_rect(Rect2(0.60 * r, -0.28 * r, 0.28 * r, 0.56 * r), NEUTRAL)
	b.draw_rect(Rect2(0.86 * r, -0.14 * r, 0.16 * r, 0.28 * r),
		Color(g.r, g.g, g.b, 0.85))
	# ⑧ CORE 要害核（中轴留空给炮列让位）
	_core_socket(b, r, c, pulse, -r * 0.10)


# ================================================================ L4 深渊之喉 · 触须
## 子核心的**局部坐标**列表（Boss4 的 `_cores` 是私有字段，用 `Object.get()` 读；
##   读不到 / 字段改名 → 返回空数组，触须降级画自由摆动的基础形态，不会崩绘制）
static func _sub_core_local(b: Node2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if b == null or not is_instance_valid(b):
		return out
	var v: Variant = b.get("_cores")
	if not (v is Array):
		return out
	var arr: Array = v
	for core in arr:
		if core == null or not is_instance_valid(core):
			continue
		var dv: Variant = core.get("dead")
		if dv is bool and bool(dv):
			continue
		var pv: Variant = core.get("position")
		if pv is Vector2:
			out.append((pv as Vector2) - b.position)
	return out


## 6 条牵引触须（2 / 4 / 6 随阶段）：DARK 打底 3px + GLOW α0.50 覆描 1.5px。
##   · **全部布在 +X 与 ±Y 半侧，绝不进入 −X ±40° 要害扇区**（那里坐着 CORE 与深渊之口）
##   · 子核心存活 → 绷紧成张紧直线（能量索见 `_l4_tethers`）
##   · 暴露期 → 断裂回缩（短一截 + 断口 + 缩回）
##   · 召唤预告（CD 尾 0.4s）→ 触须整体前伸 6px
static func _l4_tentacles(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var g := glow_col(c)
	var dk: Color = Game.COLOR_DARK[c]
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var exposed := _gb(b, "_exposed_win")
	var n := 2
	if ph >= 3:
		n = 6
	elif ph == 2:
		n = 4
	var cores := _sub_core_local(b)
	var tense := (not cores.is_empty()) and (not exposed)
	# 召唤预告：Boss4 的 `_summon_t` 走到 0.4s 内 → 整体前伸 6px（读不到就 0）
	var summon_t := _gf(b, "_summon_t", 99.0)
	var ext := 6.0 if summon_t <= 0.4 else 0.0
	var rage_c: Color = Game.COLOR_MAIN[Game.RED]
	for i in n:
		var a := -PI * 0.72 + (PI * 1.44) * (float(i) / float(maxi(1, n - 1)))
		if tense and i < cores.size():
			var cp: Vector2 = cores[i]
			a = cp.angle()
		var curl := 0.30 if (i % 2 == 0) else -0.30
		if tense and i < cores.size():
			curl = 0.0                      # 绷紧 = 直线
		var p0 := Vector2.RIGHT.rotated(a) * (r * 0.72)
		if exposed:
			# 暴露期：能量索已断 —— 短一截 + 断口空隙 + 缩回的残端
			var b1 := Vector2.RIGHT.rotated(a + curl * 0.3) * (r * 0.92)
			var b2 := Vector2.RIGHT.rotated(a + curl * 0.5) * (r * 1.02)
			b.draw_polyline(PackedVector2Array([p0, b1]), dk, 6.0, true)
			b.draw_polyline(PackedVector2Array([p0, b1]),
				Color(g.r, g.g, g.b, 0.35), 3.0, true)
			b.draw_polyline(PackedVector2Array([b2,
				Vector2.RIGHT.rotated(a + curl * 0.7) * (r * 1.14)]),
				dk, 5.0, true)
			continue
		var p1 := Vector2.RIGHT.rotated(a + curl * 0.35) * (r * 1.00 + ext)
		var p2 := Vector2.RIGHT.rotated(a + curl * 0.70) * (r * 1.28 + ext)
		var jy := sin(t * 5.0 + float(i)) * 2.0      # 末端 ±2px 抖动
		var tip := Vector2.RIGHT.rotated(a + curl) * (r * 1.55 + ext)
		tip.y += jy
		var pts := PackedVector2Array([p0, p1, p2, tip])
		b.draw_polyline(pts, dk, 6.0, true)
		b.draw_polyline(pts, Color(g.r, g.g, g.b, 0.70), 3.5, true)
		if rage:
			# 狂暴：触须全部亮起电浆红覆描 + 末端血色符点
			b.draw_polyline(pts, Color(rage_c.r, rage_c.g, rage_c.b, 0.80),
				1.6, true)
			b.draw_circle(tip, r * 0.055, Color(rage_c.r, rage_c.g, rage_c.b, 0.95))


## 子核心存活 → 触须末端拉出能量索连到子核心（GLOW α0.6），玩家读「打子核心去」；
##   暴露期 → 能量索断裂（不画），改由 `Boss._draw()` 的护罩弧接管读「现在要换甲破罩」。
static func _l4_tethers(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var g := glow_col(c)
	var cores := _sub_core_local(b)
	if cores.is_empty() or _gb(b, "_exposed_win"):
		return
	for i in cores.size():
		var cp: Vector2 = cores[i]
		var a := cp.angle()
		var tip := Vector2.RIGHT.rotated(a) * (r * 1.55)
		b.draw_line(tip, cp, Color(g.r, g.g, g.b, 0.60), 3.0, true)
		b.draw_circle(cp, 5.0, Color(g.r, g.g, g.b, 0.85))


## L4 本体：宽厚六边母舰（引力黄 + 电浆红能量纹 + NEUTRAL 30%），
##   −X 侧是**深渊之口**（内凹弧形开口），CORE 就坐在口里 —— 读作「打嘴」。
static func draw_maw(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var m := main_col(c)
	var g := glow_col(c)
	var dk := dark_col(c)
	var sil := _poly(SIL_MAW, r)
	b.draw_colored_polygon(_poly(SIL_MAW, r * 1.06), dk)
	b.draw_colored_polygon(sil, m)
	# ⑤ NEUTRAL 结构件 30%：上下两条纵向装甲带
	b.draw_rect(Rect2(-0.30 * r, -0.86 * r, 1.10 * r, 0.09 * r), NEUTRAL)
	b.draw_rect(Rect2(-0.30 * r, 0.77 * r, 1.10 * r, 0.09 * r), NEUTRAL)
	# ⑥ 深渊之口：−X 侧内凹开口（近黑底 + GLOW 口沿）
	var mx := -0.62 * r
	b.draw_circle(Vector2(mx, 0.0), r * 0.42, Color(0.04, 0.03, 0.08, 0.95))
	b.draw_arc(Vector2(mx, 0.0), r * 0.42, PI * 0.55, PI * 1.45, 20,
		Color(g.r, g.g, g.b, 0.85), 4.0, true)
	# 电浆红能量纹 ×3（§C.1：引力黄本体 + 电浆红能量纹）
	var acm: Color = Game.COLOR_MAIN[boss_accent_c(4)]
	for i in 3:
		var yy: float = (-0.34 + 0.34 * float(i)) * r
		b.draw_line(Vector2(-0.18 * r, yy), Vector2(0.78 * r, yy * 0.72),
			Color(acm.r, acm.g, acm.b, 0.70), 3.0, true)
	# ⑧ CORE 要害核（坐在口内）
	_core_socket(b, r, c, pulse, mx)


# ================================================================ L5 终焉号 · 分身
## ±Y 侧各一枚半透明相位残影：α0.30、**无 CORE**、呼吸滞后 0.18s
##   （同相位会读成「一个更厚的实体」，**必须滞后**才读成「影子」）。
##   残影数随四相重构 0 → 1 → 2 → 3（第 3 枚在 −X 侧，形成「三面围拢」）。
##   狂暴：α 0.30 → 0.55（变实 = 威胁升级的明度通道）。
static func _l5_echoes(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var n := clampi(ph - 1, 0, 3)
	if n <= 0:
		return
	var alpha := 0.55 if rage else 0.30
	for i in n:
		var off := Vector2.ZERO
		if i == 0:
			off = Vector2(0.0, -1.50 * r)
		elif i == 1:
			off = Vector2(0.0, 1.50 * r)
		else:
			off = Vector2(-1.50 * r, 0.0)
		var lag := 1.0 + 0.04 * sin(2.2 * (t - 0.18) + 1.7)
		var base := _poly(SIL_THRONE, r * 0.82 * lag)
		var pts := PackedVector2Array()
		pts.resize(base.size())
		for j in base.size():
			var q: Vector2 = base[j]
			pts[j] = q + off
		b.draw_colored_polygon(pts, Color(STEEL.r, STEEL.g, STEEL.b, alpha))
		var ring := PackedVector2Array(pts)
		ring.append(pts[0])
		b.draw_polyline(ring, Color(STEEL_GLOW.r, STEEL_GLOW.g, STEEL_GLOW.b,
			alpha * 0.80), 2.0, true)


## 狂暴追加：本体外缘 12 段**逆向游走**血色虚线环（§C.2-L5）
static func _l5_rage_ring(b: Node2D, _pulse: float) -> void:
	if not _gb(b, "enraged"):
		return
	var r := r_main_of(b)
	var t := _gf(b, "_t", 0.0)
	_dash_arc(b, r * 1.16, Color(1.0, 0.26, 0.16, 0.85), 4.0, 12, 0.16, -t * 0.9)


## L5 本体：纺锤形（−X 尖、+X 钝），中性亮钢灰 —— **不绑定四色**，
##   四色只在能量纹上轮转（每秒推进一色，`i = floor(_t) % 4`）。
##   换色预告时能量纹整体明暗一次（≤0.5Hz，远低于 2Hz 光敏线）。
static func draw_throne(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(5)
	var m := main_col(c)
	var dk := dark_col(c)
	var t := _gf(b, "_t", 0.0)
	var sil := _poly(SIL_THRONE, r)
	b.draw_colored_polygon(_poly(SIL_THRONE, r * 1.06), dk)
	b.draw_colored_polygon(sil, m)
	# ⑤ NEUTRAL 结构线：中轴脊 + 上下弦（保住「颜色 + 形状」双通道的形状侧）
	b.draw_line(Vector2(-0.90 * r, 0.0), Vector2(0.72 * r, 0.0), NEUTRAL_DK, 3.0, true)
	b.draw_line(Vector2(-0.40 * r, -0.22 * r), Vector2(0.52 * r, -0.12 * r),
		NEUTRAL, 2.0, true)
	b.draw_line(Vector2(-0.40 * r, 0.22 * r), Vector2(0.52 * r, 0.12 * r),
		NEUTRAL, 2.0, true)
	# ⑥ 四色轮转能量纹（−X 指向的箭羽 ×3）
	var idx := int(floor(t)) % 4
	var wc: Color = Game.COLOR_MAIN[idx]
	var wa := 0.85
	if _is_tell(b):
		wa = 0.35 + 0.50 * absf(sin(t * PI * 0.5))
	for i in 3:
		var xx: float = (-0.34 + 0.32 * float(i)) * r
		var col := Color(wc.r, wc.g, wc.b, wa)
		b.draw_line(Vector2(xx, -0.30 * r), Vector2(xx + 0.22 * r, 0.0), col, 4.0, true)
		b.draw_line(Vector2(xx + 0.22 * r, 0.0), Vector2(xx, 0.30 * r), col, 4.0, true)
	# ⑧ CORE 要害核
	_core_socket(b, r, c, pulse, -r * 0.42)
