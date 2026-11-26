# Issue Tracking System (issues/)

Issues (work items, bugs, and tasks) are tracked as plain Markdown
files inside the `issues/` directory. Directories act as a mutually
exclusive state machine—each file exists in exactly one state
subdirectory at any given time.

## Directory Layout and States

    issues/
    ├── open/       # Actionable items ready to be picked up and worked on
    ├── waiting/    # Local work complete; blocked on upstream PRs,
    │               # reviews, or external action
    └── done/       # Merged, verified, and completely closed

- `open/`: Unstarted or active tasks requiring local investigation, code
  changes, or follow-up on upstream review feedback.
- `waiting/`: Hands off for routine execution. Local implementation is
  finished and submitted, and we are waiting on external maintainers
  (e.g., upstream GitHub PRs, Launchpad bugs, Snap Store requests, or
  external dependencies).
- `done/`: Terminal state. All code is merged (locally and/or upstream)
  and no further action is needed.

## Naming Convention

Create new issues in `issues/open/` using the format:

    YYYYMMDD-short-descriptive-slug.md

Example: `20261126-fix-wizard-testing-race.md`

Never rename a file once it has been created and committed. Its filename
is its permanent, immutable identifier across all states.

## Format and Style

- Issues are Markdown files only (`.md`).
- Prose is hard-wrapped at 80 columns so the files read cleanly in a
  plain 80-column terminal (e.g. vim with no line-wrap settings).
  Headings, list markers, and indentation follow standard Markdown:
  list continuation lines align with the list item's content.
- The title line stays under 80 characters where possible (rewrite a
  long title into a shorter descriptive one). If no faithful shorter
  version exists, a longer title line is allowed — this should be rare.
- Indented (4-space) code blocks, quoted journal output, and command
  transcripts are never reflowed: line width rules apply to prose only.
- Write issues generically so that other people and agents on other
  Ubuntu machines can reproduce them: no local usernames, hostnames,
  IP addresses, MAC addresses, or machine-specific setup details.
  Report usernames as `your_username` or `<user>`, addresses as
  placeholders, and describe the machine only where genuinely
  relevant (e.g. "a TPM-less VM").
- Keep the wording plain; these files are read by other people and by
  agents, so write conclusions and evidence so they stand on their own.

## Before Creating an Issue: Survey Existing Ones

Before fixing a newly discovered bug or filing a new issue, check
whether the project already knows about it:

- Search all of `issues/` for symptom keywords, component names, and
  error strings (`grep -ri "<keyword>" issues/`). This includes
  `done/` — prior root-cause work lives there. For a quick overview,
  list the directories (`ls issues/open issues/waiting issues/done`);
  filenames are descriptive, so a listing plus a grep is usually
  enough to find what exists.
- Check `open/` first (someone may already track it — work within
  that file rather than opening a duplicate), then `waiting/` (the
  fix may exist but be blocked upstream, which changes your
  approach), then `done/`.
- Read the resolutions of any `done/` hits. Done items contain
  "do not re-derive" records, reusable diagnostic methods, and
  warnings about fixes that were later reverted or superseded. Your
  "new" bug may be a regression of such a fix — or a repeat of a
  known-dead approach.
- If an open issue covers your finding, append your findings to that
  file instead of creating a new one.
- If you create a new issue, reference related issues by bare
  filename (including done ones) so the next reader gets the full
  context.

## New Issue Requirements

Every issue (open, waiting, or done) includes an "Impact / Priority"
section immediately after the title line, before any Context or
root-cause detail. It must state:

- A priority level (e.g. Low/Medium/High) based on real-world end-user
  impact, not on implementation difficulty or how technically
  interesting the bug is.
- What a real user would actually observe or lose, in plain terms, not
  just the raw technical symptom (e.g. "the window takes 60-90s to
  appear" rather than "AppArmor denies dbus_method_call X").
- If the on-the-ground impact isn't yet known, say so explicitly and
  note what investigation would pin it down, rather than guessing.
- Wherever practical, ground this section in a real, reproduced
  end-to-end test (actually using the feature) rather than only
  log/journal reading or testing from a synthetic caller that doesn't
  represent a real user — this project has repeatedly found log-only or
  synthetic-caller testing to produce misleading conclusions (e.g.
  "broken" when it's actually just slow).

For issues in `done/`, this section records the impact the issue had
when it was open, alongside the resolution note; never invent a
priority retroactively — when unknown, say so.

## Referencing Issues (Strict Path Rule)

Because files move between `open/`, `waiting/`, and `done/`, file paths
are ephemeral and will break.

1. NEVER reference an issue using a directory path or Markdown link.
   - Bad: `issues/open/20261126-fix-wizard-testing-race.md`
   - Bad: `[wizard race](../open/20261126-fix-wizard-testing-race.md)`
2. ALWAYS reference issues strictly by their exact bare filename in
   inline code (in commits, code comments, PR descriptions, and other
   issues).
   - Good: `20261126-fix-wizard-testing-race.md`
3. Resolving references: When you need to read a referenced issue,
   never assume which subdirectory it is in. Locate it dynamically
   first using globbing (`issues/**/FILENAME`) or
   `find issues/ -name "FILENAME"`.

## State Transitions and Workflow

Always use `git mv` when moving an issue between states so Git
preserves file history cleanly.

### 1. Picking Up Work (open/)
- Read the target file in `issues/open/` and check any referenced
  filenames for historical context.
- Keep brief notes on findings, root cause, and decisions inside the
  issue file as you progress so future agents have full context.

### 2. Moving to waiting/ (open/ -> waiting/)
If completing a task requires an upstream PR, bug report, or external
review before it can be finalized:
1. Prepend (or update) YAML frontmatter at the top of the file with the
   upstream tracker link(s) and date:

       ---
       upstream: https://github.com/org/repo/pull/1234
       waiting_since: YYYY-MM-DD
       ---

2. Summarize what was submitted and what needs to happen once upstream
   responds.
3. Move the file: `git mv issues/open/FILENAME issues/waiting/FILENAME`

Note: If an upstream maintainer requests changes or CI fails on a
`waiting/` issue, move it back to `issues/open/` via `git mv`, record
the feedback in the file, and address it.

### 3. Completing Work (open/ or waiting/ -> done/)
Once the work is fully resolved—either landed locally with no external
blockers, or merged upstream:
1. Append a short resolution note at the bottom of the file (what was
   actually fixed/done, and a commit reference if applicable). Never
   move an issue to done with no resolution note appended.
2. Move the file:
   `git mv issues/CURRENT_STATE/FILENAME issues/done/FILENAME`

## External Trackers (Jira)

Do not create or update Jira tickets for routine commits, minor bug
fixes, or standard `issues/` items unless:
- The issue explicitly instructs you to update a specific Jira issue, or
- A human explicitly asks you to open or sync a Jira ticket.

If an issue is linked to an existing Jira issue, record the Jira key in
the file's frontmatter (`jira: PROJ-123`) and follow any update
instructions noted in that file.
