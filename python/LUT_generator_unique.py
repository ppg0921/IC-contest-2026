"""
LUT Duplicate Value Analysis
============================
Find all entries that share the same quantized value and identify
the conditions (abs_u, abs_v, RI) patterns that map to each value.
"""

import numpy as np
from collections import defaultdict

# ---------------------------------------------------------------------------
# Rebuild LUT (same as before)
# ---------------------------------------------------------------------------

def compute_offsets_float(X, Y, RI):
    u = (X - 8) / 8.0
    v = (Y - 8) / 8.0
    Z  = 6.0 - 2.0*u**8 - 2.0*v**8
    gx = 2.0 * u**7
    gy = 2.0 * v**7
    g2 = gx**2 + gy**2 + 1.0
    eta      = 1.0 / RI
    k        = 1.0 - eta**2 * (1.0 - 1.0/g2)
    sqrt_kgg = np.sqrt(max(k * g2, 0.0))
    coef     = (eta - sqrt_kgg) / g2
    t        = -Z / (-eta + coef)
    return t * coef * gx, t * coef * gy

def q6_floor(val):
    return int(np.floor(val * 64))

lut = {}
for RI in range(2, 16):
    for abs_u in range(9):
        X = 8 - abs_u
        for abs_v in range(9):
            Y = 8 - abs_v
            ox, _ = compute_offsets_float(X, Y, RI)
            lut[(abs_u, abs_v, RI)] = q6_floor(ox)

# ---------------------------------------------------------------------------
# Group entries by value
# ---------------------------------------------------------------------------

# value -> list of (abs_u, abs_v, RI)
val_to_entries = defaultdict(list)
for (abs_u, abs_v, RI), val in lut.items():
    val_to_entries[val].append((abs_u, abs_v, RI))

total_entries  = len(lut)          # 1134
distinct_vals  = len(val_to_entries)

print("=" * 70)
print("DUPLICATE VALUE ANALYSIS")
print("=" * 70)
print(f"  Total LUT entries : {total_entries}")
print(f"  Distinct values   : {distinct_vals}")
print(f"  Duplicate savings : {total_entries - distinct_vals} entries could share a value")
print()

# ---------------------------------------------------------------------------
# Helper: try to express the entry list as a compact condition
# ---------------------------------------------------------------------------

def summarize_condition(entries):
    """Return a compact human-readable description of when this value occurs."""
    aus  = sorted(set(e[0] for e in entries))
    avs  = sorted(set(e[1] for e in entries))
    RIs  = sorted(set(e[2] for e in entries))

    # Check if the group is a full Cartesian product of some sets
    expected = len(aus) * len(avs) * len(RIs)
    is_product = (len(entries) == expected and
                  all((au, av, RI) in set(entries)
                      for au in aus for av in avs for RI in RIs))

    def fmt_range(lst, lo, hi):
        if lst == list(range(lo, hi+1)):
            return f"{lo}..{hi}"
        if len(lst) == 1:
            return str(lst[0])
        return "{" + ",".join(map(str, lst)) + "}"

    au_str = fmt_range(aus, 0, 8)
    av_str = fmt_range(avs, 0, 8)
    ri_str = fmt_range(RIs, 2, 15)

    if is_product:
        return f"abs_u∈[{au_str}], abs_v∈[{av_str}], RI∈[{ri_str}]", True
    else:
        return f"abs_u∈[{au_str}], abs_v∈[{av_str}], RI∈[{ri_str}]  (partial)", False

# ---------------------------------------------------------------------------
# Sort values and print details
# ---------------------------------------------------------------------------

sorted_vals = sorted(val_to_entries.keys())

print("=" * 70)
print("ENTRIES GROUPED BY VALUE")
print("=" * 70)
print()

for val in sorted_vals:
    entries = sorted(val_to_entries[val])
    n = len(entries)
    cond, is_exact = summarize_condition(entries)
    real = val / 64.0
    print(f"  Value = {val:09b}  (dec={val:4d}, {real:+8.5f})  →  {n:3d} entries")
    print(f"    Condition: {cond}")

    # If not a clean Cartesian product, show full list grouped by abs_u
    if not is_exact or n <= 20:
        by_u = defaultdict(list)
        for (au, av, RI) in entries:
            by_u[au].append((av, RI))
        for au in sorted(by_u):
            items = sorted(by_u[au])
            avs_here = sorted(set(x[0] for x in items))
            RIs_here = sorted(set(x[1] for x in items))
            # check if product
            if len(items) == len(avs_here)*len(RIs_here):
                av_s = str(avs_here[0]) if len(avs_here)==1 else f"{avs_here[0]}..{avs_here[-1]}" if avs_here==list(range(avs_here[0],avs_here[-1]+1)) else str(avs_here)
                ri_s = str(RIs_here[0]) if len(RIs_here)==1 else f"{RIs_here[0]}..{RIs_here[-1]}" if RIs_here==list(range(RIs_here[0],RIs_here[-1]+1)) else str(RIs_here)
                print(f"      abs_u={au}: abs_v∈[{av_s}], RI∈[{ri_s}]")
            else:
                print(f"      abs_u={au}: {items}")
    print()

