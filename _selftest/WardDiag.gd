extends Node2D
## 一次性诊断：确认 Boss 属性护罩在探针路径下到底有没有轮转起来。
## 跑法：Godot_console --headless --path <项目> --quit-after 60000 res://_selftest/WardDiag.tscn
##
## 起因：PaceProbe 里 L1 / L5 的「完美换甲」与「不换甲」TTK **完全相同**
##   （16.8 / 16.8 与 63.2 / 63.2），而这两关恰恰是唯二带 ALWAYS 护罩的。
##   若护罩真的在轮转，不换甲必须更慢 —— 所以要么护罩没转，要么倍率没生效。
## 本探针每 0.5s 采样一次 ward / player_armors / _ward_t / hp，把这个疑问钉死。

var _lv: Level = null
var _boss: Boss = null
var _clock := 0.0


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ready() -> void:
	await _frames(2)
	for stage in [1, 5]:
		Game.current_stage = stage
		Game.picked_armors = [Game.RED, Game.BLUE]
		_lv = Level.new()
		add_child(_lv)
		await _frames(3)
		_lv._running = false
		await _frames(3)
		_lv._running = true
		_lv.stage = stage
		_lv._boss_fight()
		await _frames(30)
		_boss = _lv.boss
		if _boss == null:
			print("[DIAG] L%d Boss 生成失败" % stage)
			continue
		var g := 0
		while _boss._st != "fight" and g < 900:
			await _frames(10)
			g += 10
		print("[DIAG] ---- L%d | armors=%s | boss.player_armors=%s | ward_mode=%d | ward_cd=%.1f | off=%.2f"
			% [stage, str(_lv.player.armors), str(_boss.player_armors),
				_boss._ward_mode, _boss._ward_cd, _boss._off_color])
		_clock = 0.0
		var up := 0
		var samples := 0
		for k in 40:
			await _frames(30)
			_clock += 0.0
			samples += 1
			if _boss.ward >= 0:
				up += 1
			if k % 6 == 0:
				print("[DIAG]   t≈%.1fs | ward=%d | _ward_t=%.2f | st=%s"
					% [float(k) * 0.5, _boss.ward, _boss._ward_t, _boss._st])
		print("[DIAG]   => 护罩展开占比 %d/%d = %.0f%%"
			% [up, samples, 100.0 * float(up) / float(samples)])
		_lv.queue_free()
		await _frames(4)
	Pool.clear()
	await _frames(2)
	print("[DIAG] DONE")
	get_tree().quit(0)
