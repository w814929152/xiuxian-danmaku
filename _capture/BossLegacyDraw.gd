class_name BossLegacyDraw
extends RefCounted
## 「旧模型」绘制代理 —— **完整复刻 `Boss._draw()` 的层序与覆盖层**，唯一差别是
##   ②b / ③④⑤⑥ / ⑦b / ⑦c 的机体层走哪一套实现：
##     `legacy = true`  → `BossArtLegacy`（机甲化改造前，即 git HEAD 版 BossArt）
##     `legacy = false` → `BossArt`（现行机甲化实现）
##   气息 / 狂暴 / 护罩弧 / 四色反应堆节点 / 散热期 / 末阶狂气 / 受击白闪**两侧完全同码**，
##   所以对比图里看到的任何差异都只来自机甲化改造本身，不会掺入状态不同的噪声。
##
## ⚠️ 本文件是 `Boss._draw()` 的镜像副本：改 `Boss._draw()` 后这里要同步，否则对比会失真。


static func draw_all(b: Boss, legacy: bool) -> void:
	var r := float(StageCfg.boss_r_main(b.stage))
	# 气息取本体色（逐关固定）；护罩色单独取，见下方护罩段
	var bod_c := _main_c(legacy, b.stage)
	var g := _glow_c(legacy, bod_c)
	var pulse := 0.5 + 0.5 * sin(b._t * 3.0)
	if b.phase >= b._phases:
		pulse = 0.5 + 0.5 * sin(b._t * 8.0)

	# ① 本体气息（×1.90）
	b.draw_circle(Vector2.ZERO, r * 1.90 + 8.0 * pulse, Color(g.r, g.g, g.b, 0.07))

	# ②b 背负型标志器官 / ③④ 本体 / ⑦b 外突器官 / ⑦c 机制联动 —— **唯二的差异点**
	_body_layers(b, legacy, pulse)

	# 狂暴：周身泛红光（×2.25 / ×2.00）+ 6 枚三角符标逆向游走（形状通道）
	if b.enraged:
		var ea := 0.5 + 0.5 * sin(b._t * 9.0)
		b.draw_circle(Vector2.ZERO, r * 2.25 + 12.0 * ea, Color(1.0, 0.16, 0.10, 0.10))
		b.draw_circle(Vector2.ZERO, r * 2.00 + 8.0 * ea, Color(1.0, 0.22, 0.14, 0.14))
		for i in 6:
			var ang := -b._t * 1.8 + TAU * float(i) / 6.0
			var p := Vector2.RIGHT.rotated(ang) * (r * 2.00 + 14.0 * sin(b._t * 5.0 + i))
			var d := Vector2.RIGHT.rotated(ang)
			var sd := d.rotated(PI * 0.5) * 6.0
			b.draw_colored_polygon(PackedVector2Array([p + d * 8.0, p - d * 5.0 + sd,
				p - d * 5.0 - sd]), Color(1.0, 0.30, 0.18, 0.85))

	# 属性护罩：8 段虚线弧（段间 0.16 rad 缺口）+ 8 枚符点顺时针游走
	if b.ward >= 0:
		var wm: Color = Game.COLOR_MAIN[b.ward]
		var wk: Color = Game.COLOR_CORE[b.ward]
		var a := 0.55 + 0.35 * sin(b._ward_anim * 7.0)
		b.draw_circle(Vector2.ZERO, r * 1.70, Color(wm.r, wm.g, wm.b, 0.07))
		for i in 8:
			var a0 := b._ward_anim * 1.2 + TAU * float(i) / 8.0 + 0.08
			var a1 := b._ward_anim * 1.2 + TAU * float(i + 1) / 8.0 - 0.08
			b.draw_arc(Vector2.ZERO, r * 1.70, a0, a1, 12,
				Color(wm.r, wm.g, wm.b, a), 9.0, true)
		b.draw_arc(Vector2.ZERO, r * 1.52, 0.0, TAU, 56,
			Color(wk.r, wk.g, wk.b, a * 0.55), 3.0, true)
		for i in 8:
			var ang := b._ward_anim * 1.2 + TAU * float(i) / 8.0
			var p := Vector2.RIGHT.rotated(ang) * (r * 1.70)
			b.draw_circle(p, 4.5, Color(wk.r, wk.g, wk.b, a))
		# 护罩开启：本体外缘 2px CORE 白描边（边缘通道）
		if legacy:
			BossArtLegacy.draw_body_rim(b, Game.COLOR_CORE[Game.WHITE], 2.0)
		else:
			BossArt.draw_body_rim(b, Game.COLOR_CORE[Game.WHITE], 2.0)

	# 四色反应堆节点（当前护罩色的节点放大）——尺寸按 R_MAIN 比例化
	var rr_big := clampf(r * 0.2429, 14.0, 22.0)
	var rr_small := rr_big / 1.545
	for i in 4:
		var ang := b._t * 0.85 + TAU * float(i) / 4.0
		var p := Vector2.RIGHT.rotated(ang) * (r * 1.37)
		var cm: Color = Game.COLOR_MAIN[i]
		var rr := rr_big if i == b.ward else rr_small
		b.draw_circle(p, rr + 6.0, Color(Game.COLOR_GLOW[i].r, Game.COLOR_GLOW[i].g,
			Game.COLOR_GLOW[i].b, 0.20))
		b.draw_circle(p, rr, cm)
		b.draw_circle(p, rr * 0.42, Game.COLOR_CORE[i])

	# L3 散热期：装甲舱盖打开（亮环 + 内核高亮）
	if b._heat_t > 0.0:
		var ha := 0.5 + 0.5 * sin(b._t * 12.0)
		b.draw_arc(Vector2.ZERO, r * 1.23, 0.0, TAU, 40,
			Color(1.0, 0.85, 0.35, 0.55 + 0.35 * ha), 5.0, true)
		b.draw_circle(Vector2.ZERO, r * 0.63, Color(1.0, 0.90, 0.45, 0.20))
	if b.venting:
		b.draw_arc(Vector2.ZERO, r * 1.23, 0.0, TAU, 40,
			Color(1.0, 0.55, 0.25, 0.80), 6.0, true)
		b.draw_circle(Vector2.ZERO, r * 0.43,
			Color(1.0, 0.72, 0.35, 0.50 + 0.35 * pulse))

	# 末阶狂气
	if b.phase >= b._phases:
		for i in 12:
			var ang := -b._t * 1.6 + TAU * float(i) / 12.0
			var p := Vector2.RIGHT.rotated(ang) * (r * 2.00 + 12.0 * sin(b._t * 6.0 + i))
			b.draw_circle(p, 5.0, Color(1.0, 0.35, 0.25, 0.55))

	# 受击白闪（×1.00）
	if b._flash > 0.0:
		b.draw_circle(Vector2.ZERO, r, Color(1.0, 1.0, 1.0, b._flash * 2.2))


## 机体层：新旧两套实现的**唯一分岔口**（其余层序两侧完全一致）
static func _body_layers(b: Boss, legacy: bool, pulse: float) -> void:
	if legacy:
		BossArtLegacy.draw_sig_back(b, pulse)
		BossArtLegacy.draw_body(b, pulse)
		BossArtLegacy.draw_sig_front(b, pulse)
		BossArtLegacy.draw_mechanic(b, pulse)
	else:
		BossArt.draw_sig_back(b, pulse)
		BossArt.draw_body(b, pulse)
		BossArt.draw_sig_front(b, pulse)
		BossArt.draw_mechanic(b, pulse)


static func _main_c(legacy: bool, s: int) -> int:
	return BossArtLegacy.boss_main_c(s) if legacy else BossArt.boss_main_c(s)


static func _glow_c(legacy: bool, c: int) -> Color:
	return BossArtLegacy.glow_col(c) if legacy else BossArt.glow_col(c)
