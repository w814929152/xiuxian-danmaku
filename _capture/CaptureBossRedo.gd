extends Node2D
## 五关旗舰「玩家同语汇简化重做」验收截帧（真窗口运行，**不可 --headless**）：
##   上排 L1~L5 常态（相位Ⅱ / 合法护罩色 / _t 定格 0），下排对照：
##   玩家机（白甲）+ 狂暴 L1 + 换色预告 L1 + 狂暴 L5。
## 产物：D:/demo/_boss_redo.png

const OUT := "D:/demo/_boss_redo.png"
## 上排五台：x 均布；scale 让五关体量观感接近（R_MAIN 56→84）
const POS_X := [150.0, 430.0, 670.0, 910.0, 1150.0]
const ROW_Y := 250.0
const SC := [1.5, 1.35, 1.2, 1.05, 0.95]
const R_MAIN := [56.0, 63.0, 70.0, 77.0, 84.0]
const PH := 2
## 护罩色（-1 = 本态不展罩）；须 ∈ 玩家战甲 [RED, WHITE] —— 可行性铁律
const WARD := [0, -1, -1, -1, 2]

var _heroes: Array[Boss] = []
var _samples: Array[Boss] = []


func _ready() -> void:
	Game.picked_armors = [Game.WHITE, Game.RED]
	_bg()
	for i in 5:
		var st := i + 1
		var pos := Vector2(POS_X[i], ROW_Y)
		var b := _make_boss(pos, SC[i], st, PH, WARD[i], false)
		_lbl("L%d" % st, Vector2(POS_X[i], 428.0), 18,
			Color(0.85, 0.89, 0.98))
	# 下排对照样例
	var p := _make_player(Vector2(130.0, 575.0), Game.WHITE)
	p.scale = Vector2(1.6, 1.6)
	p.name = "PlayerRef"
	_samples.append(_make_boss(Vector2(400.0, 575.0), 1.0, 1, 1, 0, true))
	_samples.append(_make_boss(Vector2(630.0, 575.0), 1.0, 1, 1, 0, false))
	_samples[1]._ward_t = 0.9       # 换色预告：环虚线化 ×2.2 加速
	_samples.append(_make_boss(Vector2(950.0, 575.0), 1.0, 5, 4, 2, true))
	_lbl("玩家（白甲）", Vector2(85.0, 695.0), 14, Color(0.62, 0.68, 0.82))
	_lbl("L1 狂暴", Vector2(355.0, 695.0), 14, Color(0.62, 0.68, 0.82))
	_lbl("L1 换色预告", Vector2(585.0, 695.0), 14, Color(0.62, 0.68, 0.82))
	_lbl("L5 狂暴", Vector2(905.0, 695.0), 14, Color(0.62, 0.68, 0.82))
	_lbl("五关旗舰 · 玩家同语汇简化重做（BossArt 2026-10）· −X 头 / +X 尾 · 相位Ⅱ",
		Vector2(40, 18), 20, Color(0.95, 0.97, 1.0))
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("CAPTURE_SAVED ", OUT)
	get_tree().quit()


func _process(_delta: float) -> void:
	# 全部定格：_t 归零 → 环缺口 / 能量纹与标注一致
	for b in _heroes:
		if is_instance_valid(b):
			b._t = 0.0
	for b in _samples:
		if is_instance_valid(b):
			b._t = 1.0 if b.get("enraged") == false else 0.35
	queue_redraw()


func _make_boss(pos: Vector2, sc: float, st: int, ph: int, ward_c: int,
		rage: bool) -> Boss:
	var b: Boss = Boss4.new() if st == 4 else Boss.new()
	b.stage = st
	b.phase = ph
	b.player_armors = [Game.RED, Game.WHITE]
	b.world = self
	b._home_x = pos.x
	b._base_y = pos.y
	b.scale = Vector2(sc, sc)
	add_child(b)
	b.position = pos
	b._st = "pose"
	if ward_c >= 0:
		b.ward = ward_c
		b._ward_t = 99.0
	b.enraged = rage
	_heroes.append(b)
	return b


func _make_player(pos: Vector2, armor: int) -> Node2D:
	var p: Node2D = Player.new()
	var arms: Array[int] = [Game.WHITE, Game.RED]
	p.armors = arms
	p.world = self
	add_child(p)
	p.position = pos
	return p


func _bg() -> void:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.05, 0.09)
	r.size = Vector2(Game.VIEW_W, Game.VIEW_H)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.name = "BG"
	add_child(r)


func _lbl(text: String, pos: Vector2, fsize: int, col: Color) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = pos
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", col)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.z_index = 30
	add_child(lb)
