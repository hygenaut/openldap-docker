# OpenLDAP Docker 部署

基于 Docker 的 OpenLDAP 服务，集成 LDAP Account Manager (LAM) 管理界面，支持 TLS/SSL 加密连接。

## 项目简介

本项目提供了一个完整的 LDAP 服务解决方案：
- **OpenLDAP 服务器** - 企业级目录服务
- **LDAP Account Manager** - Web 管理界面
- **Nginx 反向代理** - HTTPS 访问支持
- **自动化脚本** - 一键部署和管理

## 快速开始

### 1. 配置环境变量

复制示例配置文件并修改：

```bash
cp .env.example .env
vim .env
```

**必须修改的配置项：**
- `LDAP_DOMAIN` - 你的域名（如：example.com）
- `LDAP_ROOT` - LDAP 根 DN（如：dc=example,dc=com）
- `LDAP_ADMIN_PASSWORD` - 管理员密码（强密码）
- `LDAP_CONFIG_ADMIN_PASSWORD` - 配置管理员密码
- `LDAP_ACCESSLOG_ADMIN_PASSWORD` - 日志管理员密码
- `LAM_PASSWORD` - LAM 管理界面密码

### 2. 准备 TLS 证书

将你的 SSL 证书放入 `certs/` 目录：
- `certs/openldap.crt` - 服务器证书
- `certs/openldap.key` - 私钥
- `certs/openldapCA.crt` - CA 证书

**如果没有证书，可以生成自签名证书：**

```bash
# 生成 CA 证书
openssl genrsa -out certs/openldapCA.key 2048
openssl req -x509 -new -nodes -key certs/openldapCA.key -sha256 -days 3650 \
  -out certs/openldapCA.crt -subj "/CN=My CA"

# 生成服务器证书
openssl genrsa -out certs/openldap.key 2048
openssl req -new -key certs/openldap.key -out certs/openldap.csr \
  -subj "/CN=ldap.example.com"
openssl x509 -req -in certs/openldap.csr -CA certs/openldapCA.crt \
  -CAkey certs/openldapCA.key -CAcreateserial -out certs/openldap.crt \
  -days 3650 -sha256

# 设置权限
sudo chown -R 1001:1001 certs/
```

### 3. 启动服务

使用部署脚本一键启动：

```bash
./deploy.sh init
```

部署脚本会自动完成：
- 创建必要的目录
- 初始化 LAM 配置
- 生成 LDIF 文件
- 设置证书权限
- 启动所有服务
- 加载 LDAP Schema
- 配置访问控制（ACL）

### 4. 访问服务

**LDAP Account Manager 管理界面：**
- 访问地址：`https://your-domain` 或 `https://localhost`
- 登录账号：`cn=admin,dc=example,dc=com`（根据你的配置）
- 登录密码：`.env` 中的 `LDAP_ADMIN_PASSWORD`

**LDAP 服务端口：**
- LDAP: `389`
- LDAPS: `636`

## 服务管理

### 启动服务

```bash
docker compose up -d
```

### 停止服务

```bash
docker compose down
```

### 重启服务

```bash
docker compose restart
```

### 查看日志

```bash
# 查看所有服务日志
docker compose logs -f

# 查看 OpenLDAP 日志
docker logs openldap-server -f

# 查看 LAM 日志
docker logs lam -f

# 查看 Nginx 日志
docker logs nginx -f
```

## 数据备份

### 备份数据

备份以下目录即可保留所有数据：

```bash
# 创建备份目录
mkdir -p backups/$(date +%Y%m%d)

# 备份 OpenLDAP 数据
sudo tar czf backups/$(date +%Y%m%d)/openldap-data.tar.gz openldap-data/

# 备份 LAM 配置
tar czf backups/$(date +%Y%m%d)/lam-config.tar.gz lam/

# 备份环境配置
cp .env backups/$(date +%Y%m%d)/
```

### 恢复数据

```bash
# 停止服务
docker compose down

# 恢复 OpenLDAP 数据
sudo rm -rf openldap-data/
sudo tar xzf backups/20260205/openldap-data.tar.gz

# 恢复 LAM 配置
rm -rf lam/
tar xzf backups/20260205/lam-config.tar.gz

# 恢复环境配置
cp backups/20260205/.env .

# 启动服务
docker compose up -d
```

## 用户管理

### 创建用户

使用脚本创建用户：

```bash
# 创建普通用户
./scripts/create-user.sh -u zhangsan -p Password123 -n "Zhang San"

# 创建管理员用户（加入 admin 组）
./scripts/create-user.sh -u admin_user -p Admin@123 -g admin -n "Admin User"
```

### 通过 LAM 管理用户

1. 访问 LAM 管理界面
2. 使用管理员账号登录
3. 在 "Users" 或 "Groups" 菜单中管理用户和组

## 高级功能

### 手动生成 LDIF 文件

```bash
# 生成 LDIF（不覆盖已存在的文件）
./deploy.sh generate-ldif

# 强制覆盖
./scripts/generate-ldif.sh -f
```

### 配置访问控制（ACL）

```bash
./deploy.sh configure-acl
```

当前 ACL 配置：
- **admin 组**：完整管理权限
- **普通用户**：可修改自己的信息，读取其他用户信息
- **匿名用户**：仅可进行身份验证

### LDAP 多主复制（Multi-Master）

OpenLDAP 支持多主复制（N-Way Multi-Master），所有节点都可读写，数据自动同步。

