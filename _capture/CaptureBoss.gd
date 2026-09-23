extends Node2D
## 五关旗舰「模型图」截帧（真窗口运行，**不可 --headless**）
##   关卡由场景根节点 metadata `stage` 指定（2~5）。把该关旗舰按实机矢量绘制
##   （`BossArt.*`）放大定格，配部件编号徽章 + 部件清单面板 + 三态速览。
##   规格依据 `design/art/02-Boss机甲化视觉规格.md` §3.2 ~ §3.5。
## 产物：D:/demo/_boss_l{stage}_model.png
##
## 与 L1 专用场景（`CaptureBossL1.tscn`）同构，区别是本文件用「stage 分派」把五关
##   的缩放 / 编号点位 / 清单文案 / 三态配置收在一处，避免每关复制一份脚本。

const OUT_FMT := "D:/demo/_boss_l%d_model.png"
const HERO_POS := Vector2(360.0, 384.0)
const MINI_Y := 578.0
const MINI_X := [790.0, 980.0, 1170.0]
const CAPTION_Y := 470.0
const NOTE_Y := 698.0
const PANEL_X := 672.0
const PANEL_W := 576.0

## 主视图 / 三态速览的缩放：越大的旗舰放得越小（L5 残影外缘 1.5r 最吃画面）
const MAIN_SC := [0.0, 2.60, 2.30, 2.00, 1.70, 1.45]
const MINI_SC := [0.0, 1.10, 0.95, 0.72, 0.62, 0.58]
## 玩家两件战甲 S（护罩色 / L4 子核心色一律 ∈ S —— 可行性铁律）
const ARMOR_A := [0, 1, 1, 3, 2]
const ARMOR_B := [0, 2, 2, 1, 1]
## 主视图相位 / 护罩色（-1 = 该关本态不展罩）
const MAIN_PH := [0, 2, 3, 3, 3, 4]
const MAIN_WARD := [0, 0, -1, -1, -1, 2]
## L4 两枚子核心的定格方位（±50° → 落在 +X 与 ±Y 半侧，避开 −X±40° 要害扇区）
const CORE_DEG := [-50.0, 50.0]

var stage: int = 1
var _hero: Boss = null
var _minis: Array[Boss] = []
var _mini_flags: PackedInt32Array = PackedInt32Array()
var _mini_ph: PackedInt32Array = PackedInt32Array()
var _mini_ward: PackedInt32Array = PackedInt32Array()
var _overlay: Node2D = null
var _stars: PackedVector2Array = PackedVector2Array()
var _star_a: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	stage = int(get_meta("stage", 1))
	Game.picked_armors = [_armor_a(), _armor_b()]
	_seed_stars()
	_bg()
	_mini_ph = _mini_phases()
	_mini_ward = _mini_wards()
	_mini_flags = _mini_flagset()
	_hero = _make_boss(HERO_POS, _main_sc(), _main_ph(), _main_ward(), 0)
	# 编号徽章覆盖层：Boss._ready 里 z_index=10，覆盖层必须更高
	_overlay = Node2D.new()
	_overlay.z_index = 20
	add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)
	_ui()
	for i in 3:
		_minis.append(_make_boss(Vector2(_mini_x(i), MINI_Y), _mini_sc(),
			_mini_ph[i], _mini_ward[i], _mini_flags[i]))
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_FMT % stage)
	print("CAPTURE_SAVED ", OUT_FMT % stage)
	get_tree().quit()


func _process(_delta: float) -> void:
	# 主视图定格：_t 归零 → 翼 / 环 / 残影落在整数方位，与编号点位对齐
	if _hero != null and is_instance_valid(_hero):
		_apply(_hero, _main_ph(), _main_ward(), 0, _main_sc())
	for i in _minis.size():
		_apply(_minis[i], _mini_ph[i], _mini_ward[i], _mini_flags[i], _mini_sc())
	queue_redraw()


