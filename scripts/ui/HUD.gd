class_name HUD
extends Node2D
## 战斗界面：血条 / 护盾 / 双战甲槽 / Boss 血条与护罩提示 / 始祖狂暴的血色屏幕

## 玩家按下暂停键：HUD 只上报，由 Level 决定是否真正暂停
signal pause_toggled(paused: bool)
## 玩家请求重来本关
signal restart_requested()

# ---------------------------------------------------------------- 狂暴血光
## 屏幕四周的血色：越靠边越浓。用「多层矩形」而不是一次渐变 ——
## CanvasItem 没有渐变填充 API，多层叠加是唯一不依赖顶点色插值的做法。
## 层数 × 每层厚度 = 覆盖深度（20 × 9 = 180px）
const RAGE_LAYERS := 20
const RAGE_STEP := 9.0
## 最外层的峰值不透明度 / 呼吸幅度 / 心跳尖峰的额外加成
const RAGE_PEAK := 0.42
const RAGE_BREATH := 0.35
const RAGE_BEAT := 0.30
const RAGE_BEAT_T := 1.8      # 心跳周期（秒）
const RAGE_BEAT_W := 0.20     # 尖峰宽度（秒）
## 进入狂暴那一下的强闪：持续时长与额外加成
const RAGE_FLASH_T := 0.75
const RAGE_FLASH := 0.40
const RAGE_COL := Color(1.0, 0.12, 0.09)

## HUD 不反向依赖 Level —— 只持有被绑定的实体与少量展示数据，
## 实体死亡后引用失效，统一靠 is_instance_valid 判断。
var player: Player = null
var boss: Boss = null
var score: int = 0
var wave_text: String = "出 击"
var paused := false
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var banner_dur := 0.0
var _t := 0.0
## 狂暴强闪的剩余秒数（> 0 表示刚进狂暴）
var _rage_flash := 0.0
## 上一帧的狂暴状态 —— 用来在 HUD 侧检测「刚刚狂暴」这个边沿，
## 不必为此给 Boss 加信号、也不必让 Level 转发。
var _was_enraged := false


func _ready() -> void:
	z_index = 100          # 永远绘制在最上层


func bind(p: Player) -> void:
	player = p


func bind_boss(b: Boss) -> void:
	boss = b


func set_score(v: int) -> void:
	score = v


