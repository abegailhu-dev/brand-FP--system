#!/usr/bin/env bash
# publish.sh — 一键发布 data.json 到公开链接（替代手动 GitHub Upload files）
#
# 用法:
#   ./publish.sh                      # 发布仓库根目录现有的 data.json
#   ./publish.sh ~/Downloads/data.json  # 把浏览器导出的 data.json 放进来并发布
#
# 流程: 校验JSON -> 自动打/抬升 _publishedVersion 时间戳 -> 提交 -> 推送 main
# 推送后约1分钟，所有人刷新公开链接即可看到最新数据。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$REPO_DIR/data.json}"
DST="$REPO_DIR/data.json"

cd "$REPO_DIR"

# 1) 若传入了外部文件(如浏览器导出的下载),复制覆盖
if [ "$SRC" != "$DST" ]; then
  [ -f "$SRC" ] || { echo "❌ 找不到文件: $SRC"; exit 1; }
  cp "$SRC" "$DST"
  echo "✓ 已载入: $SRC"
fi

# 2) 校验 JSON 合法 + 关键字段存在,并把 _publishedVersion 抬升为当前时间戳
#    (确保版本号严格递增,所有访问者才会自动采用最新数据)
VER=$(python3 - "$DST" << 'PY'
import json, sys, time
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
assert isinstance(d, dict), "data.json 顶层必须是对象"
assert 'employees' in d, "缺少 employees 字段"
new = int(time.time() * 1000)
old = d.get('_publishedVersion', 0)
if new <= old:           # 极端情况:同一毫秒内重复发布
    new = old + 1
d['_publishedVersion'] = new
d.pop('_baseVersion', None)
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print(new)
PY
)
echo "✓ JSON 校验通过,发布版本号: $VER ($(date -d @$((VER/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo $VER))"

# 3) 确保在 main 分支且与远端同步
git fetch origin main --quiet
git checkout main --quiet 2>/dev/null || true

# 4) 提交
if git diff --quiet -- data.json; then
  echo "ℹ️  data.json 无变化,无需发布"
  exit 0
fi
git add data.json
git commit -q -m "Publish data.json (version $VER)"

# 5) 推送(失败指数退避重试)
for i in 1 2 3 4; do
  if git push origin main; then
    echo "✅ 已发布到公开链接,约1分钟后生效。"
    exit 0
  fi
  wait=$((2 ** i)); echo "推送失败,$wait 秒后重试..."; sleep $wait
done
echo "❌ 推送失败,请检查网络/权限。"; exit 1
