# issues/

Issues (bugs, tasks, work items) are tracked as plain Markdown files
in three state directories:

    open/       actionable, ready to be picked up
    waiting/    local work submitted; blocked on an upstream response
    done/       merged, verified, closed (with resolution notes)

## Rules

The full scheme — states, naming, Impact/Priority and resolution-note
requirements, format — is specified in
[`../docs/issue-tracking-system.md`](../docs/issue-tracking-system.md).
Read that before creating or moving any issue file.

## Before assuming a bug is new: survey

Search this tree before fixing or filing anything:

    grep -ri "<symptom keyword>" issues/
    ls issues/open issues/waiting issues/done

Include `done/` in the search: a prior item may already contain the
root cause, the diagnostic method, or a warning that the obvious fix
was tried and reverted. Filenames are descriptive; a listing plus a
grep is usually enough.

## Referencing issues

Always reference issues by bare filename (e.g.
`20261126-fix-wizard-testing-race.md`) — never by directory path or
markdown link, because files move between the state directories and
paths break. Locate a referenced file dynamically
(`find issues/ -name "FILENAME"`) instead of assuming its state.
