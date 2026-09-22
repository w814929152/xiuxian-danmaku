class_name GameSingleton
extends Node
## ---------------------------------------------------------------
## Game.gd —— 全局单例 (Autoload 名称: Game)
## 负责：三色常量 / 输入映射注册 / 跨场景数据 / 中文字体
##
## Autoload 名为 `Game`（Game.RED / Game.picked_armors ...），类名 `GameSingleton` 供需要类型化的场合引用。
## 职责仅限：三色常量 / 输入映射注册 / 跨场景数据。绘制工具见 DrawUtil。
## ---------------------------------------------------------------

# ================= 画面 =================
const VIEW_W := 1280.0
const VIEW_H := 720.0

# ================= 属性弹（电浆 / 寒霜 / 光子 / 引力）=================
enum C { RED = 0, BLUE = 1, WHITE = 2, YELLOW = 3 }

# 直接可用的颜色常量（避免通过单例访问枚举的兼容问题）
const RED := 0
const BLUE := 1
const WHITE := 2
const YELLOW := 3

# 历史称呼：三色（红/蓝/白）。引力（黄）为后加的第四色。
const COLOR_CN := ["电浆", "寒霜", "光子", "引力"]

# 主色 / 外发光 / 暗部 / 内核高光
const COLOR_MAIN := [
	Color(0.98, 0.24, 0.27),
	Color(0.22, 0.62, 1.00),
	Color(0.93, 0.96, 1.00),
	Color(1.00, 0.80, 0.14),
]
const COLOR_GLOW := [
	Color(1.00, 0.56, 0.24),
	Color(0.45, 0.86, 1.00),
	Color(0.84, 0.92, 1.00),
	Color(1.00, 0.93, 0.42),
]
const COLOR_DARK := [
	Color(0.40, 0.04, 0.09),
	Color(0.03, 0.16, 0.40),
	Color(0.28, 0.32, 0.42),
	Color(0.38, 0.26, 0.02),
]
const COLOR_CORE := [
	Color(1.00, 0.94, 0.80),
	Color(0.90, 0.98, 1.00),
	Color(1.00, 1.00, 1.00),
	Color(1.00, 0.99, 0.82),
]

## 驾驶舱玻璃（舱盖色）：玩家机甲的敌我识别**主通道**（对应旧称 SKIN）。
## 仅玩家（Player._draw / ArmorArt）使用；敌方绘制路径（PirateArt / Boss）
## 严禁出现此色值 —— §2.4 V1 静态校验扫描敌方源码不得命中 (0.62,0.86,0.98)。
const CANOPY := Color(0.62, 0.86, 0.98)

# ================= 战甲资料（旧称「道袍/皮肤」，现统一为战甲）=================
const ARMOR_TITLE := ["电浆剑甲", "寒霜疾甲", "光子盾甲", "引力束甲"]
const ARMOR_DESC := [
	"免疫【电浆】属性弹\n攻击化作 · 双排光刃\n伤害 8 × 2",
	"免疫【寒霜】属性弹\n吸收寒霜弹 -> 闪避 0.5 秒\n身法提速 + 50% · 单排光刃 10",
	"免疫【光子】属性弹\n吸收光子弹 -> 护盾 +10\n护盾上限 20 · 不再自动回复",
	"免疫【引力】属性弹\n攻击化作 · 持续引力束\n过热 100 点即需散热",
]
const ARMOR_TAG := ["双排光刃", "闪避 0.5 秒", "护盾 20", "引力束 · 过热"]
# 战甲库里的详述（一行一段，比卡面文案更细）
const ARMOR_LORE := [
	"电浆剑甲以等离子熔核驱动，装具与电浆弹头共振。\n出刃时剑控自生双影，一次递出两排光刃。\n代价是刃能略散，单发伤害不及常式，胜在覆盖面广。",
	"寒霜疾甲取极寒冷却回路，甲壳常年凝着薄霜。\n着此甲者推进过载，身法提速五成。\n吞下寒霜弹的一瞬，甲壳转入相位化解 ——\n半秒内弹幕穿身而过，不损分毫；一击不中便已远遁。",
	"光子盾甲不染四能，最擅守御。\n开局不带护盾 —— 每吞下一枚光子弹，偏导场便充入十点；\n护盾上限二十点，可替驾驶员硬承伤害。\n它不会自行回复，充能全靠在弹雨里正面接弹。",
	"引力束甲以引力场发生器为核，着之可聚能成束。\n御敌时化作一道绵绵不绝的引力束，只消按住不放。\n然束流过盛则发生器过热 —— 满百即滞，须停手半秒令其自散；\n而引力弹不伤其身，反能引走三十点热量。",
]
const ARMOR_STORE := [
	"电浆 · 攻",
	"寒霜 · 速",
	"光子 · 守",
	"引力 · 术",
]

