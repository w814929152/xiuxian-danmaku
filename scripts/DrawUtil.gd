class_name DrawUtil
extends RefCounted
## 纯静态绘制工具：中文字体 / 带描边文字 / 文字宽度测量
##
## 从 Game 单例拆出 —— Autoload 只负责全局状态与跨场景数据，
## 绘制是无状态工具，不该依赖场景树，也不该挂在单例上。


static var _font: Font = null


## 取得中文字体（项目字体 -> 系统字体 -> 引擎兜底）
static func font() -> Font:
	if _font != null:
		return _font
	var f := load("res://fonts/simhei.ttf")
	if f is Font:
		_font = f
		return _font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "sans-serif"
	])
	_font = sf
	return _font


## 返回文字宽度
static func tw(s: String, size: int) -> float:
	var f := font()
	if f == null:
		return 0.0
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 在 pos 处绘制带描边的文字
## align: 0=左 1=居中 2=右（以 pos 为基准点）
static func txt(
	ci: CanvasItem,
	s: String,
	pos: Vector2,
	size: int,
	col: Color,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	outline: Color = Color(0.02, 0.03, 0.06, 0.9),
	ow: float = 3.0
) -> void:
	var f := font()
	if f == null:
		return
	var p := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			p.x -= w * 0.5
		else:
			p.x -= w
	if ow > 0.0:
		var offs := [
			Vector2(-ow, 0.0), Vector2(ow, 0.0),
			Vector2(0.0, -ow), Vector2(0.0, ow),
			Vector2(-ow, -ow), Vector2(ow, -ow),
			Vector2(-ow, ow), Vector2(ow, ow),
		]
		for d in offs:
			ci.draw_string(f, p + d, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline)
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
