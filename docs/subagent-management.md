# Sub-agent management

Reusable methodology for dispatching and managing background
sub-agents (e.g. on issues in `issues/open/`), independent of any
specific bug.

## Verification

- Always independently re-check a sub-agent's own "done"/"validated"
  claims before reporting them onward or treating an issue as closed:
  `git show`/`git log` the actual commit, check live state (snap
  connections, systemctl status, journal greps) — don't just trust the
  agent's prose summary. A sub-agent can report success while only
  having checked that a wrapping service/command exited 0, not that
  the specific thing it was asked to fix actually works (e.g. a
  `snap connect` that silently didn't establish the intended
  connection).
- Also watch for low-effort completion artifacts: a commit message
  with literal `\n` instead of real newlines, or an issue file moved
  to `done/` with no resolution notes appended.
- A sub-agent fixing one narrow bug can plausibly "fix" it by disabling
  or working around something else load-bearing that it doesn't have
  full context on (e.g. misdiagnosing a slow-but-working boot-time
  service as "looping and blocking" something, and leaving it disabled
  as a side effect of unrelated troubleshooting). Always check whether
  a sub-agent's session touched/stopped/disabled any unit, service, or
  config outside its assigned scope, not just whether its own target
  bug is fixed.

## Concurrency and resource ownership

- When two sub-agent tasks touch the same shared, exclusive resource
  (e.g. a single test VM/QEMU image), run them sequentially, not in
  parallel, and re-verify the resource's state (still up cleanly,
  correct set of prior fixes still baked in) at the start of each new
  dispatch rather than assuming the previous agent left it as claimed.
- Only one agent should touch a working tree at a time; verify with
  `git status` (clean?) and a build-process check before starting a
  new agent on the same tree.
- If a user message interrupts a sub-agent dispatch, the sub-agent
  session often survives and keeps running invisibly. After any
  interrupted/aborted dispatch, check for survivors before doing
  anything else in that area: `git status`/`git log` in the target
  repo (did the agent commit or leave edits?), running processes for
  builds it may have started. When a sub-agent's work must survive
  interruption, have it commit its source changes BEFORE starting any
  build; builds can be redone by anyone, an uncommitted edit dies with
  the vanished session.

## Tasking

- Give each sub-agent corrected/verified context up front (e.g. "X and
  Y in the issue are already resolved, here's proof; the real remaining
  gap is Z") rather than letting it re-derive/re-litigate
  already-known facts — this makes for a much narrower,
  more reliably-completed task.

## Models

- Sub-agents on this project run on OpenRouter with open-weight
  models. Use **`deepseek-v4.1-flash-1017`** for everything: set it
  explicitly in the dispatch's model field rather than leaving the
  model unset (an unset model inherits the manager's own default,
  which may not be the model you intended). Capability profile and
  model are independent settings; set both deliberately.
- Never trust a model's self-report of its own identity: LLMs
  commonly get "which model am I" wrong, and a sub-agent generally
  cannot verify its own model from its environment (it inherits the
  manager's environment rather than receiving its own copy). The only
  reliable evidence is the platform's own accounting — the sub-agent
  list/status display or API output — not prose or environment
  variables.
