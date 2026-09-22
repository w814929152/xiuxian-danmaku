class_name DifficultySelect
extends Node2D
## 择难度：简单 / 普通 / 困难 三选一
## 键盘 1 / 2 / 3 或 ← → + Enter，鼠标悬停高亮 + 左键点击；ESC 返回开始界面
##
## 界面之间互不认识：只发 start_pressed / back_pressed，由 Main 决定去哪

signal start_pressed()
signal back_pressed()

const CARD_W := 336.0
const CARD_H := 396.0
const CARD_GAP := 364.0
const CARD_N := 3

var _sel := 1          # 默认停在「普通」
var _t := 0.0
var _hover := -1


func _ready() -> void:
	var bg := Background.new()
	bg.scroll_speed = 24.0
	add_child(bg)


func _process(delta: float) -> void:
	_t += delta
	_hover = _card_at(get_viewport().get_mouse_position())
	if _hover >= 0:
		_sel = _hover
	queue_redraw()


func _card_rect(i: int) -> Rect2:
	var x := Game.VIEW_W * 0.5 + (float(i) - 1.0) * CARD_GAP - CARD_W * 0.5
	return Rect2(x, 176.0, CARD_W, CARD_H)


func _card_at(p: Vector2) -> int:
	for i in CARD_N:
		if _card_rect(i).has_point(p):
			return i
	return -1


func _goto(i: int) -> void:
	_sel = clampi(i, 0, CARD_N - 1)


func _confirm() -> void:
	Game.difficulty = _sel
	Fx.ring(self, _card_rect(_sel).get_center(), _accent(_sel), 20.0, 240.0, 0.40, 7.0)
	start_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mv_left"):
		_goto((_sel + CARD_N - 1) % CARD_N)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mv_right"):
		_goto((_sel + 1) % CARD_N)
		get_viewport().set_input_as_handled()
		return
	for i in CARD_N:
		if event.is_action_pressed("pick_%d" % i):
			_goto(i)
			_confirm()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("confirm") or event.is_action_pressed("shoot"):
		_confirm()
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
				_goto(i)
				_confirm()
				get_viewport().set_input_as_handled()


## 三档的强调色：绿 / 蓝 / 红，跟危险程度对应
static func _accent(i: int) -> Color:
	if i == Game.EASY:
		return Color(0.46, 0.92, 0.58)
	if i == Game.HARD:
		return Color(1.00, 0.34, 0.30)
	return Color(0.42, 0.72, 1.00)


static func _lines(i: int) -> PackedStringArray:
	if i == Game.EASY:
		return PackedStringArray([
			"始祖生命  1400",
			"阶段  两重",
			"属性护罩  无",
			"弹幕密度  55%",
			"狂暴  血量三成时",
		])
	if i == Game.HARD:
		return PackedStringArray([
			"始祖生命  3600",
			"阶段  三重",
			"属性护罩  有（异色 60%）",
			"弹幕密度  100%",
			"狂暴  血量三成时",
		])
	return PackedStringArray([
		"始祖生命  2500",
		"阶段  三重",
		"属性护罩  无",
		"弹幕密度  80%",
		"狂暴  血量三成时",
	])


static func _tip(i: int) -> String:
	if i == Game.EASY:
		return "初入此道 · 弹幕稀疏，始祖不展护罩"
	if i == Game.HARD:
		return "异色光刃只剩六成伤害 · 四色螺旋狂暴"
	return "标准的出征之途 · 考验走位与换甲"


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H

	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.44))

	DrawUtil.txt(self, "择 难 度", Vector2(W * 0.5, 100.0), 46,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "三档只在始祖身上分高下 —— 星袭一视同仁",
		Vector2(W * 0.5, 140.0), 18, Color(0.86, 0.90, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	for i in CARD_N:
		var r := _card_rect(i)
		var act: bool = (i == _sel)
		var ac := _accent(i)
		var bob := sin(_t * 2.6 + i) * 4.0 if act else 0.0
		var rr := Rect2(r.position.x, r.position.y + bob, r.size.x, r.size.y)

		draw_rect(rr, Color(0.04, 0.04, 0.09, 0.90))
		if act:
			draw_rect(Rect2(rr.position.x - 6.0, rr.position.y - 6.0,
				rr.size.x + 12.0, rr.size.y + 12.0), Color(ac.r, ac.g, ac.b, 0.28))
		draw_rect(rr, Color(ac.r, ac.g, ac.b, 0.95 if act else 0.40),
			false, 3.0 if act else 1.8)

		# 顶部色带
		draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x, 10.0), ac)

		# 标题
		var cx := rr.position.x + rr.size.x * 0.5
		DrawUtil.txt(self, Game.DIFF_CN[i], Vector2(cx, rr.position.y + 74.0),
			40 if act else 34, Color(1.0, 0.97, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
		DrawUtil.txt(self, _tip(i), Vector2(cx, rr.position.y + 112.0), 15,
			Color(ac.r, ac.g, ac.b), HORIZONTAL_ALIGNMENT_CENTER)

		# 参数表
		var lines := _lines(i)
		for j in lines.size():
			var y := rr.position.y + 168.0 + float(j) * 30.0
			DrawUtil.txt(self, str(lines[j]), Vector2(rr.position.x + 44.0, y), 18,
				Color(0.88, 0.91, 1.0) if act else Color(0.66, 0.70, 0.84))

		DrawUtil.txt(self, "按 %d 键" % (i + 1),
			Vector2(cx, rr.position.y + rr.size.y - 24.0), 14,
			Color(0.60, 0.66, 0.80), HORIZONTAL_ALIGNMENT_CENTER)

	DrawUtil.txt(self, "← →  或  1 / 2 / 3  选择      Enter 确认      ESC 返回",
		Vector2(W * 0.5, H - 34.0), 17, Color(0.68, 0.74, 0.92),
		HORIZONTAL_ALIGNMENT_CENTER)
	