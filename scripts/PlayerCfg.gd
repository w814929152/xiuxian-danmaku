class_name PlayerCfg
extends RefCounted
## ---------------------------------------------------------------
## 玩家 / 道具增益数值 —— 全局唯一来源
##
## 以前这些旋钮散在 `Player.gd` 里（25 个 const）：改一个「增幅核心 +10%」
## 要动 Player / Pickup / HelpScreen / README / SelfTest 五处，还容易漏。
## 现在一律从这里读，实体文件只留逻辑、不留数字。
##
## 约定（与 StageCfg / BossCfg 一致）：
##   · 只放一维、字面量同构的表；const 里不套 Dictionary / 复杂结构；
##   · 派生量走「带返回类型的静态访问器」（见文件末尾 atk_mul / atk_vis），
##     别在各处自己乘一遍 —— 否则改了公式又要全局搜；
##   · 本文件不自拟数值 —— 与 `design/` 文档冲突时以文档为准并回问主理人。
## ---------------------------------------------------------------

# ============================ 本体 ============================
const MAX_HP := 100
## 光子护盾上限。护盾**不会**自动回复 —— 唯一充能入口是穿着光子盾甲（白）
## 吞下一枚光子弹（同色吸收），见 Player.take_hit()。
const SHIELD_MAX := 20
## 光子盾甲每吸收一枚光子弹的充能量（钳到 SHIELD_MAX 为止）
const SHIELD_GAIN := 10
const BASE_SPEED := 340.0
const BLUE_MUL := 1.5          # 寒霜疾甲：移速 +50%
## 寒霜疾甲：吞下一枚寒霜弹后获得这么久的闪避，期间不承受任何**弹幕**伤害。
## 只挡走 take_hit() 的弹幕通道 —— 殉爆者冲撞 / 冲击环是刻意绕过同色免疫的
## 物理通道（EnemyBrain 里直接扣 hp），不接入本状态。
const DODGE_TIME := 0.5
## 闪避期的机体透明度基准：整体变淡，只叠极轻呼吸。
## 不做高频闪烁 —— 闪避只有 DODGE_TIME 秒，闪起来玩家根本读不清自己在哪里。
const DODGE_ALPHA := 0.28
const DODGE_BREATH := 0.06
const HIT_R := 11.0
## 光刃单发基础伤害：电浆剑甲是双排细刃，其余是单排
const SWORD_DMG_RED := 8
const SWORD_DMG := 10
const FIRE_CD := 0.105
const SWAP_CD := 0.20
const INVULN := 0.85

# ============================ 引力束甲 · 引力束 ============================
## 每秒伤害（还会再乘 atk_mul）
const BEAM_DPS := 120.0
const BEAM_TICK := 0.2         # 结算间隔（秒）
const BEAM_HALF_H := 9.0       # 光柱半高（增幅核心会整体加粗）
## 多道引力束（刃影模块叠出来的）之间的竖直间距基准。
## 取值对着**视觉宽度**定：Beam._draw() 最外层线宽约 26~30px，
## 取 28 让相邻两道刚好相接 —— 读作「挨着的一束」而不是「分开的两道」。
## ⚠️ 已知取舍：判定（BEAM_HALF_H*2 = 18px）比视觉窄，所以间距按视觉取 28 时
##    判定仍有约 10px 缝隙（改前的 46px 间距缝隙是 28px，已大幅收窄）。
##    要让判定完全无缝得把间距压到 ≤18，那样视觉会重叠约 10px、糊成一束，
##    与「多道」的读感冲突 —— 故以视觉为准。
## 该值会再乘 beam_width()（增幅核心加粗，最大约 1.88 倍），见 Player._beam_y()。
const BEAM_GAP := 28.0

# ============================ 引力束甲 · 过热 ============================
const HEAT_MAX := 100.0        # 过热值上限，满则无法出束
const HEAT_RISE := 20.0        # 出束时每秒累积
const HEAT_COOL_DELAY := 0.5   # 停火多久后开始散热
const HEAT_COOL := 30.0        # 散热速度（每秒）
const HEAT_VENT := 30.0        # 触到引力（黄）弹时立刻散去
## 解锁阈值：过热后必须散到这个数值以下才能重新出束。
## 不加这道闸门的话，按住不放会卡在「锁 0.5 秒 -> 亮 1 帧 -> 再锁」的抖动里
## （升温远快于每帧的散热量，占空比只剩约 5%），引力束等于废掉。
const HEAT_REARM := 60.0

# ============================ 道具增益 ============================
const HEAL_AMOUNT := 20        # 修复包：回复生命
const MULTI_MAX := 3           # 刃影模块：最多再叠 3 排弹道
const ATK_STEP := 0.10         # 增幅核心：每层 +10%
const ATK_MAX := 4             # 增幅核心：最多叠 4 层（+40%）
const INVINC_TIME := 6.0       # 力场罩：无敌 6 秒
## 增幅核心的视觉强度：光刃放大 / 引力束加粗都用这个系数
const ATK_VIS := 0.22

# ============================ 派生量（静态访问器）============================

## 攻击力倍率（增幅核心层数 × ATK_STEP）。HUD / 伤害结算 / 自测都走这一处。
static func atk_mul(up: int) -> float:
	return 1.0 + ATK_STEP * float(up)


## 满叠时的攻击力倍率（层数封顶 ATK_MAX）
static func atk_mul_max() -> float:
	return atk_mul(ATK_MAX)


## 增幅核心的视觉强度：层数越多，光刃越大 / 引力束越粗
static func atk_vis(up: int) -> float:
	return 1.0 + ATK_VIS * float(up)
