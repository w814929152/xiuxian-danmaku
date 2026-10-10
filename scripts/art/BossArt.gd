class_name BossArt
extends RefCounted
## ---------------------------------------------------------------
## BossArt —— 五个旗舰的矢量绘制（纯静态，与 `PirateArt` 同构）
##
## 2026-10 简化重做：**与玩家战机同一套绘画语汇**，删掉机甲化的
## 铆钉 / 传感器阵列 / 散热鳍 / 转轴环 / 闸齿等碎片细节 ——
## 玩家怎么画，Boss 就怎么画，只是体量更大：
##   · 本体 = 暗色外壳(×1.07) + 一块不透明 MAIN 实心 + SEAM 内框描边
##     （「每关一块不透明 MAIN 实心块」硬底线不变，玩家靠它判断换甲）；
##   · 尾焰 = STEEL 喷嘴壳 + GLOW 外焰 + CORE 焰心 的三层三角焰
##     （玩家推进器同款，恒在 +X 尾，不得朝 −X）；
##   · 点缀 = 对称双菱形饰灯（玩家绕身菱形光刃同语汇）。
## 朝向沿用全项目语法：**−X 是头（要害扇区），+X 是尾**，
## CORE 要害核一律落在中轴偏 −X 处。
##
## 五关差异化只保留「剪影 + 主色 + 一个标志器官」三件事：
##   L1 环（护罩指示）/ L2 翼（窗口开合）/ L3 炮列 + 暗甲壳弧 /
##   L4 触须 + 能量索 / L5 相位残影 + 四色轮转纹。
## 机制可读性一条不删：护罩色环、换色预告虚线、L2 开合、L3 减伤壳
## 与散热缺口、L4 绷紧索与暴露期、L5 残影数与狂暴血环全保留。
##
##   · 尺寸：主半径 `R_MAIN` 走 `StageCfg.boss_r_main(stage)`（56/63/70/77/84）。
##     **本文件不复制这张表**，所有器官尺寸一律 `r × 系数`。
##   · 状态读取一律走 `Object.get()` 字符串访问：BossArt **不 import Boss / Boss4**
##     （循环依赖），读不到就降级画基础形态 —— 与 HUD 读 `venting` 同一模式。
##   · 可访问性：L3「暗甲壳弧」与护罩弧三处全反（DARK vs MAIN / 静止 vs 游走 /
##     断续 vs 连续）；狂暴走「泛红 + 形状符标」双通道（Boss._draw 画三角符标）。
##   · ⚠️ 全绘制函数禁止出现 CANOPY 舱盖色 (0.62,0.86,0.98) —— 星盗没有驾驶舱。
## ---------------------------------------------------------------

# ================================================================ 常量
## 装甲金属（四色通用结构件，不污染「颜色 = 属性」）
const NEUTRAL := Color(0.74, 0.78, 0.86)
## L5 终焉号本体：中性亮钢灰（不绑定四色）+ 它的暗部 / 外发光
const STEEL := Color(0.62, 0.66, 0.74)
const STEEL_DARK := Color(0.17, 0.19, 0.26)
const STEEL_GLOW := Color(0.84, 0.88, 0.96)
## 血色（狂暴 / 断裂的通用告警色）
const RAGE := Color(1.00, 0.28, 0.18)
## 接缝色：把「结构件」与「接缝」两个职务分开
const SEAM := Color(0.45, 0.49, 0.57)

## 逐关本体主色：0=RED 1=BLUE 2=WHITE 3=YELLOW；**-1 = 中性钢灰**（L5 不绑定四色）。
##   裸 int 而非 `Game.RED` 枚举 —— 本文件既有坑：枚举 / 单例成员进不了推断数组。
const _MAIN_C := [2, 1, 0, 3, -1]
## 逐关能量纹色：仅 L4 = RED（引力黄本体 + 电浆红能量纹）；其余 -1 = 无
const _ACCENT_C := [-1, -1, -1, 0, -1]

