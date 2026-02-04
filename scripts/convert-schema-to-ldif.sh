#!/bin/bash
set -e

# 标准 schema 路径
STANDARD_SCHEMAS=(
    "/etc/ldap/schema/core.schema"
    "/etc/ldap/schema/cosine.schema"
    "/etc/ldap/schema/inetorgperson.schema"
    "/etc/ldap/schema/nis.schema"
)

# 清理 LDIF 文件
clean_ldif() {
    local ldif_file="$1"
    local temp_file="${ldif_file}.tmp"
    
    # 移除注释和元数据
    grep -v -E '# AUTO-GENERATED|# CRC32|structuralObjectClass:|entryUUID:|creatorsName:|createTimestamp:|entryCSN:|modifiersName:|modifyTimestamp:' \
        "$ldif_file" > "$temp_file" || true
    
    # 修复 DN 和 cn（移除索引号）
    sed -i 's/dn: cn={[0-9]\+}\(.*\)/dn: cn=\1,cn=schema,cn=config/' "$temp_file"
    sed -i 's/cn: {[0-9]\+}\(.*\)/cn: \1/' "$temp_file"
    
    mv "$temp_file" "$ldif_file"
}

# 转换 schema 为 LDIF
convert_schema_to_ldif() {
    local schema_file="$1"
    local output_file="$2"
    local schema_name=$(basename "$schema_file" .schema)
    
    local tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    
    local conf_file="$tmpdir/schema_convert.conf"
    local slapd_d="$tmpdir/slapd.d"
    
    # 生成配置文件
    for std_schema in "${STANDARD_SCHEMAS[@]}"; do
        if [ -f "$std_schema" ]; then
            echo "include $std_schema" >> "$conf_file"
        fi
    done
    echo "include $(realpath "$schema_file")" >> "$conf_file"
    
    mkdir -p "$slapd_d"
    
    # 执行转换
    if ! slaptest -f "$conf_file" -F "$slapd_d" 2>&1 | grep -v "^config file testing succeeded"; then
        echo "[错误] 转换失败: $schema_file" >&2
        return 1
    fi
    
    # 查找生成的 LDIF 文件
    local schema_dir="$slapd_d/cn=config/cn=schema"
    if [ ! -d "$schema_dir" ]; then
        echo "[错误] Schema 目录不存在" >&2
        return 1
    fi
    
    local generated_ldif=$(find "$schema_dir" -type f -name "*${schema_name,,}*.ldif" | head -1)
    if [ -z "$generated_ldif" ]; then
        echo "[错误] 未找到生成的 LDIF 文件" >&2
        return 1
    fi
    
    cp "$generated_ldif" "$output_file"
    clean_ldif "$output_file"
    
    echo "[完成] 转换成功: ${schema_name}.schema -> $(basename "$output_file")"
    return 0
}

# 主函数
main() {
    local input_dir="convert_schema"
    local output_dir="output_ldifs"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input-dir)
                input_dir="$2"
                shift 2
                ;;
            -o|--output-dir)
                output_dir="$2"
                shift 2
                ;;
            -h|--help)
                cat << EOF
用法: $(basename "$0") [选项]

选项:
  -i, --input-dir DIR   输入目录（包含 .schema 文件），默认: convert_schema
  -o, --output-dir DIR  输出目录（保存 .ldif 文件），默认: output_ldifs
  -h, --help            显示此帮助信息
EOF
                exit 0
                ;;
            *)
                echo "[错误] 未知参数: $1" >&2
                exit 1
                ;;
        esac
    done
    
    if [ ! -d "$input_dir" ]; then
        echo "[错误] 目录不存在: $input_dir" >&2
        exit 1
    fi
    
    mkdir -p "$output_dir"
    
    # 查找所有 .schema 文件
    local schema_files=($(find "$input_dir" -maxdepth 1 -name "*.schema" -type f | sort))
    
    if [ ${#schema_files[@]} -eq 0 ]; then
        echo "[完成] 没有需要转换的 schema 文件"
        exit 0
    fi
    
    echo "发现 ${#schema_files[@]} 个 schema 文件"
    
    local success_count=0
    local idx=0
    
    for schema_file in "${schema_files[@]}"; do
        local schema_name=$(basename "$schema_file" .schema)
        local output_file="$output_dir/$(printf "%02d" $idx)-${schema_name}-schema.ldif"
        
        if convert_schema_to_ldif "$schema_file" "$output_file"; then
            ((success_count++))
        fi
        ((idx++))
    done
    
    echo ""
    echo "转换完成: $success_count/${#schema_files[@]} 成功"
    
    [ $success_count -eq ${#schema_files[@]} ] && exit 0 || exit 1
}

main "$@"
