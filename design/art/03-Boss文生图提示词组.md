# 03 · 五关 Boss 文生图提示词组

> **用途**：可灵 / ImageGen 生成 Boss 概念图、设定图、卡面主视觉插图（`boss_card_l{N}.png`）。
> **范围**：共享风格前缀 × 1 + L1~L5 主体提示词 × 5 + 共享负面提示词 × 1 + 一致性约束表。
> **不做**：常态 / 狂暴 / 受创三态变体（待主体风格跑稳后再议）。
> **上游**：`01-五关视觉差异化规格.md`、`02-Boss机甲化视觉规格.md`、`scripts/art/BossArt.gd`、`scripts/Game.gd`。
> **落盘**：2026-09-23，用户裁定「先看正文再定」通过后落盘。

---

## 〇 · 核对来源（先报，便于复核）

| 事实 | 来源（行号） |
|---|---|
| Boss 名 `BOSS_CN` = 熔核号 / 霜噬号 / 耀斑号 / 深渊之喉 / 终焉号 | `scripts/StageCfg.gd:38` |
| 称号 `BOSS_TITLE` = 星盗先驱 / **星盗霜舰** / 星盗炮垒 / 星盗母舰 / 星盗王 | `scripts/StageCfg.gd:39` |
| 关名 / 副题 = 锈带·初次交火 / 霜环·双色夹击 / 耀斑·列阵轰击 / 引力井·深渊回响 / 王座·终局 | `scripts/StageCfg.gd:36-37` |
| 尺寸 `R_MAIN` = 56/63/70/77/84；碰撞 = 46/52/58/65/70 | `scripts/StageCfg.gd:246` / `:241` |
| 本体主色 `_MAIN_C = [2,1,0,3,-1]` → 白/蓝/红/黄/中性钢灰 | `scripts/art/BossArt.gd:47` |
| 能量纹色 `_ACCENT_C = [-1,-1,-1,0,-1]` → 仅 L4 红 | `scripts/art/BossArt.gd:49` |
| 色号映射 0=RED 1=BLUE 2=WHITE 3=YELLOW | `scripts/Game.gd:17-22` |
| 四档色值 `COLOR_MAIN/GLOW/DARK/CORE` | `scripts/Game.gd:28-51` |
| 🔴 `CANOPY = Color(0.62,0.86,0.98)`（玩家专属，敌方全路径禁止） | `scripts/Game.gd:56` |
| 五剪影 `SIL_CORE/WING/BATTERY/MAW/THRONE` | `scripts/art/BossArt.gd:52-78` |
| 标志器官分派：L1 环 / L2 翼 / L4 触须 / **L5 残影**（②b）；L3 炮列（⑦b） | `scripts/art/BossArt.gd:566-601` |
| 机甲语汇（V1 倒角 / V2 接缝铆接 / V3 导管 / V4 推进散热 / V5 传感阵列 / V7 挂架） | `02-Boss机甲化视觉规格.md` §1.1、§3.1~3.5 |
| CANOPY 替代三方案（A 矩形窗阵 / B 舷窗列 / C 观察缝） | 02 §1.3 |

---

## 一 · 共享风格前缀（**以下每条提示词前面都拼这段**）

> `P0 · SHARED STYLE PREFIX`

```
space opera enemy flagship concept sheet, ONE hostile capital ship, centered in frame,
front three-quarter view, NOSE POINTING LEFT and ENGINE BLOCK ON THE RIGHT,
clean flat vector illustration style, crisp hard edges, layered flat colour blocks,
subtle two-tone shading only, bold instantly-readable silhouette,
mecha design language throughout: layered armour plating with 45-degree chamfered corners,
visible panel seams and rivet lines, glowing energy conduits tracing plate edges,
rear thruster block with heat-vent grilles, modular hardpoints,
sensor windows as small dark sockets in a row or arc (never one big glass dome),
industrial military spacecraft, no pilot, no human, no face,
dark neutral deep-navy background with faint starfield, generous empty margin all around,
high contrast, poster-like composition, concept art for a 2D arcade bullet-hell shooter,
no text, no watermark, no UI
```

---

