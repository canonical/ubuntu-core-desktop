# Sending a fix from a project fork upstream (canonical/snapd)

The project's snapd fork (`ubuntu-core-desktop-snapd`) has both
`origin` (canonical/ubuntu-core-desktop-snapd, this project's working
fork) and `upstream` (canonical/snapd, the real upstream) as remotes.
To send a local fix upstream:

1. `gh auth login --web` (no persisted credentials by default; do this
   once per session/environment as needed).
2. `git fetch upstream master` to get the latest.
3. Create a new branch off `upstream/master` (NOT off the project's own
   `26`/other local branches — those have diverged and carry unrelated
   local-only commits) and `git cherry-pick` just the specific fix
   commit(s) onto it.
4. The authenticated GitHub user typically has no push access to
   canonical/snapd directly and no pre-existing fork — use
   `gh repo fork canonical/snapd --remote=false` to create one, then
   `git remote add myfork https://github.com/<user>/snapd.git` and push
   the branch there.
5. `gh pr create --repo canonical/snapd --base master --head
   <user>:<branch> --title ... --body-file ...` opens the PR against
   the real upstream from the personal fork.

Gotcha: switching branches with `git checkout <other-branch>` /
`git checkout -b <new> upstream/master` and back can leave a surprising
number of tracked files showing as locally "modified" (real content
differences, not a stat-cache artifact) if the branches have diverged a
lot. If you don't want to keep those changes, `git reset --hard HEAD`
cleanly restores the current branch's tracked files — check
`git status`/`git stash` first if there's any chance of losing real
uncommitted work. Also `rm` any build artifacts (binaries,
`.deb`/`.buildinfo`/`.changes`) a `go build`/packaging step drops into
the repo root as untracked files, before committing/PR'ing.