## 造一台只摆姿势的旗舰：_st="pose" 让 _process 只推进 _t —— 不移动 / 不开火 /
##   护罩状态机不接管（ward / enraged / venting / exposed 全由本文件指定）
func _make_boss(pos: Vector2, sc: float, ph: int, ward_c: int, flags: int) -> Boss:
	var b: Boss = Boss4.new() if stage == 4 else Boss.new()
	b.stage = stage
	b.phase = ph
	b.player_armors = [_armor_a(), _armor_b()]
	b.world = self
	b._home_x = pos.x
	b._base_y = pos.y
	b.scale = Vector2(sc, sc)
	add_child(b)
	b.position = pos
	b._st = "pose"
	_apply(b, ph, ward_c, flags, sc)
	return b


## 每帧把形态字段压回目标值（Boss 自身状态机在 pose 态不会改它们，这里只做保险）
func _apply(b: Boss, ph: int, ward_c: int, flags: int, sc: float) -> void:
	b._t = 0.0
	b._ward_anim = 0.0
	b._ward_t = 99.0
	b.phase = ph
	b.ward = ward_c
	b.enraged = (flags & 1) != 0
	b.venting = (flags & 2) != 0
	b._exposed_win = (flags & 4) != 0
	_fix_cores(b, flags, sc)


## L4 子核心：关掉它自己的 _process（否则公转会跑），由本文件定格方位 + 同步缩放
##   —— 子核心是 world 的独立子节点，不吃 Boss 的 scale，轨道半径也要乘 sc
func _fix_cores(b: Boss, flags: int, sc: float) -> void:
	if stage != 4:
		return
	var v: Variant = b.get("_cores")
	if not (v is Array):
		return
	var arr: Array = v
	var hide := (flags & 8) != 0
	var orbit := float(StageCfg.boss_r_main(4)) * 1.95 * sc
	for i in arr.size():
		var core: Node2D = arr[i] as Node2D
		if core == null:
			continue
		core.set_process(false)
		core.visible = not hide
		core.scale = Vector2(sc, sc)
		core.position = b.position + Vector2.RIGHT.rotated(
			deg_to_rad(_core_deg(i))) * orbit


func _bg() -> void:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.05, 0.09)
	r.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.name = "BG"
	add_child(r)


func _seed_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260922
	for i in 80:
		_stars.append(Vector2(rng.randf_range(0.0, 1280.0),
			rng.randf_range(0.0, 720.0)))
		_star_a.append(rng.randf_range(0.15, 0.65))


func _draw() -> void:
	for i in _stars.size():
		var p := _stars[i]
		draw_circle(p, 1.0, Color(0.85, 0.90, 1.0, _star_a[i] * 0.35))


## 编号徽章画在覆盖层（渲染序在 Boss 之后 → 不会被机体盖住）：
##   白底 + 深边 + 深字 —— 在暗太空底与各色本体上都读得清
func _on_overlay_draw() -> void:
	var pts := _part_points()
	for i in pts.size():
		var p: Vector2 = pts[i]
		_overlay.draw_circle(p, 12.0, Color(0.95, 0.97, 1.0, 0.95))
		_overlay.draw_arc(p, 12.0, 0.0, TAU, 20, Color(0.10, 0.12, 0.18, 0.95), 2.5, true)


## 部件编号点位（局部单位坐标 × R_MAIN × 主视图缩放 + 主视图中心）
func _part_points() -> Array[Vector2]:
	var rs: float = float(StageCfg.boss_r_main(stage)) * _main_sc()
	var loc := _part_local()
	var out: Array[Vector2] = []
	for i in loc.size():
		var p: Vector2 = loc[i]
		out.append(HERO_POS + p * rs)
	return out


## 逐关部件点位（**单位 r** 局部坐标；−X = 头 / +X = 尾，y 向下为正）
func _part_local() -> Array[Vector2]:
	match stage:
		2:
			return _pts_l2()
		3:
			return _pts_l3()
		4:
			return _pts_l4()
		_:
			return _pts_l5()
	return PackedVector2Array()


