# Git Basics

Essential Git commands and best practices for collaborative development on the PLC interpreter. Use this as the team's quick reference when working with the shared GitLab repository.

## Daily Workflow

### Checking Status
Always check what's changed before committing:
```bash
  git status
```
Shows modified, staged, and untracked files.

### Adding Files
Stage files for commit:
```bash
  # Add specific file
  git add filename.hs

  # Add all changes
  git add .

  # Add all files in a directory
  git add src/
```

### Committing
Commit your staged changes with a descriptive message:
```bash
  git commit -m "Add user login functionality"
```

**Commit regularly!** Small, frequent commits are better than large, infrequent ones.
- Commit when you complete a feature or fix a bug
- Commit before switching tasks
- Write clear, descriptive commit messages

### Pulling and Fetching
Get the latest changes from the remote before you push:
```bash
  # Fetch remote refs (doesn't change your working files)
  git fetch origin

  # Fetch and merge into your current branch
  git pull

  # Pull from a specific remote and branch
  git pull origin main
```

### Pushing
Send your commits to the remote repository:
```bash
  # Push current branch (if upstream is already set)
  git push

  # Push and set upstream in one go (use first time you push a new branch)
  git push -u origin feature/notification

  # Push current branch and set upstream (no need to type branch name)
  git push -u origin HEAD

  # Push a specific branch
  git push origin feature/notification
```

**Setting upstream:** After `git push -u origin <branch-name>` (or `git push -u origin HEAD`), future `git push` and `git pull` use that remote branch automatically.

**NEVER FORCE PUSH** (`git push --force` or `git push -f`) on shared branches unless the team agrees.
- Force pushing overwrites the remote and can cause data loss for others.
- Safe only on a branch only you use; ask for help if unsure.

## Branching

### Why Branch?
- Work on features without affecting the main code
- Test changes safely
- Collaborate without conflicts

### Creating a Branch
```bash
    # Create and switch to a new branch
    git checkout -b feature-name
    
    # Examples:
    git checkout -b add-login-page
    git checkout -b fix-database-bug
```

### Switching Branches
```bash
    git checkout branch-name
    
    # Switch back to main
    git checkout main
```

### Viewing Branches
```bash
    # List all branches
    git branch
    
    # List all branches including remote
    git branch -a
```

### Renaming a Branch
```bash
    # Rename the current branch
    git branch -m new-branch-name

    # Rename another branch (you must not be on it)
    git branch -m old-name new-name
```

### Merging Branches
```bash
    # Switch to main first
    git checkout main

    # Merge your branch into main
    git merge feature-name

    # Merge without auto-committing (useful to review first)
    git merge --no-commit --no-ff feature-name
```

## Remotes

### View and Change Remote URL
```bash
    # List remotes and their URLs
    git remote -v

    # Change the URL for origin (e.g. fix wrong URL or switch HTTP/SSH)
    git remote set-url origin git@git.soton.ac.uk:group/repo.git

    # Add a remote (if you don't have one)
    git remote add origin <url>
```

## Rebase

Rebase replays your commits on top of another branch, giving a linear history. Use on **your own** branches; avoid rebasing shared branches.

### Rebase onto main
Update your feature branch with the latest `main`:
```bash
    git checkout feature/notification
    git fetch origin
    git rebase origin/main
```
If there are conflicts, fix them, then `git add` and `git rebase --continue`. To abort: `git rebase --abort`.

### After rebasing, push
If you already pushed this branch before rebasing, you need a force push (only if no one else uses this branch):
```bash
    git push --force-with-lease origin feature/notification
```
`--force-with-lease` is safer than `--force`: it refuses to push if the remote has new commits you don't have.

### Interactive rebase (squash or reorder commits)
```bash
    # Rebase last 3 commits (edit, squash, reorder)
    git rebase -i HEAD~3
```
In the editor, change `pick` to `squash` (or `s`) to fold a commit into the previous one, or reorder lines. Save and close; then fix any conflicts if Git asks.

## Stash (Temporary Save)

