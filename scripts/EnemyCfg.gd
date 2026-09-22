class_name EnemyCfg
extends RefCounted
## ---------------------------------------------------------------
## 敌人数值 —— 星盗战将 / 独有怪 / 敌弹
##
## 喽啰的血量、射速、波次编排在 `StageCfg`（逐关缩放），Boss 在 `BossCfg`。
## 这里只放**与关卡无关的固定数值**：战将本体、独有怪的机制时长、敌弹剪影。
##
## 独有怪编号沿用设计 §C.5：① 拆解者 ② 变节者 ④ 敷设者 ⑥ 殉爆者 ⑦ 相位者。
## 本文件不自拟数值 —— 与 `design/` 文档冲突时以文档为准并回问主理人。
## ---------------------------------------------------------------

# ============================ 星盗战将（Elite）============================
## 本体生命（× hp_scale，波次系数在 StageCfg）
const ELITE_BASE_HP := 480
## 单层力场值（× hp_scale）
const ELITE_WARD_HP := 150
## 力场总层数：破一层虚弱一次，可重铸次数 = 层数 - 1
const ELITE_WARD_LAYERS := 2
## 力场存续时，异色光刃只剩这个比例（旗舰护罩是 0.60，这里更狠 —— 逼你换甲）
const ELITE_WARD_RESIST := 0.35
## 破力场后的虚弱期（秒）
const ELITE_BROKEN_TIME := 4.5
const ELITE_SPEED := 150.0
## 基础出手间隔（还会再按弹幕密度放慢）
const ELITE_FIRE_CD := 1.05
## 斩杀奖励
const ELITE_SCORE := 800
## 碰撞半径（主体剪影壳 ≤ r32，角 / 尾 / 顶冠在圆外属造型）
const ELITE_R := 34.0

# ============================ 护盾冲锋将（EliteAegis）============================
## 正面挂一面朝向护盾，只有绕到侧 / 后方才打得到本体（考走位绕背 + 换甲）
const AEGIS_BASE_HP := 720
const AEGIS_SHIELD_HP := 260
const AEGIS_SHIELD_LAYERS := 1
## 护盾存续时异色光刃的衰减（与战将同为 0.35，但两者是两套机制，各留一个名）
const AEGIS_WARD_RESIST := 0.35
const AEGIS_BROKEN_TIME := 4.0
## 护盾锥的半角（度）：覆盖朝向玩家的那一侧
const AEGIS_SHIELD_ARC_DEG := 55.0
const AEGIS_SPEED := 110.0
const AEGIS_CHARGE_MUL := 2.4      # 冲锋时的移速倍率
const AEGIS_CHARGE_CD := 3.2       # 两次冲锋的间隔
const AEGIS_CHARGE_TIME := 0.55    # 一次冲锋的持续
const AEGIS_FIRE_CD := 1.5
const AEGIS_SCORE := 900

# ============================ 弹幕堡垒将（EliteBastion）============================
## 无护罩、无色的厚甲炮台：纯 DPS + 弹幕走位检验，任意色都能全额打
const BASTION_BASE_HP := 900
const BASTION_SPEED := 90.0
const BASTION_FIRE_CD := 1.35
const BASTION_SCORE := 900

# ============================ 增殖指挥将（EliteSwarm）============================
## 周期性召唤同色喽啰增援：本体躲在召唤物后面，考清场优先级
const SWARM_BASE_HP := 620
const SWARM_SPEED := 100.0
const SWARM_FIRE_CD := 1.6
const SWARM_SUMMON_CD := 4.5
const SWARM_SUMMON_BATCH := 2
const SWARM_SCORE := 900
## 本体每次召唤时的自愈比例（占 max_hp）
const SWARM_HEAL_RATIO := 0.02

# ============================ 敌弹 ============================
## 灵纹能量珠的剪影基准半径。判定半径是 9，视觉刻意略大于判定（所见即所中
## 的反向宽容），改这里要同步确认 `tools/build_danmaku.py` 里的烘焙断言。
const DANMAKU_ART_BASE_R := 9.0

# ============================ 独有怪 ============================
## ② 变节者：核心在玩家两件战甲色之间轮换的间隔（秒）
const DEFECTOR_SWAP := 3.5
## ② 变节者：换色瞬间的破绽窗口（秒）—— 此间任意色 ×2
const DEFECTOR_WINDOW := 0.6
## ① 拆解者：死亡分裂出的小片数
const DISMANTLER_SHARDS := 2
## ⑦ 相位者：折跃 + 无敌的节奏
const PHASER_CYCLE := 2.6
const PHASER_INVULN := 1.1
## ⑥ 殉爆者 · 冲撞自杀舰：贴到这个距离内即引爆
const MARTYR_CONTACT := 26.0
## ⑥ 殉爆者：冲撞伤害。**物理通道** —— 直接扣血，不经同色吸收 / 闪避判定
const MARTYR_DMG := 20
## ⑥ 殉爆者：自爆冲击环伤害（设计 §C.5 ⑥：半径 150，伤害 15，物理通道）
const MARTYR_SHOCK_DMG := 15
## ⑥ 殉爆者：自爆抛出的破片数（继承本体色，可被同色甲免疫）
const MARTYR_SHARDS := 8
# ============================ 引力雷（④ 敷设者 / L5 终焉号相④ 共用一件）============================
## 上一版这个 8.0 在 EnemyBrain 与 BossMine 里各写了一份，改一处漏一处。
const MINE_R := 16.0           # 碰撞半径 / 器形半径
const MINE_LIFE := 8.0         # 存在时长：8s 自毁（设计 §D L5 相④）
const MINE_ARM := 0.55         # 布设后的保险期，这段时间不判定玩家（防贴脸瞬爆）
const MINE_BLAST_R := 150.0    # 引爆半径
const MINE_DMG := 12           # 引爆伤害
const MINE_FADE := 1.2         # 最后这么多秒开始闪烁预警
