class_name EliteBase
extends Damageable
## ---------------------------------------------------------------
## EliteBase —— 星盗精英怪的共同基类（纯骨架，不含任何具体机制）
##
## 2026-09-22 主理人要求「增加一些精英怪」，在既有【星盗战将】（Elite）之外
## 新增三只机制各异的精英：弹幕堡垒将（EliteBastion）· 增殖指挥将（EliteSwarm）·
## 护盾冲锋将（EliteAegis）。四只精英机制完全不同（破罩 / 弹幕墙 / 召唤 / 朝向护盾），
## 若塞进一个类里用 if 分支，会长出四个状态机 —— 故按项目既有范式
## （独有怪走 EnemyBrain 分发 / Boss4 拆子类）各自成类，只共享这层骨架。
##
## 骨架只承载「四只精英都长一个样」的部分：
##   · killed 信号（pos / color / score）—— Level 连同一个 _on_elite_killed
##   · 公共字段：world / player_ref / stage / color / hp / max_hp / score / dead
##   · _pop 飘字（挂 world 而非自身：自身 queue_free 时挂在身上的池化 Fx 会连带被 free，
##     池里却还留着引用 —— 下次取出就是已释放对象。这条坑 Elite 早就踩过并修了）
##   · _bar 头顶血条（四只共用同一套条）
##
## 不含 _process / _draw / hit / 运动 / 开火 —— 那些是各子类自己的机制，一律下沉。
## Damageable.hit() 的默认实现会 push_warning，子类不重写就会暴露 —— 是刻意的。
##
## 可行性铁律（四只一律遵守）：任何「必须特定颜色才能破」的色防，
##   其颜色只能从玩家已选两件战甲 S 中抽取。凭空给个玩家没带的色 = 破防死局 = 设计事故。
## ---------------------------------------------------------------

signal killed(pos: Vector2, c: int, sc: int)

## 碰撞半径（精英机剪影壳，四只共用；造型外突允许探出圆外）
## 碰撞半径取自 EnemyCfg（四只精英共用）。

var color: int = Game.RED
var hp := 0
var max_hp := 0
var score := 0
var dead := false
## 所属关卡（1-based）；由 Level 在 add_child 前注入（供关卡级访问器取用，如 bullet_scale）
var stage: int = 1
## 由 Level 显式注入：弹幕与特效的挂载容器（禁用 get_parent()）
var world: Node2D = null
var player_ref: Player = null
## 玩家已选两件战甲色 S —— 一切「必须打破的色防」只从这里抽。
## 四只精英都要用，故声明在基类；子类**不要**再声明同名变量（会触发 shadow 警告）。
var player_armors: Array[int] = []


## 头顶本体血条（四只精英共用；力场条由各子类自行叠加）
func _bar(x: float, y: float, w: float, h: float, ratio: float, col: Color) -> void:
	draw_rect(Rect2(x - 1.0, y - 1.0, w + 2.0, h + 2.0), Color(0.02, 0.02, 0.05, 0.55))
	draw_rect(Rect2(x, y, w, h), Color(0.05, 0.05, 0.10, 0.60))
	draw_rect(Rect2(x, y, maxf(0.0, w) * clampf(ratio, 0.0, 1.0), h), col)


## 飘字挂在 world 而不是自己身上（理由见类头注释）
func _pop(v: int, col: Color, size: int) -> void:
	var host := world if (world != null and is_instance_valid(world)) else self
	Fx.pop(host, position + Vector2(0.0, -44.0), str(v), col, size)


## 朝玩家的归一化方向（无玩家时默认向左）—— 四只精英的瞄准共用
func _aim() -> Vector2:
	if player_ref != null and is_instance_valid(player_ref):
		return (player_ref.position - position).normalized()
	return Vector2.LEFT


## 发射一枚弹幕（world 显式注入，走 Danmaku 对象池）—— 四只精英的开火共用
func _fire_shot(c: int, dirv: Vector2, sp: float, r: float, dmg: int) -> void:
	if world == null:
		return
	var dir := dirv.normalized()
	Danmaku.spawn(world, c, position + dir * (EnemyCfg.ELITE_R + 6.0), dir * sp, dmg, r)