# ---- 本体剪影（单位半径 1 = R_MAIN，运行时乘 r）----
## ⚠ 全部是「舰体流线」：−X 尖艏 → 平行舯体 → +X 收艉（艉留平面给喷焰），
##   宽长比约 1:1.8~2.0 —— 飞行器读感的三要素：细长、前尖后钝、头尾朝向明确。
##   对称多边形（六边/方块）会读成徽章/板件，一律不用。
## L1 熔核号：圆钝驱逐舰体（尖艏 + 圆弧舷 + 平艉）
const SIL_CORE := [
	Vector2(-1.00, 0.0), Vector2(-0.66, -0.42), Vector2(0.20, -0.56),
	Vector2(0.72, -0.42), Vector2(0.90, -0.16), Vector2(0.90, 0.16),
	Vector2(0.72, 0.42), Vector2(0.20, 0.56), Vector2(-0.66, 0.42),
]
## L2 霜噬号：细长菱形巡洋舰体（−X 尖艏、+X 平艉）
const SIL_WING := [
	Vector2(-1.04, 0.0), Vector2(-0.42, -0.36), Vector2(0.30, -0.44),
	Vector2(0.82, -0.24), Vector2(0.82, 0.24), Vector2(0.30, 0.44),
	Vector2(-0.42, 0.36),
]
## L3 耀斑号：槌头炮舰（艏面宽平给炮口贴装，舯体收窄，+X 收艉）
const SIL_BATTERY := [
	Vector2(-0.74, -0.76), Vector2(0.16, -0.66), Vector2(0.78, -0.40),
	Vector2(0.96, -0.14), Vector2(0.96, 0.14), Vector2(0.78, 0.40),
	Vector2(0.16, 0.66), Vector2(-0.74, 0.76),
]
## L4 深渊之喉：宽扁母舰体（细长化，艏面开深渊之口 = 机库闸门）
const SIL_MAW := [
	Vector2(-0.92, -0.26), Vector2(-0.62, -0.52), Vector2(0.22, -0.60),
	Vector2(0.80, -0.34), Vector2(0.80, 0.34), Vector2(0.22, 0.60),
	Vector2(-0.62, 0.52), Vector2(-0.92, 0.26),
]
## L5 终焉号：细长纺锤（−X 尖艏、+X 平艉）
const SIL_THRONE := [
	Vector2(-1.06, 0.0), Vector2(-0.56, -0.26), Vector2(0.12, -0.40),
	Vector2(0.78, -0.24), Vector2(0.78, 0.24), Vector2(0.12, 0.40),
	Vector2(-0.56, 0.26),
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


## 换色预告中：护罩展开着 + 剩余时长已进预告窗
##   读不到 `_ward_tell` / `_ward_t`（非 Boss 实例）时恒 false —— 降级成"不预告"。
static func _is_tell(b: Node2D) -> bool:
	var tell := _gf(b, "_ward_tell", 0.0)
	if tell <= 0.0:
		return false
	if _gi(b, "ward", -1) < 0:
		return false
	return _gf(b, "_ward_t", 99.0) <= tell


## L4 子核心**暴露期**：单一布尔派生量（能量索 / 闸门 / 护罩弧三处同读）。
##   方法读不到就走基类字段 `_exposed_win`，再读不到恒 false。
static func _is_exposed(b: Node2D) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	if b.has_method("is_exposed"):
		var v: Variant = b.call("is_exposed")
		if v is bool:
			return bool(v)
	return _gb(b, "_exposed_win")


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


## 断续弧（段间 gap 弧度缺口）—— 护罩预告弧 / L3 暗甲壳弧 / L5 血色虚线环共用
##   [param span] 总跨度；< TAU 时留一个大缺口（L1 环缺口 / L3 散热缺口靠它）
static func _dash_arc(ci: Node2D, rad: float, col: Color, w: float, segs: int,
		gap: float, off: float, span: float = TAU) -> void:
	var step := span / float(segs)
	for i in segs:
		var a0 := off + float(i) * step + gap * 0.5
		var a1 := off + float(i + 1) * step - gap * 0.5
		if a1 <= a0:
			continue
		ci.draw_arc(Vector2.ZERO, rad, a0, a1, 8, col, w, true)


## 三层三角尾焰（玩家推进器同款语汇）：STEEL 喷嘴壳 → GLOW 外焰 → CORE 焰心。
##   恒朝 +X（−X 是要害扇区，焰不得朝 −X）。焰长带 ~1.4Hz 抖动（守 ≤3Hz 光敏线）。
static func _flame(ci: Node2D, x: float, hw: float, len: float,
		g: Color, k: Color, t: float) -> void:
	var jf := 1.0 + 0.12 * sin(t * 9.0)
	var jl := len * jf
	ci.draw_rect(Rect2(x - 1.0, -hw, 5.0, hw * 2.0), STEEL)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x + 3.0, -hw), Vector2(x + jl, 0.0), Vector2(x + 3.0, hw)
	]), Color(g.r, g.g, g.b, 0.45))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(x + 3.0, -hw * 0.5), Vector2(x + jl * 0.60, 0.0),
		Vector2(x + 3.0, hw * 0.5)
	]), Color(k.r, k.g, k.b, 0.90))


