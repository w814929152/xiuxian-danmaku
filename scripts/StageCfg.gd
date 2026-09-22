class_name StageCfg
extends RefCounted
## ---------------------------------------------------------------
## 五关配置 —— 只对外暴露「带返回类型的静态访问器」
##
## 数值来源：`design/levels/01-五关设计总纲.md`（文策渊终裁稿，§A~§G + §J 终裁）。
## 本文件**不自拟任何数值**；设计与本文档冲突时，以设计总纲为准并回问主理人。
##
## 三条铁律（踩过的坑）：
##   1. const 里不套 Dictionary / Array 的复杂结构 —— 只放一维、字面量同构的表；
##   2. 不放 PackedStringArray([...])（不能用于 const）—— 需要它在 static func 里构建；
##   3. 所有表的元素类型必须同构（全 int / 全 float / 全 bool / 全 String），
##      否则推断不出 Array[int]，下标取值就会退化成 Variant（那正是要避的坑）。
##
## 关卡号一律 1-based；越界一律 clampi，绝不返回 null / 抛错。
## ---------------------------------------------------------------

const STAGE_N := 5
## 波次表按 (s-1)*MAX_WAVES + (n-1) 展平；不足的格子填 0
const MAX_WAVES := 5
## 「本关第二种独有怪」不存在时的哨兵值
const NO_KIND := -1
## 单色连长上限：允许 2 连，禁止连续 ≥3 同色。
## （第 1 关第 1 波是刻意的一色到底 —— 教换甲的教学波，不受此限。）
## 原在 Level.gd，属波次编排规则，故归位到本文件。
const MAX_RUN := 2

## 护罩模式
enum WardMode {
	NONE = 0,      # 永不展护罩（L2 / L3）
	ALWAYS = 1,    # 全程轮转（L1 / L5）
	EXPOSED = 2,   # 仅暴露期展开（L4）
}

# ============================ 展示文案（统称「星盗旗舰」，各关专属头衔见 BOSS_TITLE）============================
const STAGE_CN := ["锈带星域", "霜环星域", "耀斑星域", "引力井星域", "王座星域"]
const STAGE_SUB := ["初次交火", "双色夹击", "列阵轰击", "深渊回响", "终局"]
const BOSS_CN := ["熔核号", "霜噬号", "耀斑号", "深渊之喉", "终焉号"]
const BOSS_TITLE := ["星盗先驱", "星盗霜舰", "星盗炮垒", "星盗母舰", "星盗王"]

# ============================ 逐关标量（下标 0 = 第 1 关）============================
const _BOSS_HP := [1600, 2400, 3200, 4200, 6000]
const _BOSS_PHASES := [2, 3, 3, 3, 4]
const _WARD_MODE := [1, 0, 0, 2, 1]        # WardMode（int，枚举不能进推断数组）
const _BULLET := [0.55, 0.80, 0.85, 0.95, 1.00]
const _OFF_COLOR := [0.60, 1.00, 1.00, 0.60, 0.55]
const _SCORE_MUL := [1.00, 1.10, 1.20, 1.30, 1.40]
const _WAVES := [3, 4, 4, 5, 5]
const _ENRAGE_AT := [0.30, 0.30, 0.30, 0.30, 0.25]
## 清场 guard 上限（秒）：无战将波 / 战将波
const _GUARD_PLAIN := [14.0, 14.0, 18.0, 18.0, 20.0]
const _GUARD_ELITE := [26.0, 26.0, 30.0, 30.0, 32.0]
## 击杀掉落概率（L5 续航考验：0.18 -> 0.14）
const _DROP := [0.18, 0.18, 0.18, 0.18, 0.14]
## 常驻减伤（与颜色无关，不触可行性铁律）：L3 耀斑号 = 70%
const _RESIST := [0.00, 0.00, 0.70, 0.00, 0.00]
## 护罩轮转间隔 / 狂暴后间隔 / 换色预告时长
const _WARD_CD := [6.5, 0.0, 0.0, 6.0, 5.0]
const _WARD_CD_RAGE := [3.5, 0.0, 0.0, 4.5, 3.5]
const _WARD_TELL := [1.5, 0.0, 0.0, 1.5, 1.5]
## 子核心：免伤 / 伤害共享 / 暴露期 / 召唤间隔（L4 深渊之喉）
const _SUB_REDUCE := 0.80
const _SUB_SHARE := 0.40
const _EXPOSE := [0.0, 0.0, 0.0, 6.0, 0.0]
const _EXPOSE_RAGE := [0.0, 0.0, 0.0, 4.5, 0.0]
const _SUMMON_CD := [0.0, 0.0, 0.0, 4.0, 0.0]
const _SUMMON_CD_RAGE := [0.0, 0.0, 0.0, 2.0, 0.0]

