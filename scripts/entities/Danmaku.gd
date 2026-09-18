class_name Danmaku
extends Area2D
## 敌方魔法弹（赤炎 / 玄冰 / 太清 / 戊土）
## 四色共用同一张白模弹丸，运行期用 modulate 染属性色 —— 颜色是唯一区分维度。
## （曾用四种外形，实测密集场里玩家在躲、没有余量辨轮廓，反而更难读。）
##
## Phase 4：
##   · 走 Pool 对象池（Boss 弹幕高峰每秒数百颗，避免反复 new/free）
##   · CollisionShape2D 只在 _ready 建一次，setup 只改半径
##   · 位移迁到 _physics_process，低帧率下不再穿过玩家

const POOL_KEY := "danmaku"
## 弹丸纹理按「半径 = 9」1:1 烘焙（见 tools/build_sprites.py 的 danmaku 条目）。
## 其余半径靠 scale 缩放；改烘焙尺寸必须同步这里，否则弹幕整体变大/变小。
const ART_BASE_R := 9.0

var color: int = Game.RED
var vel := Vector2.ZERO
var dmg := 10
var accel := 0.0          # 沿速度方向的加速度
var turn := 0.0           # 追踪角速度 (rad/s)，0 表示直线
var target: Node2D = null
## 由生成方（Enemy / Boss）注入：消散特效的挂载容器
var world: Node2D = null
var life := 9.0
var radius := 9.0
var spin := 0.0
var _t := 0.0
var _alive := false
var _shape: CircleShape2D = null
## 像素 sprite（ArtAssets 共享纹理，_ready 建一次，setup 切换 / 缩放）
var _art: Sprite2D = null


static func _make() -> Node:
	return Danmaku.new()


## 唯一生成入口：优先从池中取，池空才新建
static func spawn(parent: Node2D, c: int, p: Vector2, v: Vector2, d: int,
		r: float) -> Danmaku:
	var b := Pool.acquire(POOL_KEY, parent, Danmaku._make) as Danmaku
	if b == null:
		return null
	b.world = parent
	b._alive = true
	b.setup(c, p, v, d, r)
	return b


func _ready() -> void:
	collision_layer = 8   # bit3: 敌弹
	collision_mask = 1    # bit0: 玩家
	z_index = 20
	var cs := CollisionShape2D.new()
	_shape = CircleShape2D.new()
	_shape.radius = radius
	cs.shape = _shape
	add_child(cs)
	_art = ArtAssets.make_sprite("danmaku")
	add_child(_art)
	area_entered.connect(_on_area_entered)


## 池化复用：必须覆盖上一颗弹留下的全部状态
func setup(c: int, p: Vector2, v: Vector2, d: int, r: float) -> void:
	color = c
	position = p
	vel = v
	dmg = d
	radius = r
	accel = 0.0
	turn = 0.0
	target = null
	life = 9.0
	_t = 0.0
	rotation = 0.0
	spin = 0.0
	modulate = Color.WHITE
	visible = true
	if _shape != null:
		_shape.radius = r
	# sprite：四色同形白模弹丸，modulate 染属性色（颜色是唯一区分维度）；
	# 纹理只有一张、_ready 时已设好，这里只改尺寸与染色
	if _art != null:
		_art.scale = Vector2.ONE * (r / ART_BASE_R)
		_art.modulate = Game.COLOR_MAIN[c]
	# 弹丸改为旋转对称圆形，spin 一律归零：
	# NEAREST 过滤下旋转像素图会边缘抖动，而形状已不携带任何信息，自转纯属干扰。
	# 属性含义仍由 color 承载（免疫判定 / 异色衰减 / 染色），与外观无关。


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_t += delta
	if turn > 0.0 and target != null and is_instance_valid(target):
		var want := (target.global_position - global_position).angle()
		var cur := vel.angle()
		var d := angle_difference(cur, want)
		var stepv := turn * delta
		vel = vel.rotated(clampf(d, -stepv, stepv))
	if accel != 0.0:
		vel += vel.normalized() * accel * delta
	position += vel * delta
	if spin != 0.0:
		rotation += spin * delta
	life -= delta
	if life <= 0.0 or not Game.in_view(position, 120.0):
		_kill()


## 被清屏 / 阶段转换时化为灵气
func dissolve() -> void:
	if not _alive:
		return
	Fx.burst(world, position, Game.COLOR_GLOW[color], 6, 120.0, 0.35)
	_kill()


## 归还对象池（不 queue_free）
## 摘除必须延后：Area2D 属于 CollisionObject，Godot 禁止在物理回调里
## 直接 remove_child（会报 "Removing a CollisionObject node during a physics
## callback is not allowed"），因此先置死 + 隐藏，帧末再摘。
func _kill() -> void:
	if not _alive:
		return
	_alive = false
	visible = false
	_detach.call_deferred()


func _detach() -> void:
	Pool.release(POOL_KEY, self)


func _on_area_entered(a: Area2D) -> void:
	if not _alive:
		return
	if a is Player:
		if (a as Player).take_hit(color, dmg):
			_kill()
