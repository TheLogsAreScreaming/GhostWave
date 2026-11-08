#!/usr/bin/env python3
"""Multi-seed sweeps for the open simulation questions in docs/DESIGN.md §13.

    python3 open_questions.py --study geo spray sos load [--jobs 8]
    python3 open_questions.py --report

Each run appends one row per seed to results/open-questions/<study>.csv and
finished rows are skipped, so an interrupted sweep can be resumed. --report
prints the tables used in DESIGN §14 from those CSVs. Results are model output
only: nothing here has been validated on real radios. Pure stdlib.
"""
import argparse
import csv
import math
import multiprocessing as mp
import os
import statistics
from collections import defaultdict

import ghostsim as gs

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "open-questions")

for _n in (20, 40, 80, 160):
    # same node + repeater density as `backcountry` / same 25 km area as `backcountry`
    gs.SCENARIOS[f"density{_n}"] = (int(25000 * math.sqrt(_n / 40)), _n, max(1, round(_n / 10)), 0.15, 1200)
    gs.SCENARIOS[f"area{_n}"] = (25000, _n, max(1, round(_n / 10)), 0.15, 1200)

FIELDS = ["study", "scenario", "label", "seed", "msgs", "pdr", "pdr60", "pdr600", "lat_med", "lat_p90",
          "air_per_msg", "air_total", "air_beacon", "air_data", "air_ack", "air_lack", "air_sos",
          "tx", "lost", "spray_n", "spray_pdr", "spray_lat_med",
          "sos_n", "sos_reach", "sos_reach60", "sos_times", "sos_cov300", "sos_cov2400",
          "sos_orig", "sos_resend", "sos_relay", "sos_offer", "sos_flood", "beacons", "sos_age"]


def gw(**kw):
    return ("gw", kw)


def flood(hops):
    return ("flood", {"hops": hops})


GRIDS = [0, 100, 250, 500, 1000, 2000, 3000, 5000, 8000]
SPRAY_L = [1, 2, 4, 8, 16, 32]

SOS_VARIANTS = {
    "flood3": flood(3),
    "flood7": flood(7),
    "ghostwave": gw(),
    "bloom-15min": gw(bloom_div=3),
    "bloom-30min": gw(bloom_div=6),
    "bloom-sos-only": gw(bloom_sos_only=True),
    "relay-gap-5min": gw(SOS_RELAY_GAP=300),
    "relay-gap-30min": gw(SOS_RELAY_GAP=1800),
    "dup-cancel-1": gw(SOS_DUP_CANCEL=1),
    "no-early-probes": gw(SOS_RETRY_MAX=0),
    "no-reoffer": gw(SOS_REOFFER=10 ** 9),
}

# shortlist re-run on more seeds, with position freshness
SOS_SHORT = {k: SOS_VARIANTS[k] for k in ("flood3", "flood7", "ghostwave", "bloom-15min", "bloom-30min")}
SOS_SHORT["bloom-15min+gap-30min"] = gw(bloom_div=3, SOS_RELAY_GAP=1800)
SOS_SHORT["bloom-15min+no-reoffer"] = gw(bloom_div=3, SOS_REOFFER=10 ** 9)


def jobs_for(study, seeds_override=None):
    def seeds(n):
        return range(1, (seeds_override or n) + 1)
    if study == "geo":
        for sc, ns in (("trail", 10), ("backcountry", 10), ("busy", 5)):
            for g in GRIDS:
                for scope in ("all", "far") if g else ("all",):
                    for s in seeds(ns):
                        yield study, sc, f"{scope}-{g}", gw(coarse=g, coarse_scope=scope), s, {}
        for sc in ("trail", "backcountry"):      # GEO alone, nothing for DTN to rescue
            for g in GRIDS:
                for s in seeds(10):
                    yield study, sc, f"nodtn-{g}", gw(coarse=g, dtn=False), s, {}
    elif study == "spray":
        for fam in ("density", "area"):
            for n in (20, 40, 80, 160):
                ns = 5 if n == 160 else 10
                for L in SPRAY_L:
                    for cond, gossip in (("gossip", True), ("nogossip", False)):
                        for s in seeds(ns):
                            yield study, f"{fam}{n}", f"{cond}-L{L}", gw(COPIES=L, gossip=gossip), s, {}
        for n in (40, 80):      # does capping hand-outs at L (firmware over-issues) matter?
            for L in (8, 16):
                for s in seeds(10):
                    yield study, f"density{n}", f"strict-nogossip-L{L}", gw(COPIES=L, gossip=False, strict_spray=True), s, {}
    elif study == "sos":
        for label, spec in SOS_VARIANTS.items():
            for s in seeds(30):
                yield study, "backcountry", label, spec, s, {"sos": True}
    elif study == "sos2":
        for label, spec in SOS_SHORT.items():
            for s in seeds(100):
                yield study, "backcountry", label, spec, s, {"sos": True}
    elif study == "load":
        for label, spec in (("ghostwave", gw()), ("flood3", flood(3)), ("flood7", flood(7))):
            for tr in (0, 0.5, 1, 2):
                for s in seeds(30):
                    yield study, "backcountry", f"{label}@{tr}", spec, s, {"sos": True, "traffic": tr}
    else:
        raise SystemExit(f"unknown study {study}")


