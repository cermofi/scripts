#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Updates 7-Zip and supported TeamViewer installations and services Secure Boot 2023.
Updates machine-wide TeamViewer MSI deployments with the matching signed vendor MSI.
Uninstalls registered LibreOffice products and the official Microsoft Store package.
Updates registered pgAdmin 4 and supported standalone JetBrains desktop products to stable releases.
Checks the Windows 11 build and BitLocker. Does not run Windows Update or restart Windows.
Use -CheckOnly to report findings without installing updates, removing apps or changing Secure Boot.
Run or paste this script in an open PowerShell prompt to return to that prompt after the report.
-NoPause is accepted for compatibility with previous versions.
A TeamViewer update can disconnect an active remote session.
Exit codes: 0 = checks passed, 1 = failure or action required, 2 = update or reboot pending.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$NoPause
)

$RequiredWindowsBuild = 26100
$MinimumTeamViewerVersion = [version]'15.83.0.0' # TeamViewer security bulletin TV-2026-1011.
$SecureBootPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
$SecureBootTaskPath = '\Microsoft\Windows\PI\'
$SecureBootTaskName = 'Secure-Boot-Update'
$SecureBootUpdateFlags = 0x5944
$SecureBootActionFlags = 0x1944

function New-Result {
    param(
        [string]$Name, [string]$Status, [string]$Detail, [switch]$Restart,
        [string]$InstalledVersion, [string]$LatestStableVersion, [string]$PreviousVersion
    )

    [pscustomobject]@{
        Name                = $Name
        Status              = $Status
        Detail              = $Detail
        Restart             = [bool]$Restart
        InstalledVersion    = $InstalledVersion
        LatestStableVersion = $LatestStableVersion
        PreviousVersion     = $PreviousVersion
    }
}

function Get-StatusColor {
    param([string]$Status)

    switch ($Status) {
        'FAILED'          { 'Red' }
        'WARNING'         { 'Yellow' }
        'ACTION REQUIRED' { 'Yellow' }
        'PENDING'         { 'Yellow' }
        'SKIPPED'         { 'Gray' }
        'INFO'            { 'Cyan' }
        default           { 'Green' }
    }
}

function Write-StepMessage {
    param([string]$Message, [string]$Level = 'INFO')

    Write-Host ('[{0:HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level, $Message) -ForegroundColor (Get-StatusColor $Level)
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action, [switch]$ShowVersions)

    Write-StepMessage "Starting $Name."
    & {
        try {
            & $Action
        }
        catch {
            $versions = if ($ShowVersions) { @{ InstalledVersion = 'Unknown'; LatestStableVersion = 'Not checked' } } else { @{} }
            New-Result $Name 'FAILED' $_.Exception.Message @versions
        }
    } | ForEach-Object {
        Write-StepMessage "$($_.Name) | $($_.Detail)" $_.Status
        $_
    }
}

function Write-FinalReport {
    param([object[]]$Results)

    Write-Host ''
    Write-Host 'Final report' -ForegroundColor Cyan
    foreach ($result in $Results) {
        Write-Host ("{0}  [{1}]" -f $result.Name, $result.Status) -ForegroundColor (Get-StatusColor $result.Status)
        if ($result.InstalledVersion -or $result.LatestStableVersion) {
            $installed = if ($result.InstalledVersion) { $result.InstalledVersion } else { 'Unknown' }
            $latest = if ($result.LatestStableVersion) { $result.LatestStableVersion } else { 'Unavailable' }
            Write-Host ("  {0,-22} {1}" -f 'Installed version', $installed)
            Write-Host ("  {0,-22} {1}" -f 'Latest stable version', $latest)
        }
        if ($result.PreviousVersion) {
            Write-Host ("  {0,-22} {1}" -f 'Previous version', $result.PreviousVersion)
        }
        if ($result.Detail) {
            Write-Host ("  {0,-22} {1}" -f 'Details', $result.Detail)
        }
    }
}

function ConvertTo-AppVersion {
    param([string]$Text)

    if ($Text -match '\d+(?:\.\d+){1,3}') {
        $parsed = $null
        if ([version]::TryParse($Matches[0], [ref]$parsed)) {
            return [version]::new(
                $parsed.Major, $parsed.Minor,
                [Math]::Max(0, $parsed.Build), [Math]::Max(0, $parsed.Revision)
            )
        }
    }
}

function Get-ExecutableVersion {
    param([string]$Path)

    $info = (Get-Item -LiteralPath $Path).VersionInfo
    $version = ConvertTo-AppVersion $info.FileVersion
    if (-not $version) {
        $version = ConvertTo-AppVersion $info.ProductVersion
    }
    return $version
}

function Get-InstalledApps {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            Get-ItemProperty -Path "$path\*"
        }
    }
}

function Get-PeArchitecture {
    param([string]$Path)

    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Invalid executable header: $Path"
        }
        $stream.Position = 0x3C
        $stream.Position = $reader.ReadInt32()
        if ($reader.ReadUInt32() -ne 0x4550) {
            throw "Invalid PE signature: $Path"
        }
        switch ($reader.ReadUInt16()) {
            0x014C { return 'x86' }
            0x8664 { return 'x64' }
            0x01C4 { return 'arm' }
            0xAA64 { return 'arm64' }
            default { throw "Unsupported executable architecture: $Path" }
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Get-SevenZipInstallations {
    param([object[]]$Registered)

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $directories = @(
        foreach ($base in @($env:ProgramFiles, $programFilesX86, $env:ProgramW6432)) {
            if ($base) { Join-Path $base '7-Zip' }
        }
        foreach ($app in $Registered) {
            if ($app.InstallLocation) { $app.InstallLocation }
        }
        foreach ($key in @('HKLM:\SOFTWARE\7-Zip', 'HKLM:\SOFTWARE\WOW6432Node\7-Zip')) {
            if (Test-Path -LiteralPath $key) {
                $entry = Get-ItemProperty -LiteralPath $key
                $entry.Path
                $entry.Path64
                $entry.Path32
            }
        }
    )

    foreach ($directory in ($directories | Where-Object { $_ } | Sort-Object -Unique)) {
        $file = Join-Path $directory '7z.exe'
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file
            [pscustomobject]@{
                File         = $item.FullName
                Directory    = $item.DirectoryName
                Architecture = Get-PeArchitecture $item.FullName
            }
        }
    }
}

function Get-SevenZipVersion {
    param([string[]]$Files)

    $versions = foreach ($file in $Files) {
        $version = Get-ExecutableVersion $file
        if (-not $version) { throw "Could not read the version of $file." }
        $version
    }
    $versions | Sort-Object | Select-Object -First 1
}

function Test-PendingFileReplacement {
    param([string[]]$Files)

    $session = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $renames = @($session.PendingFileRenameOperations)
    for ($index = 1; $index -lt $renames.Count; $index += 2) {
        $destination = ([string]$renames[$index]).TrimStart('!')
        foreach ($file in $Files) {
            if ($destination -eq "\??\$file") { return $true }
        }
    }
    return $false
}

