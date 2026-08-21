$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ============================================================
# Competition Environment Setup
#
# Installs:
#   - Chocolatey
#   - Git
#   - kubectl
#   - k9s
#   - k6
#   - Terraform
#   - AWS CLI v2
#   - jq
#   - Visual Studio Code
#   - Python
#   - Docker Desktop
#   - uBlock Origin Lite Chrome extension
#   - w.swanno3o.com Chrome bookmark bar link
#
# Run as Administrator:
#   irm https://setup.swanno3o.com/wsc2026/setup.ps1 | iex
# ============================================================


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Message
    Write-Host "============================================================"
}


function Test-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}


function Download-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue

    if ($curl) {
        Write-Host "Downloading with curl.exe: $Url"

        & $curl.Source `
            --fail `
            --location `
            --retry 3 `
            --retry-delay 2 `
            --connect-timeout 20 `
            --max-time 600 `
            --output $Destination `
            $Url

        if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination)) {
            return
        }

        Write-Warning "curl.exe download failed. Retrying with .NET WebClient."
    }

    $webClient = New-Object System.Net.WebClient
    $webClient.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $webClient.DownloadFile($Url, $Destination)

    if (-not (Test-Path $Destination)) {
        throw "Download failed: $Url"
    }
}


$chromeWasRunning = $false
$chromeExecutable = $null

function Get-ChromeExecutable {
    $candidates = @(
        $script:chromeExecutable
        (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:LOCALAPPDATA "Google\Chrome SxS\Application\chrome.exe")
    )

    $appPathKeys = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
    )

    foreach ($key in $appPathKeys) {
        try {
            $registeredPath = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)'
            if ($registeredPath) {
                $candidates += [string]$registeredPath
            }
        }
        catch {
            # The registry key is optional.
        }
    }

    $command = Get-Command "chrome.exe" -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates += $command.Source
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            $resolvedPath = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                return $resolvedPath
            }
        }
        catch {
            # Try the next candidate.
        }
    }

    return $null
}


function Get-ChromeExecutable {
    $candidates = @(
        $script:chromeExecutable
        (Join-Path ${env:ProgramFiles} "Google\Chrome\Application\chrome.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
        (Join-Path $env:LOCALAPPDATA "Google\Chrome SxS\Application\chrome.exe")
    )

    $appPathKeys = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
    )

    foreach ($key in $appPathKeys) {
        try {
            $registeredPath = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)'
            if ($registeredPath) {
                $candidates += [string]$registeredPath
            }
        }
        catch {
            # The registry key is optional.
        }
    }

    $command = Get-Command "chrome.exe" -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $candidates += $command.Source
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            $resolvedPath = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                return $resolvedPath
            }
        }
        catch {
            # Try the next candidate.
        }
    }

    return $null
}


function Stop-ChromeForSetup {
    $chromeProcesses = @(Get-Process -Name "chrome" -ErrorAction SilentlyContinue)

    if ($chromeProcesses.Count -eq 0) {
        return
    }

    $script:chromeWasRunning = $true

    # Get-Process.Path can be unavailable for elevated processes. Query the
    # executable path before stopping Chrome so it can be restarted later.
    try {
        $processPaths = @(
            Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction Stop |
                Select-Object -ExpandProperty ExecutablePath
        )

        if ($processPaths.Count -gt 0) {
            $script:chromeExecutable = $processPaths[0]
        }
    }
    catch {
        # Fall back to the standard paths and registry below.
    }

    if (-not $script:chromeExecutable) {
        $script:chromeExecutable = Get-ChromeExecutable
    }

    if (-not $script:chromeExecutable) {
        foreach ($process in $chromeProcesses) {
            try {
                $script:chromeExecutable = $process.Path
                if ($script:chromeExecutable) {
                    break
                }
            }
            catch {
                # The executable path may be unavailable without process access.
            }
        }
    }

    Write-Host "Chrome is running. Closing Chrome before updating its profile."
    $chromeProcesses | Stop-Process -Force

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        if (-not (Get-Process -Name "chrome" -ErrorAction SilentlyContinue)) {
            return
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Could not close Chrome before updating its profile."
}


function Start-ChromeAfterSetup {
    if (-not $script:chromeWasRunning) {
        return
    }

    try {
        $chromePath = Get-ChromeExecutable

        if (-not $chromePath) {
            Write-Warning "Chrome was running before setup but its executable could not be found. Start Chrome manually."
            return
        }

        Start-Process `
            -FilePath $chromePath `
            -WorkingDirectory (Split-Path $chromePath -Parent)

        Start-Sleep -Milliseconds 750

        if (Get-Process -Name "chrome" -ErrorAction SilentlyContinue) {
            Write-Host "Chrome restarted: $chromePath"
        }
        else {
            Write-Warning "Chrome launch did not create a running process: $chromePath"
        }
    }
    catch {
        Write-Warning "Chrome was closed but could not be restarted: $($_.Exception.Message)"
    }
}


trap {
    Start-ChromeAfterSetup
    throw $_
}


function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::Machine
    )

    $userPath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::User
    )

    $paths = @()

    if ($machinePath) {
        $paths += $machinePath
    }

    if ($userPath) {
        $paths += $userPath
    }

    $env:Path = $paths -join ";"
}