#### 架构说明

- **多主模式**：所有节点都可读写，无主从之分
- **自动同步**：任意节点的修改会自动同步到其他节点
- **高可用**：任意节点故障不影响其他节点
- **地理分布**：可部署在不同地区，就近访问

#### 配置步骤

**1. 节点 1 配置（如：北京）**

编辑 `.env` 文件：

```bash
# 启用复制
ENABLE_REPLICATION=yes

# 当前节点 ID（必须唯一）
SERVER_ID=1

# 其他节点地址（逗号分隔）
REPLICATION_HOSTS=ldap://node2.example.com:389,ldap://node3.example.com:389

# 复制用户配置（所有节点必须相同）
REPLICATION_USER=replica_admin
REPLICATION_PASSWORD=ChangeMe123!
```

部署：

```bash
./deploy.sh init
```

**2. 节点 2 配置（如：上海）**

复制整个项目到节点 2，编辑 `.env` 文件：

```bash
# 启用复制
ENABLE_REPLICATION=yes

# 当前节点 ID（必须唯一）
SERVER_ID=2

# 其他节点地址
REPLICATION_HOSTS=ldap://node1.example.com:389,ldap://node3.example.com:389

# 复制用户配置（与节点 1 相同）
REPLICATION_USER=replica_admin
REPLICATION_PASSWORD=ChangeMe123!
```

部署：

```bash
./deploy.sh init
```

**3. 节点 3 配置（如：深圳）**

复制整个项目到节点 3，编辑 `.env` 文件：

```bash
# 启用复制
ENABLE_REPLICATION=yes

# 当前节点 ID（必须唯一）
SERVER_ID=3

# 其他节点地址
REPLICATION_HOSTS=ldap://node1.example.com:389,ldap://node2.example.com:389

# 复制用户配置（与节点 1 相同）
REPLICATION_USER=replica_admin
REPLICATION_PASSWORD=ChangeMe123!
```

部署：

```bash
./deploy.sh init
```

#### 验证复制状态

在任意节点添加数据：

```bash
# 在节点 1 添加用户
./scripts/create-user.sh -u testuser -p Test123! -n "Test User"

# 在节点 2 查询（应该能看到新用户）
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=com" \
  -D "cn=admin,dc=example,dc=com" -w "your-password" "(uid=testuser)"
```

#### 单节点模式

如果只部署单个节点，保持默认配置即可：

```bash
# 不启用复制
ENABLE_REPLICATION=no
```

或者启用但不配置其他节点：

```bash
# 启用复制但无其他节点
ENABLE_REPLICATION=yes
SERVER_ID=1
REPLICATION_HOSTS=
```

#### 自定义复制用户

默认使用 `replica_admin` 用户进行同步，可以自定义：

```bash
# 使用自定义用户
REPLICATION_USER=my_sync_user
REPLICATION_PASSWORD=MySecurePass123!
```

**注意**：自定义用户必须：
1. 在 LDAP 中存在（在 `ou=people` 下）
2. 有读取所有数据的权限
3. 所有节点使用相同的用户名和密码

#### 注意事项

1. **SERVER_ID 必须唯一**：每个节点的 SERVER_ID 必须不同（1-999）
2. **用户凭据必须相同**：所有节点的 REPLICATION_USER 和 REPLICATION_PASSWORD 必须相同
3. **网络互通**：所有节点之间必须能通过 LDAP 端口（389）互相访问
4. **时间同步**：建议所有节点使用 NTP 同步时间
5. **冲突处理**：同时修改同一条目时，以最后写入为准
6. **安全建议**：生产环境建议使用自定义复制用户，避免使用默认的 replica_admin

## 目录结构

```
.
├── certs/                    # TLS 证书
├── lam/                      # LAM 配置数据
├── openldap-data/            # OpenLDAP 数据（持久化）
├── nginx/                    # Nginx 配置
├── scripts/                  # 管理脚本
├── template/                 # LDIF 模板
├── .env                      # 环境配置（敏感信息）
├── .env.example              # 配置示例
├── docker-compose.yml        # Docker Compose 配置
└── deploy.sh                 # 部署脚本
```

## 故障排查

### LDAPS 连接失败

检查证书权限：
```bash
sudo chown -R 1001:1001 certs/
docker compose restart openldap-server
```

### LAM 无法访问

检查容器状态：
```bash
docker compose ps
docker logs lam
```

### 忘记管理员密码

需要重新初始化（会丢失数据）：
```bash
docker compose down
sudo rm -rf openldap-data/
./deploy.sh init
```

## 安全建议

1. **使用强密码** - 所有密码至少 12 位，包含大小写字母、数字和特殊字符
2. **保护 .env 文件** - 不要提交到版本控制系统
3. **使用正式证书** - 生产环境使用 Let's Encrypt 等 CA 签发的证书
4. **定期备份** - 建议每天自动备份数据
5. **限制网络访问** - 使用防火墙限制 LDAP 端口访问
6. **及时更新** - 定期更新 Docker 镜像

## 技术栈

- OpenLDAP (Bitnami)
- LDAP Account Manager
- Nginx
- Docker & Docker Compose

## 许可证

本项目采用 [AGPL-3.0](LICENSE) 许可证。

## 支持

如有问题，请查看：
- [OpenLDAP 文档](https://www.openldap.org/doc/)
- [LAM 文档](https://www.ldap-account-manager.org/lamcms/)
