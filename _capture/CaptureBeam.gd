extends Node2D
## 一次性截帧工具（真窗口运行，**不可 --headless**）：
## 竖直排四个引力束甲，刃影模块层数 0/1/2/3 -> 引力束 1/2/3/4 道，
## 核对多道引力束之间的间距是不是「挨着」（见 PlayerCfg.BEAM_GAP）。
##
## 出两张：常规粗细 / 叠满增幅核心（光柱加粗约 1.88 倍，确认不糊成一坨、
## 还能数清道数）。
## 产物：D:/demo/_beam_gap.png、D:/demo/_beam_gap_wide.png

const OUT_A := "D:/demo/_beam_gap.png"
const OUT_B := "D:/demo/_beam_gap_wide.png"

var _ys := [130.0, 290.0, 450.0, 610.0]
var _tags := ["1 道", "2 道", "3 道", "4 道"]
var _players: Array[Player] = []
var _wide := false


func _ready() -> void:
	_build()
	await _shot(OUT_A)
	for p in _players:
		p.atk_up = PlayerCfg.ATK_MAX      # 叠满增幅核心 -> 光柱加粗
		p._beam_on()
	_wide = true
	queue_redraw()
	await _shot(OUT_B)
	get_tree().quit()


func _build() -> void:
	for i in 4:
		var p := Player.new()
		p.armors = [Game.YELLOW, Game.RED]
		p.armor_idx = 0
		# position 必须在 add_child 之后设 —— _ready() 里会把它重置成 (230, 360)
		add_child(p)
		p.position = Vector2(230.0, _ys[i])
		p.world = self
		p.multi = i                       # 0..3 -> 道数 1..4
		# 停掉自动出束：截帧没有真实按键，_shoot() 会因为「没按住」立刻熄灯
		p.set_process(false)
		p._beam_on()
		_players.append(p)


func _shot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE_SAVED " + path)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.05, 0.06, 0.12))
	var title := "引力束道数对比（叠满增幅核心）" if _wide else "引力束道数对比"
	DrawUtil.txt(self, title, Vector2(24.0, 40.0), 20, Color(1.0, 0.93, 0.42))
	for i in 4:
		DrawUtil.txt(self, _tags[i], Vector2(24.0, _ys[i] - 8.0), 15,
			Color(1.0, 0.93, 0.42))
