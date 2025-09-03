#!/bin/bash
set -e

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Unknown option $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$1" ]; then
    echo "Usage: $0 [--dry-run] <version_tag>"
    echo "Example: $0 v1.4.302"
    echo "         $0 --dry-run v1.4.302"
    exit 1
fi

tag="$1"
version="${tag#v}"

if [ "$DRY_RUN" = true ]; then
    echo "🧪 DRY RUN MODE - No changes will be made to PRs, commits, or pushes"
fi

echo "🔧 Fixing WinGet manifest for version $version (tag: $tag)"

# Step 1: Find the PR that was just created for this version
echo "📋 Finding PR for danielmiessler.Fabric version $version..."
pr_number=$(gh pr list --repo microsoft/winget-pkgs --search "danielmiessler.Fabric $version" --json number --jq '.[0].number')

if [ -z "$pr_number" ] || [ "$pr_number" = "null" ]; then
    echo "❌ Could not find PR for danielmiessler.Fabric version $version"
    exit 1
fi

echo "✅ Found PR #$pr_number"

# Check if PR has already been fixed (idempotency check)
echo "🔍 Checking if PR #$pr_number has already been fixed..."
pr_commits=$(gh pr view "$pr_number" --repo microsoft/winget-pkgs --json commits --jq '.commits[].messageHeadline')

if echo "$pr_commits" | grep -q "fix: multi-arch manifest for $tag"; then
    echo "✅ PR #$pr_number has already been fixed with multi-arch manifest (found fix commit)"
    echo "🎉 No action needed - manifest is already correct!"
    exit 0
fi

# Double-check by examining the actual manifest content
echo "🔍 Double-checking manifest content..."
pr_info=$(gh pr view "$pr_number" --repo microsoft/winget-pkgs --json headRefName,headRepositoryOwner,headRepository)
pr_branch=$(echo "$pr_info" | jq -r '.headRefName')
pr_repo_owner=$(echo "$pr_info" | jq -r '.headRepositoryOwner.login // "microsoft"')
pr_repo_name=$(echo "$pr_info" | jq -r '.headRepository.name // "winget-pkgs"')

manifest_url="https://raw.githubusercontent.com/$pr_repo_owner/$pr_repo_name/$pr_branch/manifests/d/danielmiessler/Fabric/$version/danielmiessler.Fabric.installer.yaml"
if curl -f -s "$manifest_url" | grep -q "InstallerType: zip"; then
    echo "✅ PR #$pr_number already has correct InstallerType: zip"
    echo "🎉 No action needed - manifest is already correct!"
    exit 0
fi

echo "📝 PR #$pr_number needs to be fixed"

# Step 2: Convert PR to draft mode
if [ "$DRY_RUN" = true ]; then
    echo "📝 [DRY RUN] Would convert PR #$pr_number to draft mode"
else
    echo "📝 Converting PR #$pr_number to draft..."
    gh pr ready --undo "$pr_number" --repo microsoft/winget-pkgs
fi

# Step 3: Setup workspace
TEMP_DIR="/tmp/fabric_winget_$$"
mkdir -p "$TEMP_DIR"
echo "📂 Created temp directory: $TEMP_DIR"

# Setup cleanup trap to remove temp directory on exit/interrupt
CLEANUP_ON_EXIT=${CLEANUP_ON_EXIT:-true}  # Default to true, can be overridden via env var

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && [ "$CLEANUP_ON_EXIT" = true ]; then
        echo "🧹 Cleaning up temp directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

# Step 4: Checkout the PR branch directly
echo "🔄 Checking out PR #$pr_number..."
cd "$TEMP_DIR"

# Get the PR details
echo "🔍 Getting PR details..."
pr_info=$(gh pr view "$pr_number" --repo microsoft/winget-pkgs --json headRefName,headRepository,headRepositoryOwner)

if [ "$DRY_RUN" = true ]; then
    echo "🐛 DEBUG: PR info JSON:"
    echo "$pr_info"
fi

pr_branch=$(echo "$pr_info" | jq -r '.headRefName')
pr_repo_owner=$(echo "$pr_info" | jq -r '.headRepositoryOwner.login')
pr_repo_name=$(echo "$pr_info" | jq -r '.headRepository.name')

echo "🐛 DEBUG: Extracted values: owner='$pr_repo_owner', name='$pr_repo_name', branch='$pr_branch'"

# Handle null values (fallback to assuming it's in microsoft/winget-pkgs)
if [ "$pr_repo_owner" = "null" ] || [ -z "$pr_repo_owner" ]; then
    pr_repo_owner="microsoft"
fi
if [ "$pr_repo_name" = "null" ] || [ -z "$pr_repo_name" ]; then
    pr_repo_name="winget-pkgs"
fi

echo "📥 Downloading manifest files from PR branch '$pr_branch' on $pr_repo_owner/$pr_repo_name..."
# Create a minimal git repo structure and download just the files we need
mkdir -p winget-pkgs/manifests/d/danielmiessler/Fabric/$version
cd winget-pkgs

# Initialize a minimal git repo so we can track changes
git init
git config user.email "fix-manifest@script.local"
git config user.name "Fix Manifest Script"

# Download the manifest files directly from the GitHub API
manifest_base_url="https://raw.githubusercontent.com/$pr_repo_owner/$pr_repo_name/$pr_branch/manifests/d/danielmiessler/Fabric/$version"

