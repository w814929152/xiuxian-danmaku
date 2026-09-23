extends Node2D
## L4 三角化压力测试（一次性诊断，可删）。
##   真机**可见**的 Boss4 定格在 pose 态，**逐帧旋转子核心方位角**，把「触须绷紧
##   指向子核心」的全部核角组合真画一遍，抓 `Invalid polygon data, triangulation failed`。
##
##   ⚠ 节点必须 visible —— 隐藏时绘制命令在三角化之前就被丢弃，测不出自交（假阴性）。
##
##   覆盖矩阵：phase 1/2/3（臂数 2/4/6） × enraged × exposed × 核角扫满 2π
##   × 两核夹角 4 档（0.35 / 1.10 / 2.00 / 3.00 rad，制造「挤在一起」的极端构型）。

const ORBIT := 77.0 * 1.95
const SEPS := [0.35, 1.10, 2.00, 3.00]
const PHS := [1, 2, 3]

var _b: Boss = null
var _ci := 0          # 配置序号
var _f := 0           # 当前配置已跑帧数
var _a := 0.0         # 核角相位
var _t := 0.0


func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	var pa: Array[int] = [Game.RED, Game.WHITE]
	_b = Boss4.new()
	_b.stage = 4
	_b.phase = 3
	_b.player_armors = pa
	_b.world = self
	_b._home_x = 640.0
	_b._base_y = 360.0
	add_child(_b)
	_b.position = Vector2(640.0, 360.0)
	_b._st = "pose"
	_b.visible = true
	print("[L4STRESS] begin")


func _process(_d: float) -> void:
	if _b == null or not is_instance_valid(_b):
		return
	var slot := _ci % (PHS.size() * 4)
	var ph: int = PHS[slot / 4]
	_b.phase = ph
	_b.enraged = (_ci % 2) == 1
	_b._exposed_win = ((_ci / 2) % 2) == 1
	_b._t = _t
	# 子核心定格到受控方位（关掉它自己的公转，避免每帧叠加未知增量）
	var v: Variant = _b.get("_cores")
	if v is Array:
		var arr: Array = v
		var sep: float = float(SEPS[(_f / 20) % SEPS.size()])
		for i in arr.size():
			var core: Node2D = arr[i] as Node2D
			if core == null:
				continue
			core.set_process(false)
			core.visible = true
			core.position = _b.position + Vector2.RIGHT.rotated(
				_a + sep * float(i)) * ORBIT
	_a += 0.11
	_t += 0.06
	_b.queue_redraw()
	_f += 1
	if _f >= 80:
		_f = 0
		_ci += 1
		print("[L4STRESS] cfg %d done" % (_ci - 1))
	if _ci >= PHS.size() * 4:
		print("[L4STRESS] ALL DONE")
		get_tree().quit()
