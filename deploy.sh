#!/bin/bash
set -e

SCRIPT_NAME=$(basename "$0")

# 显示帮助信息
show_help() {
    cat << EOF
用法: $SCRIPT_NAME [命令] [选项]

命令:
  init              完整部署流程（初始化 + 启动 + 配置证书 + 加载 Schema + 配置 ACL）
  start             启动服务
  stop              停止服务
  restart           重启服务
  delete            删除所有数据和容器
  reload-certs      重新加载 TLS 证书
  load-schemas      加载自定义 Schema
  configure-acl     配置 LDAP ACL 访问控制
  generate-ldif     从模板生成 LDIF 文件（使用 -f 强制覆盖）
  set-folders-owner 设置目录权限
  help              显示此帮助信息

不带参数运行时显示此帮助信息
EOF
}

# 检查 .env 文件
check_env() {
    if [ ! -f .env ]; then
        echo "[错误] .env 文件不存在"
        echo "请先复制 .env.example 并配置："
        echo "  cp .env.example .env"
        echo "  vim .env"
        exit 1
    fi
}

# 创建目录结构
create_directories() {
    echo "==> 创建目录结构"
    
    mkdir -p openldap-data/openldap
    mkdir -p nginx/logs
    mkdir -p convert_schema
    mkdir -p custom_ldifs
    mkdir -p schemas
    mkdir -p lam/config
    
    # 初始化 LAM 配置（如果不存在）
    if [ ! -f lam/config/lam.conf ]; then
        echo "==> 初始化 LAM 配置"
        docker run --rm -v "$(pwd)/lam/config:/tmp/config" ldapaccountmanager/lam:latest sh -c "cp -r /var/lib/ldap-account-manager/config/* /tmp/config/"
    fi
    
    echo "[完成] 目录创建完成"
}

# 完整部署流程
cmd_init() {
    echo "==> OpenLDAP 完整部署"
    echo ""
    check_env
    cmd_generate_ldif -f
    create_directories
    cmd_set_folders_owner
    
    cmd_start
    cmd_reload_certs
    cmd_load_schemas
    cmd_configure_acl
    show_completion
}

# 设置目录权限（一次性配置，使用 ACL 自动继承）
cmd_set_folders_owner() {
    echo "==> 设置目录权限（使用 ACL 自动继承）"
    
    # 检查是否支持 ACL
    if ! command -v setfacl &> /dev/null; then
        echo "[警告] 系统不支持 ACL，使用传统 chown 方式"
        sudo chown -R 1001:1001 openldap-data/ 2>/dev/null || true
        sudo chown -R 101:101 nginx/ 2>/dev/null || true
        sudo chown -R 33:33 lam/ 2>/dev/null || true
        echo "[完成] 目录权限设置完成"
        return
    fi
    
    # Bitnami OpenLDAP (uid=1001)
    sudo chown -R 1001:1001 openldap-data/ 2>/dev/null || true
    sudo setfacl -R -m d:u:1001:rwx,d:g:1001:rwx openldap-data/ 2>/dev/null || true
    
    # Nginx (uid=101)
    sudo chown -R 101:101 nginx/ 2>/dev/null || true
    sudo setfacl -R -m d:u:101:rwx,d:g:101:rwx nginx/ 2>/dev/null || true
    
    # LAM (uid=33, www-data)
    sudo chown -R 33:33 lam/ 2>/dev/null || true
    sudo setfacl -R -m d:u:33:rwx,d:g:33:rwx lam/ 2>/dev/null || true
    
    echo "[完成] 目录权限设置完成（新文件将自动继承权限）"
}

# 启动服务
cmd_start() {
    echo "==> 验证 Docker Compose 配置"
    docker compose config --quiet
    echo "[完成] 配置验证通过"
    
    echo "==> 启动服务"
    docker compose up -d
    echo "[完成] 服务启动完成"
    
    echo "==> 等待服务就绪（15秒）"
    sleep 15
    
    echo "==> 验证服务状态"
    docker compose ps
}

