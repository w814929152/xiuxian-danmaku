class_name ArtAssets
extends RefCounted
## ---------------------------------------------------------------
## ArtAssets —— 像素 sprite 纹理加载器（纯静态）
##
## 由 tools/build_sprites.py 离线产出的 PNG 统一放在 res://assets/sprites/。
## 这里按 key 懒加载并全项目共享一份缓存：池化节点（Danmaku / Sword / Fx）
## 每秒成批生成，绝不允许各自持一份纹理。
##
## 像素风约定：
##   · 所有 sprite 已按游戏内最终尺寸预烘焙（约 1:1 呈现）；
##   · 节点上仍统一设置 TEXTURE_FILTER_NEAREST —— 弹幕按半径的运行期
##     缩放（r / 9）与飞剑的增攻放大也不会糊；
##   · 表里没有 / 文件缺失的 key 一律返回 null，调用方据 null 走各自的
##     兜底呈现（不 push_warning，避免污染 0-warning 门禁）。
## ---------------------------------------------------------------

const DIR := "res://assets/sprites/"

## 属性色枚举 -> 文件名后缀（Game.RED..YELLOW = 0..3）
const _CN := ["red", "blue", "white", "yellow"]

const FILES: Dictionary[String, String] = {
	# 玩家 in-game 像素道袍：44x36 侧身人形（朝右），由 tools/build_robes.py 手绘
	# （不是立绘缩小 —— 立绘缩到这个尺寸会糊）。四件共用同一基础剪影；颜色仍是
	# 属性识别的第一载体，但每件另有 1~2 个**形状层身份部件**（红双剑 / 蓝飘带
	# 霜晶 / 白罡罩护肩 / 黄符箓）供切换后一眼分辨 —— 改部件见 build_robes.py
	# 的 EXTRAS 一节。靠 by_color 取。
	"robe_red": "robe_red.png",
	"robe_blue": "robe_blue.png",
	"robe_white": "robe_white.png",
	"robe_yellow": "robe_yellow.png",
	# 小妖：42x42 朝左人形妖（弓身矮壮、V 形双角、獠牙、三指爪、赤足），
	# 由 tools/build_enemies.py 手绘（不是异形怪物图 —— 旧的 AI 生成图识别度差）。
	# 四色完全同形、只换四档映射，靠 by_color 取。
	"enemy_red": "enemy_red.png",
	"enemy_blue": "enemy_blue.png",
	"enemy_yellow": "enemy_yellow.png",
	"enemy_white": "enemy_white.png",
	# 护法妖将：84x84 朝左直立人形妖（双巨角带分叉、肩吞、披风、腰带兽面扣、
	# 兵器按属性切换）。**独立重绘，不是小妖图的放大** —— 整数放大把 2px 元素
	# 糊成 4px 块，且会被读成「小妖群」。同靠 by_color 取。
	"elite_red": "elite_red.png",
	"elite_blue": "elite_blue.png",
	"elite_yellow": "elite_yellow.png",
	"elite_white": "elite_white.png",
	"boss": "boss.png",
	# 弹幕：四色同形的白模弹丸，使用处以 modulate 染属性色
	"danmaku": "danmaku.png",
	# 白模：使用处以 modulate 染成属性色
	"sword_player": "sword_player.png",
	"fx_burst": "fx_burst.png",
	# 满画幅背景（唯一无需去背的源图）
	"bg_mountains": "bg_mountains.png",
}

static var _cache: Dictionary[String, Texture2D] = {}


## 按 key 取纹理；未命中返回 null（负结果同样缓存，避免反复查盘）。
static func tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	var fname: String = FILES.get(key, "")
	if fname != "" and ResourceLoader.exists(DIR + fname):
		t = load(DIR + fname) as Texture2D
	_cache[key] = t
	return t


## 按属性色取纹理（c: Game.RED / BLUE / WHITE / YELLOW）
static func by_color(kind: String, c: int) -> Texture2D:
	var idx := clampi(c, 0, _CN.size() - 1)
	return tex("%s_%s" % [kind, str(_CN[idx])])


## 建一个按约定配置好的 Sprite2D：NEAREST 过滤、居中、贴图为 key 对应纹理
## （key 无效时 texture 为 null，由调用方决定是否隐藏）
static func make_sprite(key: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "Art"
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.texture = tex(key)
	return s