# ================= 输入 =================
## 全部在运行期注册，无需在 project.godot 里手配 InputMap
const ACTION_KEYS := {
	"mv_up": [KEY_W, KEY_UP],
	"mv_down": [KEY_S, KEY_DOWN],
	"mv_left": [KEY_A, KEY_LEFT],
	"mv_right": [KEY_D, KEY_RIGHT],
	"shoot": [KEY_J, KEY_K],
	"swap": [KEY_SPACE],
	"swap_again": [KEY_T],
	"pick_0": [KEY_1, KEY_KP_1],
	"pick_1": [KEY_2, KEY_KP_2],
	"pick_2": [KEY_3, KEY_KP_3],
	"pick_3": [KEY_4, KEY_KP_4],
	"confirm": [KEY_ENTER, KEY_KP_ENTER],
	"cancel": [KEY_ESCAPE],
	"restart": [KEY_R],
	"pause": [KEY_P],
}

# ================= 跨场景数据 =================
## 玩家在关卡开始前选定的两件战甲（关卡中按空格切换）
var picked_armors: Array[int] = [C.RED, C.WHITE]
var score := 0
var result_win := false
var result_score := 0
var result_hp := 0
## 本局是否刷新了**本关**的最高分（结算界面据此打「新高」标记）
var result_is_new_high := false
## 本局开打之前**本关**的历史最高分（结算界面据此显示「历史最高」）
var result_prev_high := 0

# ================= 本地存档 =================
## 最高分存档路径（user:// 由引擎解析到各平台的用户数据目录）
const HIGHSCORE_PATH := "user://highscores.json"
## 结构：{ "0" / "1" / "2": { "score": int, "robes": Array[int],
##                            "rank": String, "win": bool } }
## 键是难度 int 转 String —— JSON 的对象键只能是字符串。
## 注：rank 为展示串，随文案版本变化，不承担跨版本兼容职责；
##     历史最高只显示分数，从不读回旧 rank 串展示给玩家。
## 【五关改造】本文件退为**只读不写**：旧键 "0"/"1"/"2" 是难度键，
##   绝不能被读成关卡纪录（设计总纲 §J.7 判定为阻塞项）。关卡纪录一律走 progress.json。
var highscores: Dictionary = {}

# ================= 关卡进度存档（五关改造新增）=================
## 新档路径：解锁进度 + 每关最高分
const PROGRESS_PATH := "user://progress.json"
## 旧档备份：首次启动时把 highscores.json 另存一份，玩家侧不会觉得数据被吞掉。
## 不迁移、不删除 —— 旧纪录是「难度最高分」，与新「关卡最高分」语义不可映射。
const LEGACY_PATH := "user://highscores.legacy.json"
## 存档格式版本 —— 版本不对就整体降级，不做半吊子迁移
const PROGRESS_VERSION := 2
## 关卡键：**必须是非纯数字键**。用 "L1".."L5"，避免撞上旧难度键 "0"/"1"/"2"
const KEY_PREFIX := "L"
## 老档继承的解锁上限：旧档只有三档，最多只能推出「打到第 3 关」这个事实
const LEGACY_MAX_UNLOCK := 3

## 已解锁到第几关（1 = 只有第 1 关可打）
var unlocked: int = 1
## 每关最高分：{ "L1": {"score": int, "robes": Array[int], "rank": String} }
## JSON 的对象键只能是字符串，故关卡号走 stage_key()。
## 注：rank 只写不读 —— 展示时用 rank_of_stage() 现算（品阶已改为每关独立完成度）。
var stage_best: Dictionary = {}
## 当前选择的关卡（跨界面数据；关卡选择界面写入，Level 读取）
var current_stage: int = 1