## L2：翼几何与 `BossArt._l2_wings` 同式（spread=80°，t=0 → beat=0，取上翼 sg=-1）
func _pts_l2() -> Array[Vector2]:
	var dir := Vector2.RIGHT.rotated(-deg_to_rad(80.0))
	var perp := dir.rotated(PI * 0.5)
	var root := Vector2(-0.16, -0.50)
	var j1 := root + dir * 0.32 + perp * 0.06
	var j2 := root + dir * 0.62 - perp * 0.06
	var tip := root + dir * 0.85
	return [
		(root + j1) * 0.5 + perp * 0.13,   # ① 翼板（三段折面 · GLOW α0.55）
		(j1 + j2) * 0.5 + perp * 0.10,     # ② 翼骨（承力梁）+ 段间接缝
		(j2 + tip) * 0.5,                  # ③ 翼尖（狂暴伸 4 枚霜刃）
		root,                              # ④ 翼根挂架
		Vector2(-1.02, 0.0),               # ⑤ 菱形舰体（DARK×1.07 + 倒角）
		Vector2(-0.21, -0.28),             # ⑥ 甲板散热格栅 ×2
		Vector2(0.18, -0.34),              # ⑦ 能量导管（沿上/下弦）
		Vector2(0.34, -0.44),              # ⑧ 舷窗列 B ×4
		Vector2(0.90, -0.16),              # ⑨ 推进舱（+X 尾）
		Vector2(-0.30, 0.0),               # ⑩ CORE 要害核
	]


## L3：甲壳弧标在段中心（8 段，段间 0.16 rad 缺口，−90° 正好落在缺口里 → 取 292.5°）
func _pts_l3() -> Array[Vector2]:
	var seg := Vector2.RIGHT.rotated(deg_to_rad(292.5)) * 1.80
	return [
		seg,                               # ① 暗甲壳弧 ×1.80（8 段 DARK）
		Vector2(-0.706, -0.65),            # ② 炮塔座 ×8
		Vector2(-0.826, -0.65),            # ③ 炮口 ×8（GLOW α0.95）
		Vector2(-0.676, -0.58),            # ④ 炮塔挂梁 ×8
		Vector2(0.30, -0.72),              # ⑤ 长方炮垒（+3px 白描边）
		Vector2(-0.20, -0.42),             # ⑥ 横向装甲带 ×3 + 铆钉
		Vector2(0.02, -0.58),              # ⑦ 观察缝 C（水平不倾斜）
		Vector2(0.74, 0.0),                # ⑧ 推进舱（+X 尾）
		Vector2(-0.10, 0.0),               # ⑨ CORE 要害核
	]


## L4：触须取绷紧态（指向 −50° 那枚子核心），与被牵引的子核心一起标
func _pts_l4() -> Array[Vector2]:
	return [
		Vector2.RIGHT.rotated(deg_to_rad(-50.0)) * 1.00,  # ① 牵引臂（3 节）
		Vector2.RIGHT.rotated(deg_to_rad(-50.0)) * 0.75,  # ② 转轴环 ×3
		Vector2.RIGHT.rotated(deg_to_rad(-50.0)) * 1.55,  # ③ 末端夹爪
		Vector2.RIGHT.rotated(deg_to_rad(-50.0)) * 1.95,  # ④ 子核心（色 ∈ S）+ 能量索
		Vector2(0.02, -0.90),                             # ⑤ 宽厚六边母舰
		Vector2(0.25, -0.815),                            # ⑥ 纵向装甲带 ×2 + 铆钉
		Vector2(-0.62, 0.0),                              # ⑦ 机库牵引闸门（CORE 坐腔内）
		Vector2(-0.74, -0.24),                            # ⑧ 闸齿 ×6
		Vector2(0.30, -0.34),                             # ⑨ 电浆红能量纹 ×3
		Vector2(0.38, -0.55),                             # ⑩ 舷窗列 B ×5
		Vector2(1.00, 0.0),                               # ⑪ 推进舱（+X 尾）
	]