# ============================ 波次级（展平，5 关 × 5 波）============================
## 目标色喽啰只数（∈ S）。行序 s1..s5，每行 5 格
const _TARGET := [
	5, 4, 3, 0, 0,     # s1（3 波）
	4, 4, 4, 3, 0,     # s2（4 波）
	5, 4, 4, 4, 0,     # s3（4 波）
	5, 4, 4, 4, 3,     # s4（5 波）
	5, 4, 4, 4, 3,     # s5（5 波）
]
## 骚扰色喽啰只数（∈ S'，恒 hover）。第 1 波恒 0（教学波豁免）
const _HARASS := [
	0, 2, 3, 0, 0,
	1, 2, 3, 3, 0,
	2, 2, 2, 2, 0,
	2, 2, 3, 3, 3,
	3, 3, 3, 3, 4,
]
## 本波「第一种独有怪」只数（L3 列阵者按「组」计，1 格 = 3 艘）
const _UNIQ_A := [
	0, 1, 2, 0, 0,     # s1 拆解者：全场 3
	1, 1, 1, 2, 0,     # s2 变节者：全场 5
	0, 1, 1, 2, 0,     # s3 列阵者：全场 4 组 = 12 艘
	0, 1, 1, 1, 1,     # s4 敷设者：全场 4
	0, 2, 2, 2, 3,     # s5 殉爆者：全场 9
]
## 本波「第二种独有怪」只数（L1~L3 只有一种，恒 0）
const _UNIQ_B := [
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 0, 0, 0,
	0, 0, 1, 1, 2,     # s4 虹吸者：全场 4
	0, 0, 1, 2, 2,     # s5 相位者：全场 5
]
## 本波是否以星盗战将压轴（1 = 有）。L4 / L5 双战将须强制异色
const _ELITE := [
	0, 0, 1, 0, 0,     # L1：战将 ×1（第 3 波）
	0, 1, 0, 1, 0,     # L2：指挥(第 2 波) + 战将(第 4 波)
	0, 1, 1, 1, 0,     # L3：堡垒(第 2 波) + 战将(第 3、4 波)
	0, 1, 0, 1, 1,     # L4：护盾(第 2 波) + 战将(第 4、5 波)
	0, 1, 1, 1, 1,     # L5：堡垒(第 2) + 指挥(第 3) + 战将(第 4、5 波)
]
## 本波压轴精英的**种类**（EnemyKind.E：1 战将 / 2 弹幕堡垒 / 3 增殖指挥 / 4 护盾冲锋）。
##   与 `_ELITE` 一一对应：只在 `_ELITE == 1` 的波次非 0，其余填 0（占位）。
##   排布原则（2026-09-22 主理人要求「增加精英怪」）：
##     · 战将（破罩）位置**完全不动**（L1-3 / L2-4 / L3-3,4 / L4-4,5 / L5-4,5）——
##       它最贴合「换甲」这根支柱，仍是每关的主考。
##     · 新三只作为**额外**精英插在中前波，且**不与战将同波**（避免一波塞两种色防机制，
##       玩家读不过来）：L2-2 指挥 · L3-2 堡垒 · L4-2 护盾 · L5-2 堡垒 · L5-3 指挥。
##     · L1 保持单战将（教学关，机制不宜过早叠）。
##   每关精英总数：L1=1 / L2=2 / L3=3 / L4=3 / L5=4 —— 满分表 `_MAX` 已按此重算。
const _ELITE_TYPE := [
	0, 0, 1, 0, 0,
	0, 3, 0, 1, 0,
	0, 2, 1, 1, 0,
	0, 4, 0, 1, 1,
	0, 2, 3, 1, 1,
]
## 星盗战将弹幕的**色数**（> 1 即多色弹幕；色序 = [力场色, S'①, S'②, S 另一色] 取前 N 色）
##   起因（2026-09-22 主理人要求「精英怪要可以发出多色弹幕」）：
##   现状战将弹幕**全是力场色**（∈ S），玩家换上同色甲后弹幕被全量吸收
##   （寒霜疾甲闪避 / 光子盾甲充盾），战将的弹幕威胁**归零** —— 破罩与走位只活了前半。
##   掺入 ∈ S' 的骚扰色把走位压力补回来；**力场色恒占 ≥50%**，「为主」的语义保留。
##   顺序有讲究：先掺玩家永远吸不了的 S'（逼走位），L5 才把玩家的副甲色也拉进来 ——
##   那一关吸弹与破力场开始互相排斥，是终局该有的抉择。
##   **前两关恒 1**：教学期不该一上来就混色（与 bullet_scale 的递进语言一致）。
##   ⚠ 可行性铁律只约束**必须打破的色防**（战将力场色 ∈ S，见 `Elite.setup`），
##   不约束弹幕色 —— 骚扰色喽啰（∈ S'、逼走位）本就是同款既有设计。
const _ELITE_HUE := [1, 1, 2, 3, 4]

