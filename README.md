# Fabric Packager

Auxiliary packaging tools for the [Fabric CLI](https://github.com/danielmiessler/fabric), providing automated distribution to various package managers. Currently supports automated publishing to the Windows Package Manager (WinGet) and Docker registries (GHCR + Docker Hub).

## Overview

This repository contains GitHub Actions workflows that automatically monitor Fabric releases and publish them to multiple distribution channels:

- **WinGet**: Uses the [michidk/run-komac](https://github.com/michidk/run-komac) action to handle Windows installer detection and manifest submission to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)
- **Docker**: Builds and publishes multi-architecture container images to GitHub Container Registry (GHCR) and Docker Hub

## Setup Required

Before the workflows can function, you need to complete these setup steps:

### 1. WinGet Publishing Setup

**Create Personal Access Token:**

1. Go to [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Name: `WINGET_TOKEN`
4. Scope: `public_repo`
5. Generate and copy the token

**Add Repository Secret:**

1. In this repository, go to Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `WINGET_TOKEN`
4. Value: Your personal access token from above

### 2. Docker Publishing Setup

**Configure Docker Hub (Required):**

1. Create a Docker Hub access token at [Docker Hub → Account Settings → Security](https://hub.docker.com/settings/security)
2. In this repository, add these secrets:
   - `DOCKERHUB_TOKEN`: Your Docker Hub access token
3. In this repository, add this variable (Settings → Secrets and variables → Actions → Variables tab):
   - `DOCKERHUB_USERNAME`: Your Docker Hub username

**GitHub Container Registry (GHCR):**

- Uses the built-in `GITHUB_TOKEN` - no additional setup required

**That's it!** The workflows handle everything else automatically:

- **WinGet**: Forking microsoft/winget-pkgs, installing Komac, creating pull requests
- **Docker**: Building multi-arch images, pushing to both registries, managing `:latest` tags

## How It Works

All workflows use a simple, reliable process:

1. **Parse release information** - Extract version and tag from Fabric releases
2. **Detect assets** - Find Windows installers for WinGet, checkout Fabric source for Docker
3. **Check for duplicates** - Skip publishing if releases already exist in target registries
4. **Publish to distribution channels**:
   - **WinGet**: Use the [run-komac action](https://github.com/michidk/run-komac) to handle manifest updates
   - **Docker**: Build multi-architecture images and push to GHCR + Docker Hub

### WinGet Publishing

The `michidk/run-komac` action handles all the complexity:

- Downloads and installs Komac
- Manages winget-pkgs repository interactions
- Creates and submits pull requests to microsoft/winget-pkgs
- Handles authentication and error reporting

### Docker Publishing

The Docker workflows provide:

- Multi-architecture builds (amd64, arm64)
- Simultaneous publishing to GHCR and Docker Hub
- Automatic `:latest` tag management for newest releases
- Duplicate detection to avoid unnecessary rebuilds

## Workflows

### 1. Monitor Releases (`monitor-releases.yml`) - Recommended

Automatically checks for new Fabric releases every 3 hours and publishes them to all channels.

- **Runs on**: Ubuntu runners (fast and reliable)
- **Schedule**: Every 3 hours via cron (`13 */3 * * *`)
- **Manual trigger**: Optional version parameter
- **Process**:
  1. Checks GitHub API for latest release
  2. Finds Windows assets → Submits to WinGet (if assets exist)
  3. Checks Docker registries → Triggers Docker publishing (if images missing)
  4. Skips already-published releases automatically

### 2. Manual WinGet Publishing (`manual-publish.yml`)

User-friendly manual WinGet publishing for specific releases.

- **Runs on**: Ubuntu runners
- **Input**: GitHub release URL (e.g., `https://github.com/danielmiessler/fabric/releases/tag/v1.4.302`)
- **Process**: Extracts version → Finds Windows assets → Submits to WinGet

### 3. Manual Docker Publishing (`manual-docker-publish.yml`)

User-friendly manual Docker publishing for specific releases.

- **Runs on**: Ubuntu runners
- **Input**: GitHub release URL (e.g., `https://github.com/danielmiessler/fabric/releases/tag/v1.4.302`)
- **Process**: Extracts version → Builds multi-arch Docker images → Pushes to GHCR & Docker Hub
- **Features**: Duplicate detection, automatic `:latest` tag management

### 4. Webhook Publishing (`winget-publish.yml`)

Immediate WinGet publishing triggered by external webhooks.

- **Runs on**: Ubuntu runners
- **Triggers**: Repository dispatch events (`fabric-winget-release`) or manual trigger with tag
- **Process**: Uses provided tag → Finds Windows assets → Submits to WinGet

### 5. Docker Webhook Publishing (`docker-publish.yml`)

Immediate Docker publishing triggered by external webhooks.

- **Runs on**: Ubuntu runners
- **Triggers**: Repository dispatch events (`fabric-docker-release`) or manual trigger with tag
- **Process**: Uses provided tag → Builds multi-arch Docker images → Pushes to GHCR & Docker Hub

## Usage

### Automatic (Recommended)

The monitor workflow will automatically publish new releases to all channels. No action required.

### Manual WinGet Publishing

1. Go to Actions → Manual WinGet Publishing
2. Click "Run workflow"
3. Enter the GitHub release URL (e.g., `https://github.com/danielmiessler/fabric/releases/tag/v1.4.302`)
4. Click "Run workflow"

### Manual Docker Publishing

1. Go to Actions → Manual Docker Publishing
2. Click "Run workflow"
3. Enter the GitHub release URL (e.g., `https://github.com/danielmiessler/fabric/releases/tag/v1.4.302`)
4. Click "Run workflow"

### Webhook Integration (Optional)

To trigger immediate publishing from the main Fabric repository, add these steps to the Fabric release workflow:

```yaml
- name: Trigger WinGet Publishing
  run: |
    curl -X POST \
      -H "Authorization: token ${{ secrets.WINGET_DISPATCH_TOKEN }}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/YOUR_USERNAME/fabric-packager/dispatches \
      -d '{
        "event_type": "fabric-winget-release",
        "client_payload": {
          "tag": "${{ github.ref_name }}",
          "url": "${{ github.event.release.html_url }}"
        }
      }'

- name: Trigger Docker Publishing
  run: |
    curl -X POST \
      -H "Authorization: token ${{ secrets.DOCKER_DISPATCH_TOKEN }}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/YOUR_USERNAME/fabric-packager/dispatches \
      -d '{
        "event_type": "fabric-docker-release",
        "client_payload": {
          "tag": "${{ github.ref_name }}",
          "url": "${{ github.event.release.html_url }}"
        }
      }'
```

## Prerequisites

### WinGet Requirements

- Fabric must already exist in WinGet (at least one version manually submitted)
- Fabric releases must include Windows installer files (`.exe`, `.msi`, `.msix`, `.appx`)
- Personal Access Token with `public_repo` scope

### Docker Requirements

- Docker Hub account with valid access token
- Fabric source code must include `scripts/docker/Dockerfile`
- Repository variables and secrets configured (see Setup section)

## Troubleshooting

### Common Issues

1. **"Package not found" error**
   - Ensure Fabric already exists in WinGet (run `winget search danielmiessler.fabric`)
   - If not found, the first version must be manually submitted to winget-pkgs

2. **"Unauthorized" or "Authentication" error**
   - Check that `WINGET_TOKEN` secret is set correctly in repository settings
   - Verify token has `public_repo` scope and hasn't expired
   - Ensure you're using a classic Personal Access Token (not fine-grained)

3. **"No Windows installer assets found" message**
   - Verify the Fabric release contains Windows installer files
   - Supported formats: `.exe`, `.msi`, `.msix`, `.appx`
   - Check the release assets in the GitHub release page

4. **Workflow fails silently**
   - Check the Actions tab for detailed error logs
   - Ensure the release tag format matches expectations (e.g., `v1.4.302`)

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

## Technical Details

### Key Components

- **run-komac Action**: [michidk/run-komac@v2](https://github.com/michidk/run-komac) - Handles all Komac operations automatically
- **Komac**: Modern WinGet manifest creation tool written in Rust (installed by the action)
- **Package identifier**: `danielmiessler.Fabric`
- **Supported formats**: `.exe`, `.msi`, `.msix`, `.appx` installer files

### Workflow Environment

All workflows run on `ubuntu-latest` runners for:

- **Speed**: Ubuntu runners start faster than Windows
- **Reliability**: More stable and predictable environment
- **Simplicity**: No Windows-specific PATH or installation issues
- **Cost**: Ubuntu runners are more cost-effective

### Version Management

- **All versions are retained** by default in the WinGet repository
- Users can install any published version: `winget install danielmiessler.Fabric --version 1.4.302`
- No automatic cleanup of old versions (standard WinGet practice)

## References

### Tools Used

- [run-komac Action](https://github.com/michidk/run-komac) - GitHub Action that runs Komac automatically
- [Komac](https://github.com/russellbanks/Komac) - Modern WinGet manifest creation tool (used by the action)
- [Microsoft WinGet CLI](https://github.com/microsoft/winget-cli) - Windows Package Manager

### Documentation

- [Microsoft WinGet Documentation](https://learn.microsoft.com/en-us/windows/package-manager/)
- [WinGet Package Submission Guidelines](https://learn.microsoft.com/en-us/windows/package-manager/package/)
- [WinGet Manifest Schema](https://learn.microsoft.com/en-us/windows/package-manager/package/manifest)

### Repositories

- [Fabric Repository](https://github.com/danielmiessler/fabric) - Source project
- [WinGet Package Repository](https://github.com/microsoft/winget-pkgs) - Official package repository

## License

This repository is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
