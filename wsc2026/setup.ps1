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


function Test-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
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


# ------------------------------------------------------------
# PowerShell script execution
# ------------------------------------------------------------

Write-Step "Configuring PowerShell script execution"

# Allow this setup process to run local scripts and persist a reasonable
# per-user policy for future contest workspace scripts.
try {
    Set-ExecutionPolicy `
        -Scope Process `
        -ExecutionPolicy Bypass `
        -Force `
        -ErrorAction Stop

    Set-ExecutionPolicy `
        -Scope CurrentUser `
        -ExecutionPolicy RemoteSigned `
        -Force `
        -ErrorAction Stop

    Write-Host "PowerShell execution policy configured."
}
catch {
    Write-Warning "Could not change the PowerShell execution policy: $($_.Exception.Message)"
}

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
            $unblockedCount++
        }
        catch {
            Write-Warning "Could not unblock PowerShell script: $($script.FullName)"
        }
    }
}

Write-Host "Unblocked $unblockedCount PowerShell script(s) in trusted workspaces."


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

    Set-ExecutionPolicy `
        Bypass `
        -Scope Process `
        -Force


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

& choco install `
    git `
    kubernetes-cli `
    k9s `
    k6 `
    terraform `
    jq `
    vscode `
    python `
    docker-desktop `
    -y `
    --no-progress

$chocoExitCode = $LASTEXITCODE

# Chocolatey uses 3010 to mean that installation succeeded but Windows
# must be rebooted before all changes take effect. It is not a failure.
if ($chocoExitCode -eq 3010) {
    $rebootRequired = $true
    Write-Warning "Chocolatey installed the packages successfully, but a reboot is required. Continuing setup."
}
elseif ($chocoExitCode -ne 0) {
    throw "Chocolatey package installation failed. Exit code: $chocoExitCode"
}

Refresh-Path


# ------------------------------------------------------------
# GitHub setup repository
# ------------------------------------------------------------

Write-Step "Syncing GitHub setup repository"

if (-not (Test-Command "git")) {
    throw "Git was not found after installation."
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
$setupRepo = Join-Path $desktopPath "setup"
$setupRemote = "https://github.com/WhAnci/setup.git"

if (-not $desktopPath) {
    throw "Could not determine the current user's Desktop path."
}

New-Item `
    -ItemType Directory `
    -Path $desktopPath `
    -Force | Out-Null

if (Test-Path (Join-Path $setupRepo ".git")) {
    Write-Host "Existing setup repository found:"
    Write-Host $setupRepo

    & git -C $setupRepo remote set-url origin $setupRemote
    & git -C $setupRepo pull --ff-only origin main

    if ($LASTEXITCODE -ne 0) {
        throw "Git pull failed for $setupRepo. Check for local changes or conflicts."
    }
}
elseif (Test-Path $setupRepo) {
    throw "The setup directory exists but is not a Git repository: $setupRepo"
}
else {
    Write-Host "Cloning setup repository to the Desktop:"
    Write-Host $setupRepo

    & git clone --branch main $setupRemote $setupRepo

    if ($LASTEXITCODE -ne 0) {
        throw "Git clone failed for $setupRemote"
    }
}

Write-Host "Setup repository is ready:"
Write-Host $setupRepo


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

        $awsWebClient.DownloadFile(
            $awsUrl,
            $awsMsi
        )

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
    Write-Host "  - Docker Desktop"

}
else {

    Write-Warning "Setup completed with verification failures:"

    foreach ($item in $failed) {
        Write-Warning "  - $item"
    }

    throw "One or more tools failed verification."
}

Write-Host "============================================================"
