class_name Fx
extends Node2D
## 轻量特效：爆散 / 光环 / 冲击波 / 飘字
## 全部通过静态函数生成，到期自动归还对象池（Phase 4：不再反复 new/free）

const POOL_KEY := "fx"

enum K { BURST, RING, SHOCK, POP }

var kind: int = K.BURST
var col: Color = Color.WHITE
var t: float = 0.0
var dur: float = 0.5
var r0: float = 0.0
var r1: float = 40.0
var width: float = 5.0
var text: String = ""
var text_size: int = 20
var parts: Array[Vector2] = []


static func _make() -> Node:
	return Fx.new()


## 池化复用入口：取一个已重置的特效节点
## 注意不能叫 _get —— 那会撞上 Node 的虚方法 _get(property)
static func _take(parent: Node) -> Fx:
	if parent == null or not is_instance_valid(parent):
		return null
	var f := Pool.acquire(POOL_KEY, parent, Fx._make) as Fx
	if f != null:
		f.reset()
	return f


func _ready() -> void:
	z_index = 30
	# 消散粒子走像素 sprite，NEAREST 保证缩放时像素边缘不糊
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## 池化复用：清空上一次特效留下的全部状态
func reset() -> void:
	kind = K.BURST
	col = Color.WHITE
	t = 0.0
	dur = 0.5
	r0 = 0.0
	r1 = 40.0
	width = 5.0
	text = ""
	text_size = 20
	parts.clear()
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	visible = true


static func burst(parent: Node, pos: Vector2, c: Color, n: int = 12,
		power: float = 260.0, d: float = 0.5) -> void:
	var f := _take(parent)
	if f == null:
		return
	f.kind = K.BURST
	f.col = c
	f.dur = d
	f.position = pos
	for i in n:
		var a := randf() * TAU
		var sp := power * (0.35 + randf() * 0.65)
		f.parts.append(Vector2.RIGHT.rotated(a) * sp)


static func ring(parent: Node, pos: Vector2, c: Color, rr0: float, rr1: float,
		d: float = 0.35, w: float = 5.0) -> void:
	var f := _take(parent)
	if f == null:
		return
	f.kind = K.RING
	f.col = c
	f.dur = d
	f.position = pos
	f.r0 = rr0
	f.r1 = rr1
	f.width = w


static func shock(parent: Node, pos: Vector2, c: Color, rr1: float = 220.0,
		d: float = 0.55) -> void:
	var f := _take(parent)
	if f == null:
		return
	f.kind = K.SHOCK
	f.col = c
	f.dur = d
	f.position = pos
	f.r1 = rr1


static func pop(parent: Node, pos: Vector2, s: String, c: Color, size: int = 20,
		d: float = 0.75) -> void:
	var f := _take(parent)
	if f == null:
		return
	f.kind = K.POP
	f.col = c
	f.dur = d
	f.position = pos
	f.text = s
	f.text_size = size


func _process(delta: float) -> void:
	t += delta
	if t >= dur:
		Pool.release(POOL_KEY, self)
		return
	queue_redraw()


func _draw() -> void:
	var k: float = clampf(t / dur, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.0)  # ease-out
	var a: float = 1.0 - k
	match kind:
		K.BURST:
			# 消散粒子：白模像素 sprite，modulate 染成来色，随时间放大 + 淡出
			var tex := ArtAssets.tex("fx_burst")
			if tex != null:
				var rr := 0.0
				for v in parts:
					rr = maxf(rr, v.length())
				rr = maxf(24.0, rr * dur * e * 0.55)
				var sz := rr * 2.0
				draw_texture_rect(tex, Rect2(-rr, -rr, sz, sz), false,
					Color(col.r, col.g, col.b, a))
		K.RING:
			draw_arc(Vector2.ZERO, lerpf(r0, r1, e), 0.0, TAU, 40,
				Color(col.r, col.g, col.b, a), maxf(1.0, width * a), true)
		K.SHOCK:
			var rr := lerpf(10.0, r1, e)
			draw_circle(Vector2.ZERO, rr * 0.55, Color(col.r, col.g, col.b, a * 0.16))
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56,
				Color(col.r, col.g, col.b, a * 0.9), maxf(1.0, 10.0 * a), true)
			draw_arc(Vector2.ZERO, rr * 0.72, 0.0, TAU, 40,
				Color(1, 1, 1, a * 0.5), maxf(1.0, 3.0 * a), true)
		K.POP:
			var p := Vector2(0.0, -34.0 * e)
			DrawUtil.txt(self, text, p, text_size, Color(col.r, col.g, col.b, a),
				HORIZONTAL_ALIGNMENT_CENTER)