func _pts_l5() -> Array[Vector2]:
	return [
		Vector2(0.0, -1.50),               # ① 相位残影 ×3（上下 + −X，α0.30）
		Vector2(0.66, -0.32),              # ② 纺锤本体（STEEL_DARK×1.06 / STEEL）
		Vector2(0.30, 0.0),                # ③ 结构线（中轴脊 + 上下弦）
		Vector2(-0.34, -0.30),             # ④ 四色轮转能量纹（箭羽 ×3）
		Vector2.RIGHT.rotated(deg_to_rad(-38.0)) * 0.40,  # ⑤ 传感器阵列 A · 旗舰版 ×7
		Vector2(0.89, -0.24),              # ⑥ 三连推进舱 ×3
		Vector2(-0.42, 0.0),               # ⑦ CORE 要害核
		Vector2.RIGHT.rotated(deg_to_rad(-30.0)) * 1.70,  # ⑧ 属性护罩弧 ×1.70（ALWAYS）
	]


# ------------------------------------------------------------ 常量表访问器
## const 数组取出的元素是 Variant，直接 `var x := arr[i]` 推不出类型（项目既有坑），
##   一律走带返回类型的访问器。
func _main_sc() -> float:
	return MAIN_SC[stage]


func _mini_sc() -> float:
	return MINI_SC[stage]


func _mini_x(i: int) -> float:
	return MINI_X[i]


func _main_ph() -> int:
	return MAIN_PH[stage]


func _main_ward() -> int:
	return MAIN_WARD[stage]


func _armor_a() -> int:
	return ARMOR_A[stage - 1]


func _armor_b() -> int:
	return ARMOR_B[stage - 1]


func _core_deg(i: int) -> float:
	return CORE_DEG[i % 2]


# ------------------------------------------------------------ 文案（design/art/02 §3.2~3.5）
func _title() -> String:
	match stage:
		2:
			return "第二关 BOSS 模型 · 霜噬号 · 星盗霜舰"
		3:
			return "第三关 BOSS 模型 · 耀斑号 · 星盗炮垒"
		4:
			return "第四关 BOSS 模型 · 深渊之喉 · 星盗母舰"
		_:
			return "第五关 BOSS 模型 · 终焉号 · 星盗王"
	return ""


func _sub() -> String:
	match stage:
		2:
			return "L2 旗舰 · 实机矢量绘制（BossArt · SIL_WING 菱形舰体 ×2.30）· 本体寒霜蓝 · −X 头 / +X 尾"
		3:
			return "L3 旗舰 · 实机矢量绘制（BossArt · SIL_BATTERY 长方炮垒 ×2.00）· 电浆红 + 强制 3px 白描边"
		4:
			return "L4 旗舰 · 实机矢量绘制（BossArt · SIL_MAW 宽厚六边母舰 ×1.70）· 引力黄本体 + 电浆红能量纹"
		_:
			return "L5 旗舰 · 实机矢量绘制（BossArt · SIL_THRONE 纺锤旗舰 ×1.45）· 中性钢灰（不绑四色）"
	return ""


