# Fabric WinGet Publisher

Automated publishing of [Fabric](https://github.com/danielmiessler/fabric) releases to the Windows Package Manager (WinGet).

## Overview

This repository contains GitHub Actions workflows that automatically monitor Fabric releases and publish them to WinGet through the [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) repository.

## Setup Required

Before the workflows can function, you need to complete these setup steps:

### 1. Fork microsoft/winget-pkgs

1. Navigate to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)
2. Click "Fork" in the top-right corner
3. Fork to your account (keep the name `winget-pkgs`)

### 2. Create Personal Access Token

1. Go to [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Name: `WINGET_TOKEN`
4. Scope: `public_repo`
5. Generate and copy the token

### 3. Add Repository Secret

1. In this repository, go to Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `WINGET_TOKEN`
4. Value: Your personal access token from step 2

### 4. Update Fork Username

Update the `fork-user` parameter in all workflow files to match your GitHub username:

- `.github/workflows/monitor-releases.yml`
- `.github/workflows/winget-publish.yml`  
- `.github/workflows/manual-publish.yml`

Change `fork-user: ksylvan` to `fork-user: YOUR_USERNAME`

## Workflows

### 1. Monitor Releases (`monitor-releases.yml`)

**Recommended approach** - Automatically checks for new Fabric releases every 6 hours.

- **Schedule**: Runs every 6 hours via cron
- **Manual trigger**: Can be triggered manually with optional version parameter
- **Function**: Checks for latest Fabric release and publishes to WinGet

### 2. Webhook Publishing (`winget-publish.yml`)

Immediate response to releases via webhook or manual trigger.

- **Repository dispatch**: Triggered by external webhook
- **Manual trigger**: Requires release tag input
- **Function**: Publishes specific release to WinGet

### 3. Manual Publishing (`manual-publish.yml`)

Backup method for manual publishing with user-friendly inputs.

- **Manual trigger**: Accepts GitHub release URL
- **Version extraction**: Automatically extracts version from URL
- **Function**: Publishes any release to WinGet

## Usage

### Automatic (Recommended)

The monitor workflow will automatically publish new releases. No action required.

### Manual Publishing

1. Go to Actions → Manual WinGet Publishing
2. Click "Run workflow"
3. Enter the GitHub release URL (e.g., `https://github.com/danielmiessler/fabric/releases/tag/v1.4.302`)
4. Click "Run workflow"

### Webhook Integration (Optional)

To trigger immediate publishing from the main Fabric repository, add this step to the Fabric release workflow:

```yaml
- name: Trigger WinGet Publishing
  run: |
    curl -X POST \
      -H "Authorization: token ${{ secrets.WINGET_DISPATCH_TOKEN }}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/YOUR_USERNAME/fabric-winget/dispatches \
      -d '{
        "event_type": "fabric-release",
        "client_payload": {
          "tag": "${{ github.ref_name }}",
          "url": "${{ github.event.release.html_url }}"
        }
      }'
```

## Prerequisites

- Fabric must already exist in WinGet (at least one version manually submitted)
- Fabric releases must include Windows binaries (`.exe`, `.msi`, or `.zip`)
- GitHub fork of microsoft/winget-pkgs repository
- Personal Access Token with `public_repo` scope

## Troubleshooting

### Common Issues

1. **"Package not found" error**
   - Ensure Fabric exists in winget-pkgs repository
   - First version must be manually submitted

2. **"Unauthorized" error**
   - Check that `WINGET_TOKEN` secret is set correctly
   - Verify token has `public_repo` scope and hasn't expired

3. **"Fork not found" error**
   - Verify you've forked microsoft/winget-pkgs
   - Check `fork-user` parameter matches your GitHub username

4. **"No matching installers" error**
   - Verify Fabric release contains Windows binaries
   - Check release assets include `.exe`, `.msi`, or `.zip` files

### Testing

Test your WinGet package:

```bash
# Search for Fabric
winget search fabric

# Show package details
winget show danielmiessler.Fabric

# Install Fabric
winget install danielmiessler.Fabric
```

## Configuration

### Workflow Parameters

All workflows support these common parameters:

- `identifier`: `danielmiessler.Fabric` (WinGet package identifier)
- `token`: `${{ secrets.WINGET_TOKEN }}` (GitHub PAT)
- `fork-user`: Your GitHub username
- `max-versions-to-keep`: `5` (Retain only 5 latest versions)

### Installer Filtering

The webhook workflow includes installer filtering:

```yaml
installers-regex: '\.exe$|\.msi$'  # Only .exe and .msi files
```

Adjust this pattern if Fabric uses different installer formats.

## References

- [WinGet-Releaser Action](https://github.com/vedantmgoyal9/winget-releaser)
- [Microsoft WinGet Documentation](https://learn.microsoft.com/en-us/windows/package-manager/)
- [Fabric Repository](https://github.com/danielmiessler/fabric)
- [WinGet Package Repository](https://github.com/microsoft/winget-pkgs)

## License

This repository is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.