function Convert-PowerShellScriptToUtf8Bom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $content = [System.IO.File]::ReadAllText($Path)
        $encoding = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($Path, $content, $encoding)
        return $true
    }
    catch {
        Write-Warning "Could not convert PowerShell script encoding: $Path"
        return $false
    }
}


# ------------------------------------------------------------
# Windows check
# ------------------------------------------------------------

if ($env:OS -ne "Windows_NT") {
    throw "This setup script only supports Windows."
}


# ------------------------------------------------------------
# Administrator check
# ------------------------------------------------------------

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()

$principal = New-Object `
    Security.Principal.WindowsPrincipal($currentUser)

$isAdmin = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    throw "Please run PowerShell as Administrator."
}

Write-Host "Administrator privileges confirmed."

Stop-ChromeForSetup


# ------------------------------------------------------------
# PowerShell script execution
# ------------------------------------------------------------

Write-Step "Configuring PowerShell script execution"

# The script is executed through irm | iex, so no persistent execution-policy
# change is necessary. Machine policies may reject Set-ExecutionPolicy anyway.
Write-Host "Using the current PowerShell execution policy for this setup run."


# Files downloaded from the Internet can carry a Zone.Identifier alternate
# data stream. Remove that mark from trusted local contest workspaces so
# scripts such as tools\check.ps1 can run normally.
$scriptRoots = @(
    $PSScriptRoot
    (Join-Path $env:USERPROFILE "Documents\Github")
    (Join-Path $env:USERPROFILE "Desktop")
) | Where-Object {
    $_ -and (Test-Path $_)
} | Select-Object -Unique

$unblockedCount = 0
$scriptFailures = New-Object System.Collections.ArrayList

foreach ($root in $scriptRoots) {
    $scripts = Get-ChildItem `
        -Path $root `
        -Filter "*.ps1" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue

    foreach ($script in $scripts) {
        try {
            Unblock-File -LiteralPath $script.FullName -ErrorAction Stop
            if (-not (Convert-PowerShellScriptToUtf8Bom -Path $script.FullName)) {
                [void]$scriptFailures.Add($script.FullName)
                continue
            }
            $unblockedCount++
        }
        catch {
            [void]$scriptFailures.Add($script.FullName)
            Write-Warning "Could not prepare PowerShell script: $($script.FullName)"
        }
    }
}

if ($scriptFailures.Count -gt 0) {
    Write-Warning "The following PowerShell scripts could not be prepared:"
    $scriptFailures | ForEach-Object { Write-Warning "  - $_" }
    throw "PowerShell script preparation failed."
}

Write-Host "Prepared $unblockedCount PowerShell script(s) in trusted workspaces."


# ------------------------------------------------------------
# TLS 1.2
# ------------------------------------------------------------

try {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
}
catch {
    Write-Warning "Could not explicitly enable TLS 1.2."
}


# ------------------------------------------------------------
# Chocolatey fallback installer
# ------------------------------------------------------------

function Install-ChocolateyWithDotNetZip {

    Write-Step "Installing Chocolatey (.NET ZIP fallback)"

    $workDir = Join-Path `
        $env:TEMP `
        ("choco-bootstrap-" + [Guid]::NewGuid().ToString("N"))

    $extractDir = Join-Path $workDir "package"
    $packageFile = Join-Path $workDir "chocolatey.nupkg"

    New-Item `
        -ItemType Directory `
        -Path $workDir `
        -Force | Out-Null

    New-Item `
        -ItemType Directory `
        -Path $extractDir `
        -Force | Out-Null

    try {

        Write-Host "Downloading latest Chocolatey package..."

        $queryUrl = "https://community.chocolatey.org/api/v2/Packages()?`$filter=((Id%20eq%20'chocolatey')%20and%20(not%20IsPrerelease))%20and%20IsLatestVersion"

        $webClient = New-Object System.Net.WebClient
        $webClient.Credentials = `
            [System.Net.CredentialCache]::DefaultCredentials

        [xml]$result = $webClient.DownloadString($queryUrl)

        $packageUrl = $null

        foreach ($entry in $result.feed.entry) {
            if ($entry.content.src) {
                $packageUrl = [string]$entry.content.src
                break
            }
        }

        if (-not $packageUrl) {
            throw "Could not determine Chocolatey package URL."
        }

        Write-Host "Downloading:"
        Write-Host $packageUrl

        $webClient.DownloadFile(
            $packageUrl,
            $packageFile
        )

        if (-not (Test-Path $packageFile)) {
            throw "Chocolatey package download failed."
        }

        Write-Host "Extracting Chocolatey using .NET ZIP API..."

        Add-Type `
            -AssemblyName System.IO.Compression.FileSystem `
            -ErrorAction Stop

        [System.IO.Compression.ZipFile]::ExtractToDirectory(
            $packageFile,
            $extractDir
        )

        $installScript = Join-Path `
            $extractDir `
            "tools\chocolateyInstall.ps1"

        if (-not (Test-Path $installScript)) {
            throw "Chocolatey install script not found."
        }

        Write-Host "Running Chocolatey installer..."

        & $installScript
    }
    finally {

        Remove-Item `
            $workDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}


