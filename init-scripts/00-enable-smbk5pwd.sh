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

  echo "==> 配置 smbk5pwd overlay"

  # 检查 overlay 是否已加载
  if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "(olcOverlay=smbk5pwd)" dn 2>/dev/null | grep -q "olcOverlay"; then
    echo "[完成] smbk5pwd overlay 已存在"
    exit 0
  fi

  # 加载 smbk5pwd 模块
  ldapadd -Y EXTERNAL -H ldapi:/// <<EOF 2>&1 | grep -v "^SASL"
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: smbk5pwd
EOF

  # 配置 smbk5pwd overlay
  ldapadd -Y EXTERNAL -H ldapi:/// <<EOF 2>&1 | grep -v "^SASL"
dn: olcOverlay=smbk5pwd,olcDatabase={2}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcSmbK5PwdConfig
olcOverlay: smbk5pwd
olcSmbK5PwdEnable: samba
olcSmbK5PwdMustChange: 2592000
EOF

  if [ $? -eq 0 ]; then
    echo "[完成] smbk5pwd overlay 配置成功"
  else
    echo "[警告] smbk5pwd overlay 配置失败"
  fi

) &