func _items() -> PackedStringArray:
	match stage:
		2:
			return PackedStringArray([
				"① 折翼 ×2（翼根 ±Y · 翼尖朝 +X · 展开角 25°/55°/80°）",
				"② 翼骨（承力梁 4px）+ 翼段接缝 ×2（SEAM）",
				"③ 翼尖（狂暴伸 4 枚 GLOW 三角霜刃 · 两侧共 8 枚）",
				"④ 翼根挂架 ×2（0.10r × 0.06r · 标志器官挂挂架）",
				"⑤ 菱形舰体：DARK 壳 ×1.07 + MAIN 主体 · −X 尖倒角",
				"⑥ 甲板散热格栅 ×2（各 5 条 1.5px · α 随展开度）",
				"⑦ 能量导管（沿上/下弦 · GLOW α0.55 · 非玩家尾带）",
				"⑧ 舷窗列 B ×4（DARK 眼窝 + NEUTRAL 芯 · 不朝 +X）",
				"⑨ 推进舱 +X（NEUTRAL 壳 + GLOW 焰心）＋⑩ CORE（ox=−0.30r）",
			])
		3:
			return PackedStringArray([
				"① 暗甲壳弧 ×1.80（8 段 DARK · 静止不游走 · 减伤 70%）",
				"② 炮塔座 ×8（NEUTRAL 0.20r×0.11r · +45° 倒角）",
				"③ 炮口 ×8（GLOW α0.95 · 中轴留空让开 CORE）",
				"④ 炮塔挂梁 ×8（0.06r×0.03r · 读作挂载武器）",
				"⑤ 长方炮垒：DARK ×1.06 + MAIN + 3px CORE 白描边",
				"⑥ 横向装甲带 ×3 + 铆钉 4 枚/带（NEUTRAL_DK 沉孔）",
				"⑦ 观察缝 C（0.30r × 3.8px · 水平不倾斜）",
				"⑧ 推进舱（壳 0.60r~0.88r · GLOW 焰心）",
				"⑨ CORE 要害核（ox = −0.10r · 中轴留空给炮列）",
			])
		4:
			return PackedStringArray([
				"① 牵引臂 ×2/4/6（3 节 · DARK 6px + GLOW α0.70 3.5px）",
				"② 转轴环 ×3/臂（节点 0.72r / 1.00r / 1.28r）",
				"③ 末端夹爪（1.55r · 狂暴加血色符点）",
				"④ 子核心 ×2（色 ∈ 玩家战甲 S）+ 能量索 GLOW α0.60",
				"⑤ 宽厚六边母舰：DARK ×1.06 + MAIN 引力黄",
				"⑥ 纵向装甲带 ×2 + 铆钉 5 枚/带（NEUTRAL 30%）",
				"⑦ 机库牵引闸门（−0.62r · 口 r 0.42r · CORE 坐腔内）",
				"⑧ 闸齿 ×6（三角 0.08r · 暴露期内收 0.03r）",
				"⑨ 电浆红能量纹 ×3（MAIN[RED] α0.70 · 3px）",
				"⑩ 舷窗列 B ×5（沿上弦 · DARK + NEUTRAL）",
				"⑪ 推进舱 +X（NEUTRAL 壳 + GLOW 焰心）",
			])
		_:
			return PackedStringArray([
				"① 相位残影 ×0/1/2/3（1.50r · ×0.82 · α0.30 · 无 CORE）",
				"② 纺锤本体：STEEL_DARK ×1.06 + STEEL 中性亮钢灰",
				"③ 结构线：中轴脊 NEUTRAL_DK 3px + 上下弦 2px",
				"④ 四色轮转能量纹（箭羽 ×3 · MAIN[floor(_t) % 4]）",
				"⑤ 传感器阵列 A · 旗舰版 ×7（弧形排列 · 底槽弧 1 次 draw）",
				"⑥ 三连推进舱 ×3（0.18r×0.10r · 焰心走当前轮转色）",
				"⑦ CORE 要害核（ox = −0.42r · core_col(−1) = 纯白）",
				"⑧ 属性护罩弧 ×1.70 · 8 段虚线（色 ∈ 玩家战甲）",
			])
	return PackedStringArray()


func _mini_phases() -> PackedInt32Array:
	match stage:
		2:
			return PackedInt32Array([1, 3, 3])
		3, 4:
			return PackedInt32Array([3, 3, 3])
		_:
			return PackedInt32Array([1, 4, 4])   # L5：残影数随相位 0 → 3
	return PackedInt32Array([3, 3, 3])


## 三态标志位：bit0 狂暴 / bit1 散热期(L3) / bit2 暴露期(L4) / bit3 隐藏子核心
func _mini_flagset() -> PackedInt32Array:
	match stage:
		2:
			return PackedInt32Array([0, 0, 1])
		3:
			return PackedInt32Array([0, 2, 1])
		4:
			return PackedInt32Array([0, 4 + 8, 1])
		_:
			return PackedInt32Array([0, 0, 1])
	return PackedInt32Array([0, 0, 1])


func _mini_wards() -> PackedInt32Array:
	match stage:
		4:
			return PackedInt32Array([-1, 3, -1])     # 暴露期展引力黄护罩（∈ S）
		5:
			return PackedInt32Array([2, 2, 2])       # ALWAYS：光子白
		_:
			return PackedInt32Array([-1, -1, -1])    # L2 / L3 = WardMode.NONE
	return PackedInt32Array([-1, -1, -1])


