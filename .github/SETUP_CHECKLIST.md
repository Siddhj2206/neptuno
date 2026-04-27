# Repository Setup Checklist

## Initial Setup

### 1. Verify Project Identity

- [ ] Confirm `neptuno` is used consistently in: `Containerfile`, `Justfile`, `README.md`, and `artifacthub-repo.yml`
- [ ] Replace any remaining template placeholders or example values with project-specific content

### 2. Enable GitHub Actions

- [ ] Settings → Actions → General → Enable workflows
- [ ] Set "Read and write permissions"

### 3. First Push

```bash
git add .
git commit -m "feat: initial customization"
git push origin main
```

### 4. Deploy

```bash
sudo bootc switch --transport registry ghcr.io/<owner>/neptuno:stable
sudo systemctl reboot
```

## Optional: Production Features

### Enable Signing (Recommended)

```bash
cosign generate-key-pair
# Add cosign.key to GitHub Secrets as SIGNING_SECRET
# Uncomment signing in .github/workflows/build.yml
```
