#!/bin/bash

# create-group.sh - 创建 LDAP 组
# 基于 create-user.sh 的设计模式

# 显示使用帮助
show_help() {
    cat << EOF
用法: $(basename "$0") -g GROUPNAME -i GID [选项]

必需参数:
  -g GROUPNAME   组名
  -i GID         组ID（必须手动指定，不能自动生成）

可选参数:
  -d DESCRIPTION 组描述
  -h             显示此帮助信息

示例:
  $(basename "$0") -g developers -i 3000 -d "Development Team"
  $(basename "$0") -g marketing -i 3001

EOF
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "错误：命令 '$1' 未找到。请确保已安装 openldap-clients。"
        exit 1
    fi
}

# 从环境变量文件读取配置
load_config() {
    local env_file=".env"
    
    if [[ ! -f "$env_file" ]]; then
        echo "错误：未找到 .env 文件。请先创建并配置环境变量。"
        exit 1
    fi
    
    # 读取环境变量
    source "$env_file"
    
    # 验证必需的环境变量
    if [[ -z "$LDAP_ROOT" ]]; then
        echo "错误：未找到 LDAP_ROOT 配置"
        exit 1
    fi
    
    if [[ -z "$LDAP_ADMIN_USERNAME" ]]; then
        echo "错误：未找到 LDAP_ADMIN_USERNAME 配置"
        exit 1
    fi
    
    if [[ -z "$LDAP_ADMIN_PASSWORD" ]]; then
        echo "错误：未找到 LDAP_ADMIN_PASSWORD 配置"
        exit 1
    fi
    
    # 设置 LDAP 服务器地址
    LDAP_HOST=${LDAP_HOST:-localhost}
    LDAP_PORT=${LDAP_PORT:-389}
    LDAP_URI="ldap://${LDAP_HOST}:${LDAP_PORT}"
}

# 检查组是否已存在
check_group_exists() {
    local groupname="$1"
    local gid="$2"
    
    echo "检查组是否已存在..."
    
    # 检查组名是否已存在
    if ldapsearch -x -H "$LDAP_URI" -D "cn=${LDAP_ADMIN_USERNAME},${LDAP_ROOT}" -w "$LDAP_ADMIN_PASSWORD" -b "ou=groups,${LDAP_ROOT}" "(cn=${groupname})" cn 2>/dev/null | grep -q "cn: ${groupname}"; then
        echo "错误：组名 '${groupname}' 已存在"
        return 1
    fi
    
    # 检查 GID 是否已存在
    if ldapsearch -x -H "$LDAP_URI" -D "cn=${LDAP_ADMIN_USERNAME},${LDAP_ROOT}" -w "$LDAP_ADMIN_PASSWORD" -b "ou=groups,${LDAP_ROOT}" "(gidNumber=${gid})" gidNumber 2>/dev/null | grep -q "gidNumber: ${gid}"; then
        echo "错误：GID '${gid}' 已存在"
        return 1
    fi
    
    echo "组名和 GID 检查通过"
    return 0
}

# 验证 GID 格式
validate_gid() {
    local gid="$1"
    
    # 检查是否为数字
    if ! [[ "$gid" =~ ^[0-9]+$ ]]; then
        echo "错误：GID 必须是数字"
        return 1
    fi
    
    # 检查 GID 范围（通常应该 >= 1000）
    if [[ "$gid" -lt 1000 ]]; then
        echo "警告：GID < 1000 可能与系统组冲突，建议使用 >= 1000 的值"
    fi
    
    return 0
}

# 创建 LDIF 文件
create_group_ldif() {
    local groupname="$1"
    local gid="$2"
    local description="$3"
    local temp_ldif="/tmp/add_group_${groupname}.ldif"
    
    cat > "$temp_ldif" << EOF
dn: cn=${groupname},ou=groups,${LDAP_ROOT}
objectClass: posixGroup
cn: ${groupname}
gidNumber: ${gid}
EOF
    
    # 如果提供了描述，添加到 LDIF
    if [[ -n "$description" ]]; then
        echo "description: ${description}" >> "$temp_ldif"
    fi
    
    echo "$temp_ldif"
}

# 添加组到 LDAP
add_group_to_ldap() {
    local ldif_file="$1"
    local groupname="$2"
    
    echo "正在添加组到 LDAP..."
    
    if ldapadd -x -H "$LDAP_URI" -D "cn=${LDAP_ADMIN_USERNAME},${LDAP_ROOT}" -w "$LDAP_ADMIN_PASSWORD" -f "$ldif_file"; then
        echo "组 '${groupname}' 创建成功"
        
        # 清理临时文件
        rm -f "$ldif_file"
        
        return 0
    else
        echo "组创建失败"
        echo "LDIF 文件内容："
        cat "$ldif_file"
        
        # 保留 LDIF 文件用于调试
        echo "LDIF 文件保存在: $ldif_file"
        
        return 1
    fi
}

# 显示组信息
show_group_info() {
    local groupname="$1"
    
    echo
    echo "组信息："
    echo "==============================="
    ldapsearch -x -H "$LDAP_URI" -D "cn=${LDAP_ADMIN_USERNAME},${LDAP_ROOT}" -w "$LDAP_ADMIN_PASSWORD" -b "ou=groups,${LDAP_ROOT}" "(cn=${groupname})" 2>/dev/null | grep -E "^(dn:|cn:|gidNumber:|description:)"
    echo
}

# 主函数
main() {
    local groupname=""
    local gid=""
    local description=""
    
    # 解析命令行参数
    while getopts "g:i:d:h" opt; do
        case $opt in
            g)
                groupname="$OPTARG"
                ;;
            i)
                gid="$OPTARG"
                ;;
            d)
                description="$OPTARG"
                ;;
            h)
                show_help
                exit 0
                ;;
            \?)
                echo "错误：无效选项 -$OPTARG" >&2
                show_help
                exit 1
                ;;
            :)
                echo "错误：选项 -$OPTARG 需要参数" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # 验证必需参数
    if [[ -z "$groupname" ]]; then
        echo "错误：必须指定组名 (-g)"
        show_help
        exit 1
    fi
    
    if [[ -z "$gid" ]]; then
        echo "错误：必须指定 GID (-i)"
        show_help
        exit 1
    fi
    
    # 验证 GID 格式
    if ! validate_gid "$gid"; then
        exit 1
    fi
    
    # 检查必要的命令
    check_command "ldapsearch"
    check_command "ldapadd"
    
    # 加载配置
    load_config
    
    echo "创建 LDAP 组"
    echo "=============="
    echo "组名: $groupname"
    echo "GID: $gid"
    [[ -n "$description" ]] && echo "描述: $description"
    echo "LDAP URI: $LDAP_URI"
    echo
    
    # 检查组是否已存在
    if ! check_group_exists "$groupname" "$gid"; then
        exit 1
    fi
    
    # 创建 LDIF 文件
    ldif_file=$(create_group_ldif "$groupname" "$gid" "$description")
    
    # 添加组到 LDAP
    if add_group_to_ldap "$ldif_file" "$groupname"; then
        show_group_info "$groupname"
        
        echo "提示：可以使用以下命令将用户添加到组："
        echo "  usermod -a -G $groupname username"
        echo "  或在 LAM 界面中编辑用户账户"
        echo
    else
        exit 1
    fi
}

# 检查是否直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi