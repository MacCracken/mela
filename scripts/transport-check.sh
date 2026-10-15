#!/usr/bin/env bash
# Live transport check (D7 / D10, docs/development/rust-parity.md).
#
# `cyrius test` never opens a socket, so this is where mela's real HTTP client
# meets a server: a local Python server (stdlib only) on 127.0.0.1. Checks:
#   1. a 1.5 MB artifact streams to disk byte-exact (the old buffered path
#      failed anything over 256 KiB);
#   2. a 302 redirect is followed;
#   3. a 404 fails and leaves no file behind;
#   4. an artifact over the size ceiling fails and leaves no partial file;
#   5. a stalled server is abandoned at the deadline;
#   6. every request carries User-Agent agnos-marketplace/<VERSION>;
#   7. rc_publish_signed sends X-Package-Metadata with the signature as hex.
#
# Run from anywhere: scripts/transport-check.sh. Needs python3.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "transport-check: FAIL: $*" >&2; exit 1; }
command -v python3 >/dev/null || fail "python3 is required"

T="$(mktemp -d)"
SRV=""
cleanup() {
  if [ -n "$SRV" ]; then kill "$SRV" 2>/dev/null || true; fi
  rm -rf "$T"
}
trap cleanup EXIT

mkdir -p build
cyrius build scripts/transport-check.cyr build/transport-check > "$T/build.log" 2>&1 \
  || { cat "$T/build.log" >&2; fail "helper did not build"; }
H=build/transport-check

head -c 1500000 /dev/urandom > "$T/big.bin"

cat > "$T/server.py" <<'PY'
import json, sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

root = sys.argv[1]
big = open(root + "/big.bin", "rb").read()
log = open(root + "/requests.jsonl", "a")
lock = threading.Lock()

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a):
        pass
    def record(self):
        with lock:
            log.write(json.dumps({
                "method": self.command, "path": self.path,
                "ua": self.headers.get("User-Agent"),
                "meta": self.headers.get("X-Package-Metadata"),
            }) + "\n")
            log.flush()
    def send_body(self, code, body, ctype="application/octet-stream"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        self.record()
        p = self.path
        if p == "/v1/packages/big/1.0.0/download":
            self.send_body(200, big)
        elif p == "/v1/packages/redir/1.0.0/download":
            self.send_response(302)
            self.send_header("Location", "/v1/packages/big/1.0.0/download")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif p == "/v1/packages/slow/1.0.0/download":
            time.sleep(60)
            self.send_body(200, b"late")
        else:
            self.send_body(404, b"not found", "text/plain")
    def do_POST(self):
        self.record()
        n = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(n)
        resp = {"name": "check", "version": "1.0.0", "download_url": "/x", "replaced": False}
        self.send_body(200, json.dumps(resp).encode(), "application/json")

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
srv.daemon_threads = True
with open(root + "/port", "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PY

python3 -I "$T/server.py" "$T" &
SRV=$!
for _ in $(seq 1 50); do
  [ -s "$T/port" ] && break
  sleep 0.1
done
[ -s "$T/port" ] || fail "test server did not start"
B="http://127.0.0.1:$(cat "$T/port")"

# 1. streams past the old 256 KiB cap, byte-exact
"$H" fetch "$B" big 1.0.0 "$T/a.bin" > /dev/null || fail "1.5 MB artifact did not download"
cmp "$T/big.bin" "$T/a.bin" || fail "downloaded artifact differs"

# 2. redirect followed
"$H" fetch "$B" redir 1.0.0 "$T/b.bin" > /dev/null || fail "redirect not followed"
cmp "$T/big.bin" "$T/b.bin" || fail "redirected artifact differs"

# 3. 404: failure, no file
if "$H" fetch "$B" missing 1.0.0 "$T/c.bin" > /dev/null; then fail "404 reported as success"; fi
[ ! -e "$T/c.bin" ] || fail "404 left a file behind"

# 4. over the size ceiling: failure, no partial file
if "$H" fetch "$B" big 1.0.0 "$T/d.bin" 1000000 > /dev/null; then fail "over-cap artifact accepted"; fi
[ ! -e "$T/d.bin" ] || fail "over-cap download left a partial file"

# 5. stalled server: abandoned at the 2 s deadline
start=$(date +%s)
if "$H" fetch "$B" slow 1.0.0 "$T/e.bin" 0 2 > /dev/null; then fail "stalled server reported as success"; fi
elapsed=$(( $(date +%s) - start ))
[ "$elapsed" -lt 10 ] || fail "stalled server held the client ${elapsed}s (deadline 2s)"
[ ! -e "$T/e.bin" ] || fail "timed-out download left a file behind"

# 7. publish_signed carries the metadata header
echo "bundle" > "$T/bundle.bin"
[ "$("$H" publish "$B" "$T/bundle.bin")" = "check" ] || fail "publish did not reach the registry"

# 6 + 7, from the server's request log
python3 -I - "$T/requests.jsonl" "agnos-marketplace/$(tr -d '[:space:]' < VERSION)" <<'PY' || fail "request log check failed"
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
want_ua = sys.argv[2]
bad = [r for r in rows if r["ua"] != want_ua]
assert not bad, f"wrong User-Agent: {bad[0]['ua']!r} (want {want_ua!r})"
posts = [r for r in rows if r["method"] == "POST"]
assert len(posts) == 1, f"expected one POST, saw {len(posts)}"
meta = json.loads(posts[0]["meta"])
assert meta["bundle_name"] == "check.agnos-agent", meta
assert meta["bundle_size"] == 7, meta
assert len(meta["bundle_sha256"]) == 64, meta
assert meta["signature"] == "ab" * 64, meta
PY

echo "transport-check: ok (1.5 MB streamed, redirect, 404, size cap, 2 s deadline, User-Agent, publish metadata)"
