#!/usr/bin/env zsh

# Git Auto-Update Script for Greenviro Project (ZSH)
# This script automatically adds, commits, and pushes changes to git via SSH

echo "🔄 Starting Git Auto-Update (SSH)..."

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Error: Not in a git repository!"
    exit 1
fi

# Check if SSH agent is running and has keys
if ! ssh-add -l > /dev/null 2>&1; then
    echo "🔑 SSH agent not running or no keys loaded."
    echo "💡 Starting ssh-agent and adding your SSH key..."
    
    # Start ssh-agent if not running
    if [[ -z "$SSH_AUTH_SOCK" ]]; then
        eval "$(ssh-agent -s)"
    fi
    
    # Add SSH key (will prompt for passphrase if needed)
    echo "🔐 Please enter your SSH key passphrase when prompted:"
    ssh-add
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to add SSH key. Please check your SSH setup."
        exit 1
    fi
fi

# Check git status
echo "📊 Checking current git status..."
git status --porcelain

# Check if there are any changes to commit
if [[ -z $(git status --porcelain) ]]; then
    echo "✅ No changes to commit. Repository is up to date!"
    exit 0
fi

# Add all changes
echo "➕ Adding all changes..."
git add .

# Use fixed commit message
COMMIT_MSG="This Update Automatically From zsh Script."

# Commit changes
echo "💾 Committing changes with message: '$COMMIT_MSG'"
git commit -m "$COMMIT_MSG"

if [[ $? -ne 0 ]]; then
    echo "❌ Error: Failed to commit changes!"
    exit 1
fi

# Check remote URL to confirm it's using SSH
REMOTE_URL=$(git remote get-url origin)
if [[ $REMOTE_URL == git@* ]] || [[ $REMOTE_URL == ssh://* ]]; then
    echo "🔒 Using SSH authentication: $REMOTE_URL"
else
    echo "⚠️  Warning: Remote URL doesn't appear to be SSH: $REMOTE_URL"
    echo "💡 Consider switching to SSH for better security."
fi

# Push to remote repository
echo "🚀 Pushing to remote repository via SSH..."
git push

if [[ $? -eq 0 ]]; then
    echo "✅ Successfully updated git repository!"
    echo "📝 Committed: $COMMIT_MSG"
    echo "🌐 Pushed to remote: $REMOTE_URL"
else
    echo "❌ Error: Failed to push to remote repository!"
    echo "💡 Possible issues:"
    echo "   - SSH key not properly configured"
    echo "   - Need to pull changes first (git pull)"
    echo "   - Network connectivity issues"
    echo "   - Repository permissions"
    exit 1
fi

echo "🎉 Git auto-update completed successfully!"
