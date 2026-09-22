class_name Sword
extends Area2D
## 玩家光刃（颜色 = 当前战甲色）
##
## Phase 4：
##   · 走 Pool 对象池（电浆剑甲每秒约 20 把）
##   · 位移迁到 _physics_process：980 px/s 的速度在 30fps 下单帧跨 32px，
##     原来放在 _process 里会直接跨过星盗（半径 19）造成穿模

const POOL_KEY := "sword"

var color: int = Game.WHITE
var damage := 10
## 由生成方（Player）注入：命中特效的挂载容器
var world: Node2D = null
var vel := Vector2(980.0, 0.0)
var life := 2.2
var _t := 0.0
var _alive := false
## 像素 sprite（白模共享纹理，modulate 染成战甲色）
var _art: Sprite2D = null


static func _make() -> Node:
	return Sword.new()


## 唯一生成入口：优先从池中取，池空才新建
## size > 1 表示拾了增幅核心 —— 整节点放大，剑身与碰撞体一起变粗
static func spawn(parent: Node2D, c: int, p: Vector2, d: int, v: Vector2,
		size: float = 1.0) -> Sword:
	var s := Pool.acquire(POOL_KEY, parent, Sword._make) as Sword
	if s == null:
		return null
	s.world = parent
	s._alive = true
	s.setup(c, p, d, v, size)
	return s


func _ready() -> void:
	collision_layer = 2   # bit1: 玩家子弹
	collision_mask = 4    # bit2: 敌人
	z_index = 20
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(34.0, 10.0)
	cs.shape = sh
	add_child(cs)
	_art = ArtAssets.make_sprite("sword_player")
	add_child(_art)
	area_entered.connect(_on_area_entered)


## 池化复用：必须覆盖上一把剑留下的全部状态（含 scale —— 增幅核心会放大剑身；
## 含 _art.modulate —— 白模按战甲色染色）
func setup(c: int, p: Vector2, d: int, v: Vector2, size: float = 1.0) -> void:
	color = c
	position = p
	damage = d
	vel = v
	life = 2.2
	_t = 0.0
	rotation = 0.0
	scale = Vector2(size, size)
	modulate = Color.WHITE
	if _art != null:
		_art.modulate = Game.COLOR_MAIN[c]
	visible = true


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_t += delta
	position += vel * delta
	life -= delta
	if life <= 0.0 or position.x > Game.VIEW_W + 80.0 or position.x < -80.0:
		_kill()


## 一帧内可能同时压到多个目标（敌群重叠 / Boss 与小怪重合），
## 命中后立即归还，必须挡住后续重入。
func _on_area_entered(a: Area2D) -> void:
	if not _alive:
		return
	if not (a is Damageable):
		return
	(a as Damageable).hit(damage, color)
	Fx.burst(world, position, Game.COLOR_GLOW[color], 5, 130.0, 0.25)
	_kill()


## 归还对象池（不 queue_free）
## 同 Danmaku：Area2D 不能在物理回调里直接摘除，延后到帧末。
func _kill() -> void:
	if not _alive:
		return
	_alive = false
	visible = false
	_detach.call_deferred()


func _detach() -> void:
	Pool.release(POOL_KEY, self)