## 驻留阵地波位表（1 = 该波为驻留波：背景降到 SCROLL_HOLD + 敌人屏内跃迁入场）
##   提案 `design/levels/03-关卡节奏实测与驻留波提案.md` §3 —— 关卡形式原本只有
##   「持续向前推进」一种，驻留波用来补**空间形式**的对比：推进 → 驻留 → 推进 → Boss。
##   每关只插 1~2 波、压在中后段，**不碰第 1 波**（那是教学波，整波一色到底）。
##   清场判定完全复用推进波（一行不改），只改入场位置与背景滚速 —— 对既有
##   平衡的影响接近零（不动血量 / 弹幕 / 配色 / 计分）。
const _HOLD := [
	0, 1, 0, 0, 0,   # L1（3 波）：第 2 波
	0, 0, 1, 0, 0,   # L2（4 波）：第 3 波
	0, 1, 0, 0, 0,   # L3（4 波）：第 2 波（列阵组首登，正好是"阵地战遭遇炮列"）
	0, 0, 1, 0, 1,   # L4（5 波）：第 3 / 第 5 波
	0, 1, 0, 1, 0,   # L5（5 波）：第 2 / 第 4 波
]

## 出怪间隔（秒）
const _GAP := [
	0.62, 0.57, 0.52, 0.00, 0.00,
	0.62, 0.57, 0.52, 0.47, 0.00,
	0.62, 0.57, 0.52, 0.47, 0.00,
	0.62, 0.57, 0.52, 0.47, 0.42,
	0.62, 0.56, 0.50, 0.44, 0.40,
]

# ============================ 波次强度（设计 §B.3）============================
## LEVEL_HP：关卡基准
const LEVEL_HP := [1.00, 1.15, 1.30, 1.50, 1.75]
## WAVE_HP(w, N) = 1.00 + 0.30 × (w-1)/(N-1)；与 LEVEL_HP 相乘后极值 2.275
const _HP_MAX_STEP := 0.30

# ============================ 每关满分 / 品阶阈值（主理人终裁：**以波次表为唯一来源**）==========
## 落账满分（已乘计分倍率）= 结算展示分 = 最高分存档分 = 品阶判定分
##
## ⚠ 不用设计 §G.3 的旧表（8350 / 10725）—— 那两张表漏算了骚扰色喽啰，
##   会让实际可得分（8850 / 11715）超过满分 100%，而金勋线是 96% → 金勋白送。
##   现按主理人 R-15 口径，从 `_TARGET + _HARASS + _UNIQ_A/B + _ELITE` 波次表重算：
##
##   计分单位（设计 §G.2，全部走 Level._add_score 的「落账时 × 计分倍率」链路）：
##     喽啰 100（目标色 + 骚扰色同价）· 拆解者小片 50 · 引力雷 0
##     其余独有怪按 EnemyKind.SCORE · 战将 800 · 新精英（堡垒/指挥/护盾）各 900 ·
##     阶段切换 600 · 斩杀 Boss 5000
##
##   ⚠ 2026-09-22 新增三只精英后重算（每关精英数 L1=1 / L2=2 / L3=3 / L4=3 / L5=4）：
##   L1: (17×100 + 3×150 + 6×50 + 1×800 + 1×600 + 5000) × 1.00 = 8850
##   L2: (24×100 + 5×250 + 1×900 + 1×800 + 2×600 + 5000) × 1.10 = 12705
##   L3: (25×100 + 4×300 + 1×900 + 2×800 + 2×600 + 5000) × 1.20 = 14880
##   L4: (33×100 + 4×250 + 4×350 + 1×900 + 2×800 + 2×600 + 5000) × 1.30 = 18720
##   L5: (36×100 + 9×200 + 5×300 + 2×900 + 2×800 + 3×600 + 5000) × 1.40 = 23940
const _MAX := [8850, 12705, 14880, 18720, 23940]
## 品阶阈值（≥55% 铜 / ≥80% 银 / ≥96% 金）
## 取整口径（主理人终裁）：铜档与金档**向下取整到 10**，银档**按公式值取整**
const _RANK_COPPER := [4860, 6980, 8180, 10290, 13160]
const _RANK_SILVER := [7080, 10164, 11904, 14976, 19152]
const _RANK_GOLD := [8490, 12190, 14280, 17970, 22980]

