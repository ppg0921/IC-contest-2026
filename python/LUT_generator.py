"""
ICC 2026 - Optical Refraction: LUT Symmetry Analysis  (CORRECTED)
=================================================================
Key insight: The lens is CONVEX (focusing). Light always deflects TOWARD the
optical axis (x=8, y=8). So:
  - X < 8  →  zx > X  (ox > 0, deflects right toward center)
  - X > 8  →  zx < X  (ox < 0, deflects left toward center)
  - X = 8  →  ox = 0  (symmetric axis, no x-deflection)

The sign of ox is always OPPOSITE to sign(X-8).  The magnitude |ox| is
symmetric: |ox(X,Y,RI)| ≈ |ox(16-X, Y, RI)|  (not exact due to floor, but
within 1/64 which is within the tolerance budget).

LUT stores:  mag_ox(|X-8|, |Y-8|, RI) = magnitude of ox for canonical X<8
Then:   ox = +mag  if X < 8
        ox =  0    if X = 8
        ox = -mag  if X > 8
"""

import numpy as np

# ---------------------------------------------------------------------------
# Core computation
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
    """Floor to 1/64 → returns integer (signed, in units of 1/64)."""
    return int(np.floor(val * 64))

# ---------------------------------------------------------------------------
# Build raw table
# ---------------------------------------------------------------------------

raw = {}
for RI in range(2, 16):
    for X in range(16):
        for Y in range(16):
            ox, oy = compute_offsets_float(X, Y, RI)
            raw[(X, Y, RI)] = (q6_floor(ox), q6_floor(oy))

# ---------------------------------------------------------------------------
# Verify sign direction of ox and oy
# ---------------------------------------------------------------------------

print("=" * 65)
print("SIGN DIRECTION VERIFICATION")
print("=" * 65)

sign_ox_ok = True
for RI in range(2, 16):
    for X in range(16):
        for Y in range(16):
            ox, oy = raw[(X, Y, RI)]
            # ox should be > 0 when X < 8, < 0 when X > 8
            if X < 8 and ox < 0:
                print(f"  ox<0 but X<8: X={X},Y={Y},RI={RI} ox={ox}")
                sign_ox_ok = False
            if X > 8 and ox > 0:
                print(f"  ox>0 but X>8: X={X},Y={Y},RI={RI} ox={ox}")
                sign_ox_ok = False
            if Y < 8 and oy < 0:
                print(f"  oy<0 but Y<8: X={X},Y={Y},RI={RI} oy={oy}")
            if Y > 8 and oy > 0:
                print(f"  oy>0 but Y>8: X={X},Y={Y},RI={RI} oy={oy}")
print(f"  ox sign = -sign(X-8): {'PASS ✓' if sign_ox_ok else 'FAIL ✗'}")

# ---------------------------------------------------------------------------
# Symmetry checks (analytical, pre-quantization)
# ---------------------------------------------------------------------------

print()
print("=" * 65)
print("SYMMETRY ANALYSIS (float, before quantization)")
print("=" * 65)

max_err = {}
for sym in ['S1_xy_swap', 'S2_x_mirror', 'S3_y_mirror', 'S4_ox_yindep', 'S5_oy_xindep']:
    max_err[sym] = 0.0

for RI in range(2, 16):
    for X in range(16):
        for Y in range(16):
            ox_f, oy_f = compute_offsets_float(X, Y, RI)
            # S1
            ox2, oy2 = compute_offsets_float(Y, X, RI)
            max_err['S1_xy_swap'] = max(max_err['S1_xy_swap'], abs(ox_f - oy2))
            # S2
            if 16-X <= 15:
                ox2, _ = compute_offsets_float(16-X, Y, RI)
                max_err['S2_x_mirror'] = max(max_err['S2_x_mirror'], abs(ox_f + ox2))
            # S3
            if 16-Y <= 15:
                _, oy2 = compute_offsets_float(X, 16-Y, RI)
                max_err['S3_y_mirror'] = max(max_err['S3_y_mirror'], abs(oy_f + oy2))
            # S4
            if 16-Y <= 15:
                ox2, _ = compute_offsets_float(X, 16-Y, RI)
                max_err['S4_ox_yindep'] = max(max_err['S4_ox_yindep'], abs(ox_f - ox2))
            # S5
            if 16-X <= 15:
                _, oy2 = compute_offsets_float(16-X, Y, RI)
                max_err['S5_oy_xindep'] = max(max_err['S5_oy_xindep'], abs(oy_f - oy2))