func set_wave(s: String) -> void:
	wave_text = s


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		paused = not paused
		pause_toggled.emit(paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		paused = false
		restart_requested.emit()
		get_viewport().set_input_as_handled()


func show_banner(t: String, sub: String, dur: float = 2.2) -> void:
	banner = t
	banner_sub = sub
	banner_dur = dur
	banner_t = dur


func _process(delta: float) -> void:
	_t += delta
	if banner_t > 0.0:
		banner_t -= delta
	if _rage_flash > 0.0:
		_rage_flash = maxf(0.0, _rage_flash - delta)
	_rage_edge()
	queue_redraw()


## 狂暴边沿检测：只在 HUD 做一次，Boss 与 Level 都无需为此改动
func _rage_edge() -> void:
	var on := false
	if boss != null and is_instance_valid(boss):
		on = boss.enraged
	if on and not _was_enraged:
		_rage_flash = RAGE_FLASH_T
	_was_enraged = on


## 始祖狂暴 —— 屏幕四周泛起血色。三条节奏叠在一起：
##   1. **呼吸**（RAGE_BREATH）：缓慢起伏，让血光「活着」而不是一层死贴纸；
##   2. **心跳**（RAGE_BEAT）：每 RAGE_BEAT_T 秒一次尖峰衰减，这才是「闪」；
##   3. **强闪**（_rage_flash）：刚跌破三成那一下的爆闪 ——
##      狂暴是局面转折点，玩家需要一帧就能读到的信号，不能只靠横幅。
## 只在 boss.enraged 时才画，普通战斗一帧指令都不多花。
func _rage_vignette() -> void:
	var flash := _rage_flash / RAGE_FLASH_T                     # 1 -> 0
	var breath := 0.5 + 0.5 * sin(_t * 2.0)
	var phase := fmod(_t, RAGE_BEAT_T)
	var beat := 0.0
	if phase < RAGE_BEAT_W:
		var u := 1.0 - phase / RAGE_BEAT_W
		beat = u * u
	var peak := RAGE_PEAK * (1.0 - RAGE_BREATH + RAGE_BREATH * breath + RAGE_BEAT * beat) \
		+ RAGE_FLASH * flash
	peak = minf(peak, 0.92)
	# 爆闪那一瞬间连画面中心也带上一点血色，冲击感才够
	if flash > 0.0:
		draw_rect(Rect2(0.0, 0.0, Game.VIEW_W, Game.VIEW_H),
			Color(RAGE_COL.r, RAGE_COL.g, RAGE_COL.b, 0.10 * flash))
	for i in RAGE_LAYERS:
		# 外层 f = 1 最浓，向内按平方衰减
		var f := float(RAGE_LAYERS - i) / float(RAGE_LAYERS)
		var a := peak * f * f
		if a <= 0.004:
			continue
		var d := float(i) * RAGE_STEP
		var c := Color(RAGE_COL.r, RAGE_COL.g, RAGE_COL.b, a)
		var w := Game.VIEW_W
		var h := Game.VIEW_H
		draw_rect(Rect2(0.0, d, w, RAGE_STEP), c)
		draw_rect(Rect2(0.0, h - d - RAGE_STEP, w, RAGE_STEP), c)
		draw_rect(Rect2(d, d, RAGE_STEP, h - d * 2.0), c)
		draw_rect(Rect2(w - d - RAGE_STEP, d, RAGE_STEP, h - d * 2.0), c)


func _bar(x: float, y: float, w: float, h: float, ratio: float, col: Color,
		bg := Color(0.04, 0.04, 0.08, 0.62),
		border := Color(0.62, 0.68, 0.92, 0.35)) -> void:
	draw_rect(Rect2(x - 2.0, y - 2.0, w + 4.0, h + 4.0), Color(0.02, 0.02, 0.05, 0.45))
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x + 2.0, y + 2.0, maxf(0.0, w - 4.0) * clampf(ratio, 0.0, 1.0), h - 4.0), col)
	draw_rect(Rect2(x, y, w, h), border, false, 1.5)


## 生效中的增益，横排一行小牌（左上角，血条下方）
func _buff_row(p: Player) -> void:
	var chips: Array[String] = []
	var cols: Array[Color] = []
	# COL 是未类型化的 const Array，下标取值必须显式写明类型才能推断
	if p.multi > 0:
		var cm: Color = Pickup.COL[Pickup.T.MULTI]
		chips.append("弹道 ×%d" % p.rows())
		cols.append(cm)
	if p.atk_up > 0:
		var ca: Color = Pickup.COL[Pickup.T.ATK]
		chips.append("攻击 +%d%%" % int(roundf((p.atk_mul - 1.0) * 100.0)))
		cols.append(ca)
	if p.invincible:
		var ci: Color = Pickup.COL[Pickup.T.INVINC]
		chips.append("力场 %.1fs" % p.invinc)
		cols.append(ci)
	var cx := 26.0
	for i in chips.size():
		var s: String = chips[i]
		var col: Color = cols[i]
		var w := DrawUtil.tw(s, 14) + 22.0
		draw_rect(Rect2(cx, 106.0, w, 24.0), Color(col.r, col.g, col.b, 0.20))
		draw_rect(Rect2(cx, 106.0, w, 24.0), Color(col.r, col.g, col.b, 0.85), false, 1.2)
		DrawUtil.txt(self, s, Vector2(cx + 11.0, 123.0), 14, col)
		cx += w + 8.0


