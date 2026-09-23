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
##       L5 残影 α 0.30→0.45 + 12 段血色虚线环（形状 / 明度通道）；
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
## 接缝色（02 §5.2 新增裁定）：比 NEUTRAL 暗一档，把「结构件」与「接缝」两个职务分开 ——
##   机甲化后接缝量翻倍，两者同色会把装甲片糊成一片。`|B−R| = 0.12`，同样合规。
const SEAM := Color(0.45, 0.49, 0.57)

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
	Vector2(-0.646, -0.762), Vector2(0.348, -0.795), Vector2(0.630, -0.480),
	Vector2(0.630, 0.480), Vector2(0.348, 0.795), Vector2(-0.646, 0.762),
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


## L4 子核心**暴露期**（02 §7.2 缓解口径）：单一布尔派生量，三个绘制层
##   （⑥ 闸门 / ⑦c 能量索 / ⑨ 护罩弧）**都读它**，而不是各自从 `_cores.is_empty()` 推。
##   方法是方法不是字段 —— `Object.get()` 取不到，走 `Object.call()`；
##   读不到（非 Boss4 实例 / 方法被摘）就降级读基类字段 `_exposed_win`，再读不到恒 false。
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
		# 采样点 12 → 8（02 §4.4 实现方式硬约束 ②）：L1 环 8 段 × 12 = 96 段线段是
		#   全场最大单项，降到 8 后 64 段，视觉无差别。
		ci.draw_arc(Vector2.ZERO, rad, a0, a1, 8, col, w, true)


