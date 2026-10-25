function Latest-Ver {
    $Releases = try {
        Invoke-RestMethod -Uri "https://api.github.com/repos/munastronaut/zon2tct/releases/latest?per_page=1" `
            -Headers @{
                "Accept" = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2026-03-10"
            }
    } catch {
        throw "failed to find latest version: $_"
    }

    return $Releases.tag_name
}

function Arch {
    $Raw = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture

    $Arch = switch ($Raw) {
        "X64"   { "x86_64" }
        "Arm64" { "aarch64" }
        default { "unknown" }
    }

    return $Arch
}

function Os {
    $Os = switch ($true) {
        { $IsLinux }   { "linux" }
        { $IsMacOS }   { "macos" }
        { $IsWindows } { "windows" }
        default        { "unknown" }
    }

    return $Os
}

function Fmt {
    param(
        [string]$Os
    );

    $Fmt = switch ($Os) {
        "windows" { ".zip" }
        default   { ".tar.gz" }
    }

    return $Fmt
}

function Install {
    param(
        [string]$Arch,
        [string]$Os,
        [string]$Ver
    );

    $Fmt = Fmt $Os

    $Asset = "zon2tct-$Arch-$Os-$Ver$Fmt"
    $Link  = "https://github.com/munastronaut/zon2tct/releases/latest/download/$Asset"

    $Filename = "zon2tct$Fmt"

    $LastPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Link -OutFile $Filename
    } catch {
        throw "failed to download zon2tct: $_"
    }
    $ProgressPreference = $LastPreference

    $Path = Join-Path -Path $Home -ChildPath ".zon2tct"

    New-Item -Force -Path "${Home}" -Name ".zon2tct" -ItemType "Directory"

    try {
        switch ($Fmt) {
            "zip"    { Expand-Archive -Path $Filename -Force -ErrorAction Stop }
            "tar.gz" { tar -xzf $Filename -C $Path }
        }
    } catch {
        throw "failed to extract ${Filename}: $_"
    }

    $ExeFmt = switch ($Os) {
        windows { '.exe' }
        default { '' }
    }

    $ArchivePath = Join-Path -Path $Path -ChildPath "zon2tct$ExeFmt"

    switch ($Os) {
        "linux" { chmod +x $ArchivePath }
        default { Unblock-File -Path $ArchivePath -Force -ErrorAction SilentlyContinue }
    }

    Remove-Item $Filename -Force -ErrorAction SilentlyContinue
}

function Environ {
    $Sep  = [System.IO.Path]::PathSeparator
    $User = [System.EnvironmentVariableTarget]::User
    $Path = [System.Environment]::GetEnvironmentVariable('Path', $User) -split $Sep

    $Z2TRoot    = Join-Path -Path $Home -ChildPath ".zon2tct"
    $Z2TInst    = 'Z2T_INSTALL'
    $Z2TInstVal = [System.Environment]::GetEnvironmentVariable($Z2TInst, $User)

    if ($null -eq $Z2TInstVal) {
        [System.Environment]::SetEnvironmentVariable($Z2TInst, $Z2TRoot, $User)
    }

    if ($Path -notcontains $Z2TRoot) {
        $Path += $Z2TRoot
        [System.Environment]::SetEnvironmentVariable('Path', $Path -join $Sep, $User)
    }

    Write-Host "zon2tct was installed at $Z2TRoot"
    Write-Host 'restart your shell to start using zon2tct'
}

function Main {
    Install $(Arch) $(Os) $(Latest-Ver)
    Environ
}

Main
