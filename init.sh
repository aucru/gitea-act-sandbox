#!/bin/bash
set -e

echo "⏳ 等待 Gitea 服务启动..."
until curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; do
  sleep 2
done
echo "✅ Gitea 已就绪!"

# 1. 在容器内创建初始管理员 (绕过 Web 安装界面)
echo "🔐 创建 Gitea 初始管理员 (root)..."
docker exec gitea gitea admin user create --admin --username root --password 12345678 --email root@local.com --must-change-password=false

# 2. 通过 API 获取管理员 Token
echo "🔑 获取 API Token..."
TOKEN_RESPONSE=$(curl -s -u root:root123 -X POST "http://localhost:3000/api/v1/users/root/tokens" \
  -H "Content-Type: application/json" \
  -d '{"name": "init-token", "scopes": ["write:repository", "write:user", "read:user"]}')
TOKEN=$(echo "${TOKEN_RESPONSE}" | grep -o '"sha1":"[^"]*' | cut -d'"' -f4)

# 3. 创建用于 CI 的普通用户
echo "👤 创建 CI 用户 (act-user)..."
curl -s -X POST "http://localhost:3000/api/v1/admin/users" \
  -H "Authorization: token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username": "act-user", "email": "act@local.com", "password": "act-password", "must_change_password": false}'

# 4. 为 act-user 创建仓库
echo "📦 创建测试仓库 (test-repo)..."
curl -s -X POST "http://localhost:3000/api/v1/user/repos" \
  -u act-user:act-password \
  -H "Content-Type: application/json" \
  -d '{"name": "test-repo", "auto_init": false, "private": false}'

# 5. 初始化本地 git 并推送到 Gitea
echo "🚀 推送示例代码和 Workflow 到 Gitea..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
git init
git config user.email "act@local.com"
git config user.name "Act User"

# 复制 app 和 workflows 目录
cp -r "$(dirname "$0")/app" .
cp -r "$(dirname "$0")/workflows" .
mkdir -p .gitea
mv workflows/ci.yml .gitea/workflows/ci.yml
rm -rf workflows

git add .
git commit -m "Initial commit: http server and ci workflow"

# 强制推送 (使用包含凭据的 URL)
git remote add origin http://act-user:act-password@localhost:3000/act-user/test-repo.git
git branch -M main
git push -u origin main

cd - > /dev/null
rm -rf "$TEMP_DIR"

echo "🎉 初始化完成！你现在可以运行 ./run-act.sh 进行测试。"