function Update-SevenZip {
    Write-StepMessage '7-Zip | Looking for installed copies in the registry and application folders.'
    $registered = @(Get-InstalledApps | Where-Object { $_.DisplayName -match '^7-Zip(?:\s|$)' })
    $installations = @(Get-SevenZipInstallations $registered | Sort-Object File -Unique)
    if (-not $installations) {
        if ($registered) { throw '7-Zip is registered, but 7z.exe could not be found.' }
        New-Result '7-Zip' 'SKIPPED' '7-Zip is not installed.' -InstalledVersion 'Not installed' -LatestStableVersion 'Not checked'
        return
    }

    $msiLocations = @(
        foreach ($entry in ($registered | Where-Object { $_.WindowsInstaller -eq 1 })) {
            $matchesForMsi = @($installations | Where-Object {
                if ($entry.InstallLocation) {
                    $_.Directory -eq $entry.InstallLocation.TrimEnd('\')
                }
                elseif ($entry.PSPath -match 'WOW6432Node' -or $entry.DisplayName -match '\(x86\)') {
                    $_.Architecture -eq 'x86'
                }
                else {
                    $_.Architecture -eq 'x64' -or
                        ($_.Architecture -eq 'x86' -and -not [Environment]::Is64BitOperatingSystem)
                }
            })
            if ($matchesForMsi.Count -ne 1) {
                throw "Could not identify the installed MSI location for $($entry.DisplayName)."
            }
            $matchesForMsi[0].File
        }
    )

    $request = @{
        Uri = 'https://api.github.com/repos/ip7z/7zip/releases/latest'
        Headers = @{ Accept = 'application/vnd.github+json' }
        UserAgent = 'Security-Remediation'
        UseBasicParsing = $true
        TimeoutSec = 30
    }
    $latest = $null
    $releaseError = $null
    Write-StepMessage '7-Zip | Checking the latest stable release from the publisher.'
    try {
        $release = Invoke-RestMethod @request
        if ($release.tag_name -notmatch '^\d+\.\d+$' -or $release.draft -or $release.prerelease) {
            throw 'The official 7-Zip release could not be identified.'
        }
        $latest = ConvertTo-AppVersion $release.tag_name
        if (-not $latest) { throw 'Invalid version in the official 7-Zip release.' }
    }
    catch {
        $releaseError = $_.Exception.Message
    }

    foreach ($installation in $installations) {
        $name = "7-Zip ($($installation.Architecture))"
        $versions = @{ InstalledVersion = 'Unknown'; LatestStableVersion = 'Unavailable' }
        if ($latest) { $versions.LatestStableVersion = $release.tag_name }
        try {
            Write-StepMessage "$name | Reading installed executable and library versions."
            $files = @($installation.File, (Join-Path $installation.Directory '7z.dll'))
            foreach ($component in @('7zFM.exe', '7zG.exe', '7-zip.dll', '7-zip32.dll')) {
                $file = Join-Path $installation.Directory $component
                if (Test-Path -LiteralPath $file -PathType Leaf) { $files += $file }
            }
            $before = Get-SevenZipVersion $files
            $versions.InstalledVersion = $before
            if ($releaseError) { throw $releaseError }
            Write-StepMessage "$name | Oldest installed component $before. Latest stable release $($release.tag_name)."
            if ($before -ge $latest) {
                New-Result $name 'UP TO DATE' 'All checked components meet the latest stable version.' @versions
                continue
            }
            if ($CheckOnly) {
                New-Result $name 'ACTION REQUIRED' 'A newer release is available. Check-only mode.' @versions
                continue
            }

            $isMsi = $msiLocations -contains $installation.File
            $extension = if ($isMsi) { 'msi' } else { 'exe' }
            $suffix = if ($installation.Architecture -ne 'x86') { "-$($installation.Architecture)" }
            $assetName = "7z$($release.tag_name.Replace('.', ''))$suffix.$extension"
            $url = "https://github.com/ip7z/7zip/releases/download/$($release.tag_name)/$assetName"
            $asset = $release.assets | Where-Object { $_.name -ceq $assetName } | Select-Object -First 1
            if (-not $asset -or $asset.browser_download_url -cne $url -or
                $asset.digest -notmatch '^sha256:[a-f0-9]{64}$') {
                throw "Official installer or SHA-256 missing for $assetName."
            }

            $installer = Join-Path ([IO.Path]::GetTempPath()) ("7zip-{0}.$extension" -f [guid]::NewGuid())
            try {
                Write-StepMessage "$name | Downloading $assetName."
                Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $installer -TimeoutSec 120
                Write-StepMessage "$name | Verifying the SHA-256 hash and checking the installer signature."
                if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $asset.digest.Substring(7)) {
                    throw "SHA-256 mismatch for $assetName."
                }

                # The official release can be unsigned. Reject an invalid signature when one exists.
                $signature = Get-AuthenticodeSignature -LiteralPath $installer
                if ($signature.Status -notin @('Valid', 'NotSigned')) {
                    throw "Invalid installer signature: $($signature.Status)."
                }

                Write-StepMessage "$name | Installing silently. Waiting for the installer to finish."
                if ($isMsi) {
                    $arguments = '/i "{0}" /qn /norestart INSTALLDIR="{1}"' -f $installer, $installation.Directory
                    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
                }
                else {
                    $arguments = '/S /D="{0}"' -f $installation.Directory
                    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
                }

                if ($process.ExitCode -eq 3010) {
                    New-Result $name 'PENDING' 'The installer requests a restart (3010). Installed version is the last verified value.' @versions -Restart
                    continue
                }
                if ($process.ExitCode -ne 0) {
                    throw "Installer exit code: $($process.ExitCode)."
                }

                Write-StepMessage "$name | Installer exited with code 0. Checking the installed versions again."
                $after = Get-SevenZipVersion $files
                $versions.InstalledVersion = $after
                if ($after -lt $latest) {
                    if (Test-PendingFileReplacement $files) {
                        New-Result $name 'PENDING' 'Restart to replace files in use.' @versions -Restart
                        continue
                    }
                    throw "After installation: $after | Expected: $latest or newer | $($installation.File)"
                }
                New-Result $name 'UPDATED' "Verified update from $before to $after." @versions -PreviousVersion $before
            }
            finally {
                Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            New-Result $name 'FAILED' $_.Exception.Message @versions
        }
    }
}

function Get-HexCode {
    param([long]$Code)
    '0x{0:X8}' -f ($Code -band 4294967295L)
}

function Invoke-WinGet {
    param([string]$Path, [string[]]$Arguments)

    $temporaryPath = Join-Path ([IO.Path]::GetTempPath()) ("winget-{0}" -f [guid]::NewGuid())
    $stdout = "$temporaryPath.out"
    $stderr = "$temporaryPath.err"
    try {
        $options = @{
            FilePath = $Path
            ArgumentList = $Arguments
            Wait = $true
            PassThru = $true
            RedirectStandardOutput = $stdout
            RedirectStandardError = $stderr
            WindowStyle = 'Hidden'
        }
        $process = Start-Process @options
        [pscustomobject]@{
            Code   = Get-HexCode $process.ExitCode
            Output = Get-Content -LiteralPath $stdout -Raw
            Error  = Get-Content -LiteralPath $stderr -Raw
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Get-TeamViewerCommandPath {
    param([string]$CommandLine)

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine)
    if ($expanded -match '^\s*"?(?<Path>[a-z]:\\(?:[^"\r\n]*?\\)?TeamViewer(?:_Service|_Host|_Full)?\.exe)(?=["\s,]|$)') {
        return $Matches.Path
    }
}

function Get-TeamViewerExecutable {
    param([string]$Directory)

    if (-not $Directory) { return }
    foreach ($name in @('TeamViewer.exe', 'TeamViewer_Service.exe', 'TeamViewer_Host.exe', 'TeamViewer_Full.exe')) {
        $path = Join-Path $Directory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
}

function Get-RegisteredAppEntries {
    foreach ($entry in (Get-InstalledApps)) {
        [pscustomobject]@{ Entry = $entry; Scope = 'Machine registry'; CurrentContext = $true }
    }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
        foreach ($hive in (Get-ChildItem -LiteralPath 'Registry::HKEY_USERS')) {
            if ($hive.PSChildName -ne $currentSid -and $hive.PSChildName -match '^S-1-(5-21|12-1)-[\d-]+$') {
                "$($hive.PSPath)\Software\Microsoft\Windows\CurrentVersion\Uninstall"
            }
        }
    )
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root) {
            foreach ($entry in (Get-ItemProperty -Path "$root\*")) {
                [pscustomobject]@{ Entry = $entry; Scope = 'User registry'; CurrentContext = $root -like 'HKCU:*' }
            }
        }
    }
}

function Get-TeamViewerMachineFiles {
    $programRoots = @(
        $env:ProgramFiles
        [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $env:ProgramW6432
    )
    foreach ($root in ($programRoots | Where-Object { $_ } | Sort-Object -Unique)) {
        foreach ($folder in @('TeamViewer', 'TeamViewer Host')) {
            Get-TeamViewerExecutable (Join-Path $root $folder)
        }
    }

    $services = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\TeamViewer*' -ErrorAction SilentlyContinue
    foreach ($service in $services) {
        $path = Get-TeamViewerCommandPath $service.ImagePath
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $directory = Split-Path -LiteralPath $path
            $mainExecutable = Get-TeamViewerExecutable $directory
            if ($mainExecutable) { $mainExecutable } else { $path }
        }
    }
}

function Get-TeamViewerInventory {
    $apps = @(
        foreach ($record in (Get-RegisteredAppEntries)) {
            $app = $record.Entry
            $name = [string]$app.DisplayName
            if ($name -match '\b(?:Quick\s*Support|Quick\s*Join|Meeting|Pilot|Assist AR|Frontline|DEX|Endpoint Protection|Remote Management|Add-ons?)\b') {
                continue
            }

            $icon = Get-TeamViewerCommandPath $app.DisplayIcon
            $isMsi = $app.WindowsInstaller -eq 1 -or
                "$($app.UninstallString) $($app.QuietUninstallString)" -match '\bmsiexec(?:\.exe)?(?=["\s]|$)'
            $vendorMsi = $isMsi -and $app.Publisher -match '^TeamViewer\b'
            if ($name -notmatch '\bTeamViewer\b' -and -not $vendorMsi -and -not $icon) { continue }

            $path = $null
            if ($app.InstallLocation) {
                $directory = [Environment]::ExpandEnvironmentVariables($app.InstallLocation.Trim().Trim('"'))
                if ($directory -match '^[a-z]:\\') { $path = Get-TeamViewerExecutable $directory }
            }
            if (-not $path -and $icon -and (Test-Path -LiteralPath $icon -PathType Leaf)) {
                $path = $icon
            }
            if ($name -notmatch '\bTeamViewer\b' -and -not $path -and -not $vendorMsi) { continue }

            $packageId = if ($name -match '\bHost\b' -or $path -match '\\TeamViewer_Host\.exe$') {
                'TeamViewer.TeamViewer.Host'
            }
            elseif ($name -match '^TeamViewer(?:\s+(?:Remote|Full(?:\s+Client)?|Client|\d+(?:\.\d+)*))*' +
                '(?:\s*(?:\(|\[)?(?:x86|x64|arm64|32[- ]bit|64[- ]bit)(?:\)|\])?)?$' -or
                $path -match '\\TeamViewer_Full\.exe$') {
                'TeamViewer.TeamViewer'
            }
            $productCode = if ($isMsi -and $app.PSChildName -match '^\{[0-9a-f-]{36}\}$') {
                $app.PSChildName
            }
            elseif ($isMsi -and $app.UninstallString -match '\{[0-9a-f-]{36}\}') {
                $Matches[0]
            }
            [pscustomobject]@{
                Name        = if ($name) { $name } else { 'TeamViewer' }
                PackageId   = $packageId
                VersionText = $app.DisplayVersion
                Executable  = $path
                IsMsi       = $isMsi
                Scope       = $record.Scope
                ProductCode = $productCode
                RegistryPath = $app.PSPath
            }
        }
    )

    $extraFiles = @(Get-TeamViewerMachineFiles | Sort-Object -Unique | Where-Object {
        $apps.Executable -notcontains $_
    })
    if ($apps.Count -eq 1 -and $apps[0].Scope -eq 'Machine registry' -and -not $apps[0].Executable -and
        $extraFiles.Count -eq 1) {
        $apps[0].Executable = $extraFiles[0]
        $extraFiles = @()
    }

    $apps
    foreach ($path in $extraFiles) {
        [pscustomobject]@{
            Name        = 'TeamViewer (edition unconfirmed)'
            PackageId   = $null
            VersionText = $null
            Executable  = $path
            IsMsi       = $false
            Scope       = 'Windows service or installed executable'
        }
    }
}

function Get-TeamViewerVersion {
    param([object[]]$Apps)

    if (-not $Apps) { return }
    $versions = foreach ($app in $Apps) {
        $version = if ($app.Executable) { Get-ExecutableVersion $app.Executable }
        if (-not $version) { $version = ConvertTo-AppVersion $app.VersionText }
        if (-not $version) { return }
        $version
    }
    $versions | Sort-Object | Select-Object -First 1
}

function Write-TeamViewerDetectedResult {
    param($App)

    Write-StepMessage "$($App.Name) | Reading the installed version."
    $version = Get-TeamViewerVersion @($App)
    $displayVersion = if ($version) { $version } else { 'UNKNOWN' }
    $latest = 'Not checked'
    if ($App.PackageId) {
        try {
            $latest = Get-LatestTeamViewerVersion $App.PackageId
        }
        catch {
            $latest = 'Unavailable'
            Write-StepMessage "$($App.Name) | Latest stable version lookup failed. $($_.Exception.Message)" 'WARNING'
        }
    }
    $detail = "Detected via: $($App.Scope)"
    $detail += if ($App.IsMsi) {
        ' | MSI: update through your managed TeamViewer deployment.'
    }
    elseif ($App.Scope -eq 'User registry') {
        ' | Per-user installation: update in the user context or through your managed deployment.'
    }
    elseif ($App.PackageId) {
        ' | An overlapping installation needs review before updating via WinGet.'
    }
    else {
        ' | Confirm Host or Full Client before updating through your managed deployment.'
    }
    $status = if ($version -and $version -ge $MinimumTeamViewerVersion) { 'COMPLIANT' } else { 'ACTION REQUIRED' }
    New-Result $App.Name $status "$detail | Minimum fixed version: $MinimumTeamViewerVersion" `
        -InstalledVersion $displayVersion -LatestStableVersion $latest
}

function Get-LatestTeamViewerVersion {
    param([string]$PackageId)

    Write-StepMessage "TeamViewer | Checking the publisher's latest Windows release."
    try {
        $page = Invoke-WebRequest -Uri 'https://www.teamviewer.com/en/download/portal/windows/' -UseBasicParsing -TimeoutSec 20
        $content = [Net.WebUtility]::HtmlDecode(($page.Content -replace '<[^>]+>', ' '))
        if ($content -match '(?i)\bCurrent\s+version\s*:\s*(?<Version>\d+\.\d+\.\d+(?:\.\d+)?)') {
            return (ConvertTo-AppVersion $Matches.Version)
        }
    }
    catch {
        Write-StepMessage "TeamViewer | Publisher release lookup failed. $($_.Exception.Message)" 'WARNING'
    }

    Write-StepMessage 'TeamViewer | Checking the WinGet catalog for the latest stable release instead.'
    $catalogPath = 'manifests/t/TeamViewer/TeamViewer'
    if ($PackageId -eq 'TeamViewer.TeamViewer.Host') { $catalogPath += '/Host' }
    $uri = "https://api.github.com/repos/microsoft/winget-pkgs/contents/$catalogPath"
    $entries = Invoke-RestMethod -Uri $uri -Headers @{ Accept = 'application/vnd.github+json' } -UserAgent 'Security-Remediation' -UseBasicParsing -TimeoutSec 20
    $latest = $entries | Where-Object { $_.type -eq 'dir' -and $_.name -match '^\d+\.\d+\.\d+(?:\.\d+)?$' } |
        ForEach-Object { ConvertTo-AppVersion $_.name } | Sort-Object -Descending | Select-Object -First 1
    if (-not $latest) { throw 'Could not determine the latest TeamViewer release.' }
    return $latest
}

function Get-TeamViewerMsiArchitecture {
    param($App)

    if ($App.Executable) { return (Get-PeArchitecture $App.Executable) }
    if ($App.RegistryPath -match '\\WOW6432Node\\' -or -not [Environment]::Is64BitOperatingSystem) {
        return 'x86'
    }
    if ($App.RegistryPath) {
        switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { return 'x64' }
            'ARM64' { return 'arm64' }
        }
    }
    throw 'Could not confirm the installed TeamViewer MSI architecture.'
}

function Get-MsiRows {
    param($Database, [string]$Query, [int]$ColumnCount)

    $view = $Database.OpenView($Query)
    try {
        $null = $view.Execute()
        while ($null -ne ($record = $view.Fetch())) {
            try {
                $values = for ($column = 1; $column -le $ColumnCount; $column++) {
                    [string]$record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, @($column))
                }
                ,@($values)
            }
            finally {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($record)
            }
        }
    }
    finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view)
    }
}

function Test-MsiUpgradeRange {
    param($Rule, [version]$InstalledVersion, [string]$InstalledLanguage)

    $attributes = [int]$Rule[4]
    if ($attributes -band 0x002) { return $false }
    $minimum = ConvertTo-AppVersion $Rule[1]
    $maximum = ConvertTo-AppVersion $Rule[2]
    if ($minimum -and ($InstalledVersion -lt $minimum -or
        ($InstalledVersion -eq $minimum -and -not ($attributes -band 0x100)))) { return $false }
    if ($maximum -and ($InstalledVersion -gt $maximum -or
        ($InstalledVersion -eq $maximum -and -not ($attributes -band 0x200)))) { return $false }
    if ($Rule[3]) {
        $listedLanguage = ($Rule[3] -split ',') -contains $InstalledLanguage
        if ($attributes -band 0x400) { return (-not $listedLanguage) }
        return $listedLanguage
    }
    return $true
}

function Get-TeamViewerMsiUpgrade {
    param([string]$Path, $App, [version]$Latest)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $publisher = if ($signature.SignerCertificate) {
        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    }
    if ($signature.Status -ne 'Valid' -or $publisher -notmatch '^TeamViewer(?: Germany GmbH| AG| SE| GmbH)$') {
        throw "The TeamViewer MSI does not have a valid TeamViewer signature: $($signature.Status), $publisher."
    }

    if (-not $App.ProductCode) { throw 'The registered TeamViewer MSI product code could not be read.' }
    $installer = $null
    $database = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.OpenDatabase($Path, 0)
        $properties = @{}
        # The quote character delimits identifiers in Windows Installer SQL.
        $quote = [char]96
        $propertyQuery = 'SELECT {0}Property{0}, {0}Value{0} FROM {0}Property{0}' -f $quote
        foreach ($row in (Get-MsiRows $database $propertyQuery 2)) {
            $properties[$row[0]] = $row[1]
        }
        $packageVersion = ConvertTo-AppVersion $properties.ProductVersion
        $isHost = $App.PackageId -eq 'TeamViewer.TeamViewer.Host'
        if ($properties.ProductName -notmatch '\bTeamViewer\b' -or
            ($properties.ProductName -match '\bHost\b') -ne $isHost -or
            -not $packageVersion -or $packageVersion -lt $Latest -or -not $properties.ProductCode) {
            throw "Unexpected TeamViewer MSI: $($properties.ProductName), version $($properties.ProductVersion)."
        }

        $registryVersion = $installer.GetType().InvokeMember(
            'ProductInfo', 'GetProperty', $null, $installer, @($App.ProductCode, 'VersionString'))
        $installed = ConvertTo-AppVersion $registryVersion
        if (-not $installed) { throw 'Could not read the installed TeamViewer MSI product version.' }
        $installed = [version]::new($installed.Major, $installed.Minor, $installed.Build, 0)
        $language = $installer.GetType().InvokeMember(
            'ProductInfo', 'GetProperty', $null, $installer, @($App.ProductCode, 'Language'))

        $sequenceQuery = 'SELECT {0}Action{0} FROM {0}InstallExecuteSequence{0}' -f $quote
        $actions = Get-MsiRows $database $sequenceQuery 1 | ForEach-Object { $_[0] }
        if ($actions -notcontains 'RemoveExistingProducts') {
            throw 'The downloaded TeamViewer package has no Windows Installer major upgrade action.'
        }
        $upgradeQuery = 'SELECT {0}UpgradeCode{0}, {0}VersionMin{0}, {0}VersionMax{0}, {0}Language{0}, {0}Attributes{0} FROM {0}Upgrade{0}' -f $quote
        foreach ($rule in (Get-MsiRows $database $upgradeQuery 5)) {
            if (-not (Test-MsiUpgradeRange $rule $installed $language)) { continue }
            $related = $installer.GetType().InvokeMember(
                'RelatedProducts', 'GetProperty', $null, $installer, @($rule[0]))
            try {
                $total = $related.GetType().InvokeMember('Count', 'GetProperty', $null, $related, $null)
                for ($index = 0; $index -lt $total; $index++) {
                    $code = $related.GetType().InvokeMember('Item', 'GetProperty', $null, $related, @($index))
                    if ($code -eq $App.ProductCode) {
                        return [pscustomobject]@{ ProductCode = $properties.ProductCode; Version = $packageVersion }
                    }
                }
            }
            finally {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($related)
            }
        }
        throw "The signed $($properties.ProductName) MSI does not declare an in-place upgrade for the installed product ($installed)."
    }
    finally {
        if ($database) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database) }
        if ($installer) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer) }
    }
}

function Update-TeamViewerMsi {
    param($App)

    $versions = @{ InstalledVersion = 'Unknown'; LatestStableVersion = 'Unavailable' }
    try {
        Write-StepMessage "$($App.Name) | Reading the installed MSI version."
        $before = Get-TeamViewerVersion @($App)
        if ($before) { $versions.InstalledVersion = $before }
        $latest = Get-LatestTeamViewerVersion $App.PackageId
        $versions.LatestStableVersion = $latest
        Write-StepMessage "$($App.Name) | Installed version $($versions.InstalledVersion). Latest stable version $latest."
        if ($latest -lt $MinimumTeamViewerVersion) {
            throw "The latest MSI must be at least $MinimumTeamViewerVersion."
        }
        if ($before -and $before -ge $latest) {
            New-Result $App.Name 'UP TO DATE' 'The latest stable MSI version is already installed.' @versions
            return
        }
        if ($CheckOnly) {
            New-Result $App.Name 'ACTION REQUIRED' 'A newer MSI is available. Check-only mode.' @versions
            return
        }

        Write-StepMessage "$($App.Name) | Identifying the installed MSI architecture."
        $architecture = Get-TeamViewerMsiArchitecture $App
        if ($architecture -notin @('x86', 'x64', 'arm64')) {
            throw "No TeamViewer MSI archive is known for architecture $architecture."
        }
        $versionTag = if ($latest.Revision) { $latest.ToString(4) } else { $latest.ToString(3) }
        $edition = if ($App.PackageId -eq 'TeamViewer.TeamViewer.Host') { '_Host' } else { '' }
        $suffix = if ($architecture -eq 'x86') { '' } else { "_$architecture" }
        $archiveName = 'Update_msi{0}_{1}{2}.zip' -f $edition, $versionTag, $suffix
        $uri = "https://download.teamviewer.com/download/version_$($latest.Major)x/update/$archiveName"
        $work = Join-Path ([IO.Path]::GetTempPath()) ("TeamViewer-MSI-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $work -ItemType Directory
        try {
            $archivePath = Join-Path $work $archiveName
            $msiPath = Join-Path $work 'update.msi'
            Write-StepMessage "$($App.Name) | Downloading $archiveName."
            Invoke-WebRequest -Uri $uri -OutFile $archivePath -UseBasicParsing -TimeoutSec 180

            Write-StepMessage "$($App.Name) | Extracting update.msi."
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
            try {
                $entry = $archive.GetEntry('update.msi')
                if (-not $entry) { throw "No update.msi was found in $archiveName." }
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $msiPath)
            }
            finally {
                $archive.Dispose()
            }

            Write-StepMessage "$($App.Name) | Verifying the MSI signature and checking in-place upgrade compatibility."
            $package = Get-TeamViewerMsiUpgrade $msiPath $App $latest
            $arguments = '/i "{0}" /qn /norestart' -f $msiPath
            if ($App.Executable) {
                $directory = Split-Path -LiteralPath $App.Executable
                $arguments += ' INSTALLFOLDER="{0}"' -f $directory
            }
            Write-StepMessage "$($App.Name) | Installing the signed $architecture MSI silently. Active sessions may disconnect."
            $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
            if ($process.ExitCode -in @(1641, 3010)) {
                New-Result $App.Name 'PENDING' "MSI exit code $($process.ExitCode). Installed version is the last verified value. Recheck after restart." @versions -Restart
                return
            }
            if ($process.ExitCode -ne 0) { throw "MSI installer exit code: $($process.ExitCode)." }

            Write-StepMessage "$($App.Name) | MSI exited with code 0. Checking the installed version and replacement of the old MSI."
            $afterInventory = @(Get-TeamViewerInventory | Where-Object {
                $_.IsMsi -and $_.Scope -eq 'Machine registry' -and $_.PackageId -eq $App.PackageId
            })
            $installedApp = @($afterInventory | Where-Object { $_.ProductCode -eq $package.ProductCode })
            $after = Get-TeamViewerVersion $installedApp
            if ($after) { $versions.InstalledVersion = $after }
            if (-not $after -or $after -lt $package.Version -or
                ($App.ProductCode -ne $package.ProductCode -and $afterInventory.ProductCode -contains $App.ProductCode)) {
                throw "MSI returned success, but the new version and replacement of the old MSI could not be verified."
            }
            New-Result $App.Name 'UPDATED' "Verified TeamViewer MSI update ($architecture)." @versions -PreviousVersion $before
        }
        finally {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        New-Result $App.Name 'FAILED' $_.Exception.Message @versions
    }
}

function Repair-TeamViewer {
    param([string]$WinGet, [string[]]$Arguments)

    Write-StepMessage 'TeamViewer | Retrying with WinGet. Active sessions may disconnect.' 'WARNING'
    $running = @(Get-Service | Where-Object {
        $_.Name -like 'TeamViewer*' -and $_.Status -eq 'Running'
    })
    $restoreFailures = @()
    try {
        foreach ($service in $running) {
            Write-StepMessage "TeamViewer | Stopping service $($service.Name) for the retry."
            Stop-Service -Name $service.Name
        }
        $result = Invoke-WinGet $WinGet $Arguments
    }
    finally {
        foreach ($service in $running) {
            try {
                Write-StepMessage "TeamViewer | Restarting service $($service.Name)."
                Start-Service -Name $service.Name
            }
            catch {
                $restoreFailures += $service.Name
                Write-StepMessage "TeamViewer | Could not restart service $($service.Name). $($_.Exception.Message)" 'WARNING'
            }
        }
    }
    if ($restoreFailures) {
        throw ('TeamViewer services require manual recovery: ' + ($restoreFailures -join ', '))
    }
    return $result
}

function Update-TeamViewer {
    $families = [ordered]@{
        'TeamViewer.TeamViewer.Host' = 'TeamViewer Host'
        'TeamViewer.TeamViewer'      = 'TeamViewer Full Client'
    }
    Write-StepMessage 'TeamViewer | Looking for installed copies in the registry, services and application folders.'
    $inventory = @(Get-TeamViewerInventory)
    if (-not $inventory) {
        New-Result 'TeamViewer' 'SKIPPED' 'No TeamViewer installation found in the registry, services or default folders.' `
            -InstalledVersion 'Not installed' -LatestStableVersion 'Not checked'
        return
    }

    $manual = @($inventory | Where-Object { $_.IsMsi -or $_.Scope -ne 'Machine registry' -or -not $_.PackageId })
    foreach ($app in $manual) {
        try {
            if ($app.IsMsi -and $app.Scope -eq 'Machine registry' -and $app.PackageId) {
                Update-TeamViewerMsi $app
            }
            else {
                Write-TeamViewerDetectedResult $app
            }
        }
        catch {
            New-Result $app.Name 'FAILED' $_.Exception.Message -InstalledVersion 'Unknown' -LatestStableVersion 'Not checked'
        }
    }

    foreach ($family in $families.GetEnumerator()) {
        $packageId = $family.Key
        $name = $family.Value
        $apps = @($inventory | Where-Object { $_.PackageId -eq $packageId -and $_ -notin $manual })
        if (-not $apps) { continue }
        $overlappingApp = $manual | Where-Object {
            $_.PackageId -eq $packageId -or ($_.IsMsi -and -not $_.PackageId)
        } | Select-Object -First 1
        if ($overlappingApp) {
            foreach ($app in $apps) { Write-TeamViewerDetectedResult $app }
            continue
        }

        $versions = @{ InstalledVersion = 'Unknown'; LatestStableVersion = 'Unavailable' }
        try {
            Write-StepMessage "$name | Reading the installed version."
            $before = Get-TeamViewerVersion $apps
            if ($before) { $versions.InstalledVersion = $before }
            Write-StepMessage "$name | Checking WinGet for the latest stable package."
            $winget = (Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1).Source
            if (-not $winget) { throw 'WinGet is unavailable for the current account.' }

            $selection = @('--id', $packageId, '--exact', '--source', 'winget',
                '--disable-interactivity', '--accept-source-agreements')
            $catalog = Invoke-WinGet $winget (@('show', '--versions') + $selection)
            $latest = $null
            if ($catalog.Code -eq '0x00000000') {
                $latest = $catalog.Output -split '[\r\n]+' |
                    Where-Object { $_ -match '^\s*\d+(?:\.\d+){1,3}\s*$' } |
                    ForEach-Object { ConvertTo-AppVersion $_ } |
                    Sort-Object -Descending | Select-Object -First 1
            }
            if (-not $latest) {
                $message = if ($catalog.Error) { " $($catalog.Error.Trim())" }
                throw "WinGet could not verify the latest stable version ($($catalog.Code)).$message"
            }

            $versions.LatestStableVersion = $latest
            Write-StepMessage "$name | Installed version $($versions.InstalledVersion). Latest stable version $latest."
            if ($latest -lt $MinimumTeamViewerVersion -and (-not $before -or $before -lt $MinimumTeamViewerVersion)) {
                throw "WinGet does not offer the minimum fixed version ($MinimumTeamViewerVersion)."
            }
            if ($before -and $before -ge $latest) {
                New-Result $name 'UP TO DATE' 'The latest stable package version is already installed.' @versions
                continue
            }
            if ($CheckOnly) {
                New-Result $name 'ACTION REQUIRED' 'A newer release is available. Check-only mode.' @versions
                continue
            }

            Write-StepMessage "$name | Downloading and installing silently through WinGet. Active sessions may disconnect."
            $options = $selection + @('--silent', '--accept-package-agreements')
            $update = Invoke-WinGet $winget (@('upgrade', '--include-unknown') + $options)
            Write-StepMessage "$name | WinGet returned $($update.Code). Checking the installed version again."
            $after = Get-TeamViewerVersion @(Get-TeamViewerInventory | Where-Object { $_.PackageId -eq $packageId -and $_.Scope -eq 'Machine registry' })
            if ($after) { $versions.InstalledVersion = $after }

            # Retry a failed package match or unsupported upgrade only when a newer release is known.
            if ($before -and $before -lt $latest -and (-not $after -or $after -lt $latest) -and
                $update.Code -in @('0x00000000', '0x8A150014', '0x8A150114')) {
                $message = if ($update.Error) { " $($update.Error.Trim())" }
                Write-StepMessage "$name | The first attempt did not reach the target version ($($update.Code)).$message" 'WARNING'
                $update = Repair-TeamViewer $winget (@('install', '--force') + $options)
                Write-StepMessage "$name | WinGet retry returned $($update.Code). Checking the installed version again."
                $after = Get-TeamViewerVersion @(Get-TeamViewerInventory | Where-Object { $_.PackageId -eq $packageId -and $_.Scope -eq 'Machine registry' })
                if ($after) { $versions.InstalledVersion = $after }
            }

            if ($update.Code -in @('0x8A150109', '0x8A15010A', '0x8A15010B')) {
                New-Result $name 'PENDING' "WinGet returned $($update.Code). Restart and recheck." @versions -Restart
            }
            elseif ($after -and $after -ge $latest -and $update.Code -in @('0x00000000', '0x8A15002B')) {
                New-Result $name 'UPDATED' 'Verified WinGet update.' @versions -PreviousVersion $before
            }
            else {
                $message = if ($update.Error) { " $($update.Error.Trim())" }
                throw "Update not verified. WinGet: $($update.Code). Actual: $after. Expected: $latest.$message"
            }
        }
        catch {
            New-Result $name 'FAILED' $_.Exception.Message @versions
        }
    }
}

