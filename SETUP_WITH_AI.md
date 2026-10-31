# Setting up Doc Reader on Windows with an AI assistant

This file is written for an AI coding assistant (Claude Code, Codex, Cursor and
similar) that a person has asked to install Doc Reader on their Windows PC. A
human can follow it too.

## What the person will have at the end

- **Read aloud**: select text in any app, press the read hotkey (default
  Ctrl+Alt+R), and a local neural voice (Kokoro) reads it.
- **Dictation**: hold the dictation key (default Right Ctrl), speak, release,
  and the words are typed where the cursor is, transcribed locally by Whisper.
- **Web app** at http://127.0.0.1:8766 for pasting or opening documents (PDF,
  DOCX, text), choosing a voice and speed, and changing hotkeys.
- A tray icon, a "Doc Reader" shortcut on the Desktop and in the Start menu,
  and automatic start at login. Everything runs on the PC; nothing is sent to a
  cloud service.

## Requirements

- Windows 10 or 11, 64-bit, with internet for the first install.
- About 6 GB of free disk space (PyTorch is about 2.5 GB, the speech models
  about 1 GB).
- An NVIDIA GPU is optional. With one, speech and dictation are near instant;
  without one, the CPU build is used and is slower but works.
- No administrator rights. Do not run the installer elevated: the shortcuts and
  login startup must belong to the person's own account.

## Install

From PowerShell (not elevated):

```powershell
irm https://raw.githubusercontent.com/AaronTateDev/doc-reader-fork/windows-support/install-windows.ps1 | iex
```

Or, from a downloaded or cloned copy of the repository, double-click
`install-windows.cmd`.

The installer gets uv and FFmpeg, downloads the code to `%USERPROFILE%\DocReader`,
builds the Python 3.12 environment (CUDA PyTorch when an NVIDIA GPU is present),
downloads the Kokoro and Whisper models, adds the shortcuts, enables start at
login, runs `doctor`, and starts the app. It takes 5 to 20 minutes depending on
the connection. Re-running it is safe and also updates an existing install.

Options, as environment variables when piped to `iex` (or parameters when run as
a file): `DOC_READER_INSTALL_DIR`, `DOC_READER_NO_STARTUP=1` (`-NoStartup`),
`DOC_READER_NO_SHORTCUTS=1` (`-NoShortcuts`), `DOC_READER_NO_START=1`
(`-NoStart`), `DOC_READER_TORCH=cpu` (`-Cpu`).

## Verify

```powershell
& "$env:USERPROFILE\DocReader\run-doc-reader.cmd" status
& "$env:USERPROFILE\DocReader\run-doc-reader.cmd" doctor
```

`status` should show the web app, the speech service (with Kokoro and Whisper
loaded) and the tray helper all running. Then open http://127.0.0.1:8766, paste
a sentence, and press Read text: it should speak.

Leave the hotkeys for the person to try. An assistant should not inject
keystrokes into the person's session to test them.

## Things an assistant must get right

- **Packaged (MSIX / Microsoft Store) apps redirect AppData.** If you run inside
  a packaged desktop app (the Claude desktop app is one), files you write under
  `%APPDATA%` or `%LOCALAPPDATA%` go to a private copy the person's own
  processes cannot see. A Python installed there makes the shortcut fail later
  with "No Python at ...". The installer avoids this by keeping uv, Python and
  caches in `<install dir>\.runtime`. Do not "fix" things by installing Python
  or tools user-scope under AppData yourself.
- **Python 3.10 to 3.12 only.** PyTorch has no wheels for newer versions. The
  installer creates 3.12 with uv regardless of what is installed system-wide.
- **Do not run elevated**, and do not change system or security settings.
- **Microphone access**: if dictation records silence, Windows Settings >
  Privacy & security > Microphone must allow desktop apps. Only the person
  should change this.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| The page says "Hotkey helper off", hotkeys do nothing | `run-doc-reader.cmd start` (starts whatever is missing), or the "Restart the hotkey helper" button in Details |
| No sound when reading | `doctor` must show ffplay. Install with `winget install Gyan.FFmpeg`, then `run-doc-reader.cmd restart` |
| Speech service shows an error loading Kokoro or Whisper | `.venv\Scripts\python.exe -m doc_reader.windows_app prefetch-models` in the install folder (needs internet), then restart |
| Dictation types nothing | Check the microphone privacy setting; the helper follows the Windows default input device. The log is `%USERPROFILE%\.doc-reader-managed\logs\helper.log` |
| Very slow on a PC with an NVIDIA GPU | `doctor` should say CUDA. If it says CPU, update the NVIDIA driver and re-run the installer |
| Shortcut fails with "No Python at ..." | The environment was built from a redirected location. Delete `.venv` and `.runtime` in the install folder and re-run the installer from a normal PowerShell window |

Logs live in `%USERPROFILE%\.doc-reader-managed\logs`. Uninstall:
`run-doc-reader.cmd stop`, `run-doc-reader.cmd disable-startup`,
`run-doc-reader.cmd remove-shortcuts`, then delete the install folder and
`%USERPROFILE%\.doc-reader-managed`.