# ------------------------------------------------------------
# Chocolatey
# ------------------------------------------------------------

Write-Step "Checking Chocolatey"

Refresh-Path

if (Test-Command "choco") {

    Write-Host "Chocolatey already installed:"
    choco --version

}
else {

    # Chocolatey bootstrap installers run in the current process. Do not
    # change the machine or user execution policy; irm | iex already runs.


    # --------------------------------------------------------
    # Check Microsoft.PowerShell.Archive
    # --------------------------------------------------------

    $archiveAvailable = $false

    try {

        Import-Module `
            Microsoft.PowerShell.Archive `
            -Force `
            -ErrorAction Stop

        $null = Get-Command `
            "Microsoft.PowerShell.Archive\Expand-Archive" `
            -ErrorAction Stop

        $archiveAvailable = $true

    }
    catch {

        Write-Warning `
            "Microsoft.PowerShell.Archive is unavailable or broken."

        $archiveAvailable = $false
    }


    # --------------------------------------------------------
    # Install Chocolatey
    # --------------------------------------------------------

    if ($archiveAvailable) {

        Write-Step "Installing Chocolatey"

        Write-Host "Using official Chocolatey bootstrap installer..."

        $installer = (
            New-Object System.Net.WebClient
        ).DownloadString(
            "https://community.chocolatey.org/install.ps1"
        )

        Invoke-Expression $installer

    }
    else {

        Install-ChocolateyWithDotNetZip

    }


    # --------------------------------------------------------
    # Refresh PATH
    # --------------------------------------------------------

    Refresh-Path

    $chocoExe = Join-Path `
        $env:ProgramData `
        "chocolatey\bin\choco.exe"

    if (
        (-not (Test-Command "choco")) -and
        (Test-Path $chocoExe)
    ) {
        $env:Path = `
            "$(Split-Path $chocoExe -Parent);$env:Path"
    }

    if (-not (Test-Command "choco")) {
        throw "Chocolatey installation failed."
    }

    Write-Host ""
    Write-Host "Chocolatey installed:"
    choco --version
}


# ------------------------------------------------------------
# Git / kubectl / k9s / k6 / Terraform / jq / VS Code / Python / Docker
# ------------------------------------------------------------

Write-Step "Installing Git, kubectl, k9s, k6, Terraform, jq, VS Code, Python, and Docker Desktop"

$rebootRequired = $false
$dockerDeferred = $false

Write-Host "Installing core development tools..."

& choco install `
    git `
    kubernetes-cli `
    k9s `
    k6 `
    terraform `
    jq `
    vscode `
    python `
    -y `
    --no-progress

$coreChocoExitCode = $LASTEXITCODE

# Chocolatey uses 3010 to mean that installation succeeded but Windows
# must be rebooted before all changes take effect. Install Docker separately
# after the reboot because its MSI commonly fails with 1603 during a pending
# reboot.
if ($coreChocoExitCode -eq 3010) {
    $rebootRequired = $true
    $dockerDeferred = $true
    Write-Warning "Core tools installed, but a reboot is required. Docker Desktop installation is deferred until the next setup run."
}
elseif ($coreChocoExitCode -ne 0) {
    throw "Chocolatey package installation failed for core tools. Exit code: $coreChocoExitCode"
}
else {
    Write-Host "Installing Docker Desktop..."

    & choco install `
        docker-desktop `
        -y `
        --no-progress

    $dockerChocoExitCode = $LASTEXITCODE

    if ($dockerChocoExitCode -eq 3010) {
        $rebootRequired = $true
        Write-Warning "Docker Desktop installed, but a reboot is required."
    }
    elseif ($dockerChocoExitCode -ne 0) {
        throw "Chocolatey package installation failed for Docker Desktop. Exit code: $dockerChocoExitCode"
    }
}

Refresh-Path


# ------------------------------------------------------------
# Chrome extension and bookmark bar
# ------------------------------------------------------------

Write-Step "Configuring Chrome extension and bookmark bar"

$chromePolicyPath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$extensionPolicyPath = Join-Path $chromePolicyPath "ExtensionInstallForcelist"
$uBlockOriginLite = "ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx"
$bookmarkName = "swanno3o"
$bookmarkUrl = "https://w.swanno3o.com"

try {
    New-Item -Path $chromePolicyPath -Force | Out-Null
    New-Item -Path $extensionPolicyPath -Force | Out-Null

    $extensionProperties = Get-ItemProperty -Path $extensionPolicyPath
    $extensionValues = @(
        $extensionProperties.PSObject.Properties |
            Where-Object { $_.Name -notlike "PS*" } |
            ForEach-Object { [string]$_.Value }
    )

    if ($extensionValues -notcontains $uBlockOriginLite) {
        $extensionNumber = 1
        while ($extensionProperties.PSObject.Properties.Name -contains [string]$extensionNumber) {
            $extensionNumber++
        }

        New-ItemProperty `
            -Path $extensionPolicyPath `
            -Name ([string]$extensionNumber) `
            -Value $uBlockOriginLite `
            -PropertyType String `
            -Force | Out-Null

        Write-Host "uBlock Origin Lite force-install policy configured."
    }
    else {
        Write-Host "uBlock Origin Lite force-install policy already configured."
    }

    # Remove the managed-bookmarks policy so the link can live directly on
    # the user's bookmark bar instead of inside Chrome's managed folder.
    Remove-ItemProperty `
        -Path $chromePolicyPath `
        -Name "ManagedBookmarks" `
        -ErrorAction SilentlyContinue

    $pythonCandidates = @(
        (Get-Command "python.exe" -ErrorAction SilentlyContinue).Source
        (Join-Path $env:ProgramFiles "Python314\python.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Python314\python.exe")
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python314\python.exe")
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe")
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe")
    ) | Where-Object {
        $_ -and (Test-Path $_ -PathType Leaf)
    } | Select-Object -First 1

    if (-not $pythonCandidates) {
        throw "Python was not found. Chrome bookmark configuration requires Python."
    }

    $chromeUserDataPath = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
    $chromeProfiles = @(
        (Join-Path $chromeUserDataPath "Default")
        Get-ChildItem `
            -Path $chromeUserDataPath `
            -Directory `
            -Filter "Profile *" `
            -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    ) | Where-Object {
        $_ -and (Test-Path (Join-Path $_ "Bookmarks") -PathType Leaf)
    } | Select-Object -Unique

    if ($chromeProfiles.Count -eq 0) {
        Write-Warning "No Chrome profile was found under $chromeUserDataPath."
    }
    else {
        Write-Host "Chrome profile(s) found: $($chromeProfiles -join ', ')"
            $bookmarkTimestamp = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000 + 11644473600000000).ToString()
            $bookmarkAdded = $false
            $bookmarkPythonCode = @'
import json
import os
import sys
import tempfile
import time
import uuid

path, name, url = sys.argv[1:4]
with open(path, "r", encoding="utf-8-sig") as source:
    data = json.load(source)

bookmark_bar = data["roots"]["bookmark_bar"]
children = bookmark_bar.setdefault("children", [])

if any(item.get("url") == url for item in children):
    print("EXISTS")
    raise SystemExit(0)

numeric_ids = []
for item in children:
    try:
        numeric_ids.append(int(item.get("id", "0")))
    except (TypeError, ValueError):
        pass

chrome_timestamp = str(int((time.time() + 11644473600) * 1000000))
children.append({
    "date_added": chrome_timestamp,
    "guid": str(uuid.uuid4()),
    "id": str(max(numeric_ids, default=0) + 1),
    "name": name,
    "type": "url",
    "url": url,
})
bookmark_bar["date_modified"] = chrome_timestamp

folder = os.path.dirname(path)
fd, temporary_path = tempfile.mkstemp(prefix="Bookmarks.setup-", dir=folder)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as target:
        json.dump(data, target, ensure_ascii=False, indent=2)
        target.write("\n")
    os.replace(temporary_path, path)
except Exception:
    try:
        os.unlink(temporary_path)
    except FileNotFoundError:
        pass
    raise

print("ADDED")
'@

            $bookmarkUpdaterPath = Join-Path $env:TEMP ("setup-chrome-bookmark-" + [Guid]::NewGuid().ToString("N") + ".py")
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($bookmarkUpdaterPath, $bookmarkPythonCode, $utf8NoBom)

            try {
                foreach ($profile in $chromeProfiles) {
                    $bookmarksPath = Join-Path $profile "Bookmarks"
                    $backupPath = "$bookmarksPath.setup-backup"

                    try {
                        Copy-Item -LiteralPath $bookmarksPath -Destination $backupPath -Force
                        $pythonResult = @(
                            & $pythonCandidates $bookmarkUpdaterPath $bookmarksPath $bookmarkName $bookmarkUrl 2>&1 |
                                ForEach-Object { [string]$_ }
                        )

                        if ($LASTEXITCODE -ne 0) {
                            throw (($pythonResult -join [Environment]::NewLine).Trim())
                        }

                        $pythonStatus = ($pythonResult -join "`n").Trim()
                        if ($pythonStatus -match "(?m)^ADDED\s*$") {
                            $bookmarkAdded = $true
                            Write-Host "Added $bookmarkUrl to the Chrome bookmark bar in profile: $profile"
                        }
                        elseif ($pythonStatus -match "(?m)^EXISTS\s*$") {
                            Write-Host "Bookmark already exists in Chrome profile: $profile"
                        }
                        else {
                            throw "Unexpected bookmark updater output: $pythonStatus"
                        }
                    }
                    catch {
                        Write-Warning "Could not update Chrome bookmarks in profile '$profile': $($_.Exception.Message)"
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $bookmarkUpdaterPath -Force -ErrorAction SilentlyContinue
            }

            if ($bookmarkAdded) {
                Write-Host "Chrome bookmark bar updated. Start Chrome to see the link."
            }
        }
    }
catch {
    throw "Chrome extension/bookmark configuration failed: $($_.Exception.Message)"
}


# ------------------------------------------------------------
# WSC 2026 repository
# ------------------------------------------------------------

Write-Step "Cloning WSC 2026 repository to the Desktop"

if (-not (Test-Command "git")) {
    throw "Git was not found after installation."
}

$desktopPath = [Environment]::GetFolderPath("Desktop")

if (-not $desktopPath) {
    throw "Could not determine the current user's Desktop path."
}

New-Item `
    -ItemType Directory `
    -Path $desktopPath `
    -Force | Out-Null

$wscRepo = Join-Path $desktopPath "wsc2026"
$wscRemote = "https://github.com/onlycryintherain/wsc2026.git"

if (Test-Path (Join-Path $wscRepo ".git")) {
    Write-Host "Existing WSC 2026 repository found:"
    Write-Host $wscRepo

    & git -C $wscRepo remote set-url origin $wscRemote
    & git -C $wscRepo pull --ff-only

    if ($LASTEXITCODE -ne 0) {
        throw "Git pull failed for $wscRepo. Check for local changes or conflicts."
    }
}
elseif (Test-Path $wscRepo) {
    throw "The wsc2026 directory exists but is not a Git repository: $wscRepo"
}
else {
    Write-Host "Cloning WSC 2026 repository to the Desktop:"
    Write-Host $wscRepo

    & git clone $wscRemote $wscRepo

    if ($LASTEXITCODE -ne 0) {
        throw "Git clone failed for $wscRemote"
    }
}

Write-Host "WSC 2026 repository is ready:"
Write-Host $wscRepo

# Repeat the unblock step after clone/pull so newly downloaded workspace files
# are also runnable immediately.
$workspaceRoots = @(
    (Join-Path $env:USERPROFILE "Documents\Github")
    (Join-Path $env:USERPROFILE "Desktop")
) | Where-Object {
    $_ -and (Test-Path $_)
} | Select-Object -Unique

$postSyncFailures = New-Object System.Collections.ArrayList

foreach ($root in $workspaceRoots) {
    Get-ChildItem `
        -Path $root `
        -Filter "*.ps1" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Unblock-File `
                    -LiteralPath $_.FullName `
                    -ErrorAction Stop
                if (-not (Convert-PowerShellScriptToUtf8Bom -Path $_.FullName)) {
                    [void]$postSyncFailures.Add($_.FullName)
                }
            }
            catch {
                [void]$postSyncFailures.Add($_.FullName)
            }
        }
}

if ($postSyncFailures.Count -gt 0) {
    Write-Warning "The following synced PowerShell scripts could not be prepared:"
    $postSyncFailures | ForEach-Object { Write-Warning "  - $_" }
    throw "Synced PowerShell script preparation failed."
}


if (Test-Command "code") {
    Write-Step "Installing selected VS Code extensions"

    $vscodeExtensions = @(
        "teabyii.ayu"
        "PKief.material-icon-theme"
        "DavidAnson.vscode-markdownlint"
        "ms-vscode-remote.remote-ssh"
    )

    $extensionFailures = New-Object System.Collections.ArrayList

    foreach ($extension in $vscodeExtensions) {
        Write-Host "Installing VS Code extension: $extension"
        & code --install-extension $extension --force

        if ($LASTEXITCODE -ne 0) {
            [void]$extensionFailures.Add($extension)
            Write-Warning "VS Code extension installation failed: $extension"
        }
    }

    if ($extensionFailures.Count -gt 0) {
        Write-Warning "Some VS Code extensions could not be installed. Retry later with:"
        $extensionFailures | ForEach-Object {
            Write-Warning "  code --install-extension $_"
        }
    }

    # Preserve existing VS Code settings and update only the requested themes.
    $vscodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    $vscodeSettingsDir = Split-Path $vscodeSettingsPath -Parent

    try {
        New-Item -ItemType Directory -Path $vscodeSettingsDir -Force | Out-Null

        if (Test-Path $vscodeSettingsPath) {
            $settingsText = Get-Content -LiteralPath $vscodeSettingsPath -Raw
            $vscodeSettings = $settingsText | ConvertFrom-Json
        }
        else {
            $vscodeSettings = [PSCustomObject]@{}
        }

        $vscodeSettings | Add-Member `
            -MemberType NoteProperty `
            -Name "workbench.colorTheme" `
            -Value "Ayu Light" `
            -Force

        $vscodeSettings | Add-Member `
            -MemberType NoteProperty `
            -Name "workbench.iconTheme" `
            -Value "material-icon-theme" `
            -Force

        $vscodeSettings | ConvertTo-Json -Depth 20 | Set-Content `
            -LiteralPath $vscodeSettingsPath `
            -Encoding UTF8

        Write-Host "VS Code theme configured: Ayu Light"
        Write-Host "VS Code icon theme configured: Material Icon Theme"
    }
    catch {
        Write-Warning "Could not update VS Code settings: $($_.Exception.Message)"
    }
}
else {
    Write-Warning "VS Code command was not found; skipping extension installation."
}


# ------------------------------------------------------------
# AWS CLI v2
# ------------------------------------------------------------

Write-Step "Checking AWS CLI v2"

$installAws = $true

if (Test-Command "aws") {

    try {

        $awsVersion = (& aws --version 2>&1 | Out-String).Trim()

        Write-Host "Existing AWS CLI:"
        Write-Host $awsVersion

        if ($awsVersion -match "aws-cli/2\.") {
            $installAws = $false
        }

    }
    catch {
        $installAws = $true
    }
}


if ($installAws) {

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "AWS CLI v2 requires 64-bit Windows."
    }

    Write-Host "Installing AWS CLI v2 using official AWS MSI..."

    $awsMsi = Join-Path `
        $env:TEMP `
        "AWSCLIV2.msi"

    if (Test-Path $awsMsi) {
        Remove-Item $awsMsi -Force
    }

    try {
        # --------------------------------------------------------
        # Download AWS CLI MSI
        # --------------------------------------------------------

        $awsUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"

        $awsWebClient = New-Object System.Net.WebClient

        $awsWebClient.Credentials = `
            [System.Net.CredentialCache]::DefaultCredentials

        Download-File `
            -Url $awsUrl `
            -Destination $awsMsi

        if (-not (Test-Path $awsMsi)) {
            throw "AWS CLI MSI download failed."
        }


        # --------------------------------------------------------
        # Verify digital signature
        # --------------------------------------------------------

        Write-Host "Verifying AWS CLI MSI signature..."

        $signature = Get-AuthenticodeSignature $awsMsi

        if ($signature.Status -ne "Valid") {
            throw "AWS CLI MSI signature verification failed: $($signature.Status)"
        }

        Write-Host "AWS MSI signature valid:"
        Write-Host $signature.SignerCertificate.Subject


        # --------------------------------------------------------
        # Install AWS CLI
        # --------------------------------------------------------

        $process = Start-Process `
            -FilePath "msiexec.exe" `
            -ArgumentList @(
                "/i"
                "`"$awsMsi`""
                "/qn"
                "/norestart"
            ) `
            -Wait `
            -PassThru

        # 0    = success
        # 3010 = success, reboot required

        if ($process.ExitCode -eq 3010) {
            $rebootRequired = $true
            Write-Warning "AWS CLI installed successfully, but a reboot is required."
        }
        elseif ($process.ExitCode -ne 0) {
            throw "AWS CLI installation failed. Exit code: $($process.ExitCode)"
        }
    }
    finally {
        if (Test-Path $awsMsi) {
            Remove-Item `
                $awsMsi `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }

}
else {

    Write-Host "AWS CLI v2 already installed."
}


Refresh-Path


# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------

Write-Step "Verifying installed tools"

$failed = @()


# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- Git ---"

if (Test-Command "git") {

    try {
        git --version
    }
    catch {
        Write-Warning "Git verification failed."
        $failed += "git"
    }

}
else {

    Write-Warning "Git not found."
    $failed += "git"
}


# ------------------------------------------------------------
# kubectl
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- kubectl ---"

if (Test-Command "kubectl") {

    try {
        kubectl version --client
    }
    catch {
        Write-Warning "kubectl verification failed."
        $failed += "kubectl"
    }

}
else {

    Write-Warning "kubectl not found."
    $failed += "kubectl"
}


# ------------------------------------------------------------
# k9s
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- k9s ---"

if (Test-Command "k9s") {

    try {
        k9s version
    }
    catch {
        Write-Warning "k9s verification failed."
        $failed += "k9s"
    }

}
else {

    Write-Warning "k9s not found."
    $failed += "k9s"
}


# ------------------------------------------------------------
# k6
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- k6 ---"

if (Test-Command "k6") {

    try {
        k6 version
    }
    catch {
        Write-Warning "k6 verification failed."
        $failed += "k6"
    }

}
else {

    Write-Warning "k6 not found."
    $failed += "k6"
}


# ------------------------------------------------------------
# Terraform
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- Terraform ---"

if (Test-Command "terraform") {

    try {
        terraform version
    }
    catch {
        Write-Warning "Terraform verification failed."
        $failed += "terraform"
    }

}
else {

    Write-Warning "Terraform not found."
    $failed += "terraform"
}


# ------------------------------------------------------------
# AWS CLI
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- AWS CLI ---"

if (Test-Command "aws") {

    try {
        aws --version
    }
    catch {
        Write-Warning "AWS CLI verification failed."
        $failed += "aws"
    }

}
else {

    Write-Warning "AWS CLI not found."
    $failed += "aws"
}


# ------------------------------------------------------------
# Chocolatey
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- Chocolatey ---"

if (Test-Command "choco") {

    try {
        choco --version
    }
    catch {
        Write-Warning "Chocolatey verification failed."
        $failed += "chocolatey"
    }

}
else {

    Write-Warning "Chocolatey not found."
    $failed += "chocolatey"
}


# ------------------------------------------------------------
# jq
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- jq ---"

if (Test-Command "jq") {

    try {
        jq --version
    }
    catch {
        Write-Warning "jq verification failed."
        $failed += "jq"
    }

}
else {

    Write-Warning "jq not found."
    $failed += "jq"
}


# ------------------------------------------------------------
# VS Code
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- VS Code ---"

if (Test-Command "code") {

    try {
        code --version
    }
    catch {
        Write-Warning "VS Code verification failed."
        $failed += "vscode"
    }

}
else {

    Write-Warning "VS Code not found."
    $failed += "vscode"
}


# ------------------------------------------------------------
# Python
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- Python ---"

if (Test-Command "python") {

    try {
        python --version
    }
    catch {
        Write-Warning "Python verification failed."
        $failed += "python"
    }

}
else {

    Write-Warning "Python not found."
    $failed += "python"
}


# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

Write-Host ""
Write-Host "--- Docker ---"

if (Test-Command "docker") {

    try {
        docker --version
    }
    catch {
        Write-Warning "Docker verification failed."
        $failed += "docker"
    }

}
elseif ($dockerDeferred) {

    Write-Warning "Docker verification deferred until after the required reboot."

}
else {

    Write-Warning "Docker not found."
    $failed += "docker"

}


# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"

if ($rebootRequired) {
    Write-Warning "A reboot is required to complete the installation. Please reboot Windows before using the installed tools."
}

if ($failed.Count -eq 0) {

    Write-Host "SETUP COMPLETE"
    Write-Host ""
    Write-Host "Installed:"
    Write-Host "  - Chocolatey"
    Write-Host "  - Git"
    Write-Host "  - kubectl"
    Write-Host "  - k9s"
    Write-Host "  - k6"
    Write-Host "  - Terraform"
    Write-Host "  - AWS CLI v2"
    Write-Host "  - jq"
    Write-Host "  - Visual Studio Code"
    Write-Host "  - Python"
    if (-not $dockerDeferred) {
        Write-Host "  - Docker Desktop"
    }
    else {
        Write-Host "  - Docker Desktop (deferred until reboot)"
    }
    Write-Host "  - uBlock Origin Lite Chrome extension (if Chrome is installed)"
    Write-Host "  - w.swanno3o.com Chrome bookmark bar link (if Chrome is installed)"

}
else {

    Write-Warning "Setup completed with verification failures:"

    foreach ($item in $failed) {
        Write-Warning "  - $item"
    }

    Write-Warning "One or more tools failed verification."

    throw "One or more tools failed verification."
}

Write-Host "============================================================"
Start-ChromeAfterSetup
