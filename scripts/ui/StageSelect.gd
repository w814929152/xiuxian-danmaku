class_name StageSelect
extends Node2D
## 关卡选择：五关卡片（锈带 / 霜环 / 耀斑 / 引力井 / 王座）
##
## 版式与锁态照 `design/art/01-五关视觉差异化规格.md` §I（v3 生效版）：
##   卡宽 216 / 中心间距 232 / 高 396 / 顶边 y176；总跨度 1144，左右各留 68。
##
## §I.1 v5 修订（主理人裁定）：卡面**唯一一处位图** —— 顶部 Boss 主视觉插图
##   （184×104，`assets/sprites/boss_card_l{1..5}.png`）。其余全部维持矢量绘制。
##   插图挤进卡面靠「下方元素整体下移 56px」腾位，不改卡宽 / 卡高 / 间距。
##   锁态换去色版（`_lock` 后缀），与「去色即锁」同一条规则（§I.3）。
##
## 锁态**不用「整卡 alpha 0.35」** —— 深底上那样会让 5 张卡不再读成一排、
## 关键文字对比掉到 1.5:1。改用「去色 + 斜封条 + 锁形 + 占位行」四件套，
## 锁态有**形状（斜封条 + 锁形）+ 文字（未解锁 / 通关第 N-1 关开启）**两条冗余通道，
## 不依赖颜色传达（可访问性自检 §I.3）。
##
## 界面之间互不认识：只发 start_pressed / back_pressed，由 Main 决定去哪。

signal start_pressed(stage: int)
signal back_pressed()

const CARD_N := 5
const CARD_W := 216.0
const CARD_H := 396.0
const CARD_GAP := 232.0
const CARD_TOP := 176.0

# ---------------- 卡面 Boss 插图（§I.1 v5）----------------
## 画在色带下方 4px，宽占满卡面内容区（x0+16 → x0+200）
const ART_W := 184.0
const ART_H := 104.0
const ART_TOP := 14.0
## 关号徽章 / 锁形挪到插图左上角（原居中 y210 → 插图内，仍读「第几关」）
const BADGE_OFF := Vector2(38.0, 36.0)
## 解锁态 / 锁态两套图：后者是同图的灰度去色版（去色即锁）
const BOSS_TEX: Array[Texture2D] = [
	preload("res://assets/sprites/boss_card_l1.png"),
	preload("res://assets/sprites/boss_card_l2.png"),
	preload("res://assets/sprites/boss_card_l3.png"),
	preload("res://assets/sprites/boss_card_l4.png"),
	preload("res://assets/sprites/boss_card_l5.png"),
]
const BOSS_TEX_LOCK: Array[Texture2D] = [
	preload("res://assets/sprites/boss_card_l1_lock.png"),
	preload("res://assets/sprites/boss_card_l2_lock.png"),
	preload("res://assets/sprites/boss_card_l3_lock.png"),
	preload("res://assets/sprites/boss_card_l4_lock.png"),
	preload("res://assets/sprites/boss_card_l5_lock.png"),
]

# ---------------- 卡面配色 ----------------
## 五张卡的强调色（§I.2）：刻意避开 COLOR_MAIN 的四值 ——
## 四色是玩法判据，UI 强调色若用同一组值，玩家会在择关界面建立「这个色 = 属性」的错误映射。
## 这五个值同色相但偏移过，保留「冷 → 暖」的温度递进（= 难度递进），对红绿色盲同样可读。
const ACCENT := [
	Color(0.78, 0.85, 1.00),   # L1 锈带星域 · 淡蓝白
	Color(0.35, 0.78, 1.00),   # L2 霜环星域 · 青蓝
	Color(0.98, 0.72, 0.26),   # L3 耀斑星域 · 琥珀金
	Color(1.00, 0.52, 0.20),   # L4 引力井星域 · 橙
	Color(1.00, 0.30, 0.26),   # L5 王座星域 · 赤
]
const CARD_BG := Color(0.08, 0.09, 0.16, 0.92)
const CARD_LINE := Color(0.35, 0.40, 0.60, 0.50)

