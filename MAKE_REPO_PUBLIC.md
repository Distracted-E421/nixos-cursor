# Making nixos-cursor Repository Public

## Step 1: Delete Remote dev Branch (Keep It Private)

```bash
cd /home/e421/nixos-cursor

# Delete the remote dev branch
git push origin --delete dev

# Verify it's gone
git branch -a  # Should NOT show origin/dev
```

## Step 2: Configure Local dev Branch to Never Push

Add this to your repo's Git config:

```bash
# Prevent accidental pushes of dev branch
git config branch.dev.remote none
git config branch.dev.pushRemote none
```

Or add to `.git/config`:

```ini
[branch "dev"]
    remote = none
    pushRemote = none
```

## Step 3: Make Repository Public (Manual - GitHub Web UI)

**Option A: Via GitHub Website**

1. Go to: https://github.com/Distracted-E421/nixos-cursor/settings
2. Scroll to bottom: "Danger Zone"
3. Click "Change visibility" → "Change to public"
4. Type repository name to confirm
5. Click "I understand, change repository visibility"

**Option B: Via GitHub CLI**

```bash
# Install gh if not already installed
gh repo edit Distracted-E421/nixos-cursor --visibility public
```

## Step 4: Update homelab Flake Input (After Public)

Once public, update your homelab flake to use the shorter GitHub URL:

```bash
cd /home/e421/homelab/nixos

# Edit flake.nix to change:
# url = "git+ssh://git@github.com/Distracted-E421/nixos-cursor.git?ref=pre-release";
# TO:
# url = "github:Distracted-E421/nixos-cursor/pre-release";

# Or use sed:
sed -i 's|url = "git+ssh://git@github.com/Distracted-E421/nixos-cursor.git?ref=pre-release";|url = "github:Distracted-E421/nixos-cursor/pre-release";|' flake.nix

# Update the lock
nix flake lock --update-input nixos-cursor
```

## Step 5: Verify Branch Structure

After making repo public, verify:

```bash
cd /home/e421/nixos-cursor

# Check local branches
git branch
# Should show: dev, main, pre-release

# Check remote branches
git branch -r
# Should show: origin/main, origin/pre-release
# Should NOT show: origin/dev

# Check dev is local-only
git config branch.dev.remote
# Should output: none (or nothing)
```

## Final Branch Structure

```
Repository: Distracted-E421/nixos-cursor (PUBLIC)

Branches:
├── main (public)
│   └── Clean landing page
│   └── Points to RC1
│
├── pre-release (public)
│   └── v2.1.20-rc1 tag
│   └── Full documentation
│   └── .cursor/ excluded (via .gitignore)
│
└── dev (LOCAL ONLY - NEVER PUSHED)
    └── Active development
    └── .cursor/ folder included (configs, rules, hooks)
    └── Chat history in .cursor/chat-history/ (never leaves dev)
```

## Working with dev Branch Going Forward

```bash
# Normal workflow
git checkout dev
# ... do work ...
git add .
git commit -m "dev: work in progress"

# dev never gets pushed (remote = none)
# When ready to release:
git checkout pre-release
git merge dev  # Or cherry-pick specific commits
./scripts/prepare-public-branch.sh  # Cleans .cursor/ etc.
git push origin pre-release
```

## Security Notes

- **dev branch**: Local only, can contain anything (chat history, personal notes, etc.)
- **pre-release**: Public, cleaned via scripts, no .cursor/ content
- **main**: Public, stable releases only

The `.gitignore` system ensures sensitive content can't accidentally leak:
- Public branches: `.gitignore` excludes `.cursor/`
- Dev branch: `.gitignore-dev` tracks `.cursor/`

---

**Ready to make the repo public!**
