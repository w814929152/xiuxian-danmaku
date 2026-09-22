class_name TitleScreen
extends Node2D
## 开始界面（主菜单）
## 三项：开始出征 / 战甲库 / 作战手册
## 键盘 ↑↓ + Enter，或数字键 1/2/3 直达，鼠标悬停高亮 + 左键点击

signal start_pressed()
signal gallery_pressed()
signal help_pressed()

const ITEMS := ["开 始 出 征", "战 甲 库", "作 战 手 册"]
const SUBS := [
	"择两件战甲 · 历三重星袭 · 战星盗始祖",
	"翻阅四件战甲的形制、免疫与战技",
	"操作、规则、计分与破罩之法",
]

const ITEM_W := 460.0
const ITEM_H := 78.0
const ITEM_GAP := 14.0

var _sel := 0
var _t := 0.0


func _ready() -> void:
	var bg := Background.new()
	bg.scroll_speed = 30.0
	add_child(bg)


func _process(delta: float) -> void:
	_t += delta
	var i := _item_at(get_viewport().get_mouse_position())
	if i >= 0:
		_sel = i
	queue_redraw()


func _item_rect(i: int) -> Rect2:
	var y := Game.VIEW_H * 0.505 + float(i) * (ITEM_H + ITEM_GAP)
	return Rect2(Game.VIEW_W * 0.5 - ITEM_W * 0.5, y - ITEM_H * 0.5, ITEM_W, ITEM_H)


func _item_at(p: Vector2) -> int:
	for i in ITEMS.size():
		if _item_rect(i).has_point(p):
			return i
	return -1


func _activate() -> void:
	match _sel:
		0:
			start_pressed.emit()
		1:
			gallery_pressed.emit()
		_:
			help_pressed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mv_up"):
		_sel = (_sel + ITEMS.size() - 1) % ITEMS.size()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mv_down"):
		_sel = (_sel + 1) % ITEMS.size()
		get_viewport().set_input_as_handled()
		return
	for i in ITEMS.size():
		if event.is_action_pressed("pick_%d" % i):
			_sel = i
			_activate()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("confirm") or event.is_action_pressed("shoot"):
		_activate()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _item_at(mb.position)
			if i >= 0:
				_sel = i
				_activate()
				get_viewport().set_input_as_handled()


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	var cx := W * 0.5

	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.30))

	# 四色法环
	for i in 4:
		var ang := _t * 0.55 + TAU * float(i) / 4.0
		var p := Vector2(cx, H * 0.29) + Vector2.RIGHT.rotated(ang) * 210.0
		var m: Color = Game.COLOR_MAIN[i]
		draw_circle(p, 28.0, Color(m.r, m.g, m.b, 0.10))
		draw_circle(p, 12.0, Color(m.r, m.g, m.b, 0.85))
		draw_circle(p, 5.0, Game.COLOR_CORE[i])

	# 标题
	var ty := H * 0.255
	DrawUtil.txt(self, "星 际 弹 幕", Vector2(cx + 3.0, ty + 3.0), 80,
		Color(0.05, 0.02, 0.08, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "星 际 弹 幕", Vector2(cx, ty), 80,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)

	# 菜单
	for i in ITEMS.size():
		var r := _item_rect(i)
		var act: bool = (i == _sel)
		var m: Color = Game.COLOR_MAIN[i]
		var bob := sin(_t * 2.6 + i) * 2.0 if act else 0.0
		var rr := Rect2(r.position.x, r.position.y + bob, r.size.x, r.size.y)

		draw_rect(rr, Color(0.03, 0.03, 0.08, 0.86 if act else 0.66))
		if act:
			draw_rect(Rect2(rr.position.x - 5.0, rr.position.y - 5.0,
				rr.size.x + 10.0, rr.size.y + 10.0), Color(m.r, m.g, m.b, 0.28))
		draw_rect(rr, Color(m.r, m.g, m.b, 0.95 if act else 0.40), false,
			3.0 if act else 1.6)

		# 左侧色条
		draw_rect(Rect2(rr.position.x, rr.position.y, 6.0, rr.size.y),
			Color(m.r, m.g, m.b, 1.0 if act else 0.5))

		DrawUtil.txt(self, ITEMS[i],
			Vector2(rr.position.x + rr.size.x * 0.5, rr.position.y + 40.0),
			30 if act else 26,
			Color(1.0, 0.96, 0.80) if act else Color(0.80, 0.84, 0.94),
			HORIZONTAL_ALIGNMENT_CENTER)
		DrawUtil.txt(self, SUBS[i],
			Vector2(rr.position.x + rr.size.x * 0.5, rr.position.y + 64.0),
			14, Color(0.72, 0.78, 0.95) if act else Color(0.52, 0.56, 0.70),
			HORIZONTAL_ALIGNMENT_CENTER)

		# 序号提示
		DrawUtil.txt(self, str(i + 1),
			Vector2(rr.position.x + rr.size.x - 18.0, rr.position.y + 40.0),
			15, Color(m.r, m.g, m.b, 0.9 if act else 0.45),
			HORIZONTAL_ALIGNMENT_RIGHT)

	# 底部提示
	DrawUtil.txt(self, "↑ ↓ 选择      Enter / J 确认      1 / 2 / 3 直达",
		Vector2(cx, H - 58.0), 16, Color(0.66, 0.72, 0.90),
		HORIZONTAL_ALIGNMENT_CENTER)
	var a := 0.5 + 0.5 * (0.5 + 0.5 * sin(_t * 2.2))
	DrawUtil.txt(self, "入关卡前需择【两件】战甲，关卡内以【空格】互换",
		Vector2(cx, H - 30.0), 15, Color(0.60, 0.66, 0.86, a),
		HORIZONTAL_ALIGNMENT_CENTER)
