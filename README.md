# zhento-Software-Source

Debian/Ubuntu apt repository hosted on Cloudflare R2 and served at
`https://apt.zitzhen.cn`.

This repository is the source of truth for that apt repository. `Software.list`
at the root lists upstream GitHub projects. A manually triggered GitHub Actions
workflow clones every listed project, builds an `amd64` `.deb` package from its
`debian/` directory, generates the apt indexes, signs them with a dedicated GPG
key, and syncs the result to the R2 bucket behind `apt.zitzhen.cn`.

## How it works

1. `scripts/parse-software-list.sh` reads `Software.list`, validates and de-duplicates entries.
2. `scripts/build-deb.sh` clones each upstream repository, installs its build dependencies with `mk-build-deps`, and runs `dpkg-buildpackage -b -us -uc`.
3. `scripts/publish-repo.sh` assembles `pool/main/...`, generates `Packages`, `Packages.gz`, `Release`, `InRelease`, and `Release.gpg`, then exports the public key.
4. The AWS CLI syncs the published tree to Cloudflare R2. Existing bucket objects are never deleted by the workflow.

The published layout uses suite `stable`, component `main`, and architecture `amd64`:

```text
dists/stable/InRelease
dists/stable/Release
dists/stable/Release.gpg
dists/stable/main/binary-amd64/Packages
dists/stable/main/binary-amd64/Packages.gz
pool/main/<p>/<package>/<package>_<version>_amd64.deb
apt-key.asc
apt-key.gpg
```

## Using the repository

```bash
curl -fsSL https://apt.zitzhen.cn/apt-key.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/zhento-apt.gpg

echo "deb [signed-by=/usr/share/keyrings/zhento-apt.gpg arch=amd64] https://apt.zitzhen.cn stable main" \
  | sudo tee /etc/apt/sources.list.d/zhento.list

sudo apt update
```

The repository signing key fingerprint is `3B310141DFDBDE77A802C0627DFBD414F81DC0BB`.

## Adding a package

1. Append a `https://github.com/<owner>/<repo>` URL to `Software.list`.
2. Make sure the upstream repository contains a `debian/` directory.
3. Run the **Publish apt repository to R2** workflow manually from the Actions tab.

## Repository configuration

Add the following secrets and variables under **Settings -> Secrets and variables -> Actions**.

### Secrets

| Name | Description |
| --- | --- |
| `R2_ACCOUNT_ID` | Cloudflare account ID used to derive the S3 endpoint. |
| `R2_ACCESS_KEY_ID` | Access Key ID of the R2 API token. |
| `R2_SECRET_ACCESS_KEY` | Secret Access Key of the R2 API token. |
| `R2_BUCKET` | Name of the bucket bound to `apt.zitzhen.cn`. |
| `APT_GPG_PRIVATE_KEY` | ASCII-armored private key `3B310141DFDBDE77A802C0627DFBD414F81DC0BB`, from `gpg --armor --export-secret-keys 3B310141DFDBDE77A802C0627DFBD414F81DC0BB`. |
| `APT_GPG_PASSPHRASE` | Passphrase for the private key; leave empty if the key has no passphrase. |

### Variables

| Name | Description |
| --- | --- |
| `APT_GPG_KEY_ID` | Signing key fingerprint, `3B310141DFDBDE77A802C0627DFBD414F81DC0BB`. |
| `APT_REPO_URL` | Public repository URL, `https://apt.zitzhen.cn`, used in workflow logs. |

The S3 endpoint is derived as `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`.

## Local development

```bash
./scripts/parse-software-list.sh Software.list
./scripts/build-deb.sh https://github.com/zitzhen/patchsplit /tmp/debs
```

Local builds need `git`, `devscripts`, `dpkg-dev`, and `sudo` for installing build dependencies.

## DCO and Git hooks

Every commit must carry a `Signed-off-by` trailer. The versioned hooks in
`.githooks/` add and verify it. After cloning, enable them locally:

```bash
git config core.hooksPath .githooks
```

The hooks use the local `user.name` and `user.email` Git configuration.

## License

AGPL-3.0-only. See the license header in `Software.list`.
