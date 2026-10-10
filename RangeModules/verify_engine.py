TICK=0.01; R=1.00; EPS=TICK*0.5
def Q(p): return round(round(p/TICK)*TICK,10)
bars=[]; cur=None
def open_bar(p): 
    global cur; cur=dict(o=p,h=p,l=p,c=p)
def add(price):
    global cur
    p=Q(price)
    if cur is None: open_bar(p); return
    while True:
        up   = p>cur['h'] and (p-cur['l'])>=R-EPS
        dn   = p<cur['l'] and (cur['h']-p)>=R-EPS
        if not up and not dn:
            cur['h']=max(cur['h'],p); cur['l']=min(cur['l'],p); cur['c']=p; return
        if up:  cp=Q(cur['l']+R); cur['h']=cp; nxt=Q(cp+TICK)
        else:   cp=Q(cur['h']-R); cur['l']=cp; nxt=Q(cp-TICK)
        cur['c']=cp; bars.append(dict(cur)); open_bar(nxt)

# path replayed from the two TradingView bars
open_bar(4403.48)
for p in [4403.60,4404.16,4403.90,4403.16,          # bar 1: up then down
          4403.00,4402.55,4402.90,4403.55]:         # bar 2: down then up
    add(p)

exp=[(4403.48,4404.16,4403.16,4403.16),(4403.15,4403.55,4402.55,4403.55)]
for i,(b,e) in enumerate(zip(bars,exp)):
    got=(b['o'],b['h'],b['l'],b['c'])
    ok="PASS" if all(abs(a-c)<1e-9 for a,c in zip(got,e)) else "FAIL"
    print(f"bar{i+1}  engine O{got[0]:.2f} H{got[1]:.2f} L{got[2]:.2f} C{got[3]:.2f}")
    print(f"      TV      O{e[0]:.2f} H{e[1]:.2f} L{e[2]:.2f} C{e[3]:.2f}   -> {ok}")
    print(f"      height={b['h']-b['l']:.2f}")
print("forming:",{k:round(v,2) for k,v in cur.items()})
