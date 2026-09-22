# ADR-05：以「关卡」取代「难度档」（流程层）

- **状态**：已接受 · 已实施（2026-09-22）
- **决策者**：主理人（用户）终裁「关卡即难度」；流程层实现 eng-flow
- **影响范围**
  - 改：`scripts/Main.gd`、`scripts/world/Level.gd`、`scripts/Game.gd`、`scripts/ui/HUD.gd`、`scripts/ui/ResultScreen.gd`、`_selftest/SelfTest.gd`
  - 增：`scripts/ui/StageSelect.gd`
  - 删：`scripts/ui/DifficultySelect.gd`（含 `.uid`）、`Game.difficulty` / `EASY` / `NORMAL` / `HARD` / `DIFF_CN` / `enum D` / `diff_name()` / `score_multiplier()` / `rank_of()`
- **相关**：设计 `design/levels/01-五关设计总纲.md` §J.7 / §J.10；架构 `docs/architecture/五关改造架构.md` ADR-4 / ADR-4.1

---

## 1. 上下文

《弹幕修仙》原本是**三档难度**（简单 / 普通 / 困难）：开局先选难度，再选战甲，然后进关卡。
五关改造把内容切成 5 个关卡（`StageCfg`，L1~L5），每个关卡自带血量、波数、护罩、弹幕密度、计分倍率。

于是出现两个「难度旋钮」同时存在：玩家要先选一档难度，再选一个关卡。
而关卡本身已经编码了难度曲线（`_BOSS_HP = [1600,2400,3200,4200,6000]`、`_BULLET = [0.55,0.80,0.85,0.95,1.00]`、`_SCORE_MUL = [1.00,1.10,1.20,1.30,1.40]`）——
再叠一层难度档，等于让玩家**为同一次游玩做两次难度决策**，且两个旋钮会互相污染（例如「简单档 + 第 5 关」到底算多难？没人说得清）。

---

## 2. 备选方案

| 方案 | 描述 | 结论 |
| --- | --- | --- |
| **A. 两级菜单**：保留择难度，前面再加一层择关卡 | 界面改动最小，难度访问器一行不用动 | ❌ 否决。两个正交维度，玩家做两次难度选择；且「难度 × 关卡」是 3×5 = 15 种实际难度，无法调平、无法写数值表 |
| **B. 关卡即难度（采纳）** | 删掉难度维度，关卡号是唯一的强度旋钮 | ✅ 采纳 |
| **C. 合并矩阵**：「第 N 关 · 简单/普通/困难」单页 15 格 | 保留组合能力，一个界面搞定 | ❌ 否决。15 个组合每一个都要单独配平与验证，五关设计没有给这套数值；且关卡选择界面会塞不下 |
| **D. 难度档改名为「修行境界」等名义保留** | 玩家感知上仍是「选一个难度」 | ❌ 否决。换名字不换维度，复杂度一点没少 |

---

## 3. 决定

### 3.1 删掉择难度界面 —— 关卡是唯一的难度旋钮

- 主流程改为：`开始 → 关卡选择 → 择战甲 → 关卡 → 结算`。
- `Main.show_difficulty()` 整段删除；`scripts/ui/DifficultySelect.gd` 文件删除（已无任何引用）。
- `Game.difficulty` 与其六个难度访问器**全部退场**（`diff_name` / `boss_hp` / `boss_phases` / `boss_ward` / `bullet_scale` / `off_color_mul` / `score_multiplier` 的难度实现）。
- 强度参数一律改由 `StageCfg.*(stage)` 提供，唯一入口。

### 3.2 `stage` 必须在 `add_child(boss)` 之前注入 —— 踩过坑

`Boss._ready()` 里就按 `stage` 取全部参数（`max_hp` / `_phases` / `_has_ward` / `title` / `boss_name` …）。
若先 `add_child()` 再赋值，`_ready()` 已经跑完，Boss 拿到的 `stage` 是默认值 0 ——
表现不是报错，而是**Boss 静默退化到兜底分支**（血量/阶段/护罩全错，`title` 退回硬编码旧名）。

```gdscript
# scripts/world/Level.gd —— 顺序不可调换
boss = _make_boss(stage)
boss.stage = stage                    # ★ add_child 之前
boss.title = StageCfg.boss_full_name(stage)
boss.boss_name = StageCfg.boss_name(stage)
add_child(boss)
```

**同一条铁律适用于 `Level` 自己**：`Main.start_level()` 里也是先 `s.stage = Game.current_stage` 再 `add_child(s)`。

### 3.3 旧档继承口径 —— 只继承解锁，不继承分数（方案 A）

依据：设计 §J.10 / 架构 ADR-4.1（主理人 2026-09-22 裁定），最终口径由主理人 2026-09-22 复核后补全 `win` 区分。

**档 → 关映射**：简单 → L1 / 普通 → L2 / 困难 → L3。

| 旧档（`highscores.json`） | 判定 | 新档 `unlocked` 初值 |
| --- | --- | --- |
| 键 `"0"` 有分数（玩过简单） | 玩过 | ≥ `1` |
| 键 `"0"` 且 `win=true` | 通关过 | `2` |
| 键 `"1"` 有分数（玩过普通） | 玩过 | ≥ `2` |
| 键 `"1"` 且 `win=true` | 通关过 | `3` |
| 键 `"2"` 有分数（玩过困难） | 玩过 | `3` |
| 键 `"2"` 且 `win=true` | 通关过 | `3`（**封顶吸收**） |

实现（`Game._inherit_unlocked_from_legacy()`）：

