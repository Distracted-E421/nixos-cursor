# URL Validation and Hash Computation Scripts

Scripts for validating Cursor download URLs and computing SHA256 hashes for new versions.

## Scripts

### `validate-urls.sh`

Validates that all download URLs in the URL files are accessible.

```bash
./scripts/validation/validate-urls.sh
```

**Output:**
- Creates validation report in `.cursor/validation-results/`
- Reports HTTP status codes for each URL
- Identifies broken or inaccessible URLs

### `compute-hashes.sh`

Computes SHA256 hashes for new Cursor versions that don't have hashes yet.

```bash
# Compute hashes for all missing versions
./scripts/validation/compute-hashes.sh --all

# Output in Nix format
./scripts/validation/compute-hashes.sh --all --nix

# Save to file
./scripts/validation/compute-hashes.sh --all --nix -o new-versions.nix

# Compute hash for a specific URL
./scripts/validation/compute-hashes.sh https://downloads.cursor.com/.../Cursor-X.Y.Z-x86_64.AppImage
```

**Options:**
- `--all` - Compute hashes for all versions in URL files that aren't in cursor-versions.nix
- `--nix` - Output in Nix attribute format (ready to paste into cursor-versions.nix)
- `-o FILE` - Write output to file
- `-v VERSION` - Specify version (auto-detected from URL if not provided)

## URL Files

- `.cursor/linux -x64-version-urls.txt` - Linux x64 AppImage URLs
- `.cursor/darwin-all-urls.txt` - macOS DMG URLs (universal, x64, arm64)

## Adding New Versions

1. Add the URL to the appropriate URL file
2. Run `./scripts/validation/compute-hashes.sh --all --nix`
3. Copy the output to `cursor-versions.nix`
4. Add the package export to `flake.nix`
5. Run `./tests/all-versions-test.sh quick` to verify

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/ci.yml`) includes:
- URL validation on workflow dispatch
- Build tests for all versions
- Automatic flake checking

## Requirements

- `curl` - For downloading and checking URLs
- `nix` - For hash computation
- `jq` - For parsing flake output (tests only)
