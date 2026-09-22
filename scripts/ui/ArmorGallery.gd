class_name ArmorGallery
extends Node2D
## 战甲库：逐件翻阅四件战甲的形制、免疫属性与战技
## ← → 或 1 / 2 / 3 / 4 切换，ESC / Enter 返回开始界面

signal back_pressed()

const TAB_N := 4

var _idx := 0
var _t := 0.0
var _hover := -1


func _ready() -> void:
	var bg := Background.new()
	bg.scroll_speed = 22.0
	add_child(bg)


func _process(delta: float) -> void:
	_t += delta
	_hover = _tab_at(get_viewport().get_mouse_position())
	queue_redraw()


func _tab_rect(i: int) -> Rect2:
	var w := 194.0
	var x := Game.VIEW_W * 0.5 + (float(i) - (float(TAB_N) - 1.0) * 0.5) \
		* (w + 20.0) - w * 0.5
	return Rect2(x, 596.0, w, 62.0)


func _tab_at(p: Vector2) -> int:
	for i in TAB_N:
		if _tab_rect(i).has_point(p):
			return i
	return -1


func _goto(i: int) -> void:
	if i == _idx:
		return
	_idx = i
	Fx.ring(self, _tab_rect(i).get_center(), Game.COLOR_MAIN[i], 10.0, 130.0, 0.35, 5.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mv_left"):
		_goto((_idx + TAB_N - 1) % TAB_N)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mv_right"):
		_goto((_idx + 1) % TAB_N)
		get_viewport().set_input_as_handled()
		return
	for i in TAB_N:
		if event.is_action_pressed("pick_%d" % i):
			_goto(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("cancel") or event.is_action_pressed("confirm") \
			or event.is_action_pressed("shoot"):
		back_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _tab_at(mb.position)
			if i >= 0:
				_goto(i)
				get_viewport().set_input_as_handled()


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	var c: int = _idx
	var m: Color = Game.COLOR_MAIN[c]
	var g: Color = Game.COLOR_GLOW[c]

	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.46))

	DrawUtil.txt(self, "战 甲 库", Vector2(W * 0.5, 92.0), 44,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "一甲一性，择其二而出征 —— 免疫同色弹幕",
		Vector2(W * 0.5, 132.0), 17, Color(0.86, 0.90, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	# ---------- 左：立绘 ----------
	var lp := Rect2(90.0, 176.0, 470.0, 386.0)
	draw_rect(lp, Color(0.03, 0.03, 0.08, 0.72))
	draw_rect(lp, Color(m.r, m.g, m.b, 0.55), false, 2.0)
	ArmorArt.draw(self, Vector2(lp.position.x + lp.size.x * 0.5,
		lp.position.y + lp.size.y * 0.48), c, _t, 2.15)
	DrawUtil.txt(self, Game.ARMOR_STORE[c],
		Vector2(lp.position.x + lp.size.x * 0.5, lp.position.y + lp.size.y - 26.0),
		16, Color(m.r, m.g, m.b, 0.9), HORIZONTAL_ALIGNMENT_CENTER)

	# ---------- 右：详述 ----------
	var rx := 606.0
	var ry := 176.0
	draw_rect(Rect2(rx, ry, W - rx - 90.0, 386.0), Color(0.03, 0.03, 0.08, 0.72))
	draw_rect(Rect2(rx, ry, W - rx - 90.0, 386.0), Color(m.r, m.g, m.b, 0.35), false, 2.0)

	var px := rx + 40.0
	var py := ry + 56.0
	DrawUtil.txt(self, Game.ARMOR_TITLE[c], Vector2(px, py), 40,
		Color(1.0, 0.97, 0.86))
	DrawUtil.txt(self, "第 %d / %d 件" % [c + 1, TAB_N], Vector2(rx + 40.0, py + 34.0), 15,
		Color(0.62, 0.68, 0.84))

	# 已择标记
	if Game.picked_armors.has(c):
		DrawUtil.txt(self, "· 当前已择 ·", Vector2(rx + 240.0, py - 6.0), 16,
			Color(1.0, 0.90, 0.55))

	# 免疫
	py += 78.0
	draw_rect(Rect2(px, py - 22.0, 300.0, 34.0), Color(m.r, m.g, m.b, 0.16))
	DrawUtil.txt(self, "免疫【%s】属性弹" % Game.COLOR_CN[c], Vector2(px + 12.0, py + 2.0),
		20, Color(m.r, m.g, m.b))

	# 神通
	py += 52.0
	var lines: PackedStringArray = str(Game.ARMOR_DESC[c]).split("\n")
	for j in lines.size():
		DrawUtil.txt(self, "·  " + str(lines[j]), Vector2(px, py + float(j) * 30.0),
			19, Color(0.90, 0.93, 1.0))

	# 详述
	py += float(lines.size()) * 30.0 + 26.0
	var lore: PackedStringArray = str(Game.ARMOR_LORE[c]).split("\n")
	for j in lore.size():
		DrawUtil.txt(self, str(lore[j]), Vector2(px, py + float(j) * 24.0),
			15, Color(0.68, 0.73, 0.88))

	# ---------- 底部：四件切换 ----------
	for i in TAB_N:
		var r := _tab_rect(i)
		var mc: Color = Game.COLOR_MAIN[i]
		var act: bool = (i == _idx)
		var hv: bool = (_hover == i)
		draw_rect(r, Color(0.03, 0.03, 0.08, 0.85))
		draw_rect(r, Color(mc.r, mc.g, mc.b, 0.95 if act else (0.6 if hv else 0.35)),
			false, 3.0 if act else 1.6)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5.0), mc)
		DrawUtil.txt(self, Game.ARMOR_TITLE[i],
			Vector2(r.position.x + r.size.x * 0.5, r.position.y + 30.0),
			20 if act else 18, Color(1, 1, 1) if act else Color(0.72, 0.76, 0.88),
			HORIZONTAL_ALIGNMENT_CENTER)
		DrawUtil.txt(self, Game.ARMOR_TAG[i],
			Vector2(r.position.x + r.size.x * 0.5, r.position.y + 51.0),
			13, Color(mc.r, mc.g, mc.b, 1.0 if act else 0.55),
			HORIZONTAL_ALIGNMENT_CENTER)
		if Game.picked_armors.has(i):
			DrawUtil.txt(self, "已择", Vector2(r.position.x + r.size.x - 12.0,
				r.position.y + 28.0), 13, Color(1.0, 0.90, 0.55),
				HORIZONTAL_ALIGNMENT_RIGHT)

	DrawUtil.txt(self, "← →  或  1 / 2 / 3 / 4  翻阅      ESC / Enter  返回",
		Vector2(W * 0.5, H - 30.0), 16, Color(0.66, 0.72, 0.90),
		HORIZONTAL_ALIGNMENT_CENTER)
