#!/usr/bin/env bash
set -euo pipefail

# Records which upstream Tactus commit this book targets.
#
# Default input path assumes the sibling repo layout:
#   ../Tactus
#
# Output:
#   tactus-target.yml

repo_path="${1:-../Tactus}"
out_file="${2:-tactus-target.yml}"

if [[ ! -d "${repo_path}" ]]; then
  echo "update-tactus-target: repo not found: ${repo_path}" >&2
  exit 1
fi

if ! git -C "${repo_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "update-tactus-target: not a git repo: ${repo_path}" >&2
  exit 1
fi

commit="$(git -C "${repo_path}" rev-parse HEAD)"
commit_short="$(git -C "${repo_path}" rev-parse --short=12 HEAD)"
describe="$(git -C "${repo_path}" describe --tags --always --dirty)"
recorded_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Best-effort: extract the base version tag (e.g. v0.27.0 from v0.27.0-2-g<sha>).
version_tag="unknown"
version="unknown"
if [[ "${describe}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  version_tag="${BASH_REMATCH[0]}"
  version="${version_tag#v}"
fi

# Best-effort: infer GitHub repo slug from remotes if possible; otherwise keep default.
repo_slug="anthusai/Tactus"
remote_url="$(git -C "${repo_path}" remote get-url origin 2>/dev/null || true)"
if [[ -n "${remote_url}" ]]; then
  # Supports:
  # - https://github.com/owner/repo.git
  # - git@github.com:owner/repo.git
  remote_url="${remote_url%.git}"
  if [[ "${remote_url}" =~ github\.com[:/]+([^/]+/[^/]+)$ ]]; then
    repo_slug="${BASH_REMATCH[1]}"
  fi
fi

cat > "${out_file}" <<EOF
tactus_repo: ${repo_slug}
tactus_ref: main
tactus_commit: ${commit}
tactus_commit_short: ${commit_short}
tactus_describe: ${describe}
tactus_version_tag: ${version_tag}
tactus_version: ${version}
tactus_recorded_at: ${recorded_at}
EOF

echo "Wrote ${out_file}"