# ---------------- 锁态配色（§I.3，全部中性灰 —— 去色即锁）----------------
const LOCK_ACCENT := Color(0.52, 0.55, 0.66)
const LOCK_NAME := Color(0.62, 0.66, 0.78)
const LOCK_VAL := Color(0.60, 0.64, 0.76)
const LOCK_PLACE := Color(0.45, 0.48, 0.60)
const LOCK_BAND := Color(0.10, 0.10, 0.14, 0.55)
const LOCK_METAL := Color(0.72, 0.76, 0.88)
const LOCK_WORD := Color(0.78, 0.82, 0.95)

# ---------------- 斜封条几何（相对卡左上角）----------------
const BAND_W := 16.0
const BAND_A := Vector2(8.0, 388.0)     # 左下
const BAND_B := Vector2(208.0, 8.0)     # 右上

## 本关是否放行过独有怪横幅（Level 侧用）
var _sel := 0
var _t := 0.0
var _hover := -1


func _ready() -> void:
	# 数字键 5 -> pick_4：Game.ACTION_KEYS 只到 pick_3，这里补齐（不改动 Game.gd）
	_ensure_key("pick_4", [KEY_5, KEY_KP_5])
	var bg := Background.new()
	bg.scroll_speed = 24.0
	add_child(bg)
	# 默认停在当前关卡；当前关没解锁就停在已解锁的最后一关
	_sel = clampi(Game.current_stage, 1, StageCfg.STAGE_N) - 1
	if not Game.is_unlocked(_sel + 1):
		_sel = clampi(Game.unlocked, 1, StageCfg.STAGE_N) - 1


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
	_hover = _card_at(get_viewport().get_mouse_position())
	if _hover >= 0:
		_sel = _hover
	queue_redraw()


func _card_rect(i: int) -> Rect2:
	var x := Game.VIEW_W * 0.5 + (float(i) - (float(CARD_N) - 1.0) * 0.5) \
		* CARD_GAP - CARD_W * 0.5
	return Rect2(x, CARD_TOP, CARD_W, CARD_H)


func _card_at(p: Vector2) -> int:
	for i in CARD_N:
		if _card_rect(i).has_point(p):
			return i
	return -1


func _goto(i: int) -> void:
	_sel = clampi(i, 0, CARD_N - 1)


func _accent(i: int) -> Color:
	var c: Color = ACCENT[clampi(i, 0, ACCENT.size() - 1)]
	if not Game.is_unlocked(i + 1):
		return LOCK_ACCENT      # 去色（主）：锁卡一律中性灰，选中框也不例外
	return c


func _confirm() -> void:
	var s := _sel + 1
	if not Game.is_unlocked(s):
		Fx.pop(self, Vector2(Game.VIEW_W * 0.5, 620.0),
			"未 解 锁 · 通关第 %d 关开启" % (s - 1), Color(1.0, 0.62, 0.55), 20, 1.0)
		return                  # 拒绝并弹字，**不 emit**
	Fx.ring(self, _card_rect(_sel).get_center(), _accent(_sel), 20.0, 240.0, 0.40, 7.0)
	start_pressed.emit(s)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mv_left"):
		_goto((_sel + CARD_N - 1) % CARD_N)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mv_right"):
		_goto((_sel + 1) % CARD_N)
		get_viewport().set_input_as_handled()
		return
	for i in CARD_N:
		if event.is_action_pressed("pick_%d" % i):
			_goto(i)
			_confirm()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("confirm") or event.is_action_pressed("shoot"):
		_confirm()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cancel"):
		back_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i := _card_at(mb.position)
			if i >= 0:
				_goto(i)
				_confirm()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 参数行
## 五关参数行：标签 / 数值（全部从 StageCfg 读，不自拟）
static func _labels() -> Array[String]:
	var out: Array[String] = []
	out.append("首领生命")
	out.append("阶段")
	out.append("属性护罩")
	out.append("弹幕密度")
	out.append("计分倍率")
	return out


func _values(s: int) -> Array[String]:
	var out: Array[String] = []
	out.append(str(StageCfg.boss_hp(s)))
	out.append(_phase_cn(StageCfg.boss_phases(s)))
	out.append(_ward_cn(s))
	out.append("%d%%" % int(roundf(StageCfg.bullet_scale(s) * 100.0)))
	out.append("×%.2f" % StageCfg.score_multiplier(s))
	return out


static func _phase_cn(p: int) -> String:
	match p:
		2:
			return "两阶段"
		3:
			return "三阶段"
		4:
			return "四阶段"
		_:
			return "%d 阶段" % p