func _draw() -> void:
	var p: Player = player

	# ---------------- 玩家 ----------------
	if p != null and is_instance_valid(p):
		var hp_r := float(p.hp) / float(Player.MAX_HP)
		var hpc := Color(1.0, 0.32, 0.36)
		if hp_r < 0.3:
			hpc = Color(1.0, 0.18, 0.22)
		_bar(26.0, 24.0, 320.0, 20.0, hp_r, hpc)
		DrawUtil.txt(self, "生命 %d / %d" % [p.hp, Player.MAX_HP],
			Vector2(36.0, 40.0), 15, Color(0.94, 0.95, 1.0))

		# 护盾
		var sk := float(p.shield) / float(Player.SHIELD_MAX)
		var skc := Color(0.93, 0.96, 1.0, 0.95) if p.color == Game.WHITE \
			else Color(0.55, 0.60, 0.72, 0.38)
		_bar(26.0, 52.0, 320.0, 12.0, sk, skc)
		DrawUtil.txt(self, "护盾 %d" % p.shield, Vector2(354.0, 63.0), 14,
			Color(0.80, 0.86, 1.0) if p.color == Game.WHITE else Color(0.5, 0.55, 0.66))
		if p.color != Game.WHITE:
			DrawUtil.txt(self, "（仅光子护盾状态下生效）", Vector2(408.0, 63.0), 13,
				Color(0.48, 0.52, 0.62))

		# 无伤读条
		if p.shield < Player.SHIELD_MAX:
			var rt := clampf(p.no_hit_ratio(), 0.0, 1.0)
			_bar(26.0, 70.0, 320.0, 5.0, rt, Color(0.5, 0.85, 1.0, 0.75))
			DrawUtil.txt(self, "十息回盾 %.0f%%" % (rt * 100.0), Vector2(354.0, 78.0), 12,
				Color(0.55, 0.8, 0.95))

		# 引力束过热（引力束甲专属：满值即停手散热）
		if p.color == Game.YELLOW or p.heat > 0.0:
			var hr := clampf(p.heat / Player.HEAT_MAX, 0.0, 1.0)
			var hc := Color(1.0, 0.35, 0.20) if p.overheated \
				else Color(1.0, 0.80, 0.22)
			_bar(26.0, 84.0, 320.0, 10.0, hr, hc)
			var hs: String = "束甲过热 · 停手散热" if p.overheated \
				else "引力束过热 %d%%" % int(hr * 100.0)
			DrawUtil.txt(self, hs, Vector2(354.0, 94.0), 13, hc)

		# 道具增益（修复包是即时效果，不占常驻槽位）
		_buff_row(p)

		# 双战甲槽
		var bx := 26.0
		var by := Game.VIEW_H - 96.0
		for i in p.armors.size():
			var c: int = p.armors[i]
			var act: bool = (i == p.armor_idx)
			var w: float = 132.0 if act else 112.0
			var h: float = 58.0 if act else 48.0
			var ox: float = bx + (i * 146.0)
			var oy: float = by - (10.0 if act else 0.0)
			var m: Color = Game.COLOR_MAIN[c]
			if act:
				draw_rect(Rect2(ox - 4.0, oy - 4.0, w + 8.0, h + 8.0),
					Color(m.r, m.g, m.b, 0.35))
			draw_rect(Rect2(ox, oy, w, h), Color(0.05, 0.05, 0.10, 0.72))
			draw_rect(Rect2(ox, oy, w, h), Color(m.r, m.g, m.b, 0.95 if act else 0.4),
				false, 2.0 if act else 1.2)
			draw_rect(Rect2(ox + 6.0, oy + 8.0, 12.0, h - 16.0), m)
			DrawUtil.txt(self, Game.ARMOR_TITLE[c], Vector2(ox + 26.0, oy + 24.0),
				16 if act else 14, Color(1, 1, 1) if act else Color(0.72, 0.75, 0.85))
			DrawUtil.txt(self, Game.ARMOR_TAG[c], Vector2(ox + 26.0, oy + 43.0),
				13 if act else 12, Color(m.r, m.g, m.b, 1.0 if act else 0.6))
			if act:
				DrawUtil.txt(self, "当前", Vector2(ox + w - 8.0, oy + 20.0), 13,
					Color(1.0, 0.92, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
		DrawUtil.txt(self, "【空格】更换战甲  ·  免疫同色弹幕",
			Vector2(26.0, Game.VIEW_H - 26.0), 14, Color(0.72, 0.78, 0.95))

	# ---------------- 分数 ----------------
	DrawUtil.txt(self, "星币  %d" % score, Vector2(Game.VIEW_W - 26.0, 34.0), 20,
		Color(1.0, 0.92, 0.62), HORIZONTAL_ALIGNMENT_RIGHT)
	DrawUtil.txt(self, wave_text, Vector2(Game.VIEW_W - 26.0, 58.0), 15,
		Color(0.78, 0.84, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	DrawUtil.txt(self, "难度 · %s" % Game.diff_name(), Vector2(Game.VIEW_W - 26.0, 80.0),
		14, Color(0.70, 0.76, 0.94), HORIZONTAL_ALIGNMENT_RIGHT)

	# ---------------- Boss ----------------
	if boss != null and is_instance_valid(boss):
		var W := 620.0
		var X := (Game.VIEW_W - W) * 0.5
		var r := float(boss.hp) / float(boss.max_hp)
		_bar(X, 26.0, W, 18.0, r, Color(0.95, 0.28, 0.30))
		# 阶段分隔（两重一条线，三重两条）
		for f in boss.phase_marks():
			draw_rect(Rect2(X + W * f, 24.0, 2.0, 22.0), Color(0.05, 0.05, 0.08, 0.9))
		var bt := "星盗始祖  ·  第 %d 阶段" % boss.phase
		if boss.enraged:
			bt += "  ·  狂 暴"
		DrawUtil.txt(self, bt, Vector2(Game.VIEW_W * 0.5, 22.0), 16,
			Color(1.0, 0.62, 0.55) if boss.enraged else Color(1.0, 0.88, 0.88),
			HORIZONTAL_ALIGNMENT_CENTER)

		# 护罩提示
		var wy := 68.0
		if boss.ward >= 0:
			var m: Color = Game.COLOR_MAIN[boss.ward]
			var s := "护罩 · %s  →  换上【%s】破之" % [
				Game.COLOR_CN[boss.ward], Game.ARMOR_TITLE[boss.ward]
			]
			var w := DrawUtil.tw(s, 17) + 40.0
			draw_rect(Rect2(Game.VIEW_W * 0.5 - w * 0.5, wy - 16.0, w, 28.0),
				Color(m.r, m.g, m.b, 0.28))
			draw_rect(Rect2(Game.VIEW_W * 0.5 - w * 0.5, wy - 16.0, w, 28.0),
				Color(m.r, m.g, m.b, 0.95), false, 1.5)
			DrawUtil.txt(self, s, Vector2(Game.VIEW_W * 0.5, wy + 4.0), 17,
				Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
		else:
			DrawUtil.txt(self, "护罩未启  ·  全力输出",
				Vector2(Game.VIEW_W * 0.5, wy + 4.0), 15,
				Color(0.62, 0.68, 0.82), HORIZONTAL_ALIGNMENT_CENTER)

	# ---------------- 始祖狂暴：屏幕四周血光 ----------------
	# 画在横幅之下：横幅的文字仍压在血光之上，读得清
	if boss != null and is_instance_valid(boss) and boss.enraged:
		_rage_vignette()

	# ---------------- 横幅 ----------------
	if banner_t > 0.0 and banner_dur > 0.0:
		var k := banner_t / banner_dur
		var a := clampf(minf(k * 3.0, (1.0 - k) * 6.0 + 0.35), 0.0, 1.0)
		var cy := Game.VIEW_H * 0.34
		draw_rect(Rect2(0.0, cy - 52.0, Game.VIEW_W, 104.0), Color(0.02, 0.02, 0.06, 0.42 * a))
		DrawUtil.txt(self, banner, Vector2(Game.VIEW_W * 0.5, cy), 42,
			Color(1.0, 0.95, 0.80, a), HORIZONTAL_ALIGNMENT_CENTER)
		if banner_sub != "":
			DrawUtil.txt(self, banner_sub, Vector2(Game.VIEW_W * 0.5, cy + 34.0), 17,
				Color(0.86, 0.90, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER)

	# ---------------- 暂停 ----------------
	if paused:
		draw_rect(Rect2(0.0, 0.0, Game.VIEW_W, Game.VIEW_H), Color(0.02, 0.02, 0.05, 0.62))
		DrawUtil.txt(self, "暂 停", Vector2(Game.VIEW_W * 0.5, Game.VIEW_H * 0.45), 46,
			Color(1.0, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
		DrawUtil.txt(self, "P / ESC 继续 · R 重来本关",
			Vector2(Game.VIEW_W * 0.5, Game.VIEW_H * 0.45 + 44.0), 18,
			Color(0.85, 0.89, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
