"""Isolated provider API and authoritative DNS for real Certbot/Pebble tests."""
import hashlib
import json
import socketserver
import struct
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

state_file = Path(sys.argv[1])
zone = "f" * 32
records = {}
metrics = {"created": {}, "denied": 0, "deleted": 0, "queries": 0}
lock = threading.Lock()
counter = 0


class API(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def answer(self, result=None, error=None):
        body = {"success": error is None, "result": result,
                "errors": [] if error is None else [error], "messages": []}
        if isinstance(result, list):
            body["result_info"] = {"page": 1, "per_page": 20, "total_pages": 1,
                                   "count": len(result), "total_count": len(result)}
        raw = json.dumps(body).encode()
        self.send_response(200 if error is None else 403)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def handle_api(self):
        global counter
        parsed = urlsplit(self.path)
        if parsed.path == "/metrics":
            with lock:
                self.answer(dict(metrics, records=list(records.values())))
            return
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        rights = json.loads(state_file.read_text()).get("tokens", {}).get(token, [])
        if "zone" not in rights or (self.command in ("POST", "DELETE") and "edit" not in rights):
            with lock:
                metrics["denied"] += 1
            self.answer(error={"code": 1009, "message": "Test permission denied: " + token})
            return
        query = parse_qs(parsed.query)
        if self.command == "GET" and parsed.path == "/client/v4/zones":
            self.answer([{"id": zone, "name": "example.test"}] if query.get("name") == ["example.test"] else [])
            return
        prefix = "/client/v4/zones/" + zone + "/dns_records"
        with lock:
            if self.command == "POST" and parsed.path == prefix:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                assert body["type"] == "TXT" and body["name"].rstrip(".") == "_acme-challenge.node.example.test"
                counter += 1
                record = dict(body, id=str(counter)); records[str(counter)] = record
                key = hashlib.sha256(token.encode()).hexdigest()
                metrics["created"][key] = metrics["created"].get(key, 0) + 1
                self.answer(record)
            elif self.command == "GET" and parsed.path == prefix:
                self.answer([r for r in records.values() if all(r.get(k) == v[0] for k, v in query.items() if k in ("name", "type", "content"))])
            elif self.command == "DELETE" and parsed.path.startswith(prefix + "/"):
                item = records.pop(parsed.path.rsplit("/", 1)[1]); metrics["deleted"] += 1
                self.answer(item)
            else:
                self.answer(error={"code": 1003, "message": "Unexpected test API endpoint"})

    do_GET = do_POST = do_DELETE = handle_api


def dns_response(raw):
    request_id, flags, questions, *_ = struct.unpack("!6H", raw[:12])
    assert questions == 1
    pos, parts = 12, []
    while raw[pos]:
        size = raw[pos]; assert 0 < size < 64
        parts.append(raw[pos + 1:pos + 1 + size].decode("ascii").lower()); pos += 1 + size
    pos += 1
    record_type, record_class = struct.unpack("!HH", raw[pos:pos + 4])
    name = ".".join(parts)
    with lock:
        metrics["queries"] += 1
        values = [r["content"] for r in records.values() if record_type == 16 and r["name"].rstrip(".").lower() == name]
    answer = b""
    for value in values:
        content = value.encode("ascii"); data = bytes([len(content)]) + content
        answer += b"\xc0\x0c" + struct.pack("!HHIH", 16, record_class, 0, len(data)) + data
    return struct.pack("!6H", request_id, 0x8400 | (flags & 0x0100), 1, len(values), 0, 0) + raw[12:pos + 4] + answer


class DNSUDP(socketserver.BaseRequestHandler):
    def handle(self):
        raw, sock = self.request
        sock.sendto(dns_response(raw), self.client_address)


class DNSTCP(socketserver.StreamRequestHandler):
    def handle(self):
        size = struct.unpack("!H", self.rfile.read(2))[0]
        response = dns_response(self.rfile.read(size))
        self.wfile.write(struct.pack("!H", len(response)) + response)


if __name__ == "__main__":
    for server in (socketserver.ThreadingUDPServer(("0.0.0.0", 8053), DNSUDP),
                   socketserver.ThreadingTCPServer(("0.0.0.0", 8053), DNSTCP)):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8055), API).serve_forever()
