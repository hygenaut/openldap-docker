#!/bin/bash
set -e

# 加载 .env 配置
if [ ! -f .env ]; then
    echo "[错误] .env 文件不存在" >&2
    exit 1
fi

source .env

CONTAINER="openldap-server"
ENABLE_REPLICATION=${ENABLE_REPLICATION:-no}
SERVER_ID=${SERVER_ID:-1}
REPLICATION_HOSTS=${REPLICATION_HOSTS:-}
REPLICATION_USER=${REPLICATION_USER:-replica_admin}

# 如果未启用复制，跳过配置
if [ "$ENABLE_REPLICATION" != "yes" ]; then
    echo "[跳过] 复制功能未启用（ENABLE_REPLICATION=$ENABLE_REPLICATION）"
    exit 0
fi

# 如果没有配置其他节点，跳过配置
if [ -z "$REPLICATION_HOSTS" ]; then
    echo "[跳过] 未配置其他复制节点（REPLICATION_HOSTS 为空）"
    echo "[提示] 这是单节点模式，如需多主复制，请在 .env 中配置 REPLICATION_HOSTS"
    exit 0
fi

echo "==> 配置多主复制"
echo "当前节点 ID: $SERVER_ID"
echo "复制节点: $REPLICATION_HOSTS"

# 等待 LDAP 服务就绪
echo "等待 LDAP 服务就绪..."
for i in {1..30}; do
    if docker exec "$CONTAINER" ldapsearch -x -H ldap://localhost:1389 -b "" -s base &>/dev/null; then
        echo "[完成] LDAP 服务已就绪"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "[错误] LDAP 服务启动超时" >&2
        exit 1
    fi
    sleep 2
done

# 配置 ServerID
echo "==> 配置 ServerID"
docker exec "$CONTAINER" bash -c "cat > /tmp/serverid.ldif <<'EOFLDIF'
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: ${SERVER_ID}
EOFLDIF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/serverid.ldif 2>&1" | grep -v "^SASL" || true

# 配置 syncrepl（从其他节点同步数据）
echo "==> 配置 syncrepl"

# 将 REPLICATION_HOSTS 转换为数组
IFS=',' read -ra HOSTS <<< "$REPLICATION_HOSTS"
RID=1

# 生成 syncrepl 配置
SYNCREPL_CONFIG=""
for host in "${HOSTS[@]}"; do
    host=$(echo "$host" | xargs)  # 去除空格
    SYNCREPL_CONFIG="${SYNCREPL_CONFIG}olcSyncrepl: rid=${RID} provider=${host} bindmethod=simple binddn=\"uid=${REPLICATION_USER},ou=people,${LDAP_ROOT}\" credentials=\"${REPLICATION_PASSWORD}\" searchbase=\"${LDAP_ROOT}\" type=refreshAndPersist retry=\"5 5 300 +\" timeout=1
"
    RID=$((RID + 1))
done

# 添加 MirrorMode 配置
docker exec "$CONTAINER" bash -c "cat > /tmp/syncrepl.ldif <<'EOFLDIF'
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcSyncrepl
${SYNCREPL_CONFIG}-
add: olcMirrorMode
olcMirrorMode: TRUE
EOFLDIF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/syncrepl.ldif 2>&1" | grep -v "^SASL" || true

# 配置 ACL（允许复制用户读取所有数据）
echo "==> 配置复制 ACL"
docker exec "$CONTAINER" bash -c "cat > /tmp/replication-acl.ldif <<'EOFLDIF'
dn: olcDatabase={2}mdb,cn=config
changetype: modify
add: olcAccess
olcAccess: {0}to * by dn.exact=\"uid=${REPLICATION_USER},ou=people,${LDAP_ROOT}\" read by * break
EOFLDIF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/replication-acl.ldif 2>&1" | grep -v "^SASL" || true

echo "[完成] 多主复制配置完成"
echo ""
echo "复制信息："
echo "  当前节点 ID: ${SERVER_ID}"
echo "  复制用户: uid=${REPLICATION_USER},ou=people,${LDAP_ROOT}"
echo "  复制节点数: ${#HOSTS[@]}"
echo ""
echo "注意事项："
echo "  1. 确保所有节点的 SERVER_ID 唯一"
echo "  2. 确保所有节点的 REPLICATION_HOSTS 包含其他节点地址"
echo "  3. 确保所有节点的 REPLICATION_USER 和 REPLICATION_PASSWORD 相同"
echo "  4. 复制用户必须在 LDAP 中存在且有读取权限"
echo "  5. 所有节点都可读写，数据自动同步"
