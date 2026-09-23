import math
import random
import importlib.util

spec = importlib.util.spec_from_file_location("gc", r"D:\demo\xiuxian-danmaku\_capture\_geo_check.py")

# 直接复用 _geo_check 的几何函数，但不跑它的主循环：改成 import 安全版
src = open(r"D:\demo\xiuxian-danmaku\_capture\_geo_check.py", encoding="utf-8").read()
src = src.split("r = 77.0\nfor flip")[0]
ns = {}
exec(compile(src, "geo", "exec"), ns)

rot = ns["rot"]
ribbons = ns["ribbons"]
chain_arms = ns["chain_arms"]
sort_arms = ns["sort_arms"]
self_int = ns["self_int"]

R = 77.0
random.seed(20240922)


def build(r, n, exposed, cores, t, flip):
    angs = []
    curls = []
    for i in range(n):
        a = -math.pi * 0.72 + (math.pi * 1.44) * (i / max(1, n - 1))
        cv = 0.30 if (i % 2 == 0) else -0.30
        if (not exposed) and i < len(cores):
            a = math.atan2(cores[i][1], cores[i][0])
            cv = 0.0
        angs.append(a)
        curls.append(cv)
    sort_arms(angs, curls)
    chains = []
    arms = []
    for i in range(n):
        a = angs[i]
        curl = curls[i]
        p0 = rot(a, r * 0.72)
        if exposed:
            b1 = rot(a + curl * 0.3, r * 0.92)
            chains.append([p0, rot(a + curl * 0.15, r * 0.82), b1])
            arms.append([p0, b1])
            continue
        p1 = rot(a + curl * 0.35, r * 1.00)
        p2 = rot(a + curl * 0.70, r * 1.28)
        tip = rot(a + curl, r * 1.55)
        tip = (tip[0], tip[1] + math.sin(t * 5.0 + i) * 2.0)
        chains.append([p0, p1, p2, tip])
        arms.append([p0, p1, p2, tip])
    return chains, arms


def run(flip, hubfix, cases):
    bad = 0
    worst = None
    for (n, ncores, exposed, t) in cases:
        cores = []
        for i in range(ncores):
            aa = random.uniform(-math.pi, math.pi)
            cores.append(rot(aa, R * 1.95))
        chains, arms = build(R, n, exposed, cores, t, flip)
        s = 0
        for poly in (chain_arms(chains, 0.035 * R, 0.062 * R, flip, hubfix),
                     ribbons(arms, 3.0, 0.0, flip, hubfix),
                     ribbons(arms, 1.75, 0.0, flip, hubfix),
                     ribbons(arms, 0.80, R * 0.055, flip, hubfix)):
            s += len(self_int(poly))
        bad += s
        if s and worst is None:
            worst = (n, ncores, exposed, t,
                     [math.degrees(math.atan2(c[1], c[0])) for c in cores])
    return bad, worst


# L4 真实工况矩阵：阶段 → (臂数, 子核心数)；狂暴再叠加一次（只多一层覆描，几何同）
CASES = []
for (n, nc) in ((2, 0), (2, 1), (4, 0), (4, 1), (4, 2), (6, 0), (6, 1), (6, 2)):
    for exposed in (False, True):
        for _rep in range(400):
            CASES.append((n, nc, exposed, random.uniform(0.0, 12.0)))

for flip, hubfix in ((False, False), (True, False), (True, True)):
    bad, worst = run(flip, hubfix, CASES)
    print("flip=%-5s hubfix=%-5s  用例=%d  自交边对=%d  %s"
          % (flip, hubfix, len(CASES), bad, ("worst=%s" % (worst,)) if worst else ""))
