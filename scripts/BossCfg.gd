class_name BossCfg
extends RefCounted
## ---------------------------------------------------------------
## 五个旗舰的技能池与节奏表 —— 只对外暴露「带返回类型的静态访问器」
##
## 数值 / 技能池来源：`design/levels/01-五关设计总纲.md` §D（五个 Boss 逐条）。
## 本文件**不自拟任何数值**；设计与本文件冲突时，以设计总纲为准并回问主理人。
##
## 三条铁律（踩过的坑）：
##   1. const 里不套 Dictionary / 嵌套 Array —— 只放一维、字面量同构的表；
##   2. 不放 PackedStringArray([...])（不能用于 const）；
##   3. 所有表的元素类型必须同构，否则推断不出 Array[String]，下标会退化成 Variant。
##
## 关卡号 1-based，阶段号 1-based；越界一律收敛，绝不返回空池。
## ---------------------------------------------------------------

## 兜底节奏：设计未给值的技能走这里（dur_of / tick_of 绝不返回 0，否则死循环开火）
const DUR_FALLBACK := 3.2
const TICK_FALLBACK := 0.60

## 狂暴散热期结束的近距离冲击环（设计总纲 §D.3 原话：「散热期结束会喷一次
## 近距离冲击环（半径 180），逼玩家打完就撤」）。
## 伤害与 `EnemyCfg.MINE_DMG` 同为 12 是**刻意**的（主理人裁定：同族数值玩家
## 已有直觉）；但不加保险期 —— 环是瞬发的，不像雷有「刚落地贴脸瞬爆」的问题。
## 原在 Boss.gd，属 Boss 数值，故归位到本文件。
const HEAT_BLAST_R := 180.0
const HEAT_BLAST_DMG := 12

# ============================ 技能池（设计 §D，逐条照抄）============================
# L1 熔核号 · 2 阶段 · 换甲
const _L1_P1 := ["fan_red", "aim_blue", "ring_white"]
const _L1_P2 := ["rain_red", "fan_yellow", "ring_white"]
# L2 霜噬号 · 3 阶段 · 走位（全部可预判固定图形 + 呼吸窗口）
const _L2_P1 := ["ring_slow", "cross_ray"]
const _L2_P2 := ["grid_rain_blue", "fan_blue", "ring_slow"]
const _L2_P3 := ["spiral_wb", "cross_ray", "grid_rain_blue"]
# L3 耀斑号 · 3 阶段 · 集火（常驻减伤 70% + 散热期 ×1.8 / 狂暴 ×2.4，见 StageCfg.heat_mul）
const _L3_P1 := ["fan_red", "ring_white"]
const _L3_P2 := ["rain_yellow", "aim_white", "fan_red"]
const _L3_P3 := ["chaos", "ring_white", "spiral_ry"]
# L4 深渊之喉 · 3 阶段 · 应对召唤（子核心免伤 80% / 伤害共享 40% / 暴露期才展护罩）
const _L4_P1 := ["homing", "ring_white"]
const _L4_P2 := ["spiral_rb", "rain_red", "fan_yellow"]
# ⚠ 第三招原为 `spiral_4`，主理人裁定改 `spiral_ry`（2026-09-22）：
#   总纲 §D.4 与验收清单 §2.5.1 自相矛盾 —— 验收清单是后出的去重核对文档，
#   用「唯一例外」的强约束措辞定死「spiral_4 全色旋臂只允许 L5 相④」，
#   且语义成立：四色全色旋臂是终焉号第四相的身份标识，L4 提前用会泄露 L5 的收束感。
#   `spiral_ry`（红+黄双色）不是全色，不触独占，且更贴 L4 引力井（黄）主题。
const _L4_P3 := ["chaos", "spiral_ry", "grid_rain"]
# L5 终焉号 · 4 阶段 · 续航（四相重构，每相独立技能组 + 独立护罩轮转）
#
# ⚠ L5 四相走「自解释技能名」（验收清单 §2.5.1）：同名招在 L5 要的参数与 L1/L3 不同
#   （例：L5 相① fan_red = 15发/1.35rad，L1 fan_red = 11发/1.15rad）。改原语会波及
#   L1 / L3，故**另开带参数后缀的新名**，原语一行不改 —— 纯增量，零回归。
#   新增名一览（参数写在名字里，一眼可读）：
#     fan_red_w      红扇 · 15发 · 1.35rad 宽扇（w = wide）   [原名 fan_red  = 11发/1.15rad]
#     rain_red_3     红雨 · 3发                                [原名 rain_red = 2发]
#     ring_white_x2  白环 · 34发 · 双环反向                    [原名 ring_white = 24发单环]
#     aim_white_6    白点射 · 6发速射                          [原名 aim_white = 5发]
#     homing_white   追尾 · 3发 · 白弹（原 homing 取 ward 色 / 随机色）
#     rain_yellow_3  黄雨 · 3发                                [原名 rain_yellow = 2发]
#     mine_toss_y    黄雷 · 2枚 · 8s 自毁（EnemyCfg.MINE_LIFE）
const _L5_P1 := ["fan_red_w", "rain_red_3", "spiral_rb"]
# 相② 霜环·蓝 —— 三招全蓝（主色占比 3/3 ≥ 2/3）。
#   顺序是设计定的：「把最蓝的两招放在玩家最先看到的位置，首招决定第一印象」。
#   ⚠ ring_white 是**白弹**，不得出现在非白相（它只能在相③）—— 这就是原先「相②偏白」的根因。
const _L5_P2 := ["fan_blue", "grid_rain_blue", "ring_blue"]
# 相③ 光子·白 —— 三招皆白（主色占比 3/3 ≥ 2/3），靠**几何 + 追尾**拉开差异，不靠换色：
#   双环反向 / 6发速射 / 追尾弹。注意 `homing` 原语取 ward 色或随机色，用在白相会漏白，
#   故换成白弹版 `homing_white`（纯增量，`homing` 本身仍服务 L4 P1）。
const _L5_P3 := ["ring_white_x2", "aim_white_6", "homing_white"]
# 相④ 引力·黄 —— 循环序按验收清单 §2.5.1 四相编排表：雨 → 雷 → 全色旋臂（终相信号收尾）
const _L5_P4 := ["rain_yellow_3", "mine_toss_y", "spiral_4"]

