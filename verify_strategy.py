#!/usr/bin/env python3
"""Reference mirror of RangeStrategy.mqh, used to check the port.

The Pine indicator cannot be run here, so this is a line-for-line
transliteration of the MQL port instead. It replays a synthetic tick
path through the same range-bar rules the aggregator uses, steps the
hook logic over the resulting bars, and asserts the invariants that
have to hold if the control flow and the arithmetic are right:

  * equity == initial capital + sum of every closed trade's P/L
  * TP / SL / RF counts add up to the number of finished trades
  * every finished trade carries exactly one result tag
  * a TP pays risk * R:R - spread, an SL costs risk + spread, an RF is flat
  * no trade closes before it opens, and no hook is confirmed twice

Run: python3 verify_strategy.py
"""

import math
import random

TICK = 0.01
R    = 1.00
EPS  = TICK * 0.5

Q = lambda p: round(round(p / TICK) * TICK, 10)


# ── range bar engine, same rules as CRangeAggregator ────────────────
class Bar:
    __slots__ = ("o", "h", "l", "c", "t")

    def __init__(self, o, h, l, c, t):
        self.o, self.h, self.l, self.c, self.t = o, h, l, c, t


def build_bars(path):
    bars, cur, t0 = [], None, None
    for price, t in path:
        p = Q(price)
        if cur is None:
            cur = [p, p, p, p]
            t0 = t
            continue
        while True:
            up = p > cur[1] and (p - cur[2]) >= R - EPS
            dn = p < cur[2] and (cur[1] - p) >= R - EPS
            if not up and not dn:
                cur[1] = max(cur[1], p)
                cur[2] = min(cur[2], p)
                cur[3] = p
                break
            if up:
                cp = Q(cur[2] + R)
                cur[1] = cp
                nxt = Q(cp + TICK)
            else:
                cp = Q(cur[1] - R)
                cur[2] = cp
                nxt = Q(cp - TICK)
            cur[3] = cp
            bars.append(Bar(cur[0], cur[1], cur[2], cur[3], t0))
            cur = [nxt, nxt, nxt, nxt]
            t0 = t
    return bars


# ── settings, mirroring SHookSettings defaults ──────────────────────
class S:
    max_dollar_hook   = 100.0
    max_pullback_hook = 10.0
    max_hook_bars     = 15
    look_back_len     = 0
    initial_capital   = 100.0
    risk_percent      = 10.0
    risk_reward       = 2.0
    spread            = 0.02
    enable_sl_reduce  = False
    sl_reduce_percent = 20.0
    enable_risk_free  = False
    risk_free_trigger = 1.0
    end_main_candle   = 0
    min_minutes       = 0
    allow_multi_trade = False
    min_size_sharp    = 1
    just_node_1       = True


class Hook:
    def __init__(self, s, p, e, ps, pp, pe, typ):
        self.isSharpRightHook = False
        self.indexStart, self.indexPeak, self.indexEnd = s, p, e
        self.priceStart, self.pricePeak, self.priceEnd = ps, pp, pe
        self.typeSignal = typ
        self.isConfirmed = self.isDrawn = self.isOpen = False
        self.isOrder = self.isGetProfit = self.isFinish = False
        self.isRiskFreeActive = self.isRiskFreeClosed = False
        self.priceStopLoss = self.priceTakeProfit = 0.0
        self.tradeCapitalAtEntry = self.tradeRiskAmount = self.tradePnl = 0.0
        self.tradeOpenTime = self.tradeCloseTime = 0
        self.tradeDurationMinutes = 0
        self.resultKind = 0
        self.resultNum = 0


