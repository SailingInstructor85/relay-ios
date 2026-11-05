#!/usr/bin/env python3
"""CI: schreibt authorized_keys für den Testschlüssel (fester Test-Seed der UI-Tests).

Der öffentliche Schlüssel wird mit einer kleinen Ed25519-Implementierung (RFC 8032) aus dem Seed berechnet.
Aufruf: ci_keygen.py <seed-hex> <mock-pfad> <ausgabe-datei>
"""
import base64, hashlib, struct, sys

p = 2**255 - 19
d = -121665 * pow(121666, p - 2, p) % p
q = 2**252 + 27742317777372353535851937790883648493


def inv(x): return pow(x, p - 2, p)


def add(P, Q):
    x1, y1 = P; x2, y2 = Q
    x3 = (x1 * y2 + x2 * y1) * inv(1 + d * x1 * x2 * y1 * y2) % p
    y3 = (y1 * y2 + x1 * x2) * inv(1 - d * x1 * x2 * y1 * y2) % p
    return x3, y3


def mul(s, P):
    R = (0, 1)
    while s:
        if s & 1: R = add(R, P)
        P = add(P, P); s >>= 1
    return R


By = 4 * inv(5) % p
Bx = pow((By * By - 1) * inv(d * By * By + 1) % p, (p + 3) // 8, p)
if (Bx * Bx - (By * By - 1) * inv(d * By * By + 1)) % p: Bx = Bx * pow(2, (p - 1) // 4, p) % p
if Bx % 2: Bx = p - Bx
B = (Bx, By)


def pub(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    x, y = mul(a, B)
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


seed = bytes.fromhex(sys.argv[1])
pk = pub(seed)
blob = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32) + pk
line = 'restrict,pty,command="python3 %s" ssh-ed25519 %s relay-ui-test\n' % (sys.argv[2], base64.b64encode(blob).decode())
open(sys.argv[3], "w").write(line)
print("authorized_keys geschrieben")
