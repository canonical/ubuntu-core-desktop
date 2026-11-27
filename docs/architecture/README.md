# Architecture diagram

`core-desktop-architecture.svg` (source:
`core-desktop-architecture.excalidraw`) is the target architecture
for the Ubuntu Core Desktop 28.04 MVP. It is **not the current
system**: interfaces drawn in red or marked "(new)" do not exist
yet, and the models shown (`ubuntu-core-desktop-28-amd64`,
`ubuntu-core-desktop-kde-28-amd64`) are the planned 28 models —
today's models are in ../models.md.

The canvas has two frames:

- **Composition matrix** — what each Platform (model) and Persona
  runs: five layers (Foundation, System services, Greeter session,
  User session, Apps), where each layer lists the interfaces it
  exposes (grouped by consumer) and consumes (grouped by provider).
- **Interface map** — who exposes each interface (slot) and who
  plugs it.

Legend: white = in the Platform model; blue dashed = persona snap,
never in a model; red = needs a new upstream snapd interface;
`*` = provider or consumer inferred, not stated in the target
architecture spec. Notes in the diagram that cite
"target-architecture.md" refer to the 28.04 target-architecture
specification, which is not part of this repo.

## Editing and re-exporting

1. Open `core-desktop-architecture.excalidraw` at
   https://app.excalidraw.com (drag the file onto the page).
2. Edit, then File → Export → SVG with background **on**, dark mode
   **off**, embed scene **off**, scale 1x. Save it as
   `core-desktop-architecture.svg`.
3. Commit both files together.

The SVG embeds the hand-drawn fonts, so it renders identically
everywhere (GitHub included) with no font installs. Keep the render
as SVG rather than PNG: it is a text file (~380 KB vs a 6.4 MB
PNG), so git stores updates as small deltas instead of a new full
binary blob per export.