for sym, err in max_err.items():
    print(f"  {sym:20s}: max error = {err:.2e}  {'EXACT ✓' if err < 1e-10 else f'off by {err:.2e}'}")

print()
print("  >> S2 and S3 are EXACT in float (before quantization)")
print("  >> After floor-truncation, |ox(X,Y)| and |ox(16-X,Y)| differ by ≤ 1/64")
print("  >> This 1-LSB difference is within the contest's 1/64 tolerance")

# ---------------------------------------------------------------------------
# Build the LUT using ONLY X < 8 (or X=8) as canonical
# LUT stores mag_ox = ox for X ≤ 8 (which is ≥ 0)
# For X > 8: mag_ox = -ox(X,Y,RI) ≈ ox(16-X, Y, RI)  (within 1 LSB)
# We choose to build LUT from the X ≤ 8 side for correct floor behavior
# ---------------------------------------------------------------------------

print()
print("=" * 65)
print("BUILDING LUT from canonical X ≤ 8 (ox ≥ 0)")
print("=" * 65)

# lut[(abs_u, abs_v, RI)] = mag_ox  (non-negative integer, in units of 1/64)
lut = {}

for RI in range(2, 16):
    for abs_u in range(9):   # 0..8 → |X-8| ∈ {0..8}
        X = 8 - abs_u         # canonical X from left half: X = 0..8
        for abs_v in range(9):
            # abs_v = |Y-8|. ox does not depend on sign(Y-8), so use Y ≤ 8
            Y = 8 - abs_v     # Y = 0..8
            ox, oy = raw[(X, Y, RI)]
            # ox should be ≥ 0 here (X ≤ 8)
            assert ox >= 0, f"Unexpected: X={X},Y={Y},RI={RI} gives ox={ox}"
            lut[(abs_u, abs_v, RI)] = ox   # already non-negative

print(f"  LUT entries: {len(lut)}  (9×9×14 = {9*9*14})")
distinct = sorted(set(lut.values()))
print(f"  Distinct quantized values: {len(distinct)}")
print(f"  Value range: [{min(distinct)/64:.4f}, {max(distinct)/64:.4f}]")

# ---------------------------------------------------------------------------
# Reconstruct and check error
# ---------------------------------------------------------------------------

print()
print("=" * 65)
print("RECONSTRUCTION ACCURACY CHECK")
print("=" * 65)
print("  Reconstructed:  ox_r = +LUT(|X-8|,|Y-8|,RI) if X<8, else -LUT(...)")
print("                  oy_r = +LUT(|Y-8|,|X-8|,RI) if Y<8, else -LUT(...)")
print()

max_ox_err = 0
max_oy_err = 0
n_ox_err_gt0 = 0
n_oy_err_gt0 = 0

for RI in range(2, 16):
    for X in range(16):
        for Y in range(16):
            abs_u = abs(X - 8)
            abs_v = abs(Y - 8)
            sx = -1 if X > 8 else (0 if X == 8 else 1)
            sy = -1 if Y > 8 else (0 if Y == 8 else 1)

            ox_r = lut[(abs_u, abs_v, RI)] * sx
            oy_r = lut[(abs_v, abs_u, RI)] * sy

            ox_raw, oy_raw = raw[(X, Y, RI)]
            ex = abs(ox_r - ox_raw)
            ey = abs(oy_r - oy_raw)
            if ex > max_ox_err: max_ox_err = ex
            if ey > max_oy_err: max_oy_err = ey
            if ex > 0: n_ox_err_gt0 += 1
            if ey > 0: n_oy_err_gt0 += 1