func _mini_caps() -> PackedStringArray:
	match stage:
		2:
			return PackedStringArray(["收拢 · 相位Ⅰ 25°", "全展 · 相位Ⅲ 80°",
				"狂暴 · 翼尖霜刃 ×8"])
		3:
			return PackedStringArray(["甲壳闭合 · 减伤 70%", "散热期 · 缺口 + 白光",
				"狂暴 · 45° 告警条纹"])
		4:
			return PackedStringArray(["子核心牵引 · 绷紧", "暴露期 · 闸门关 + 展罩",
				"狂暴 · 触须红覆描"])
		_:
			return PackedStringArray(["相位Ⅰ · 无残影", "相位Ⅳ · 三面围拢",
				"狂暴 · 残影 α0.45 + 血环"])
	return PackedStringArray()


func _note() -> String:
	match stage:
		2:
			return "霜噬号 · 星盗霜舰 —— r=63 · 护罩 NONE（永不展罩，翼开合即窗口语言）· 定格相位Ⅲ：翼展 80° ± 4° 呼吸"
		3:
			return "耀斑号 · 星盗炮垒 —— r=70 · 护罩 NONE + 常驻减伤 70%（暗甲壳弧）· 定格相位Ⅲ：炮列 8 门 · 散热期缺口朝 −X 1.2 rad"
		4:
			return "深渊之喉 · 星盗母舰 —— r=77 · 护罩 EXPOSED（暴露期才展）· 定格相位Ⅲ：牵引臂 6 条 / 子核心 2 枚（色 ∈ S）"
		_:
			return "终焉号 · 星盗王 —— r=84 · 护罩 ALWAYS（光子白）· 定格相位Ⅳ：残影 3 枚 · 能量纹轮转定格 _t=0 → 电浆红"
	return ""


func _spec() -> String:
	return "部件清单（design/art/02 · 机甲化规格 §3.%d）" % stage


# ------------------------------------------------------------ UI
func _ui() -> void:
	_lbl(_title(), Vector2(40, 20), 28, Color(0.95, 0.97, 1.0))
	_lbl(_sub(), Vector2(40, 62), 14, Color(0.62, 0.68, 0.82))

	# ---- 部件清单面板 ----
	var items := _items()
	var panel := ColorRect.new()
	panel.color = Color(0.06, 0.08, 0.14, 0.85)
	panel.position = Vector2(PANEL_X, 90)
	panel.size = Vector2(PANEL_W, 34.0 + 28.0 * float(items.size()))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_lbl(_spec(), Vector2(PANEL_X + 18, 98), 15, Color(0.95, 0.97, 1.0))
	for i in items.size():
		_lbl(items[i], Vector2(PANEL_X + 18, 126 + 28 * i), 14, Color(0.85, 0.89, 0.98))

	# ---- 主视图部件编号 ----
	var pts := _part_points()
	for i in pts.size():
		var lb := Label.new()
		lb.text = str(i + 1)
		lb.position = pts[i] - Vector2(11.0, 11.0)
		lb.size = Vector2(22.0, 22.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 14)
		lb.add_theme_color_override("font_color", Color(0.10, 0.12, 0.18))
		lb.z_index = 20
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lb)

	# ---- 三态速览 ----
	_lbl("状态速览（×%.2f · 实机动态）" % _mini_sc(), Vector2(PANEL_X, 446), 13,
		Color(0.62, 0.68, 0.82))
	var caps := _mini_caps()
	for i in caps.size():
		var lb := Label.new()
		lb.text = caps[i]
		lb.position = Vector2(_mini_x(i) - 95.0, CAPTION_Y)
		lb.size = Vector2(190.0, 20.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 14)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lb)

	# ---- 底部说明 ----
	_lbl(_note(), Vector2(40, NOTE_Y), 14, Color(0.72, 0.77, 0.90))


func _lbl(text: String, pos: Vector2, fsize: int, col: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", col)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