## 二 · L1~L5 主体提示词（英文）

### L1 · 熔核号 · 星盗先驱　|　环　|　光子白　|　r=56（最小、最轻、最好读）

```
compact hexagonal reactor-core hull, perfectly symmetric regular hexagon, no spikes,
every corner chamfered at 45 degrees, hull in pearl-white photon armour
(near-white 0.93/0.96/1.00) with cool slate-blue shadow in the recesses,
20% neutral steel-grey structural parts,
ONE large external rotating cooling ring around the hull — a heat-shedding radiator hoop
with a gap at the rear right, ring studded with eight small radiator fins on its outer edge,
ring glowing in a single clean accent colour, three small rune nodes riding the ring,
a soft furnace halo ring glowing at the hull centre,
armour split into six pie-slice plates with visible seams and a rivet line along each spoke,
five small rectangular sensor windows in a lateral row (dark sockets, pale grey cores, NOT cyan),
rear thruster block with a pale white glow,
SMALLEST and LIGHTEST of the set: low part density, sparse detailing, clean and readable,
teaching-level threat
```

**中文对照**：正六边「反应堆核心舱」，全对称无尖角，六角一律 45° 倒角 —— 这是五张里最轻、最好读的一张，教学位。本体恒**光子白**，环是外挂的**散热回路组件**（不是光环），环上八枚散热鳍 + 三枚符点；环走护罩色，是 L1 的护罩指示器。传感窗用**侧向一排 5 枚矩形暗槽**（方案 A），刻意不朝船头、不朝前向，避免被读成「脸」。体型词刻意压到「最小最轻、部件密度最低」，为后面四张留出递进空间。

---

### L2 · 霜噬号 · 星盗霜舰　|　翼　|　寒霜蓝　|　r=63

```
elongated diamond arrowhead frigate hull, slightly pointed nose on the left, blunt tail on the right,
all convex corners chamfered, hull in deep frost-blue armour (0.22/0.62/1.00)
with pale ice-blue glow accents, 25% neutral steel-grey structural parts,
TWO three-segment folded wings on dorsal and ventral hardpoints,
wing roots near the hull mid-line, WING TIPS SWEPT BACK TO THE RIGHT,
each wing built from three separate armour panels divided by visible seams,
a structural spar beam running the length of each wing, translucent pale-blue glow panel between spars,
heat-vent grilles on the deck exposed between the wings,
energy conduits tracing the upper and lower hull chords,
four small round portholes in a row along the upper hull (dark sockets, pale grey cores),
rear thruster block with an ice-blue flame core,
MEDIUM size, moderate part density, cold and agile
```

**中文对照**：菱形舰体（船头略尖、船尾钝），两侧各一组**三段折面推进翼** —— 每段是独立装甲板、段间有接缝，翼骨是承力梁，**翼尖一律朝船尾（右）**，绝不前指。主色**寒霜蓝** + 25% 中性钢灰结构件。窗用**方案 B 舷窗列**（4 枚小圆窗，暗眼窝 + 灰白芯）。体型词「中等、部件密度适中、冷而灵巧」，比 L1 重一档。

---

### L3 · 耀斑号 · 星盗炮垒　|　炮列　|　电浆红　|　r=70

```
long rectangular gun-battery fortress hull, tall slab silhouette, flat armoured front-left flank,
an EVEN NUMBER of turret mounts in one vertical column along that flank
with a deliberate GAP ON THE CENTRE LINE, each turret a chamfered steel-grey housing
with a hot glowing muzzle, each seated on a short pylon beam,
hull in saturated plasma crimson-red armour (0.98/0.24/0.27) with orange-hot glow,
30% neutral steel-grey armour, three horizontal armour belts with seams and rivet rows,
a THICK PURE-WHITE OUTLINE wrapping the entire silhouette for contrast,
ONE single horizontal observation slit (NOT slanted) — dark fill with a pale grey inner core,
rear engine block with red-hot exhaust and vent grilles,
LARGE and HEAVY, high weapon density, aggressive and blocky
```

