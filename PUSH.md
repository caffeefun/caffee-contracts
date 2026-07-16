# How to publish this repo (copy-paste)

This folder (`ops/opensource/`) is a **self-contained, ready-to-publish** repository. Nothing here touches
the live app or any credentials. Follow either path below to push it to a **new public GitHub repo**.

> Run every command from **inside this folder**:
>
> ```bash
> cd /var/www/caffee/ops/opensource
> ```
>
> Replace `<REPO_URL>` / `<OWNER>/<REPO>` with your target, e.g. `caffee-fun/caffee-contracts`.

## 1. Initialize the local git repo

```bash
cd /var/www/caffee/ops/opensource

git init
git add .
git commit -m "Open-source Caffee smart contracts (verified on Robinhood Chain 4663)"
git branch -M main
```

## 2. Create + push the public repo

### Option A — GitHub CLI (`gh`), creates the repo for you

```bash
# authenticate once if you haven't: gh auth login
gh repo create <OWNER>/<REPO> --public --source=. --remote=origin --push
```

That single `gh repo create` command creates the public repo, adds it as `origin`, and pushes `main`.

### Option B — create the repo in the GitHub UI first, then push

1. On GitHub: **New repository** → name it (e.g. `caffee-contracts`) → **Public** → **do not** add a
   README/License/.gitignore (this folder already has them) → **Create repository**.
2. Then:

```bash
git remote add origin <REPO_URL>     # e.g. https://github.com/<OWNER>/<REPO>.git  (or git@github.com:<OWNER>/<REPO>.git)
git push -u origin main
```

## 3. After publishing (recommended)

- Add the repo link to caffee.fun and the docs so the community can find it.
- In the repo **About** box, set the description and topics (e.g. `solidity`, `robinhood-chain`,
  `bonding-curve`, `launchpad`) and link <https://caffee.fun>.
- Optionally add the four Blockscout verification links (see `README.md`) to the About/README so visitors
  can confirm the on-chain match in one click.

---

**What gets pushed:** `contracts/` (the four verified Solidity sources + the Standard-JSON verification
inputs), `README.md`, `LICENSE`, `SECURITY.md`, and this `PUSH.md`. No private keys, no app code, no build
output.