## 对称双菱形饰灯（玩家绕身菱形光刃同语汇，缩小成舷侧饰灯）
static func _twin_blades(ci: Node2D, r: float, col: Color) -> void:
	var s: float = 0.055 * r
	for sg in [-1.0, 1.0]:
		var p := Vector2(0.06 * r, sg * 0.38 * r)
		ci.draw_colored_polygon(PackedVector2Array([
			p + Vector2(s, 0.0), p + Vector2(0.0, -s * 0.36),
			p - Vector2(s, 0.0), p + Vector2(0.0, s * 0.36)
		]), col)


## 舰艏箭标（−X 尖艏上的一个「>」形亮线）—— 飞行器朝向读感的点睛笔，
##   一条折线搞定。画在 CORE 之前（白身/要害核重叠时被眼窝盖住，不脏）。
static func _bow_mark(ci: Node2D, r: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([
		Vector2(-0.38 * r, 0.24 * r), Vector2(-0.70 * r, 0.0),
		Vector2(-0.38 * r, -0.24 * r)
	]), Color(col.r, col.g, col.b, 0.75), 3.0, true)


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
			_l1_rings(b)
		2:
			_l2_wings(b)
		4:
			_l4_tentacles(b)
		5:
			_l5_echoes(b)
		_:
			pass        # L3 的炮列是外突型器官，画在 ⑦b


