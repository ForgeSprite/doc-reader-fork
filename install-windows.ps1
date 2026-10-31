# Doc Reader: one-step installer for Windows 10/11.
#
# Gets everything a fresh PC needs and leaves Doc Reader running:
#   1. uv (builds the Python 3.12 environment) and FFmpeg (audio playback)
#   2. the Doc Reader code (git clone when git is present, otherwise a zip download)
#   3. the Python environment with PyTorch (CUDA build on NVIDIA GPUs, CPU build otherwise)
#   4. the Kokoro voice and Whisper speech models
#   5. Desktop and Start menu shortcuts, start at login, then starts the app
#
# Run it either way:
#   From a downloaded or cloned copy:   double-click install-windows.cmd
#   On a PC with nothing yet (PowerShell):
#     irm https://raw.githubusercontent.com/AaronTateDev/doc-reader-fork/windows-support/install-windows.ps1 | iex
#
# No administrator rights are needed. Re-running it is safe: it updates the code,
# skips what is already installed, and starts Doc Reader again.
#
# Options (parameters when run as a file, environment variables when piped to iex):
#   -InstallDir   / DOC_READER_INSTALL_DIR     where to put a fresh copy (default %USERPROFILE%\DocReader)
#   -NoStartup    / DOC_READER_NO_STARTUP=1    do not start Doc Reader at login
#   -NoShortcuts  / DOC_READER_NO_SHORTCUTS=1  no Desktop / Start menu shortcuts
#   -NoStart      / DOC_READER_NO_START=1      install only, do not start it now
#   -Cpu          / DOC_READER_TORCH=cpu       force the CPU build even with an NVIDIA GPU
#   DOC_READER_REPO_URL / DOC_READER_BRANCH    install from another fork or branch

