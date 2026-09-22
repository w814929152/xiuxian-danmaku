class_name Background
extends Node2D
## 星域背景：远星云画底（像素 sprite）/ 主行星 / 小行星带剪影 / 星云 / 星际尘埃
##
## 性能策略（Phase 4）：
##   · 画底 —— tools/build_sprites.py 离线烘焙的 1280x720 远山剪影，
##     满画幅一次 draw_texture_rect
##   · 山脊 / 星野 —— 在 _ready 里烘焙成「周期性纹理」，逐帧只做纹理平移
##     （原本 3 × 72 = 216 个多边形 / 帧 -> 6 次区域绘制）
##   · 夜空渐变 —— 烘焙成 GradientTexture2D（26 条色带 -> 1 次绘制）
##   · 云海 —— 单位椭圆顶点预计算，逐帧只做变换，不再跑 cos/sin
## 每帧三角函数调用由 ~1300 次降到 ~120 次，绘制指令由 ~370 降到 ~105。

const PERIOD := 1600.0      # 小行星带剪影循环周期（屏幕像素，必须 > 视宽）
const TEX_SCALE := 2.0      # 剪影纹理水平压缩：2 纹理像素 = 1 屏幕像素
const STAR_PERIOD := 1024.0 # 星野循环周期（屏幕像素）
const NEB_PERIOD := 2048.0  # 星云循环周期（屏幕像素，最慢视差）
const OVAL_SEG := 24        # 尘埃云带椭圆分段

## 三档滚动速度（2026-09-22 收成常量 —— 原来 46 / 22 散落在 Background 初值与
##   Level 的 Boss 战分支里，加驻留波时若不收拢就会出现第三个裸数字）：
##   · NORMAL 推进波（现状恒速）
##   · BOSS   Boss 战（已有自己的慢滚，是第三种节奏，不用再改）
##   · HOLD   驻留阵地波（提案 `design/levels/03-关卡节奏实测与驻留波提案.md` §3.4）
##     ⚠ **不降成硬 0**：`_off` 同时驱动星野 / 星云 / 小行星带，只有漂浮碎屑走
##     `_t` 仍在动，硬 0 会让画面整个"死"掉看着像卡住。8 px/s 保留一点漂移感。
const SCROLL_NORMAL := 46.0
const SCROLL_BOSS := 22.0
const SCROLL_HOLD := 8.0

var scroll_speed := SCROLL_NORMAL
var _t := 0.0
var _off := 0.0

var _sky: GradientTexture2D = null
var _star_tex: ImageTexture = null
var _neb_tex: ImageTexture = null   # 星云（新增，最慢视差层）
var _bg_tex: Texture2D = null    # 远星云画底（ArtAssets 共享纹理）
var _mts: Array[Dictionary] = []
var _oval: PackedVector2Array = []
var _cloud_v: Array[Vector4] = []   # x0 / y / w / h
var _cloud_a: Array[float] = []
var _cloud_s: Array[float] = []
var _stars: Array[Vector2] = []     # 逐颗明灭的亮星（少量，保留呼吸感）
var _srad: Array[float] = []
var _motes: Array[Vector2] = []     # 浮尘
var _mph: Array[float] = []


func _ready() -> void:
	z_index = -10
	# 画底按 1:1 呈现，仍统一 NEAREST，与其余 sprite 呈现口径一致
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_tex = ArtAssets.tex("bg_mountains")
	randomize()
	_sky = _make_sky()
	_star_tex = _make_stars()
	_neb_tex = _make_nebula()
	_mts = _make_mountains()
	_bake_clouds()
	for i in OVAL_SEG:
		var a := TAU * float(i) / float(OVAL_SEG)
		_oval.append(Vector2(cos(a), sin(a)))
	for i in 26:
		_stars.append(Vector2(randf() * Game.VIEW_W, randf() * Game.VIEW_H * 0.72))
		_srad.append(1.1 + randf() * 1.4)
	for i in 46:
		_motes.append(Vector2(randf() * Game.VIEW_W, randf() * Game.VIEW_H))
		_mph.append(randf() * TAU)


func _process(delta: float) -> void:
	_t += delta
	_off += scroll_speed * delta
	queue_redraw()


## 供自测断言：四块周期纹理是否烘焙成功
func baked() -> bool:
	return _sky != null and _star_tex != null and _neb_tex != null and _mts.size() == 3


