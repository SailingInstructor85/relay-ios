#!/bin/bash
# CI: eigener sshd auf 127.0.0.1:2222 mit eingeschränktem Testschlüssel, der nur das Mock-Gateway startet.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D=/tmp/relaymock
SEED=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff
rm -rf "$D"; mkdir -p "$D/control"
python3 "$ROOT/testing/ci_keygen.py" "$SEED" "$ROOT/testing/mock_gateway.py" "$D/authorized_keys"
# zweiter Schlüssel nur für die Prüfung mit gewöhnlichem ssh
ssh-keygen -q -t ed25519 -N "" -f "$D/verify_key"
echo "restrict,pty,command=\"python3 $ROOT/testing/mock_gateway.py\" $(cat "$D/verify_key.pub")" >> "$D/authorized_keys"
ssh-keygen -q -t ed25519 -N "" -f "$D/host_key"
cat > "$D/sshd_config" <<CFG
Port 2222
ListenAddress 127.0.0.1
HostKey $D/host_key
AuthorizedKeysFile $D/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
StrictModes no
AllowUsers $(whoami)
PidFile $D/sshd.pid
LogLevel VERBOSE
CFG
chmod -R a+rwX "$D"; chmod 600 "$D/host_key" "$D/verify_key"
sudo /usr/sbin/sshd -f "$D/sshd_config" -E "$D/sshd.log"
sleep 1
echo "sshd laeuft:"; pgrep -fl "sshd -f $D" || { sudo cat "$D/sshd.log"; exit 1; }
# Prüfung mit gewöhnlichem ssh: hello -> hello_ok
OUT=$(printf '{"type":"hello","since_seq":0,"client":"ci"}\n{"type":"rpc","id":"1","method":"ping","params":{}}\n' \
  | ssh -o ConnectTimeout=10 -i "$D/verify_key" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$(whoami)@127.0.0.1" serve | head -c 3000 || true)
echo "$OUT" | cut -c1-300
echo "$OUT" | grep -q hello_ok || { echo "FEHLER: kein hello_ok ueber ssh"; sudo tail -30 "$D/sshd.log"; exit 1; }
echo "ssh-Pruefung ok"
rm -f "$D/state.json" "$D/rpc.jsonl"; chmod -R a+rwX "$D" 2>/dev/null || true
