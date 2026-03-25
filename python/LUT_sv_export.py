"""
Generate LUT as a SystemVerilog localparam 3D array.
Indices: [RI-2 (0..13)][|X-8| (0..8)][|Y-8| (0..8)]
Values: non-negative magnitudes in Q4.8 format
        stored in 12-bit signed representation
        (4 integer bits + 8 fractional bits = 12 bits total)
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

def q8_floor(val):
    return int(np.floor(val * 256))

# ---------------------------------------------------------------------------
# Build LUT from canonical X <= 8 side (ox >= 0)
# lut[ri_idx][abs_u][abs_v]  ri_idx = RI-2
# ---------------------------------------------------------------------------

BITS = 12   # Q4.8 => 12 bits total

def to_twos_complement(val, bits):
    """Convert integer to bits-wide 2's complement binary string."""
    if val < 0:
        val = val + (1 << bits)
    return format(val & ((1 << bits) - 1), f'0{bits}b')

lut = {}   # (abs_u, abs_v, RI) -> non-negative int

for RI in range(2, 16):
    for abs_u in range(9):
        X = 8 - abs_u
        for abs_v in range(9):
            Y = 8 - abs_v
            ox, _ = compute_offsets_float(X, Y, RI)
            raw = q8_floor(ox)
            assert raw >= 0
            lut[(abs_u, abs_v, RI)] = raw

# ---------------------------------------------------------------------------
# Write SystemVerilog localparam
# ---------------------------------------------------------------------------

outfile = "lut_localparam_q4_8.txt"

with open(outfile, "w") as f:
    f.write("// ============================================================\n")
    f.write("// Optical Refraction LUT\n")
    f.write("// Indices: [RI_idx][abs_u][abs_v]\n")
    f.write("//   RI_idx = RI - 2  (0..13, maps to RI=2..15)\n")
    f.write("//   abs_u  = |X - 8| (0..8)\n")
    f.write("//   abs_v  = |Y - 8| (0..8)\n")
    f.write("//\n")
    f.write("// Values: non-negative magnitudes in Q4.8 format (units of 1/256)\n")
    f.write(f"//         {BITS}-bit signed representation\n")
    f.write("//\n")
    f.write("// Reconstruct outputs:\n")
    f.write("//   ox = (X > 8) ? -LUT[RI-2][|X-8|][|Y-8|]\n")
    f.write("//                :  LUT[RI-2][|X-8|][|Y-8|]\n")
    f.write("//   oy = (Y > 8) ? -LUT[RI-2][|Y-8|][|X-8|]  // note: abs_u/abs_v swapped\n")
    f.write("//                :  LUT[RI-2][|Y-8|][|X-8|]\n")
    f.write("// ============================================================\n\n")

    f.write(f"localparam logic signed [{BITS-1}:0] REFRACT_LUT [0:13][0:8][0:8] = '{{\n")

    for ri_idx, RI in enumerate(range(2, 16)):
        comma_ri = "" if ri_idx == 13 else ","
        f.write(f"  // RI = {RI}\n")
        f.write("  '{\n")
        for abs_u in range(9):
            comma_u = "" if abs_u == 8 else ","
            vals = []
            for abs_v in range(9):
                v = lut[(abs_u, abs_v, RI)]
                tc = to_twos_complement(v, BITS)
                vals.append(f"{BITS}'b{tc}")
            row = ", ".join(vals)
            f.write(f"    '{{ {row} }}{comma_u}  // |X-8|={abs_u}\n")
        f.write(f"  }}{comma_ri}\n")

    f.write("};\n")

print(f"Written: {outfile}")
print(f"  Entries  : {9*9*14} ({14} RIs × 9 abs_u × 9 abs_v)")
print(f"  Bit width: {BITS}-bit signed")
print(f"  Max value: {max(lut.values())}  ({to_twos_complement(max(lut.values()), BITS)}b)")
print(f"  Min value: {min(lut.values())}  ({to_twos_complement(min(lut.values()), BITS)}b)")
print()

print("Preview (first 16 lines of file):")
with open(outfile) as f:
    for i, line in enumerate(f):
        if i < 16:
            print(" ", line, end="")