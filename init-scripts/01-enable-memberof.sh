#!/bin/bash

# 后台执行，不阻塞容器启动
(
  # 等待 slapd 进程启动
  for i in {1..60}; do
    if pgrep -x slapd > /dev/null 2>&1; then
      sleep 3
      break
    fi
    sleep 1
  done

  echo "==> 配置 memberof overlay"

  # 检查 overlay 是否已加载
  if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=memberof)" dn 2>/dev/null | grep -q "olcOverlay"; then
    echo "[完成] memberof overlay 已存在"
    exit 0
  fi

  # 加载 memberof 模块
  ldapadd -Y EXTERNAL -H ldapi:/// <<EOF 2>&1 | grep -v "^SASL"
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: memberof
EOF

  # 配置 memberof overlay
  ldapadd -Y EXTERNAL -H ldapi:/// <<EOF 2>&1 | grep -v "^SASL"
dn: olcOverlay=memberof,olcDatabase={2}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: memberof
olcMemberOfRefint: TRUE
olcMemberOfDangling: ignore
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf
EOF

  if [ $? -eq 0 ]; then
    echo "[完成] memberof overlay 配置成功"
  else
    echo "[警告] memberof overlay 配置失败"
  fi

) &
