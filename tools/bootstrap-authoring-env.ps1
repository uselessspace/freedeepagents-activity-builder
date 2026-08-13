[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$WithNode,
    [string]$PythonMirror = $(if ($env:FDA_PYTHON_MIRROR) { $env:FDA_PYTHON_MIRROR } else { "https://registry.npmmirror.com/-/binary/python-build-standalone" }),
    [string]$NodeMirror = $(if ($env:FDA_NODE_MIRROR) { $env:FDA_NODE_MIRROR } else { "https://registry.npmmirror.com/-/binary/node" }),
    [string]$PipIndex = $(if ($env:FDA_PIP_INDEX) { $env:FDA_PIP_INDEX } else { "https://pypi.tuna.tsinghua.edu.cn/simple" }),
    [string]$NpmRegistry = $(if ($env:FDA_NPM_REGISTRY) { $env:FDA_NPM_REGISTRY } else { "https://registry.npmmirror.com" })
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$PythonVersion = "3.12.13"
$PythonRelease = "20260807"
$NodeVersion = "20.20.2"
$env:PIP_INDEX_URL = $PipIndex
$env:npm_config_registry = $NpmRegistry

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Project root does not exist: $ProjectRoot"
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$ToolsDir = Join-Path $ProjectRoot ".fda-tools"
$VenvDir = Join-Path $ProjectRoot ".venv"
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

function Add-GitIgnoreEntry([string]$Entry) {
    $ignoreFile = Join-Path $ProjectRoot ".gitignore"
    $lines = if (Test-Path -LiteralPath $ignoreFile) { @(Get-Content -LiteralPath $ignoreFile) } else { @() }
    if ($lines -notcontains $Entry) {
        Add-Content -LiteralPath $ignoreFile -Value $Entry -Encoding utf8
    }
}

function Get-CheckedDownload(
    [string]$Base,
    [string]$VersionDir,
    [string]$FileName,
    [string]$Destination,
    [string]$TempDir
) {
    Write-Host "Downloading $FileName"
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/$VersionDir/$FileName" -OutFile $Destination
    $sumFile = Join-Path $TempDir "SHA256SUMS"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$Base/$VersionDir/SHASUMS256.txt" -OutFile $sumFile
    } catch {
        Invoke-WebRequest -UseBasicParsing -Uri "$Base/$VersionDir/SHA256SUMS" -OutFile $sumFile
    }
    $pattern = "\s\*?{0}$" -f [regex]::Escape($FileName)
    $line = Get-Content -LiteralPath $sumFile | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if (-not $line) { throw "Checksum entry missing for $FileName" }
    $expected = ($line -split "\s+")[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Checksum mismatch for $FileName" }
}

function Get-PythonMinor([string]$PythonExe) {
    try {
        $versionText = (& $PythonExe --version 2>&1 | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and "$versionText" -match '^Python\s+(\d+\.\d+)(?:\.|$)') {
            return $Matches[1]
        }
    } catch {}
    return $null
}

function Get-NodeMajor([string]$NodeExe) {
    try {
        $versionText = (& $NodeExe --version 2>&1 | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and "$versionText" -match '^v(\d+)\.') {
            return $Matches[1]
        }
    } catch {}
    return $null
}

$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$ProjectPython = $null
if (Test-Path -LiteralPath $VenvDir) {
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        throw "$VenvDir exists but has no Scripts\python.exe; refusing to overwrite it"
    }
    $detected = Get-PythonMinor $VenvPython
    if ($detected -ne "3.12") { throw "Existing .venv uses Python $detected; FDA authoring requires 3.12" }
    $ProjectPython = $VenvPython
    Write-Host "Reusing Python: $ProjectPython"
} else {
    $BasePython = $null
    foreach ($candidate in @("python3.12.exe", "python3.12", "python.exe", "python")) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command -and (Get-PythonMinor $command.Source) -eq "3.12") {
            $BasePython = $command.Source
            break
        }
    }

    $UsePyLauncher = $false
    if (-not $BasePython) {
        $py = Get-Command "py.exe" -ErrorAction SilentlyContinue
        if ($py) {
            try {
                $versionText = (& $py.Source -3.12 --version 2>&1 | Select-Object -First 1)
                if ($LASTEXITCODE -eq 0 -and "$versionText" -match '^Python\s+3\.12(?:\.|$)') {
                    $UsePyLauncher = $true
                    $BasePython = $py.Source
                }
            } catch {}
        }
    }

    if (-not $BasePython) {
        $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        switch ($architecture.ToUpperInvariant()) {
            "AMD64" { $target = "x86_64-pc-windows-msvc" }
            "ARM64" { $target = "aarch64-pc-windows-msvc" }
            default { throw "Unsupported Windows architecture for automatic Python install: $architecture" }
        }
        $PythonHome = Join-Path $ToolsDir "python-$PythonVersion"
        $ManagedPython = Join-Path $PythonHome "python.exe"
        if ((Test-Path -LiteralPath $ManagedPython -PathType Leaf) -and (Get-PythonMinor $ManagedPython) -eq "3.12") {
            $BasePython = $ManagedPython
            Write-Host "Reusing managed Python: $BasePython"
        } elseif (Test-Path -LiteralPath $PythonHome) {
            throw "Incomplete or incompatible managed Python path already exists: $PythonHome"
        } else {
            $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("fda-authoring-" + [guid]::NewGuid())
            $Staging = Join-Path $ToolsDir (".python-staging-" + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $TempDir, $Staging | Out-Null
            try {
                $archive = "cpython-$PythonVersion+$PythonRelease-$target-install_only_stripped.tar.gz"
                $archivePath = Join-Path $TempDir $archive
                Get-CheckedDownload $PythonMirror $PythonRelease $archive $archivePath $TempDir
                & tar.exe -xzf $archivePath -C $Staging --strip-components=1
                if ($LASTEXITCODE -ne 0) { throw "Unable to extract Python archive" }
                $BasePython = Join-Path $Staging "python.exe"
                if ((Get-PythonMinor $BasePython) -ne "3.12") { throw "Downloaded Python failed its version check" }
                Move-Item -LiteralPath $Staging -Destination $PythonHome
                $BasePython = Join-Path $PythonHome "python.exe"
                Write-Host "Installed project-local Python: $BasePython"
            } finally {
                Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($UsePyLauncher) { & $BasePython -3.12 -m venv $VenvDir } else { & $BasePython -m venv $VenvDir }
    if ($LASTEXITCODE -ne 0) { throw "Unable to create $VenvDir" }
    $ProjectPython = $VenvPython
    Write-Host "Created project environment: $VenvDir"
}

@"
[global]
index-url = $PipIndex
timeout = 60
"@ | Set-Content -LiteralPath (Join-Path $VenvDir "pip.ini") -Encoding utf8

$LocalNodeBin = $null
if ($WithNode) {
    $node = Get-Command "node.exe" -ErrorAction SilentlyContinue
    $npm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    $nodeMajor = if ($node) { Get-NodeMajor $node.Source } else { $null }
    $npmMajor = if ($npm) { ((& $npm.Source --version 2>$null) -split "\.")[0] } else { $null }
    if (($nodeMajor -in @("20", "22")) -and $npmMajor -eq "10") {
        $NodeExe = $node.Source
        $NpmExe = $npm.Source
        Write-Host "Reusing Node: $($node.Source) ($(& $node.Source --version)), npm $(& $npm.Source --version)"
    } else {
        $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        switch ($architecture.ToUpperInvariant()) {
            "AMD64" { $target = "win-x64" }
            "ARM64" { $target = "win-arm64" }
            default { throw "Unsupported Windows architecture for automatic Node install: $architecture" }
        }
        $NodeHome = Join-Path $ToolsDir "node-v$NodeVersion"
        $LocalNodeBin = $NodeHome
        $managedNode = Join-Path $NodeHome "node.exe"
        if (Test-Path -LiteralPath $managedNode -PathType Leaf) {
            $NodeAction = "Reusing managed Node"
        } else {
            if (Test-Path -LiteralPath $NodeHome) { throw "Incomplete managed Node path already exists: $NodeHome" }
            $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("fda-authoring-" + [guid]::NewGuid())
            $Staging = Join-Path $ToolsDir (".node-staging-" + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $TempDir, $Staging | Out-Null
            try {
                $archive = "node-v$NodeVersion-$target.zip"
                $archivePath = Join-Path $TempDir $archive
                Get-CheckedDownload $NodeMirror "v$NodeVersion" $archive $archivePath $TempDir
                Expand-Archive -LiteralPath $archivePath -DestinationPath $Staging
                $extracted = Join-Path $Staging "node-v$NodeVersion-$target"
                if (-not (Test-Path -LiteralPath (Join-Path $extracted "node.exe") -PathType Leaf)) {
                    throw "Downloaded Node archive has an unexpected layout"
                }
                Move-Item -LiteralPath $extracted -Destination $NodeHome
                $NodeAction = "Installed project-local Node"
            } finally {
                Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        $managedNpm = Join-Path $NodeHome "npm.cmd"
        $nodeMajor = Get-NodeMajor $managedNode
        $npmMajor = ((& $managedNpm --version) -split "\.")[0]
        if ($nodeMajor -ne "20" -or $npmMajor -ne "10") { throw "Managed Node/npm failed its version check" }
        Write-Host "${NodeAction}: $managedNode ($(& $managedNode --version))"
        $NodeExe = $managedNode
        $NpmExe = $managedNpm
    }
}

Add-GitIgnoreEntry ".venv/"
Add-GitIgnoreEntry ".fda-tools/"

$EnvFile = Join-Path $ToolsDir "authoring-env.ps1"
@'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:VIRTUAL_ENV = Join-Path $projectRoot ".venv"
$env:Path = (Join-Path $env:VIRTUAL_ENV "Scripts") + ";" + $env:Path
$env:PIP_INDEX_URL = if ($env:FDA_PIP_INDEX) { $env:FDA_PIP_INDEX } else { "https://pypi.tuna.tsinghua.edu.cn/simple" }
$env:npm_config_registry = if ($env:FDA_NPM_REGISTRY) { $env:FDA_NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$managedNode = Join-Path $projectRoot ".fda-tools\node-v20.20.2"
if (Test-Path -LiteralPath $managedNode -PathType Container) {
    $env:Path = $managedNode + ";" + $env:Path
}
'@ | Set-Content -LiteralPath $EnvFile -Encoding utf8

Write-Host ""
Write-Host "Authoring environment ready."
$ProjectPythonVersion = (& $ProjectPython --version 2>&1 | Select-Object -First 1)
Write-Host "Python: $ProjectPython ($ProjectPythonVersion)"
if ($WithNode) { Write-Host "Node: $NodeExe ($(& $NodeExe --version)); npm $(& $NpmExe --version)" }
Write-Host "Load it in a new PowerShell session with: . `"$EnvFile`""
