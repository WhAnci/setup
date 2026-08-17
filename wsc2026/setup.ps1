$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Require Administrator
# ------------------------------------------------------------
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

$isAdmin = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    throw "Please run PowerShell as Administrator."
}

Write-Host "Administrator privileges confirmed."


# ------------------------------------------------------------
# Chocolatey
# ------------------------------------------------------------
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..."

    Set-ExecutionPolicy Bypass -Scope Process -Force

    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    iex (
        (New-Object System.Net.WebClient).DownloadString(
            "https://community.chocolatey.org/install.ps1"
        )
    )

    # Refresh PATH
    $env:Path = (
        [Environment]::GetEnvironmentVariable("Path", "Machine"),
        [Environment]::GetEnvironmentVariable("Path", "User")
    ) -join ";"
}
else {
    Write-Host "Chocolatey already installed."
}


# ------------------------------------------------------------
# kubectl / k9s / k6 / Terraform
# ------------------------------------------------------------
Write-Host "Installing kubectl, k9s, k6, Terraform..."

choco install kubernetes-cli k9s k6 terraform -y


# ------------------------------------------------------------
# AWS CLI v2
# Official AWS MSI installer
# ------------------------------------------------------------
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "Installing AWS CLI v2..."

    $awsMsi = Join-Path $env:TEMP "AWSCLIV2.msi"

    Invoke-WebRequest `
        -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" `
        -OutFile $awsMsi

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

    Remove-Item $awsMsi -Force -ErrorAction SilentlyContinue

    # 0 = success
    # 3010 = success, reboot required
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "AWS CLI installation failed. Exit code: $($process.ExitCode)"
    }
}
else {
    Write-Host "AWS CLI already installed."
}


# ------------------------------------------------------------
# Refresh PATH
# ------------------------------------------------------------
$env:Path = (
    [Environment]::GetEnvironmentVariable("Path", "Machine"),
    [Environment]::GetEnvironmentVariable("Path", "User")
) -join ";"


# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------
Write-Host ""
Write-Host "========================================"
Write-Host "Installed tools"
Write-Host "========================================"

Write-Host -NoNewline "kubectl:   "
kubectl version --client

Write-Host -NoNewline "k9s:       "
k9s version

Write-Host -NoNewline "k6:        "
k6 version

Write-Host -NoNewline "terraform: "
terraform version

Write-Host -NoNewline "aws:       "
aws --version

Write-Host ""
Write-Host "Setup complete."