**中文对照**：长方炮垒舰体（纵向长板），船头左舷等距挂**一列炮塔** —— 炮塔数取偶数、**中轴留空**（给要害核让位），每门炮都有倒角炮塔座 + 座下挂梁，读作「挂载武器」而不是「身体长刺」。主色**电浆红**，对比仅 3.15:1，所以**强制一圈厚纯白外描边**（这一条是硬补偿，提示词里必须写、不能省）。窗用**方案 C 观察缝**（单条水平狭缝、不倾斜）。体型词「大、重、武器密度高」。

---

### L4 · 深渊之喉 · 星盗母舰　|　触须（口器）　|　引力黄本体 + 电浆红能量纹　|　r=77

```
wide heavy hexagonal carrier hull, blunt armoured bulk,
on its FRONT-LEFT FACE a recessed hangar maw — an inward-curved docking gate,
dark cavity inside, mouth rim ringed with six angular gate teeth,
from that opening extend segmented articulated TRACTOR ARMS (three segments each,
round joint rings at the nodes, small claw tips at the ends),
arms sweeping back and to the sides, NEVER crossing the forward-left centre line,
hull in gravity amber-yellow armour (1.00/0.80/0.14) with pale gold glow,
PLASMA-RED energy veins glowing across the armour plates,
two longitudinal armour bands with rivet rows and panel seams,
five small round portholes along the upper chord (dark sockets, pale grey cores),
rear thruster block with amber exhaust,
VERY LARGE, dense and oppressive, heavy industrial mass
```

**中文对照**：宽厚六边母舰体，船头左面是**机库牵引闸门**（内凹开口 + 六枚闸齿 + 暗腔），**不是嘴**。自腔内伸出**分节牵引机械臂**（3 节 + 转轴环 + 末端夹爪），**不是生物触须**；臂一律往船尾与上下两侧扫，**绝不进入船头 ±40° 要害扇区**。主色**引力黄本体 + 电浆红能量纹**（双色是预期效果，不是错误）。窗用**方案 B 舷窗列**（5 枚沿上弦）。体型词「非常巨大、密、压迫」。

---

### L5 · 终焉号 · 星盗王　|　分身（相位残影）　|　中性亮钢灰 + 四色轮转　|　r=84（最大）

```
spindle-shaped flagship command hull, sharp nose on the left, broad blunt tail on the right,
body in neutral bright steel grey (0.62/0.66/0.74) with a very dark blue-grey outer shell,
NOT bound to a single accent colour — three arrow-feather energy veins along the hull
cycling through FOUR accent colours (plasma red, frost blue, photon white, gravity amber),
an ARC of SEVEN small rectangular sensor windows curved along the forward hull
(dark sockets, pale grey cores), dorsal spine and chord structure lines,
TRIPLE rear thruster block in a vertical stack,
flanking the hull TWO OR THREE SEMI-TRANSPARENT GHOST PROJECTIONS of the same ship —
outline and faint structure lines only, no engine glow, no hardpoints,
offset above and below the real hull, last one trailing behind the tail,
LARGEST of the set, highest part density, most imposing, throne-like authority
```

**中文对照**：纺锤形指挥舰体（船头尖、船尾钝 + 三连推进舱）。本体**中性亮钢灰**、不绑定四色，四色只在**三道箭羽能量纹**上轮转 —— 终局感靠「尺寸最大 + 部件最密 + 四色齐备」，不靠「更黑」。窗用**方案 A 旗舰版**（弧形排列 7 枚）。标志器官是**相位残影**：只画轮廓 + 结构线、**无挂架、无引擎焰**（「无实体挂点」就是它「不是实体」的形状证据）。体型词拉到「最大、部件密度最高、最具威严」。

---

## 三 · 共享负面提示词（**五条共用，拼在每条末尾**）

