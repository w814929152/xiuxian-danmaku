extends Node2D
## 每关 draw 调用实测（一次性核对脚本，不进正式门禁，可删）
## 做法：用 BossArt 的**计数副本** `_BA_count.gd`（每个 `X.draw_*` 包一层 `tk()` 计数），
##       再手工跑一遍 `Boss._draw()` 所用的四个 BossArt 分派入口。
## 盲区：`DrawUtil.txt()` 内部的 `draw_string` 不在副本里 —— BossArt 只在
##       L4 暴露期飘字处用它一次（ow=0 → 1 次 draw_string），已手工 +1 补回。

func _ready() -> void:
	Game.picked_armors = [Game.RED, Game.WHITE]
	for s in range(1, 6):
		for rage in [false, true]:
			await _one(s, rage, int(StageCfg._BOSS_PHASES[s - 1]), false)
		# L4 子核心暴露态另列（暴露会替换触须残端 / 机库闭闸 / 加飘字）
		if s == 4:
			await _one(4, true, int(StageCfg._BOSS_PHASES[3]), true)
	print("[DRAWCOUNT] DONE")
	get_tree().quit()


func _one(s: int, rage: bool, ph: int, exposed: bool) -> void:
	var b: Boss
	if s == 4:
		b = Boss4.new()
	else:
		b = Boss.new()
	b.stage = s
	b.phase = ph
	b.enraged = rage
	var pa: Array[int] = [Game.RED, Game.WHITE]
	b.player_armors = pa
	b.world = self
	b._home_x = 600.0
	b._base_y = 360.0
	add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	b.set("_exposed_win", exposed)   # 必须在 _ready() 之后再设：Boss4 会把状态初始化掉
	b.visible = false              # 停掉引擎侧 _draw()，避免污染计数

	var ba: Object = load("res://_capture/_BA_count.gd").new()
	ba.set("N", 0)
	ba.draw_sig_back(b, 0.0)
	var n1: int = int(ba.get("N"))
	ba.draw_body(b, 0.0)
	var n2: int = int(ba.get("N"))
	ba.draw_sig_front(b, 0.0)
	var n3: int = int(ba.get("N"))
	ba.draw_mechanic(b, 0.0)
	var n4: int = int(ba.get("N"))
	ba.draw_body_rim(b, Color(1.0, 1.0, 1.0, 1.0), 2.0)
	var n5: int = int(ba.get("N"))
	var txt: int = 1 if (s == 4 and exposed) else 0
	var line: String = "[DRAWCOUNT] L%d rage=%s ph=%d exp=%s | sig_back=%d body=%d sig_front=%d mechanic=%d => SUM=%d (+rim=%d +txt=%d => TOTAL=%d)"
	print(line % [s, rage, ph, exposed, n1, n2 - n1, n3 - n2, n4 - n3, n4, n5 - n4, txt, n4 + txt])
	b.queue_free()
	await get_tree().process_frame