# ============================ 节奏表（沿用旧表 + 设计新增原语）============================
const _DUR := {
	"fan_red": 3.2, "aim_blue": 3.0, "rain_red": 3.0, "rain_blue": 3.0,
	"ring_white": 3.4, "spiral_rb": 4.2, "chaos": 4.4, "homing": 3.6,
	"fan_yellow": 3.0, "rain_yellow": 3.2,
	# —— 设计 §D 新增原语 ——
	"ring_slow": 3.4, "cross_ray": 3.6, "grid_rain": 3.4, "grid_rain_blue": 3.4,
	"fan_blue": 3.0, "aim_white": 2.8, "spiral_wb": 4.2,
	"ring_blue": 3.4,
	"spiral_ry": 4.2, "spiral_4": 4.4, "mine_toss": 3.0,
	# —— L5 四相「自解释技能名」（验收清单 §2.5.1）—— 节奏照同族原语取值，绝不走兜底
	"fan_red_w": 3.2, "rain_red_3": 3.0,
	"ring_white_x2": 3.4, "aim_white_6": 2.8, "homing_white": 3.6,
	"rain_yellow_3": 3.2, "mine_toss_y": 3.0,
}
const _TICK := {
	"fan_red": 0.60, "aim_blue": 0.55, "rain_red": 0.17, "rain_blue": 0.22,
	"ring_white": 0.80, "spiral_rb": 0.075, "chaos": 0.13, "homing": 0.45,
	"fan_yellow": 0.70, "rain_yellow": 0.20,
	# —— 设计 §D 新增原语 ——
	"ring_slow": 0.80, "cross_ray": 0.20, "grid_rain": 0.35, "grid_rain_blue": 0.35,
	"fan_blue": 0.60, "aim_white": 0.40, "spiral_wb": 0.075,
	"ring_blue": 0.80,
	"spiral_ry": 0.085, "spiral_4": 0.09, "mine_toss": 1.20,
	# —— L5 四相「自解释技能名」—— aim_white_6 是「速射」，比原 aim_white(0.40) 略快
	"fan_red_w": 0.60, "rain_red_3": 0.17,
	"ring_white_x2": 0.80, "aim_white_6": 0.36, "homing_white": 0.45,
	"rain_yellow_3": 0.20, "mine_toss_y": 1.20,
}


## ⚠ const 一维字面量数组在本版本推断为**未类型化 Array**，直接 return 给
##   `Array[String]` 会在运行时报「Trying to assign an array of type Array to a
##   variable of type Array[String]」，而且每个开火周期刷一条。统一走这里转换。
static func _sa(a: Array) -> Array[String]:
	var out: Array[String] = []
	for v in a:
		out.append(str(v))
	return out


## 本关本阶段的技能池。stage 越界收敛到 1..5，phase 越界收敛到本关最后一相。
static func pool(stage: int, phase: int) -> Array[String]:
	var s := clampi(stage, 1, StageCfg.STAGE_N)
	var p := clampi(phase, 1, StageCfg.boss_phases(s))
	match s:
		1:
			return _sa(_L1_P2 if p >= 2 else _L1_P1)
		2:
			if p <= 1:
				return _sa(_L2_P1)
			return _sa(_L2_P3 if p >= 3 else _L2_P2)
		3:
			if p <= 1:
				return _sa(_L3_P1)
			return _sa(_L3_P3 if p >= 3 else _L3_P2)
		4:
			if p <= 1:
				return _sa(_L4_P1)
			return _sa(_L4_P3 if p >= 3 else _L4_P2)
		_:
			if p <= 1:
				return _sa(_L5_P1)
			if p == 2:
				return _sa(_L5_P2)
			return _sa(_L5_P4 if p >= 4 else _L5_P3)


## 技能持续时长（秒）。未登记的技能走兜底，绝不返回 0。
static func dur_of(skill: String) -> float:
	var v: float = _DUR.get(skill, DUR_FALLBACK)
	return v if v > 0.0 else DUR_FALLBACK


## 技能发射间隔（秒）。未登记的技能走兜底，绝不返回 0。
static func tick_of(skill: String) -> float:
	var v: float = _TICK.get(skill, TICK_FALLBACK)
	return v if v > 0.0 else TICK_FALLBACK
