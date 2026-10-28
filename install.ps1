<#
.SYNOPSIS
    Install kubeadd on Windows.

.DESCRIPTION
    irm https://raw.githubusercontent.com/ozkanpoyrazoglu/kubeadd/main/install.ps1 | iex

    Installs into %LOCALAPPDATA%\Programs\kubeadd and adds that folder to the user PATH
    (no administrator rights needed). Set $env:KUBEADD_VERSION = "v2.0.0" first to install
    a tag, branch or commit instead of main.

    Uninstall:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ozkanpoyrazoglu/kubeadd/main/install.ps1))) -Uninstall
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$Repo = 'ozkanpoyrazoglu/kubeadd'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\kubeadd'
$Files = 'kubeadd.py', 'kubeadd.cmd'

function Get-UserPathEntries {
    $value = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $value) { return @() }
    return @($value -split ';' | Where-Object { $_ })
}

function Test-SameDir([string]$a, [string]$b) {
    return $a.TrimEnd('\') -ieq $b.TrimEnd('\')
}

function Find-Python {
    # Emits the command (e.g. 'py', '-3'); call as @(Find-Python) so one word stays an array.
    # The Microsoft Store "python" stub exists but fails, so actually run a version check.
    foreach ($candidate in @(@('py', '-3'), @('python'))) {
        if (-not (Get-Command $candidate[0] -ErrorAction SilentlyContinue)) { continue }
        $arguments = @($candidate | Select-Object -Skip 1) + @('-c', 'import sys; sys.exit(sys.version_info < (3, 8))')
        try {
            & $candidate[0] @arguments 2>$null
            if ($LASTEXITCODE -eq 0) { $candidate; return }
        } catch { }
    }
}

if ($Uninstall) {
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-Host "Removed $InstallDir"
    } else {
        Write-Host "kubeadd is not installed in $InstallDir"
    }
    $entries = Get-UserPathEntries
    $kept = @($entries | Where-Object { -not (Test-SameDir $_ $InstallDir) })
    if ($kept.Count -ne $entries.Count) {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
        Write-Host "Removed $InstallDir from the user PATH"
    }
    return
}

# Requirements
$python = @(Find-Python)
if ($python.Count -eq 0) {
    throw 'Python 3.8 or newer is required. Install it with: winget install Python.Python.3.12'
}
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Warning 'kubectl was not found in PATH; kubeadd needs it. Install it with: winget install Kubernetes.kubectl'
}

# Fetch the files: from this checkout when run as a file inside the repo, otherwise from GitHub.
$staging = Join-Path ([IO.Path]::GetTempPath()) ("kubeadd-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    if (-not $env:KUBEADD_VERSION -and $PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'kubeadd.py'))) {
        Write-Host "Installing from $PSScriptRoot"
        foreach ($file in $Files) { Copy-Item (Join-Path $PSScriptRoot $file) $staging }
    } else {
        $version = if ($env:KUBEADD_VERSION) { $env:KUBEADD_VERSION } else { 'main' }
        Write-Host "Downloading kubeadd ($version)"
        # Windows PowerShell 5.1 does not enable TLS 1.2 by default.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        foreach ($file in $Files) {
            $url = "https://raw.githubusercontent.com/$Repo/$version/$file"
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile (Join-Path $staging $file)
            } catch {
                throw "Download of $url failed; check that '$version' exists in https://github.com/$Repo"
            }
        }
    }

    # GitHub serves the launcher with LF line endings; cmd.exe expects CRLF.
    $launcher = Join-Path $staging 'kubeadd.cmd'
    $lines = [IO.File]::ReadAllText($launcher) -split "\r?\n"
    [IO.File]::WriteAllText($launcher, ($lines -join "`r`n"))

    $arguments = @($python | Select-Object -Skip 1) + @((Join-Path $staging 'kubeadd.py'), '--version')
    $installedVersion = & $python[0] @arguments
    if ($LASTEXITCODE -ne 0) { throw 'The downloaded file is not a working kubeadd' }

    # Install
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($file in $Files) { Copy-Item -Force (Join-Path $staging $file) $InstallDir }
    Write-Host "Installed $installedVersion to $InstallDir"
} finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}

# PATH: persist for new terminals and update the current session.
$entries = Get-UserPathEntries
if (-not ($entries | Where-Object { Test-SameDir $_ $InstallDir })) {
    [Environment]::SetEnvironmentVariable('Path', ((@($entries) + $InstallDir) -join ';'), 'User')
    Write-Host "Added $InstallDir to your user PATH"
}
if (-not (($env:Path -split ';') | Where-Object { $_ -and (Test-SameDir $_ $InstallDir) })) {
    $env:Path = "$env:Path;$InstallDir"
}
Write-Host "Run 'kubeadd -h' to get started (open a new terminal if the command is not found)"
