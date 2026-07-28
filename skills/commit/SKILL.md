---
name: commit
description: "Read this skill before making git commits"
---

Checkpoint known task changes immediately as a WIP commit, leave unrelated changes untouched, then amend that checkpoint into a concise Conventional Commit after fresh verification passes.

## Format

Draft: `WIP: <type>(<scope>): <summary>`

Final: `<type>(<scope>): <summary>`

- `WIP:` is REQUIRED until fresh verification succeeds.
- `type` REQUIRED. Use `feat` for new features, `fix` for bug fixes. Other common types: `docs`, `refactor`, `chore`, `test`, `perf`.
- `scope` OPTIONAL. Short noun in parentheses for the affected area (e.g., `api`, `parser`, `ui`).
- `summary` REQUIRED. Short, imperative, <= 72 chars, no trailing period.

## Notes

- Body is OPTIONAL. If needed, add a blank line after the subject and write short paragraphs.
- Do NOT include breaking-change markers or footers.
- Do NOT add sign-offs (no `Signed-off-by`).
- Only commit; do NOT push.
- Describe every unrelated or pre-existing change found before any necessary clarification. Say explicitly when none exist.
- Immediately commit known task changes as WIP without asking for confirmation.
- Exclude unrelated, pre-existing, or ambiguous changes unless the user already explicitly included them.
- Do not request routine commit-scope confirmation; proceed with verification after the WIP exists.
- Before WIP, only inspect with commands such as `git status`, `git diff`, and `git diff --cached`. Do not run any command containing `--check`, or any test, lint, build, or validation command.
- Never stage unrelated or pre-existing changes without explicit inclusion. Do not unstage or otherwise alter pre-existing staged changes; use path-limited commits.
- Treat caller-provided arguments as scope guidance. Common patterns:
  - Freeform instructions should influence scope, summary, and body.
  - File paths or globs should limit which files to commit. If files are specified, only stage/commit those unless the user explicitly asks otherwise.
  - If arguments combine files and instructions, honor both.

## Steps

1. Infer the known task scope and message guidance from the prompt and session history.
2. Review `git status`, staged changes, and relevant diffs. Separate known task changes from unrelated, pre-existing, or ambiguous changes.
3. Report the unrelated/pre-existing changes first, or state that none exist.
4. Without asking for confirmation, stage only known task paths and immediately create the WIP with no check in between:
   ```bash
   git add -- <known-task-paths>
   git commit --only -m "WIP: <conventional subject>" -- <known-task-paths>
   ```
   `--only` excludes unrelated changes that were already staged.
5. Leave excluded files and their index state untouched, then proceed with the appropriate verification.
   - Ask for clarification only when no safe known-task scope can be identified.
   - If the user later includes more files, amend them into WIP before rerunning verification.
6. Run the appropriate verification.
7. If verification fails, report the evidence. For each fix:
   - edit only the known task scope;
   - stage it and `git commit --amend --no-edit` before rerunning verification;
   - leave `WIP:` in place.
8. After fresh verification passes, amend only the message to remove `WIP:`. Report the final commit and verification evidence.
9. If work stops or verification cannot pass, leave the commit marked `WIP:`.

## Red Flags

- Running any check before the task changes are in a WIP commit, including inserting `git diff --cached --check` between `git add` and `git commit`
- Unstaging unrelated user changes instead of leaving their index state untouched
- Asking for routine confirmation before or after creating the known-task WIP checkpoint
- Asking about unrelated/pre-existing changes before describing them
- Delaying verification for confirmation when known task scope is safe
- Using `git add .` or `git commit -a` when unrelated changes exist
- Removing `WIP:` before fresh verification passes
- Creating follow-up fix commits instead of amending or later squashing them into the WIP
