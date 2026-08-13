# PrintFlow — Batch Print Queue Manager

> Built for **ESKAY PRINTERS** (Cyber Café) · Owner: Zenus · v1.1
> Platform: **Windows Desktop (Flutter)**

PrintFlow is a desktop tool that takes a batch of 100+ PDFs, arranges them in
the exact print sequence, then prints them **strictly one at a time** — only
sending file *N+1* to the printer after file *N* has *actually, physically*
finished printing (not just "command sent"). No more mixed pages at the output
tray, no skipped/duplicated files, and a complete audit trail for billing.

This repository implements **Phase 1** of the PRD (Modules 1–6 + Module 10),
plus the supporting Phase 3 dashboard and history views.

---

## ✨ Features (Phase 1)

| Module | What it does |
|---|---|
| **1 — File Intake** | Drag-and-drop / browse / import-folder; PDF-only; pre-flight flags corrupted & password-protected PDFs *before* Start |
| **2 — Sequence Builder** | Drag-handle reorder + typed sequence numbers, sort helpers, optional per-file label, append files mid-run |
| **3 — Print Configuration** | Printer selector (exact SumatraPDF spelling), batch defaults (copies, color, duplex), per-file page-exclusion thumbnail grid |
| **4 — Print Execution Engine** | Fires each job via SumatraPDF `-print-to -silent`, captures Layer 1 exit code + spooler Job ID |
| **5 — Job Status Monitor** | Polls the Windows spooler every ~1s for that job's status; declares Completed only on `Printed` + `PagesPrinted == TotalPages`; stuck-job + process-watchdog timeouts |
| **6 — Queue Orchestrator** | Global lock — exactly one job Printing at a time; on Failed the whole queue pauses and surfaces Retry / Skip / Cancel |
| **10 — Crash Recovery** | Every job state persisted to SQLite; on reopen an interrupted batch offers "Resume from job #X" |

Bonus screens included: **Live Dashboard** (current job, page X of Y, overall
progress, ETA controls) and **History** (per-batch logs + CSV export for
GST-invoice cross-checking) and a **Settings** screen.

---

## 🔨 The Golden Rule (PRD §7)

> File 2 is **never** sent while file 1 is still printing. Not "probably done" —
> actually, physically done.

Two-layer completion verification:

1. **Layer 1 — command accepted?** SumatraPDF's process exit code (0 = accepted,
   non-zero = rejected outright).
2. **Layer 2 — printer finished?** Poll the specific job's spooler status every
   ~1s. A job is `Completed` only when the spooler reports `Printed` with
   `PagesPrinted == TotalPages`, or the job has cleanly left the queue
   (combined with Layer 1 to avoid trusting a disappearance that was actually
   an auto-deleted error).

Only then does the queue unlock and hand off the next file.

---

## 🏗 Tech Stack

| Layer | Choice |
|---|---|
| UI | Flutter Desktop (Windows) |
| Print execution | [SumatraPDF](https://www.sumatrapdfreader.org/) (portable, bundled) via `Process.run` |
| Spooler polling | PowerShell `Get-PrintJob` (MVP; swappable to `win32` FFI EnumJobs later) |
| PDF metadata + thumbnails | [`pdfrx`](https://pub.dev/packages/pdfrx) |
| Local persistence | `sqflite` + `sqflite_common_ffi` (SQLite) |
| State | `flutter_riverpod` |

---

## 🚀 Building with GitHub Actions

The included workflow (`.github/workflows/build-windows.yml`) builds the
Windows `.exe` on a `windows-latest` runner, bundles SumatraPDF.exe, and
publishes a **portable zip** as an artifact.

1. Push this repository to GitHub.
2. The `Build Windows` workflow runs automatically on every push to `main`
   (and via the **Actions → Run workflow** button for manual dispatch).
3. Download the **`PrintFlow-windows-portable-zip`** artifact from the run's
   summary page, unzip, and run `printflow.exe`. SumatraPDF.exe is included
   next to it.

### Running locally

```bash
flutter config --enable-windows-desktop
flutter create . --platforms=windows --org com.eskayprinters --project-name printflow
flutter pub get
flutter run -d windows
```

For printing to actually work, place `SumatraPDF.exe` in `assets/` or next to
the built executable, or use the in-app **Settings → Download** button.

---

## 📁 Project layout

```
lib/
  main.dart                       App shell + NavigationRail
  models/                         batch, print_job, printer_profile, app_settings
  services/                       database, pdf, printer, print_engine, spooler_monitor
  state/                          batch_provider (the orchestrator), providers
  utils/                          page_range builder, sumatra resolver
  screens/                        home, page_selector_modal, live_dashboard, history, settings
assets/                           SumatraPDF.exe goes here (downloaded at build time)
.github/workflows/build-windows.yml
```

---

## ⚠️ Notes & known limits (v1)

- Windows-only printing/spooler integration; the UI itself is portable for dev.
- Single printer, strictly serial — no parallel/multi-printer support yet.
- PDF only; other formats are a future enhancement.
- Spooler polling uses PowerShell `Get-PrintJob` (PRD §10 MVP approach) —
  swap to the `win32` package's `EnumJobs` later if parsing proves fragile.

---

## 📄 License & attribution

PrintFlow source is © ESKAY PRINTERS. The bundled
[SumatraPDF](https://www.sumatrapdfreader.org/) is GPLv3 and is downloaded
fresh at build time (not committed).
