class_name ResultScreen
extends Node2D
## 结算界面

signal again_pressed()
signal title_pressed()
## 换甲再来：保留当前难度直接回择甲界面
signal swap_pressed()

var win := false
var _t := 0.0


func _ready() -> void:
	var bg := Background.new()
	bg.scroll_speed = 20.0
	add_child(bg)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") or event.is_action_pressed("shoot"):
		again_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm") or event.is_action_pressed("cancel"):
		title_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("swap_again"):
		swap_pressed.emit()
		get_viewport().set_input_as_handled()


func _rank() -> String:
	return Game.rank_of(Game.result_score)


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	var cx := W * 0.5
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.55))

	var title := "凯 旋" if win else "陨 落"
	var col := Color(1.0, 0.92, 0.66) if win else Color(0.95, 0.42, 0.42)
	DrawUtil.txt(self, title, Vector2(cx, H * 0.30), 88, col, HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "星盗始祖伏诛 · 此役已毕" if win else "生命耗尽 · 再战此疆",
		Vector2(cx, H * 0.30 + 58.0), 22, Color(0.88, 0.91, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	draw_rect(Rect2(cx - 230.0, H * 0.47, 460.0, 142.0), Color(0.03, 0.03, 0.08, 0.6))
	draw_rect(Rect2(cx - 230.0, H * 0.47, 460.0, 142.0), Color(0.6, 0.66, 0.95, 0.3),
		false, 1.5)
	DrawUtil.txt(self, "星币  %d" % Game.result_score, Vector2(cx, H * 0.47 + 46.0), 34,
		Color(1.0, 0.92, 0.62), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "品阶  %s" % _rank(), Vector2(cx, H * 0.47 + 84.0), 20,
		Color(0.86, 0.90, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	# 历史最高：取自本地存档。破纪录时右边挂一枚「新 高」——
	# 存档里存的是刷新后的值，所以这里显示的是本局之前的成绩，
	# 否则这行永远等于上面的星币数。
	DrawUtil.txt(self, "历史最高  %d" % Game.result_prev_high,
		Vector2(cx, H * 0.47 + 112.0), 17,
		Color(0.72, 0.78, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	if Game.result_is_new_high:
		DrawUtil.txt(self, "新 高", Vector2(cx + 156.0, H * 0.47 + 112.0), 17,
			Color(1.0, 0.86, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
	if win:
		DrawUtil.txt(self, "剩余生命  %d" % Game.result_hp, Vector2(cx, H * 0.47 + 134.0), 15,
			Color(0.7, 0.76, 0.92), HORIZONTAL_ALIGNMENT_CENTER)

	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.4))
	DrawUtil.txt(self, "R / J  再 来 一 次", Vector2(cx, H * 0.72), 26,
		Color(1.0, 0.95, 0.72, a), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "T  换 甲 再 来", Vector2(cx, H * 0.72 + 38.0), 20,
		Color(0.82, 0.86, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "Enter  回 到 标 题", Vector2(cx, H * 0.72 + 76.0), 20,
		Color(0.82, 0.86, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
