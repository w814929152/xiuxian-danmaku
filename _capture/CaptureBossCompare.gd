extends Node2D
## 五关旗舰「新旧模型对比」截帧（真窗口运行，**不可 --headless**）
##   关卡由场景根节点 metadata `stage` 指定（1~5）。左 = 改版前（旧模型），右 = 改版后。
##   两侧**同一批实机类**：旧侧 `BossLegacy` / `Boss4Legacy`，新侧 `Boss` / `Boss4`；
##   同一相位、同一护罩色、同一 `_t=0` 定格、同一套覆盖层 —— 只有机体绘制层
##   （`BossArtLegacy` vs `BossArt`）不同，故画面对比**只反映机甲化改造本身**。
##   规格依据 `design/art/02-Boss机甲化视觉规格.md` §1.1 语汇 / §3.1~3.5 部件表 / §5.3 新增项。
## 产物：D:/demo/_boss_l{stage}_compare.png

const OUT_FMT := "D:/demo/_boss_l%d_compare.png"
const OLD_POS := Vector2(360.0, 320.0)
const NEW_POS := Vector2(920.0, 320.0)
const BOX_T := 100.0
const BOX_B := 520.0
const PANEL_Y := 540.0

## 与模型图同表，×0.78 让两侧并排放得下（护罩弧 ×1.70 也要留出来）
const MAIN_SC := [0.0, 2.60, 2.30, 2.00, 1.70, 1.45]
const SC_MUL := 0.78
## 玩家两件战甲 S（护罩色 / L4 子核心色一律 ∈ S —— 可行性铁律）
const ARMOR_A := [0, 1, 1, 3, 2]
const ARMOR_B := [0, 2, 2, 1, 1]
## 定格相位 / 护罩色（-1 = 该关本态不展罩）；与 `CaptureBoss.gd` 主视图同态
const MAIN_PH := [2, 3, 3, 3, 4]
const MAIN_WARD := [0, -1, -1, -1, 2]
## L4 两枚子核心的定格方位
const CORE_DEG := [-50.0, 50.0]

var stage: int = 1
var _old: Boss = null
var _new: Boss = null
var _overlay: Node2D = null
var _stars: PackedVector2Array = PackedVector2Array()
var _star_a: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	stage = int(get_meta("stage", 1))
	Game.picked_armors = [_armor_a(), _armor_b()]
	_seed_stars()
	_bg()
	_old = _make_boss(OLD_POS, true)
	_new = _make_boss(NEW_POS, false)
	_overlay = Node2D.new()
	_overlay.z_index = 30          # Boss._ready 里 z_index=10，装饰层必须更高
	add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)
	_ui()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_FMT % stage)
	print("CAPTURE_SAVED ", OUT_FMT % stage)
	get_tree().quit()


func _process(_delta: float) -> void:
	# 两侧同步定格：_t 归零 → 环缺口朝 +X / 翼落整数方位 / 能量纹定格
	if _old != null and is_instance_valid(_old):
		_apply(_old)
	if _new != null and is_instance_valid(_new):
		_apply(_new)
	queue_redraw()


## 造一台只摆姿势的旗舰：legacy=true 走旧绘制层，false 走现行实现
func _make_boss(pos: Vector2, legacy: bool) -> Boss:
	var b: Boss
	if stage == 4:
		b = Boss4Legacy.new() if legacy else Boss4.new()
	else:
		b = BossLegacy.new() if legacy else Boss.new()
	b.stage = stage
	b.phase = _main_ph()
	b.player_armors = [_armor_a(), _armor_b()]
	b.world = self
	b._home_x = pos.x
	b._base_y = pos.y
	b.scale = Vector2(_sc(), _sc())
	add_child(b)
	b.position = pos
	b._st = "pose"
	_apply(b)
	return b


## 每帧把形态字段压回目标值（pose 态下状态机不接管，这里只做保险）
func _apply(b: Boss) -> void:
	b._t = 0.0
	b._ward_anim = 0.0
	b._ward_t = 99.0
	b.phase = _main_ph()
	b.ward = _main_ward()
	b.enraged = false
	b.venting = false
	b._exposed_win = false
	_fix_cores(b)


## L4 子核心：关掉自身 _process（否则公转会跑），由本文件定格方位 + 同步缩放
##   —— 子核心是 world 的独立子节点，不吃 Boss 的 scale，轨道半径也要乘 sc
func _fix_cores(b: Boss) -> void:
	if stage != 4:
		return
	var v: Variant = b.get("_cores")
	if not (v is Array):
		return
	var arr: Array = v
	var orbit := float(StageCfg.boss_r_main(4)) * 1.95 * _sc()
	for i in arr.size():
		var core: Node2D = arr[i] as Node2D
		if core == null:
			continue
		core.set_process(false)
		core.visible = true
		core.scale = Vector2(_sc(), _sc())
		core.position = b.position + Vector2.RIGHT.rotated(
			deg_to_rad(CORE_DEG[i % 2])) * orbit


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


