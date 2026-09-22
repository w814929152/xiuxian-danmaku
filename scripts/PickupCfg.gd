class_name PickupCfg
extends RefCounted
## ---------------------------------------------------------------
## 道具配置 —— 种类文案 / 配色 / 掉落权重 / 漂浮与存在时长
##
## ⚠ 只管「道具自己长什么样、怎么掉」；**数值效果不在这里** ——
## 回复量 / 增幅步长 / 无敌时长一律在 `PlayerCfg`（作用对象是玩家），
## 两边各写一份就是上次「改了 ATK_STEP 还要手改飘字」的根源。
##
## 拾取飘字走 `tip()` 现场从 PlayerCfg 拼出来：改了配置，文案自动跟着变。
## `tip()` 的下标必须与 `Pickup.T` 的顺序一致（HEAL / MULTI / ATK / INVINC），
## 这条由 SelfTest 的「飘字与配置同源」断言守着。
## ---------------------------------------------------------------

const N := 4

## 名称 / 器形上的一字
const CN := ["修复包", "刃影模块", "增幅核心", "力场罩"]
const GLYPH := ["修", "影", "增", "力"]

## 主色（与 CN 同序）：修复 · 青绿 / 刃影 · 天蓝 / 增幅 · 橙 / 力场 · 明黄
const COL := [
	Color(0.42, 0.95, 0.55),
	Color(0.45, 0.80, 1.00),
	Color(1.00, 0.62, 0.22),
	Color(1.00, 0.92, 0.45),
]

## 掉落权重（相对值，不必归一）—— 修复包略高，力场罩略低
const WEIGHT: Array[int] = [30, 24, 26, 20]

const R := 21.0            # 拾取半径
const DRIFT := -58.0       # 随场景一起向左漂
const BOB_A := 13.0        # 上下浮动幅度
const BOB_F := 1.15        # 上下浮动频率
const LIFE := 15.0         # 存在时长，超时淡出
const FADE := 1.5          # 最后这么多秒开始闪烁淡出

## 掉落的另外两个来源在关卡侧：`StageCfg.drop_chance(s)`（斩敌概率）
## 与 `StageCfg.wave_drop(s)`（每波刷新数）—— 别在 Level 里再写一份。


## 拾取飘字。数值全部取自 PlayerCfg，改配置即可，不用再来改文案。
static func tip(t: int) -> String:
	match t:
		0:
			return "生命 +%d" % PlayerCfg.HEAL_AMOUNT
		1:
			return "弹道 +1"
		2:
			return "攻击 +%d%%" % int(roundf(PlayerCfg.ATK_STEP * 100.0))
		_:
			return "无敌 %.0f 秒" % PlayerCfg.INVINC_TIME
