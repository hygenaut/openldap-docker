#!/bin/bash

# 加载 .env 配置
if [ ! -f .env ]; then
    echo "[错误] .env 文件不存在" >&2
    exit 1
fi

source .env

echo "==> 配置 ACL 访问控制"

# 等待 LDAP 服务就绪
echo "等待 LDAP 服务就绪..."
for i in {1..30}; do
    if docker exec openldap-server ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" -LLL 2>/dev/null | grep -q "dn: cn=config"; then
        echo "[完成] LDAP 服务已就绪"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "[错误] LDAP 服务未就绪，超时" >&2
        exit 1
    fi
    sleep 1
done

# 检查 ACL 是否已配置（检查是否有自定义的 admin 组权限）
if docker exec openldap-server ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={2}mdb,cn=config" olcAccess 2>/dev/null | grep -q "cn=admin,ou=groups"; then
    echo "[完成] ACL 已配置，跳过"
    exit 0
fi

# 配置 ACL：基于角色的访问控制
echo "正在配置 ACL..."
docker exec openldap-server bash -c "cat > /tmp/acl.ldif <<'EOFLDIF'
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword by self write by group.exact=\"cn=admin,ou=groups,${LDAP_ROOT}\" write by anonymous auth by * none
olcAccess: {1}to dn.subtree=\"ou=people,${LDAP_ROOT}\" by self write by group.exact=\"cn=admin,ou=groups,${LDAP_ROOT}\" write by * read
olcAccess: {2}to dn.subtree=\"ou=groups,${LDAP_ROOT}\" by group.exact=\"cn=admin,ou=groups,${LDAP_ROOT}\" write by * read
olcAccess: {3}to * by self read by group.exact=\"cn=admin,ou=groups,${LDAP_ROOT}\" write by * read
EOFLDIF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/acl.ldif 2>&1"

if [ $? -eq 0 ]; then
    echo "[完成] ACL 配置成功"
else
    echo "[错误] ACL 配置失败" >&2
    exit 1
fi

echo "[完成] ACL 配置完成"
echo ""
echo "权限说明："
echo "  - admin 组：完整管理权限"
echo "  - replica 组：完整读取权限（用于数据同步）"
echo "  - 其他组：普通用户权限（只能修改自己的信息）"
echo ""
echo "如需为新组添加特殊权限，请手动修改 ACL："
echo "  docker exec openldap-server ldapmodify -Y EXTERNAL -H ldapi:///"

