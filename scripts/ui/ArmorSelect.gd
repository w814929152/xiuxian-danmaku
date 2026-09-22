class_name ArmorSelect
extends Node2D
## 择战甲：四选二（关卡内按空格互换）

signal start_pressed()
signal back_pressed()

const CARD_W := 272.0
const CARD_H := 392.0
const CARD_GAP := 292.0
const CARD_N := 4

var picked: Array[int] = []
var hover := -1
var _t := 0.0


func _ready() -> void:
	# 立绘缩放为连续小数倍（1.05），这里保持默认线性采样即可
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bg := Background.new()
	bg.scroll_speed = 26.0
	add_child(bg)


func _process(delta: float) -> void:
	_t += delta
	var mp := get_viewport().get_mouse_position()
	hover = _card_at(mp)
	queue_redraw()


func _card_rect(i: int) -> Rect2:
	var x := Game.VIEW_W * 0.5 + (float(i) - (float(CARD_N) - 1.0) * 0.5) \
		* CARD_GAP - CARD_W * 0.5
	return Rect2(x, 188.0, CARD_W, CARD_H)


func _card_at(p: Vector2) -> int:
	for i in CARD_N:
		if _card_rect(i).has_point(p):
			return i
	return -1


func _unhandled_input(event: InputEvent) -> void:
	for i in CARD_N:
		if event.is_action_pressed("pick_%d" % i):
			_toggle(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("confirm"):
		if picked.size() == 2:
			Game.picked_armors = picked.duplicate()
			start_pressed.emit()
		else:
			Fx.pop(self, Vector2(Game.VIEW_W * 0.5, 620.0), "还需再择一件战甲",
				Color(1.0, 0.6, 0.5), 20, 1.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel"):
		back_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _card_at(mb.position)
			if i >= 0:
				_toggle(i)
				get_viewport().set_input_as_handled()


func _toggle(i: int) -> void:
	var at := picked.find(i)
	if at >= 0:
		picked.remove_at(at)
		return
	if picked.size() >= 2:
		picked.remove_at(0)
	picked.append(i)
	Fx.ring(self, _card_rect(i).get_center(), Game.COLOR_MAIN[i], 20.0, 210.0, 0.4, 6.0)


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.42))

	DrawUtil.txt(self, "择 二 战 甲", Vector2(W * 0.5, 104.0), 46,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "关卡中按【空格】在两件战甲间互换 —— 免疫同色弹幕",
		Vector2(W * 0.5, 146.0), 18, Color(0.86, 0.90, 1.0), HORIZONTAL_ALIGNMENT_CENTER)

	for i in CARD_N:
		var r := _card_rect(i)
		var m: Color = Game.COLOR_MAIN[i]
		var sel := picked.find(i)
		var is_hover := (hover == i)
		var bob := 0.0
		if sel >= 0:
			bob = sin(_t * 3.0 + i) * 4.0
		var rr := Rect2(r.position.x, r.position.y + bob, r.size.x, r.size.y)

		# 卡面
		draw_rect(rr, Color(0.04, 0.04, 0.09, 0.88))
		if sel >= 0:
			draw_rect(Rect2(rr.position.x - 6.0, rr.position.y - 6.0,
				rr.size.x + 12.0, rr.size.y + 12.0), Color(m.r, m.g, m.b, 0.30))
		draw_rect(rr, Color(m.r, m.g, m.b, 0.95 if sel >= 0 else (0.75 if is_hover else 0.42)),
			false, 3.0 if sel >= 0 else 2.0)

		# 顶部色带
		draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x, 10.0), m)

		# 战甲立绘
		var cp := Vector2(rr.position.x + rr.size.x * 0.5, rr.position.y + 92.0)
		var pulse := 0.5 + 0.5 * sin(_t * 2.4 + i)
		draw_circle(cp, 58.0 + 5.0 * pulse, Color(m.r, m.g, m.b, 0.08))
		ArmorArt.draw(self, cp, i, _t, 1.05)

		# 文案
		DrawUtil.txt(self, Game.ARMOR_TITLE[i], Vector2(cp.x, rr.position.y + 176.0), 26,
			Color(1.0, 1.0, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
		DrawUtil.txt(self, "免疫【%s】弹" % Game.COLOR_CN[i],
			Vector2(cp.x, rr.position.y + 208.0), 17,
			Color(m.r, m.g, m.b), HORIZONTAL_ALIGNMENT_CENTER)

		var lines: PackedStringArray = str(Game.ARMOR_DESC[i]).split("\n")
		for j in lines.size():
			DrawUtil.txt(self, str(lines[j]), Vector2(cp.x, rr.position.y + 248.0 + j * 27.0),
				15, Color(0.84, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)

		# 序号徽记
		if sel >= 0:
			var label: String = ["", "壹", "贰"][sel + 1]
			var bp := Vector2(rr.position.x + rr.size.x - 34.0, rr.position.y + 40.0)
			draw_circle(bp, 24.0, Color(m.r, m.g, m.b, 0.95))
			DrawUtil.txt(self, label, Vector2(bp.x, bp.y + 8.0), 22,
				Color(0.06, 0.06, 0.10), HORIZONTAL_ALIGNMENT_CENTER)

		DrawUtil.txt(self, "按 %d 键" % (i + 1), Vector2(cp.x, rr.position.y + rr.size.y - 22.0),
			14, Color(0.6, 0.66, 0.8), HORIZONTAL_ALIGNMENT_CENTER)

	# 底部状态
	var names := PackedStringArray()
	for c in picked:
		names.append(Game.ARMOR_TITLE[c])
	var s := "已择：" + (" + ".join(names) if names.size() > 0 else "（尚未选择）")
	DrawUtil.txt(self, s, Vector2(W * 0.5, 636.0), 22, Color(1.0, 0.92, 0.66),
		HORIZONTAL_ALIGNMENT_CENTER)

	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.4))
	var tip := "按 Enter 开始出征（需择满两件）" if picked.size() == 2 \
		else "再择 %d 件战甲" % (2 - picked.size())
	DrawUtil.txt(self, tip, Vector2(W * 0.5, 676.0), 22,
		Color(1.0, 0.95, 0.72, a), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "ESC 返回开始界面", Vector2(W * 0.5, 704.0), 15,
		Color(0.6, 0.66, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
