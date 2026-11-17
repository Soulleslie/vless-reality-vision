#!/usr/bin/env bash
# 真实交互期间自动续期锁可用；提交后串行，域名/安装变化时拒绝误应用。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT/tests/cf_token.bash" <<'PY_LOCK'
import errno, fcntl, hashlib, json, os, pathlib, pty, re, select, shutil, signal, sys, termios, time
os.umask(0o077)
for scenario in ("ok", "domain", "reinstall"):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv("/bin/bash", ["bash", sys.argv[1], "--interactive-lock", scenario])
    output, reaped = b"", False
    try:
        deadline = time.monotonic() + 20
        while "不回显".encode() not in output:
            assert time.monotonic() < deadline, "Token 提示未出现"
            if select.select([fd], [], [], 0.1)[0]: output += os.read(fd, 65536)
        root = pathlib.Path(re.search(rb"TEST_SELF_DIR=([^\r\n]+)", output)[1].decode())
        case = root.parent
        assert not (termios.tcgetattr(fd)[3] & termios.ECHO)
        with open(root / "operation.lock", "a+") as operation:
            fcntl.flock(operation, fcntl.LOCK_EX | fcntl.LOCK_NB)  # Input must not block automatic renewal.
            if scenario == "domain":
                marker = case / "xray/.vless-reality-owned"
                lines = marker.read_text().splitlines(); lines[1] = "other.example.com"
                marker.write_text("\n".join(lines) + "\n")
                state = root / "state.json"; data = json.loads(state.read_text()); data["domain"] = lines[1]
                state.write_text(json.dumps(data) + "\n")
                manifest = root / "files.sha256"
                manifest.write_text("\n".join(hashlib.sha256(state.read_bytes()).hexdigest() + "  " + str(state)
                    if entry.endswith("  " + str(state)) else entry for entry in manifest.read_text().splitlines()) + "\n")
                (root / "acme/renewal/node.example.com.conf").rename(root / "acme/renewal/other.example.com.conf")
                (root / "acme/live/node.example.com").rename(root / "acme/live/other.example.com")
            elif scenario == "reinstall":
                old_root = case / "previous-self"
                root.rename(old_root); shutil.copytree(old_root, root)
            value = b"new_cloudflare_token_fixture_0987654321\n"
            os.write(fd, value)
            time.sleep(0.1)
            assert not (case / "certbot.calls").exists()
            fcntl.flock(operation, fcntl.LOCK_UN)
        while True:
            assert time.monotonic() < deadline, "Token 交互锁测试超时"
            if select.select([fd], [], [], 0.1)[0]:
                try: chunk = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EIO: break
                    raise
                if not chunk: break
                output += chunk
        _, status = os.waitpid(pid, 0); reaped = True
        assert os.waitstatus_to_exitcode(status) == 0, output.decode(errors="replace")
        assert value.strip() not in output
        assert (b"INTERACTIVE_TOKEN_OK" if scenario == "ok" else b"CONTEXT_CHANGED") in output
        if scenario != "ok": assert "等待输入期间".encode() in output
    finally:
        if not reaped:
            try: os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError: pass
            os.waitpid(pid, 0)
        os.close(fd)
print("Token 输入不阻塞自动续期、提交后串行、域名/安装切换保护通过")
PY_LOCK
