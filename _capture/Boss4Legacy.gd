class_name Boss4Legacy
extends Boss4
## L4「深渊之喉」旧模型：`Boss4` 的分核逻辑（`_split_cores` / 牵引 / 暴露期）全部保留，
##   只把 `_draw()` 的机体层换成 `BossArtLegacy`。子核心自绘（`SubCore._draw`）新旧同码，
##   所以对比图里两侧的子核心**本就该长得一样** —— 差异只在母舰本体与牵引臂。


func _draw() -> void:
	BossLegacyDraw.draw_all(self, true)
