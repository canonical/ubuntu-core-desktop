# Git commit message conventions

When generating a commit message for this project, always follow the
standard Git 50/72 convention:

- Subject line (first line): soft cap of 50 characters, hard cap of 72.
  Keep it concise and imperative mood ("Fix bug", not "Fixed bug" or
  "Fixes bug"). Do not end it with a period. It is fine to exceed the
  50-char soft cap if that makes the subject meaningfully more
  descriptive/helpful — just stay under the 72-char hard cap.
- Blank line: exactly one empty line between the subject and the body.
- Body: wrap lines at 72 characters max. Explain what changed and why,
  not just how (the diff already shows how).
- When scripting/automating a multi-line commit message, use
  `git commit -F -` with a real heredoc (or an editor), not a `-m`
  string containing literal `\n` — the latter commits literal
  backslash-n characters instead of real line breaks.
- This applies even to a single `-m` body argument: a long paragraph
  passed as one unwrapped `-m "..."` string produces real newlines at
  the message boundary but no wrapping *within* the body, silently
  violating the 72-char body wrap. Always compose the body text with
  line breaks already inserted at <=72 chars (e.g. via a heredoc into
  `git commit -F -`) rather than relying on multiple `-m` flags or a
  single long `-m` string to get correct wrapping.