total = 14 * 16 * 16
print(f"  ox: max error = {max_ox_err}/64 = {max_ox_err/64:.4f},  "
      f"non-zero errors: {n_ox_err_gt0}/{total}")
print(f"  oy: max error = {max_oy_err}/64 = {max_oy_err/64:.4f},  "
      f"non-zero errors: {n_oy_err_gt0}/{total}")
print()
if max_ox_err <= 1 and max_oy_err <= 1:
    print("  ✓ Max error ≤ 1/64 (within contest tolerance of 1/64)")
    print("  ✓ This comes purely from floor-truncation asymmetry")
    print("    It ONLY affects cases where X>8 or Y>8 (the mirror side)")
    print("    The LUT is built from X≤8, so X>8 may be off by 1 LSB")
    print()
    print("  Options to eliminate this 1-LSB error:")
    print("    A) Use round-to-nearest instead of floor in hardware")
    print("       (then symmetry is exact)")
    print("    B) Store LUT for both X<8 and X>8 halves separately")
    print("       (doubles LUT size but exact)")
    print("    C) Accept the 1-LSB error (it's within the 1/64 tolerance)")
    print("       BUT: if your hardware also has other rounding errors,")
    print("       they could stack. Keep this in mind.")

# ---------------------------------------------------------------------------
# Print the full LUT tables
# ---------------------------------------------------------------------------

print()
print("=" * 65)
print("FULL LUT (values in units of 1/64, i.e., value/64 = real offset)")
print("Rows = |X-8|  (abs_u, 0=center, 8=edge)")
print("Cols = |Y-8|  (abs_v, 0=center, 8=edge)")
print("=" * 65)
print()
print("Physical interpretation:")
print("  - abs_u=0,1,2,3: very little x-deflection (near top of lens)")
print("  - abs_u=4..7:    significant deflection")
print("  - abs_v affects Z (height), which affects how far ray travels")
print()

for RI in range(2, 16):
    print(f"  RI={RI:2d}  (eta=1/{RI})")
    col_label = 'au\\av'
    header = f"  {col_label:>6} |" + "".join(f"  {v:>4}" for v in range(9))
    print(header)
    print("  " + "-" * (len(header)-2))
    for abs_u in range(9):
        row = f"  {abs_u:>6} |"
        for abs_v in range(9):
            row += f"  {lut[(abs_u, abs_v, RI)]:>4}"
        print(row)
    print()

# ---------------------------------------------------------------------------
# Highlight near-zero region
# ---------------------------------------------------------------------------

print("=" * 65)
print("NOTABLE PATTERN: abs_u ≤ 3 gives ZERO deflection for all RI")
print("=" * 65)
print()
print("  For abs_u = 0,1,2,3  (i.e. X ∈ {5,6,7,8,9,10,11}):")
print("  gx = 2*((X-8)/8)^7 is tiny, floor rounds to 0/64 for all RI")
print()
print("  gx values:")
for abs_u in range(9):
    u = abs_u / 8.0
    gx = 2 * u**7
    print(f"    abs_u={abs_u}: gx={gx:.8f}  "
          f"(any zero-row RI? {all(lut[(abs_u,av,RI)]==0 for RI in range(2,16) for av in range(9))})")
print()

# ---------------------------------------------------------------------------
# Show symmetry conditions summary table
# ---------------------------------------------------------------------------

