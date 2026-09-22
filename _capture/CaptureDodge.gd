extends Node2D
## 一次性截帧工具（真窗口运行，**不可 --headless**）：
## 四个寒霜疾甲并排，闪避进度各不相同 —— 核对「机身变淡」与「残影环下限」。
##
## 左 -> 右：常态 / 前段 0.45s / 中段 0.25s / 尾段 0.08s
## 尾段是本次的修复重点：残影环 alpha 原本按 0.80*(1-ph) 衰减，
## 剩约 0.05s 时降到约 0.08 几乎不可见 —— 玩家最隐形、且马上要恢复受击的
## 窗口恰好没有定位锚。现已加下限 maxf(0.35, ...)，本帧即用来确认它生效。
##
## 产物落在 D:/demo/_dodge_strip.png

const OUT := "D:/demo/_dodge_strip.png"

var _players: Array[Player] = []
var _x := [180.0, 490.0, 800.0, 1110.0]
var _dodge := [0.0, 0.45, 0.25, 0.08]
var _tag := ["常态", "前段 0.45s", "中段 0.25s", "尾段 0.08s"]


func _ready() -> void:
	for i in 4:
		var p := Player.new()
		p.armors = [Game.BLUE, Game.RED]
		p.armor_idx = 0
		# 注意：position 必须在 add_child 之后设 —— _ready() 里会把位置重置成 (230, 360)
		add_child(p)
		p.position = Vector2(_x[i], 330.0)
		_players.append(p)
	# 每帧重设 _dodge，抵消 _process 的递减，保证落帧时就是目标进度
	for _i in 3:
		await get_tree().process_frame
		for j in _players.size():
			_players[j]._dodge = _dodge[j]
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("CAPTURE_SAVED dodge")
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.04, 0.07, 0.16))
	for i in _tag.size():
		DrawUtil.txt(self, _tag[i], Vector2(_x[i] - 60.0, 560.0), 16, Color(0.85, 0.92, 1.0))
	DrawUtil.txt(self, "寒霜疾甲 · 闪避各阶段（背景为纯色，便于看淡出）",
		Vector2(60.0, 60.0), 20, Color(0.62, 0.86, 0.98))
