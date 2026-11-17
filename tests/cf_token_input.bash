#!/usr/bin/env bash
# 真正 PTY：等隐藏输入生效后再发送模拟 Token，检查无回显及终端属性恢复。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == --read ]]; then
    # shellcheck source=/dev/null
    source <(sed '$d' "$ROOT/install.sh")
    original_terminal="$(stty -g)"
    if value="$(self_read_cf_token)"; then
        [[ "$value" == hidden_input_fixture_token_1234567890 && "$(stty -g)" == "$original_terminal" ]]
        printf 'INPUT_OK\n'
    else
        [[ "$(stty -g)" == "$original_terminal" ]]
        printf 'CANCELLED\n'
    fi
    exit 0
fi
python3 - "${BASH_SOURCE[0]}" <<'PY_TTY'
import errno, os, pty, select, sys, termios, time
for value, marker in ((b"hidden_input_fixture_token_1234567890\n", b"INPUT_OK"), (b"\x04", b"CANCELLED"), (b"short\n", b"CANCELLED")):
    pid, fd = pty.fork()
    if pid == 0:
        os.execv("/bin/bash", ["bash", sys.argv[1], "--read"])
    output = b""
    try:
        deadline = time.monotonic() + 10
        while "不回显".encode() not in output:
            assert time.monotonic() < deadline, "隐藏输入提示未出现"
            if select.select([fd], [], [], 0.1)[0]:
                output += os.read(fd, 65536)
        assert not (termios.tcgetattr(fd)[3] & termios.ECHO), "Token 输入仍会回显"
        os.write(fd, value)
        while True:
            assert time.monotonic() < deadline, "输入测试超时"
            if select.select([fd], [], [], 0.1)[0]:
                try:
                    chunk = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EIO: break
                    raise
                if not chunk: break
                output += chunk
        _, status = os.waitpid(pid, 0)
        assert os.waitstatus_to_exitcode(status) == 0 and marker in output
        if value != b"\x04": assert value.strip() not in output, "模拟 Token 出现在终端输出"
    finally:
        os.close(fd)
print("隐藏 Token 输入、格式失败/EOF 取消、终端属性恢复通过")
PY_TTY