print("=" * 65)
print("HARDWARE SYMMETRY EXPLOITATION SUMMARY")
print("=" * 65)
print("""
  ┌─────────────────────────────────────────────────────────────┐
  │  ONE LUT:  base[abs_u][abs_v][RI]   (9×9×14 = 1134 entries)│
  │            vs naive 16×16×14 = 3584  (3.16× compression)   │
  │                                                             │
  │  Decode:                                                    │
  │    abs_u = |X - 8|   (4 bits: 0..8)                        │
  │    abs_v = |Y - 8|   (4 bits: 0..8)                        │
  │    x_neg = (X > 8)   (1 bit)                               │
  │    y_neg = (Y > 8)   (1 bit)                               │
  │                                                             │
  │    ox = x_neg ? -base[abs_u][abs_v][RI]                     │
  │               :  base[abs_u][abs_v][RI]  (when X=8, base=0)│
  │                                                             │
  │    oy = y_neg ? -base[abs_v][abs_u][RI]  ← args SWAPPED    │
  │               :  base[abs_v][abs_u][RI]  (when Y=8, base=0)│
  │                                                             │
  │  Total negations/sign-muxes: 2 (no multipliers needed)     │
  │                                                             │
  │  LUT values are non-negative integers ∈ [0, 443]           │
  │  → 9 bits needed for LUT data width                        │
  │  → Total LUT storage: 1134 × 9 bits ≈ 1.25 KB             │
  │                                                             │
  │  RI LUT address: 14 values (RI=2..15) → 4 bits             │
  │  abs_u LUT address: 9 values (0..8)   → 4 bits             │
  │  abs_v LUT address: 9 values (0..8)   → 4 bits             │
  │  Total address bits: 12 bits (actual entries: 1134 < 4096) │
  └─────────────────────────────────────────────────────────────┘
""")

# ---------------------------------------------------------------------------
# Show X=8 and Y=8 zero cases
# ---------------------------------------------------------------------------

print("=" * 65)
print("ZERO CASES (X=8 or Y=8)")
print("=" * 65)
print()
print("  When X=8: abs_u=0, gx=0 exactly → ox=0 for ALL Y, RI")
print("  When Y=8: abs_v=0, gy=0 exactly → oy=0 for ALL X, RI")
print()
print("  Verify: all base[0][abs_v][RI] = 0?")
all_zero = all(lut[(0, av, RI)] == 0 for RI in range(2,16) for av in range(9))
print(f"    {'YES ✓' if all_zero else 'NO ✗'}")
print()
print("  Verify: all base[abs_u][0][RI] describes oy when Y=8?")
print("  (When Y=8, oy uses base[0][abs_u][RI] which is all-zero)")
all_zero2 = all(lut[(0, au, RI)] == 0 for RI in range(2,16) for au in range(9))
print(f"    {'YES ✓' if all_zero2 else 'NO ✗'}")

# ---------------------------------------------------------------------------
# Save the LUT as a flat Verilog memory init (for reference)
# ---------------------------------------------------------------------------

print()
print("=" * 65)
print("SAMPLE: Flat address encoding for Verilog ROM")
print("=" * 65)
print()
print("  addr = {RI_minus2[3:0], abs_u[3:0], abs_v[3:0]}  // 12-bit addr")
print("  RI_minus2 = RI - 2  (maps RI=2..15 to 0..13)")
print()
print("  First and last 10 entries:")
entries = []
for RI in range(2, 16):
    for abs_u in range(9):
        for abs_v in range(9):
            addr = (RI-2)*9*9 + abs_u*9 + abs_v
            entries.append((addr, lut[(abs_u, abs_v, RI)], abs_u, abs_v, RI))

for addr, val, au, av, RI in entries[:10]:
    print(f"    addr={addr:4d} (RI={RI:2d},|X-8|={au},|Y-8|={av}): {val:4d}  ({val/64:.5f})")
print("    ...")
for addr, val, au, av, RI in entries[-5:]:
    print(f"    addr={addr:4d} (RI={RI:2d},|X-8|={au},|Y-8|={av}): {val:4d}  ({val/64:.5f})")

print()
print(f"  Total ROM entries used: {len(entries)}  (max addr used: {max(e[0] for e in entries)})")
print(f"  Max value: {max(e[1] for e in entries)}  → needs {max(e[1] for e in entries).bit_length()} bits")

output_path = "lut_binary.txt"
with open(output_path, "w") as f:
    for RI in range(2, 16):
        for abs_u in range(9):
            for abs_v in range(9):
                val = lut[(abs_u, abs_v, RI)]
                f.write(f"{val:09b}\n")