def make(spec):
    kind, kw = spec
    return gs.Flood(kw["hops"]) if kind == "flood" else gs.GhostWave(**kw)


def run(job):
    study, sc, label, spec, seed, kw = job
    r = gs.Sim(sc, make(spec), seed, **kw).run()
    lat = sorted(r["lat"])
    air, roles = r["air_kinds"], r["sos_roles"]
    return {"study": study, "scenario": sc, "label": label, "seed": seed, "msgs": r["msgs"],
            "pdr": r["pdr"], "pdr60": r["pdr60"],
            "pdr600": sum(x <= 600 for x in lat) / r["msgs"] if r["msgs"] else 0,
            "lat_med": r["lat_med"], "lat_p90": lat[int(0.9 * (len(lat) - 1))] if lat else float("nan"),
            "air_per_msg": r["air_per_msg"], "air_total": r["air_total"],
            "air_beacon": air.get("beacon", air.get("pos", 0)), "air_data": air.get("data", 0),
            "air_ack": air.get("ack", 0), "air_lack": air.get("lack", 0), "air_sos": air.get("sos", 0),
            "tx": r["tx"], "lost": r["lost"], "spray_n": r["spray_n"], "spray_pdr": r["spray_pdr"],
            "spray_lat_med": r["spray_lat_med"], "sos_n": r["sos_n"], "sos_reach": r["sos_reach"],
            "sos_reach60": r["sos_reach60"], "sos_times": ";".join(f"{x:.1f}" for x in r["sos_times"]),
            "sos_cov300": r["sos_cov300"], "sos_cov2400": r["sos_cov2400"],
            "sos_orig": roles.get("orig", 0), "sos_resend": roles.get("resend", 0),
            "sos_relay": roles.get("relay", 0), "sos_offer": roles.get("offer", 0),
            "sos_flood": roles.get("flood", 0), "beacons": r["kinds"].get("beacon", r["kinds"].get("pos", 0)),
            "sos_age": r["sos_age"]}


def path(study):
    return os.path.join(OUT, f"{study}.csv")


def load(study):
    if not os.path.exists(path(study)):
        return []
    with open(path(study), newline="") as fh:
        return list(csv.DictReader(fh))


def sweep(study, n_jobs, seeds):
    os.makedirs(OUT, exist_ok=True)
    done = {(r["scenario"], r["label"], r["seed"]) for r in load(study)}
    todo = [j for j in jobs_for(study, seeds) if (j[1], j[2], str(j[4])) not in done]
    print(f"{study}: {len(todo)} runs to do, {len(done)} already done", flush=True)
    new = not os.path.exists(path(study))
    with open(path(study), "a", newline="") as fh, mp.Pool(n_jobs) as pool:
        w = csv.DictWriter(fh, FIELDS)
        if new:
            w.writeheader()
        for i, row in enumerate(pool.imap_unordered(run, todo), 1):
            w.writerow(row)
            fh.flush()
            if i % 50 == 0:
                print(f"{study}: {i}/{len(todo)}", flush=True)


# ------------------------------------------------------------- reporting ----
def _vals(rows, k):
    out = []
    for r in rows:
        try:
            v = float(r[k])
        except (TypeError, ValueError):
            continue
        if not math.isnan(v):
            out.append(v)
    return out


def mean(rows, k):
    v = _vals(rows, k)
    return statistics.mean(v) if v else float("nan")


def ci(rows, k):
    """Half-width of an approximate 95 % interval on the mean across seeds."""
    v = _vals(rows, k)
    return 1.96 * statistics.stdev(v) / math.sqrt(len(v)) if len(v) > 1 else float("nan")


def group(rows):
    g = defaultdict(list)
    for r in rows:
        g[(r["scenario"], r["label"])].append(r)
    return g


def pct(rows, k):
    return f"{mean(rows, k) * 100:.1f} ±{ci(rows, k) * 100:.1f}"


def quantile(xs, q):
    return xs[int(q * (len(xs) - 1))] if xs else float("nan")