class Strategy:
    def __init__(self, bars, s=S):
        self.b, self.s = bars, s
        self.lst = []
        self.equity = s.initial_capital
        self.peak = s.initial_capital
        self.maxdd = 0.0
        self.tp = self.sl = self.rf = self.buy = self.sell = 0
        self.profit = self.loss = 0.0
        self.last_open = 0
        self.dur = 0
        self.closed = []
        self.warmup = max(40, s.max_hook_bars + 2)

    # ── bar access, relative to self.bi ─────────────────────────────
    def valid(self, off):
        return off >= 0 and self.bi - off >= 0

    def _b(self, off):
        return self.b[max(0, min(self.bi, self.bi - off))]

    def H(self, off): return self._b(off).h
    def L(self, off): return self._b(off).l
    def O(self, off): return self._b(off).o
    def C(self, off): return self._b(off).c

    def green(self, off): return self.valid(off) and self.C(off) > self.O(off)
    def red(self, off):   return self.valid(off) and self.C(off) < self.O(off)
    def time(self):       return self.b[self.bi].t

    # ── Pine helpers ────────────────────────────────────────────────
    def highest(self, a, z):
        best, ok = 0.0, False
        for i in range(a, z + 1):
            off = self.bi - i
            if not self.valid(off):
                continue
            v = self.H(off)
            if not ok or v > best:
                best, ok = v, True
        return best, ok

    def lowest(self, a, z):
        best, ok = 0.0, False
        for i in range(a, z + 1):
            off = self.bi - i
            if not self.valid(off):
                continue
            v = self.L(off)
            if not ok or v < best:
                best, ok = v, True
        return best, ok

    def prev_lows_higher(self, idx):
        base = self.bi - idx
        if not self.valid(base):
            return True
        ref = self.L(base)
        to = self.s.look_back_len
        step = 1 if to >= 1 else -1
        i = 1
        for _ in range(5000):
            off = base + i
            if self.valid(off) and self.L(off) < ref:
                return False
            if i == to:
                break
            i += step
        return True

    def prev_highs_lower(self, idx):
        len_ = self.s.look_back_len
        base = self.bi - idx
        if len_ <= 0 or base < 0 or not self.valid(base):
            return True
        ref = self.H(base)
        for k in range(1, len_ + 1):
            off = base + k
            if not self.valid(off):
                break
            if self.H(off) > ref:
                return False
        return True

    def _zig(self, a, z, want_green):
        frm = self.bi - a - 1
        to = self.bi - z + 1
        step = 1 if to >= frm else -1
        i = frm
        for _ in range(10000):
            hit = self.green(i) if want_green else self.red(i)
            if hit:
                return True, i
            if i == to:
                break
            i += step
        return False, 0

    def zig_green(self, a, z): return self._zig(a, z, True)
    def zig_red(self, a, z):   return self._zig(a, z, False)

    def _walk(self, pred):
        idx = -1
        for i in range(1, 30):
            if not pred(i):
                break
            idx = self.bi - i
        return idx

    def start_left_buy(self):  return self._walk(self.green)
    def start_left_sell(self): return self._walk(self.red)
    def peak_buy(self):        return self._walk(self.red)
    def peak_sell(self):       return self._walk(self.green)

    def right_sharp_buy(self, peak_hook):
        peak = self.bi - peak_hook
        if peak < 0:
            return False, -1
        start_idx, i = -1, peak
        while i < self.s.max_hook_bars:
            if self.valid(i) and self.L(i) <= self.L(0):
                hi, ok = self.highest(self.bi - i, self.bi - peak)
                if ok and hi > self.H(peak):
                    break
                lo, ok = self.lowest(self.bi - i, self.bi - peak)
                if ok and lo < self.L(i):
                    i += 1
                    continue
                if self.prev_lows_higher(self.bi - i):
                    flag, z = self.zig_red(self.bi - i, self.bi - peak)
                    node1 = True
                    if flag and self.s.just_node_1:
                        node1 = self.valid(z) and self.L(z) >= self.L(0)
                    if flag and node1:
                        start_idx = self.bi - i
                        allv = self.H(peak) - self.L(i)
                        if allv <= self.s.max_dollar_hook:
                            part = self.H(peak) - self.L(0)
                            pct = part * 100.0 / allv if allv > 0 else 0.0
                            if pct >= self.s.max_pullback_hook:
                                return True, start_idx
                        else:
                            break
            i += 1
        return False, start_idx

    def right_sharp_sell(self, peak_hook):
        peak = self.bi - peak_hook
        if peak < 0:
            return False, -1
        start_idx, i = -1, peak
        while i < self.s.max_hook_bars:
            if self.valid(i) and self.H(i) >= self.H(0):
                lo, ok = self.lowest(self.bi - i, self.bi - peak)
                if ok and lo < self.L(peak):
                    break
                hi, ok = self.highest(self.bi - i, self.bi - peak)
                if ok and hi > self.H(i):
                    i += 1
                    continue
                if self.prev_highs_lower(self.bi - i):
                    flag, z = self.zig_green(self.bi - i, self.bi - peak)
                    node1 = True
                    if flag and self.s.just_node_1:
                        node1 = self.valid(z) and self.H(z) <= self.H(0)
                    if flag and node1:
                        start_idx = self.bi - i
                        allv = self.H(i) - self.L(peak)
                        if allv <= self.s.max_dollar_hook:
                            part = self.H(0) - self.L(peak)
                            pct = part * 100.0 / allv if allv > 0 else 0.0
                            if pct >= self.s.max_pullback_hook:
                                return True, start_idx
                        else:
                            break
            i += 1
        return False, start_idx

    # ── money management ────────────────────────────────────────────
    def pull_buy(self, h):
        a = h.pricePeak - h.priceStart
        return a > 0 and (h.pricePeak - h.priceEnd) * 100.0 / a >= self.s.max_pullback_hook

    def pull_sell(self, h):
        a = h.priceStart - h.pricePeak
        return a > 0 and (h.priceEnd - h.pricePeak) * 100.0 / a >= self.s.max_pullback_hook

    def dol_buy(self, h):  return (h.pricePeak - h.priceStart) <= self.s.max_dollar_hook
    def dol_sell(self, h): return (h.priceStart - h.pricePeak) <= self.s.max_dollar_hook

    def adj_sl(self, entry, raw):
        if not self.s.enable_sl_reduce or self.s.sl_reduce_percent <= 0:
            return raw
        return entry - (entry - raw) * (1.0 - self.s.sl_reduce_percent / 100.0)

    def risk_amt(self, cap): return cap * self.s.risk_percent / 100.0

    def can_open(self):
        ok = self.last_open == 0 or (self.time() - self.last_open) // 60 >= self.s.min_minutes
        if self.s.allow_multi_trade:
            return ok
        for h in self.lst:
            if h.isConfirmed and not h.isFinish:
                return False
        return ok

    def remove(self, h):
        if h in self.lst:
            self.lst.remove(h)
        h.isDrawn = False

    def clear_pending(self, keep):
        if self.s.allow_multi_trade:
            return
        for h in list(reversed(self.lst)):
            if h.priceEnd != keep.priceEnd and not h.isConfirmed and not h.isFinish:
                self.remove(h)

    def _enter(self, h, is_buy):
        h.isConfirmed = h.isOpen = True
        h.priceStopLoss = self.adj_sl(h.pricePeak, h.priceEnd)
        d = h.pricePeak - h.priceStopLoss if is_buy else h.priceStopLoss - h.pricePeak
        h.priceTakeProfit = (h.pricePeak + d * self.s.risk_reward) if is_buy \
                            else (h.pricePeak - d * self.s.risk_reward)
        h.tradeCapitalAtEntry = self.equity
        h.tradeOpenTime = self.time()
        h.tradeRiskAmount = self.risk_amt(self.equity)
        h.isDrawn = True

    # ── order management ────────────────────────────────────────────
    def order_buy_normal(self, h):
        flag, _ = self.zig_green(h.indexPeak, h.indexEnd)
        if h.priceStart > self.L(0):
            self.remove(h)
        elif h.pricePeak < self.H(0) and not flag:
            self.remove(h)
        elif h.pricePeak < self.H(0):
            if h.indexEnd - h.indexPeak > 2:
                f2, _ = self.zig_green(h.indexPeak, h.indexEnd)
                if f2:
                    if self.pull_buy(h):
                        if self.dol_buy(h):          # no else, matching Pine
                            if self.can_open():
                                self._enter(h, True)
                                return True
                            self.remove(h)
                    else:
                        self.remove(h)
            else:
                self.remove(h)
        elif h.priceEnd >= self.L(0):
            h.indexEnd, h.priceEnd = self.bi, self.L(0)
            f3, _ = self.zig_green(h.indexPeak, h.indexEnd)
            if f3 and self.bi - h.indexPeak > 1:
                if self.pull_buy(h) and self.dol_buy(h) and self.can_open():
                    h.priceStopLoss = self.adj_sl(h.pricePeak, h.priceEnd)
                    h.priceTakeProfit = h.pricePeak + \
                        (h.pricePeak - h.priceStopLoss) * self.s.risk_reward
                    h.isOrder = True
                    h.isDrawn = True
        return False

    def order_buy_sharp(self, h):
        if h.priceEnd > self.L(0):
            self.remove(h)
        elif h.pricePeak < self.H(0):
            if self.can_open():
                self._enter(h, True)
                return True
            self.remove(h)
        return False

    def order_sell_normal(self, h):
        flag, _ = self.zig_red(h.indexPeak, h.indexEnd)
        if h.priceStart < self.H(0):
            self.remove(h)
        elif h.pricePeak > self.L(0) and not flag:
            self.remove(h)
        elif h.pricePeak > self.L(0):
            if h.indexEnd - h.indexPeak > 2:
                f2, _ = self.zig_red(h.indexPeak, h.indexEnd)
                if f2:
                    if self.pull_sell(h):
                        if self.dol_sell(h):
                            if self.can_open():
                                self._enter(h, False)
                                return True
                            self.remove(h)
                        else:
                            self.remove(h)
                    else:
                        self.remove(h)
            else:
                self.remove(h)
        elif h.priceEnd <= self.H(0):
            h.indexEnd, h.priceEnd = self.bi, self.H(0)
            f3, _ = self.zig_red(h.indexPeak, h.indexEnd)
            if f3 and h.indexEnd - h.indexPeak > 2:
                if self.pull_sell(h) and self.dol_sell(h) and self.can_open():
                    h.priceStopLoss = self.adj_sl(h.pricePeak, h.priceEnd)
                    h.priceTakeProfit = h.pricePeak - \
                        (h.priceStopLoss - h.pricePeak) * self.s.risk_reward
                    h.isOrder = True
                    h.isDrawn = True
        return False

    def order_sell_sharp(self, h):
        if h.priceEnd < self.H(0):
            self.remove(h)
        elif h.pricePeak > self.L(0):
            if self.can_open():
                self._enter(h, False)
                return True
            self.remove(h)
        return False

    def manage_order(self, h):
        if h.typeSignal == "buy" and not h.isOpen:
            return (self.order_buy_sharp(h) if h.isSharpRightHook
                    else self.order_buy_normal(h)), False
        if h.typeSignal == "sell" and not h.isOpen:
            return False, (self.order_sell_sharp(h) if h.isSharpRightHook
                           else self.order_sell_normal(h))
        return False, False

    def manage_position(self, h):
        tp = sl = rf = False
        if h.isOpen and not h.isFinish:
            if self.s.enable_risk_free and not h.isRiskFreeActive:
                if h.typeSignal == "buy":
                    d = h.pricePeak - h.priceStopLoss
                    if self.H(0) >= h.pricePeak + d * self.s.risk_free_trigger:
                        h.isRiskFreeActive = True
                        h.priceStopLoss = h.pricePeak
                else:
                    d = h.priceStopLoss - h.pricePeak
                    if self.L(0) <= h.pricePeak - d * self.s.risk_free_trigger:
                        h.isRiskFreeActive = True
                        h.priceStopLoss = h.pricePeak
            if h.typeSignal == "buy":
                if h.priceTakeProfit < self.H(0):
                    h.isGetProfit = h.isFinish = True
                elif h.priceStopLoss > self.L(0):
                    h.isFinish = True
                    if h.isRiskFreeActive:
                        h.isRiskFreeClosed = True
                    else:
                        h.isGetProfit = False
            if h.typeSignal == "sell":
                if h.priceTakeProfit > self.L(0):
                    h.isGetProfit = h.isFinish = True
                elif h.priceStopLoss < self.H(0):
                    h.isFinish = True
                    if h.isRiskFreeActive:
                        h.isRiskFreeClosed = True
                    else:
                        h.isGetProfit = False

        if h.isFinish and h.tradeCloseTime == 0:
            h.tradeCloseTime = self.time()
            h.tradeDurationMinutes = (h.tradeCloseTime - h.tradeOpenTime) // 60
            if h.isRiskFreeClosed:
                h.tradePnl, rf = 0.0, True
            elif h.isGetProfit:
                h.tradePnl = h.tradeRiskAmount * self.s.risk_reward - self.s.spread
                tp = True
            else:
                h.tradePnl = -(h.tradeRiskAmount + self.s.spread)
                sl = True
            h.resultKind = 1 if tp else (2 if sl else 3)
            self.closed.append(h)
        return tp, sl, rf, h.tradePnl, h.tradeDurationMinutes

    # ── detection ───────────────────────────────────────────────────
    def check_buy(self):
        if self.red(0) and self.green(1):
            i = self.start_left_buy()
            if i >= 0 and self.prev_lows_higher(i):
                self.lst.append(Hook(i, self.bi, self.bi,
                                     self.L(self.bi - i), self.H(0), self.L(0), "buy"))
        if self.green(0) and self.red(1):
            p = self.peak_buy()
            if p >= 0 and self.bi - p > self.s.min_size_sharp:
                ok, i = self.right_sharp_buy(p)
                if ok and i >= 0:
                    h = Hook(i, p, self.bi, self.L(self.bi - i),
                             self.H(self.bi - p), self.L(0), "buy")
                    h.isSharpRightHook = True
                    h.priceStopLoss = self.adj_sl(h.pricePeak, h.priceEnd)
                    h.priceTakeProfit = h.pricePeak + \
                        (h.pricePeak - h.priceStopLoss) * self.s.risk_reward
                    h.isOrder = h.isDrawn = True
                    self.lst.append(h)

    def check_sell(self):
        if self.green(0) and self.red(1):
            i = self.start_left_sell()
            if i >= 0 and self.prev_highs_lower(i):
                self.lst.append(Hook(i, self.bi, self.bi,
                                     self.H(self.bi - i), self.L(0), self.H(0), "sell"))
        if self.red(0) and self.green(1):
            p = self.peak_sell()
            if p >= 0 and self.bi - p > self.s.min_size_sharp:
                ok, i = self.right_sharp_sell(p)
                if ok and i >= 0:
                    h = Hook(i, p, self.bi, self.H(self.bi - i),
                             self.L(self.bi - p), self.H(0), "sell")
                    h.isSharpRightHook = True
                    h.priceStopLoss = self.adj_sl(h.pricePeak, h.priceEnd)
                    h.priceTakeProfit = h.pricePeak - \
                        (h.priceStopLoss - h.pricePeak) * self.s.risk_reward
                    h.isOrder = h.isDrawn = True
                    self.lst.append(h)

    # ── main loop ───────────────────────────────────────────────────
    def on_bar(self, bi, last):
        self.bi, self.last = bi, last
        if bi < self.warmup or bi > last - self.s.end_main_candle:
            return
        n0 = len(self.lst)
        for i in range(n0 - 1, -1, -1):
            if i > len(self.lst) - 1:
                continue
            h = self.lst[i]
            if h.isConfirmed and h.isFinish:
                continue
            if not h.isConfirmed:
                b, s = self.manage_order(h)
                if b:
                    self.buy += 1
                    self.last_open = self.time()
                    self.clear_pending(h)
                if s:
                    self.sell += 1
                    self.last_open = self.time()
                    self.clear_pending(h)
            if h.isConfirmed and not h.isFinish:
                tp, sl, rf, pnl, dur = self.manage_position(h)
                if tp:
                    self.tp += 1
                    self.profit += pnl
                if sl:
                    self.sl += 1
                    self.loss += abs(pnl)
                if rf:
                    self.rf += 1
                if tp or sl or rf:
                    self.equity += pnl
                    self.dur += dur
                    self.peak = max(self.peak, self.equity)
                    self.maxdd = max(self.maxdd,
                                     (self.peak - self.equity) / self.peak * 100.0)

        self.check_buy()
        self.check_sell()

    def run(self):
        last = len(self.b) - 1
        for i in range(last + 1):
            self.on_bar(i, last)