# ---------------------------------------------------------------- 索引工具
static func _i(s: int) -> int:
	return clampi(s, 1, STAGE_N) - 1


## 波次二维索引：n 越界时收敛到本关最后一波（调用方只会在 1..waves(s) 内循环）
static func _w(s: int, n: int) -> int:
	return _i(s) * MAX_WAVES + (clampi(n, 1, waves(s)) - 1)


# ---------------------------------------------------------------- 展示
static func is_valid(s: int) -> bool:
	return s >= 1 and s <= STAGE_N


static func name_of(s: int) -> String:
	return STAGE_CN[_i(s)]


static func sub_of(s: int) -> String:
	return STAGE_SUB[_i(s)]


## HUD / 横幅用的全名，例如「熔核号 · 星盗先驱」
static func boss_full_name(s: int) -> String:
	return "%s · %s" % [BOSS_CN[_i(s)], BOSS_TITLE[_i(s)]]


## 短名，例如「熔核号」（存档 / 调试 / 关卡卡面）
static func boss_name(s: int) -> String:
	return BOSS_CN[_i(s)]


# ---------------------------------------------------------------- 旗舰参数
## 血上限一律落到 Boss 的实例变量 max_hp，不用常量（既有铁律）
static func boss_hp(s: int) -> int:
	return _BOSS_HP[_i(s)]


static func boss_phases(s: int) -> int:
	return _BOSS_PHASES[_i(s)]


## 旗舰【碰撞半径】（设计 `01-五关视觉差异化规格.md` §C.1）：L1..L5 = 46/52/58/65/70。
##   本体/碰撞比（剪影最远角 × R_MAIN ÷ R_HIT，V5 口径）实测 1.19~1.22，非单调：
##   L1 1.217 → L2 1.212 → L3 1.206 → L4 1.193（最小）→ L5 1.224（最大，
##   即最接近 1.34 上限、最紧的一关）。勿按「越往后越小」推断。
##   ⚠ 该比值 = (R_MAIN / R_HIT) × 剪影形状系数，两者都算：L3 曾因炮垒四角外突
##     做到 1.456，而它的 R_MAIN/R_HIT 只有 1.207。改剪影形状必须重跑 V5。
const _BOSS_R_HIT := [46, 52, 58, 65, 70]

## 旗舰【主半径 R_MAIN】（§C.1）：L1..L5 = 56/63/70/77/84。
##   `Boss._draw()` 的一切覆盖层（气息 / 护罩弧 / 狂暴圈 / 白闪）都按它比例化（§C.0-2），
##   不再写死数值 —— 旧代码全部以 70 为基准写成硬编码常量，改一个半径就要改十几处。
const _BOSS_R_MAIN := [56, 63, 70, 77, 84]

## 旗舰碰撞半径（`Boss._ready()` 写 `sh.radius`）—— 五关不同，见 `_BOSS_R_HIT`
static func boss_radius(s: int) -> int:
	var v: int = _BOSS_R_HIT[_i(s)]
	return v


## 旗舰主半径 R_MAIN（`Boss._draw()` 覆盖层比例化的唯一基准）—— 见 `_BOSS_R_MAIN`
static func boss_r_main(s: int) -> int:
	var v: int = _BOSS_R_MAIN[_i(s)]
	return v


static func boss_ward(s: int) -> bool:
	return ward_mode(s) != WardMode.NONE


static func ward_mode(s: int) -> int:
	return _WARD_MODE[_i(s)]


static func bullet_scale(s: int) -> float:
	return _BULLET[_i(s)]


