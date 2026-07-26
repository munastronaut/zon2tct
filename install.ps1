function Install-Latest {
    param(
        [string]$Suffix
    );

    # Ripping off zvm's install script

    $Z2TRoot = "${Home}\.zon2tct"
    $Target = $Suffix
    $ZipPath = "${Z2TRoot}\$Target"

    $URL = "https://github.com/munastronaut/zon2tct/releases/latest/download/$Target"

    $null = mkdir -Force $Z2TRoot
    Remove-Item -Force $ZipPath -ErrorAction SilentlyContinue
    curl.exe "-#SfLo" "$ZipPath" "$URL"
    if ($LASTEXITCODE -ne 0) {
        Write-Output "install failed - could not download $URL"
        Write-Output "the command 'curl.exe $URL -o $ZipPath' exited with code ${LASTEXITCODE}`n"
        exit 1
    }
    if (!(Test-Path $ZipPath)) {
        Write-Output "install failed - could not download $URL"
        Write-Output "the file '$ZipPath' does not exist. did an antivirus delete it?`n"
        exit 1
    }
    try {
        $lastProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue';
        Remove-Item "${Z2TRoot}\zon2tct.exe" -Force -ErrorAction SilentlyContinue
        Expand-Archive "$ZipPath" "$Z2TRoot" -Force
        Unblock-File "${Z2TRoot}\zon2tct.exe" -ErrorAction SilentlyContinue
        $global:ProgressPreference = $lastProgressPreference
        if (!(Test-Path "${Z2TRoot}\zon2tct.exe")) {
            throw "the file '${Z2TRoot}\zon2tct.exe' does not exist`nlikely cause: Windows Defender quarantined it`nfix: add an exclusion for '$Z2TRoot' in Windows Security > Virus & threat protection > Exclusions, then re-run the installer`n"
        }
    }
    catch {
        Write-Output "Install Failed - could not unzip $ZipPath"
        Write-Error $_
        exit 1
    }
    Remove-Item "$ZipPath" -Force -ErrorAction SilentlyContinue

    $null = "$(& "${Z2TRoot}\zon2tct.exe")"
    if ($LASTEXITCODE -eq 1073741795) {
        # STATUS_ILLEGAL_INSTRUCTION
        Write-Output "install failed - zon2tct.exe is not compatible with your CPU`n"
        exit 1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Output "install failed - could not verify zon2tct.exe"
        Write-Output "the command '${Z2TRoot}\zon2tct.exe' exited with code ${LASTEXITCODE}`n"
        exit 1
    }

    $User = [System.EnvironmentVariableTarget]::User
    $Path = [System.Environment]::GetEnvironmentVariable('Path', $User) -split ';'
    $Z2TInstall = 'Z2T_INSTALL'

    $Z2TInstallValue = [System.Environment]::GetEnvironmentVariable($Z2TInstall, [System.EnvironmentVariableTarget]::User)

    if ($null -eq $Z2TInstallValue) {
        [System.Environment]::SetEnvironmentVariable($Z2TInstall, $Z2TRoot, [System.EnvironmentVariableTarget]::User)
    }

    if ($Path -notcontains $Z2TRoot) {
        $Path += $Z2TRoot
        [System.Environment]::SetEnvironmentVariable('Path', $Path -join ';', $User)
    }
    $SessionPath = $env:PATH -split ';'
    if ($SessionPath -notcontains $Z2TRoot) {
        $env:PATH = "${env:PATH};${Z2TRoot}"
    }

    Write-Output "zon2tct was installed at '${Z2TRoot}\zon2tct.exe'"
    Write-Output "restart your terminal or editor to start using zon2tct"
}

$PROCESSOR_ARCH = $env:PROCESSOR_ARCHITECTURE.ToLower()

if ($PROCESSOR_ARCH -eq "x86") {
    Write-Output "install failed - zon2tct requires a 64-bit environment"
    Write-Output "please ensure that you are running the 64-bit version of PowerShell or that your system is 64-bit`n"
    exit 1
}

function Actual-Install {
    $Releases = Invoke-RestMethod -Uri "https://api.github.com/repos/munastronaut/zon2tct/releases/latest" `
                                  -Headers @{
                                      "Accept" = "application/vnd.github+json"
                                      "X-GitHub-Api-Version" = "2026-03-10"
                                  }

    $Assets = $Releases.assets |
        Where-Object {$_.name -like "*$PROCESSOR_ARCH*" -and $_.name -like "*windows*"} |
        Select-Object -ExpandProperty name

    $Asset = $Assets | Select-Object -Last 2 | Select-Object -First 1

    Install-Latest $Asset
}

Actual-Install
