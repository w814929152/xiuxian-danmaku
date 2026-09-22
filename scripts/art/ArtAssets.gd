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
	# 杂兵 / 精英 / Boss 全部回滚为矢量绘制（scripts/art/PirateArt.gd 与 Boss._draw），
	# 不再引用 enemy_* / elite_* / boss 像素 PNG；文件仍保留在 assets/sprites/ 供追溯。
	# 弹幕：四色同形「灵纹能量珠」白模（24×24，tools/build_danmaku.py 程序化烘焙），
	# 使用处 modulate 染成属性色。
	# （曾用四色异形图 danmaku_{red,blue,white,yellow}.png，形状各异导致弹幕高峰画面杂乱，
	#   已回退白模；四张异形图仍留在 assets/sprites/ 未删，需要时可比对。）
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