# =============================================================== 逐帧绘制
func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H

	# 远星云画底（满画幅，覆盖原夜空渐变 —— 渐变仍烘焙供 baked() 校验）
	# modulate 更冷更暗（0.30/0.34/0.58）：让星云画底不抢弹幕，角色与弹幕对比度更高。
	if _bg_tex != null:
		draw_texture_rect(_bg_tex, Rect2(0.0, 0.0, W, H), false,
			Color(0.30, 0.34, 0.58, 1.0))

	# 星野（烘焙 + 平移，整体缓慢呼吸）
	if _star_tex != null:
		_tile(_star_tex, _off, 0.16, 0.0, float(_star_tex.get_height()), 1.0,
			0.40 + 0.14 * (0.5 + 0.5 * sin(_t * 0.8)))

	# 逐颗明灭的亮星（冷白偏蓝、低 alpha、小半径 —— 避免与光子白弹争「近白亮点」）
	for i in _stars.size():
		var p := _stars[i]
		var x := fmod(p.x - _off * 0.16 + W, W)
		var tw := 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 1.6 + p.y))
		draw_circle(Vector2(x, p.y), _srad[i], Color(0.88, 0.93, 1.00, 0.42 * tw))

	# 星云（新增，最慢视差层；烘焙 + 平移，逐帧零成本）
	if _neb_tex != null:
		_tile(_neb_tex, _off, 0.10, 40.0, float(_neb_tex.get_height()), TEX_SCALE, 0.55)

	# 主行星 / 母星（原月轮位置不动，构图锚点）
	var mp := Vector2(W * 0.80, H * 0.20)
	draw_circle(mp, 130.0, Color(0.42, 0.56, 0.95, 0.045))
	draw_circle(mp, 86.0, Color(0.50, 0.64, 1.00, 0.055))
	draw_circle(mp, 52.0, Color(0.72, 0.80, 0.98, 0.92))
	draw_circle(mp + Vector2(14.0, -10.0), 44.0, Color(0.38, 0.44, 0.72, 0.35))  # 晨昏线暗面

	# 小行星带 / 残骸带剪影三层（烘焙 + 平移）
	for i in _mts.size():
		var m: Dictionary = _mts[i]
		_tile(m["tex"] as ImageTexture, _off, float(m["par"]), float(m["top"]),
			float(m["h"]), TEX_SCALE, 1.0)

	# 星际尘埃 / 离子云带（预计算椭圆 + 变换复用）
	for i in _cloud_v.size():
		var v := _cloud_v[i]
		var x := fmod(v.x + _off * _cloud_s[i], W + 460.0) - 230.0
		draw_set_transform_matrix(Transform2D(0.0, Vector2(v.z, v.w), 0.0,
			Vector2(x, v.y)))
		draw_colored_polygon(_oval, Color(0.48, 0.52, 0.86, _cloud_a[i]))
	draw_set_transform_matrix(Transform2D.IDENTITY)

	# 漂浮碎屑 / 离子微粒上升
	for i in _motes.size():
		var p := _motes[i]
		var y := fmod(p.y - _t * (16.0 + fmod(float(i), 5.0) * 9.0) + H, H)
		var x := p.x + sin(_t * 0.7 + _mph[i]) * 16.0
		var a := 0.25 + 0.35 * (0.5 + 0.5 * sin(_t * 2.2 + _mph[i]))
		draw_circle(Vector2(x, y), 1.6 + fmod(float(i), 3.0) * 0.7,
			Color(0.70, 0.84, 0.98, a))

	# 底部雾气（读作深空暗带）
	draw_rect(Rect2(0.0, H - 90.0, W, 90.0), Color(0.10, 0.09, 0.18, 0.35))

	# 边框（HUD 舷窗框 / 舰内视口框）
	draw_rect(Rect2(0.0, 0.0, W, 3.0), Color(0.45, 0.70, 0.95, 0.16))
	draw_rect(Rect2(0.0, H - 3.0, W, 3.0), Color(0.45, 0.70, 0.95, 0.16))


## 把一张「周期纹理」按视差平移铺满屏幕宽，最多 2~3 段即可覆盖
func _tile(tex: ImageTexture, off: float, par: float, top: float, h: float,
		sx: float, alpha: float) -> void:
	var tw := float(tex.get_width())
	var P := tw * sx                       # 周期（屏幕像素）
	var o := fposmod(off * par, P) / sx    # 起始列（纹理像素）
	var x := 0.0
	var W := Game.VIEW_W
	while x < W - 0.5:
		var w := minf((W - x) / sx, tw - o)
		if w <= 0.01:
			break
		draw_texture_rect_region(tex, Rect2(x, top, w * sx, h),
			Rect2(o, 0.0, w, h), Color(1.0, 1.0, 1.0, alpha))
		x += w * sx
		o = 0.0


# =============================================================== 烘焙
func _make_sky() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.045, 0.035, 0.10))
	g.set_color(1, Color(0.13, 0.10, 0.20))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 256
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	return t


