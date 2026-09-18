class_name HelpScreen
extends Node2D
## 游戏说明：操作、四色规则、道袍、符光过热、关卡与破罩、计分、漂浮道具
## ESC / Enter 返回开始界面

signal back_pressed()

var _sections: Array[Dictionary] = []


## 说明文案放在函数里构建：const 里套 Dictionary / Array 不是常量表达式，
## 会报 "Assigned value for constant ... isn't a constant expression"
static func _build_sections() -> Array[Dictionary]:
	return [
	{
		"h": "操 作",
		"l": [
			"WASD / 方向键 —— 移动身法",
			"J 或 鼠标左键 —— 御剑（按住连发）",
			"空格 —— 在两件道袍间互换",
			"P —— 暂停 / 继续      R —— 重来本关",
			"ESC —— 返回上一级界面",
		],
	},
	{
		"h": "四 色 属 性",
		"l": [
			"妖物与老祖会射出四色魔法弹：赤炎 / 玄冰 / 太清 / 戊土",
			"身上道袍与弹幕同色时 —— 该弹直接穿身而过",
			"飞剑与道袍同色时 —— 伤害额外 +50%",
		],
	},
	{
		"h": "道 袍",
		"l": [
			"赤炎剑袍 —— 免疫赤炎弹 · 双排飞剑（8 × 2）",
			"玄冰遁袍 —— 免疫玄冰弹 · 身法提速 +50%",
			"太清罡袍 —— 免疫太清弹 · 十点罡气，十息无伤自动回满",
			"戊土符袍 —— 免疫戊土弹 · 按住出持续符光",
			"入关卡前须择【两件】，关卡内随时以空格互换",
		],
	},
	{
		"h": "符 光 与 过 热",
		"l": [
			"戊土符袍不出飞剑，改为一道绵绵不绝的符光（按住不放）",
			"出光时过热值每秒 +20，满 100 点即无法出光",
			"停手 0.5 秒后每秒 -30；硬吃一发戊土符弹立刻散去 30",
		],
	},
	{
		"h": "关 卡 与 破 罩",
		"l": [
			"三重妖潮层层递进，中途不再回血 —— 元神只靠回春丹补",
			"第 2、3 重妖潮末有【护法妖将】压阵：身披属性法罡，",
			"  法罡未破本体不掉血 —— 须换上同色道袍方能速破",
			"血魔老祖会展开【属性法罩】，法罩色只从你所携两件道袍中抽取",
			"法罩开启时：同色飞剑全额伤害，异色仅剩 60%",
			"老祖三阶段，血量越低弹幕越急",
		],
	},
	{
		"h": "计 分",
		"l": [
			"斩妖得灵石 · 破一重法相 +600 · 斩杀老祖 +5000 · 斩妖将 +800",
		],
	},
	{
		"h": "漂 浮 道 具",
		"l": [
			"斩妖有概率掉落，每重妖潮结束另会刷新一批",
			"回春丹 —— 回复元神 20 点",
			"剑影符 —— 弹道 +1 排（戊土加一道符光，且不额外生热）",
			"增攻符 —— 攻击 +30%，飞剑变大 / 符光变粗",
			"无量罩 —— 六秒无敌，周身泛起四色护罩",
		],
	},
	]


var _t := 0.0


func _ready() -> void:
	_sections = _build_sections()
	var bg := Background.new()
	bg.scroll_speed = 18.0
	add_child(bg)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("confirm") \
			or event.is_action_pressed("shoot"):
		back_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			back_pressed.emit()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.52))

	DrawUtil.txt(self, "游 戏 说 明", Vector2(W * 0.5, 78.0), 42,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "一册在手，可入三重妖潮",
		Vector2(W * 0.5, 112.0), 16, Color(0.84, 0.88, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	# 两列排布。行距 / 字号 / 列宽都是按 720 高、七节内容量过的 ——
	# 纯绘制的 UI 没有自动布局，改文案要顺手复核最后一节是否压到底部提示。
	const LINE_H := 21.0
	const LINE_FS := 15
	var col_x := [88.0, 664.0]
	var col_w := 528.0
	var col_y := [156.0, 156.0]

	for i in _sections.size():
		var col: int = 0 if i < 3 else 1
		var s: Dictionary = _sections[i]
		var x: float = col_x[col]
		var y: float = col_y[col]

		var head: String = str(s["h"])
		var head_col: Color = Game.COLOR_MAIN[i % 4]
		DrawUtil.txt(self, head, Vector2(x, y), 26, head_col)
		draw_rect(Rect2(x, y + 12.0, col_w, 2.0),
			Color(head_col.r, head_col.g, head_col.b, 0.45))

		var lines: Array = s["l"]
		for j in lines.size():
			DrawUtil.txt(self, "·  " + str(lines[j]),
				Vector2(x + 6.0, y + 42.0 + float(j) * LINE_H), LINE_FS,
				Color(0.86, 0.90, 1.0))
		col_y[col] = y + 42.0 + float(lines.size()) * LINE_H + LINE_H

	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 2.6))
	DrawUtil.txt(self, "ESC / Enter  返回开始界面", Vector2(W * 0.5, H - 30.0), 18,
		Color(1.0, 0.93, 0.68, a), HORIZONTAL_ALIGNMENT_CENTER)