# ================= 生命周期 =================
func _ready() -> void:
	_setup_actions()
	_load_highscores()
	_load_progress()


## 退出前清空对象池：池内节点是无父节点的孤儿，
## 不主动 free 会在退出时被统计成 RID / ObjectDB 泄漏
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Pool.clear()


func _setup_actions() -> void:
	for a in ACTION_KEYS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		for k in ACTION_KEYS[a]:
			var ev := InputEventKey.new()
			ev.keycode = k
			ev.physical_keycode = k
			if not InputMap.action_has_event(a, ev):
				InputMap.action_add_event(a, ev)


# ---------------------------------------------------------------
# 绘制工具已拆到 DrawUtil（纯静态），本单例不再承担绘制职责
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# 最高分持久化
# 存档不是玩法：任何 IO / 解析失败都静默降级成「没有存档」，
# 绝不能因为读不出文件就让游戏起不来或结算崩掉。
# ---------------------------------------------------------------
func _load_highscores() -> void:
	highscores = {}
	if not FileAccess.file_exists(HIGHSCORE_PATH):
		return
	var f := FileAccess.open(HIGHSCORE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	if txt.is_empty():
		return
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		highscores = data


func _write_highscores() -> void:
	var f := FileAccess.open(HIGHSCORE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(highscores))
	f.close()


## 仅在刷新纪录时写盘（否则每次结算都白写一次文件）
func save_highscore(diff: int, sc: int, armors: Array[int], rank: String, win: bool) -> void:
	var key := str(diff)
	if sc <= highscore_for(diff):
		return
	highscores[key] = {
		"score": sc,
		"robes": armors,
		"rank": rank,
		"win": win,
	}
	_write_highscores()


## 该难度的最高分；无存档返回 0
func highscore_for(diff: int) -> int:
	var key := str(diff)
	if not highscores.has(key):
		return 0
	var e: Variant = highscores[key]
	if typeof(e) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = e
	if not d.has("score"):
		return 0
	return int(d["score"])


# ---------------------------------------------------------------
# 关卡进度持久化（五关改造新增）
# 与旧档同一条原则：存档不是玩法，任何 IO / 解析失败都静默降级成
# 「只解锁第 1 关」，绝不能因为读不出文件就让游戏起不来。
# ---------------------------------------------------------------
## 关卡号 -> 存档键（"L1".."L5"）
static func stage_key(s: int) -> String:
	return KEY_PREFIX + str(s)


## 本关是否可打
func is_unlocked(s: int) -> bool:
	return s >= 1 and s <= min(unlocked, StageCfg.STAGE_N)


## 本关历史最高分；无记录返回 0。
## 注意：Dictionary 下标取出来是 Variant，必须逐层验型（与 highscore_for 同一写法）
func stage_highscore(s: int) -> int:
	var key := stage_key(s)
	if not stage_best.has(key):
		return 0
	var e: Variant = stage_best[key]
	if typeof(e) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = e
	if not d.has("score"):
		return 0
	return int(d["score"])


func _load_progress() -> void:
	unlocked = 1
	stage_best = {}
	var fresh := not FileAccess.file_exists(PROGRESS_PATH)
	if fresh:
		_maybe_backup_legacy()
		_inherit_unlocked_from_legacy()   # 只在首次启动时跑一次
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	if txt.is_empty():
		return
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	if int(d.get("v", 0)) != PROGRESS_VERSION:
		return                       # 版本不对 -> 整体降级，不猜结构
	unlocked = clampi(int(d.get("unlocked", 1)), 1, StageCfg.STAGE_N)
	var sb: Variant = d.get("stages", {})
	if typeof(sb) == TYPE_DICTIONARY:
		stage_best = sb


func _write_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"v": PROGRESS_VERSION,
		"unlocked": unlocked,
		"stages": stage_best,
	}))
	f.close()


