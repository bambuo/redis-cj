#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

tag_name=""
message_file=""
commit_version=0

usage() {
    cat <<'EOF'
Usage:
  scripts/git_tag.sh [--tag vVERSION] [--message-file FILE] [--commit-version]

Options:
  --tag vVERSION       Tag name. Defaults to v<version from cjpm.toml>.
  --message-file FILE  Use FILE as annotated tag message.
  --commit-version     Commit cjpm.toml and README.md changes before tagging.
  -h, --help           Show this help.

The script refuses to tag a dirty worktree. Use --commit-version only for the
release version/documentation bump; unrelated changes must be handled manually.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            if [ "$#" -lt 2 ]; then
                echo "缺少 --tag 的 tag 名称" >&2
                exit 1
            fi
            tag_name="$2"
            shift 2
            ;;
        --message-file)
            if [ "$#" -lt 2 ]; then
                echo "缺少 --message-file 的文件路径" >&2
                exit 1
            fi
            message_file="$2"
            shift 2
            ;;
        --commit-version)
            commit_version=1
            shift
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

cd "${repo_root}"

version="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' cjpm.toml | head -n 1)"
if [ -z "${version}" ]; then
    echo "无法从 cjpm.toml 读取 version 字段" >&2
    exit 1
fi

if [ -z "${tag_name}" ]; then
    tag_name="v${version}"
fi

tag_version="${tag_name#v}"
if [ "${tag_version}" != "${version}" ]; then
    echo "tag 与 cjpm.toml 版本不一致: tag=${tag_name}, version=${version}" >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag_name}" >/dev/null; then
    echo "tag 已存在: ${tag_name}" >&2
    exit 1
fi

if [ "${commit_version}" -eq 1 ] && ! git diff --quiet -- cjpm.toml README.md; then
    git add cjpm.toml README.md
    git commit -m "chore(release): ${tag_name}" -m "Prepare ${tag_name} for central repository publishing."
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "工作区不干净，拒绝打 tag。请先提交或清理变更。" >&2
    git status --short >&2
    exit 1
fi

tmp_message=""
if [ -z "${message_file}" ]; then
    tmp_message="$(mktemp "${TMPDIR:-/tmp}/redis-cj-tag.XXXXXX")"
    previous_tag="$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
    {
        printf 'Release %s\n\n' "${tag_name}"
        printf 'Version: %s\n' "${version}"
        printf 'Commit: %s\n' "$(git rev-parse --short HEAD)"
        if [ -n "${previous_tag}" ]; then
            printf 'Previous tag: %s\n\n' "${previous_tag}"
            printf 'Changes:\n'
            git log --format='- %s (%h)' "${previous_tag}..HEAD"
        else
            printf '\nChanges:\n'
            git log --format='- %s (%h)' HEAD
        fi
    } > "${tmp_message}"
    message_file="${tmp_message}"
fi

git tag -a "${tag_name}" -F "${message_file}"
printf '%s\n' "${tag_name}"
