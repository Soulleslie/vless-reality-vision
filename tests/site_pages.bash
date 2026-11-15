#!/usr/bin/env bash
# 六种布局、离线资源、重复调用稳定性、旧网页保护及创建失败；无需 root 或网络。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source <(sed '$d' "$ROOT/install.sh")
TEST_DIR="$(mktemp -d)"; trap 'rm -rf -- "$TEST_DIR"' EXIT
fixture() {
    SELF_DIR="$TEST_DIR/$1/state"; SELF_WEB="$TEST_DIR/$1/www"
    mkdir -p "$SELF_DIR/work"; : > "$SELF_DIR/files.sha256"
}
python3() {
    printf 'render\n' >> "$TEST_DIR/render.calls"
    # 只在测试进程替换随机源，生产渲染器没有测试开关或模板选择入口。
    command python3 -c '
import secrets, sys
wanted, variant = int(sys.argv[1]), int(sys.argv[2])
real, first = secrets.randbelow, True
def pick(n):
    global first
    if first:
        first = False
        assert n == 6
        return wanted
    return real(n)
secrets.randbelow = pick
secrets.choice = lambda values: values[(0, -1, -2)[variant]]
sys.argv = ["site-render", *sys.argv[4:]]
exec(compile(sys.stdin.read(), "site-render", "exec"))
' "$theme_index" "$variant" "$@"
}
for index in {0..13}; do
    theme_index=$((index % 6)); variant=$((index / 6))
    fixture "case-$index"
    started="$(date +%s%3N)"
    self_site_write
    printf '%s\n' "$(( $(date +%s%3N) - started ))" >> "$TEST_DIR/render-ms"
    [[ -f "$SELF_WEB/index.html" && "$(stat -c %a "$SELF_WEB/index.html")" == 644 && "$(stat -c %a "$SELF_WEB")" == 755 ]]
    self_file_owned "$SELF_WEB/index.html"
    [[ -z "$(find "$SELF_DIR/work" -mindepth 1 -print)" && "$(find "$SELF_WEB" -type f | wc -l)" == 1 ]]
    before="$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")"
    self_site_write
    [[ "$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")" == "$before" ]]
done
[[ "$(wc -l < "$TEST_DIR/render.calls")" == 14 ]]
command python3 - "$TEST_DIR" <<'PY_VALIDATE'
import pathlib, re, sys
from html.parser import HTMLParser
class Page(HTMLParser):
    def __init__(self):
        super().__init__(); self.tags=[]; self.ids=set(); self.links=[]; self.kind=None
    def handle_starttag(self, tag, attrs):
        attrs=dict(attrs); self.tags.append(tag)
        assert tag not in {"script", "iframe", "object", "embed", "form", "link", "img", "base"}, tag
        assert not any(k.lower().startswith("on") for k in attrs), attrs
        assert not any(k in attrs for k in ("src", "srcset", "action", "poster", "data")), attrs
        assert attrs.get("http-equiv", "").lower() != "refresh"
        if "id" in attrs:
            assert attrs["id"] not in self.ids
            self.ids.add(attrs["id"])
        if "href" in attrs:
            assert attrs["href"].startswith("#"), attrs
            self.links.append(attrs["href"][1:])
        if tag == "body": self.kind=attrs["class"]
    handle_startendtag=handle_starttag
root=pathlib.Path(sys.argv[1]); kinds=[]; titles=[]; colors=[]
for i in range(14):
    raw=(root/f"case-{i}/www/index.html").read_bytes()
    assert 0 < len(raw) <= 16384, len(raw)
    text=raw.decode("utf-8"); page=Page(); page.feed(text); page.close()
    assert text.startswith("<!doctype html>") and text.endswith("</html>\n")
    assert all(page.tags.count(t)==1 for t in ("html","head","title","style","body","main","h1","footer"))
    assert page.tags.count("article")==3 and page.tags.count("svg")>=1
    assert set(page.links) <= page.ids and {"top","collection","about"} <= page.ids
    assert not re.search(r"url\s*\(|@import|@font-face", text, re.I)
    assert not any(v in text.lower() for v in ("vless://", "reality", "xray", "privatekey", "api_token"))
    kinds.append(page.kind); titles.append(re.search(r"<title>(.*?)</title>",text).group(1))
    colors.append(re.search(r"--paper:([^;]+)",text).group(1))
assert len(set(kinds))==6
assert kinds[0]==kinds[6] and titles[0]!=titles[6] and colors[0]!=colors[6]
assert colors[12] == colors[13] == "#20232d"  # 强制覆盖深色配色。
print("六种独立布局、自包含 HTML、有效锚点、无脚本/外链与体积限制通过")
PY_VALIDATE
unset -f python3

# 旧版已归属网页重复调用也保持字节不变；手工修改、符号链接和其他文件均不覆盖。
fixture legacy; mkdir -p "$SELF_WEB"
printf '<!doctype html><title>旧版网页</title>\n' > "$SELF_WEB/index.html"
self_track "$SELF_WEB/index.html"
before="$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")"
python3() { printf 'unexpected render\n' >&2; return 1; }
self_site_write
[[ "$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")" == "$before" ]]
printf 'user edit\n' >> "$SELF_WEB/index.html"
edited="$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")"
if self_site_write >/dev/null 2>&1; then exit 1; fi
[[ "$(sha256sum "$SELF_WEB/index.html" "$SELF_DIR/files.sha256")" == "$edited" ]]
fixture linked; mkdir -p "$SELF_WEB"
printf 'foreign\n' > "$TEST_DIR/foreign"
ln -s "$TEST_DIR/foreign" "$SELF_WEB/index.html"
if self_site_write >/dev/null 2>&1; then exit 1; fi
[[ "$(< "$TEST_DIR/foreign")" == foreign && -L "$SELF_WEB/index.html" ]]
fixture linked-dir; ln -s "$TEST_DIR" "$SELF_WEB"
if self_site_write >/dev/null 2>&1; then exit 1; fi
[[ -L "$SELF_WEB" ]]

# 渲染失败或空输出不发布网页，暂存文件清理，原校验记录不动。
for failure in partial empty; do
    fixture "fail-$failure"; before="$(sha256sum "$SELF_DIR/files.sha256")"
    python3() { if [[ "$failure" == partial ]]; then printf 'partial'; return 1; fi; return 0; }
    if self_site_write >/dev/null 2>&1; then exit 1; fi
    [[ ! -e "$SELF_WEB" && -z "$(find "$SELF_DIR/work" -mindepth 1 -print)" && "$(sha256sum "$SELF_DIR/files.sha256")" == "$before" ]]
done
printf '网页重复调用稳定、旧版/用户文件保护与失败暂存清理通过\n'
command python3 - "$TEST_DIR/render-ms" <<'PY_TIMING'
import statistics, sys
values=[int(line) for line in open(sys.argv[1])]
print(f"首次生成 {len(values)} 个样本：中位数 {statistics.median(values):g} ms；仅新安装执行一次")
PY_TIMING
if [[ "${1:-}" == --preview ]]; then
    mkdir -p -- "${2:?请提供开发预览输出目录}"
    for index in {0..13}; do install -m 644 "$TEST_DIR/case-$index/www/index.html" "$2/template-$index.html"; done
fi