# ================================================================ 机甲语汇工具（02 §1）
## V1 45° 倒角：把单位剪影按 r 缩放后，对每个**凸角**切掉边长 `cut` 的等腰直角。
##   ⚠ **只在绘制时算** —— `SIL_*` 常量表一个顶点都不动（02 §5.1 / 用户裁决 ③）。
##   凸角用「叉积符号 == 有向面积符号」自适配绕向判定，凹角原样保留。
static func _bevel(base: Array, r: float, cut: float) -> PackedVector2Array:
	var n := base.size()
	var src := PackedVector2Array()
	src.resize(n)
	for i in n:
		var p: Vector2 = base[i]
		src[i] = p * r
	if cut <= 0.01 or n < 3:
		return src
	var area := 0.0
	for i in n:
		var a: Vector2 = src[i]
		var b: Vector2 = src[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var out := PackedVector2Array()
	for i in n:
		var p1: Vector2 = src[i]
		var v0: Vector2 = src[(i - 1 + n) % n] - p1
		var v1: Vector2 = src[(i + 1) % n] - p1
		var l0 := v0.length()
		var l1 := v1.length()
		if l0 < 0.001 or l1 < 0.001:
			out.append(p1)
			continue
		var d0 := v0 / l0
		var d1 := v1 / l1
		var cross := d0.x * d1.y - d0.y * d1.x
		if absf(cross) < 0.01 or signf(cross) != signf(area):
			out.append(p1)                  # 凹角 / 近共线 → 不切
			continue
		var c: float = minf(cut, minf(l0 * 0.45, l1 * 0.45))
		out.append(p1 + d0 * c)
		out.append(p1 + d1 * c)
	return out


## V2 / V5 / V7 批绘：N 枚**同色**小件（铆钉 / 传感窗 / 闸齿 / 鳍 / 挂梁 / 炮口）
##   合成**一次** `draw_colored_polygon` —— 02 §4.4 硬约束①「铆钉禁止逐枚 draw」。
##   齿沿 `uy` 从 `bus_h` 立到 `bus_h + tooth_h`；齿间由高 `bus_h` 的细总线相连。
##   `bus_h` 取 ~1px 且压在接缝 / 挂梁 / 舰体弦线下面，实际上看不见。
##   [param ds] 每枚齿沿 `ux` 的中心距离　[param cham] > 0 时切齿顶两角（读作圆窗）
static func _comb(ci: Node2D, org: Vector2, ux: Vector2, uy: Vector2,
		ds: PackedFloat32Array, hw: float, bus_h: float, tooth_h: float,
		col: Color, cham: float = 0.0) -> void:
	var n := ds.size()
	if n < 1:
		return
	# 齿距 < 2×齿宽 → 相邻齿的矩形互相重叠 → 轮廓自交 → Godot 报
	#   "Invalid polygon data, triangulation failed"。把齿宽硬钳到最小齿距的 0.45 倍。
	if n >= 2:
		var ming := ds[1] - ds[0]
		for i in range(1, n):
			ming = minf(ming, ds[i] - ds[i - 1])
		if ming > 0.0:
			hw = minf(hw, ming * 0.45)
	var cm: float = minf(cham, minf(hw * 0.45, tooth_h * 0.45))
	var p := PackedVector2Array()
	p.append(org + ux * (ds[0] - hw))
	p.append(org + ux * (ds[n - 1] + hw))
	var i := n - 1
	while i >= 0:
		var d: float = ds[i]
		var yt := bus_h + tooth_h
		if cm > 0.01:
			p.append(org + ux * (d + hw) + uy * (yt - cm))
			p.append(org + ux * (d + hw - cm) + uy * yt)
			p.append(org + ux * (d - hw + cm) + uy * yt)
			p.append(org + ux * (d - hw) + uy * (yt - cm))
		else:
			p.append(org + ux * (d + hw) + uy * yt)
			p.append(org + ux * (d - hw) + uy * yt)
		p.append(org + ux * (d - hw) + uy * bus_h)
		if i > 0:
			p.append(org + ux * (ds[i - 1] + hw) + uy * bus_h)
		i -= 1
	ci.draw_colored_polygon(p, col)


## 链式批绘：`_comb` 的**折线版** —— 齿心不必共线（L4 牵引臂是弯的，节点不共线）。
##   齿间由**同宽**的连杆带相连；**先画链再画臂**，连杆就被 6px 的臂盖住，只留齿突出两侧
##   （读作「转轴环 / 分节套管」）。同样只 **1 次** draw。
##   [param bh] 连杆半高（默认 = `hh`）。要「离散小件」时把它压到 ~0.5px —— 连杆看不见，
##   只留一排分离的齿（L5 旗舰版弧形传感器阵列就这么用）。
static func _chain_comb(ci: Node2D, cs: Array[Vector2], hw: float, hh: float,
		col: Color, bh: float = -1.0) -> void:
	var one: Array[PackedVector2Array] = [cs]
	_chain_arms(ci, one, hw, hh, col, bh)


## 多臂链式批绘：`_chain_comb` 的**多折线版**（L4 六条牵引臂的转轴环 / 夹爪）。
##   每条折线各出一排齿，臂与臂之间靠**穿过本体的桥**串成单一闭合轮廓 ——
##   ②b 画在 ③④ 之前，桥被不透明舰体盖住，实际不可见。**全部臂只 1 次 draw**。
static func _chain_arms(ci: Node2D, arms: Array[PackedVector2Array], hw: float,
		hh: float, col: Color, bh: float = -1.0) -> void:
	var bhv := hh if bh < 0.0 else bh
	var p := PackedVector2Array()
	for k in arms.size():
		var cs: PackedVector2Array = arms[k]
		var n := cs.size()
		if n < 1:
			continue
		var dirs: Array[Vector2] = []
		var nrms: Array[Vector2] = []
		dirs.resize(n)
		nrms.resize(n)
		for i in n:
			var a: Vector2 = cs[maxi(0, i - 1)]
			var bb: Vector2 = cs[mini(n - 1, i + 1)]
			var d := bb - a
			if d.length() < 0.001:
				d = Vector2(1.0, 0.0)
			dirs[i] = d.normalized()
			nrms[i] = (dirs[i] as Vector2).rotated(PI * 0.5)
		# 齿距 < 2×齿长 → 相邻齿重叠 → 轮廓自交（同 `_comb` 的钳位理由）
		if n >= 2:
			var ming := (cs[1] - cs[0]).length()
			for i in range(1, n):
				ming = minf(ming, (cs[i] - cs[i - 1]).length())
			if ming > 0.0:
				hw = minf(hw, ming * 0.45)
		# 轮廓：**先沿 +nrm 侧正向走**（每齿 4 点：入口@bh → 齿顶@hh → 出口@bh），
		#   再沿 −nrm 侧反向走回来。绕向**必须**是这一侧：臂按角度**降序**排，枢纽点在
		#   「本臂之后、下臂之前」，所以进边从枢纽（角更低）落到本臂的 **+nrm 侧**
		#   （角更高一侧），出边从本臂的 **−nrm 侧**（角更低一侧）走到下一条臂。
		#   反过来（先 −nrm）的话，进 / 出两条边会在臂根角度附近互相跨越 → 自交
		#   （Godot 报 "Invalid polygon data, triangulation failed"）。
		for i in n:
			var c: Vector2 = cs[i]
			var d: Vector2 = dirs[i]
			var q: Vector2 = nrms[i]
			p.append(c - d * hw + q * bhv)
			p.append(c - d * hw + q * hh)
			p.append(c + d * hw + q * hh)
			p.append(c + d * hw + q * bhv)
		var i2 := n - 1
		while i2 >= 0:
			var c: Vector2 = cs[i2]
			var d: Vector2 = dirs[i2]
			var q: Vector2 = nrms[i2]
			p.append(c + d * hw - q * bhv)
			p.append(c + d * hw - q * hh)
			p.append(c - d * hw - q * hh)
			p.append(c - d * hw - q * bhv)
			i2 -= 1
		# 臂间连接：直连会让「进」与「出」两条边在下一条臂的根部打架（自交）。
		#   折一次 —— 先收到本体深处的枢纽点（相邻两臂夹角的平分线上），再出去。
		#   这样进边只覆盖 [平分线, 本臂+δ]、出边只覆盖 [下臂−δ, 平分线]，角度区间不重叠。
		if arms.size() >= 2:
			p.append(_hub_pt(arms, k))
	if p.size() >= 3:
		ci.draw_colored_polygon(p, col)


## 多臂合批的枢纽点：沿**角度递减方向**从本臂走到下一条臂的那段弧的正中，
##   半径 = 根部半径 × 0.22。落在舰体内部（②b 先于 ③④ → 被不透明舰体盖住），
##   只用来把进 / 出两条边分开（进边覆盖 [hub, 本臂−δ]、出边覆盖 [下臂+δ, hub]）。
##   ⚠ 不能写成「两臂根部向量的和」求平分线：那是**短弧**的中点。相邻臂用短弧没错，
##   但**首尾臂的环绕**（k = n−1 → 0）要的是**长弧**的中点 —— 臂角跨度 < π 时
##   （触须绷紧指向子核心时就是）短弧中点落在扇区**内部**，连接边横穿整个扇形 → 自交。
static func _hub_pt(arms: Array[PackedVector2Array], k: int) -> Vector2:
	var a0f: float = arms[k][0].angle()
	var a1f: float = arms[(k + 1) % arms.size()][0].angle()
	var g := a0f - a1f
	while g <= 0.0:
		g += TAU
	return Vector2.RIGHT.rotated(a0f - g * 0.5) * (arms[k][0].length() * 0.22)


## 多臂带状批绘：N 条折线（L4 牵引臂）按半宽 `hw` 扩成带状，**合成一次 draw**。
##   臂间的连接边同样穿过本体（②b 在 ③④ 之前 → 被舰体盖住）。
##   [param tip_w] > 0 时末点带宽加到 `hw + tip_w` 并拉出尖 —— 狂暴「末端血色符点」
##   就烘在这条带里，省下 N 次 `draw_circle`（02 §4.4 硬约束①的同款刀法）。
## 多臂合批的**排序与间隔守卫**（`_ribbons` / `_chain_arms` 共用）。
##   合批把 N 条臂串成**一个**多边形，所以任意两条臂在任意半径上都不能相交 —— 相交
##   就等于轮廓自交。做法：① 按角度**降序**排（与带状轮廓的绕向配套）；
##   ② 把挨太近的臂推开，最小间隔 = 两臂 curl 的收敛量 + `clr` 的带宽余量。
##   [param clr] **必须 ≥ 最宽带子的角宽**。L4 最宽的是转轴环带：半高 `hh = 0.062r`、
##   半长 `hw = 0.035r`，根半径 `0.72r` → 角宽 ≈ 2·(0.062+0.035)/0.72 = 0.269 rad。
##   取 0.30 留出 ~0.03 rad 余量；取 0.18 时（≈10px，带本身就有 9.5px）两臂根部的
##   侧向边会互相跨越 → 自交（随机扫描实测：0.18 → 303 处，0.30 → 0 处）。
##   实测（L4@r77，6 条臂）：扇形角距 0.905 rad、curl ±0.30 → 需求 0.90 rad，刚好够，
##   扇形形态一帧不改；只有「触须绷紧指向子核心」时子核心角度撞上扇形角才推开。
static func _sort_arms(angs: Array[float], curls: Array[float], clr: float = 0.30) -> void:
	var n := angs.size()
	if n < 2:
		return
	var i := 1
	while i < n:
		var ka: float = angs[i]
		var kc: float = curls[i]
		var j := i - 1
		while j >= 0 and angs[j] < ka:
			angs[j + 1] = angs[j]
			curls[j + 1] = curls[j]
			j -= 1
		angs[j + 1] = ka
		curls[j + 1] = kc
		i += 1
	# ② 间隔守卫 —— **必须全环形**：臂在圆上，`angs[n-1] → angs[0]` 的环绕段同样
	#   是一对相邻臂。只跑 k=1..n-1 会漏掉它，触须绷紧时首尾两臂就能贴到 7° 而自交。
	#   需求角距 = 两臂 curl 的收敛量 + 带宽余量 `clr`（臂端在 `angs+curl` 上，
	#   故 (angs[pv]+curl[pv]) − (angs[k]+curl[k]) ≥ clr ⇔ gap ≥ curl[k]−curl[pv] + clr）。
	var need: Array[float] = []
	var gap: Array[float] = []
	need.resize(n)
	gap.resize(n)
	for k in n:
		var pv := (k - 1 + n) % n
		need[k] = maxf(0.0, curls[k] - curls[pv]) + clr
		gap[k] = angs[pv] - angs[k]
		# ⚠ **只有环绕段（k=0）允许 +TAU**。k≥1 的段已经因降序而 ≥0；把 0 也当成
		#   「需要 +TAU」会让「两臂同角」变成「一整圈」，Σgap 就大于 TAU，
		#   重建出来的角度互相绕圈 → 自交（子核心分裂首帧两核都还在 (0,0) 时必现）。
		if k == 0 and gap[k] <= 0.0:
			gap[k] += TAU
	#    不足的段先补到 need；缺的量从富余段按富余比例扣。Σgap ≡ TAU，而
	#    Σneed ≤ n·(0.60 + clr) = 5.4 < TAU（n ≤ 6），故「缺 ≤ 富余」恒成立，一次就收敛。
	for _it in n:
		var def := 0.0
		for k in n:
			if gap[k] < need[k]:
				def += need[k] - gap[k]
				gap[k] = need[k]
		if def <= 0.0:
			break
		var slack := 0.0
		for k in n:
			slack += maxf(0.0, gap[k] - need[k])
		if slack <= 0.0:
			break
		for k in n:
			gap[k] -= def * maxf(0.0, gap[k] - need[k]) / slack
	# ③ 按 gap 重建角度：锚在 angs[0]，其余依次递减（结果必然仍是降序）
	for k in range(1, n):
		angs[k] = angs[k - 1] - gap[k]


static func _ribbons(ci: Node2D, arms: Array[PackedVector2Array], hw: float,
		col: Color, tip_w: float = 0.0) -> void:
	var p := PackedVector2Array()
	for k in arms.size():
		var pts: PackedVector2Array = arms[k]
		var n := pts.size()
		if n < 2:
			continue
		var nrms: Array[Vector2] = []
		nrms.resize(n)
		for i in n:
			var a: Vector2 = pts[maxi(0, i - 1)]
			var bb: Vector2 = pts[mini(n - 1, i + 1)]
			var d := bb - a
			if d.length() < 0.001:
				d = Vector2(1.0, 0.0)
			nrms[i] = d.normalized().rotated(PI * 0.5)
		# 同 `_chain_arms`：**先走 +nrm 侧**（臂按角度降序排，连接边才不会在臂根处
		#   跨过下一条臂 → 自交）
		for i in n:
			var w: float = hw + (tip_w if i == n - 1 else 0.0)
			p.append(pts[i] + nrms[i] * w)
		if tip_w > 0.0:
			var dl: Vector2 = pts[n - 1] - pts[n - 2]
			if dl.length() > 0.001:
				p.append(pts[n - 1] + dl.normalized() * tip_w)
		var j := n - 1
		while j >= 0:
			var w2: float = hw + (tip_w if j == n - 1 else 0.0)
			p.append(pts[j] - nrms[j] * w2)
			j -= 1
		# 同上：臂间连接折一次，经本体深处的枢纽点中转，避免进 / 出两条边自交
		if arms.size() >= 2:
			p.append(_hub_pt(arms, k))
	if p.size() >= 3:
		ci.draw_colored_polygon(p, col)


## 弧形底槽（L5 旗舰版传感器阵列 / 环形散热架的底槽弧）：一段圆环带，一次 draw。
static func _arc_band(ci: Node2D, rad: float, half_w: float, a0: float, a1: float,
		col: Color) -> void:
	var steps := 10
	var p := PackedVector2Array()
	var i := 0
	while i <= steps:
		var a: float = a0 + (a1 - a0) * float(i) / float(steps)
		p.append(Vector2.RIGHT.rotated(a) * (rad + half_w))
		i += 1
	i = steps
	while i >= 0:
		var a: float = a0 + (a1 - a0) * float(i) / float(steps)
		p.append(Vector2.RIGHT.rotated(a) * (rad - half_w))
		i -= 1
	ci.draw_colored_polygon(p, col)


## V4 推进舱（NEUTRAL 壳 + GLOW 焰心）—— 02 §3.0 新增层 ②c，恒在 +X 尾。
##   焰**不得朝 −X**（−X 是要害扇区，会被读成「头」）；壳不得越过 1.10r。
static func _thruster(ci: Node2D, x: float, y: float, w: float, h: float,
		g: Color, alpha: float) -> void:
	ci.draw_rect(Rect2(x, y, w, h), NEUTRAL)
	var fw := w * 0.72
	var fh := h * 0.60
	ci.draw_rect(Rect2(x + w * 0.22, y + h * 0.20, fw, fh),
		Color(g.r, g.g, g.b, alpha))


## V5 传感器阵列（02 §1.3 方案 A · 矩形窗）：**1 次 DARK 底槽 + 1 次合并窗芯 = 2 次 draw**
##   （§4.4「传感器阵列 ≤ 2」）。窗芯恒 `NEUTRAL`（`|B−R| = 0.12`）—— 玩家舱盖色
##   `|B−R| = 0.36` 被这条判据挡在外面；**无纯白描边、无 CORE 单点高光、≥3 枚成阵**。
##   ⚠ 底槽宽度按 pitch 反推（02 §3.1 P7 写的 0.34r 装不下 5 枚 4px 窗，实测最小 0.47r）。
static func _sensor_row(ci: Node2D, c: Vector2, n: int, pitch: float,
		win_w: float, win_h: float, dk: Color) -> void:
	var hw := win_w * 0.5
	var bus := 1.0
	var slot_w := pitch * float(n - 1) + win_w
	var org := Vector2(c.x, c.y - (bus + win_h) * 0.5)
	ci.draw_rect(Rect2(c.x - slot_w * 0.5 - 1.5, org.y - 1.5,
		slot_w + 3.0, bus + win_h + 3.0), dk)
	var ds := PackedFloat32Array()
	ds.resize(n)
	for i in n:
		ds[i] = (float(i) - float(n - 1) * 0.5) * pitch
	_comb(ci, org, Vector2(1.0, 0.0), Vector2(0.0, 1.0), ds, hw, bus, win_h, NEUTRAL)


## V5 舷窗列（02 §1.3 方案 B · 圆窗）：**1 次 DARK 眼窝槽 + 1 次合并窗芯 = 2 次 draw**。
##   圆窗用「切顶角的合并齿」表达 —— 2.5~3px 半径下方窗与圆窗不可分辨，且省掉逐枚 draw。
static func _portholes(ci: Node2D, c: Vector2, n: int, pitch: float,
		win_r: float, dk: Color) -> void:
	var bus := 1.0
	var hh := win_r * 2.0
	var slot_w := pitch * float(n - 1) + hh
	var org := Vector2(c.x, c.y - (bus + hh) * 0.5)
	ci.draw_rect(Rect2(c.x - slot_w * 0.5 - 1.3, org.y - 1.3,
		slot_w + 2.6, bus + hh + 2.6), dk)
	var ds := PackedFloat32Array()
	ds.resize(n)
	for i in n:
		ds[i] = (float(i) - float(n - 1) * 0.5) * pitch
	_comb(ci, org, Vector2(1.0, 0.0), Vector2(0.0, 1.0), ds, win_r, bus, hh,
		NEUTRAL, win_r * 0.62)


## V5 观察缝（02 §1.3 方案 C）：单条水平狭缝，**不倾斜**，DARK 槽 + NEUTRAL 芯（芯高 = 缝高 × 0.5）。
static func _view_slot(ci: Node2D, c: Vector2, w: float, h: float, dk: Color) -> void:
	ci.draw_rect(Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h), dk)
	ci.draw_rect(Rect2(c.x - w * 0.5 + 1.5, c.y - h * 0.25, w - 3.0, h * 0.5), NEUTRAL)


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
	# P2 散热鳍 ×8（沿环外缘等距，1.28r → 1.38r）—— 环读作「外挂式环形散热架」而非光环。
	#   狂暴：鳍转 RAGE α0.70（02 §3.6 狂暴行的明度 / 色相通道）
	var fcol := Color(RAGE.r, RAGE.g, RAGE.b, 0.70) if rage else NEUTRAL
	for i in 8:
		var a := spin * 0.5 + TAU * float(i) / 8.0
		var d := Vector2.RIGHT.rotated(a)
		var pp := d.rotated(PI * 0.5) * (r * 0.036)
		var i0 := d * (r * 1.28)
		var i1 := d * (r * 1.38)
		b.draw_colored_polygon(PackedVector2Array([i0 + pp, i1 + pp, i1 - pp,
			i0 - pp]), fcol)
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
##   机甲化（02 §3.1）：V1 六角 45° 倒角 / V2 装甲片分块缝 + 铆钉带 / V4 推进舱
##   / V5 传感器阵列 A（5 枚，侧向排布不朝 +X）。
##   狂暴：接缝渗 RAGE（§3.6）—— 走**换色**而不是另叠一层，不增加 draw。
static func draw_core(b: Node2D, pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(1)
	var m := main_col(c)
	var g := glow_col(c)
	var dk := dark_col(c)
	var rage := _gb(b, "enraged")
	# ③ DARK 外壳（×1.07）+ V1 45° 倒角（切角边长 0.08r = 4.5px @r56）
	b.draw_colored_polygon(_bevel(SIL_CORE, r * 1.07, 0.08 * r), dk)
	# ④ MAIN 主体（硬底线：不透明 MAIN 实心块）+ 倒角
	b.draw_colored_polygon(_bevel(SIL_CORE, r, 0.08 * r), m)
	# ⑤ NEUTRAL 结构件：内框六边
	_outline(b, _poly(SIL_CORE, r * 0.62), NEUTRAL, 2.0)
	# ⑤ V2 装甲片分块缝 ×6（片间留缝 → 读作 6 块独立装甲片，不是一整片）
	#   线宽硬钳位 maxf(1.5, 0.03r)：1px 在 canvas_items 拉伸下会断（02 §4.2）
	var seamc := SEAM.lerp(RAGE, 0.45) if rage else SEAM
	var sw := maxf(1.5, 0.03 * r)
	for i in 6:
		var a := TAU * float(i) / 6.0
		b.draw_line(Vector2.RIGHT.rotated(a) * (r * 0.62),
			Vector2.RIGHT.rotated(a) * (r * 0.95), seamc, sw, true)
	# ⑤ V2 铆钉带 ×2（沿上下两条直缝，各 5 枚 —— 合成 2 次 draw，不逐枚画）
	#   间距 0.16r = 9px ≥ 下限（< 9px 会糊成线）；铆钉 r maxf(2.0, 0.036r)
	#   ⚠ 不能把两行并成一次 `_chain_comb`：第 5→6 枚之间出现 180° 折返，
	#     齿的朝向跟着翻转、与相邻齿相交 → 轮廓自交 → triangulation failed
	var rw := maxf(2.0, 0.036 * r)
	var rds := PackedFloat32Array()
	rds.resize(5)
	for i in 5:
		rds[i] = (float(i) - 2.0) * (0.16 * r)
	for k in 2:
		var yy: float = (-0.80 + 1.60 * float(k)) * r
		_comb(b, Vector2(0.0, yy - rw), Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			rds, rw, 1.0, rw * 2.0, NEUTRAL, rw * 0.62)
	# ⑤b V5 传感器阵列 A（5 枚矩形窗，座在 y=−0.66r 的横向底槽里，**不朝 +X**）
	_sensor_row(b, Vector2(0.0, -0.66 * r), 5, 0.10 * r,
		maxf(4.0, 0.071 * r), maxf(3.0, 0.054 * r), dk)
	# ②c V4 推进舱（+X 尾，NEUTRAL 壳 + GLOW 焰心；焰不朝 −X，不越 1.10r）
	_thruster(b, 0.86 * r, -0.20 * r, 0.22 * r, 0.40 * r, g, 0.85)
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
		# 翼骨（承力梁）—— 三段折面的中轴
		b.draw_polyline(PackedVector2Array([root, j1, j2, tip]), NEUTRAL, 4.0, true)
		# P2 翼段接缝 ×2（三段折面的段间缝，SEAM）—— 有接缝才读作「三段独立装甲板」
		var sew := maxf(1.5, 0.04 * r)
		b.draw_line(j1 + perp * (w1 * 0.85), j1 - perp * (w1 * 0.62), SEAM, sew, true)
		b.draw_line(j2 + perp * (w2 * 0.85), j2 - perp * (w2 * 0.62), SEAM, sew, true)
		# P3 翼根挂架（NEUTRAL 0.10r × 0.06r）—— 标志器官一律「挂在挂架上」
		b.draw_rect(Rect2(root.x - 0.05 * r, root.y - 0.03 * r,
			0.10 * r, 0.06 * r), NEUTRAL)
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
	# ③ DARK 外壳 ×1.07 / ④ MAIN 主体 —— V1 45° 倒角（−X 尖端切 0.06r = 3.8px @r63）
	b.draw_colored_polygon(_bevel(SIL_WING, r * 1.07, 0.06 * r), dk)
	b.draw_colored_polygon(_bevel(SIL_WING, r, 0.06 * r), m)
	# ⑤ 结构线 ×2（寒霜四色结构线语言，§E.5 硬约束：器官不得覆盖它）
	b.draw_line(Vector2(-0.34, -0.46) * r, Vector2(0.55, -0.10) * r, dk, 2.0, true)
	b.draw_line(Vector2(-0.34, 0.46) * r, Vector2(0.55, 0.10) * r, dk, 2.0, true)
	# 甲板散热面：展开度越高露得越多（= "窗口打开"的形状读数）
	#   V4 机甲化：原来的一块实心面改成 **5 条 1.5px 平行散热格栅**（合成 2 次 draw）
	var open := clampf(float(ph - 1) / 2.0, 0.0, 1.0)
	for i in 2:
		var yy: float = (-0.28 + 0.44 * float(i)) * r
		var ds := PackedFloat32Array()
		ds.resize(5)
		for j in 5:
			ds[j] = float(j) * (0.03 * r)
		_comb(b, Vector2(-0.52 * r, yy), Vector2(0.0, 1.0), Vector2(1.0, 0.0),
			ds, 0.75, 1.0, 0.62 * r, Color(g.r, g.g, g.b, 0.18 + 0.45 * open))
	# ⑤ V3 能量导管（贴上 / 下弦走，3.0px，GLOW α0.55）——
	#   禁止玩家同款「身后 10 点正弦尾带」，那条是玩家专属
	var cond := Color(g.r, g.g, g.b, 0.55)
	b.draw_line(Vector2(-0.20, -0.33) * r, Vector2(0.55, -0.35) * r, cond, 3.0, true)
	b.draw_line(Vector2(-0.20, 0.33) * r, Vector2(0.55, 0.35) * r, cond, 3.0, true)
	# ⑤b V5 舷窗列 B（4 枚圆窗，沿舰体纵向排布，不朝 +X）
	_portholes(b, Vector2(0.10 * r, -0.44 * r), 4, 0.16 * r,
		maxf(2.5, 0.045 * r), dk)
	# ②c V4 推进舱（+X 尾）
	_thruster(b, 0.80 * r, -0.16 * r, 0.20 * r, 0.32 * r, g, 0.85)
	# ⑧ CORE 要害核
	_core_socket(b, r, c, pulse, -r * 0.30)


# ================================================================ L3 耀斑号 · 炮列
## −X 舷一列炮塔（4 / 6 / 8 门随阶段，中轴留空让开 CORE），炮管 NEUTRAL、炮口 GLOW。
##   散热期：全部炮口喷 GLOW 焰 —— 与「甲壳缺口 + 白光」一起构成三层冗余。
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
	# 炮塔的 y 序列（中轴留空让开 CORE —— 要害扇区 −X±40° 内除 CORE 外不得有部件）
	var ys := PackedFloat32Array()
	ys.resize(n)
	for j in half:
		var off: float = (0.17 + 0.16 * float(j)) * r
		ys[half - 1 - j] = -off
		ys[half + j] = off
	var ds := PackedFloat32Array()
	ds.resize(n)
	var ymin: float = ys[0]
	for i2 in n:
		ds[i2] = ys[i2] - ymin
	# P1 炮塔座 ×n（NEUTRAL，0.20r × 0.11r，+45° 倒角由矩形近似）→ **1 次** draw
	var bx := -0.646 * r
	_comb(b, Vector2(bx - 0.16 * r, ymin - 0.055 * r), Vector2(0.0, 1.0),
		Vector2(1.0, 0.0), ds, 0.055 * r, 1.0, 0.20 * r, NEUTRAL)
	# P2 炮塔挂梁 ×n（NEUTRAL，0.06r × 0.03r，座下）→ 读作「挂载武器」而非「身体长刺」
	_comb(b, Vector2(bx - 0.09 * r, ymin + 0.070 * r), Vector2(0.0, 1.0),
		Vector2(1.0, 0.0), ds, 0.015 * r, 1.0, 0.06 * r, NEUTRAL)
	# 散热期：全部炮口喷 GLOW 焰（外晕 + 焰心各合成 1 次 draw）
	if vent:
		_comb(b, Vector2(bx - 0.45 * r, ymin), Vector2(0.0, 1.0),
			Vector2(1.0, 0.0), ds, 0.13 * r, 1.0, 0.26 * r,
			Color(g.r, g.g, g.b, 0.30), 0.13 * r * 0.62)
		_comb(b, Vector2(bx - 0.315 * r, ymin), Vector2(0.0, 1.0),
			Vector2(1.0, 0.0), ds, 0.075 * r, 1.0, 0.15 * r,
			Color(g.r, g.g, g.b, 0.90), 0.075 * r * 0.62)
	# P1 炮口（GLOW α0.95）—— 逐门画，它是炮塔的识别点，不合并
	for j in half:
		var off: float = (0.17 + 0.16 * float(j)) * r
		for k in 2:
			var sg: float = -1.0 + 2.0 * float(k)
			_turret(b, r, sg * off, g)


## 单门炮塔：**炮口**（GLOW α0.95）。座与挂梁已合并进 `_l3_guns` 的两次批绘
##   （02 §4.4 硬约束①）。`bx` 必须锁在 SIL_BATTERY 的 −X 顶点 x —— V7 静态校验读它。
static func _turret(ci: Node2D, r: float, y: float, g: Color) -> void:
	var bx := -0.646 * r
	ci.draw_circle(Vector2(bx - r * 0.18, y), r * 0.055, Color(g.r, g.g, g.b, 0.95))


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
	# ③④ V1 45° 倒角（0.06r）+ 硬底线：不透明 MAIN 实心块
	var sil := _bevel(SIL_BATTERY, r, 0.06 * r)
	b.draw_colored_polygon(_bevel(SIL_BATTERY, r * 1.06, 0.06 * r), dk)
	b.draw_colored_polygon(sil, m)
	# 🔴 强制 3px `CORE[WHITE]` 外描边（02 §4.3：红本体对比仅 3.15:1 的补偿，**不得删**）
	_outline(b, sil, core_col(Game.WHITE), 3.0)
	# ⑤ NEUTRAL 结构件 30%：横向装甲带 ×3（V7：x0 内缩于 −X 顶点，右端不越舰体右界）
	for i in 3:
		var yy: float = (-0.456 + 0.456 * float(i)) * r
		b.draw_rect(Rect2(-0.514 * r, yy, 1.060 * r, 0.07 * r), NEUTRAL)
	# ⑤ V2 带间铆钉 4 枚/带（r 2.5px）—— 每带合成 **1 次** draw，共 3 次
	#   ⚠ 铆钉压在 NEUTRAL 装甲带上，同色会隐身 → 用 NEUTRAL_DK 读作「紧固件沉孔」
	var rds := PackedFloat32Array()
	rds.resize(4)
	for j in 4:
		rds[j] = (-0.35 + 0.23 * float(j)) * r
	for i in 3:
		var yc: float = (-0.456 + 0.456 * float(i)) * r + 0.035 * r
		_comb(b, Vector2(0.0, yc - 2.5), Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			rds, 2.5, 1.0, 5.0, NEUTRAL_DK, 1.6)
	# ⑤b V5 观察缝 C（0.30r × maxf(3,0.054r)，**水平不倾斜**，DARK 槽 + NEUTRAL 芯）
	_view_slot(b, Vector2(0.02 * r, -0.58 * r), 0.30 * r, maxf(3.0, 0.054 * r), dk)
	# ⑤ V6 告警条纹（狂暴，45° 斜纹 RAGE α0.35，条宽 6px / 间距 6px）
	if _gb(b, "enraged"):
		var hs := PackedFloat32Array()
		hs.resize(6)
		for j in 6:
			hs[j] = float(j) * 12.0
		_comb(b, Vector2(-0.55 * r, -0.70 * r), Vector2(1.0, 0.0),
			Vector2(0.7071, 0.7071), hs, 3.0, 1.0, 9.0,
			Color(RAGE.r, RAGE.g, RAGE.b, 0.35))
	# ②c +X 推进舱（NEUTRAL 壳 + GLOW 焰心）—— 全五关的范本
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
	# 轨道半径 = R_MAIN × 1.95（Boss4.SubCore._process 定的）。不在轨道带上的一律丢掉：
	#   分裂首帧子核心的 `position` 还是 (0,0)（它自己的 _process 尚未跑过），此时
	#   局部偏移长度 ≈ 700px 且**两核同角** —— 拿它去定向触须既画错方向，又会让
	#   `_sort_arms` 收到两条同角臂。丢掉即降级成扇形基础形态，一帧后自动恢复。
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
	var exposed := _is_exposed(b)
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
	# 臂的角度 / 弯向先算出来再排序 —— 合批要求臂之间互不相交（见 `_sort_arms`）
	var angs: Array[float] = []
	var curls: Array[float] = []
	angs.resize(n)
	curls.resize(n)
	for i in n:
		var a := -PI * 0.72 + (PI * 1.44) * (float(i) / float(maxi(1, n - 1)))
		var cv := 0.30 if (i % 2 == 0) else -0.30
		if tense and i < cores.size():
			var cp: Vector2 = cores[i]
			a = cp.angle()
			cv = 0.0                        # 绷紧 = 直线
		angs[i] = a
		curls[i] = cv
	_sort_arms(angs, curls, 0.30)
	# 三条批绘队列：**所有臂合成 1 次 draw**（02 §4.4 硬上限 40 —— 逐臂画 6 条就是
	#   18~30 次，L4 直接爆表）。臂间的连接边穿过本体，被 ③④ 的不透明舰体盖住。
	var chains: Array[PackedVector2Array] = []      # P2 转轴环 + P3 夹爪（NEUTRAL）
	var arms: Array[PackedVector2Array] = []        # P1 牵引臂（DARK 6px）
	var stubs: Array[PackedVector2Array] = []       # 暴露期断口外的残端（脱体，不能合批）
	for i in n:
		var a: float = angs[i]
		var curl: float = curls[i]
		var p0 := Vector2.RIGHT.rotated(a) * (r * 0.72)
		if exposed:
			# 暴露期：能量索已断 —— 短一截 + 断口空隙 + 缩回的残端
			#   **残端不再有 GLOW**（能量索断了就没能量了），这也是省下 1 次 draw 的语义依据
			var b1 := Vector2.RIGHT.rotated(a + curl * 0.3) * (r * 0.92)
			var b2 := Vector2.RIGHT.rotated(a + curl * 0.5) * (r * 1.02)
			# P2 转轴环：缩回的残端上只剩 2 节套管
			chains.append(PackedVector2Array([p0,
				Vector2.RIGHT.rotated(a + curl * 0.15) * (r * 0.82), b1]))
			arms.append(PackedVector2Array([p0, b1]))
			# 残端与本体之间有断口空隙 —— 合批会拿连接边把断口填掉，故逐条画
			stubs.append(PackedVector2Array([b2,
				Vector2.RIGHT.rotated(a + curl * 0.7) * (r * 1.14)]))
			continue
		var p1 := Vector2.RIGHT.rotated(a + curl * 0.35) * (r * 1.00 + ext)
		var p2 := Vector2.RIGHT.rotated(a + curl * 0.70) * (r * 1.28 + ext)
		var jy := sin(t * 5.0 + float(i)) * 2.0      # 末端 ±2px 抖动
		var tip := Vector2.RIGHT.rotated(a + curl) * (r * 1.55 + ext)
		tip.y += jy
		# P2 转轴环 ×3（节点处）+ P3 末端夹爪
		chains.append(PackedVector2Array([p0, p1, p2, tip]))
		arms.append(PackedVector2Array([p0, p1, p2, tip]))
	# **先画链后画臂**：连杆被 6px 的臂盖住，只留套管突出两侧 → 读作「分节机械臂」
	_chain_arms(b, chains, 0.035 * r, 0.062 * r, NEUTRAL)
	_ribbons(b, arms, 3.0, dk)
	if not stubs.is_empty():
		for k in stubs.size():
			b.draw_polyline(stubs[k], dk, 5.0, true)
		return
	_ribbons(b, arms, 1.75, Color(g.r, g.g, g.b, 0.70))
	if rage:
		# 狂暴：触须全部亮起电浆红覆描 + 末端血色符点（符点烘在带末端的尖里，不另开 draw）
		_ribbons(b, arms, 0.80, Color(rage_c.r, rage_c.g, rage_c.b, 0.80),
			r * 0.055)


## 子核心存活 → 触须末端拉出能量索连到子核心（GLOW α0.6），玩家读「打子核心去」；
##   暴露期 → 能量索断裂（不画），改由 `Boss._draw()` 的护罩弧接管读「现在要换甲破罩」。
static func _l4_tethers(b: Node2D, _pulse: float) -> void:
	var r := r_main_of(b)
	var c := boss_main_c(4)
	var g := glow_col(c)
	var cores := _sub_core_local(b)
	if cores.is_empty() or _is_exposed(b):
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
	var exposed := _is_exposed(b)
	# ③④ V1 45° 倒角（0.06r）+ 硬底线：不透明 MAIN 实心块
	var sil := _bevel(SIL_MAW, r, 0.06 * r)
	b.draw_colored_polygon(_bevel(SIL_MAW, r * 1.06, 0.06 * r), dk)
	b.draw_colored_polygon(sil, m)
	# ⑤ NEUTRAL 结构件 30%：上下两条纵向装甲带
	b.draw_rect(Rect2(-0.30 * r, -0.86 * r, 1.10 * r, 0.09 * r), NEUTRAL)
	b.draw_rect(Rect2(-0.30 * r, 0.77 * r, 1.10 * r, 0.09 * r), NEUTRAL)
	# ⑤ V2 铆钉（沿两条装甲带，各 5 枚，合成 2 次 draw）—— NEUTRAL_DK 沉孔读法（同 L3）
	var rds := PackedFloat32Array()
	rds.resize(5)
	for j in 5:
		rds[j] = (-0.15 + 0.22 * float(j)) * r
	for k in 2:
		var yc: float = (-0.815 + 1.63 * float(k)) * r
		_comb(b, Vector2(0.0, yc - 2.5), Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			rds, 2.5, 1.0, 5.0, NEUTRAL_DK, 1.6)
	# ⑥ 机库牵引闸门（原深渊之口）—— **读 `_is_exposed()`，与能量索 / 护罩弧同一帧同相位**
	var mx := -0.62 * r
	if exposed:
		# 闸门**关闭**：腔内改 DARK 实心（不再是「能打进去的口」）
		b.draw_circle(Vector2(mx, 0.0), r * 0.42, dk)
	else:
		b.draw_circle(Vector2(mx, 0.0), r * 0.42, Color(0.04, 0.03, 0.08, 0.95))
		b.draw_arc(Vector2(mx, 0.0), r * 0.42, PI * 0.55, PI * 1.45, 20,
			Color(g.r, g.g, g.b, 0.85), 4.0, true)
	# P6 闸齿 ×6（三角 0.08r；暴露期内收 0.03r）—— 合成 1 次 draw
	var ts := PackedFloat32Array()
	ts.resize(6)
	for j in 6:
		ts[j] = float(j) * (0.12 * r)
	_comb(b, Vector2(-0.74 * r + (0.03 * r if exposed else 0.0), -0.30 * r),
		Vector2(0.0, 1.0), Vector2(-1.0, 0.0), ts, 0.04 * r,
		1.0, 0.08 * r * (0.60 if exposed else 1.0), NEUTRAL)
	# ⑦ 电浆红能量纹 ×3（§C.1：引力黄本体 + 电浆红能量纹）—— 合成 1 次 draw
	var acm: Color = Game.COLOR_MAIN[boss_accent_c(4)]
	var eds := PackedFloat32Array()
	eds.resize(3)
	for j in 3:
		eds[j] = float(j) * (0.34 * r)
	_comb(b, Vector2(-0.18 * r, -0.34 * r), Vector2(0.0, 1.0), Vector2(1.0, 0.0),
		eds, 1.5, 1.0, 0.96 * r, Color(acm.r, acm.g, acm.b, 0.70))
	# ⑤b V5 舷窗列 B（5 枚，沿上弦纵向排布）
	_portholes(b, Vector2(0.10 * r, -0.55 * r), 5, 0.14 * r,
		maxf(2.5, 0.04 * r), dk)
	# ②c V4 推进舱（+X 尾）
	_thruster(b, 0.90 * r, -0.18 * r, 0.20 * r, 0.36 * r, g, 0.85)
	# ⑥ 暴露期飘字（A2：一律走 `DrawUtil.txt()`；ow=0 → 只 1 次 draw_string）
	if exposed:
		DrawUtil.txt(b, "暴露期", Vector2(0.0, -1.18 * r), 15,
			Color(0.95, 0.97, 1.0, 0.92), HORIZONTAL_ALIGNMENT_CENTER,
			Color(0.02, 0.03, 0.06, 0.9), 0.0)
	# ⑧ CORE 要害核（坐在闸门腔内）
	_core_socket(b, r, c, pulse, mx)


# ================================================================ L5 终焉号 · 分身
## ±Y 侧各一枚半透明相位残影：α0.30、**无 CORE**、呼吸滞后 0.18s
##   （同相位会读成「一个更厚的实体」，**必须滞后**才读成「影子」）。
##   残影数随四相重构 0 → 1 → 2 → 3（第 3 枚在 −X 侧，形成「三面围拢」）。
##   狂暴：α 0.30 → 0.45（变实 = 威胁升级的明度通道；但残影外缘 196px 比狂暴圈 189px
##     还大却无碰撞 / 无 CORE / 不受击，0.55 会把威胁感给到假目标，故压到 0.45 降视觉权重）。
static func _l5_echoes(b: Node2D, _pulse: float) -> void:
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
	# ③④ V1 45° 倒角（0.06r）+ 硬底线：中性钢灰实心块（L5 不绑定四色）
	var sil := _bevel(SIL_THRONE, r, 0.06 * r)
	b.draw_colored_polygon(_bevel(SIL_THRONE, r * 1.06, 0.06 * r), dk)
	b.draw_colored_polygon(sil, m)
	# ⑤ NEUTRAL 结构线：中轴脊 + 上下弦（保住「颜色 + 形状」双通道的形状侧）
	b.draw_line(Vector2(-0.90 * r, 0.0), Vector2(0.72 * r, 0.0), NEUTRAL_DK, 3.0, true)
	b.draw_line(Vector2(-0.40 * r, -0.22 * r), Vector2(0.52 * r, -0.12 * r),
		NEUTRAL, 2.0, true)
	b.draw_line(Vector2(-0.40 * r, 0.22 * r), Vector2(0.52 * r, 0.12 * r),
		NEUTRAL, 2.0, true)
	# ⑥ 四色轮转能量纹（−X 指向的箭羽 ×3）—— 每支箭羽的两条线首尾相接，合成 1 次 polyline
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
	# ⑤b V5 传感器阵列 A · 旗舰版（7 枚**弧形排列**）：底槽弧 1 次 + 窗芯 1 次 = 2 次 draw
	var a0 := deg_to_rad(-68.0)
	var a1 := deg_to_rad(-8.0)
	var arc_r := 0.40 * r
	_arc_band(b, arc_r, maxf(3.0, 0.036 * r), a0, a1, dk)
	var wcs: Array[Vector2] = []
	wcs.resize(7)
	for i in 7:
		wcs[i] = Vector2.RIGHT.rotated(a0 + (a1 - a0) * float(i) / 6.0) * arc_r
	_chain_comb(b, wcs, minf(2.4, 0.036 * r), maxf(2.25, 0.027 * r), NEUTRAL, 0.5)
	# ②c V4 三连推进舱（3 × 0.18r × 0.10r）—— 壳 1 次 + 焰心 1 次 = 2 次 draw
	var tds := PackedFloat32Array()
	tds.resize(3)
	for i in 3:
		tds[i] = (-0.24 + 0.24 * float(i)) * r
	_comb(b, Vector2(0.80 * r, -0.29 * r), Vector2(0.0, 1.0), Vector2(1.0, 0.0),
		tds, 0.05 * r, 1.0, 0.18 * r, NEUTRAL)
	_comb(b, Vector2(0.92 * r, -0.27 * r), Vector2(0.0, 1.0), Vector2(1.0, 0.0),
		tds, 0.03 * r, 1.0, 0.10 * r, Color(wc.r, wc.g, wc.b, 0.85))
	# ⑧ CORE 要害核
	_core_socket(b, r, c, pulse, -r * 0.42)