# ---------------------------------------------------------------------------
# Focus: non-zero entries only (the interesting part)
# ---------------------------------------------------------------------------

print("=" * 70)
print("NON-ZERO ENTRIES ONLY (abs_u >= 4)")
print("=" * 70)
print()

nonzero_entries = {k: v for k, v in lut.items() if v != 0}
nz_val_to_entries = defaultdict(list)
for (abs_u, abs_v, RI), val in nonzero_entries.items():
    nz_val_to_entries[val].append((abs_u, abs_v, RI))

print(f"  Non-zero entries  : {len(nonzero_entries)}")
print(f"  Distinct non-zero : {len(nz_val_to_entries)}")
print()

# ---------------------------------------------------------------------------
# Key pattern: for fixed abs_u and RI, how many abs_v values share the same val?
# ---------------------------------------------------------------------------

print("=" * 70)
print("PATTERN: For each (abs_u, RI), which abs_v values share the same output?")
print("=" * 70)
print()

for abs_u in range(4, 9):
    print(f"  abs_u = {abs_u}  (|X-8| = {abs_u}, X = {8-abs_u} or {8+abs_u})")
    for RI in range(2, 16):
        # get val for each abs_v
        vals_by_av = {av: lut[(abs_u, av, RI)] for av in range(9)}
        # group abs_v by value
        val_groups = defaultdict(list)
        for av, v in vals_by_av.items():
            val_groups[v].append(av)
        # show groups that have more than one abs_v
        groups = sorted(val_groups.items(), key=lambda x: -len(x[1]))
        repeats = [(v, avs) for v, avs in groups if len(avs) > 1]
        uniq    = [(v, avs) for v, avs in groups if len(avs) == 1]
        row = f"    RI={RI:2d}: "
        for v, avs in sorted(groups, key=lambda x: x[0]):
            avs_s = f"av={avs[0]}" if len(avs)==1 else f"av={avs[0]}..{avs[-1]}" if avs==list(range(avs[0],avs[-1]+1)) else f"av={avs}"
            row += f"  [{avs_s}]→{v:09b}"
        print(row)
    print()

# ---------------------------------------------------------------------------
# Pattern: for fixed abs_v, how does value vary with abs_u and RI?
# ---------------------------------------------------------------------------

print("=" * 70)
print("PATTERN: abs_v that give the SAME value as abs_v=0 (flat region)")
print("=" * 70)
print()
print("  For each (abs_u, RI), the value is identical for abs_v = 0..K")
print("  where K is the largest abs_v that doesn't change the value.")
print("  This means: the Y-position only matters when |Y-8| is large")
print()

for abs_u in range(4, 9):
    print(f"  abs_u={abs_u}:")
    for RI in range(2, 16):
        base_val = lut[(abs_u, 0, RI)]
        # find the highest abs_v that still equals base_val
        flat_up_to = 0
        for av in range(1, 9):
            if lut[(abs_u, av, RI)] == base_val:
                flat_up_to = av
            else:
                break
        next_val = f"{lut[(abs_u, flat_up_to+1, RI)]:09b}" if flat_up_to+1 <= 8 else 'N/A'
        print(f"    RI={RI:2d}: flat (val={val:09b}) for abs_v=0..{flat_up_to}, "
              f"then changes at abs_v={flat_up_to+1} → {next_val}")
    print()

# ---------------------------------------------------------------------------
# Summary table: unique value count per abs_u row
# ---------------------------------------------------------------------------

print("=" * 70)
print("SUMMARY: Unique values per abs_u row (across all abs_v and RI)")
print("=" * 70)
print()
print(f"  {'abs_u':>6} | {'entries':>8} | {'unique vals':>11} | {'compression':>12} | note")
print("  " + "-"*60)
for abs_u in range(9):
    row_entries = [(abs_u, av, RI) for av in range(9) for RI in range(2,16)]
    vals = [lut[k] for k in row_entries]
    n_unique = len(set(vals))
    n_total  = len(vals)
    note = "ALL ZERO" if set(vals) == {0} else ""
    print(f"  {abs_u:>6} | {n_total:>8} | {n_unique:>11} | {n_total/n_unique:>10.1f}× | {note}")
print()

# ---------------------------------------------------------------------------
# Write a cleaner summary to file
# ---------------------------------------------------------------------------

with open("lut_value_groups.txt", "w") as f:
    f.write("LUT Value Groups — entries sharing the same quantized value\n")
    f.write("="*70 + "\n\n")
    f.write(f"Total entries : {total_entries}\n")
    f.write(f"Distinct vals : {distinct_vals}\n\n")

    for val in sorted_vals:
        entries = sorted(val_to_entries[val])
        real = val / 64.0
        f.write(f"VALUE = {val:09b}  (dec={val:4d}, {real:+.5f})  [{len(entries)} entries]\n")
        by_u = defaultdict(list)
        for (au, av, RI) in entries:
            by_u[au].append((av, RI))
        for au in sorted(by_u):
            items = sorted(by_u[au])
            avs_here = sorted(set(x[0] for x in items))
            RIs_here = sorted(set(x[1] for x in items))
            f.write(f"  abs_u={au}: abs_v={avs_here}  RI={RIs_here}\n")
        f.write("\n")

print("  Saved full group listing to: lut_value_groups.txt")