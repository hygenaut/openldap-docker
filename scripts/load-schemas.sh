#!/bin/bash
set -e

FORCE=false
if [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
  FORCE=true
fi

echo "==> 手动加载 Schema 文件"

docker exec openldap-server bash -c "
FORCE=$FORCE
for f in /custom_ldifs/*-schema.ldif; do
  [ -f \"\$f\" ] || continue
  
  schema_name=\$(grep \"^cn:\" \"\$f\" 2>/dev/null | head -1 | sed 's/cn: //')
  [ -z \"\$schema_name\" ] && continue
  
  if [ \"\$FORCE\" = \"false\" ]; then
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b \"cn=schema,cn=config\" \"objectClass=olcSchemaConfig\" dn 2>/dev/null | grep -q \"}\$schema_name,\"; then
      echo \"[跳过] Schema 已存在: \$schema_name\"
      continue
    fi
  fi
  
  echo \"加载 Schema: \$schema_name\"
  if ldapadd -Y EXTERNAL -H ldapi:/// -f \"\$f\" 2>&1; then
    echo \"[完成] Schema 加载成功: \$schema_name\"
  else
    echo \"[警告] Schema 加载失败: \$schema_name\"
  fi
done
"

echo "[完成] Schema 加载完成"
