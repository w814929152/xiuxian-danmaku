class_name Damageable
extends Area2D
## 可被飞剑伤害的目标 —— Enemy 与 Boss 的共同抽象
##
## 用途：让 Sword 只面向基类判定命中一次，不再写 `a is Enemy / a is Boss` 两条分支。
## 子类必须重写 hit()，否则会收到一条警告（不静默吞伤害）。


## [param dmg] 原始伤害；[param c] 飞剑颜色（用于同源共振 / 属性法罩判定）
func hit(_dmg: int, _c: int) -> void:
	push_warning("Damageable.hit() 未实现：子类必须重写")
