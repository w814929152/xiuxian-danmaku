extends Node2D
## 玩家战甲「风格锚点图」截帧（真窗口运行，**不可 --headless**）
##   四件战甲按实机矢量绘制（`ArmorArt.draw`）放大定格横排，供 AI 绘图做**美术风格参考**
##   —— 项目里 Boss 的机甲语汇就是从这套战甲派生的（design/art/02 §1.1）。
## 产物：D:/demo/_player_armor_style.png

const OUT := "D:/demo/_player_armor_style.png"
const SC := 2.5
const CY := 360.0
const CX := [160.0, 480.0, 800.0, 1120.0]
const NAMES := ["电浆剑甲", "寒霜疾甲", "光子盾甲", "引力束甲"]
const NOTES := [
	"红 · 前置双刃 + 满能激光",
	"蓝 · 三层残影 + 同色闪避",
	"白 · 护盾环 + 光子护盾",
	"黄 · 绕身引力环 ×4",
]
## 定格时刻：让残影 / 光刃 / 引力环落在整齐方位
const T := 0.62

var _stars: PackedVector2Array = PackedVector2Array()
var _star_a: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_seed_stars()
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09)
	bg.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠️ 子节点默认画在父节点 _draw() 内容之上，必须压到负层，否则整屏色块盖住星空与战甲
	bg.z_index = -10
	add_child(bg)
	_ui()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("CAPTURE_SAVED ", OUT)
	get_tree().quit()


func _seed_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260922
	for i in 60:
		_stars.append(Vector2(rng.randf_range(0.0, 1280.0),
			rng.randf_range(0.0, 720.0)))
		_star_a.append(rng.randf_range(0.15, 0.55))


func _draw() -> void:
	for i in _stars.size():
		draw_circle(_stars[i], 1.0, Color(0.85, 0.90, 1.0, _star_a[i] * 0.30))
	# 四件战甲：ArmorArt 与 Player / 战甲库同码同参（放大 SC 倍）
	for i in 4:
		ArmorArt.draw(self, Vector2(CX[i], CY), i, T, SC)


func _ui() -> void:
	_lbl("玩家战甲 · 实机矢量绘制（ArmorArt · 四色 ×%.1f 放大定格）" % SC,
		Vector2(40, 18), 24, Color(0.95, 0.97, 1.0))
	_lbl("Boss 机甲语汇即派生自这套战甲（design/art/02 §1.1）：暗身亮边 · 硬边六边裁片 · 细主色描边环 · 薄辉光 · 扁平无渐变",
		Vector2(40, 58), 14, Color(0.62, 0.68, 0.82))
	for i in 4:
		_lbl(NAMES[i], Vector2(CX[i] - 90.0, 556.0), 18, _main_col(i), 180.0)
		_lbl(NOTES[i], Vector2(CX[i] - 110.0, 584.0), 13, Color(0.72, 0.77, 0.90), 220.0)
	_lbl("敌我识别主通道：玩家 +X 是头（冷青 CANOPY 舱盖朝前 + 白判定点），Boss −X 是头（CORE 白核）",
		Vector2(40, 640), 14, Color(0.66, 0.71, 0.85))
	_lbl("玩家专属语汇（Boss 禁用）：CANOPY 冷青座舱 / 绕身光刃 ×3 / 中心白判定点 / 能量尾带",
		Vector2(40, 666), 13, Color(0.58, 0.63, 0.78))


func _main_col(i: int) -> Color:
	return Game.COLOR_MAIN[i]


func _lbl(text: String, pos: Vector2, fsize: int, col: Color, w := 0.0) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	if w > 0.0:
		lb.size = Vector2(w, float(fsize) + 8.0)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", col)
	lb.z_index = 20
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