```
photorealistic render, photographic texture, oil painting, heavy weathering, rust, grime,
dirty metal, lens flare, depth-of-field blur, cinematic dramatic lighting,
human figure, human face, pilot, helmet, driver, cockpit, cockpit canopy,
CYAN CANOPY, SKY-BLUE GLASS DOME, glowing cyan glass, single large forward-slanted window,
one big eye-like window, creature, organic flesh, biological tentacles, bones, fangs,
dragon, insect, animal, monster, humanoid mecha with arms and legs, anime character, mascot,
text, letters, numbers, logo, watermark, signature, UI frame, HUD, health bar, speech bubble,
arrow annotation, callout label,
multiple ships, fleet formation, escort craft, explosion, fire debris, smoke plume,
motion blur trail, airbrush gradient background, busy background, ground, planet surface,
city, space station interior, 3D render, octane render, Unreal Engine screenshot,
low-contrast muddy colours, pastel palette, neon cyberpunk overload
```

> 🔴 其中 `cyan canopy / sky-blue glass dome / glowing cyan glass` 三条是**敌我识别铁律**的落点（`Game.gd:56` 的 `0.62,0.86,0.98` 是玩家侧专属）。Boss 的窗一律走「暗色底槽 + 中性灰芯 + ≥3 枚成阵」，不倾斜、不朝船头、无纯白描边、无单点高光。

---

## 四 · 一致性约束表

### 4.1 五张**必须出现**的词（缺一即不成组）

| 类别 | 必须出现的表述 |
|---|---|
| **朝向（敌我识别）** | `nose/bow pointing LEFT`、`engine thruster block on the RIGHT`（−X 是头、+X 是尾，与玩家完全相反） |
| **机甲语汇 4 件套** | `layered armour plating`、`45-degree chamfered corners`、`panel seams and rivet lines`、`rear thruster block with heat-vent grilles` |
| **传感器表达** | `sensor windows as small dark sockets in a row or arc`、`pale grey cores`（≥3 枚成阵，绝不单枚大窗） |
| **材质分工** | `neutral steel-grey structural parts`（结构件恒灰，属性色只给本体与能量部件） |
| **风格** | `flat vector illustration`、`crisp hard edges`、`layered flat colour blocks`、`dark neutral deep-navy background`、`generous empty margin` |
| **排他** | `ONE hostile capital ship`（单舰，不成编队）、`no pilot / no human / no face` |

### 4.2 五张**必须避免**的词

| 类别 | 禁词 | 理由 |
|---|---|---|
| 🔴 **敌我识别** | `cyan canopy`、`sky-blue cockpit glass`、`glowing cyan dome`、`single large forward-slanted window` | `Color(0.62,0.86,0.98)` 玩家专属（02 §1.2 X1/X2/X3） |
| 🔴 **生物化** | `creature`、`organic tentacles`、`flesh`、`maw with teeth as a mouth`、`bones`、`dragon`、`insect` | 五张必须同语汇，不许「有的机甲有的怪兽」 |
| 🔴 **拟人** | `human figure`、`pilot`、`helmet`、`face`、`humanoid mecha with arms and legs` | Boss 是舰不是人 |
| **写实** | `photorealistic`、`octane render`、`cinematic lighting`、`heavy weathering`、`grime`、`lens flare` | 与「矢量绘制质感」冲突 |
| **构图污染** | `multiple ships`、`fleet`、`explosion`、`motion blur`、`UI / HUD / text / watermark` | 破坏留白与后续矢量化/裁切 |
| **色相污染** | `pastel palette`、`neon cyberpunk`、把后期关卡背景写成暖红调 | 01 §D.1：背景色相轴锁在蓝紫→靛→石板灰 |

### 4.3 五关差异化关键词（**每关独占，互不重复**）

| 关 | 主色关键词 | 标志器官关键词 | 体型/密度递进词 | 窗方案 |
|---|---|---|---|---|
| L1 | `pearl-white photon armour` | `one rotating cooling ring with eight radiator fins` | `smallest, low part density, readable` | A · 5 枚矩形窗，侧向一排 |
| L2 | `deep frost-blue armour` | `two three-segment folded wings, tips swept back` | `medium, moderate density, cold and agile` | B · 4 枚圆舷窗一列 |
| L3 | `saturated plasma crimson` + `thick pure-white outline` | `even column of turret mounts, gap on centre line` | `large and heavy, high weapon density` | C · 单条水平观察缝 |
| L4 | `gravity amber` + `plasma-red energy veins` | `hangar gate with six teeth + segmented tractor arms` | `very large, dense and oppressive` | B · 5 枚圆舷窗沿上弦 |
| L5 | `neutral bright steel grey` + `four-colour cycling veins` | `semi-transparent ghost projections, outline only` | `largest, highest density, throne-like` | A · 7 枚矩形窗成弧 |