function Get-DesktopUpdateInventory {
    param([ValidateSet('pgAdmin 4', 'JetBrains')][string]$Family)

    $jetBrainsProducts = [ordered]@{
        'IntelliJ IDEA' = @('IntelliJIDEA', 'IIU', 'idea')
        'PyCharm'      = @('PyCharm', 'PCP', 'pycharm')
        'CLion'        = @('CLion', 'CL', 'clion')
        'DataGrip'     = @('DataGrip', 'DG', 'datagrip')
        'DataSpell'    = @('DataSpell', 'DS', 'dataspell')
        'GoLand'       = @('GoLand', 'GO', 'goland')
        'PhpStorm'     = @('PhpStorm', 'PS', 'phpstorm')
        'Rider'        = @('Rider', 'RD', 'rider')
        'RubyMine'     = @('RubyMine', 'RM', 'rubymine')
        'RustRover'    = @('RustRover', 'RR', 'rustrover')
        'WebStorm'     = @('WebStorm', 'WS', 'webstorm')
        'MPS'          = @('MPS', 'MPS')
        'Aqua'         = @('Aqua', '')
        'Gateway'      = @('Gateway', 'GW', 'gateway')
        'Writerside'   = @('Writerside', '')
        'dotPeek'      = @('dotPeek', 'DPK')
        'dotTrace'     = @('dotTrace', 'DP')
        'dotUltimate'  = @('dotUltimate', 'RSU')
        'ReSharper'    = @('ReSharper', 'RS')
    }

    foreach ($record in (Get-RegisteredAppEntries)) {
        $app = $record.Entry
        $displayName = ([string]$app.DisplayName).Trim()
        $version = ConvertTo-AppVersion $app.DisplayVersion
        $scope = if ($record.Scope -eq 'Machine registry') { 'machine' } else { 'user' }
        $otherUser = 'This installation belongs to another user. Run the update in that user context.'
        if ($Family -eq 'pgAdmin 4') {
            if ($displayName -notmatch '^pgAdmin\s+4(?:\s|$)') { continue }
            if (-not $version) { $version = ConvertTo-AppVersion $displayName }
            [pscustomobject]@{
                Name         = 'pgAdmin 4'
                DisplayName  = $displayName
                PackageId    = 'PostgreSQL.pgAdmin'
                Scope        = $scope
                Version      = $version
                Restriction  = if (-not $record.CurrentContext) { $otherUser }
            }
            continue
        }

        $name = $null
        $product = $null
        $isToolbox = $displayName -match '^JetBrains\s+Toolbox(?:\s|$)' -or
            ($displayName -match '^Toolbox(?:\s|$)' -and $app.Publisher -match '^JetBrains\b')
        if ($isToolbox) {
            $name = 'JetBrains Toolbox'
            $product = @('Toolbox', 'TBA', 'jetbrains-toolbox')
        }
        else {
            foreach ($item in $jetBrainsProducts.GetEnumerator()) {
                $pattern = '^(?:JetBrains\s+)?{0}(?:[\s(-]|$)' -f [regex]::Escape($item.Key)
                if ($displayName -match $pattern) {
                    $name = $item.Key
                    $product = $item.Value
                    break
                }
            }
            if (-not $product) { continue }
        }

        $launcher = if ($product.Count -gt 2) { $product[2] }
        $toolboxManaged = -not $isToolbox -and (
            "$($app.InstallLocation) $($app.UninstallString) $($app.DisplayIcon) $($app.PSChildName)" -match
                '(?:\\JetBrains\\Toolbox\\|jetbrains-toolbox\.exe)' -or
            ($scope -eq 'user' -and "$($app.InstallLocation) $($app.DisplayIcon)" -match '\\AppData\\Local\\Programs\\' -and
                $app.UninstallString -notmatch '\\bin\\uninstall\.exe')
        )

        $folder = [Environment]::ExpandEnvironmentVariables(([string]$app.InstallLocation).Trim().Trim('"'))
        $folder = $folder.Replace('/', '\').TrimEnd('\')
        if (-not $folder -and $record.CurrentContext) {
            foreach ($command in @($app.UninstallString, $app.DisplayIcon)) {
                $command = [Environment]::ExpandEnvironmentVariables([string]$command)
                if ($command -match '^\s*"?(?<Folder>[a-z]:\\[^"\r\n]*?)\\bin\\[^\\"]+?\.exe(?=["\s,]|$)') {
                    $folder = $Matches.Folder
                    break
                }
            }
        }

        $executable = $null
        $productInfoVersion = $null
        $isPreview = $displayName -match '\b(?:EAP|Preview|Beta|Nightly|RC|Canary|Alpha)\s*\d*\b|Release Candidate'
        if ($launcher -and $folder -match '^[a-z]:\\' -and $record.CurrentContext) {
            try {
                $candidates = @()
                if (-not $isToolbox) {
                    $infoPath = Join-Path $folder 'product-info.json'
                    if (Test-Path -LiteralPath $infoPath -PathType Leaf) {
                        $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
                        $productInfoVersion = ConvertTo-AppVersion $info.version
                        $isPreview = $isPreview -or ([string]$info.versionSuffix -match '\b(?:EAP|Preview|Beta|Nightly|RC|Canary|Alpha)\s*\d*\b|Release Candidate')
                        $candidates = @($info.launch | Where-Object {
                            $_.os -eq 'Windows' -and $_.launcherPath -match '^bin[\\/][\w.-]+\.exe$'
                        } | Select-Object -ExpandProperty launcherPath -Unique)
                    }
                    $candidates += @(('bin\{0}64.exe' -f $launcher), "bin\$launcher.exe")
                }
                else { $candidates = @("bin\$launcher.exe", "$launcher.exe") }
                foreach ($relativePath in $candidates) {
                    $path = Join-Path $folder $relativePath
                    if (Test-Path -LiteralPath $path -PathType Leaf) { $executable = $path; break }
                }
                if ($isToolbox -and $executable) {
                    $fileVersion = Get-ExecutableVersion $executable
                    if ($fileVersion -and $version -and $fileVersion.Major -eq $version.Major -and
                        $fileVersion.Minor -eq $version.Minor -and $fileVersion -gt $version) { $version = $fileVersion }
                }
            }
            catch {
                Write-StepMessage "$name | Could not read installed files in $folder. $($_.Exception.Message)" 'WARNING'
            }
        }

        if (-not $isToolbox) {
            if ($productInfoVersion) { $version = $productInfoVersion }
            elseif ($launcher) {
                $displayVersion = ConvertTo-AppVersion $displayName
                if ($displayVersion) { $version = $displayVersion }
                elseif ($version -and $version.Major -lt 2000) { $version = $null }
            }
        }
        elseif (-not $version) { $version = ConvertTo-AppVersion $displayName }

        $restriction = ''
        $management = ''
        if ($isPreview) { $restriction = 'Pre-release installation. Select the Release channel in the product updater.' }
        elseif (-not $record.CurrentContext) { $restriction = $otherUser }
        elseif ($toolboxManaged) {
            $management = 'Toolbox'
            $restriction = 'This IDE is managed by JetBrains Toolbox. Use the Release channel and enable automatic updates in Toolbox.'
        }
        elseif ($app.WindowsInstaller -eq 1 -or $app.UninstallString -match '\bmsiexec(?:\.exe)?\b') {
            $restriction = 'Managed MSI installation. Update it through its original deployment.'
        }
        elseif (-not $launcher) { $restriction = 'Use the original JetBrains installer or deployment for this product.' }
        elseif ($isToolbox -and $scope -ne 'user') {
            $restriction = 'This Toolbox App registration is machine-wide. Update it through its original deployment.'
        }

        [pscustomobject]@{
            Name        = $name
            DisplayName = $displayName
            PackageId   = "JetBrains.$($product[0])"
            ProductCode = $product[1]
            Launcher    = $launcher
            IsToolbox   = $isToolbox
            Scope       = $scope
            Folder      = $folder
            Executable  = $executable
            ProductInfoVersion = $productInfoVersion
            Version     = $version
            Management  = $management
            Restriction = $restriction
        }
    }
}

function Update-PgAdmin {
    Write-StepMessage 'pgAdmin 4 | Looking for registered installations.'
    $name = 'pgAdmin 4'
    $inventory = @(Get-DesktopUpdateInventory $name)
    if (-not $inventory) {
        New-Result $name 'SKIPPED' 'No registered pgAdmin 4 installation found.' -InstalledVersion 'Not installed' -LatestStableVersion 'Not checked'
        return
    }

    Write-StepMessage 'pgAdmin 4 | Checking the publisher for the latest stable release.'
    $tag = 'Unavailable'
    $latest = $null
    $releaseError = $null
    try {
        $catalog = Invoke-RestMethod -Uri 'https://www.pgadmin.org/versions.json' -UseBasicParsing -TimeoutSec 30
        $releaseTag = [string]$catalog.pgadmin4.version
        if ($releaseTag -notmatch '^\d+(?:\.\d+){1,3}$') { throw 'The publisher did not return a stable pgAdmin 4 version.' }
        $latest = ConvertTo-AppVersion $releaseTag
        if (-not $latest) { throw 'Could not read the stable pgAdmin 4 version from the publisher.' }
        $tag = $releaseTag
    }
    catch {
        $releaseError = $_.Exception.Message
    }

    foreach ($app in ($inventory | Where-Object Restriction)) {
        New-Result $name 'ACTION REQUIRED' $app.Restriction -InstalledVersion $app.Version -LatestStableVersion $tag
    }

    $installerPath = Join-Path ([IO.Path]::GetTempPath()) ("pgadmin4-{0}.exe" -f [guid]::NewGuid())
    $verifiedInstaller = $false
    $installerRunning = $false
    try {
        foreach ($scope in @('machine', 'user')) {
            $apps = @($inventory | Where-Object { $_.Scope -eq $scope -and -not $_.Restriction })
            if (-not $apps) { continue }

            $installed = @($apps.Version | Where-Object { $_ } | Sort-Object -Unique)
            $versions = @{
                InstalledVersion = if ($installed) { $installed -join ', ' } else { 'Unknown' }
                LatestStableVersion = $tag
            }
            try {
                if ($releaseError) { throw "Publisher release lookup failed. $releaseError" }
                Write-StepMessage "$name | Installed version $($versions.InstalledVersion). Latest stable version $tag ($scope scope)."
                if ($apps | Where-Object { -not $_.Version }) {
                    New-Result $name 'ACTION REQUIRED' "Could not verify every registered pgAdmin version ($scope scope)." @versions
                    continue
                }
                if ($installed[0] -ge $latest) {
                    New-Result $name 'UP TO DATE' "All detected copies meet the latest stable version ($scope scope)." @versions
                    continue
                }
                if ($installed[-1] -ge $latest) {
                    New-Result $name 'ACTION REQUIRED' "The stable release is present, but an older copy is still registered ($scope scope)." @versions
                    continue
                }
                if ($CheckOnly) {
                    New-Result $name 'ACTION REQUIRED' "Stable update available for the $scope installation. Check-only mode." @versions
                    continue
                }
                if ($installerRunning) {
                    New-Result $name 'PENDING' 'Update deferred while a pgAdmin installer is still running.' @versions
                    continue
                }

                if (-not $verifiedInstaller) {
                    $url = "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v$tag/windows/pgadmin4-$tag-x64.exe"
                    Write-StepMessage "$name | Downloading the official $tag installer from PostgreSQL."
                    Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -TimeoutSec 600
                    Write-StepMessage "$name | Verifying the official installer signature."
                    $signature = Get-AuthenticodeSignature -LiteralPath $installerPath
                    $publisher = if ($signature.SignerCertificate) {
                        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
                    }
                    if ($signature.Status -ne 'Valid' -or $publisher -ne 'Open Source Developer, David John Page') {
                        throw "Unexpected pgAdmin installer signature. Status: $($signature.Status). Signer: $publisher."
                    }
                    $verifiedInstaller = $true
                }

                $logPath = Join-Path ([IO.Path]::GetTempPath()) ("pgadmin4-update-{0}.log" -f [guid]::NewGuid())
                $scopeOption = if ($scope -eq 'machine') { '/ALLUSERS' } else { '/CURRENTUSER' }
                $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /SP- /NORESTART /RESTARTEXITCODE=3010 /NOCLOSEAPPLICATIONS /NORESTARTAPPLICATIONS {0} /LOG="{1}"' -f $scopeOption, $logPath
                Write-StepMessage "$name | Installing $tag silently ($scope scope)."
                $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
                $installerRunning = $true
                try {
                    for ($elapsed = 15; $elapsed -le 600; $elapsed += 15) {
                        if ($process.WaitForExit(15000)) {
                            $code = $process.ExitCode
                            $installerRunning = $false
                            break
                        }
                        if ($elapsed -lt 600) {
                            Write-StepMessage "$name | Waiting for the installer (PID $($process.Id), $elapsed seconds)."
                        }
                    }
                    if ($installerRunning) {
                        New-Result $name 'PENDING' "Installer PID $($process.Id) is still running after 10 minutes. Log: $logPath" @versions
                        continue
                    }
                }
                finally {
                    $process.Dispose()
                }

                Write-StepMessage "$name | Installer returned exit code $code."
                if ($code -eq 3010) {
                    New-Result $name 'PENDING' "Recheck after restart. Installer log: $logPath" @versions -Restart
                    continue
                }
                if ($code -ne 0) { throw "Installer exit code $code. Log: $logPath" }

                Write-StepMessage "$name | Verifying the installed version in the $scope scope."
                $after = @(Get-DesktopUpdateInventory $name | Where-Object { $_.Scope -eq $scope -and -not $_.Restriction })
                $afterVersions = @($after.Version | Where-Object { $_ } | Sort-Object -Unique)
                $previous = $versions.InstalledVersion
                $versions.InstalledVersion = if ($afterVersions) { $afterVersions -join ', ' } else { 'Unknown' }
                if (-not $afterVersions -or $afterVersions[-1] -lt $latest) {
                    throw "Could not verify the stable pgAdmin release after installation. Log: $logPath"
                }
                if ($afterVersions[0] -lt $latest -or ($after | Where-Object { -not $_.Version })) {
                    New-Result $name 'ACTION REQUIRED' "The stable release was verified, but older or unverified copies remain ($scope scope). Log: $logPath" @versions -PreviousVersion $previous
                    continue
                }
                Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
                New-Result $name 'UPDATED' "Stable version verified in the $scope scope." @versions -PreviousVersion $previous
            }
            catch {
                New-Result $name 'FAILED' $_.Exception.Message @versions
            }
        }
    }
    finally {
        if (-not $installerRunning) {
            Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-JetBrainsStableReleases {
    param([string[]]$ProductCodes)

    $codes = [uri]::EscapeDataString(($ProductCodes -join ','))
    $api = "https://data.services.jetbrains.com/products/releases?code=$codes&latest=true&type=release"
    $catalog = Invoke-RestMethod -Uri $api -UseBasicParsing -TimeoutSec 30
    $releases = @{}
    foreach ($productCode in $ProductCodes) {
        $entry = $catalog.PSObject.Properties[$productCode]
        if (-not $entry) { continue }
        foreach ($release in $entry.Value) {
            $tag = [string]$release.version
            if ($release.type -ne 'release' -or $tag -notmatch '^\d+(?:\.\d+){1,3}$') { continue }
            $target = ConvertTo-AppVersion $tag
            if (-not $target) { continue }
            if ($productCode -eq 'TBA' -and $release.build -match '^\d+(?:\.\d+){2,3}$') {
                $build = ConvertTo-AppVersion $release.build
                if ($build -ge $target -and $build.Major -eq $target.Major -and $build.Minor -eq $target.Minor) {
                    $target = $build
                }
            }
            if (-not $releases.ContainsKey($productCode) -or $target -gt $releases[$productCode].Version) {
                $releases[$productCode] = [pscustomobject]@{ Tag = $tag; Version = $target; Downloads = $release.downloads }
            }
        }
    }
    return $releases
}

function Save-JetBrainsInstaller {
    param($Download, [string]$TargetPath)

    foreach ($address in @($Download.link, $Download.checksumLink)) {
        $url = $null
        if (-not [uri]::TryCreate([string]$address, [UriKind]::Absolute, [ref]$url) -or
            $url.Scheme -ne 'https' -or $url.Host -notin @('download.jetbrains.com', 'download-cdn.jetbrains.com') -or
            -not $url.IsDefaultPort -or $url.UserInfo) {
            throw 'JetBrains did not return an approved HTTPS installer or checksum URL.'
        }
    }
    $installerUri = [uri]$Download.link
    if ($installerUri.AbsolutePath -notmatch '\.exe$' -or "$($Download.link).sha256" -ne $Download.checksumLink) {
        throw 'The JetBrains release does not provide a matching Windows EXE and SHA-256 checksum.'
    }

    $checksum = Invoke-WebRequest -Uri $Download.checksumLink -UseBasicParsing -TimeoutSec 30
    $checksumText = if ($checksum.Content -is [byte[]]) {
        [Text.Encoding]::ASCII.GetString($checksum.Content)
    } else { [string]$checksum.Content }
    if ($checksumText.Trim() -notmatch '^(?<Hash>[0-9a-f]{64})(?:[ \t]+\*?[^\r\n]+)?$') {
        throw 'Could not read the publisher SHA-256 checksum.'
    }
    $expectedHash = $Matches.Hash
    Invoke-WebRequest -Uri $installerUri -OutFile $TargetPath -UseBasicParsing -TimeoutSec 1200
    if ($Download.size -gt 0 -and (Get-Item -LiteralPath $TargetPath).Length -ne $Download.size) {
        throw 'The downloaded JetBrains installer is incomplete or has an unexpected size.'
    }
    if ((Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'The JetBrains installer SHA-256 checksum did not match.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $TargetPath
    $publisher = if ($signature.SignerCertificate) {
        $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    }
    if ($signature.Status -ne 'Valid' -or $publisher -ne 'JetBrains s.r.o.') {
        throw "Unexpected installer signature. Status: $($signature.Status). Signer: $publisher."
    }
}

function Update-JetBrains {
    Write-StepMessage 'JetBrains | Looking for installed products, installation scope and management channel.'
    $inventory = @(Get-DesktopUpdateInventory 'JetBrains')
    if (-not $inventory) {
        New-Result 'JetBrains' 'SKIPPED' 'No supported registered products found.' -InstalledVersion 'Not installed' -LatestStableVersion 'Not checked'
        return
    }

    $catalog = @{}
    $catalogError = $null
    $codes = @($inventory | Where-Object ProductCode | Select-Object -ExpandProperty ProductCode -Unique)
    if ($codes) {
        Write-StepMessage 'JetBrains | Checking the publisher for stable Windows releases.'
        try { $catalog = Get-JetBrainsStableReleases $codes }
        catch { $catalogError = $_.Exception.Message }
    }

    # Group on a single non-null string for Windows PowerShell 5.1.
    $groups = $inventory | Group-Object { '{0}|{1}|{2}' -f $_.PackageId, $_.Scope, $_.Restriction }
    $installerRunning = $false
    foreach ($group in $groups) {
        $apps = @($group.Group)
        $app = $apps[0]
        $name = $app.Name
        $latest = $catalog[$app.ProductCode]
        $installed = @($apps.Version | Where-Object { $_ } | Sort-Object -Unique)
        $versions = @{
            InstalledVersion = if ($installed) { $installed -join ', ' } else { 'Unknown' }
            LatestStableVersion = if ($latest) { $latest.Tag } else { 'Unavailable' }
        }
        $workPath = $null
        $keepFiles = $false
        $logPath = $null
        try {
            Write-StepMessage "$name | Installed version $($versions.InstalledVersion). Latest stable version $($versions.LatestStableVersion) ($($app.Scope) scope)."
            if ($app.Restriction) {
                if ($app.Management -eq 'Toolbox' -and $latest -and $installed -and
                    $installed[0] -ge $latest.Version -and -not ($apps | Where-Object { -not $_.Version -or -not $_.Executable })) {
                    New-Result $name 'UP TO DATE' 'All detected Toolbox-managed copies meet the latest stable version.' @versions
                }
                else {
                    $reason = $app.Restriction
                    if ($catalogError) { $reason += " Stable release lookup failed. $catalogError" }
                    New-Result $name 'ACTION REQUIRED' $reason @versions
                }
                continue
            }
            if ($catalogError) { throw "Publisher release lookup failed. $catalogError" }
            if (-not $latest) { throw 'The publisher did not return a stable release for this product.' }

            $current = @($apps | Where-Object { $_.Executable -and $_.Version -ge $latest.Version })
            $needsAttention = @($apps | Where-Object {
                -not $_.Version -or -not $_.Executable -or $_.Version -lt $latest.Version
            })
            if ($current) {
                if ($needsAttention) {
                    New-Result $name 'ACTION REQUIRED' "The stable release is present. Older or unverified copies remain ($($app.Scope) scope)." @versions
                }
                else {
                    New-Result $name 'UP TO DATE' "All detected copies meet the latest stable version ($($app.Scope) scope)." @versions
                }
                continue
            }

            $source = $apps | Where-Object { $_.Executable -and $_.Version -and $_.Version -lt $latest.Version } |
                Sort-Object Version -Descending | Select-Object -First 1
            if (-not $source) {
                New-Result $name 'ACTION REQUIRED' 'Could not verify an installed launcher and version. Review the registered installation.' @versions
                continue
            }
            if ($CheckOnly) {
                New-Result $name 'ACTION REQUIRED' "Stable update available for the $($app.Scope) installation. Check-only mode." @versions
                continue
            }
            if ($installerRunning -or (Get-Process -Name 'jetbrains-remediation-*' -ErrorAction SilentlyContinue)) {
                New-Result $name 'PENDING' 'Update deferred while a JetBrains installer is still running.' @versions
                continue
            }

            $processNames = @($app.Launcher, ('{0}64' -f $app.Launcher))
            $processNames += @($apps.Executable | Where-Object { $_ } | ForEach-Object {
                [regex]::Match($_, '[^\\/]+(?=\.exe$)', 'IgnoreCase').Value
            } | Where-Object { $_ } | Select-Object -Unique)
            if (Get-Process -Name $processNames -ErrorAction SilentlyContinue) {
                New-Result $name 'ACTION REQUIRED' "Close $name in all sessions and rerun the update." @versions
                continue
            }

            $launcherArchitecture = Get-PeArchitecture $source.Executable
            if ($launcherArchitecture -eq 'x86' -and -not $app.IsToolbox) {
                New-Result $name 'ACTION REQUIRED' 'A legacy 32-bit IDE was detected. Use the original deployment to migrate it.' @versions
                continue
            }
            # The IDE installer checks the native processor even when the old launcher runs under emulation.
            $processor = Get-CimInstance -ClassName Win32_Processor -Property Architecture -OperationTimeoutSec 15 |
                Select-Object -First 1
            $architecture = switch ($processor.Architecture) {
                9  { 'x64' }
                12 { 'arm64' }
            }
            if (-not $architecture) { throw 'Could not verify the native Windows processor architecture.' }
            if (-not $app.IsToolbox -and $launcherArchitecture -ne $architecture) {
                New-Result $name 'ACTION REQUIRED' "The installed IDE uses $launcherArchitecture on $architecture. Use the original deployment to migrate it." @versions
                continue
            }
            $download = switch ($architecture) {
                'x64' { $latest.Downloads.windows }
                'arm64' { $latest.Downloads.windowsARM64 }
            }
            if (-not $download) {
                New-Result $name 'ACTION REQUIRED' "The publisher offers no supported $architecture installer." @versions
                continue
            }

            $destination = $null
            if (-not $app.IsToolbox) {
                $base = if ($app.Scope -eq 'machine') { $env:ProgramFiles } else { Join-Path $env:LOCALAPPDATA 'Programs' }
                $destination = (Join-Path $base ("JetBrains\{0} {1}" -f $name, $latest.Tag)).Replace('/', '\')
                if (Test-Path -LiteralPath $destination) {
                    New-Result $name 'ACTION REQUIRED' "Target folder already exists. Review it before retrying. Folder: $destination" @versions
                    continue
                }
            }

            $runId = [guid]::NewGuid().ToString('N')
            $workPath = Join-Path ([IO.Path]::GetTempPath()) "jetbrains-remediation-$runId"
            New-Item -Path $workPath -ItemType Directory | Out-Null
            $installerPath = Join-Path $workPath "jetbrains-remediation-$runId.exe"
            Write-StepMessage "$name | Downloading stable release $($latest.Tag) ($architecture) and verifying its SHA-256 and JetBrains signature."
            Save-JetBrainsInstaller $download $installerPath
            if (Get-Process -Name $processNames -ErrorAction SilentlyContinue) {
                New-Result $name 'ACTION REQUIRED' "$name opened during the download. Close it and rerun the update." @versions
                continue
            }

            $arguments = '/headless'
            if ($destination) {
                $logPath = "$workPath.log"
                $config = Join-Path $workPath 'silent.config'
                $mode = if ($app.Scope -eq 'machine') { 'admin' } else { 'user' }
                Set-Content -LiteralPath $config -Value "mode=$mode" -Encoding Ascii
                if (Test-Path -LiteralPath $destination) {
                    New-Result $name 'ACTION REQUIRED' "Target folder appeared during the download. Review it before retrying. Folder: $destination" @versions
                    continue
                }
                # NSIS requires the unquoted /D= path to be last, including paths with spaces.
                $arguments = '/S /CONFIG="{0}" /LOG="{1}" /D={2}' -f $config, $logPath, $destination
            }
            $logDetails = if ($logPath) { " Installer log: $logPath" } else { '' }
            Write-StepMessage "$name | Installing $($latest.Tag) silently ($($app.Scope) scope)."
            $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -WindowStyle Hidden -PassThru
            $installerRunning = $true
            $keepFiles = $true
            try {
                for ($elapsed = 30; $elapsed -le 1200; $elapsed += 30) {
                    if ($process.WaitForExit(30000)) {
                        $exitCode = $process.ExitCode
                        $installerRunning = $false
                        $keepFiles = $false
                        break
                    }
                    Write-StepMessage "$name | Waiting for installer PID $($process.Id) ($elapsed seconds)."
                }
                if ($keepFiles) {
                    New-Result $name 'PENDING' "Installer PID $($process.Id) is still running after 20 minutes. Recheck after it finishes.$logDetails" @versions
                    continue
                }
            }
            finally { $process.Dispose() }

            Write-StepMessage "$name | Installer returned exit code $exitCode. Verifying the installed version."
            if ($exitCode -in @(1641, 3010)) {
                New-Result $name 'PENDING' "Installer returned exit code $exitCode. Recheck after restart.$logDetails" @versions -Restart
                continue
            }
            if ($exitCode -ne 0) { throw "Installer returned exit code $exitCode.$logDetails" }

            $previous = $versions.InstalledVersion
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $after = @(Get-DesktopUpdateInventory 'JetBrains' | Where-Object {
                    $_.PackageId -eq $app.PackageId -and $_.Scope -eq $app.Scope -and -not $_.Restriction
                })
                $verified = @($after | Where-Object {
                    $_.Executable -and (
                        ($app.IsToolbox -and $_.Version -ge $latest.Version) -or
                        ($destination -and $_.Folder -eq $destination -and $_.ProductInfoVersion -ge $latest.Version)
                    )
                })
                if ($verified) { break }
                if ($attempt -lt 6) { Start-Sleep -Seconds 5 }
            }
            $afterVersions = @($after.Version | Where-Object { $_ } | Sort-Object -Unique)
            if ($afterVersions) { $versions.InstalledVersion = $afterVersions -join ', ' }
            if (-not $verified) {
                throw "The installer finished, but the expected registry entry, launcher and version could not be verified.$logDetails"
            }
            if ($after | Where-Object { -not $_.Executable -or -not $_.Version -or $_.Version -lt $latest.Version }) {
                New-Result $name 'ACTION REQUIRED' "The stable release was installed and verified. Older or unverified copies remain.$logDetails" @versions -PreviousVersion $previous
                continue
            }
            if ($logPath) { Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue }
            New-Result $name 'UPDATED' "Stable version verified in the $($app.Scope) scope." @versions -PreviousVersion $previous
        }
        catch {
            New-Result $name 'FAILED' $_.Exception.Message @versions
        }
        finally {
            if ($workPath -and -not $keepFiles) {
                Remove-Item -LiteralPath $workPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Get-LibreOfficeProducts {
    param([switch]$RegistryOnly)

    $guidPattern = '\{[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\}'
    $products = @(
        foreach ($record in (Get-RegisteredAppEntries)) {
            $entry = $record.Entry
            if ($entry.DisplayName -notmatch '^(?:The Document Foundation\s+)?LibreOffice(?:Dev)?(?:$|[\s_.(-])') {
                continue
            }

            $id = $null
            $uninstall = "$($entry.UninstallString) $($entry.QuietUninstallString)"
            $usesMsiexec = $uninstall -match '\bmsiexec(?:\.exe)?(?=["\s]|$)'
            if ($entry.WindowsInstaller -eq 1 -or $usesMsiexec) {
                if ($entry.PSChildName -match "^$guidPattern$") { $id = $entry.PSChildName }
                elseif ($usesMsiexec -and $uninstall -match $guidPattern) { $id = $Matches[0] }
            }

            $type = if ($id -and $record.CurrentContext) { 'MSI' } else { 'Unsupported' }
            $key = if ($type -eq 'MSI') { "MSI $($record.Scope) $id" } else { $entry.PSPath }
            [pscustomobject]@{
                Key       = $key
                Name      = $entry.DisplayName
                Version   = [string]$entry.DisplayVersion
                Id        = $id
                Type      = $type
                Priority  = [int]($entry.DisplayName -notmatch '\b(?:help\s*pack|language\s*pack|sdk)\b')
                Reason    = if (-not $record.CurrentContext) {
                    'Installed for another user. Uninstall in the owning user context.'
                }
                elseif (-not $id) {
                    'No Windows Installer product code found. Use the registered uninstall method for this package.'
                }
            }
        }

        if (-not $RegistryOnly) {
            # Microsoft Store product 9PB80DCFP83W, published by The Document Foundation.
            $storeName = 'TheDocumentFoundation.LibreOfficeMSIX'
            $publisherId = 'vv1d32z7hj13r'
            $familyName = '{0}_{1}' -f $storeName, $publisherId

            foreach ($package in (Get-AppxProvisionedPackage -Online | Where-Object {
                $_.DisplayName -eq $storeName -and $_.PackageName.EndsWith("_$publisherId")
            })) {
                [pscustomobject]@{
                    Key      = "Provisioned $($package.PackageName)"
                    Name     = 'LibreOffice (provisioned Microsoft Store package)'
                    Version  = [string]$package.Version
                    Id       = $package.PackageName
                    Type     = 'Provisioned'
                    Priority = 2
                }
            }

            $storePackages = @(Get-AppxPackage -AllUsers -Name $storeName -PackageTypeFilter Main, Bundle |
                Where-Object { $_.PackageFamilyName -eq $familyName })
            $bundles = @($storePackages | Where-Object IsBundle)
            foreach ($package in $storePackages) {
                if (-not $package.IsBundle -and $bundles.Version -contains $package.Version) { continue }
                [pscustomobject]@{
                    Key      = "MSIX $($package.PackageFullName)"
                    Name     = 'LibreOffice (Microsoft Store)'
                    Version  = [string]$package.Version
                    Id       = $package.PackageFullName
                    Type     = 'MSIX'
                    Priority = 3
                }
            }
        }
    )
    $products | Sort-Object Key -Unique | Sort-Object Priority, Name
}

function Invoke-LibreOfficeUninstaller {
    param($Product)

    $logPath = Join-Path ([IO.Path]::GetTempPath()) ("LibreOffice-removal-{0}.log" -f [guid]::NewGuid().ToString('N'))
    $isMsi = $Product.Type -eq 'MSI'
    $options = @{ PassThru = $true; WindowStyle = 'Hidden' }
    if ($isMsi) {
        $options.FilePath = "$env:SystemRoot\System32\msiexec.exe"
        $options.ArgumentList = '/x {0} /qn /norestart MSIRESTARTMANAGERCONTROL=Disable /L*v "{1}"' -f $Product.Id, $logPath
    }
    else {
        $package = $Product.Id.Replace("'", "''")
        $command = if ($Product.Type -eq 'Provisioned') {
            "Remove-AppxProvisionedPackage -Online -PackageName '$package' | Out-Null"
        }
        else {
            "Remove-AppxPackage -AllUsers -Package '$package' -Confirm:" + '$false'
        }
        $script = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    __REMOVE_PACKAGE__
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@.Replace('__REMOVE_PACKAGE__', $command)
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
        $options.FilePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $options.ArgumentList = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
        $options.RedirectStandardError = $logPath
    }

    $timeoutSeconds = 300
    $waitSeconds = if ($isMsi) { 5 } else { 15 }
    $absentChecks = 0
    $registryWarningShown = $false
    $process = Start-Process @options
    $keepLog = $true
    try {
        for ($elapsed = $waitSeconds; $elapsed -le $timeoutSeconds; $elapsed += $waitSeconds) {
            # Start-Process -Wait also waits for descendants. Wait for the uninstall command itself.
            if ($process.WaitForExit($waitSeconds * 1000)) {
                $code = $process.ExitCode
                $keepLog = if ($isMsi) { $code -notin @(0, 1605, 1614) } else { $code -ne 0 }
                $errorText = if (-not $isMsi -and $code -ne 0 -and (Test-Path -LiteralPath $logPath)) {
                    ([string](Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue)).Trim()
                }
                return [pscustomobject]@{
                    ExitCode = $code
                    TimedOut = $false
                    ErrorText = $errorText
                    LogPath = if ($keepLog) { $logPath }
                }
            }
            if ($isMsi) {
                try {
                    $registered = Get-LibreOfficeProducts -RegistryOnly | Where-Object Key -eq $Product.Key | Select-Object -First 1
                    if ($registered) { $absentChecks = 0 }
                    else { $absentChecks++ }
                }
                catch {
                    $absentChecks = 0
                    if (-not $registryWarningShown) {
                        Write-StepMessage "$($Product.Name) | Registry verification failed while waiting. $($_.Exception.Message)" 'WARNING'
                        $registryWarningShown = $true
                    }
                }
                if ($absentChecks -ge 2) {
                    return [pscustomobject]@{
                        RegistrationGone = $true
                        ProcessId = $process.Id
                        LogPath = $logPath
                    }
                }
            }
            if ($elapsed -lt $timeoutSeconds -and $elapsed % 15 -eq 0) {
                Write-StepMessage "$($Product.Name) | Waiting for the uninstaller (PID $($process.Id), $elapsed seconds)."
            }
        }
        [pscustomobject]@{
            TimedOut = $true
            ProcessId = $process.Id
            LogPath = $logPath
            TimeoutSeconds = $timeoutSeconds
        }
    }
    finally {
        $process.Dispose()
        if (-not $keepLog) {
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-LibreOfficeProducts {
    Write-StepMessage 'LibreOffice | Looking for installed MSI and Microsoft Store packages.'
    $products = @(Get-LibreOfficeProducts)
    if (-not $products) {
        New-Result 'LibreOffice' 'SKIPPED' 'No registered LibreOffice products found.'
        return
    }

    $attempted = @{}
    $operationPending = $false
    foreach ($product in $products) {
        $detail = "Package type: $($product.Type)"
        $versions = @{
            InstalledVersion = if ($product.Version) { $product.Version } else { 'Unknown' }
            LatestStableVersion = 'Not applicable'
        }
        if ($product.Type -eq 'Unsupported') {
            New-Result $product.Name 'ACTION REQUIRED' $product.Reason @versions
            continue
        }
        if ($CheckOnly) {
            New-Result $product.Name 'ACTION REQUIRED' "$detail | Removal available. Check-only mode." @versions
            continue
        }
        if ($operationPending) {
            New-Result $product.Name 'PENDING' 'Removal deferred while another uninstall is still in progress.' @versions
            continue
        }

        try {
            Write-StepMessage "$($product.Name) | Removing $($versions.InstalledVersion) ($($product.Type))."
            $removal = Invoke-LibreOfficeUninstaller $product
            $logNote = if ($removal.LogPath) { " Log: $($removal.LogPath)" }
            if ($removal.RegistrationGone) {
                $operationPending = $true
                $versions.InstalledVersion = 'Not registered'
                New-Result $product.Name 'PENDING' "MSI registration was absent in two consecutive checks. Uninstaller PID $($removal.ProcessId) is still running.$logNote" @versions
                continue
            }
            if ($removal.TimedOut) {
                $operationPending = $true
                New-Result $product.Name 'PENDING' "Uninstaller PID $($removal.ProcessId) has not exited after $($removal.TimeoutSeconds) seconds. Installed version was last checked before removal.$logNote" @versions
                continue
            }

            $code = $removal.ExitCode
            $installer = if ($product.Type -eq 'MSI') { 'Windows Installer' } else { 'Microsoft Store uninstall command' }
            Write-StepMessage "$($product.Name) | $installer returned exit code $code."
            if ($product.Type -eq 'MSI' -and $code -in @(1641, 3010)) {
                New-Result $product.Name 'PENDING' "Windows Installer exit code $code. Recheck after restart.$logNote" @versions -Restart
                continue
            }
            if ($product.Type -eq 'MSI' -and $code -eq 1618) {
                $operationPending = $true
                New-Result $product.Name 'PENDING' "Windows Installer is busy with another operation (1618).$logNote" @versions
                continue
            }
            if ($code -ne 0 -and -not ($product.Type -eq 'MSI' -and $code -in @(1605, 1614))) {
                $message = if ($product.Type -eq 'MSI') { [ComponentModel.Win32Exception]::new($code).Message }
                    else { $removal.ErrorText }
                throw "$installer exit code $code. $message$logNote"
            }
            $attempted[$product.Key] = $true
        }
        catch {
            New-Result $product.Name 'FAILED' $_.Exception.Message @versions
        }
    }

    if (-not $attempted.Count) { return }
    Write-StepMessage 'LibreOffice | Scanning again to verify removal.'
    $remaining = @{}
    foreach ($product in (Get-LibreOfficeProducts -RegistryOnly:$operationPending)) { $remaining[$product.Key] = $product }
    foreach ($product in $products) {
        if (-not $attempted.ContainsKey($product.Key)) { continue }
        if ($operationPending -and $product.Type -ne 'MSI') {
            New-Result $product.Name 'PENDING' 'Uninstall finished. Store verification is deferred while another uninstall is still running.' -InstalledVersion $product.Version -LatestStableVersion 'Not applicable'
        }
        elseif ($remaining.ContainsKey($product.Key)) {
            New-Result $product.Name 'FAILED' 'The package is still registered after removal.' -InstalledVersion $product.Version -LatestStableVersion 'Not applicable'
        }
        else {
            New-Result $product.Name 'REMOVED' 'Removal verified.' -InstalledVersion 'Not installed' -LatestStableVersion 'Not applicable' -PreviousVersion $product.Version
        }
    }
    foreach ($product in $remaining.Values) {
        if ($products.Key -notcontains $product.Key) {
            New-Result $product.Name 'ACTION REQUIRED' 'This package appeared during removal. Run the script again to remove it.' -InstalledVersion $product.Version -LatestStableVersion 'Not applicable'
        }
    }
}

function Test-WindowsBuild {
    Write-StepMessage 'Windows | Reading the installed edition, release and build from the registry.'
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$os.CurrentBuild
    $detail = "$($os.EditionID) $($os.DisplayVersion), build $build.$($os.UBR)"
    $homeOrPro = $os.EditionID -match '^(Core|Professional|CloudEdition)'
    if ($os.InstallationType -ne 'Client' -or $build -lt $RequiredWindowsBuild) {
        New-Result 'Windows' 'ACTION REQUIRED' "$detail | Install a supported Windows 11 release (24H2 or newer)."
    }
    elseif ($build -eq $RequiredWindowsBuild -and $homeOrPro) {
        New-Result 'Windows' 'ACTION REQUIRED' "$detail | Servicing for this edition of 24H2 has ended. Move to a supported release or edition."
    }
    else {
        New-Result 'Windows' 'COMPLIANT' "$detail | Minimum build met. Cumulative patch level is not checked."
    }
}

function Test-SystemBitLocker {
    Write-StepMessage "BitLocker | Checking encryption, protection and the recovery protector on $env:SystemDrive."
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
    $hasRecovery = [bool]($volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' })
    $detail = "Protection: $($volume.ProtectionStatus) | Encryption: $($volume.VolumeStatus) | Recovery protector: $hasRecovery"
    $status = if ($volume.ProtectionStatus -eq 'On' -and $volume.VolumeStatus -eq 'FullyEncrypted' -and $hasRecovery) {
        'COMPLIANT'
    }
    else { 'ACTION REQUIRED' }

    $result = New-Result 'BitLocker' $status $detail
    $result | Add-Member -NotePropertyName ReadyForSecureBoot -NotePropertyValue (
        $status -eq 'COMPLIANT' -or $volume.VolumeStatus -eq 'FullyDecrypted'
    )
    return $result
}

function Get-SecureBootState {
    $root = Get-ItemProperty -LiteralPath $SecureBootPath
    $servicingPath = "$SecureBootPath\Servicing"
    $servicing = if (Test-Path -LiteralPath $servicingPath) {
        Get-ItemProperty -LiteralPath $servicingPath
    }
    $state = if ($servicing.UEFICA2023Status) { $servicing.UEFICA2023Status } else { $root.UEFICA2023Status }
    $flags = [long]$root.AvailableUpdates -band 4294967295L
    $errorCode = Get-HexCode $servicing.UEFICA2023Error
    $eventId = $servicing.UEFICA2023ErrorEvent
    $pendingBits = $flags -band $SecureBootActionFlags
    [pscustomobject]@{
        State        = $state
        Flags        = $flags
        PendingBits  = $pendingBits
        Restart      = $pendingBits -eq 0x0100 -or $errorCode -eq '0x8007015E'
        Failed       = $errorCode -notin @('0x00000000', '0x8007015E') -or
            ($eventId -and $errorCode -eq '0x00000000')
        Complete     = $state -eq 'Updated' -and $errorCode -eq '0x00000000' -and $pendingBits -eq 0 -and -not $eventId
        Detail       = 'Status: {0} | AvailableUpdates: 0x{1:X4} | Error: {2} | Event: {3}' -f $state, $flags, $errorCode, $eventId
    }
}

function Start-SecureBoot2023 {
    param([bool]$ReadyForSecureBoot)

    $name = 'Secure Boot 2023'
    Write-StepMessage "$name | Checking whether Secure Boot is enabled in UEFI."
    if (-not (Confirm-SecureBootUEFI)) {
        New-Result $name 'ACTION REQUIRED' 'Secure Boot is disabled. Check the UEFI configuration.'
        return
    }

    Write-StepMessage "$name | Reading certificate servicing status and pending update flags."
    $state = Get-SecureBootState
    if ($state.Complete) {
        New-Result $name 'COMPLIANT' $state.Detail
        return
    }
    if ($state.Failed) {
        New-Result $name 'FAILED' "$($state.Detail) | Review Secure Boot events in the System log."
        return
    }
    if ($CheckOnly -or -not $ReadyForSecureBoot) {
        if (-not $CheckOnly -and -not $ReadyForSecureBoot) {
            New-Result $name 'ACTION REQUIRED' "$($state.Detail) | Verify BitLocker and its recovery protector first."
        }
        elseif ($state.Restart) {
            New-Result $name 'PENDING' "$($state.Detail) | Restart may be required to finish." -Restart
        }
        else {
            New-Result $name 'ACTION REQUIRED' $state.Detail
        }
        return
    }

    Write-StepMessage "$name | Checking the Windows Secure-Boot-Update task."
    $task = Get-ScheduledTask -TaskPath $SecureBootTaskPath -TaskName $SecureBootTaskName
    if (-not $task) { throw 'The Windows Secure-Boot-Update task was not found.' }
    if ($task.State -eq 'Disabled') {
        Write-StepMessage "$name | Enabling the servicing task."
        Enable-ScheduledTask -InputObject $task | Out-Null
    }
    if ($task.State -ne 'Running') {
        if ($state.PendingBits -eq 0 -and $state.State -ne 'InProgress' -and -not $state.Restart) {
            Write-StepMessage "$name | Setting the certificate update flags."
            # The servicing task clears completed bits. Preserve the remaining work on subsequent runs.
            $flags = $state.Flags -bor $SecureBootUpdateFlags
            $dword = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$flags), 0)
            New-ItemProperty -LiteralPath $SecureBootPath -Name AvailableUpdates -PropertyType DWord -Value $dword -Force | Out-Null
        }
        Write-StepMessage "$name | Starting the servicing task."
        Start-ScheduledTask -TaskPath $SecureBootTaskPath -TaskName $SecureBootTaskName
    }
    Write-StepMessage "$name | Waiting for Windows to report the servicing result."
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        Start-Sleep -Seconds 2
        $state = Get-SecureBootState
        if ($state.Complete -or $state.Failed -or $state.Restart) { break }
    }

    if ($state.Complete) {
        New-Result $name 'UPDATED' $state.Detail
    }
    elseif ($state.Failed) {
        New-Result $name 'FAILED' "$($state.Detail) | Review Secure Boot events in the System log."
    }
    elseif ($state.Restart) {
        New-Result $name 'PENDING' "$($state.Detail) | Restart, then run this script again." -Restart
    }
    else {
        New-Result $name 'PENDING' "$($state.Detail) | Windows servicing was triggered. Recheck its status."
    }
}

$remediationExitCode = & {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Host 'Run this script from a 64-bit PowerShell session.' -ForegroundColor Red
        return 1
    }

    $mutex = [Threading.Mutex]::new($false, 'Global\WorkstationSecurityRemediation')
    $hasLock = $false
    try {
        try {
            $hasLock = $mutex.WaitOne(0)
        }
        catch [Threading.AbandonedMutexException] {
            $hasLock = $true
        }
        if (-not $hasLock) {
            Write-Host 'Security remediation is already running.' -ForegroundColor Yellow
            return 2
        }

        Write-Host ("Security remediation on {0} | {1:yyyy-MM-dd HH:mm:ss}" -f $env:COMPUTERNAME, (Get-Date))
        if ($CheckOnly) { Write-StepMessage 'Check-only mode.' }
        else { Write-StepMessage 'Remediation mode.' }

        $results = @(Invoke-Step '7-Zip' { Update-SevenZip } -ShowVersions)
        $results += @(Invoke-Step 'TeamViewer' { Update-TeamViewer } -ShowVersions)
        $results += @(Invoke-Step 'pgAdmin 4' { Update-PgAdmin } -ShowVersions)
        $results += @(Invoke-Step 'JetBrains' { Update-JetBrains } -ShowVersions)
        $results += @(Invoke-Step 'LibreOffice' { Remove-LibreOfficeProducts })
        $results += @(Invoke-Step 'Windows' { Test-WindowsBuild })
        $bitLocker = Invoke-Step 'BitLocker' { Test-SystemBitLocker }
        $results += $bitLocker
        $results += @(Invoke-Step 'Secure Boot 2023' { Start-SecureBoot2023 ([bool]$bitLocker.ReadyForSecureBoot) })

        Write-FinalReport $results
        if ($results.Restart -contains $true) {
            Write-Host 'Manual restart required. If BitLocker is active, verify access to the recovery key first.' -ForegroundColor Yellow
        }
        if ($results.Status -contains 'FAILED' -or $results.Status -contains 'ACTION REQUIRED') { return 1 }
        if ($results.Status -contains 'PENDING') { return 2 }
        return 0
    }
    finally {
        if ($hasLock) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# A pasted command runs in the caller's console. Only a file invocation may exit.
if ($PSCommandPath -and $MyInvocation.InvocationName -ne '.') {
    exit $remediationExitCode
}
$global:LASTEXITCODE = $remediationExitCode
