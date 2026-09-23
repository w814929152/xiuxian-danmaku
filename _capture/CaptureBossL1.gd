extends Node2D
## L1 熔核号 · 模型图截帧（真窗口运行，**不可 --headless**）：
##   把第一关旗舰按实机矢量绘制（BossArt.draw_core / _l1_rings）放大 2.6 倍，
##   部件编号标注 + 部件清单 + 三态速览（常规 / 换色预告 / 狂暴）。
##   规格依据：`design/art/02-Boss机甲化视觉规格.md` §3.1。
## 产物：D:/demo/_boss_l1_model.png

const OUT := "D:/demo/_boss_l1_model.png"
const HERO_POS := Vector2(360.0, 390.0)
const HERO_SCALE := 2.6

var _hero: Boss = null
var _overlay: Node2D = null
var _stars: PackedVector2Array = PackedVector2Array()
var _star_a: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	_seed_stars()
	_bg()
	# 主视图：相位Ⅱ（双环）+ 护罩弧展开（电浆红 ∈ 玩家战甲色）
	_hero = _make_boss(HERO_POS, HERO_SCALE, 2, Game.RED)
	# 编号圆点覆盖层：必须压在 Boss 绘制之上（父节点 _draw 会被子节点盖住）
	_overlay = Node2D.new()
	_overlay.z_index = 20          # Boss._ready 里 z_index=10，覆盖层必须更高
	add_child(_overlay)
	_overlay.draw.connect(_on_overlay_draw)
	_ui()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("CAPTURE_SAVED ", OUT)
	get_tree().quit()


func _process(_delta: float) -> void:
	# 主视图定格：_t 归零 → 环缺口朝 +X、散热鳍落在 45° 整数方位，与标注点对齐。
	#   （Boss._process 仍会 _t += delta，但每帧都被压回，漂移 ≤ 1 帧）
	if _hero != null and is_instance_valid(_hero):
		_hero._t = 0.0
	queue_redraw()


## 造一台只摆姿势的 L1：自定义态 "pose" 让 _process 只推进 _t ——
##   不移动 / 不开火 / 护罩状态机不接管（ward 由这里直接指定）。
func _make_boss(pos: Vector2, sc: float, ph: int, ward_c: int) -> Boss:
	var b := Boss.new()
	b.stage = 1
	b.phase = ph
	b.player_armors = [Game.RED, Game.WHITE]
	b.world = self
	b._home_x = pos.x
	b._base_y = pos.y
	b.scale = Vector2(sc, sc)
	add_child(b)
	b.position = pos
	b._st = "pose"
	b.ward = ward_c
	b._ward_t = 99.0
	return b


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
	# 远景星野（静态，压在最底层）
	for i in _stars.size():
		var p := _stars[i]
		draw_circle(p, 1.0, Color(0.85, 0.90, 1.0, _star_a[i] * 0.35))


## 编号徽章画在覆盖层（渲染序在 Boss 之后 → 不会被机体盖住）：
##   白底 + 深边 + 深字 —— 在暗太空底与红色环上都读得清
func _on_overlay_draw() -> void:
	for p in _part_points():
		_overlay.draw_circle(p, 12.0, Color(0.95, 0.97, 1.0, 0.95))
		_overlay.draw_arc(p, 12.0, 0.0, TAU, 20, Color(0.10, 0.12, 0.18, 0.95), 2.5, true)


## 九个部件在屏幕上的编号点位（r=56 × 2.6，定格 _t=0）
func _part_points() -> Array[Vector2]:
	var rs := 56.0 * HERO_SCALE
	return [
		HERO_POS + Vector2.RIGHT.rotated(PI * 7.0 / 6.0) * (1.28 * rs),  # ① 环形散热架
		HERO_POS + Vector2.RIGHT.rotated(-PI * 0.25) * (1.33 * rs),      # ② 散热鳍
		HERO_POS + Vector2(-0.5, -0.866) * (1.07 * rs),                  # ③ 暗壳 + 倒角
		HERO_POS + Vector2(-0.5, 0.866) * (1.07 * rs),                   # ④ 装甲片 ×6
		HERO_POS + Vector2(0.0, -0.66 * rs),                             # ⑤ 传感器阵列
		HERO_POS + Vector2.RIGHT.rotated(-PI / 3.0) * (0.40 * rs),       # ⑥ 熔炉辉环
		HERO_POS + Vector2(0.97 * rs, 0.0),                              # ⑦ 推进舱
		HERO_POS + Vector2(-0.16 * rs, 0.0),                             # ⑧ CORE 要害核
		HERO_POS + Vector2.RIGHT.rotated(-PI * 0.14) * (1.70 * rs),      # ⑨ 护罩弧
	]


