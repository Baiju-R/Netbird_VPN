# -----------------------------
# NetBird Silent Deployment
# -----------------------------

$NetBirdVersion = "0.75.0"

$ManagementURL = "https://fs-ztvpn.finsurge.ai"

$Installer = "$env:TEMP\netbird-$NetBirdVersion.msi"

$DownloadUrl = "https://github.com/netbirdio/netbird/releases/download/v$NetBirdVersion/netbird_installer_$($NetBirdVersion)_windows_amd64.msi"


Write-Host "Downloading NetBird $NetBirdVersion..."

Invoke-WebRequest `
    -Uri $DownloadUrl `
    -OutFile $Installer


Write-Host "Installing NetBird..."

Start-Process `
    -FilePath "msiexec.exe" `
    -ArgumentList "/i `"$Installer`" /qn /norestart" `
    -Wait `
    -NoNewWindow


Start-Sleep -Seconds 5


$NetBirdExe = "${env:ProgramFiles}\NetBird\netbird.exe"


if (!(Test-Path $NetBirdExe)) {
    throw "netbird.exe not found."
}


Write-Host "Configuring NetBird management URL..."


# Interactive SSO enrollment
& $NetBirdExe up `
    --management-url $ManagementURL


Write-Host "Checking NetBird service..."

$Service = Get-Service -Name "NetBird" -ErrorAction SilentlyContinue

if ($null -eq $Service) {
    Write-Host "NetBird service not found."
}
elseif ($Service.Status -ne "Running") {
    Write-Host "Starting NetBird service..."
    Start-Service -Name "NetBird"
}
else {
    Write-Host "NetBird service running."
}


Write-Host "NetBird deployment completed."