```gdscript
for diff in 3:
    var e: Variant = highscores.get(str(diff))
    if typeof(e) != TYPE_DICTIONARY:
        continue
    var d: Dictionary = e
    var stage := diff + 1                    # 简单→L1 / 普通→L2 / 困难→L3
    unlocked = maxi(unlocked, stage)         # 有分数 = 玩过
    if bool(d.get("win", false)):
        unlocked = maxi(unlocked, stage + 1) # 通关过 = 多开一关
unlocked = clampi(unlocked, 1, LEGACY_MAX_UNLOCK)   # 封顶 L3
```

两条约束：① **只在 `progress.json` 不存在时执行**（否则每次启动都用旧档覆盖玩家的真实进度）；
② `stage_best` **全部留空**，只动 `unlocked`。

**为什么不一一对应**：
1. **量纲不同构**：旧档是「难度」粒度 3 条（旧只数 / 旧倍率 / 旧阈值 6000/9000/12500），新档是「关卡」粒度 5 条（L1 满分 8850 / L3 满分 13800）。把旧困难档分数写进 L3，等于断言"你在**新**第 3 关打出了这个完成度"——那是一次没发生过的游玩，且超过 L3 金勋线就是白送品阶。
2. **`win` 是布尔事实，分数是度量**：`win`（"我确实打穿过某一档"）翻译成"我至少打到第 N 关"是保真映射；分数搬过来则不是。
3. **连续前缀原则**：玩家对存档的心智模型是一条从左到右的进度条，任何缝隙都读作异常。方案 A 的结果「L1/L2/L3 可玩 + L4/L5 锁定」正是连续前缀。
4. **为什么封顶 L3**：旧档只有三档，最高只能推出"打到第 3 关"级别的事实，不可能凭空推出 L5。
   L4/L5 是完全的新内容（深渊之喉子核心、终焉号四相），让老玩家重打 L1~L3 体验一遍是合理的、且更保守。
   副作用：`win` 在**困难档**被封顶吸收（玩过困难与通关困难结果相同），只在简单 / 普通两档有区分度。

**分数不迁移、不删除、不展示**：首次启动（有旧档、无新档）把 `highscores.json` 另存 `user://highscores.legacy.json`，玩家侧不会觉得数据被吞掉。

> ✅ **已实现**（2026-09-22）：`Game._inherit_unlocked_from_legacy()`，由 `_load_progress()` 在 `fresh`（新档不存在）分支调用，`LEGACY_MAX_UNLOCK = 3`。

---

## 4. 附带决定：五个「过渡桥」访问器

`boss_hp()` / `boss_phases()` / `boss_ward()` / `bullet_scale()` / `off_color_mul()` **没有删**，而是改成按 `Game.current_stage` 向 `StageCfg` 取值的薄桥：

```gdscript
func bullet_scale() -> float:
	return StageCfg.bullet_scale(current_stage)
```

原因：还有三处调用点不在流程层手里，直接删会当场编译红：
`Boss.gd:139`（未注入 `stage` 的兜底分支）、`Enemy.gd:75` 与 `Elite.gd:137`（开火密度）。

**桥的唯一目的是让「难度」这个变量消失而不动别人的文件。** 上述调用点各自改用 `StageCfg.*(自身的 stage)` 之后，这五个函数整块删除即可。

---

## 5. 后果

**正面**
- 强度只有一个旋钮，数值表从「3 档 × N 参数」收敛为「5 关 × N 参数」一张 `StageCfg`。
- 关卡选择界面（`StageSelect`）能同时承担"选难度"和"看进度"两件事，一次决策。
- 门禁真绿：`PASS=212 / FAIL=0 / ERROR=0 / WARNING=0`，`exit=0`。

**负面 / 代价**
- 老玩家在三档难度下的历史分数不再可见（只备份、不展示）—— 这是**有意为之**：展示会造成成绩伪造。
- `Game.gd` 里留下五个过渡桥函数，属于技术债，需等调用点迁移后清理。
- 旧 `highscores.json` 的读写函数（`highscores` / `highscore_for` / `save_highscore`）**保留但未再被调用**：它们是「只读不写」的旧档存档策略的一部分（`_maybe_backup_legacy()` 依赖文件路径）。迁移完成后是否一并删除，留待后续决定。

**遗留**
1. ~~ADR-4.1 解锁进度继承未实现~~ → ✅ 已实现，见 §3.3。
2. ~~`save_stage` 的 `win` 字段~~ → ✅ 已删（`win` 只写不读且会被失败局覆盖），并补了回归闸。
3. **`Boss.gd:139-148` 兜底分支**仍读旧难度访问器（现由五个过渡桥兜住）并硬编码旧 Boss 名；该分支在 `stage` 正常注入时不可达，建议随子类拆分一并清理。
4. ~~术语整改未覆盖~~ → ✅ 已全覆盖。新增 `_test_wording()` 扫描断言：递归枚举 `res://scripts` + `res://_selftest` 下**全部 35 个 .gd**，
   命中旧称即硬失败。禁用词在断言里用**拼接**书写（`"母舰" + "核心"`），否则本文件自己会命中自己。
   注：L4 子类 `Boss4.gd` 已落地，`Level._make_boss()` 的按关号探测自动生效，**Level.gd 无需改动**。
5. **`unlock_after` 的落盘**（附带的缺陷修复）：原实现只改内存里的 `unlocked`、不写盘，而 `save_stage` 只在破纪录时才写 ——
   一局「通关了但分数没破自己的纪录」会导致解锁进度在下次启动时静默丢失。已改为 `unlocked` 变更时立刻 `_write_progress()`。
