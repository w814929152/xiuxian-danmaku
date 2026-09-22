class_name ResultScreen
extends Node2D
## 结算界面
##
## 品阶已改为「每关独立完成度」（设计 §J.1）：品阶串由 `Game.rank_of_stage(score, stage)`
## 按本关阈值现算，**不再跨关可比**，所以这里必须补一行「完成度 xx%」向玩家自解释。
## 通关且解锁了下一关时，多一条「下一关」入口（`next_pressed`），由 Main 接去推进关号。

signal again_pressed()
## 回关卡选择（原 title_pressed —— 择难度界面已由 StageSelect 取代，语义随之改变）
signal stage_pressed()
## 换甲再来：保留当前关卡直接回择甲界面
signal swap_pressed()
## 继续推进：进入下一关（仅通关且下一关已解锁时可用）
signal next_pressed()

var win := false
## 本局关号（由 Main 在 add_child 之前注入）
var stage: int = 1
var _t := 0.0


func _ready() -> void:
	# 下一关快捷键 N：Game.ACTION_KEYS 里没有，这里补齐（不改动 Game.gd）
	_ensure_key("next", [KEY_N])
	var bg := Background.new()
	bg.scroll_speed = 20.0
	add_child(bg)


## 输入动作补齐：动作不存在就建，键位缺就补（Game.gd 日后补了也不冲突）
static func _ensure_key(a: String, keys: Array[int]) -> void:
	if not InputMap.has_action(a):
		InputMap.add_action(a, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		if not InputMap.action_has_event(a, ev):
			InputMap.action_add_event(a, ev)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 是否给出「下一关」入口：赢了、且下一关已解锁（_finish 里已 unlock_after）
func can_next() -> bool:
	if not win:
		return false
	var nxt := stage + 1
	return nxt <= StageCfg.STAGE_N and Game.is_unlocked(nxt)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") or event.is_action_pressed("shoot"):
		again_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("next"):
		if can_next():
			next_pressed.emit()
		else:
			Fx.pop(self, Vector2(Game.VIEW_W * 0.5, 586.0), "下一关尚未解锁",
				Color(1.0, 0.62, 0.55), 20, 1.0)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("confirm") or event.is_action_pressed("cancel"):
		stage_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("swap_again"):
		swap_pressed.emit()
		get_viewport().set_input_as_handled()


func _rank() -> String:
	return Game.rank_of_stage(Game.result_score, stage)


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	var cx := W * 0.5
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.55))

	var title := "凯 旋" if win else "陨 落"
	var col := Color(1.0, 0.92, 0.66) if win else Color(0.95, 0.42, 0.42)
	DrawUtil.txt(self, title, Vector2(cx, H * 0.30), 88, col, HORIZONTAL_ALIGNMENT_CENTER)
	var sub: String = "%s 已破 · 此役已毕" % StageCfg.boss_name(stage) if win \
		else "生命耗尽 · 再战此疆"
	DrawUtil.txt(self, sub, Vector2(cx, H * 0.30 + 58.0), 22, Color(0.88, 0.91, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	var py := H * 0.47
	var ph := 168.0
	draw_rect(Rect2(cx - 230.0, py, 460.0, ph), Color(0.03, 0.03, 0.08, 0.6))
	draw_rect(Rect2(cx - 230.0, py, 460.0, ph), Color(0.6, 0.66, 0.95, 0.3),
		false, 1.5)
	DrawUtil.txt(self, "星币  %d" % Game.result_score, Vector2(cx, py + 46.0), 34,
		Color(1.0, 0.92, 0.62), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "品阶  %s" % _rank(), Vector2(cx, py + 84.0), 20,
		Color(0.86, 0.90, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	# 历史最高：取自本地存档。破纪录时右边挂一枚「新 高」——
	# 存档里存的是刷新后的值，所以这里显示的是本局之前的成绩，
	# 否则这行永远等于上面的星币数。
	DrawUtil.txt(self, "历史最高  %d" % Game.result_prev_high,
		Vector2(cx, py + 112.0), 17,
		Color(0.72, 0.78, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	if Game.result_is_new_high:
		DrawUtil.txt(self, "新 高", Vector2(cx + 156.0, py + 112.0), 17,
			Color(1.0, 0.86, 0.42), HORIZONTAL_ALIGNMENT_CENTER)
	# 完成度：品阶不再跨关可比，这一行负责把「88% 是什么意思」说清楚
	DrawUtil.txt(self, "完成度  %d%%（本关满分 %d）" % [
		int(roundf(Game.completion_of(Game.result_score, stage) * 100.0)),
		StageCfg.theoretical_max(stage),
	], Vector2(cx, py + 134.0), 15, Color(0.70, 0.76, 0.92),
		HORIZONTAL_ALIGNMENT_CENTER)
	if win:
		DrawUtil.txt(self, "剩余生命  %d" % Game.result_hp, Vector2(cx, py + 154.0), 15,
			Color(0.7, 0.76, 0.92), HORIZONTAL_ALIGNMENT_CENTER)

	# 解锁行：让「通关 = 解锁下一关」这条推进规则当场可见
	var nxt := stage + 1
	if can_next():
		DrawUtil.txt(self, "解 锁 · 第 %d 关（%s）" % [nxt, StageCfg.name_of(nxt)],
			Vector2(cx, py + ph + 18.0), 19, Color(1.0, 0.86, 0.42),
			HORIZONTAL_ALIGNMENT_CENTER)
	elif win and nxt > StageCfg.STAGE_N:
		DrawUtil.txt(self, "五 关 已 通 · 星 域 尽 收",
			Vector2(cx, py + ph + 18.0), 19, Color(1.0, 0.86, 0.42),
			HORIZONTAL_ALIGNMENT_CENTER)

	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.4))
	DrawUtil.txt(self, "R / J  再 来 一 次", Vector2(cx, 552.0), 26,
		Color(1.0, 0.95, 0.72, a), HORIZONTAL_ALIGNMENT_CENTER)
	if can_next():
		DrawUtil.txt(self, "N  下 一 关 · 第 %d 关（%s）" % [nxt, StageCfg.name_of(nxt)],
			Vector2(cx, 586.0), 22, Color(0.72, 1.0, 0.86),
			HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "T  换 甲 再 来        Enter  回 关 卡 选 择",
		Vector2(cx, 620.0), 18, Color(0.82, 0.86, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
