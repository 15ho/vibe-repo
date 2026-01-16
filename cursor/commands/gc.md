# /gc

You are an agent running inside Cursor with terminal access.

Goal:
- Enforce Gitflow + Conventional Commits
- Prepare a correct commit message, but DO NOT commit automatically

Steps:

1) Show git status:
   - Run `git status --short`
   - If there are unstaged changes, stage ALL changes using:
     git add -A

2) Collect staged changes ONLY:
   - git diff --staged --name-status
   - git diff --staged --stat
   - git diff --staged

3) Generate a Conventional Commit message:
   - Infer <type> from code changes
   - Infer <scope> from top-level directory or module
   - Summary line ≤ 72 characters, imperative mood
   - Body as bullet points from diff/stat
   - Add BREAKING CHANGE only if API/behavior changed

4) Output ONLY:
   - current branch
   - final commit message, the message needs to be concise.

Do NOT run git commit.
Wait for my confirmation.