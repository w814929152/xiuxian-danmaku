class_name BossLegacy
extends Boss
## 机甲化**改造前**的旗舰（旧模型）：与现 `Boss` 完全同态 —— 同一套 `_process` /
##   状态机 / 碰撞 / 护罩逻辑，只把 `_draw()` 的机体层换成 `BossArtLegacy`
##   （git HEAD 版 `BossArt.gd`，机甲化前的实现）。
## 仅供新旧对比截帧（`_capture/CaptureBossCompare.gd`）使用，**不进正式玩法**。


func _draw() -> void:
	BossLegacyDraw.draw_all(self, true)
