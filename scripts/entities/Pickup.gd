class_name Pickup
extends Area2D
## ---------------------------------------------------------------
## 漂浮道具 · 掉落物
##
## 两个来源（都由 Level 发起）：
##   1. 击杀星盗按概率掉落（DROP_CHANCE = 18%，实测 18.65%）
##   2. 每波星袭结束刷新 WAVE_DROP = 1 个
## 每局合计约 3.6（斩敌）+ 每波固定 1 个 ≈ 6~9 个（波数随关卡递增：L1=3 波 … L4/L5=5 波）。
## 波次刷新原来是 2 个 —— 固定送的占总量的大半，反而把「斩敌出不出货」稀释掉了，收到 1 个。
##
## 不走对象池：一局只掉十来个，池化收益为零，反而多一层 reset 要维护。
## 碰撞层 bit4「道具」—— 玩家 mask 加了 bit4 才吃得到，
## 光刃（mask=bit2 敌人）与敌弹（mask=bit0 玩家）都不会误触它。
## ---------------------------------------------------------------

enum T { HEAL, MULTI, ATK, INVINC }

## 数值 / 文案 / 配色一律取自 PickupCfg（效果数值在 PlayerCfg）。
## 改道具请去那两个文件 —— 本文件只留逻辑。

var kind: int = T.HEAL
## 由 Level 显式注入：拾取特效的挂载容器
var world: Node2D = null
var _t := 0.0
var _base_y := 360.0
var _alive := false
var _spin := 0.0


## 唯一生成入口。pos 为掉落点（通常是星盗的死亡位置）。
##
## 入树要延后一帧：掉落常常发生在**物理回调里**
## （光刃命中 -> Sword._on_area_entered -> Enemy._die -> Level 掉落），
## 那时新建 Area2D 并改碰撞层会报
## "Can't change this state while flushing queries. Use call_deferred() ..."。
## 与弹幕 / 光刃归还时用 call_deferred 摘除是同一条规矩：
## **别在物理回调里动碰撞体**。这个坑只在真的打死怪时才走得到，很容易漏。
static func spawn(parent: Node2D, k: int, pos: Vector2) -> Pickup:
	if parent == null or not is_instance_valid(parent):
		return null
	var p := Pickup.new()
	p.world = parent
	p.kind = k
	p._base_y = clampf(pos.y, 70.0, Game.VIEW_H - 70.0)
	p.position = Vector2(clampf(pos.x, 40.0, Game.VIEW_W - 40.0), p._base_y)
	p._alive = true
	p._enter.call_deferred(parent)
	return p


func _enter(parent: Node2D) -> void:
	if not is_instance_valid(parent):
		queue_free()      # 关卡已经没了，这个道具也不必存在
		return
	parent.add_child(self)


## 按权重随机一种（Level 掉落时用）
static func random_kind() -> int:
	var total := 0
	for w in PickupCfg.WEIGHT:
		total += int(w)
	var roll := randi() % total
	var acc := 0
	for i in PickupCfg.N:
		acc += int(PickupCfg.WEIGHT[i])
		if roll < acc:
			return i
	return T.HEAL


func _ready() -> void:
	collision_layer = 16   # bit4 道具
	collision_mask = 1     # bit0 玩家
	z_index = 15
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = PickupCfg.R
	cs.shape = sh
	add_child(cs)
	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	if not _alive:
		return
	_t += delta
	_spin += delta
	position.x += PickupCfg.DRIFT * delta
	position.y = _base_y + sin(_t * PickupCfg.BOB_F * TAU) * PickupCfg.BOB_A
	if position.x < -60.0 or _t >= PickupCfg.LIFE:
		queue_free()
		return
	queue_redraw()


## 由道具自己去认玩家：Player 一侧不必为每种道具各开一个分支，
## 效果是「道具施加给玩家」，责任本来就在道具这边。
func _on_area_entered(a: Area2D) -> void:
	if not _alive:
		return
	if not (a is Player):
		return
	var p := a as Player
	if not is_instance_valid(p) or not p.alive:
		return
	_taken(p)


func _taken(p: Player) -> void:
	_alive = false
	var gain := p.apply_pickup(kind)
	Fx.ring(world, position, PickupCfg.COL[kind], 8.0, 56.0, 0.36, 6.0)
	Fx.burst(world, position, PickupCfg.COL[kind], 12, 220.0, 0.45)
	# gain 为空串表示已满 / 无需提示（例如满血吃修复包）
	if gain != "":
		Fx.pop(world, position + Vector2(0.0, -26.0), gain, PickupCfg.COL[kind], 19, 0.9)
	queue_free()


func _draw() -> void:
	var c: Color = PickupCfg.COL[kind]
	var k: Color = Color(1.0, 1.0, 1.0, 0.92)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)

	# 超时前的闪烁提示
	var a := 1.0
	if _t > PickupCfg.LIFE - PickupCfg.FADE:
		a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 22.0))
	modulate.a = a

	# 外晕 + 光环
	draw_circle(Vector2.ZERO, 26.0 + 4.0 * pulse, Color(c.r, c.g, c.b, 0.14))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.55), 2.4, true)

	# 器形：旋转的菱形玉牌（四种道具共用底形，靠颜色与字面区分）
	var q := PackedVector2Array([
		Vector2(0.0, -17.0), Vector2(17.0, 0.0),
		Vector2(0.0, 17.0), Vector2(-17.0, 0.0)
	])
	draw_set_transform_matrix(Transform2D(_spin * 0.9, Vector2.ZERO))
	draw_colored_polygon(q, Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, 0.92))
	var qr := PackedVector2Array(q)
	qr.append(q[0])
	draw_polyline(qr, c, 2.4, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	# 内芯 + 一字
	draw_circle(Vector2.ZERO, 9.0, Color(c.r, c.g, c.b, 0.30))
	DrawUtil.txt(self, PickupCfg.GLYPH[kind], Vector2(0.0, 7.0), 17, k,
		HORIZONTAL_ALIGNMENT_CENTER)