## 装饰层：左右取景框 + 中间分隔虚线 + 「机甲化」箭头
func _on_overlay_draw() -> void:
	var faint := Color(0.55, 0.62, 0.78, 0.16)
	_overlay.draw_rect(Rect2(60.0, BOX_T, 560.0, BOX_B - BOX_T), faint, false, 1.0)
	_overlay.draw_rect(Rect2(660.0, BOX_T, 560.0, BOX_B - BOX_T), faint, false, 1.0)
	# 中间竖虚线
	var y := BOX_T + 8.0
	while y < BOX_B - 8.0:
		_overlay.draw_line(Vector2(640.0, y), Vector2(640.0, y + 10.0),
			Color(0.62, 0.68, 0.82, 0.55), 2.0)
		y += 20.0
	# 箭头（指向右 = 改造方向）
	var tip := Vector2(672.0, 300.0)
	_overlay.draw_colored_polygon(PackedVector2Array([
		tip, Vector2(tip.x - 18.0, tip.y - 11.0), Vector2(tip.x - 18.0, tip.y + 11.0)]),
		Color(0.72, 0.86, 1.0, 0.90))
	_overlay.draw_line(Vector2(tip.x - 46.0, tip.y), Vector2(tip.x - 18.0, tip.y),
		Color(0.72, 0.86, 1.0, 0.90), 4.0)


# ------------------------------------------------------------ 常量表访问器
## const 数组取出的元素是 Variant，直接 `var x := arr[i]` 推不出类型（项目既有坑）
func _sc() -> float:
	return MAIN_SC[stage] * SC_MUL


func _main_ph() -> int:
	return MAIN_PH[stage - 1]


func _main_ward() -> int:
	return MAIN_WARD[stage - 1]


func _armor_a() -> int:
	return ARMOR_A[stage - 1]


func _armor_b() -> int:
	return ARMOR_B[stage - 1]


# ------------------------------------------------------------ 文案
func _title() -> String:
	match stage:
		1:
			return "第一关 BOSS 新旧对比 · 熔核号 · 星盗先驱"
		2:
			return "第二关 BOSS 新旧对比 · 霜噬号 · 星盗霜舰"
		3:
			return "第三关 BOSS 新旧对比 · 耀斑号 · 星盗炮垒"
		4:
			return "第四关 BOSS 新旧对比 · 深渊之喉 · 星盗母舰"
		_:
			return "第五关 BOSS 新旧对比 · 终焉号 · 星盗王"
	return ""


func _sub() -> String:
	return ("左 = 改版前（机甲化前 BossArt）　右 = 改版后（现行机甲化实现）"
		+ " · 同一相位 / 同一护罩 / 定格 _t=0 · 缩放 ×%.2f" % _sc())


func _note() -> String:
	match stage:
		1:
			return "剪影 SIL_CORE 一个顶点未改；差异只在「外壳怎么画」—— 倒角 / 装甲片分块 / 接缝铆钉 / 散热架 / 传感器 / 推进舱"
		2:
			return "剪影 SIL_WING 一个顶点未改；翼从「整片霜晶膜」变成「三段折面装甲板 + 承力梁 + 挂架」"
		3:
			return "剪影 SIL_BATTERY 一个顶点未改；3px CORE[W] 强制外描边是对比度补偿，新旧都保留"
		4:
			return "剪影 SIL_MAW 一个顶点未改；两侧子核心本就同码（自绘未改动），差异只在母舰本体与牵引臂"
		_:
			return "剪影 SIL_THRONE 一个顶点未改；残影从「实心同型机」变成「只画轮廓 + 3 条结构线的相位投影」"
	return ""


