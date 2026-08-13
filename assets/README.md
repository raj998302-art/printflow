# PrintFlow Assets

This folder holds runtime assets for the PrintFlow Windows desktop app.

## SumatraPDF

PrintFlow uses [SumatraPDF](https://www.sumatrapdfreader.org/) (portable, GPLv3) as the
silent print engine. The build pipeline (`.github/workflows/build-windows.yml`)
downloads `SumatraPDF.exe` into this folder automatically during the GitHub Actions
build, so it gets bundled next to the app executable.

If you are building locally, download the portable zip from
<https://www.sumatrapdfreader.org/download-free-pdf-viewer>, extract it, and place
`SumatraPDF.exe` in this folder — or let PrintFlow download it on first run from the
in-app Settings screen.

`SumatraPDF.exe` is intentionally git-ignored (see `.gitignore`) because of its license
and size; it is always fetched fresh at build time.