echo "📥 Downloading manifest files..."
for manifest_file in "danielmiessler.Fabric.installer.yaml" "danielmiessler.Fabric.locale.en-US.yaml" "danielmiessler.Fabric.yaml"; do
    if curl -f -s "$manifest_base_url/$manifest_file" -o "manifests/d/danielmiessler/Fabric/$version/$manifest_file"; then
        echo "✅ Downloaded $manifest_file"
    else
        echo "⚠️  Could not download $manifest_file (might not exist)"
    fi
done

# Add files to git so we can track changes
git add .
git commit -m "Initial manifest files from PR"

if [ "$DRY_RUN" = true ]; then
    echo "✅ [DRY RUN] PR checked out (read-only for inspection)"
fi

# Step 5: Generate fresh manifests with komac dry-run
echo "⚙️  Generating fresh manifests with komac dry-run..."
komac_output_dir="$TEMP_DIR/komac_output"

# Build URLs for all three architectures
arm64_url="https://github.com/danielmiessler/fabric/releases/download/$tag/fabric_Windows_arm64.zip"
x64_url="https://github.com/danielmiessler/fabric/releases/download/$tag/fabric_Windows_x86_64.zip"
i386_url="https://github.com/danielmiessler/fabric/releases/download/$tag/fabric_Windows_i386.zip"

komac update danielmiessler.Fabric \
    --version "$version" \
    --urls "$arm64_url" "$x64_url" "$i386_url" \
    --dry-run \
    --output "$komac_output_dir"

# Step 6: Fix the InstallerType in the generated manifest
installer_manifest_path="$komac_output_dir/manifests/d/danielmiessler/Fabric/$version/danielmiessler.Fabric.installer.yaml"

if [ ! -f "$installer_manifest_path" ]; then
    echo "❌ Generated installer manifest not found at: $installer_manifest_path"
    exit 1
fi

echo "🔧 Fixing InstallerType from 'portable' to 'zip'..."
sed 's/^InstallerType: portable/InstallerType: zip/' "$installer_manifest_path" > "$TEMP_DIR/fixed_installer.yaml"

# Step 7: Replace the installer manifest in the PR
target_manifest="manifests/d/danielmiessler/Fabric/$version/danielmiessler.Fabric.installer.yaml"
cp "$TEMP_DIR/fixed_installer.yaml" "$target_manifest"

echo "✅ Replaced installer manifest with fixed version"

# Step 8: Commit and push the changes
if [ "$DRY_RUN" = true ]; then
    echo "📤 [DRY RUN] Would commit and push changes with message:"
    echo "    fix: multi-arch manifest for $tag"
    echo "    - Changed InstallerType from 'portable' to 'zip'"
    echo "    - Updated manifest to properly support all three architectures (arm64, x64, i386)"
else
    echo "📤 Committing and pushing changes..."
    git add "$target_manifest"
    git commit -m "fix: multi-arch manifest for $tag

- Changed InstallerType from 'portable' to 'zip'
- Updated manifest to properly support all three architectures (arm64, x64, i386)"

    git push
fi

# Step 9: Convert PR back to ready status
if [ "$DRY_RUN" = true ]; then
    echo "✅ [DRY RUN] Would convert PR #$pr_number back to ready for review"
else
    echo "✅ Converting PR #$pr_number back to ready for review..."
    gh pr ready "$pr_number" --repo microsoft/winget-pkgs
fi

# Cleanup
if [ "$DRY_RUN" = true ]; then
    echo "📁 Files generated in: $TEMP_DIR"
    echo "   - PR checkout directory: $TEMP_DIR/winget-pkgs/"
    echo "   - Original manifest (if exists): $TEMP_DIR/winget-pkgs/manifests/d/danielmiessler/Fabric/$version/"
    echo "   - Generated manifests: $TEMP_DIR/komac_output/manifests/d/danielmiessler/Fabric/$version/"
    echo "   - Fixed installer manifest: $TEMP_DIR/fixed_installer.yaml"
    echo ""
    echo "💡 To inspect changes:"
    echo "   cd $TEMP_DIR/winget-pkgs"
    echo "   git status                    # See which files would be modified"
    echo "   git diff                      # See current changes (if any)"
    echo "   # Compare original vs fixed:"
    echo "   diff manifests/d/danielmiessler/Fabric/$version/danielmiessler.Fabric.installer.yaml ../fixed_installer.yaml"
    echo ""
    read -p "🗑️  Clean up temp directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_ON_EXIT=true  # Let trap handle cleanup
    else
        CLEANUP_ON_EXIT=false  # Disable trap cleanup
        echo "📂 Temp directory preserved: $TEMP_DIR"
    fi
else
    CLEANUP_ON_EXIT=true  # Let trap handle cleanup on normal exit
fi

if [ "$DRY_RUN" = true ]; then
    echo "🎉 [DRY RUN] Would have successfully fixed manifest for danielmiessler.Fabric $version!"
    echo "📋 PR #$pr_number would be ready for review with correct multi-architecture support"
    echo "💡 To apply changes, run: $0 $tag"
else
    echo "🎉 Successfully fixed manifest for danielmiessler.Fabric $version!"
    echo "📋 PR #$pr_number is now ready for review with correct multi-architecture support"
fi