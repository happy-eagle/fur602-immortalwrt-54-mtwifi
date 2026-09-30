#!/usr/bin/env bash
# 一键：创建 GitHub 仓库 → 推送 → 触发云编译 → 轮询结果
#
# 用法：
#   GITHUB_TOKEN=<你的PAT> ./push-and-build.sh [仓库名] [public|private]
#
# 例：
#   GITHUB_TOKEN=ghp_xxx ./push-and-build.sh fur602-immortalwrt-54-mtwifi private
#
set -euo pipefail

API="https://api.github.com"
WF="build-fur602.yml"
NAME="${1:-fur602-immortalwrt-54-mtwifi}"
VIS="${2:-private}"
BRANCH="main"

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "错误：请先 export GITHUB_TOKEN=<Personal Access Token>" >&2
  echo "需要权限：repo（全部）+ workflow" >&2
  exit 1
fi

AUTH_H=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")

echo "==> 校验 token ..."
USER_JSON=$(curl -fsS "${AUTH_H[@]}" "$API/user" || true)
LOGIN=$(printf '%s' "$USER_JSON" | grep -oE '"login": *"[^"]*"' | head -1 | sed -E 's/.*: *"([^"]*)".*/\1/' || true)
if [ -z "$LOGIN" ]; then
  echo "错误：token 无效或无法读取用户信息" >&2
  exit 1
fi
echo "    用户: $LOGIN"

# 检查 workflow 权限（token 是否带 workflow scope）
SCOPES=$(curl -fsS -I "${AUTH_H[@]}" "$API/user" | grep -i '^x-oauth-scopes:' | tr -d '\r' || true)
echo "    scopes: ${SCOPES#*: }"
case "$SCOPES" in
  *workflow*) ;;
  *) echo "警告：未检测到 workflow scope，可能无法触发 Actions（但推送不受影响）" >&2 ;;
esac

echo "==> 检查/创建仓库 $LOGIN/$NAME ..."
if curl -fsS "${AUTH_H[@]}" "$API/repos/$LOGIN/$NAME" >/dev/null 2>&1; then
  echo "    仓库已存在，直接复用"
  NEW_REPO=0
else
  curl -fsS -X POST "${AUTH_H[@]}" "$API/user/repos" \
    -d "{\"name\":\"$NAME\",\"private\":$([ "$VIS" = "private" ] && echo true || echo false),\"auto_init\":false}" \
    >/dev/null
  echo "    已创建（$VIS）"
  NEW_REPO=1
fi

echo "==> 提交本地文件 ..."
cd "$(dirname "$0")"
if [ ! -d .git ]; then git init -q; fi
git add -A
if [ -z "$(git status --porcelain)" ]; then
  echo "    无变更"
else
  git -c user.name="${GIT_AUTHOR_NAME:-workbuddy}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-workbuddy@users.noreply.github.com}" \
      commit -q -m "FUR-602: ImmortalWrt 5.4 + mtwifi cloud build"
  echo "    已提交"
fi
git branch -q -M "$BRANCH"

echo "==> 推送 ..."
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${LOGIN}/${NAME}.git"
# 关掉系统凭据管理器（helper-selector 会在无交互环境里卡死），token 已内嵌在 URL 里
GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.askPass= push -q -u origin "$BRANCH"
echo "    已推送到 https://github.com/$LOGIN/$NAME"

if [ "$NEW_REPO" = "1" ]; then sleep 5; fi

echo "==> 触发云编译 ..."
DISPATCH=$(curl -fsS -w '%{http_code}' -o /dev/null -X POST "${AUTH_H[@]}" \
  "$API/repos/$LOGIN/$NAME/actions/workflows/$WF/dispatches" \
  -d "{\"ref\":\"$BRANCH\"}" || true)
if [ "$DISPATCH" != "204" ]; then
  echo "    触发失败（HTTP $DISPATCH）。常见原因：workflow 权限不足，或 Actions 未启用。" >&2
  echo "    请手动打开：https://github.com/$LOGIN/$NAME/actions" >&2
  exit 1
fi
echo "    已触发"

echo "==> 等待 run 创建 ..."
RUN_ID=""
for i in $(seq 1 30); do
  RUN_ID=$(curl -fsS "${AUTH_H[@]}" \
    "$API/repos/$LOGIN/$NAME/actions/workflows/$WF/runs?per_page=1" \
    | grep -oE '"id": *[0-9]+' | head -1 | grep -oE '[0-9]+$' || true)
  [ -n "$RUN_ID" ] && break
  sleep 2
done
if [ -z "$RUN_ID" ]; then
  echo "    未能获取 run id，请打开 https://github.com/$LOGIN/$NAME/actions 查看" >&2
  exit 0
fi

echo "==> 构建已启动"
echo "    run: https://github.com/$LOGIN/$NAME/actions/runs/$RUN_ID"
echo "    通常 2~4 小时完成，完成后在同一页面的 Artifacts 下载固件"
