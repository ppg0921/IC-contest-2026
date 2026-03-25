"""
Generate SystemVerilog case statement LUT for coef/(-eta+coef)
indexed by {gx, gy, RI}.

All intermediate values are rounded back to Q4.12 after each operation.
"""

import math

# ---------------------------------------------------------------------------
# Fixed-point helpers  (Q4.12, 16-bit signed for IO; Python int internally)
# ---------------------------------------------------------------------------

Q = 12
BITS = 16
ONE = 1 << Q

def float_to_q(val):
    """Float -> nearest integer in Q4.12."""
    return int(round(val * ONE))

def q_to_float(val):
    return val / ONE

def fixed_hex(val):
    """Q4.12 integer -> 16-bit signed SV literal."""
    return f"16'sh{val & 0xFFFF:04X}"

def q_add(a, b):
    return a + b

def q_sub(a, b):
    return a - b

def q_mul(a, b):
    """
    Q4.12 * Q4.12 -> Q4.12
    Rounded to nearest, symmetric for signed values.
    """
    prod = a * b
    if prod >= 0:
        return (prod + (1 << (Q - 1))) >> Q
    else:
        return -(((-prod) + (1 << (Q - 1))) >> Q)

def q_div(a, b):
    """
    Q4.12 / Q4.12 -> Q4.12
    Rounded to nearest, symmetric for signed values.
    """
    if b == 0:
        raise ZeroDivisionError("q_div divisor is zero")
    num = a << Q
    sign = -1 if (num < 0) ^ (b < 0) else 1
    anum = abs(num)
    ab = abs(b)
    q = (anum + ab // 2) // ab
    return sign * q

def q_sqrt(a):
    """
    sqrt(Q4.12) -> Q4.12
    Implemented by converting to float for sqrt, then rounding back to Q4.12.
    If you later want a pure-integer sqrt, that can also be done.
    """
    if a < 0:
        raise ValueError("q_sqrt input must be non-negative")
    return float_to_q(math.sqrt(q_to_float(a)))

# ---------------------------------------------------------------------------
# Core fixed-point computation with rounding after every step
# ---------------------------------------------------------------------------

def compute_offsets_q412(X, Y, RI):
    """
    Return gx, gy, ratio in Q4.12 integers.
    All intermediate results are quantized back to Q4.12.
    """

    # u = (X - 8) / 8, v = (Y - 8) / 8
    # Since 8 is exact, do directly in fixed-point
    u = float_to_q((X - 8) / 8.0)
    v = float_to_q((Y - 8) / 8.0)

    # Build powers one multiply at a time
    u2 = q_mul(u, u)
    u3 = q_mul(u2, u)
    u4 = q_mul(u2, u2)
    u5 = q_mul(u4, u)
    u6 = q_mul(u5, u)
    u7 = q_mul(u6, u)
    u8 = q_mul(u4, u4)

    v2 = q_mul(v, v)
    v3 = q_mul(v2, v)
    v4 = q_mul(v2, v2)
    v5 = q_mul(v4, v)
    v6 = q_mul(v5, v)
    v7 = q_mul(v6, v)
    v8 = q_mul(v4, v4)

    two = float_to_q(2.0)
    one = float_to_q(1.0)
    six = float_to_q(6.0)

    # Z = 6 - 2*u^8 - 2*v^8
    two_u8 = q_mul(two, u8)
    two_v8 = q_mul(two, v8)
    Z = q_sub(q_sub(six, two_u8), two_v8)

    # gx = 2*u^7, gy = 2*v^7
    gx = q_mul(two, u7)
    gy = q_mul(two, v7)

    # g2 = gx^2 + gy^2 + 1
    gx2 = q_mul(gx, gx)
    gy2 = q_mul(gy, gy)
    g2 = q_add(q_add(gx2, gy2), one)

    # eta = 1 / RI
    eta = q_div(one, float_to_q(RI))

    # eta^2
    eta2 = q_mul(eta, eta)

    # 1/g2
    inv_g2 = q_div(one, g2)

    # k = 1 - eta^2 * (1 - 1/g2)
    one_minus_inv_g2 = q_sub(one, inv_g2)
    eta2_term = q_mul(eta2, one_minus_inv_g2)
    k = q_sub(one, eta2_term)

    # sqrt_kgg = sqrt(k * g2)
    kg2 = q_mul(k, g2)
    if kg2 < 0:
        kg2 = 0
    sqrt_kgg = q_sqrt(kg2)

    # coef = (eta - sqrt_kgg) / g2
    eta_minus_sqrt = q_sub(eta, sqrt_kgg)
    coef = q_div(eta_minus_sqrt, g2)

    # ratio = -coef / (-eta + coef)
    neg_coef = -coef
    denom = q_add(-eta, coef)
    ratio = q_div(neg_coef, denom)

    return gx, gy, ratio

# ---------------------------------------------------------------------------
# Enumerate all unique (gx_q, gy_q, RI) -> ratio_q entries
# X, Y in 0..15 ; RI in 2..15
# ---------------------------------------------------------------------------

entries = {}

for X in range(0, 16):
    for Y in range(0, 16):
        for RI in range(2, 16):
            gx_q, gy_q, ratio_q = compute_offsets_q412(X, Y, RI)
            key = (gx_q, gy_q, RI)
            entries[key] = ratio_q

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

assert all(-32768 <= v <= 32767 for v in entries.values()), \
    "Some ratio values overflow 16-bit signed!"

ratio_vals  = list(entries.values())
gx_distinct = sorted(set(k[0] for k in entries))
gy_distinct = sorted(set(k[1] for k in entries))

print(f"Unique case entries : {len(entries)}")
print(f"Distinct gx values  : {len(gx_distinct)} -> {gx_distinct}")
print(f"Distinct gy values  : {len(gy_distinct)} -> {gy_distinct}")
print(f"ratio range (Q4.12) : {min(ratio_vals)} ~ {max(ratio_vals)}")
print(f"ratio range (float) : {min(ratio_vals)/(1<<Q):.6f} ~ {max(ratio_vals)/(1<<Q):.6f}")

# ---------------------------------------------------------------------------
# Write SystemVerilog
# ---------------------------------------------------------------------------

OUTFILE = "refract_ratio_lut.sv"

with open(OUTFILE, "w") as f:

    f.write("// =============================================================\n")
    f.write("// Auto-generated LUT: -coef/(-eta+coef)\n")
    f.write("// Indexed by {gx, gy, RI}\n")
    f.write("// All intermediate arithmetic quantized to Q4.12 after each step.\n")
    f.write("//\n")
    f.write("//   gx, gy : Q4.12 signed 16-bit  (= 2*u^7, 2*v^7)\n")
    f.write("//   RI     : 4-bit unsigned, range 2~15\n")
    f.write("//   output : Q4.12 signed 16-bit\n")
    f.write("//\n")
    f.write(f"//   Total entries : {len(entries)}\n")
    f.write(f"//   ratio range   : {min(ratio_vals)/(1<<Q):.6f} ~ "
            f"{max(ratio_vals)/(1<<Q):.6f}\n")
    f.write("// =============================================================\n\n")

    f.write("logic signed [15:0] ratio_lut;\n\n")
    f.write("always_comb begin\n")
    f.write("    unique case ({gx, gy, RI})  // 16 + 16 + 4 = 36-bit key\n")

    prev_gx = None
    for (gx_q, gy_q, RI), ratio_q in sorted(entries.items()):
        if gx_q != prev_gx:
            if prev_gx is not None:
                f.write("\n")
            f.write(f"        // gx = {gx_q} (Q4.12) = {gx_q/(1<<Q):.8f}\n")
            prev_gx = gx_q

        gx_lit  = fixed_hex(gx_q)
        gy_lit  = fixed_hex(gy_q)
        rat_lit = fixed_hex(ratio_q)
        f.write(f"        {{{gx_lit}, {gy_lit}, 4'd{RI:2d}}}: "
                f"ratio_lut = {rat_lit};\n")

    f.write("\n")
    f.write("        default: ratio_lut = 16'sh0000;  // should never hit\n")
    f.write("    endcase\n")
    f.write("end\n")

print(f"\nWritten: {OUTFILE}")