## 机甲化改造要点（design/art/02 §1.1 语汇 V1–V7 + §3.x 部件表 + §5.3 新增项）
func _items() -> PackedStringArray:
	match stage:
		1:
			return PackedStringArray([
				"① 环 → 外挂环形散热架：旧版 = 1.28r 光环 + 3 枚符点；新版外缘挂散热鳍 ×8（NEUTRAL 6×4px）",
				"② 六边核心舱加 45° 倒角 0.08r，主体切装甲片 ×6（片间 SEAM 缝 1.7px）+ 沿辐条铆钉带",
				"③ 新增 ⑤b 传感器阵列 A ×5（DARK 槽 + NEUTRAL 芯 · 侧向不朝 +X）—— §1.3 CANOPY 替代语汇",
				"④ 新增 ②c 推进舱（+X 尾 · NEUTRAL 壳 + GLOW 焰心）；熔炉辉环 0.40r 保留",
				"⑤ CORE 要害核恒在 ox = −0.16r（要害扇区 −X±40°，任何部件不得进入）",
			])
		2:
			return PackedStringArray([
				"① 翼 → 三段折面推进翼：旧版 = 整片霜晶膜；新版 = 三段独立装甲板 + 翼骨承力梁 4px + 段间接缝",
				"② 新增翼根挂架 ×2（0.10r × 0.06r）→ 读作「挂载」而非「身体长刺」",
				"③ 舰体 −X 尖端倒角 0.06r；甲板散热面机甲化为格栅（每条 5 条 1.5px 平行线）",
				"④ 新增 ⑤b 舷窗列 B ×4（DARK 眼窝 + NEUTRAL 芯）+ ②c 推进舱",
				"⑤ 狂暴：翼尖伸三角霜刃（两侧共 8 枚）—— 形状通道先于颜色通道，色盲可读",
			])
		3:
			return PackedStringArray([
				"① 炮塔座加 +45° 倒角 + 座下挂梁（NEUTRAL）→ 读作「挂载武器」而非「身体长刺」",
				"② 舰体：横向装甲带 ×3 + 带间接缝 + 铆钉 4 枚/带（NEUTRAL 带 + SEAM 缝）",
				"③ 新增 ⑤b 观察缝 C（0.30r × 3.8px · 水平不倾斜）+ ②c 推进舱（壳 + 焰心）",
				"④ 保留 3px CORE[W] 强制外描边（对比度补偿 3.15:1 · 禁止删）",
				"⑤ 狂暴：45° 告警条纹（RAGE α0.35 · 条宽/间距 6px）只画在部件边缘带",
			])
		4:
			return PackedStringArray([
				"① 触须 → 分节牵引机械臂：3 节（0.72 / 1.00 / 1.28r）+ 转轴环 ×3 + 末端夹爪 1.55r",
				"② 深渊之口 → 机库牵引闸门：内凹开口（口 r 0.42r）+ 闸齿 ×6，CORE 坐腔内 ox = −0.62r",
				"③ 舰体：纵向装甲带 ×2 + 铆钉 5 枚/带（NEUTRAL 30%）；电浆红能量纹 ×3 保留",
				"④ 新增 ⑤b 舷窗列 B ×5（沿上弦）+ ②c 推进舱",
				"⑤ 子核心色 ∈ 玩家战甲 S、增援 ∈ S′（可行性铁律不变）；暴露期统一读 is_exposed()",
			])
		_:
			return PackedStringArray([
				"① 王座 → 旗舰指挥舰体：纺锤重装舰（STEEL_DARK ×1.06 壳 + STEEL 主体 · 不绑四色）",
				"② 残影 → 相位投影：只画轮廓 + 3 条结构线（α0.30 / 狂暴 0.45），无挂架 = 无实体",
				"③ 新增 ⑤b 传感器阵列 A · 旗舰版 ×7（弧形排列 · 底槽弧 1 次 draw 省指令）",
				"④ 新增 ②c 三连推进舱 ×3（焰心走当前轮转色）；结构线 = 中轴脊 3px + 上下弦 2px",
				"⑤ 四色轮转能量纹（箭羽 ×3 · MAIN[floor(_t) % 4]）保留；CORE ox = −0.42r（纯白）",
			])
	return PackedStringArray()


# ------------------------------------------------------------ UI
func _ui() -> void:
	_lbl(_title(), Vector2(40, 14), 26, Color(0.95, 0.97, 1.0))
	_lbl(_sub(), Vector2(40, 54), 13, Color(0.62, 0.68, 0.82))
	_center_lbl("改版前 · 旧模型", OLD_POS.x, 84.0, 16, Color(0.78, 0.82, 0.90))
	_center_lbl("改版后 · 机甲化", NEW_POS.x, 84.0, 16, Color(0.72, 0.88, 1.0))
	_center_lbl("机甲化", 640.0, 322.0, 14, Color(0.72, 0.86, 1.0))

	# ---- 差异要点面板 ----
	var items := _items()
	var panel := ColorRect.new()
	panel.color = Color(0.06, 0.08, 0.14, 0.85)
	panel.position = Vector2(40.0, PANEL_Y)
	panel.size = Vector2(1200.0, 44.0 + 22.0 * float(items.size()))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_lbl("机甲化改造要点（design/art/02 · §1.1 语汇 V1–V7 + §3.%d 部件表 + §5.3 新增项）" % stage,
		Vector2(58.0, PANEL_Y + 6.0), 14, Color(0.95, 0.97, 1.0))
	for i in items.size():
		_lbl(items[i], Vector2(58.0, PANEL_Y + 32.0 + 22.0 * float(i)), 14,
			Color(0.85, 0.89, 0.98))

	_lbl(_note(), Vector2(40, 700), 13, Color(0.66, 0.71, 0.85))


func _lbl(text: String, pos: Vector2, fsize: int, col: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", col)
	lb.z_index = 30
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)


func _center_lbl(text: String, cx: float, y: float, fsize: int, col: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = Vector2(cx - 120.0, y)
	lb.size = Vector2(240.0, float(fsize) + 8.0)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", col)
	lb.z_index = 30
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