Save uncommitted changes without committing, so you can switch branch or pull:
```bash
    # Stash changes (including untracked with -u)
    git stash
    git stash -u

    # List stashes
    git stash list

    # Apply most recent stash and keep it in the list
    git stash apply

    # Apply and remove from stash list
    git stash pop

    # Drop the last stash
    git stash drop
```

## Merge Conflicts

When `git merge` or `git pull` reports a conflict:
1. Open the listed files; look for `<<<<<<<`, `=======`, `>>>>>>>`.
2. Edit the file to keep the right code and remove the conflict markers.
3. Stage the file: `git add path/to/file`.
4. Finish: `git commit` (merge), or `git rebase --continue` (rebase).

## Restoring Changes

### Undo Unstaged Changes
Discard changes to a file (before `git add`):
```bash
    git restore filename.hs
```

### Unstage Files
Remove files from staging area (undo `git add`):
```bash
    git restore --staged filename.hs
```

### Discard All Local Changes
**WARNING: This deletes all uncommitted work!**
```bash
    git restore .
```

## Reflog (Time Travel)

Git reflog shows your command history - use it to recover from mistakes.

### View Reflog
```bash
    git reflog
```

### Recover Lost Commits
If you accidentally reset or lost commits:
```bash
    # Find the commit hash in reflog
    git reflog
    
    # Go back to that commit
    git reset --hard HEAD@{n}
```
Replace `{n}` with the number from reflog (e.g., `HEAD@{2}`)

## Best Practices

1. **Pull before you push**
```bash
   git pull
   git push
```
Avoid conflicts by getting latest changes first.

2. **Commit often, push regularly**
    - Commit: Every logical change
    - Push: At least once per work session

3. **Write good commit messages**
    - ✅ "Add password validation to login form"
    - ✅ "Fix null pointer exception in user service"
    - ❌ "fixed stuff"
    - ❌ "asdfasdf"

4. **Never commit sensitive data**
    - No passwords, API keys, or personal information
    - Use `.gitignore` for sensitive files

5. **Use branches for features**
    - Don't work directly on `main`
    - Create a branch, test it, then merge

6. **Communicate with your team**
    - Before merging, make sure others know
    - Resolve merge conflicts together
    - Pull regularly to stay in sync

## Common Scenarios

### "I committed to the wrong branch"
```bash
    # Note the commit hash
    git log
    
    # Switch to correct branch
    git checkout correct-branch
    
    # Cherry-pick the commit
    git cherry-pick commit-hash
```

### "I need to see what changed in a file"
```bash
    git diff filename.java
```

### "I want to undo my last commit (but keep changes)"
```bash
    git reset --soft HEAD~1
```

### "Someone else pushed and now I can't push"
```bash
    git pull
    # Resolve any conflicts
    git push
```

### "First time pushing a new branch"
```bash
    git push -u origin HEAD
    # or
    git push -u origin feature/notification
```
After that, plain `git push` and `git pull` work on this branch.

### "I want to update my branch with latest main"
```bash
    git fetch origin
    git rebase origin/main
    # Fix conflicts if any, then:
    git push --force-with-lease origin HEAD
```
Only use `--force-with-lease` on a branch that only you push to.

### "I have uncommitted changes but need to pull / switch branch"
```bash
    git stash
    git pull   # or git checkout other-branch
    git stash pop
```

## Quick reference

| Task | Command |
|------|--------|
| Status | `git status` |
| Stage all | `git add .` |
| Commit | `git commit -m "message"` |
| Push (first time for branch) | `git push -u origin HEAD` |
| Push / pull (after upstream set) | `git push` / `git pull` |
| New branch | `git checkout -b branch-name` |
| Switch branch | `git checkout branch-name` |
| Merge main into current | `git merge main` |
| Rebase on main | `git fetch origin` then `git rebase origin/main` |
| Stash changes | `git stash` / `git stash pop` |
| See remotes | `git remote -v` |
| Undo last commit (keep changes) | `git reset --soft HEAD~1` |

## Remember

- **Commit often** - Small commits are easier to understand and debug
- **Never force push** - You'll overwrite others' work
- **Pull before push** - Stay synced with the team
- **Use branches** - Keep main stable
- **Ask for help** - Better to ask than to break something
