#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

tag_name=""
skip_test=1
skip_lint=1

usage() {
    cat <<'EOF'
Usage:
  scripts/build_release_from_tag.sh TAG [--run-test] [--run-lint]

Build a release package from the exact source tree recorded by TAG.
The script exports TAG into target/release-worktrees/<tag>, runs cjpm build,
runs cjpm bundle, and writes release/commit descriptions under
target/release-artifacts/<tag>.

Options:
  --run-test   Let cjpm bundle run tests.
  --run-lint   Let cjpm bundle run cjlint.
  -h, --help   Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-test)
            skip_test=0
            shift
            ;;
        --run-lint)
            skip_lint=0
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
artifact_dir="${repo_root}/target/release-artifacts/${safe_tag}"

rm -rf "${work_dir}"
mkdir -p "${work_dir}" "${artifact_dir}"
git archive --format=tar "${tag_name}" | tar -x -C "${work_dir}"

tag_commit="$(git rev-list -n 1 "${tag_name}")"
version="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "${work_dir}/cjpm.toml" | head -n 1)"
previous_tag="$(git describe --tags --abbrev=0 "${tag_commit}^" 2>/dev/null || true)"

(
    cd "${work_dir}"
    cjpm build --verbose
    bundle_args=()
    if [ "${skip_test}" -eq 1 ]; then
        bundle_args+=("--skip-test")
    fi
    if [ "${skip_lint}" -eq 1 ]; then
        bundle_args+=("--skip-lint")
    fi
    cjpm bundle "${bundle_args[@]}"
)

bundle_path="$(find "${work_dir}" -type f \( -name '*.tar.gz' -o -name '*.tgz' \) -print | sort | tail -n 1)"
if [ -z "${bundle_path}" ]; then
    echo "cjpm bundle 未生成可发布 tarball" >&2
    exit 1
fi

cp "${bundle_path}" "${artifact_dir}/"
artifact_bundle="${artifact_dir}/$(basename "${bundle_path}")"

{
    printf 'Release: %s\n' "${tag_name}"
    printf 'Version: %s\n' "${version}"
    printf 'Commit: %s\n' "${tag_commit}"
    printf 'Package: %s\n' "${artifact_bundle}"
    if [ -n "${previous_tag}" ]; then
        printf 'Previous tag: %s\n' "${previous_tag}"
    fi
    printf '\nPublish description:\n'
    printf 'Redis Cangjie client %s release. Includes client-side RESP2/RESP3, connection, pipeline, transaction, Pub/Sub, SCAN, and Cluster routing capabilities.\n' "${version}"
    printf '\nChanges:\n'
    if [ -n "${previous_tag}" ]; then
        git log --format='- %s (%h)' "${previous_tag}..${tag_commit}"
    else
        git log --format='- %s (%h)' "${tag_commit}"
    fi
} > "${artifact_dir}/release-description.txt"

{
    printf 'Tagged commit description for %s\n\n' "${tag_name}"
    git log -1 --format='%B' "${tag_commit}"
} > "${artifact_dir}/commit-description.txt"

printf 'worktree=%s\n' "${work_dir}"
printf 'bundle=%s\n' "${artifact_bundle}"
printf 'release_description=%s\n' "${artifact_dir}/release-description.txt"
printf 'commit_description=%s\n' "${artifact_dir}/commit-description.txt"
