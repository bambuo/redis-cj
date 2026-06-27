#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
toml_file="${repo_root}/cjpm.toml"

write_version=0
explicit_version=""

usage() {
    cat <<'EOF'
Usage:
  scripts/generate_version.sh [--write] [--set VERSION]

Options:
  --write        Write the generated version back to cjpm.toml.
  --set VERSION  Use an explicit version. Format: 1.0.YYYYMMDD[-N].
  -h, --help     Show this help.

Default behavior prints the next version only and does not modify files.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --write)
            write_version=1
            shift
            ;;
        --set)
            if [ "$#" -lt 2 ]; then
                echo "缺少 --set 的 VERSION 参数" >&2
                exit 1
            fi
            explicit_version="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

current_version="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "${toml_file}" | head -n 1)"
if [ -z "${current_version}" ]; then
    echo "无法从 cjpm.toml 读取 version 字段" >&2
    exit 1
fi

if [ -n "${explicit_version}" ]; then
    if ! printf '%s\n' "${explicit_version}" | grep -Eq '^1\.0\.[0-9]{8}(-[0-9]+)?$'; then
        echo "版本号格式必须为 1.0.YYYYMMDD[-N]: ${explicit_version}" >&2
        exit 1
    fi
    new_version="${explicit_version}"
else
    today="$(date +%Y%m%d)"
    today_prefix="1.0.${today}"

    if printf '%s\n' "${current_version}" | grep -Eq "^${today_prefix}(-[0-9]+)?$"; then
        suffix="${current_version#${today_prefix}}"
        if [ -z "${suffix}" ]; then
            count=2
        else
            count="$((${suffix#-} + 1))"
        fi
        new_version="${today_prefix}-${count}"
    else
        new_version="${today_prefix}"
    fi
fi

if [ "${write_version}" -eq 1 ]; then
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/redis-cj-version.XXXXXX")"
    sed "s/^\([[:space:]]*version[[:space:]]*=[[:space:]]*\)\"[^\"]*\"/\1\"${new_version}\"/" "${toml_file}" > "${tmp_file}"
    mv "${tmp_file}" "${toml_file}"
fi

printf '%s\n' "${new_version}"