# 停止服务
cmd_stop() {
    echo "==> 停止服务"
    docker compose stop
    echo "[完成] 服务已停止"
}

# 重启服务
cmd_restart() {
    echo "==> 重启服务"
    docker compose restart
    echo "[完成] 服务已重启"
    
    echo "==> 等待服务就绪（10秒）"
    sleep 10
    
    echo "==> 验证服务状态"
    docker compose ps
}

# 删除所有数据
cmd_delete() {
    echo "[警告] 此操作将删除所有数据和容器！"
    read -p "确认删除？(yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "已取消"
        exit 0
    fi
    
    echo "==> 停止并删除容器"
    docker compose down -v --remove-orphans
    
    echo "==> 删除数据目录"
    sudo rm -rf openldap-data/
    sudo rm -rf nginx/logs/
    sudo rm -rf lam/
    
    echo "[完成] 删除完成"
}

# 加载自定义 Schema
cmd_load_schemas() {
    echo "==> 加载自定义 Schema"
    
    if [ ! -f scripts/load-schemas.sh ]; then
        echo "[警告] scripts/load-schemas.sh 不存在"
        return
    fi
    
    bash scripts/load-schemas.sh
    echo "[完成] Schema 加载完成"
}

# 生成 LDIF 文件
cmd_generate_ldif() {
    if [ ! -f scripts/generate-ldif.sh ]; then
        echo "[错误] scripts/generate-ldif.sh 不存在"
        exit 1
    fi
    
    bash scripts/generate-ldif.sh "$@"
}

# 配置 ACL
cmd_configure_acl() {
    echo "==> 配置 LDAP ACL"
    
    if [ ! -f scripts/configure-acl.sh ]; then
        echo "[警告] scripts/configure-acl.sh 不存在"
        return
    fi
    
    bash scripts/configure-acl.sh
    echo "[完成] ACL 配置完成"
}

# 重新加载 TLS 证书
cmd_reload_certs() {
    echo "==> 配置 TLS 证书"
    
    if ! docker exec openldap-server ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=config" "objectClass=olcGlobal" olcTLSCertificateFile 2>/dev/null | grep -q "olcTLSCertificateFile:"; then
        docker exec openldap-server bash -c 'cat > /tmp/tls.ldif <<EOF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /opt/bitnami/openldap/certs/openldap.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /opt/bitnami/openldap/certs/openldap.key
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /opt/bitnami/openldap/certs/openldapCA.crt
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/tls.ldif' 2>&1 | grep -v "^SASL"
        
        echo "[完成] TLS 证书已配置，重启服务..."
        docker restart openldap-server
        sleep 10
    else
        echo "[完成] TLS 证书已存在"
    fi
}

# 显示部署完成信息
show_completion() {
    source .env
    
    echo ""
    echo "[完成] 部署完成！"
    echo ""
    echo "访问 LDAP Account Manager："
    echo "  https://localhost"
    echo ""
    echo "测试 LDAPS 连接："
    echo "  ldapsearch -x -H ldaps://localhost:636 -b \"${LDAP_ROOT}\" -D \"cn=${LDAP_ADMIN_USERNAME},${LDAP_ROOT}\" -w \"${LDAP_ADMIN_PASSWORD}\" -o tls_reqcert=never"
}

# 主逻辑
main() {
    case "${1:-}" in
        init)
            cmd_init
            ;;
        start)
            check_env
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        delete)
            cmd_delete
            ;;
        reload-certs)
            cmd_reload_certs
            ;;
        load-schemas)
            cmd_load_schemas
            ;;
        configure-acl)
            cmd_configure_acl
            ;;
        generate-ldif)
            check_env
            cmd_generate_ldif "$2"
            ;;
        set-folders-owner)
            cmd_set_folders_owner
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            # 默认：显示帮助
            show_help
            ;;
        *)
            echo "[错误] 未知命令 '$1'"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