## 老档继承（**方案 A**，主理人终裁，见 `docs/architecture/adr-05` §3.3）
## **只继承解锁到第几关，不继承分数** ——
##   旧档（难度最高分）与新档（关卡最高分）量纲不同构：把旧困难档分数写进 L3，
##   等于断言"你在**新**第 3 关打出了这个完成度"—— 那是一次没发生过的游玩。
## 而 `win` 是布尔事实（"我确实打穿过某一档"），翻译成"我至少打到第 N 关"是保真映射。
##
##   档 → 关：简单→L1 / 普通→L2 / 困难→L3
##   旧档有分数      -> unlocked ≥ 对应关卡（玩过）
##   旧档 win == true -> unlocked ≥ 对应关卡 + 1（通关过，多开一关）
##   封顶 L3         -> 旧档只有三档，不可能凭空推出 L4 / L5 的游玩事实
##
## 只在「有旧档、无新档」时调用一次，且**不写盘** —— 写盘由正常游玩自然触发
## （`unlock_after` / `save_stage`），避免每次启动都用旧档覆盖玩家的真实进度。
func _inherit_unlocked_from_legacy() -> void:
	for diff in 3:
		var e: Variant = highscores.get(str(diff))
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var stage := diff + 1                          # 0→L1 / 1→L2 / 2→L3
		unlocked = maxi(unlocked, stage)
		if bool(d.get("win", false)):
			unlocked = maxi(unlocked, stage + 1)
	unlocked = clampi(unlocked, 1, LEGACY_MAX_UNLOCK)
	# stage_best **全部留空**：一个分数都不搬


## 首次启动（有旧档、无新档）时把旧文件另存一份：保留用户数据，但不迁移、不展示。
## 全程静默 —— 失败就当没做过。
func _maybe_backup_legacy() -> void:
	if not FileAccess.file_exists(HIGHSCORE_PATH):
		return
	if FileAccess.file_exists(LEGACY_PATH):
		return
	var src := FileAccess.open(HIGHSCORE_PATH, FileAccess.READ)
	if src == null:
		return
	var txt := src.get_as_text()
	src.close()
	if txt.is_empty():
		return
	var dst := FileAccess.open(LEGACY_PATH, FileAccess.WRITE)
	if dst == null:
		return
	dst.store_string(txt)
	dst.close()


## 通关第 s 关 -> 解锁第 s+1 关。返回新解锁的关号（0 = 没有新解锁）
func unlock_after(s: int, win: bool) -> int:
	if not win:
		return 0
	var nxt := s + 1
	if nxt > StageCfg.STAGE_N or nxt <= unlocked:
		return 0
	unlocked = nxt
	# ★ 必须在这里立刻写盘：`save_stage` 只在**破纪录**时才写，
	#   一局「通关了，但分数没破自己的纪录」如果不在这一步落盘，
	#   解锁进度会在下次启动时静默丢失（玩家打穿了关，重开却还是锁着）。
	_write_progress()
	return nxt


## 仅在刷新纪录时写盘（与旧 save_highscore 同一策略）
## 【不存 `win`】本关「是否通关过」由 `unlocked` 单独承载（见 unlock_after）——
## 存进最高分条目里会被后续一局失败的高分覆盖（赢过 -> 变没赢过），是静默的数据污染。
func save_stage(s: int, sc: int, armors: Array[int]) -> void:
	var key := stage_key(s)
	if sc <= stage_highscore(s):
		return
	stage_best[key] = {
		"score": sc,
		"robes": armors,
		"rank": StageCfg.rank_cn(s, sc),
	}
	_write_progress()


# ---------------------------------------------------------------
# 品阶（五关改造：改为「每关独立完成度」）
# 阈值由 StageCfg 按关给出（设计总纲 §G.4 终值），本函数只做查表 + 文案。
# 注意：品阶因此**不再跨关可比** —— 它表达的是「你在本关打到了多少完成度」。
# ---------------------------------------------------------------
## [param score] 已乘过计分倍率的落账分；[param stage] 关卡号 1..5
static func rank_of_stage(score: int, stage: int) -> String:
	return StageCfg.rank_cn(stage, score)


## 完成度（0.0~1.0+）：结算 / 关卡选择界面用「完成度 xx%」一行向玩家自解释
static func completion_of(score: int, stage: int) -> float:
	return StageCfg.completion_ratio(stage, score)


static func clamp_view(v: Vector2, m: float) -> Vector2:
	return Vector2(clampf(v.x, m, VIEW_W - m), clampf(v.y, m, VIEW_H - m))


static func in_view(v: Vector2, m: float = 90.0) -> bool:
	return v.x > -m and v.x < VIEW_W + m and v.y > -m and v.y < VIEW_H + m
