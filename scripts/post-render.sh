#!/usr/bin/env bash
set -euo pipefail

project_dir="${QUARTO_PROJECT_DIR:-$(pwd)}"
output_dir="${QUARTO_PROJECT_OUTPUT_DIR:-_output}"

cover_src="${project_dir}/cover.html"
index_dst="${output_dir}/index.html"
animal_dst_dir="${output_dir}/images"

if [[ ! -f "${cover_src}" ]]; then
  echo "post-render: missing cover source: ${cover_src}" >&2
  exit 1
fi

if [[ ! -d "${output_dir}" ]]; then
  echo "post-render: output dir not found: ${output_dir} (skipping)" >&2
  exit 0
fi

if [[ ! -f "${index_dst}" ]]; then
  # Non-HTML renders may not produce an index.html.
  exit 0
fi

cp "${cover_src}" "${index_dst}"

animal_src=""
if [[ -f "${project_dir}/images/cover-animal.png" ]]; then
  animal_src="${project_dir}/images/cover-animal.png"
elif [[ -f "${project_dir}/cover-animal.png" ]]; then
  animal_src="${project_dir}/cover-animal.png"
fi

if [[ -n "${animal_src}" ]]; then
  mkdir -p "${animal_dst_dir}"
  cp "${animal_src}" "${animal_dst_dir}/cover-animal.png"

  # Cache-bust the cover image in the generated HTML. Browsers can aggressively
  # cache static assets during `quarto preview`, which makes it look like the
  # animal didn't update even when the file on disk did.
  animal_hash=""
  if command -v shasum >/dev/null 2>&1; then
    animal_hash="$(shasum -a 256 "${animal_src}" | awk '{print $1}' | cut -c1-12)"
  elif command -v sha256sum >/dev/null 2>&1; then
    animal_hash="$(sha256sum "${animal_src}" | awk '{print $1}' | cut -c1-12)"
  fi

  if [[ -n "${animal_hash}" ]]; then
    hashed_name="cover-animal-${animal_hash}.png"
    cp "${animal_src}" "${animal_dst_dir}/${hashed_name}"

    # Prefer the hash-stamped filename (more robust than query-string cache busting).
    perl -0pi -e 's/src="images\/cover-animal\.png(?:\?v=[^"]*)?"/src="images\/'"${hashed_name}"'"/g' "${index_dst}"

    # Remove older hash-stamped versions so the output dir doesn't accumulate assets.
    find "${animal_dst_dir}" -maxdepth 1 -type f -name 'cover-animal-*.png' ! -name "${hashed_name}" -delete
  fi
fi