## 护罩开启时，非同色光刃只剩这个比例
static func off_color_mul(s: int) -> float:
	return _OFF_COLOR[_i(s)]


static func score_multiplier(s: int) -> float:
	return _SCORE_MUL[_i(s)]


static func enrage_at(s: int) -> float:
	return _ENRAGE_AT[_i(s)]


static func ward_cd(s: int) -> float:
	return _WARD_CD[_i(s)]


static func ward_cd_rage(s: int) -> float:
	return _WARD_CD_RAGE[_i(s)]


## 换色预告时长（秒）—— 读得出来，不靠背板
static func ward_telegraph(s: int) -> float:
	return _WARD_TELL[_i(s)]


## 常驻减伤（与颜色无关）：L3 = 0.70，其余 0
static func resident_resist(s: int) -> float:
	return _RESIST[_i(s)]


## L3 散热期时长（秒）：3.0 -> 2.2 -> 1.6；狂暴 1.2。非 L3 返回 0
static func heat_window(s: int, phase: int) -> float:
	if _i(s) != 2:
		return 0.0
	match clampi(phase, 1, 3):
		1:
			return 3.0
		2:
			return 2.2
		_:
			return 1.6


static func heat_window_rage(s: int) -> float:
	return 1.2 if _i(s) == 2 else 0.0


## 散热期伤害倍率：常态 ×1.8 / 狂暴 ×2.4
##   ⚠ 2026-09-22 下调（原 ×3.0 / ×4.0）—— 原型实测 L3 Boss 战仅 19.2s，
##   比血量更少的 L2（25.3s）还短 24%，难度曲线在 L3 出现断崖。根因是散热期
##   ×3.0 压过了常驻减伤 70%：实测散热时间占全程 53.7%，平均倍率 1.75，
##   「常态 0.3 减伤」形同虚设。下调后实测平均倍率约 1.0、TTK 约 32s，
##   落在 L2 25.3s 与 L4 58.1s 之间，曲线恢复单调递增。
##   仍是「常态 0.3 → 散热 1.8」= 6 倍差距，作为唯一输出窗口的奖励感保留。
##   见 design/levels/03-关卡节奏实测与驻留波提案.md §1.5。
static func heat_mul(s: int, rage: bool) -> float:
	if _i(s) != 2:
		return 1.0
	return 2.4 if rage else 1.8


static func sub_core_resist(s: int) -> float:
	return _SUB_REDUCE if _i(s) == 3 else 0.0


static func sub_core_share(s: int) -> float:
	return _SUB_SHARE if _i(s) == 3 else 0.0


static func expose_time(s: int) -> float:
	return _EXPOSE[_i(s)]


static func expose_time_rage(s: int) -> float:
	return _EXPOSE_RAGE[_i(s)]


static func summon_cd(s: int) -> float:
	return _SUMMON_CD[_i(s)]


static func summon_cd_rage(s: int) -> float:
	return _SUMMON_CD_RAGE[_i(s)]


## L1 熔核号本体固定光子白（教学关可读性，终裁 §J.6）；其余返回 -1 = 跟随 ward 色
static func body_color(s: int) -> int:
	return Game.WHITE if _i(s) == 0 else -1


## 阶段刻度线（HUD 用）：条数 = 阶段数 - 1，1~3 条可变，HUD 不得写死两条
static func phase_marks(s: int) -> Array[float]:
	var m := boss_phases(s) - 1
	var out: Array[float] = []
	if m <= 0:
		return out
	if m == 1:
		out.append(0.50)
		return out
	if m == 2:
		out.append(0.34)
		out.append(0.67)
		return out
	out.append(0.75)
	out.append(0.50)
	out.append(0.25)
	return out


## Boss 列雨（`grid_rain` / `grid_rain_blue`）的列数 —— 逐关逐相写死，Boss 侧**只查不判**。
##   收口原因：原先两处调用点是 `8 if phase >= 3 else 6` 之类的条件表达式，
##   L5 一加就变成 `phase >= 3 or stage >= 5`，再挂特例没人看得懂，故配置化。
##   权威值（验收清单 §2.5 逐关取值）：L2 P2 = 6 / L2 P3 = 8 / L4 P3 = 7 / L5 四相一律 8。
##   该关该相用不到列雨的格子填 6（历史默认）—— **不填 0**，0 列会让列距计算除零。
## 展平下标 = _i(s) * _BOSS_PHASE_MAX + (p-1)；phase 越界收敛到 1.._BOSS_PHASE_MAX
const _BOSS_PHASE_MAX := 4
const _GRID_COLS := [
	6, 6, 6, 6,     # s1（无列雨，填默认）
	6, 6, 8, 6,     # s2：P2 = 6 / P3 = 8
	6, 6, 6, 6,     # s3（无列雨，填默认）
	6, 6, 7, 6,     # s4：P3 = 7
	8, 8, 8, 8,     # s5：四相一律 8
]

