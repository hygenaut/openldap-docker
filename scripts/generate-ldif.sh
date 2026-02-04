#!/bin/bash
set -e

# 解析参数
FORCE=false
if [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
    FORCE=true
fi

# 加载 .env 配置
if [ ! -f .env ]; then
    echo "[错误] .env 文件不存在" >&2
    exit 1
fi

source .env

# 从 LDAP_ROOT 提取 dc 组件
DOMAIN=$(echo "$LDAP_ROOT" | sed 's/dc=//g' | sed 's/,/./g')
DC_FIRST=$(echo "$LDAP_ROOT" | sed 's/dc=\([^,]*\).*/\1/')

TARGET_FILE="ldifs/00-structure.ldif"

# 检查目标文件是否存在
if [ -f "$TARGET_FILE" ] && [ "$FORCE" = false ]; then
    echo "[警告] 文件已存在: $TARGET_FILE"
    echo "使用 -f 或 --force 参数强制覆盖"
    exit 0
fi

echo "==> 从模板生成 LDIF 文件"
echo "  BASE_DN: $LDAP_ROOT"
echo "  DOMAIN: $DOMAIN"

# 生成 00-structure.ldif
sed "s/dc=example,dc=com/$LDAP_ROOT/g; s/example.com/$DOMAIN/g; s/dc: example/dc: $DC_FIRST/g; s/o: Example Organization/o: ${DOMAIN} Organization/g" \
    template/structure.ldif.template > "$TARGET_FILE"

echo "[完成] LDIF 文件生成完成: $TARGET_FILE"
