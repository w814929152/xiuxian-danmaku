class_name EnemyKind
extends RefCounted
## ---------------------------------------------------------------
## 星盗种类注册表 —— 1 种通用怪 + 7 种独有怪
##
## 数值 / 机制来源：`design/levels/01-五关设计总纲.md` §C（终裁：7 种全做，不裁剪）。
## 单独成文件：让 StageCfg（纯数据）与 Spawner 可以引用它，而不必依赖 Enemy（一个 Area2D）。
##
## 配额（quota）决定这一格占的是哪种色：
##   TARGET = 目标色（∈ S，逼换甲）· HARASS = 骚扰色（∈ S'，逼走位）· NONE = 不占配额
## ---------------------------------------------------------------

enum K {
	GRUNT = 0,        # 通用星盗（五关都有）：straight / sine / hover / dive + 按色开火
	DISMANTLER = 1,   # ① 拆解者 · 破片浮游机（L1）死亡分裂 2 小片 + 六向抛破片
	DEFECTOR = 2,     # ② 变节者 · 棱晶换色机（L2）核心在 S 两色间每 3.5s 轮换 + 换色破绽
	PHALANX = 3,      # ③ 列阵者 · 方阵炮舰（L3）3 艘成墙齐射，留一条规律平移的安全缝
	LAYER = 4,        # ④ 敷设者 · 引力雷舰（L4）横穿全屏布设静态引力雷，8s 自毁
	SIPHON = 5,       # ⑤ 虹吸者 · 反相无人机（L4）反向共振：吸收某色并回血
	MARTYR = 6,       # ⑥ 殉爆者 · 冲撞自杀舰（L5）高速直冲，死/撞都爆半径 150 冲击环（色 ∈ S 占目标配额；冲撞与冲击环走物理通道，换甲挡不住）
	PHASER = 7,       # ⑦ 相位者 · 折跃刺客（L5）每 2.6s 无敌 1.1s + 折跃到玩家脸上
}

## 占哪种色的配额
enum Q {
	NONE = 0,
	TARGET = 1,
	HARASS = 2,
}

# ============================ 硬闸（设计 §H.2 第 6 条：超上限不生成，不排队）============================
## 分身（子核心 / 小片）上限
const MAX_CLONES := 2
## 增援（召唤物）上限
const MAX_REINFORCE := 6
## 引力雷上限
const MAX_MINES := 8

## 横幅简称（设计 §C 各条「横幅简称」）
const SHORT_CN := [
	"星盗", "拆 解 者", "变 节 者", "列 阵 者",
	"敷 设 者", "虹 吸 者", "殉 爆 者", "相 位 者",
]
## 全名
const CN := [
	"星盗",
	"拆解者 · 破片浮游机",
	"变节者 · 棱晶换色机",
	"列阵者 · 方阵炮舰",
	"敷设者 · 引力雷舰",
	"虹吸者 · 反相无人机",
	"殉爆者 · 冲撞自杀舰",
	"相位者 · 折跃刺客",
]
## 击杀分值（设计 §G.2）。列阵者**按组**计 300，不按艘算
const SCORE := [100, 150, 250, 300, 250, 350, 200, 300]
## 血量倍率（相对同色通用星盗，设计 §C 各条「建议血量倍率」）
const HP_MUL := [1.00, 1.60, 2.20, 3.00, 2.00, 1.80, 1.20, 2.40]
## 占哪种色的配额（GRUNT 由波次表决定）。殉爆者占 TARGET —— 它**带色**，只是冲撞/冲击环走物理通道
const QUOTA := [0, 1, 1, 2, 2, 1, 1, 1]
## 是否中性色（不与任何战甲共振、不被任何战甲免疫）。当前**无**中性色单位 —— 殉爆者已按 §J.8-2 改为带色。保留此位是为了守住「不引入第五种属性色」这条红线的判据
const NEUTRAL := [false, false, false, false, false, false, false, false]
## 所属关卡（0 = 五关通用）
const STAGE_OF := [0, 1, 2, 3, 4, 4, 5, 5]

## ① 拆解者分裂出的小片分值（不再二次分裂，标记 no_block_clear）
const SHARD_SCORE := 50
## ④ 敷设者布下的雷：不给分（否则玩家会为了分去刷雷，与「空间管理」的设计意图相反）
const MINE_SCORE := 0


static func cn(k: int) -> String:
	return CN[_idx(k)]


static func short_cn(k: int) -> String:
	return SHORT_CN[_idx(k)]


static func score_of(k: int) -> int:
	return SCORE[_idx(k)]


static func hp_mul(k: int) -> float:
	return HP_MUL[_idx(k)]


static func quota(k: int) -> int:
	return QUOTA[_idx(k)]


static func is_neutral(k: int) -> bool:
	return NEUTRAL[_idx(k)]


static func stage_of(k: int) -> int:
	return STAGE_OF[_idx(k)]


## 越界一律收敛到通用星盗 —— 绝不返回无效下标
static func _idx(k: int) -> int:
	return clampi(k, 0, CN.size() - 1)
