class_name HelpScreen
extends Node2D
## 作战手册：操作、四色规则、战甲、引力束过热、关卡与破罩、计分、漂浮道具
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
			"J 或 鼠标左键 —— 出刃（按住连发）",
			"空格 —— 在两件战甲间互换",
			"P —— 暂停 / 继续      R —— 重来本关",
			"ESC —— 返回上一级界面",
		],
	},
	{
		"h": "四 色 属 性",
		"l": [
			"星盗喽啰与星盗旗舰会射出四色能量弹：电浆 / 寒霜 / 光子 / 引力",
			"身上战甲与弹幕同色时 —— 该弹直接穿身而过",
			"光刃与战甲同色时 —— 伤害额外 +50%",
		],
	},
	{
		"h": "战 甲",
		"l": [
			"电浆剑甲 —— 免疫电浆弹 · 双排光刃（%d × 2）" % PlayerCfg.SWORD_DMG_RED,
			"寒霜疾甲 —— 免疫寒霜弹 · 身法提速 +50%",
			"光子盾甲 —— 免疫光子弹 · 护盾开局为 0，吸收光子弹 +%d" % PlayerCfg.SHIELD_GAIN,
			"光子护盾上限 %d，不再自动回复（只在穿着光子盾甲时充能）" % PlayerCfg.SHIELD_MAX,
			"引力束甲 —— 免疫引力弹 · 按住出持续引力束",
			"入关卡前须择【两件】，关卡内随时以空格互换",
		],
	},
	{
		"h": "引 力 束 与 过 热",
		"l": [
			"引力束甲不出光刃，改为一道绵绵不绝的引力束（按住不放）",
			"出束时过热值每秒 +%d，满 %d 点即无法出束"
				% [int(PlayerCfg.HEAT_RISE), int(PlayerCfg.HEAT_MAX)],
			"停手 %.1f 秒后每秒 -%d；硬吃一发引力弹立刻散去 %d"
				% [PlayerCfg.HEAT_COOL_DELAY, int(PlayerCfg.HEAT_COOL), int(PlayerCfg.HEAT_VENT)],
		],
	},
	{
		"h": "关 卡 与 破 罩",
		"l": [
			"五关星域层层递进，中途不再回血 —— 生命只靠修复包补",
			# 战将出场波次**五关不统一**（L1 只有第 3 波；L3/L4/L5 是末两段），
			# 所以这里只能说「末段波次」—— 不承诺数量、也不承诺波号。
			"末段波次有【星盗战将】压阵：身披属性力场，",
			"  力场未破本体不掉血 —— 须换上同色战甲方能速破",
			"部分旗舰会展开【属性护罩】，护罩色只从你所携两件战甲中抽取",
			"护罩开启时：同色光刃全额伤害，异色仅剩 60%",
			"旗舰多阶段推进，血量越低弹幕越急",
		],
	},
	{
		"h": "计 分",
		"l": [
			"斩敌得星币 · 破一阶段 +600 · 击破星盗旗舰 +5000 · 斩战将 +%d" % EnemyCfg.ELITE_SCORE,
		],
	},
	{
		"h": "漂 浮 道 具",
		"l": [
			"斩敌有概率掉落，每波星袭结束另会刷新一批",
			# 数值文案一律由 PickupCfg.tip() 现拼 —— 改了配置，说明与飘字同时跟着变
			"修复包 —— %s" % PickupCfg.tip(Pickup.T.HEAL),
			"刃影模块 —— %s 排（引力加一道束，且不额外生热）" % PickupCfg.tip(Pickup.T.MULTI),
			"增幅核心 —— %s，光刃变大 / 引力束变粗" % PickupCfg.tip(Pickup.T.ATK),
			"力场罩 —— %s，周身泛起四色护罩" % PickupCfg.tip(Pickup.T.INVINC),
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

	DrawUtil.txt(self, "作 战 手 册", Vector2(W * 0.5, 78.0), 42,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "一册在手，可历五关星域",
		Vector2(W * 0.5, 112.0), 16, Color(0.84, 0.88, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	# 两列排布。行距 / 字号 / 列宽都是按 720 高、七节内容量过的 ——
	# 纯绘制的 UI 没有自动布局，改文案要顺手复核最后一节是否压到底部提示。
	#
	# 右列比左列多装一节（4 节 15 行 vs 3 节 14 行），同款行距 720 高装不下：
	# 右列末行基线一度压到 681，与底部提示（690）叠印。右列单独收紧 ——
	# 行距 21 -> 19、节头到首行 42 -> 32；节与节的间隔反而放宽 21 -> 26
	# （26 是实测下限：再小，26px 的节头顶会蹭到上一行 15px 的行）。
	# 收紧后右列末行基线 ≈ 647（注意不是 628 —— 628 是倒数第二行，差一个 LINE_H_R），
	# 底部提示基线 690，其字形顶约 672，末行字形底约 652，
	# => 真实字形净空仅约 20px（别拿基线差 43px 当净空）。
	# 临界值：右列再加 1 行只剩约 1px，加 2 行就会重新叠印 ——
	#   要加行必须先收紧 LINE_H_R / SEC_GAP_R，或把该节挪到左列。
	# 对照：左列末行基线 597，净空约 115px。
	const LINE_H := 21.0
	const LINE_H_R := 19.0      # 右列行距（右列多一节，单独收紧，见上）
	const LINE_FS := 15
	const HEAD_GAP := 42.0      # 节头基线 -> 首行基线
	const HEAD_GAP_R := 32.0    # 右列同上（收紧）
	const SEC_GAP := 21.0       # 节尾行 -> 下一节头基线
	const SEC_GAP_R := 26.0     # 右列同上（放宽，防节头顶行）
	var col_x := [88.0, 664.0]
	var col_w := 528.0
	var col_y := [156.0, 156.0]

	for i in _sections.size():
		var col: int = 0 if i < 3 else 1
		var s: Dictionary = _sections[i]
		var x: float = col_x[col]
		var y: float = col_y[col]
		var lh: float = LINE_H if col == 0 else LINE_H_R
		var hg: float = HEAD_GAP if col == 0 else HEAD_GAP_R
		var gap: float = SEC_GAP if col == 0 else SEC_GAP_R

		var head: String = str(s["h"])
		var head_col: Color = Game.COLOR_MAIN[i % 4]
		DrawUtil.txt(self, head, Vector2(x, y), 26, head_col)
		draw_rect(Rect2(x, y + 12.0, col_w, 2.0),
			Color(head_col.r, head_col.g, head_col.b, 0.45))

		var lines: Array = s["l"]
		for j in lines.size():
			DrawUtil.txt(self, "·  " + str(lines[j]),
				Vector2(x + 6.0, y + hg + float(j) * lh), LINE_FS,
				Color(0.86, 0.90, 1.0))
		col_y[col] = y + hg + float(lines.size()) * lh + gap

	var a := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 2.6))
	DrawUtil.txt(self, "ESC / Enter  返回开始界面", Vector2(W * 0.5, H - 30.0), 18,
		Color(1.0, 0.93, 0.68, a), HORIZONTAL_ALIGNMENT_CENTER)
