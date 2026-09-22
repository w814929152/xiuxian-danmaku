class_name Spawner
extends RefCounted
## ---------------------------------------------------------------
## Spawner —— 敌人生成工厂（纯静态）
##
## 唯一出怪入口。职责：new() → world 显式注入 → add_child → setup() 完整重置。
## 工厂**不接收回调入参**，因此 killed 信号仍由调用方（Level）连接。
##
## 铁律：world 一律显式注入，禁用 get_parent()。
## ---------------------------------------------------------------


## 生成一只敌人并挂入 world。
## [param kind]   EnemyKind.K：GRUNT 或 7 种独有怪。
## [param color]  四色之一（由 Level 从 S / S' 统一分配，工厂不自拟）。
## [param pat]    运动模式（GRUNT 用；独有怪忽略，行为走 EnemyBrain）。
## [param y]      出场纵坐标。
## [param hp_scale] 强度缩放（LEVEL_HP × WAVE_HP）。
## [param stage]  所属关卡（1-based）。
static func enemy(world: Node2D, kind: int, color: int, pat: String, y: float,
		hp_scale: float, stage: int) -> Enemy:
	if world == null:
		return null
	var e := Enemy.new()
	e.world = world
	e.kind = kind
	e.stage = stage
	# 中性色单位：不占配额、不参与换甲免疫判定。当前无中性色单位（殉爆者已按 §J.8-2 改为带色 ∈ S），
	# 此分支保留作为「不引入第五种属性色」红线的判据兜底
	if EnemyKind.is_neutral(kind):
		e.no_block_clear = false
	e._phase = randf() * TAU
	world.add_child(e)
	e.setup(color, pat, y, hp_scale)
	# 独有怪：覆盖血量倍率 / 分值（GRUNT 保持 setup 内的四色数值，一行不动）
	if kind != EnemyKind.K.GRUNT:
		e.hp = int(roundf(float(e.hp) * EnemyKind.hp_mul(kind)))
		e.max_hp = e.hp
		e.score = EnemyKind.score_of(kind)
	return e
