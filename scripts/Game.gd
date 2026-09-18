class_name GameSingleton
extends Node
## ---------------------------------------------------------------
## Game.gd —— 全局单例 (Autoload 名称: Game)
## 负责：三色常量 / 输入映射注册 / 跨场景数据 / 中文字体
##
## Autoload 名为 `Game`（Game.RED / Game.picked_robes ...），类名 `GameSingleton` 供需要类型化的场合引用。
## 职责仅限：三色常量 / 输入映射注册 / 跨场景数据。绘制工具见 DrawUtil。
## ---------------------------------------------------------------

# ================= 画面 =================
const VIEW_W := 1280.0
const VIEW_H := 720.0

# ================= 属性弹（赤炎 / 玄冰 / 太清 / 戊土）=================
enum C { RED = 0, BLUE = 1, WHITE = 2, YELLOW = 3 }

# 直接可用的颜色常量（避免通过单例访问枚举的兼容问题）
const RED := 0
const BLUE := 1
const WHITE := 2
const YELLOW := 3

# 历史称呼：三色（红/蓝/白）。戊土（黄）为后加的第四色。
const COLOR_CN := ["赤炎", "玄冰", "太清", "戊土"]

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

# ================= 难度 =================
enum D { EASY = 0, NORMAL = 1, HARD = 2 }

const EASY := 0
const NORMAL := 1
const HARD := 2

const DIFF_CN := ["简单", "普通", "困难"]

# ================= 道袍资料（旧称「皮肤」，现统一为道袍）=================
const ROBE_TITLE := ["赤炎剑袍", "玄冰遁袍", "太清罡袍", "戊土符袍"]
const ROBE_DESC := [
	"免疫【赤炎】属性弹\n攻击化作 · 双排飞剑\n伤害 8 × 2",
	"免疫【玄冰】属性弹\n身法提速 + 50%\n单排飞剑 伤害 10",
	"免疫【太清】属性弹\n十点罡气护盾\n十息无伤 · 护盾自动回满",
	"免疫【戊土】属性弹\n攻击化作 · 持续符光\n过热 100 点即需散热",
]
const ROBE_TAG := ["双排飞剑", "身法 +50%", "罡气护盾 10", "符光 · 过热"]
# 道袍库里的详述（一行一段，比卡面文案更细）
const ROBE_LORE := [
	"赤炎剑袍以离火蚕丝织就，穿上便与火行灵气共振。\n御剑时剑诀自生双影，一次递出两排飞剑。\n代价是剑身略轻，单发伤害不及常法，胜在覆盖面广。",
	"玄冰遁袍取极北玄冰蚕吐丝，袍角常年凝着薄霜。\n着此袍者步履生风，身法提速五成，\n最宜在弹幕夹缝中游走，一击不中便已远遁。",
	"太清罡袍不染五行，最擅守御。\n着身即生十点罡气，可替主人硬承伤害；\n只要十息之内未曾受伤，罡气便自行圆满。",
	"戊土符袍以戊土灵砂绘就符箓，着之可引灵光成柱。\n御敌时化作一道绵绵不绝的符光，只消按住不放。\n然符光过盛则符袍生热 —— 满百即滞，须停手半息令其自散；\n而戊土符弹不伤其身，反能引走三十点热气。",
]
const ROBE_STORE := [
	"火行 · 攻",
	"水行 · 速",
	"无行 · 守",
	"土行 · 术",
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
## 玩家在关卡开始前选定的两件道袍（关卡中按空格切换）
var picked_robes: Array[int] = [C.RED, C.WHITE]
## 本局难度（由择难度界面写入）
var difficulty: int = NORMAL
var score := 0
var result_win := false
var result_score := 0
var result_hp := 0
## 本局是否刷新了该难度的最高分（结算界面据此打「新高」标记）
var result_is_new_high := false
## 本局开打之前该难度的历史最高分（结算界面据此显示「历史最高」）
var result_prev_high := 0

# ================= 本地存档 =================
## 最高分存档路径（user:// 由引擎解析到各平台的用户数据目录）
const HIGHSCORE_PATH := "user://highscores.json"
## 结构：{ "0" / "1" / "2": { "score": int, "robes": Array[int],
##                            "rank": String, "win": bool } }
## 键是难度 int 转 String —— JSON 的对象键只能是字符串。
var highscores: Dictionary = {}

# ================= 生命周期 =================
func _ready() -> void:
	_setup_actions()
	_load_highscores()


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
# 难度参数
# 写成带返回类型的访问器而不是一张配置表：调用点拿到的是 int / bool / float，
# 不用到处写 int(cfg["boss_hp"]) 这种下标取值（那也是之前踩过的坑）。
# ---------------------------------------------------------------

func diff_name() -> String:
	return DIFF_CN[difficulty]


## 老祖血量：简单 1400 / 普通 2500 / 困难 3600
## 简单档原本 1000 —— 狂暴段只有 2.3 秒，三幕走不完就收场；提到 1400 后
## 狂暴段约 3.3 秒、整场约 10.9 秒，够玩家把三幕都过一遍。
func boss_hp() -> int:
	if difficulty == EASY:
		return 1400
	if difficulty == HARD:
		return 3600
	return 2500


## 法相数：简单只有两重，其余三重
func boss_phases() -> int:
	return 2 if difficulty == EASY else 3


## 属性法罩：只有困难会展开
func boss_ward() -> bool:
	return difficulty == HARD


## 弹幕密度系数：1.0 为满量，越小越稀疏
func bullet_scale() -> float:
	if difficulty == EASY:
		return 0.55
	if difficulty == HARD:
		return 1.0
	return 0.80


## 异色伤害倍率：法罩开启时，非同色飞剑只剩这个比例
## 简单 / 普通没有法罩，谈不上异色惩罚，恒为 1.0；困难为 0.60
func off_color_mul() -> float:
	return 0.60 if difficulty == HARD else 1.0


## 计分倍率：同样的战果，难度越高折算的灵石越多。
## 关卡内 _add_score 统一乘它 —— HUD 实时分 / 结算分 / 品阶判定因此全链路一致。
func score_multiplier() -> float:
	if difficulty == EASY:
		return 1.0
	if difficulty == HARD:
		return 1.35
	return 1.15


# ---------------------------------------------------------------
# 品阶
# 阈值只此一份：结算界面显示与最高分存档共用，避免两处各写一套而走偏。
# 阈值是针对「已乘过难度倍率」的分数定的：
#   困难满分 9800 × 1.35 = 13230 ≥ 12500 -> 天品可达
#   普通满分 9800 × 1.15 = 11270        -> 地品
#   简单满分 9800 × 1.00 =  9800        -> 地品
# ---------------------------------------------------------------
static func rank_of(s: int) -> String:
	if s >= 12500:
		return "天品 · 元婴"
	if s >= 9000:
		return "地品 · 金丹"
	if s >= 6000:
		return "玄品 · 筑基"
	return "黄品 · 炼气"


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
func save_highscore(diff: int, sc: int, robes: Array[int], rank: String, win: bool) -> void:
	var key := str(diff)
	if sc <= highscore_for(diff):
		return
	highscores[key] = {
		"score": sc,
		"robes": robes,
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


static func clamp_view(v: Vector2, m: float) -> Vector2:
	return Vector2(clampf(v.x, m, VIEW_W - m), clampf(v.y, m, VIEW_H - m))


static func in_view(v: Vector2, m: float = 90.0) -> bool:
	return v.x > -m and v.x < VIEW_W + m and v.y > -m and v.y < VIEW_H + m