## 属性护罩一行：无 / 全程 / 暴露期 / 常驻减伤（L3 无护罩但有常驻减伤）
static func _ward_cn(s: int) -> String:
	match StageCfg.ward_mode(s):
		StageCfg.WardMode.ALWAYS:
			return "全程轮转"
		StageCfg.WardMode.EXPOSED:
			return "暴露期"
		_:
			if StageCfg.resident_resist(s) > 0.0:
				return "常驻减伤 %d%%" % int(roundf(StageCfg.resident_resist(s) * 100.0))
			return "无"


## 独有怪名（去掉「· 机型」后缀，卡面只有 184px 可用宽）
static func _bare_cn(k: int) -> String:
	var parts := EnemyKind.cn(k).split(" · ")
	return str(parts[0])


func _uniq_cn(s: int) -> String:
	var names: Array[String] = []
	for k in StageCfg.unique_kinds(s):
		names.append(_bare_cn(k))
	if names.is_empty():
		return "独有 · 通用星盗"
	return "独有 · " + " / ".join(names)


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	var W := Game.VIEW_W
	var H := Game.VIEW_H

	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.02, 0.06, 0.44))

	DrawUtil.txt(self, "择 关", Vector2(W * 0.5, 100.0), 46,
		Color(1.0, 0.94, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	DrawUtil.txt(self, "五关星域 · 通关一关即解锁下一关",
		Vector2(W * 0.5, 140.0), 18, Color(0.86, 0.90, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER)

	for i in CARD_N:
		_draw_card(i)

	DrawUtil.txt(self, "← →  或  1 / 2 / 3 / 4 / 5  选择      Enter 出征      ESC 返回",
		Vector2(W * 0.5, H - 34.0), 17, Color(0.68, 0.74, 0.92),
		HORIZONTAL_ALIGNMENT_CENTER)


func _draw_card(i: int) -> void:
	var s := i + 1
	var un := Game.is_unlocked(s)
	var act: bool = (i == _sel)
	var ac := _accent(i)
	var r := _card_rect(i)
	var bob := sin(_t * 2.6 + float(i)) * 4.0 if act else 0.0
	var rr := Rect2(r.position.x, r.position.y + bob, r.size.x, r.size.y)
	var x0 := rr.position.x
	var cx := rr.position.x + rr.size.x * 0.5

	# 卡底 / 卡框（锁态也保持 α1.0 —— 去色不降不透明度，否则 5 张卡读不成一排）
	draw_rect(rr, CARD_BG)
	if act:
		draw_rect(Rect2(rr.position.x - 6.0, rr.position.y - 6.0,
			rr.size.x + 12.0, rr.size.y + 12.0), Color(ac.r, ac.g, ac.b, 0.28))
	draw_rect(rr, Color(ac.r, ac.g, ac.b, 0.95 if act else 0.40),
		false, 3.0 if act else 1.8)
	# 顶部色带
	draw_rect(Rect2(x0, rr.position.y, rr.size.x, 10.0), ac)

	# Boss 主视觉插图（锁态自动换去色版 —— 形状 / 文字之外再补一条去色通道）
	draw_texture_rect(BOSS_TEX[i] if un else BOSS_TEX_LOCK[i],
		Rect2(x0 + 16.0, rr.position.y + ART_TOP, ART_W, ART_H), false)

	# 关号徽章 / 锁形（纯几何、零素材）—— 叠在插图左上角
	var bp := rr.position + BADGE_OFF
	if un:
		draw_circle(bp, 22.0, Color(ac.r, ac.g, ac.b, 0.22))
		DrawUtil.txt(self, str(s), bp + Vector2(0.0, 8.0), 24,
			Color(1.0, 1.0, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_lock(bp)

	# 关卡名 / 副标题
	DrawUtil.txt(self, StageCfg.name_of(s), Vector2(cx, 308.0), 20,
		Color(0.95, 0.96, 1.00) if un else LOCK_NAME, HORIZONTAL_ALIGNMENT_CENTER)
	var sub: String = StageCfg.sub_of(s) if un else "通关第 %d 关开启" % (s - 1)
	DrawUtil.txt(self, sub, Vector2(cx, 330.0), 12,
		Color(0.68, 0.73, 0.90) if un else Color(0.62, 0.66, 0.78),
		HORIZONTAL_ALIGNMENT_CENTER)

	draw_rect(Rect2(x0 + 16.0, 346.0, rr.size.x - 32.0, 1.0), CARD_LINE)

	# 最高分 + 完成度（品阶已改为每关独立完成度，故必须就地自解释）
	var best := Game.stage_highscore(s)
	if un:
		var hs: String = "最高 %s" % (str(best) if best > 0 else "—")
		DrawUtil.txt(self, hs, Vector2(x0 + 16.0, 368.0), 13,
			Color(0.98, 0.88, 0.55) if best > 0 else Color(0.58, 0.62, 0.75))
		var pc: String = "完成度 %d%%" % int(roundf(Game.completion_of(best, s) * 100.0)) \
			if best > 0 else "完成度 —"
		DrawUtil.txt(self, pc, Vector2(x0 + rr.size.x - 16.0, 368.0), 12,
			Color(0.80, 0.85, 1.00), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		DrawUtil.txt(self, "最高 — — —", Vector2(x0 + 16.0, 368.0), 13, LOCK_PLACE)

	# 独有怪 / 首领
	if un:
		DrawUtil.txt(self, _uniq_cn(s), Vector2(x0 + 16.0, 390.0), 13,
			Color(0.80, 0.85, 1.00))
	else:
		DrawUtil.txt(self, "独有 — — —", Vector2(x0 + 16.0, 390.0), 13, LOCK_PLACE)
	DrawUtil.txt(self, "首领 · %s" % StageCfg.boss_full_name(s),
		Vector2(x0 + 16.0, 412.0), 13, ac)

	draw_rect(Rect2(x0 + 16.0, 428.0, rr.size.x - 32.0, 1.0), CARD_LINE)

	# 5 行参数（标签左 / 数值右）—— 锁态不隐藏，改占位行，保证 5 张卡等高、版式一致
	var labels := _labels()
	var vals := _values(s)
	for j in labels.size():
		var y := 448.0 + float(j) * 22.0
		DrawUtil.txt(self, str(labels[j]), Vector2(x0 + 16.0, y), 12,
			Color(0.62, 0.67, 0.82) if un else LOCK_VAL)
		var v: String = str(vals[j]) if un else "— — —"
		DrawUtil.txt(self, v, Vector2(x0 + rr.size.x - 16.0, y), 12,
			Color(0.88, 0.91, 1.00) if un else LOCK_PLACE,
			HORIZONTAL_ALIGNMENT_RIGHT)

	DrawUtil.txt(self, "按 %d 键" % s, Vector2(cx, 552.0), 12,
		ac if act else Color(0.55, 0.60, 0.75), HORIZONTAL_ALIGNMENT_CENTER)

	# 斜封条画在最上层（锁态主视觉：形状 + 文字）
	if not un:
		_draw_band(x0, rr.position.y)


## 锁形标识：锁体 14×11 + 锁梁半圆 r5 + 锁孔（纯几何、零素材）
func _draw_lock(c: Vector2) -> void:
	draw_arc(Vector2(c.x, c.y - 5.0), 5.0, PI, TAU, 16, LOCK_METAL, 2.0, true)
	draw_rect(Rect2(c.x - 7.0, c.y - 5.0, 14.0, 11.0), LOCK_METAL)
	draw_circle(Vector2(c.x, c.y + 0.5), 1.8, Color(0.10, 0.10, 0.14))


## 斜封条：卡面对角 16px 宽斜带（左下 -> 右上），带上居中写「未 解 锁」
func _draw_band(x: float, y: float) -> void:
	var a := Vector2(x + BAND_A.x, y + BAND_A.y)
	var b := Vector2(x + BAND_B.x, y + BAND_B.y)
	var d := (b - a).normalized()
	var p := Vector2(-d.y, d.x) * (BAND_W * 0.5)
	var quad := PackedVector2Array([a + p, b + p, b - p, a - p])
	draw_colored_polygon(quad, LOCK_BAND)
	DrawUtil.txt(self, "未 解 锁", (a + b) * 0.5 + Vector2(0.0, 4.0), 11,
		LOCK_WORD, HORIZONTAL_ALIGNMENT_CENTER)
