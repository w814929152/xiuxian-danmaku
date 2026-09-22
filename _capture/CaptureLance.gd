extends Node2D
## 一次性截帧工具（真窗口运行，**不可 --headless**）：
## 核对电浆剑甲的贯穿激光 —— 光柱造型、贯穿一排敌人、以及 HUD 能量条的排布。
##
## 三排红甲玩家各带一排蓝色星盗，光柱分三次打出（由早到晚），
## 于是同一张图里能同时看到「刚打出 / 收束中 / 将散」三个阶段的造型。
##
## 出两张：
##   A —— 当前穿着电浆剑甲：能量条点亮（护盾条暗 + 提示）
##   B —— 当前穿着引力束甲且过热中：三条（护盾 / 能量 / 过热）同时在场，
##        核对其纵向排布不叠印
## 产物：D:/demo/_lance.png、D:/demo/_lance_hud.png

const OUT_A := "D:/demo/_lance.png"
const OUT_B := "D:/demo/_lance_hud.png"

var _ys := [170.0, 360.0, 550.0]
var _charges := [80, 40, 20]
var _players: Array[Player] = []
var _hud_b: HUD = null
var _hud_a: HUD = null


func _ready() -> void:
	_build()

	# 由早到晚依次打出：先打的那一排收束得最厉害
	_players[2]._fire_lance()
	await _frames(4)
	_players[1]._fire_lance()
	await _frames(4)
	_players[0]._fire_lance()
	await _frames(2)

	_hud_b.visible = false
	await _shot(OUT_A)
	_hud_a.visible = false
	_hud_b.visible = true
	queue_redraw()
	await _shot(OUT_B)
	get_tree().quit()


func _build() -> void:
	for i in 3:
		var p := Player.new()
		p.armors = [Game.RED, Game.BLUE]
		p.armor_idx = 0
		add_child(p)                      # position 必须在 add_child 之后设
		p.position = Vector2(230.0, _ys[i])
		p.world = self
		p.charge = _charges[i]
		# 截帧没有真实按键：停掉 _process，免得移动 / 自动出刃
		p.set_process(false)
		_players.append(p)
		for k in 3:
			var e := Enemy.new()
			e.world = self
			add_child(e)
			e.setup(Game.BLUE, "hover", _ys[i], 1.0)
			e.position = Vector2(620.0 + float(k) * 250.0, _ys[i])

	# HUD-A：穿着电浆剑甲，能量 80
	_hud_a = HUD.new()
	add_child(_hud_a)
	_hud_a.bind(_players[0], 1)

	# HUD-B：换上引力束甲并过热 —— 三条同时在场，专门核排布
	var py := Player.new()
	add_child(py)
	py.position = Vector2(-500.0, -500.0)   # 只给 HUD 读数用的壳，不参与画面
	py.armors = [Game.YELLOW, Game.RED]
	py.armor_idx = 0
	py.heat = 60.0
	py.charge = 80
	py.set_process(false)
	_hud_b = HUD.new()
	add_child(_hud_b)
	_hud_b.bind(py, 1)
	_hud_b.visible = false


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _shot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE_SAVED " + path)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1280.0, 720.0), Color(0.05, 0.06, 0.12))
	DrawUtil.txt(self, "电浆剑甲 · 贯穿激光（上=刚打出 / 中=收束中 / 下=衰减尾段，寿命 0.55 秒）",
		Vector2(24.0, 40.0), 20, Color(1.0, 0.93, 0.42))
	for i in 3:
		DrawUtil.txt(self, "能量 %d" % _charges[i], Vector2(24.0, _ys[i] - 40.0), 15,
			Color(1.0, 0.93, 0.42))
