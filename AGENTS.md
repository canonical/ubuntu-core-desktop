Before doing ANY other work, read docs/README.md (the documentation
index) and follow its reading rules: read only the documents your task
needs, and keep the docs current when you find them inaccurate or when
you have findings useful to future agents. Before assuming a bug is
new, survey issues/ (grep, including done/) — see
issues/README.md.

# Known tool trap: QEMU screendump to PPM is corrupt

`screendump` to PPM produces a diagonally sheared image with scanline
noise — it looks like a guest display/rendering bug, but it is a
14-year-old upstream QEMU stride bug, still unpatched in Ubuntu's qemu
10.2.1. Do not debug "display corruption" that a PPM screendump showed
you. Always take PNG screendumps instead: `screendump out.png -f png`.
(Detail in docs/diagnostics-methodology.md.)
