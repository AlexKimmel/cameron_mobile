# Overnight Run

## Goal

Work through the unchecked items in `todo.md` for this checkout, in order, one item at a time. Keep working until every item is done or work is blocked. Do not work on multiple TODOs concurrently.

## Start

1. Confirm the repository root and inspect `git status`, the current branch, `todo.md`, and any `AGENTS.md` instructions.
2. Preserve any existing user changes. Do not discard, reset, or include unrelated changes in a commit.
3. Start the run on a branch named `overnight`, based on the current checkout's branch and commit. If `overnight` already exists, inspect its history and working tree before switching; do not reset it or overwrite its work. If its starting point is unclear, stop and report that rather than guessing.
4. Read the full TODO list and project guidance before choosing work. Select the first unchecked item.

## For each TODO

1. Work only on the selected TODO. Inspect the relevant code and implement the complete, smallest coherent change that satisfies it.
2. Follow the repository's existing architecture, style, and package boundaries. Avoid unrelated cleanup or scope expansion.
3. Run the relevant formatter, analyzer, and focused tests or build checks for the change. Do not claim checks passed unless they were run. If a check cannot be run, record why.
4. Review the diff and ensure it contains only this TODO's work. Keep unrelated pre-existing changes out of the commit.
5. Mark that exact item checked in `todo.md` only after its implementation and relevant verification are complete.
6. Commit the implementation and its checkbox update together before moving on. Use a descriptive conventional commit subject that identifies the TODO, for example:

   ```text
   feat(tasks): add search across task titles and notes
   ```

   Include a commit body with `Todo: <exact or clearly shortened todo text>`, a short summary of the change, and the checks run (including any checks not run and why). Each completed TODO gets its own commit.
7. Confirm the commit succeeded and the worktree is clean apart from any unrelated changes that were already present. Then select the next unchecked item.

## Stop conditions

- Stop if all items in `todo.md` are checked; report the completed commits and checks.
- If an item is blocked by missing requirements, unavailable credentials/devices, a failing dependency, or an unsafe or destructive choice, leave it unchecked. Commit any independently complete work for that item only if it is useful and coherent; otherwise leave it uncommitted only when a fix is still actively in progress. Report the blocker and continue with the next independent TODO where possible.
- If a TODO depends on another unchecked item, do not start the dependent work early. Continue with the earliest prerequisite in list order.
- If the run is interrupted, leave the branch and commits intact. On resuming, inspect the branch, status, latest commits, and TODO checkboxes to determine the next item; never repeat or amend a completed TODO's commit just to continue.
- Never force-push, rewrite existing history, or silently change the TODO list's scope. Add new TODOs only when the user asks.

## Completion report

Summarize the TODOs completed, their commit hashes and subjects, the checks run, and any unchecked items with blockers. State the branch name and whether the worktree is clean.
