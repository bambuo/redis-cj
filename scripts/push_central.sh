#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

tag_name=""
skip_build=0

usage() {
    cat <<'EOF'
Usage:
  scripts/push_central.sh TAG [--skip-build]

Publish the module from the source tree exported from TAG. Because cjpm publish
publishes the current module directory and does not accept a tarball path, this
script runs it inside target/release-worktrees/<tag>.

Options:
  --skip-build  Skip the pre-publish cjpm build verification.
  -h, --help    Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-build)
            skip_build=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -z "${tag_name}" ]; then
                tag_name="$1"
                shift
            else
                echo "未知参数: $1" >&2
                usage >&2
                exit 1
            fi
            ;;
    esac
done

if [ -z "${tag_name}" ]; then
    echo "缺少 TAG 参数" >&2
    usage >&2
    exit 1
fi

cd "${repo_root}"

if ! git rev-parse -q --verify "refs/tags/${tag_name}" >/dev/null; then
    echo "tag 不存在: ${tag_name}" >&2
    exit 1
fi

safe_tag="$(printf '%s' "${tag_name}" | sed 's/[^A-Za-z0-9._-]/_/g')"
work_dir="${repo_root}/target/release-worktrees/${safe_tag}"

if [ ! -f "${work_dir}/cjpm.toml" ]; then
    mkdir -p "${work_dir}"
    git archive --format=tar "${tag_name}" | tar -x -C "${work_dir}"
fi

(
    cd "${work_dir}"
    if [ "${skip_build}" -eq 0 ]; then
        cjpm build --verbose
    fi
    cjpm publish
)
