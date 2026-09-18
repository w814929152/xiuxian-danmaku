class_name ResultScreen
extends Node2D
## 结算界面

signal again_pressed()
signal title_pressed()

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


func _rank() -> String:
	var s := Game.result_score
	if s >= 14000:
		return "天品 · 元婴"
	if s >= 10000:
		return "地品 · 金丹"
	if s >= 6500:
		return "玄品 · 筑基"
	return "黄品 · 炼气"


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	var cx := W * 0.5
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.55))

	var title := "道 成" if win else "道 消"
	var col := Color(1.0, 0.92, 0.66) if win else Color(0.95, 0.42, 0.42)
	DrawUtil.txt(self, title, Vector2(cx, H * 0.30), 88, col, HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "血魔老祖伏诛 · 此劫已渡" if win else "元神溃散 · 再来问道",
		Vector2(cx, H * 0.30 + 58.0), 22, Color(0.88, 0.91, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	draw_rect(Rect2(cx - 230.0, H * 0.47, 460.0, 116.0), Color(0.03, 0.03, 0.08, 0.6))
	draw_rect(Rect2(cx - 230.0, H * 0.47, 460.0, 116.0), Color(0.6, 0.66, 0.95, 0.3),
		false, 1.5)
	DrawUtil.txt(self, "灵石  %d" % Game.result_score, Vector2(cx, H * 0.47 + 46.0), 34,
		Color(1.0, 0.92, 0.62), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "品阶  %s" % _rank(), Vector2(cx, H * 0.47 + 82.0), 20,
		Color(0.86, 0.90, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	if win:
		DrawUtil.txt(self, "残余元神  %d" % Game.result_hp, Vector2(cx, H * 0.47 + 106.0), 16,
			Color(0.7, 0.76, 0.92), HORIZONTAL_ALIGNMENT_CENTER)

	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.4))
	DrawUtil.txt(self, "R / J  再 来 一 次", Vector2(cx, H * 0.72), 26,
		Color(1.0, 0.95, 0.72, a), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "Enter  回 到 标 题", Vector2(cx, H * 0.72 + 38.0), 20,
		Color(0.82, 0.86, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
