#!/bin/bash
set -e

# 加载 .env 配置
if [ ! -f .env ]; then
    echo "[错误] .env 文件不存在" >&2
    exit 1
fi

source .env

CONTAINER="openldap-server"
LDAP_PORT="${LDAP_PORT_NUMBER:-1389}"
ADMIN_DN="cn=${LDAP_ADMIN_USERNAME},${LDAP_ROOT}"
BASE_DN="${LDAP_ROOT}"

# 显示帮助
show_help() {
    cat << EOF
用法: $(basename "$0") -u USERNAME -p PASSWORD [选项]

必需参数:
  -u USERNAME    用户名
  -p PASSWORD    密码

可选参数:
  -g GROUP       组名（默认: user）
  -n FULLNAME    全名（默认: 使用用户名）
  -h             显示此帮助信息

示例:
  # 创建普通用户（默认加入 user 组）
  $(basename "$0") -u zhangsan -p Password123

  # 创建管理员用户（加入 admin 组）
  $(basename "$0") -u admin_user -p Admin@123 -g admin

  # 指定全名
  $(basename "$0") -u zhangsan -p Password123 -n "Zhang San"
EOF
}

# 获取下一个可用的 UID
get_next_uid() {
    local max_uid=$(docker exec "$CONTAINER" ldapsearch -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
        -b "$BASE_DN" "(objectClass=posixAccount)" uidNumber 2>/dev/null \
        | grep "^uidNumber:" | awk '{print $2}' | sort -n | tail -1)
    
    if [ -z "$max_uid" ] || [ "$max_uid" -lt 10000 ]; then
        echo 10001
    else
        echo $((max_uid + 1))
    fi
}

# 获取所有可用的组
get_available_groups() {
    local groups=$(docker exec "$CONTAINER" ldapsearch -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
        -b "ou=groups,$BASE_DN" "(objectClass=posixGroup)" cn 2>/dev/null \
        | grep "^cn:" | awk '{print $2}' | sort | tr '\n' ', ' | sed 's/,$//')
    
    if [ -z "$groups" ]; then
        echo "(无可用组)"
    else
        echo "$groups"
    fi
}

# 检查组是否存在并获取 GID
get_group_gid() {
    local group_name="$1"
    local gid=$(docker exec "$CONTAINER" ldapsearch -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" \
        -b "ou=groups,$BASE_DN" "(cn=$group_name)" gidNumber 2>/dev/null \
        | grep "^gidNumber:" | awk '{print $2}')
    
    if [ -z "$gid" ]; then
        local available_groups=$(get_available_groups)
        echo "[错误] 组不存在: $group_name" >&2
        echo "[提示] 可用的组: $available_groups" >&2
        return 1
    fi
    
    echo "$gid"
}

# 添加用户到组
add_to_group() {
    local username="$1"
    local group_name="$2"
    
    docker exec -i "$CONTAINER" ldapmodify -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<EOF 2>&1 | grep -v "^modifying entry"
dn: cn=${group_name},ou=groups,${BASE_DN}
changetype: modify
add: memberUid
memberUid: ${username}
EOF
}

# 创建用户
create_user() {
    local username="$1"
    local password="$2"
    local group_name="$3"
    local fullname="$4"
    
    # 获取 UID 和 GID
    local uid=$(get_next_uid)
    local gid=$(get_group_gid "$group_name")
    
    # 检查 GID 是否获取成功
    if [ $? -ne 0 ] || [ -z "$gid" ]; then
        exit 1
    fi
    
    # 解析姓名
    local given_name=$(echo "$fullname" | awk '{print $1}')
    local sn=$(echo "$fullname" | awk '{print $NF}')
    
    # 生成邮箱
    local mail="${username}@${BASE_DN//dc=/}.${BASE_DN//,dc=/.}"
    mail="${mail//,/.}"
    
    # 创建用户 LDIF
    docker exec -i "$CONTAINER" ldapadd -x -H "ldap://localhost:${LDAP_PORT}" \
        -D "$ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<EOF
dn: uid=${username},ou=people,${BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: ${username}
cn: ${fullname}
sn: ${sn}
givenName: ${given_name}
mail: ${mail}
uidNumber: ${uid}
gidNumber: ${gid}
homeDirectory: /home/${username}
loginShell: /bin/bash
userPassword: ${password}
EOF
    
    if [ $? -eq 0 ]; then
        echo "[完成] 用户创建成功: ${username}"
        echo "  DN: uid=${username},ou=people,${BASE_DN}"
        echo "  UID: ${uid}"
        echo "  GID: ${gid}"
        echo "  组: ${group_name}"
        
        # 添加到组
        add_to_group "$username" "$group_name"
        echo "[完成] 已添加到组: cn=${group_name},ou=groups,${BASE_DN}"
    else
        echo "[错误] 创建用户失败" >&2
        exit 1
    fi
}

# 解析参数
USERNAME=""
PASSWORD=""
GROUP="user"
FULLNAME=""

while getopts "u:p:g:n:h" opt; do
    case $opt in
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        g) GROUP="$OPTARG" ;;
        n) FULLNAME="$OPTARG" ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# 检查必需参数
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "[错误] 缺少必需参数" >&2
    show_help
    exit 1
fi

# 设置默认全名
if [ -z "$FULLNAME" ]; then
    FULLNAME="$USERNAME"
fi

# 创建用户
create_user "$USERNAME" "$PASSWORD" "$GROUP" "$FULLNAME"