## 本关本相的列雨列数（`Boss._grid_rain` 唯一入参来源）
static func grid_cols(s: int, phase: int) -> int:
	return _GRID_COLS[_i(s) * _BOSS_PHASE_MAX + (clampi(phase, 1, _BOSS_PHASE_MAX) - 1)]


## Boss 各相的【主题色】（`Game.C`：0=红 / 1=蓝 / 2=白 / 3=黄）；**-1 = 无主题色**。
##   只服务「阶段切换的宣告环」（`Boss._on_phase`）：
##     L1~L4 一律 -1 —— 宣告环完全沿用原 `ring_white`，**行为一个字节都不变**（零回归硬要求）；
##     L5 四相 = 红 / 蓝 / 白 / 黄 —— 验收清单 §2.5.1 四相编排表的主题色列。
##   ⚠ 主题色 ≠ 护罩色：护罩色仍从玩家两件战甲 S 内轮转（可行性铁律优先于主题色）。
##   ⚠ 枚举不能进推断数组（本文件既有坑，`_WARD_MODE` 同款），故写成裸 int + 注释。
const _PHASE_THEME := [
	-1, -1, -1, -1,     # s1（无主题色）
	-1, -1, -1, -1,     # s2（无主题色）
	-1, -1, -1, -1,     # s3（无主题色）
	-1, -1, -1, -1,     # s4（无主题色）
	0, 1, 2, 3,         # s5：相①红 / 相②蓝 / 相③白 / 相④黄
]

## 本关本相的主题色；**-1 = 无主题色**，调用方沿用原行为（不写 `stage >= 5` 之类的硬编码分支）
static func phase_theme_color(s: int, phase: int) -> int:
	var v: int = _PHASE_THEME[_i(s) * _BOSS_PHASE_MAX
			+ (clampi(phase, 1, _BOSS_PHASE_MAX) - 1)]
	return v


# ---------------------------------------------------------------- 波次
static func waves(s: int) -> int:
	return _WAVES[_i(s)]


static func wave_targets(s: int, n: int) -> int:
	return _TARGET[_w(s, n)]


static func wave_harass(s: int, n: int) -> int:
	return _HARASS[_w(s, n)]


## 本波独有怪总只数（两种独有怪之和）
static func wave_unique(s: int, n: int) -> int:
	return wave_unique_a(s, n) + wave_unique_b(s, n)


static func wave_unique_a(s: int, n: int) -> int:
	return _UNIQ_A[_w(s, n)]


static func wave_unique_b(s: int, n: int) -> int:
	return _UNIQ_B[_w(s, n)]


static func wave_elite(s: int, n: int) -> bool:
	return _ELITE[_w(s, n)] == 1


## 本波压轴精英的种类（EnemyKind.E）；非精英波返回 0（占位）。
##   调用方应先判 `wave_elite` 再取种类 —— 但本函数对非精英波也安全返回 0。
static func wave_elite_type(s: int, n: int) -> int:
	return _ELITE_TYPE[_w(s, n)]


static func wave_gap(s: int, n: int) -> float:
	return _GAP[_w(s, n)]


## 该波是否为**驻留阵地波**（背景降速 + 敌人屏内跃迁入场），见 `_HOLD` 表头注释。
static func wave_hold(s: int, n: int) -> bool:
	return _HOLD[_w(s, n)] == 1


## 本关战将弹幕的色数（1 = 单色；色序的排法见 `_ELITE_HUE` 表头注释）
static func elite_hue_n(s: int) -> int:
	return _ELITE_HUE[_i(s)]


## 本关第一种独有怪的种类；无则返回 NO_KIND
static func unique_kind_a(s: int) -> int:
	var k := _kind_a_of(_i(s))
	return k


## 本关第二种独有怪的种类；无则返回 NO_KIND
static func unique_kind_b(s: int) -> int:
	return _kind_b_of(_i(s))


static func _kind_a_of(i: int) -> int:
	match i:
		0:
			return EnemyKind.K.DISMANTLER     # L1 拆解者
		1:
			return EnemyKind.K.DEFECTOR       # L2 变节者
		2:
			return EnemyKind.K.PHALANX        # L3 列阵者
		3:
			return EnemyKind.K.LAYER          # L4 敷设者
		_:
			return EnemyKind.K.MARTYR         # L5 殉爆者


static func _kind_b_of(i: int) -> int:
	match i:
		3:
			return EnemyKind.K.SIPHON         # L4 虹吸者
		4:
			return EnemyKind.K.PHASER         # L5 相位者
		_:
			return NO_KIND


## 本关会出现的独有怪种类列表（供 Spawner / 自测遍历）
static func unique_kinds(s: int) -> Array[int]:
	var out: Array[int] = []
	var a := unique_kind_a(s)
	if a != NO_KIND:
		out.append(a)
	var b := unique_kind_b(s)
	if b != NO_KIND:
		out.append(b)
	return out


static func elite_count(s: int) -> int:
	var k := 0
	for n in waves(s):
		if wave_elite(s, n):
			k += 1
	return k


## 本波出怪格数（目标色 + 骚扰色 + 独有怪格；列阵者 1 组算 1 格）
static func wave_slots(s: int, n: int) -> int:
	return wave_targets(s, n) + wave_harass(s, n) + wave_unique(s, n)


## 本关出怪格数合计（不含战将、不占配额的殉爆者另算）
static func slot_total(s: int) -> int:
	var t := 0
	for n in waves(s):
		t += wave_slots(s, n)
	return t


# ---------------------------------------------------------------- 强度缩放
static func stage_hp_scale(s: int) -> float:
	return LEVEL_HP[_i(s)]


## WAVE_HP(w, N) = 1.00 + 0.30 × (w-1)/(N-1)
static func wave_hp_mul(s: int, n: int) -> float:
	var n_waves := waves(s)
	if n_waves <= 1:
		return 1.0
	return 1.0 + _HP_MAX_STEP * float(clampi(n, 1, n_waves) - 1) / float(n_waves - 1)


## 最终 hp_scale = LEVEL_HP × WAVE_HP；极值 = 1.75 × 1.30 = 2.275
static func wave_hp_scale(s: int, n: int) -> float:
	return stage_hp_scale(s) * wave_hp_mul(s, n)


# ---------------------------------------------------------------- 掉落 / 清场
static func drop_chance(s: int) -> float:
	return _DROP[_i(s)]


## 每波结束后额外刷新的道具数
static func wave_drop(s: int) -> int:
	return 1


static func clear_guard(s: int, elite: bool) -> float:
	return _GUARD_ELITE[_i(s)] if elite else _GUARD_PLAIN[_i(s)]


# ---------------------------------------------------------------- 计分 / 品阶
## 落账满分（设计 §G.3 终值，非本文件推导）
static func theoretical_max(s: int) -> int:
	return _MAX[_i(s)]


static func rank_copper(s: int) -> int:
	return _RANK_COPPER[_i(s)]


static func rank_silver(s: int) -> int:
	return _RANK_SILVER[_i(s)]


static func rank_gold(s: int) -> int:
	return _RANK_GOLD[_i(s)]


## [铜, 银, 金] 三档阈值（PackedInt32Array 不能在 const 里构建，故在 static func 里建）
static func rank_thresholds(s: int) -> PackedInt32Array:
	return PackedInt32Array([rank_copper(s), rank_silver(s), rank_gold(s)])


## 品阶级数：0 铁 / 1 铜 / 2 银 / 3 金
static func rank_index(s: int, score: int) -> int:
	if score >= rank_gold(s):
		return 3
	if score >= rank_silver(s):
		return 2
	if score >= rank_copper(s):
		return 1
	return 0


## 完成度（0.0~1.0+）—— 结算界面「完成度 xx%」一行，用来解释品阶不可跨关比较
static func completion_ratio(s: int, score: int) -> float:
	var m := theoretical_max(s)
	if m <= 0:
		return 0.0
	return float(score) / float(m)


static func rank_cn(s: int, score: int) -> String:
	match rank_index(s, score):
		3:
			return "金勋 · 星帅"
		2:
			return "银勋 · 星将"
		1:
			return "铜勋 · 星尉"
		_:
			return "铁勋 · 星兵"