> **尺寸递进只走形容词**（smallest → medium → large → very large → largest）+ 部件密度（low → moderate → high → dense → highest），**不写死像素值** —— 真实尺寸由 `StageCfg._BOSS_R_MAIN` 在运行时给。

---

## 五 · 使用建议

- **画幅**：主出 **16:9**（1536×864 或 1920×1080）。理由：游戏视口 1280×720 也是 16:9；卡面插图 `184×104 = 1.769` 与 16:9（1.778）几乎同比例，**中心裁切几乎无损**，直接接 01 v5 的 `boss_card_l{N}.png` 管线。若要正方形图鉴头像，再补一张 1:1（1024×1024）。
- **构图留白**：主体横向占画幅 **55~65%**，四边各留 **≥12%** 边距；不要裁到散热鳍 / 炮口 / 残影尖端。
- **背景**：中性深海军蓝 + 极淡星野。**不要**逐关换背景色调 —— 五张同背景才成组，关卡色调递进由 `Background.gd` 在实机里做（01 §D.1）。
- **转成游戏内矢量绘制要注意什么（一句话）**：生成图只当**参考与卡面位图**，回写矢量时**只取剪影与部件布局**，颜色必须回落到 `Game.gd` 的 `COLOR_MAIN/GLOW/DARK/CORE` 四档常量与 `BossArt.gd` 的 `NEUTRAL / STEEL / SEAM`，**绝不吸生成图的颜色**（否则属性色通道被污染，换甲判据失效）。
- **生成顺序建议**：先跑 L1 单张 → 确认风格前缀是否稳 → 再用**同一 seed 族**跑 L2~L5，成组一致性最好。

---

## 六 · 冲突点（已裁定，见 §7）

| # | 冲突 | A 方 | B 方 | 代码实况 | 处理 |
|---|---|---|---|---|---|
| **C1** | **L2 称号** | 01 §0.5.1 / §C.1：「霜噬号 · **星盗旗舰**」 | 02 §3.2、11 §3：**星盗霜舰** | `StageCfg.gd:39` = **星盗霜舰** ✅ | 按**星盗霜舰**，已回写 01 |
| **C2** | **L5 标志器官命名** | 01 §C.1：标志 = **分身** | 02 §3.5 标题：标志 = **王座** | `BossArt.gd:566-575` `draw_sig_back` → `_l5_echoes`（残影）；`draw_throne` 只是**本体剪影**函数名，本体常量叫 `SIL_THRONE` | 二者不矛盾：「王座」是**本体剪影代号**，「分身/残影」是**标志器官**。已回写 02 §3.5 标题 |
| **C3** | **01 §H「AI 生成提示词 = 不产出」** | 01 §H 交付物自检表末行：`AI 生成提示词 ➖ 不产出` | 01 v5 修订记录：卡面 Boss 主视觉插图为**唯一 PNG 例外**，需 AI 生成五旗舰模型图 | — | 本产物属 v5 例外的延续。已回写 01 §H 那行 |
| **C4** | **L1 名实张力（非冲突，提示）** | 11 §2：「熔核号」字面偏红热熔岩，但本体固定光子白 | 已裁定保留「熔核号」 | `BossArt.gd:47` `_MAIN_C[0]=2` = WHITE | 提示词用 **「白热反应堆 / pearl-white photon」** 而不是「熔岩红」来消解张力，不改名 |

另：02 §5.4 的 M1（残影 α 0.45）/ M2（翼膜 α 0.55）/ M3（触须 6px）三处已按代码回写，提示词里**不写死 alpha 数值**（生图模型读 alpha 无意义），只在中文摘要里标相对关系。

---

## 七 · 修订记录

| 日期 | 变更 |
|---|---|
| 2026-09-23 | 初版落盘。共享前缀 + L1~L5 五条 + 负面词 + 约束表 + 使用建议；C1/C2/C3 三处文档回写执行完毕 |
