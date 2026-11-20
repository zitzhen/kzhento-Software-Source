#!/usr/bin/env bash
# Assemble apt metadata for the stable/main/amd64 suite, sign it and export the key.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: publish-repo.sh <artifacts-dir> <publish-root> <gpg-key-id>" >&2
  exit 1
fi

artifacts_dir="$1"
publish_root="$2"
gpg_key_id="$3"

suite="stable"
component="main"
arch="amd64"
dists_dir="$publish_root/dists/$suite"

if [[ ! -d "$artifacts_dir" ]]; then
  echo "Error: artifacts directory not found: $artifacts_dir" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$dists_dir/$component/binary-$arch" "$publish_root/pool/$component"
rm -f "$dists_dir/Release" "$dists_dir/InRelease" "$dists_dir/Release.gpg"

shopt -s nullglob
debs=("$artifacts_dir"/*_"$arch".deb)
shopt -u nullglob

if (( ${#debs[@]} == 0 )); then
  echo "Error: no ${arch} .deb files found in $artifacts_dir" >&2
  exit 1
fi

for deb in "${debs[@]}"; do
  package_name="$(dpkg-deb -f "$deb" Package)"
  if [[ -z "$package_name" ]]; then
    echo "Error: cannot read the Package field from $deb" >&2
    exit 1
  fi
  if [[ "$package_name" == lib* ]]; then
    prefix="${package_name:0:4}"
  else
    prefix="${package_name:0:1}"
  fi
  target_dir="$publish_root/pool/$component/$prefix/$package_name"
  mkdir -p "$target_dir"
  cp -f "$deb" "$target_dir/"
done

echo "Indexing ${#debs[@]} package(s)" >&2
(
  cd "$publish_root"
  dpkg-scanpackages "pool/$component" /dev/null \
    > "dists/$suite/$component/binary-$arch/Packages"
  gzip -9c "dists/$suite/$component/binary-$arch/Packages" \
    > "dists/$suite/$component/binary-$arch/Packages.gz"
)

echo "Generating Release metadata" >&2
(
  cd "$publish_root"
  apt-ftparchive \
    -o "APT::FTPArchive::Release::Origin=ZIT Studio" \
    -o "APT::FTPArchive::Release::Label=zhento-Software-Source" \
    -o "APT::FTPArchive::Release::Suite=$suite" \
    -o "APT::FTPArchive::Release::Codename=$suite" \
    -o "APT::FTPArchive::Release::Architectures=$arch" \
    -o "APT::FTPArchive::Release::Components=$component" \
    -o "APT::FTPArchive::Release::Description=zhento-Software-Source packages" \
    release "dists/$suite" > "$tmp_dir/Release"
)
cp "$tmp_dir/Release" "$dists_dir/Release"

gpg_args=(--batch --yes --pinentry-mode loopback --local-user "$gpg_key_id")
if [[ -n "${APT_GPG_PASSPHRASE:-}" ]]; then
  exec 3<<<"$APT_GPG_PASSPHRASE"
  gpg_args+=(--passphrase-fd 3)
fi

echo "Signing InRelease and Release.gpg" >&2
gpg "${gpg_args[@]}" --clearsign \
  --output "$dists_dir/InRelease" "$dists_dir/Release"
gpg "${gpg_args[@]}" --detach-sign --armor \
  --output "$dists_dir/Release.gpg" "$dists_dir/Release"
exec 3<&- 2>/dev/null || true

echo "Exporting the public key" >&2
gpg --batch --yes --armor --export "$gpg_key_id" > "$publish_root/apt-key.asc"
gpg --batch --yes --dearmor --output "$publish_root/apt-key.gpg" "$publish_root/apt-key.asc"

echo "Repository staged at $publish_root" >&2