def report_geo():
    rows = load("geo")
    if not rows:
        return
    g = group(rows)
    print("\n### GEO: position coarseness (mean over seeds, ± approx 95 % CI)\n")
    print("| scenario | mode | grid m | seeds | delivered % | ≤60 s % | ≤10 min % | median s | p90 s | air/msg s |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for sc in ("trail", "backcountry", "busy"):
        for mode in ("all", "far", "nodtn"):
            for gr in GRIDS:
                r = g.get((sc, f"{mode}-{gr}"))
                if not r and gr == 0 and mode == "far":
                    r = g.get((sc, "all-0"))
                if not r:
                    continue
                print(f"| {sc} | {mode} | {gr} | {len(r)} | {pct(r, 'pdr')} | {pct(r, 'pdr60')} | {pct(r, 'pdr600')} "
                      f"| {mean(r, 'lat_med'):.1f} | {mean(r, 'lat_p90'):.0f} | {mean(r, 'air_per_msg'):.1f} |")


def report_spray():
    rows = load("spray")
    if not rows:
        return
    g = group(rows)
    print("\n### Spray: copy count L vs network size\n")
    print("| scenario | gossip | L | seeds | spray share % | delivered % | spray msgs delivered % | spray median s | air/msg s | data air s/run |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for fam in ("density", "area"):
        for n in (20, 40, 80, 160):
            for cond in ("gossip", "nogossip", "strict-nogossip"):
                for L in SPRAY_L:
                    r = g.get((f"{fam}{n}", f"{cond}-L{L}"))
                    if not r:
                        continue
                    share = sum(_vals(r, "spray_n")) / sum(_vals(r, "msgs")) * 100
                    print(f"| {fam}{n} | {cond} | {L} | {len(r)} | {share:.1f} | {pct(r, 'pdr')} | "
                          f"{pct(r, 'spray_pdr')} | {mean(r, 'spray_lat_med'):.0f} | "
                          f"{mean(r, 'air_per_msg'):.1f} | {mean(r, 'air_data'):.0f} |")


def _times(rows):
    return sorted(float(x) for r in rows for x in r["sos_times"].split(";") if x)


def _sos_row(name, r):
    t = _times(r)
    n = sum(int(x["sos_n"]) for x in r)
    within = lambda s: sum(x <= s for x in t) / n * 100
    print(f"| {name} | {len(r)} | {len(t) / n * 100:.1f} | {within(60):.1f} | {within(300):.1f} | "
          f"{quantile(t, .5):.0f} | {quantile(t, .9):.0f} | {quantile(t, .99):.0f} | {max(t, default=0):.0f} | "
          f"{mean(r, 'air_sos'):.0f} | {mean(r, 'air_total'):.0f} | "
          f"{mean(r, 'sos_cov300') * 100:.0f} | {mean(r, 'sos_cov2400') * 100:.0f} |")


SOS_HEAD = ("| variant | seeds | reached % | ≤60 s % | ≤300 s % | median s | p90 s | p99 s | worst s | SOS air s/run | "
            "total air s/run | nodes heard ≤5 min % | nodes heard ≤40 min % |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|")


def report_sos():
    rows = load("sos")
    if rows:
        g = group(rows)
        print("\n### SOS variants (backcountry, 6 events per seed)\n")
        print(SOS_HEAD)
        for label in sorted({k[1] for k in g}, key=lambda x: (x not in ("flood3", "flood7", "ghostwave"), x)):
            _sos_row(label, g[("backcountry", label)])
        print("\n| variant | orig | early re-send | relay | offer | beacons | beacon air s |\n|---|---|---|---|---|---|---|")
        for (sc, label), r in sorted(g.items()):
            if label.startswith("flood"):
                continue
            print(f"| {label} | {mean(r, 'sos_orig'):.0f} | {mean(r, 'sos_resend'):.0f} | {mean(r, 'sos_relay'):.0f} | "
                  f"{mean(r, 'sos_offer'):.0f} | {mean(r, 'beacons'):.0f} | {mean(r, 'air_beacon'):.0f} |")
    rows = load("sos2")
    if rows:
        g = group(rows)
        print("\n### SOS shortlist, 100 seeds (600 events)\n")
        print(SOS_HEAD)
        for label in SOS_SHORT:
            if ("backcountry", label) in g:
                _sos_row(label, g[("backcountry", label)])
        print("\n| variant | mean age of newest fix at any fixed node, s | ±95 % CI | SOS air s/run | ±95 % CI |\n|---|---|---|---|---|")
        for label in SOS_SHORT:
            r = g.get(("backcountry", label))
            if r:
                print(f"| {label} | {mean(r, 'sos_age'):.0f} | {ci(r, 'sos_age'):.0f} | {mean(r, 'air_sos'):.0f} | {ci(r, 'air_sos'):.0f} |")
    rows = load("load")
    if rows:
        g = group(rows)
        print("\n### SOS reach vs background message load (backcountry; traffic ×1 = 1 msg/node/20 min)\n")
        print(SOS_HEAD)
        for label in sorted({k[1] for k in g}):
            _sos_row(label, g[("backcountry", label)])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--study", nargs="*", default=[], choices=["geo", "spray", "sos", "sos2", "load"])
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument("--seeds", type=int, help="override seeds per case (quick checks)")
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    for s in a.study:
        sweep(s, a.jobs, a.seeds)
    if a.report:
        report_geo()
        report_spray()
        report_sos()


if __name__ == "__main__":
    main()