func _ui() -> void:
	_lbl("第一关 BOSS 模型 · 熔核号 · 星盗先驱", Vector2(40, 20), 28,
		Color(0.95, 0.97, 1.0))
	_lbl("L1 旗舰 · 实机矢量绘制（BossArt · SIL_CORE 正六边核心舱 ×2.6）· 本体恒光子白 · −X 头 / +X 尾",
		Vector2(40, 62), 14, Color(0.62, 0.68, 0.82))

	# ---- 部件清单面板 ----
	var panel := ColorRect.new()
	panel.color = Color(0.06, 0.08, 0.14, 0.85)
	panel.position = Vector2(672, 96)
	panel.size = Vector2(576, 340)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_lbl("部件清单（design/art/02 · 机甲化规格 §3.1）", Vector2(690, 106), 15,
		Color(0.95, 0.97, 1.0))
	var items := [
		"① 环形散热架 ×1.28 —— 环色 = 护罩色（散热工质换色）",
		"② 散热鳍 ×8（1.28r~1.38r · 结构件灰 NEUTRAL）",
		"③ 六边核心舱：DARK 暗壳 ×1.07 + 45° 倒角",
		"④ 装甲片 ×6（SEAM 接缝 1.7px · 铆钉带 ×2）",
		"⑤ 传感器阵列 ×5（侧向成排 · 无白描边无高光）",
		"⑥ 熔炉辉环 0.40r（GLOW α0.55 —— 炉子在烧）",
		"⑦ 推进舱 +X 尾（NEUTRAL 壳 + GLOW 焰心）",
		"⑧ CORE 要害核 −X 头部（DARK 眼窝 + 白高光）",
		"⑨ 属性护罩弧 ×1.70 · 8 段虚线（色 ∈ 玩家战甲）",
	]
	for i in items.size():
		_lbl(items[i], Vector2(690, 138 + 33 * i), 15, Color(0.85, 0.89, 0.98))

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
	_lbl("状态速览（×1.1 · 实机动态）", Vector2(672, 446), 13, Color(0.62, 0.68, 0.82))
	var t1 := _make_boss(Vector2(790.0, 590.0), 1.1, 1, Game.WHITE)
	var t2 := _make_boss(Vector2(980.0, 590.0), 1.1, 1, Game.RED)
	t2._ward_t = 0.9        # ≤ ward_telegraph(1)=1.5 → 换色预告：环虚线化 ×2.2 加速
	var t3 := _make_boss(Vector2(1170.0, 590.0), 1.1, 1, Game.RED)
	t3.enraged = true       # 狂暴：缺口 0.90 rad + 散热鳍转 RAGE + 三角符标
	var caps := ["常规 · 相位Ⅰ", "换色预告（虚线化·×2.2）", "狂暴（缺口加大·红鳍）"]
	for i in caps.size():
		var lb := Label.new()
		lb.text = caps[i]
		lb.position = Vector2(790.0 + 190.0 * float(i) - 95.0, 466.0)
		lb.size = Vector2(190.0, 20.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 14)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(lb)

	# ---- 底部说明 ----
	_lbl("熔核号 · 星盗先驱 —— 第一关旗舰 · r=56 · 护罩 ALWAYS · 相位Ⅱ：第二环 ×1.45 逆向自转",
		Vector2(40, 680), 14, Color(0.72, 0.77, 0.90))


func _lbl(text: String, pos: Vector2, fsize: int, col: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", col)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