[CmdletBinding()]
param(
    [string] $InstallDir = "",
    [switch] $NoStartup,
    [switch] $NoShortcuts,
    [switch] $NoStart,
    [switch] $Cpu
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is many times slower with the progress bar

function Say([string] $Message) { Write-Host "[doc-reader setup] $Message" -ForegroundColor Cyan }
function Warn([string] $Message) { Write-Host "[doc-reader setup] $Message" -ForegroundColor Yellow }
function Run-Native {
    # git and winget write progress to stderr; Windows PowerShell 5.1 turns that into
    # error records, which "Stop" would treat as fatal. Judge them by exit code instead.
    # A plain function (no param block) so options such as -C or -e reach the tool untouched.
    $Exe = $args[0]; $Rest = @($args | Select-Object -Skip 1)
    $saved = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Exe @Rest 2>&1 | ForEach-Object { "$_" } | Write-Host; return $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
}
function Find([string] $Name) { $c = Get-Command $Name -ErrorAction SilentlyContinue; if ($c) { return $c.Source } return $null }
function Refresh-Path {
    # Pick up tools winget just installed without opening a new terminal.
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $links = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    $env:Path = (@($env:Path, $user, $machine, $links) -join ";")
}

$RepoUrl = if ($env:DOC_READER_REPO_URL) { $env:DOC_READER_REPO_URL } else { "https://github.com/AaronTateDev/doc-reader-fork.git" }
$Branch = if ($env:DOC_READER_BRANCH) { $env:DOC_READER_BRANCH } else { "windows-support" }
if ($env:DOC_READER_NO_STARTUP -eq "1") { $NoStartup = $true }
if ($env:DOC_READER_NO_SHORTCUTS -eq "1") { $NoShortcuts = $true }
if ($env:DOC_READER_NO_START -eq "1") { $NoStart = $true }
if ($Cpu) { $env:DOC_READER_TORCH = "cpu" }

if ([Environment]::OSVersion.Platform -ne "Win32NT") { throw "This installer is for Windows. On a Mac use: npm install -g read-docs; read-docs install" }

# ------------------------------------------------------------------ where the app lives
# Run from inside a copy of the repo: install that copy. Piped from the web: fetch a fresh copy.
$ScriptPath = $MyInvocation.MyCommand.Path
$Here = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { $null }
$InPlace = $Here -and (Test-Path (Join-Path $Here "doc_reader\windows_app.py"))
if ($InPlace) {
    $AppDir = $Here
} else {
    if (-not $InstallDir) { $InstallDir = if ($env:DOC_READER_INSTALL_DIR) { $env:DOC_READER_INSTALL_DIR } else { Join-Path $env:USERPROFILE "DocReader" } }
    $AppDir = $InstallDir
}

# Everything the installer downloads for its own use stays inside the app folder. That keeps
# the install self-contained, and it matters when an AI assistant runs this from a packaged
# (MSIX/Store) app: Windows silently redirects such an app's writes to %LOCALAPPDATA% into a
# private copy that the user's own shortcuts can never see, which leaves a venv pointing at a
# Python that "does not exist". Folders under the app directory are never redirected.
$Runtime = Join-Path $AppDir ".runtime"
$env:UV_PYTHON_INSTALL_DIR = Join-Path $Runtime "python"
$env:UV_CACHE_DIR = Join-Path $Runtime "uv-cache"
$env:UV_LINK_MODE = "copy"

Say "Installing Doc Reader into $AppDir"

# ------------------------------------------------------------------ 1. code
if (-not $InPlace) {
    $git = Find "git"
    if (Test-Path (Join-Path $AppDir ".git")) {
        Say "Updating the existing copy ..."
        if ($git) { if ((Run-Native $git -C $AppDir pull --ff-only origin $Branch) -ne 0) { Warn "Could not update (local changes?); keeping the current code." } }
    } elseif (Test-Path (Join-Path $AppDir "doc_reader\windows_app.py")) {
        Say "Found an existing copy (no git); downloading the latest code over it ..."
        $git = $null
        $refresh = $true
    }
    if (-not (Test-Path (Join-Path $AppDir "doc_reader\windows_app.py")) -or $refresh) {
        if ($git -and -not $refresh) {
            Say "Downloading the code with git ..."
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $AppDir) | Out-Null
            if ((Test-Path $AppDir) -and (Get-ChildItem $AppDir -Force | Where-Object Name -ne ".runtime")) { throw "$AppDir already exists and is not a Doc Reader folder. Pick another place with DOC_READER_INSTALL_DIR." }
            # A previous partial run may have left .runtime behind: park it outside while cloning.
            $runtimeKept = $null
            if (Test-Path $Runtime) { $runtimeKept = Join-Path ([IO.Path]::GetTempPath()) ("doc-reader-runtime-" + [guid]::NewGuid().ToString("N")); Move-Item $Runtime $runtimeKept }
            if (Test-Path $AppDir) { Remove-Item $AppDir -Force -Recurse }
            if ((Run-Native $git clone --branch $Branch --depth 1 $RepoUrl $AppDir) -ne 0) { throw "git clone of $RepoUrl failed." }
            if ($runtimeKept) { Move-Item $runtimeKept $Runtime }
        } else {
            Say "Downloading the code as a zip ..."
            $zipUrl = ($RepoUrl -replace "\.git$", "") + "/archive/refs/heads/$Branch.zip"
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("doc-reader-" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Force -Path $tmp | Out-Null
            Invoke-WebRequest $zipUrl -OutFile (Join-Path $tmp "code.zip") -UseBasicParsing
            Expand-Archive (Join-Path $tmp "code.zip") -DestinationPath $tmp -Force
            $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
            New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
            Copy-Item (Join-Path $inner.FullName "*") $AppDir -Recurse -Force
            Remove-Item $tmp -Recurse -Force
        }
    }
}

# ------------------------------------------------------------------ 2. tools
$winget = Find "winget"
$uv = Find "uv"
if (-not $uv) {
    $localUv = Join-Path $Runtime "bin\uv.exe"
    if (Test-Path $localUv) {
        $uv = $localUv
    } else {
        Say "Getting uv (Python environment manager) ..."
        New-Item -ItemType Directory -Force -Path (Join-Path $Runtime "bin") | Out-Null
        $env:UV_INSTALL_DIR = Join-Path $Runtime "bin"
        $env:UV_NO_MODIFY_PATH = "1"
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
        $uv = $localUv
        if (-not (Test-Path $uv)) { throw "uv could not be installed. Install it by hand (winget install astral-sh.uv) and run this again." }
    }
}
$env:Path = (Split-Path -Parent $uv) + ";" + $env:Path
Say "uv: $uv"

if (-not (Find "ffplay")) {
    if ($winget) {
        Say "Installing FFmpeg (audio playback) with winget ..."
        [void](Run-Native $winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements --silent)
        Refresh-Path
    }
    if (-not (Find "ffplay")) {
        Warn "FFmpeg is not on PATH yet. Doc Reader looks in the usual winget folders, so this is often fine; 'doctor' below will say for sure. If audio does not play, install it with: winget install Gyan.FFmpeg"
    }
}

# ------------------------------------------------------------------ 3. Python environment
$Launcher = Join-Path $AppDir "run-doc-reader.ps1"
Say "Building the Python environment (the first time downloads PyTorch, about 2.5 GB) ..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $Launcher --prepare-only
if ($LASTEXITCODE -ne 0) { throw "Building the Python environment failed. Scroll up for the error." }
$Python = Join-Path $AppDir ".venv\Scripts\python.exe"

# ------------------------------------------------------------------ 4. models
Say "Downloading the speech models (Kokoro voice and Whisper, about 1 GB) ..."
Push-Location $AppDir
try {
    & $Python -m doc_reader.windows_app prefetch-models
    if ($LASTEXITCODE -ne 0) { Warn "A model download failed; Doc Reader will retry on first use. Check the internet connection." }

    # ------------------------------------------------------------------ 5. shortcuts, startup, start
    if (-not $NoShortcuts) { & $Python -m doc_reader.windows_app install-shortcuts }
    if (-not $NoStartup) { & $Python -m doc_reader.windows_app enable-startup }
    Say "Checking the install ..."
    & $Python -m doc_reader.windows_app doctor
    if (-not $NoStart) {
        & $Python -m doc_reader.windows_app start
    }
} finally {
    Pop-Location
}

Write-Host ""
Say "Done. Doc Reader is installed in $AppDir"
Write-Host "  Open it:            the 'Doc Reader' shortcut, or http://127.0.0.1:8766"
Write-Host "  Read selected text: select text anywhere and press Ctrl+Alt+R"
Write-Host "  Dictate:            hold Right Ctrl, speak, release (text is typed where your cursor is)"
Write-Host "  Change hotkeys:     Details panel in the web app, or the tray icon menu"
Write-Host "  Manage it:          $AppDir\run-doc-reader.cmd start | stop | status | doctor"