func _make_stars() -> ImageTexture:
	var h := int(Game.VIEW_H * 0.72)
	var w := int(STAR_PERIOD)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := int(float(w * h) / 6200.0)
	var base := Color(0.86, 0.91, 1.00)   # 冷白偏蓝，饱和度低于白弹，避免争「近白亮点」
	for i in n:
		var x := randi() % w
		var y := randi() % h
		var c := base.lerp(Color(0.45, 0.46, 0.60), randf() * 0.75)
		var s := 1 if randf() < 0.38 else 2   # 2px 星占比降到 38%
		img.fill_rect(Rect2i(x, y, s, s), c)
		if s == 2:
			img.fill_rect(Rect2i(x - 1, y, 1, 2), c)
			img.fill_rect(Rect2i(x + 2, y, 1, 2), c)
			img.fill_rect(Rect2i(x, y - 1, 2, 1), c)
			img.fill_rect(Rect2i(x, y + 2, 2, 1), c)
	return ImageTexture.create_from_image(img)


## 星云：4~6 个径向渐变团一次性烘焙（紫/品红/青，线性明度 Y ≤ 0.15，
## 禁用四档属性色相带 —— 防止星云吃掉红色弹）。逐帧只做 _tile() 平移，零成本。
func _make_nebula() -> ImageTexture:
	var w := int(NEB_PERIOD / TEX_SCALE)
	var h := 420
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var blobs := 4 + (randi() % 3)   # 4~6 个
	for b in blobs:
		var cx := randf() * float(w)
		var cy := randf() * float(h)
		var rad := 90.0 + randf() * 130.0
		# 紫 / 品红 / 青 三色随机，明度压到 Y ≤ 0.15
		var hue_choice := randf()
		var col: Color
		if hue_choice < 0.34:
			col = Color(0.30, 0.12, 0.42)   # 紫
		elif hue_choice < 0.67:
			col = Color(0.40, 0.14, 0.34)   # 品红
		else:
			col = Color(0.12, 0.30, 0.40)   # 青
		for dy in range(-int(rad), int(rad)):
			var y := int(cy) + dy
			if y < 0 or y >= h:
				continue
			var dx := int(sqrt(rad * rad - float(dy * dy)))
			var x0 := int(cx) - dx
			var x1 := int(cx) + dx
			for x in range(x0, x1):
				if x < 0 or x >= w:
					continue
				var d := sqrt(float((x - int(cx)) * (x - int(cx)) + dy * dy)) / rad
				var a := (1.0 - d) * 0.18   # 中心 alpha 0.18，边缘归零
				if a <= 0.005:
					continue
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


func _make_mountains() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var H := Game.VIEW_H
	var bottom := H + 60.0
	var spec: Array[Dictionary] = [
		{"par": 0.22, "base": 0.78, "amp": 64.0,
			"col": Color(0.13, 0.12, 0.20), "seed": 0.7},
		{"par": 0.45, "base": 0.87, "amp": 46.0,
			"col": Color(0.095, 0.088, 0.155), "seed": 2.3},
		{"par": 0.85, "base": 0.96, "amp": 30.0,
			"col": Color(0.058, 0.052, 0.10), "seed": 4.1},
	]
	var tw := int(PERIOD / TEX_SCALE)
	for s in spec:
		var amp := float(s["amp"])
		var col := s["col"] as Color
		var seedf := float(s["seed"])
		var h_max := amp * 1.6
		var top_y := H * float(s["base"]) - h_max - 2.0
		var ih := int(ceil(bottom - top_y))
		var img := Image.create(tw, ih, false, Image.FORMAT_RGBA8)
		for x in tw:
			var top := int(h_max + 2.0 - _wave(float(x) * TEX_SCALE, amp, seedf))
			if top < 0:
				top = 0
			elif top >= ih:
				continue
			img.fill_rect(Rect2i(x, top, 1, ih - top), col)
		out.append({
			"tex": ImageTexture.create_from_image(img),
			"par": float(s["par"]),
			"top": top_y,
			"h": float(ih),
		})
	return out


## 山脊高度（相对基线，向上为正）—— 三个谐波共享周期 PERIOD，保证可无缝平铺
func _wave(u: float, amp: float, seedf: float) -> float:
	var k := TAU / PERIOD
	return sin(u * k + seedf) * amp \
		+ sin(u * k * 3.0 + seedf * 2.1) * amp * 0.42 \
		+ sin(u * k * 11.0 + seedf * 3.7) * amp * 0.34


func _bake_clouds() -> void:
	var H := Game.VIEW_H
	for i in 12:
		var seedf := float(i) * 1.37
		var sp := 0.30 + fmod(seedf, 1.0) * 0.55
		var y := H * (0.42 + fmod(seedf * 0.61, 1.0) * 0.52)
		var w := 120.0 + fmod(seedf * 3.1, 1.0) * 210.0
		var h := 13.0 + fmod(seedf * 5.7, 1.0) * 16.0
		var a := 0.04 + fmod(seedf * 7.3, 1.0) * 0.05
		_cloud_v.append(Vector4(fmod(seedf * 260.0, Game.VIEW_W + 460.0), y, w, h))
		_cloud_a.append(a)
		_cloud_s.append(sp)