## ③④ 本体（五关剪影各不相同）
static func draw_body(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		1:
			_body_common(b, pulse, SIL_CORE, 1, -0.16)
		2:
			_body_common(b, pulse, SIL_WING, 2, -0.30)
		3:
			_body_battery(b, pulse)
		4:
			_body_maw(b, pulse)
		_:
			_body_throne(b, pulse)


## ⑦b 外突型标志器官（主体之上、CORE 之前）
static func draw_sig_front(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		3:
			_l3_guns(b, pulse)
		_:
			pass


## 机制联动（每个 Boss 的「机制 → 视觉」通道）
static func draw_mechanic(b: Node2D, pulse: float) -> void:
	match _gi(b, "stage", 1):
		3:
			_l3_shell(b, pulse)
		4:
			_l4_tethers(b)
		5:
			_l5_rage_ring(b)
		_:
			pass        # L1 的换色预告已在环上表达（_l1_rings 读 _is_tell）


## 本体外缘描边（护罩开启时 2px CORE 白描边 —— 边缘通道）
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


## 通用本体（L1 / L2 共用骨架）：暗外壳 → MAIN 实心块 → SEAM 内框 →
##   各关特征线（钩子）→ 三层焰 → 双菱形饰灯 → CORE 要害核。
##   [param core_ox] CORE 要害核的中轴偏移（−X 为负）
static func _body_common(b: Node2D, pulse: float, sil: Array, st: int,
		core_ox: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(st)
	var m := main_col(c)
	var g := glow_col(c)
	var k := core_col(c)
	var dk := dark_col(c)
	var rage := _gb(b, "enraged")
	# 暗外壳（×1.07，体积感 + 玩家本体同款「暗底」读法）
	b.draw_colored_polygon(_poly(sil, r * 1.07), dk)
	# MAIN 实心块（硬底线：玩家靠高饱和 MAIN 面积判断该换哪件战甲）
	b.draw_colored_polygon(_poly(sil, r), m)
	# 装甲内框（SEAM：一块甲的读法，一次 draw）
	_outline(b, _poly(sil, r * 0.70), SEAM, 2.0)
	# 舰艏箭标（−X 尖艏的朝向读感）
	_bow_mark(b, r, g)
	match st:
		1:
			# L1：2 道横舱壁缝（舰体框架读法；狂暴渗 RAGE，走换色不另叠层）
			var seamc := SEAM.lerp(RAGE, 0.45) if rage else SEAM
			for xx: float in [-0.20, 0.45]:
				b.draw_line(Vector2(xx * r, -0.45 * r),
					Vector2(xx * r, 0.45 * r), seamc,
					maxf(1.5, 0.03 * r), true)
			# 熔炉辉环（GLOW，读作「炉子在烧」）
			b.draw_arc(Vector2.ZERO, r * 0.40, 0.0, TAU, 28,
				Color(g.r, g.g, g.b, 0.55), 4.0, true)
		2:
			# L2：两条 GLOW 导管线，α 随翼展开度增强（=「窗口打开」的读数）
			var ph := _gi(b, "phase", 1)
			var open := clampf(float(ph - 1) / 2.0, 0.0, 1.0)
			var cond := Color(g.r, g.g, g.b, 0.25 + 0.45 * open)
			b.draw_line(Vector2(-0.34, -0.28) * r, Vector2(0.52, -0.14) * r, cond, 3.0, true)
			b.draw_line(Vector2(-0.34, 0.28) * r, Vector2(0.52, 0.14) * r, cond, 3.0, true)
	# 三层三角尾焰（玩家推进器同款，+X 艉；基位随各关艉面）
	_flame(b, r * (0.88 if st == 1 else 0.80), 0.10 * r, 0.34 * r, g, k,
		_gf(b, "_t", 0.0))
	# 双菱形饰灯
	_twin_blades(b, r, Color(k.r, k.g, k.b, 0.75))
	# CORE 要害核
	_core_socket(b, r, c, pulse, core_ox * r)


# ================================================================ L1 熔核号 · 环
## 自转的护罩指示环：**环色 = 当前 ward 色，环就是护罩指示器**。
##   · 环半径 ×1.28、环宽 5px、缺口朝 +X、3 枚 CORE 符点顺时针
##   · 换色预告（1.5s）：连续弧 → 8 段虚线弧 + 加速旋转
##   · 狂暴：缺口加大 + 角速度 ×1.8
static func _l1_rings(b: Node2D) -> void:
	var r := r_main_of(b)
	var t := _gf(b, "_t", 0.0)
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
	# 环上 3 枚符点
	for i in 3:
		var a := spin + TAU * float(i) / 3.0
		b.draw_circle(Vector2.RIGHT.rotated(a) * r1, 4.6, kcol)


# ================================================================ L2 霜噬号 · 翼
## 两侧三角翼：翼根在 ±Y、翼尖朝 **+X**（−X 是要害指针，不许往前加尖出物）。
##   · 展开角随阶段 25° → 55° → 80°（收拢 = 窗口关闭，全展 = 窗口打开）
##   · 只有 L2 是 `WardMode.NONE` —— **永不画护罩弧**，开合节拍就是它的窗口语言
##   · 翼画法 = 玩家本体同款：DARK 填充 + MAIN 描边 + 一条 NEUTRAL 骨线
##   · 狂暴：翼尖各伸出 1 枚 GLOW 三角霜刃，随呼吸同步张合
static func _l2_wings(b: Node2D) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(2)
	var m := main_col(c)
	var g := glow_col(c)
	var dk := dark_col(c)
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var deg := 25.0
	if ph >= 3:
		deg = 80.0
	elif ph == 2:
		deg = 55.0
	# 翼随呼吸同步张合（±4°，0.35Hz —— 远低于 2Hz 光敏线）
	var spread := deg_to_rad(deg) + sin(t * 2.2) * deg_to_rad(4.0)
	for k in 2:
		var sg: float = -1.0 + 2.0 * float(k)
		var a := sg * spread
		var dir := Vector2.RIGHT.rotated(a)
		var perp := dir.rotated(PI * 0.5) * sg
		var root := Vector2(-0.16 * r, sg * 0.40 * r)
		var tip := root + dir * (r * 0.88)
		var mid := root + dir * (r * 0.50) + perp * (r * 0.16)
		# 翼板（DARK 填充 + MAIN 描边 —— 玩家本体同款）
		var wing := PackedVector2Array([root, tip, mid])
		b.draw_colored_polygon(wing, dk)
		_outline(b, wing, Color(m.r, m.g, m.b, 0.85), 2.0)
		# 翼骨（承力梁，一条）
		b.draw_line(root, tip, NEUTRAL, 3.0, true)
		if not rage:
			continue
		# 狂暴：翼尖 1 枚 GLOW 三角霜刃（随呼吸张合）
		var open := 0.75 + 0.25 * sin(t * 2.2)
		var aa := a + 0.16 * sg * open
		var d := Vector2.RIGHT.rotated(aa)
		var p0 := tip + d * (r * 0.05)
		var p1 := tip + d * (r * 0.26)
		var pw := d.rotated(PI * 0.5) * (r * 0.055)
		b.draw_colored_polygon(PackedVector2Array([p0 + pw, p1, p0 - pw]),
			Color(g.r, g.g, g.b, 0.9))


# ================================================================ L3 耀斑号 · 炮列
## −X 舷一列炮口（每侧 1 / 2 / 3 门随阶段，中轴留空让开 CORE）：
##   NEUTRAL 短炮管 + GLOW 炮口圆头。散热期：全部炮口喷 GLOW 三角焰 ——
##   与「甲壳缺口 + 白光」构成三层冗余。
##   ⚠ 炮口 y 偏移必须 < SIL_BATTERY 舷半高（0.762）—— SelfTest V7 静态校验读它。
static func _l3_guns(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(3)
	var g := glow_col(c)
	var ph := _gi(b, "phase", 1)
	var vent := _gb(b, "venting")
	var half := 1
	if ph >= 3:
		half = 3
	elif ph == 2:
		half = 2
	var bx := -0.74 * r        # = SIL_BATTERY 的 −X 顶点 x（槌头艏面，贴装不悬空）
	for j in half:
		var off: float = (0.20 + 0.17 * float(j)) * r
		for k in 2:
			var sg: float = -1.0 + 2.0 * float(k)
			var y := sg * off
			# 炮管（NEUTRAL，向 −X 伸出 0.20r）
			b.draw_line(Vector2(bx, y), Vector2(bx - 0.20 * r, y), NEUTRAL, 4.0, true)
			# 炮口（GLOW 圆头）
			b.draw_circle(Vector2(bx - 0.22 * r, y), r * 0.05,
				Color(g.r, g.g, g.b, 0.95))
			if vent:
				# 散热期：炮口喷 GLOW 三角焰（外晕 + 焰心）
				var mx := bx - 0.24 * r
				b.draw_colored_polygon(PackedVector2Array([
					Vector2(mx, y - 0.10 * r), Vector2(mx - 0.30 * r, y),
					Vector2(mx, y + 0.10 * r)
				]), Color(g.r, g.g, g.b, 0.30))
				b.draw_colored_polygon(PackedVector2Array([
					Vector2(mx, y - 0.05 * r), Vector2(mx - 0.18 * r, y),
					Vector2(mx, y + 0.05 * r)
				]), Color(g.r, g.g, g.b, 0.90))


## L3 三态 —— 与「护罩弧」在**颜色 / 运动 / 断续形态三处全反**：
##   常驻减伤 70% = 8 段断续暗甲壳弧、`COLOR_DARK`、**静止不游走**、半径 ×1.80
##   散热期       = 裂开 1.2 rad 大缺口，缺口固定朝 −X（正对玩家），缺口内露 CORE 白光
##   （对照）护罩 = MAIN 色、连续。这里 L2/L3 是 `WardMode.NONE`，永不展护罩
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


## L3 本体：槌头炮舰（电浆红，**强制 3px CORE 白描边** ——
##   红对比仅 2.38:1 的补偿；红本体在没有描边时会与暗背景糊成一片）
static func _body_battery(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(3)
	var m := main_col(c)
	var g := glow_col(c)
	var k := core_col(c)
	var dk := dark_col(c)
	var sil := _poly(SIL_BATTERY, r)
	b.draw_colored_polygon(_poly(SIL_BATTERY, r * 1.07), dk)
	b.draw_colored_polygon(sil, m)
	# 🔴 强制 3px `CORE[WHITE]` 外描边（红本体对比补偿，**不得删**）
	_outline(b, sil, core_col(Game.WHITE), 3.0)
	# 装甲内框 + 舰艏箭标 + 2 道横向甲板梁（NEUTRAL 结构件，舰体框架读法）
	_outline(b, _poly(SIL_BATTERY, r * 0.70), SEAM, 2.0)
	_bow_mark(b, r, g)
	for i in 2:
		var yy: float = (-0.30 + 0.60 * float(i)) * r
		b.draw_rect(Rect2(-0.60 * r, yy, 1.30 * r, 0.07 * r), NEUTRAL)
	# 三层三角尾焰 + 双菱形饰灯 + CORE 要害核
	_flame(b, r * 0.94, 0.12 * r, 0.30 * r, g, k, _gf(b, "_t", 0.0))
	_twin_blades(b, r, Color(k.r, k.g, k.b, 0.75))
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
	# 轨道半径 = R_MAIN × 1.95（Boss4.SubCore._process 定的）。不在轨道带上的一律丢掉：
	#   分裂首帧子核心的 `position` 还是 (0,0)，拿它去定向触须既画错方向又同角重叠。
	var r := r_main_of(b)
	for core in arr:
		if core == null or not is_instance_valid(core):
			continue
		var dv: Variant = core.get("dead")
		if dv is bool and bool(dv):
			continue
		var pv: Variant = core.get("position")
		if not (pv is Vector2):
			continue
		var d: Vector2 = (pv as Vector2) - b.position
		if d.length() < r * 1.20 or d.length() > r * 2.80:
			continue
		out.append(d)
	return out


## 牵引触须（每侧 1 / 2 / 3 条随阶段）：GLOW 3px 折线 + 末端符点。
##   · **全部布在 +X 与 ±Y 半侧，绝不进入 −X ±40° 要害扇区**（那里坐着 CORE 与深渊之口）
##   · 子核心存活 → 绷紧成指向子核心的直线；暴露期 → 断裂缩短
##   · 召唤预告（CD 尾 0.4s）→ 触须整体前伸 6px
##   · 狂暴：触须转 RAGE 色 + 末端血色符点
static func _l4_tentacles(b: Node2D) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var g := glow_col(c)
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var exposed := _is_exposed(b)
	var half := 1
	if ph >= 3:
		half = 3
	elif ph == 2:
		half = 2
	var cores := _sub_core_local(b)
	var tense := (not cores.is_empty()) and (not exposed)
	var summon_t := _gf(b, "_summon_t", 99.0)
	var ext := 6.0 if summon_t <= 0.4 else 0.0
	var col := Color(RAGE.r, RAGE.g, RAGE.b, 0.80) if rage \
		else Color(g.r, g.g, g.b, 0.60)
	# 基础角：+X 半圆均匀铺开（−X ±40° 要害扇区不进）
	for k in half:
		for sg in [-1.0, 1.0]:
			var a: float = sg * (PI * 0.72) * (float(k) + 0.5) / float(half)
			var curl: float = 0.30 * sg
			if tense and cores.size() > 0:
				var cp := cores[mini(k * 2 + (0 if sg < 0.0 else 1),
					cores.size() - 1)]
				a = cp.angle()
				curl = 0.0                    # 绷紧 = 直线
			var p0 := Vector2.RIGHT.rotated(a) * (r * 0.78)
			var p1 := Vector2.RIGHT.rotated(a + curl * 0.4) * (r * 1.05 + ext)
			var p2 := Vector2.RIGHT.rotated(a + curl) * (r * 1.32 + ext)
			p2.y += sin(t * 5.0 + float(k) * 1.7) * 2.0    # 末端 ±2px 抖动
			if exposed:
				# 暴露期：能量索已断 —— 缩短一截，无末端符点（断口）
				p2 = Vector2.RIGHT.rotated(a + curl * 0.5) * (r * 1.05)
			b.draw_polyline(PackedVector2Array([p0, p1, p2]), col, 3.0, true)
			if not exposed:
				b.draw_circle(p2, r * 0.045, col)


## 子核心存活 → 触须末端拉出能量索连到子核心（GLOW α0.6），玩家读「打子核心去」；
##   暴露期 → 能量索断裂（不画），改由 `Boss._draw()` 的护罩弧接管读「现在要换甲破罩」。
static func _l4_tethers(b: Node2D) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var g := glow_col(c)
	var cores := _sub_core_local(b)
	if cores.is_empty() or _is_exposed(b):
		return
	for i in cores.size():
		var cp: Vector2 = cores[i]
		var a := cp.angle()
		var tip := Vector2.RIGHT.rotated(a) * (r * 1.32)
		b.draw_line(tip, cp, Color(g.r, g.g, g.b, 0.60), 3.0, true)
		b.draw_circle(cp, 5.0, Color(g.r, g.g, g.b, 0.85))


## L4 本体：宽扁母舰体（引力黄 + 电浆红能量纹），
##   −X 艏是**深渊之口**（内凹机库闸门），CORE 就坐在口里 —— 读作「打嘴」。
static func _body_maw(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var g := glow_col(c)
	var k := core_col(c)
	var dk := dark_col(c)
	var exposed := _is_exposed(b)
	b.draw_colored_polygon(_poly(SIL_MAW, r * 1.07), dk)
	b.draw_colored_polygon(_poly(SIL_MAW, r), Game.COLOR_MAIN[c])
	_outline(b, _poly(SIL_MAW, r * 0.70), SEAM, 2.0)
	# 机库闸门（深渊之口）—— **读 `_is_exposed()`，与能量索 / 护罩弧同一帧同相位**。
	#   暗腔圆心坐在艏面顶点上（半露在舰体外）→ 读成「张开的巨口」而不是舰身上的圆窗
	var mx := -0.92 * r
	if exposed:
		# 闸门**关闭**：腔内改 DARK 实心（不再是「能打进去的口」）
		b.draw_circle(Vector2(mx, 0.0), r * 0.34, dk)
	else:
		b.draw_circle(Vector2(mx, 0.0), r * 0.34, Color(0.04, 0.03, 0.08, 0.95))
		b.draw_arc(Vector2(mx, 0.0), r * 0.34, PI * 0.55, PI * 1.45, 20,
			Color(g.r, g.g, g.b, 0.85), 4.0, true)
	# 电浆红能量纹 ×3（引力黄本体 + 电浆红能量纹）
	var acm: Color = Game.COLOR_MAIN[boss_accent_c(4)]
	for i in 3:
		var xx: float = (-0.10 + 0.28 * float(i)) * r
		b.draw_line(Vector2(xx, -0.30 * r), Vector2(xx, 0.30 * r),
			Color(acm.r, acm.g, acm.b, 0.70), 3.0, true)
	# 三层三角尾焰 + 双菱形饰灯
	_flame(b, r * 0.78, 0.11 * r, 0.32 * r, g, k, _gf(b, "_t", 0.0))
	_twin_blades(b, r, Color(k.r, k.g, k.b, 0.75))
	# 暴露期飘字（A2：一律走 `DrawUtil.txt()`）
	if exposed:
		DrawUtil.txt(b, "暴露期", Vector2(0.0, -1.18 * r), 15,
			Color(0.95, 0.97, 1.0, 0.92), HORIZONTAL_ALIGNMENT_CENTER,
			Color(0.02, 0.03, 0.06, 0.9), 0.0)
	# CORE 要害核（坐在闸门腔内）
	_core_socket(b, r, c, pulse, mx)


# ================================================================ L5 终焉号 · 分身
## ±Y 侧各一枚半透明相位残影：α0.30、**无 CORE**、呼吸滞后 0.18s
##   （同相位会读成「一个更厚的实体」，**必须滞后**才读成「影子」）。
##   残影数随四相重构 0 → 1 → 2 → 3（第 3 枚在 −X 侧，形成「三面围拢」）。
##   狂暴：α 0.30 → 0.45（变实 = 威胁升级的明度通道）。
static func _l5_echoes(b: Node2D) -> void:
	var r := r_main_of(b)
	var t := _gf(b, "_t", 0.0)
	var ph := _gi(b, "phase", 1)
	var rage := _gb(b, "enraged")
	var n := clampi(ph - 1, 0, 3)
	if n <= 0:
		return
	var alpha := 0.45 if rage else 0.30
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
		_outline(b, pts, Color(STEEL_GLOW.r, STEEL_GLOW.g, STEEL_GLOW.b,
			alpha * 0.80), 2.0)


## 狂暴追加：本体外缘 12 段**逆向游走**血色虚线环
static func _l5_rage_ring(b: Node2D) -> void:
	if not _gb(b, "enraged"):
		return
	var r := r_main_of(b)
	var t := _gf(b, "_t", 0.0)
	_dash_arc(b, r * 1.16, Color(1.0, 0.26, 0.16, 0.85), 4.0, 12, 0.16, -t * 0.9)


## L5 本体：纺锤形（−X 尖、+X 钝），中性亮钢灰 —— **不绑定四色**，
##   四色只在能量纹上轮转（每秒推进一色，`i = floor(_t) % 4`）。
##   换色预告时能量纹整体明暗一次（≤0.5Hz，远低于 2Hz 光敏线）。
static func _body_throne(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(5)
	var g := glow_col(c)
	var k := core_col(c)
	var t := _gf(b, "_t", 0.0)
	var sil := _poly(SIL_THRONE, r)
	b.draw_colored_polygon(_poly(SIL_THRONE, r * 1.07), STEEL_DARK)
	b.draw_colored_polygon(sil, STEEL)
	_outline(b, _poly(SIL_THRONE, r * 0.70), SEAM, 2.0)
	# 中轴脊（形状通道的骨架，一条）
	b.draw_line(Vector2(-0.90 * r, 0.0), Vector2(0.70 * r, 0.0), STEEL_DARK, 3.0, true)
	# 舰艏箭标（与 L1/L2/L3 同一笔）
	_bow_mark(b, r, STEEL_GLOW)
	# 四色轮转能量纹（−X 指向的箭羽 ×3）
	var idx := int(floor(t)) % 4
	var wc: Color = Game.COLOR_MAIN[idx]
	var wa := 0.85
	if _is_tell(b):
		wa = 0.35 + 0.50 * absf(sin(t * PI * 0.5))
	for i in 3:
		var xx: float = (-0.34 + 0.32 * float(i)) * r
		var col := Color(wc.r, wc.g, wc.b, wa)
		b.draw_polyline(PackedVector2Array([Vector2(xx, -0.30 * r),
			Vector2(xx + 0.22 * r, 0.0), Vector2(xx, 0.30 * r)]), col, 4.0, true)
	# 三层三角尾焰（焰心随轮转色）+ 双菱形饰灯 + CORE 要害核
	_flame(b, r * 0.76, 0.10 * r, 0.32 * r, g, k, t)
	_twin_blades(b, r, Color(wc.r, wc.g, wc.b, 0.75))
	_core_socket(b, r, c, pulse, -r * 0.42)
