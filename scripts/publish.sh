#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage:
  scripts/publish.sh generate-version [options...]
  scripts/publish.sh tag [options...]
  scripts/publish.sh build TAG [options...]
  scripts/publish.sh push TAG [options...]
  scripts/publish.sh all TAG

Subcommands:
  generate-version  Delegate to scripts/generate_version.sh.
  tag               Delegate to scripts/git_tag.sh.
  build             Delegate to scripts/build_release_from_tag.sh.
  push              Delegate to scripts/push_central.sh.
  all               Build release artifacts from TAG, then publish TAG.

Typical flow:
  scripts/generate_version.sh --write
  scripts/git_tag.sh --commit-version
  scripts/build_release_from_tag.sh v1.0.YYYYMMDD
  scripts/push_central.sh v1.0.YYYYMMDD
EOF
}

if [ "$#" -eq 0 ]; then
    usage >&2
    exit 1
fi

command="$1"
shift

case "${command}" in
    generate-version)
        "${script_dir}/generate_version.sh" "$@"
        ;;
    tag)
        "${script_dir}/git_tag.sh" "$@"
        ;;
    build)
        "${script_dir}/build_release_from_tag.sh" "$@"
        ;;
    push)
        "${script_dir}/push_central.sh" "$@"
        ;;
    all)
        if [ "$#" -lt 1 ]; then
            echo "all 子命令缺少 TAG 参数" >&2
            usage >&2
            exit 1
        fi
        tag_name="$1"
        "${script_dir}/build_release_from_tag.sh" "${tag_name}"
        "${script_dir}/push_central.sh" "${tag_name}"
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "未知子命令: ${command}" >&2
        usage >&2
        exit 1
        ;;
esac