# ── synthetic tick path: a random walk with drift changes ───────────
def make_path(seed=7, n=90000):
    random.seed(seed)
    p, t, out = 2000.0, 1_700_000_000, []
    drift = 0.0
    for i in range(n):
        if i % 900 == 0:
            drift = random.uniform(-0.02, 0.02)
        p += random.gauss(drift, 0.09)
        t += 2
        out.append((p, t))
    return out


def main():
    bars = build_bars(make_path())
    print(f"range bars built : {len(bars)}")

    st = Strategy(bars)
    st.run()

    total = st.tp + st.sl + st.rf
    net = st.equity - S.initial_capital

    print(f"bars stepped     : {len(bars)}")
    print(f"hooks alive      : {len(st.lst)}")
    print(f"trades opened    : {st.buy + st.sell}  (buy {st.buy}, sell {st.sell})")
    print(f"trades closed    : {total}  (TP {st.tp}, SL {st.sl}, RF {st.rf})")
    print(f"equity           : {st.equity:.2f}   net {net:+.2f}")
    print(f"max drawdown     : {st.maxdd:.2f}%")
    print(f"win rate         : {(st.tp / total * 100.0) if total else 0.0:.2f}%")

    fails = []

    def check(name, cond):
        print(f"  {'PASS' if cond else 'FAIL'}  {name}")
        if not cond:
            fails.append(name)

    print("\ninvariants")
    check("at least one trade was taken", total > 0)
    check("closed == len(closed list)", total == len(st.closed))
    check("equity == capital + sum(pnl)",
          abs(st.equity - (S.initial_capital + sum(h.tradePnl for h in st.closed))) < 1e-9)
    check("every closed trade is finished", all(h.isFinish for h in st.closed))
    check("every closed trade has a result tag",
          all(h.resultKind in (1, 2, 3) for h in st.closed))
    check("result tags match the counters",
          sum(h.resultKind == 1 for h in st.closed) == st.tp and
          sum(h.resultKind == 2 for h in st.closed) == st.sl and
          sum(h.resultKind == 3 for h in st.closed) == st.rf)
    check("closes never precede opens",
          all(h.tradeCloseTime >= h.tradeOpenTime for h in st.closed))
    check("TP pays risk * R:R - spread",
          all(abs(h.tradePnl - (h.tradeRiskAmount * S.risk_reward - S.spread)) < 1e-9
              for h in st.closed if h.resultKind == 1))
    check("SL costs risk + spread",
          all(abs(h.tradePnl + (h.tradeRiskAmount + S.spread)) < 1e-9
              for h in st.closed if h.resultKind == 2))
    check("risk was 10% of equity at entry",
          all(abs(h.tradeRiskAmount - h.tradeCapitalAtEntry * S.risk_percent / 100.0) < 1e-9
              for h in st.closed))
    check("buy targets sit above entry, sell targets below",
          all((h.priceTakeProfit > h.pricePeak) == (h.typeSignal == "buy")
              for h in st.closed))
    check("drawdown stayed within 0..100%", 0.0 <= st.maxdd <= 100.0)
    check("no concurrent trades while multi-trade is off",
          max_concurrent(st.closed) <= 1)

    # single-trade mode: every entry must clear the min-minutes gap
    gaps = sorted(h.tradeOpenTime for h in st.closed)
    check("entries respect the min-minutes gap",
          all((b - a) // 60 >= S.min_minutes for a, b in zip(gaps, gaps[1:])))

    print("\n" + ("ALL CHECKS PASSED" if not fails else f"FAILED: {fails}"))
    return 1 if fails else 0


def max_concurrent(trades):
    events = []
    for h in trades:
        events.append((h.tradeOpenTime, 1))
        events.append((h.tradeCloseTime, -1))
    events.sort()
    cur = best = 0
    for _, d in events:
        cur += d
        best = max(best, cur)
    return best


if __name__ == "__main__":
    raise SystemExit(main())
