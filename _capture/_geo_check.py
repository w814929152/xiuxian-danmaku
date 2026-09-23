import math

TAU = math.pi * 2


def rot(a, rad):
    return (math.cos(a) * rad, math.sin(a) * rad)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, s):
    return (a[0] * s, a[1] * s)


def norm(a):
    L = math.hypot(*a)
    return (1.0, 0.0) if L < 1e-9 else (a[0] / L, a[1] / L)


def rot90(a):
    # Godot Vector2.rotated(+PI/2): (x,y) -> (-y, x)
    return (-a[1], a[0])


def seg_int(p, p2, q, q2):
    r = sub(p2, p)
    s = sub(q2, q)
    d = r[0] * s[1] - r[1] * s[0]
    if abs(d) < 1e-12:
        return False
    t = ((q[0] - p[0]) * s[1] - (q[1] - p[1]) * s[0]) / d
    u = ((q[0] - p[0]) * r[1] - (q[1] - p[1]) * r[0]) / d
    return 1e-9 < t < 1 - 1e-9 and 1e-9 < u < 1 - 1e-9


def self_int(poly):
    n = len(poly)
    bad = []
    for i in range(n):
        for j in range(i + 1, n):
            if i == j:
                continue
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            if seg_int(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n]):
                bad.append((i, j))
    return bad


def hub_pt(arms, k, hubfix):
    nx = (k + 1) % len(arms)
    if hubfix:
        a0 = math.atan2(arms[k][0][1], arms[k][0][0])
        a1 = math.atan2(arms[nx][0][1], arms[nx][0][0])
        g = a0 - a1
        while g <= 0.0:
            g += TAU
        return rot(a0 - g * 0.5, math.hypot(*arms[k][0]) * 0.22)
    a0 = arms[k][0]
    a1 = arms[nx][0]
    v = add(a0, a1)
    if v[0] * v[0] + v[1] * v[1] > 1e-6:
        bi = math.atan2(v[1], v[0])
    else:
        bi = math.atan2(a0[1], a0[0]) + math.pi * 0.5
    L = math.hypot(*a0)
    return rot(bi, L * 0.22)


def ribbons(arms, hw, tip_w, flip, hubfix=False):
    p = []
    sgn = 1.0 if flip else -1.0
    for k in range(len(arms)):
        pts = arms[k]
        n = len(pts)
        if n < 2:
            continue
        nrms = []
        for i in range(n):
            a = pts[max(0, i - 1)]
            bb = pts[min(n - 1, i + 1)]
            nrms.append(rot90(norm(sub(bb, a))))
        for i in range(n):
            w = hw + (tip_w if i == n - 1 else 0.0)
            p.append(add(pts[i], mul(nrms[i], sgn * w)))
        if tip_w > 0.0:
            dl = sub(pts[n - 1], pts[n - 2])
            if math.hypot(*dl) > 0.001:
                p.append(add(pts[n - 1], mul(norm(dl), tip_w)))
        for j in range(n - 1, -1, -1):
            w2 = hw + (tip_w if j == n - 1 else 0.0)
            p.append(add(pts[j], mul(nrms[j], -sgn * w2)))
        if len(arms) >= 2:
            p.append(hub_pt(arms, k, hubfix))
    return p


def chain_arms(arms, hw, hh, flip, hubfix=False, bh=-1.0):
    bhv = hh if bh < 0 else bh
    p = []
    sgn = 1.0 if flip else -1.0
    for k in range(len(arms)):
        cs = arms[k]
        n = len(cs)
        if n < 1:
            continue
        dirs = []
        nrms = []
        for i in range(n):
            a = cs[max(0, i - 1)]
            bb = cs[min(n - 1, i + 1)]
            d = sub(bb, a)
            dirs.append(norm(d))
            nrms.append(rot90(norm(d)))
        if n >= 2:
            ming = min(math.hypot(*sub(cs[i], cs[i - 1])) for i in range(1, n))
            hw = min(hw, ming * 0.45)
        for i in range(n):
            c = cs[i]
            d = dirs[i]
            q = nrms[i]
            p.append(add(add(c, mul(d, -hw)), mul(q, sgn * bhv)))
            p.append(add(add(c, mul(d, -hw)), mul(q, sgn * hh)))
            p.append(add(add(c, mul(d, hw)), mul(q, sgn * hh)))
            p.append(add(add(c, mul(d, hw)), mul(q, sgn * bhv)))
        for i2 in range(n - 1, -1, -1):
            c = cs[i2]
            d = dirs[i2]
            q = nrms[i2]
            p.append(add(add(c, mul(d, hw)), mul(q, -sgn * bhv)))
            p.append(add(add(c, mul(d, hw)), mul(q, -sgn * hh)))
            p.append(add(add(c, mul(d, -hw)), mul(q, -sgn * hh)))
            p.append(add(add(c, mul(d, -hw)), mul(q, -sgn * bhv)))
        if len(arms) >= 2:
            p.append(hub_pt(arms, k, hubfix))
    return p


def sort_arms(angs, curls):
    n = len(angs)
    if n < 2:
        return
    for i in range(1, n):
        ka, kc = angs[i], curls[i]
        j = i - 1
        while j >= 0 and angs[j] < ka:
            angs[j + 1] = angs[j]
            curls[j + 1] = curls[j]
            j -= 1
        angs[j + 1] = ka
        curls[j + 1] = kc
    for k in range(1, n):
        need = max(0.0, curls[k] - curls[k - 1]) + 0.18
        if angs[k - 1] - angs[k] < need:
            angs[k] = angs[k - 1] - need


def build(r, n, exposed, tense, cores, t, flip):
    angs = []
    curls = []
    for i in range(n):
        a = -math.pi * 0.72 + (math.pi * 1.44) * (i / max(1, n - 1))
        cv = 0.30 if (i % 2 == 0) else -0.30
        if tense and i < len(cores):
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
    return chains, arms, angs


r = 77.0
for flip, hubfix in ((False, False), (True, False), (True, True)):
    tag = "flip=%s hubfix=%s" % (flip, hubfix)
    print("=== %s ===" % tag)
    tot = 0
    for n in (2, 4, 6):
        for exposed in (False, True):
            for mode in ("fan", "tense"):
                cores = []
                if mode == "tense":
                    for i in range(n):
                        aa = -1.1 + 0.5 * i
                        cores.append(rot(aa, r * 1.9))
                for t in (0.0, 0.7, 1.9, 3.3):
                    tense = (len(cores) > 0) and (not exposed)
                    chains, arms, angs = build(r, n, exposed, tense, cores, t, flip)
                    b1 = len(self_int(chain_arms(chains, 0.035 * r, 0.062 * r, flip, hubfix)))
                    b2 = len(self_int(ribbons(arms, 3.0, 0.0, flip, hubfix)))
                    b3 = len(self_int(ribbons(arms, 1.75, 0.0, flip, hubfix)))
                    b4 = len(self_int(ribbons(arms, 0.80, r * 0.055, flip, hubfix)))
                    tot += b1 + b2 + b3 + b4
                    if b1 + b2 + b3 + b4:
                        print("  n=%d expo=%s %s t=%.1f -> ch=%d dk=%d g=%d rage=%d"
                              % (n, exposed, mode, t, b1, b2, b3, b4))
    print("  合计自交边对 = %d" % tot)
