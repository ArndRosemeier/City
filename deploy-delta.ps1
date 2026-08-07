# Eccentri City - delta FTP deploy (no remote wipe).
#
# Stages web/dist, compares SHA-256 against .deploy/manifest.json from the last
# successful deploy, and uploads only new/changed files. Safe for adding
# screenshots/clips: the live gallery reads gallery-data.js, so old media can
# stay on the server while new files + the updated gallery list go up.
#
# Usage (from repo root):
#   .\deploy-delta.ps1
#   .\deploy-delta.ps1 -SkipRebuild
#   .\deploy-delta.ps1 -DryRun
#   .\deploy-delta.ps1 -MediaOnly
#
# Password: $env:FTP_PASSWORD, or User env FTP_PASSWORD, or interactive prompt.
#
# First run with no .deploy/manifest.json uploads the full staged tree (still
# no wipe). Prefer .\deploy-clean.ps1 once if the remote is unknown/corrupt.

param(
    [string]$FtpServer = "ftp.futuremagic.de",
    [string]$FtpUser = "12529-Pyrion",
    [string]$RemotePath = "/webseiten/EccentriCity/",
    [string]$BasePath = "/EccentriCity/",
    [string]$PublicUrl = "https://futuremagic.de/EccentriCity/",
    [switch]$SkipRebuild,
    [switch]$DryRun,
    [switch]$MediaOnly,
    [switch]$RegisterHub
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$WebDir = Join-Path $RepoRoot "web"
$DistDir = Join-Path $WebDir "dist"
$DeployDir = Join-Path $RepoRoot ".deploy"
$ManifestPath = Join-Path $DeployDir "manifest.json"
$RebuildScript = Join-Path $WebDir "tools\rebuild_media.py"
$RegisterScript = "C:\Projekte\Futuremagic\scripts\Register-FuturemagicApp.ps1"

function Normalize-FtpDir([string]$path) {
    $p = $path.Replace('\', '/')
    if (-not $p.StartsWith('/')) { $p = "/$p" }
    if (-not $p.EndsWith('/')) { $p = "$p/" }
    return $p
}

function Normalize-WebBase([string]$path) {
    $p = $path.Replace('\', '/')
    if (-not $p.StartsWith('/')) { $p = "/$p" }
    if (-not $p.EndsWith('/')) { $p = "$p/" }
    return $p
}

$RemotePath = Normalize-FtpDir $RemotePath
$BasePath = Normalize-WebBase $BasePath

Write-Host "Starting DELTA Eccentri City website deployment..." -ForegroundColor Cyan
Write-Host "Remote wipe: disabled (delta never cleans)" -ForegroundColor Green
if ($MediaOnly) {
    Write-Host "MediaOnly: upload candidates limited to gallery + media/**" -ForegroundColor Yellow
}
if ($DryRun) {
    Write-Host "DryRun: no FTP writes, no manifest update" -ForegroundColor Yellow
}
Write-Host "Site base: $BasePath" -ForegroundColor Cyan
Write-Host "Public URL: $PublicUrl" -ForegroundColor Cyan

function Get-FtpPassword {
    $password = $env:FTP_PASSWORD
    if (-not $password) {
        try {
            $password = [Environment]::GetEnvironmentVariable("FTP_PASSWORD", "User")
            if ($password) {
                Write-Host "Retrieved password from user environment variables" -ForegroundColor Green
                $env:FTP_PASSWORD = $password
            }
        } catch {
            # ignore
        }
    }
    if (-not $password) {
        Write-Host "Enter FTP password:" -ForegroundColor Yellow
        $secure = Read-Host -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    } else {
        Write-Host "Using stored password" -ForegroundColor Green
    }
    if (-not $password) {
        throw "FTP password is required"
    }
    return $password
}

function New-FtpRequest([string]$Uri, [string]$Method, [string]$Password) {
    $req = [System.Net.FtpWebRequest]::Create($Uri)
    $req.Method = $Method
    $req.Credentials = New-Object System.Net.NetworkCredential($FtpUser, $Password)
    $req.UseBinary = $true
    $req.UsePassive = $true
    $req.KeepAlive = $false
    $req.Timeout = 600000
    return $req
}

function Test-FtpDirectory([string]$RemoteDir, [string]$Password) {
    try {
        $req = New-FtpRequest "ftp://$FtpServer$RemoteDir" ([System.Net.WebRequestMethods+Ftp]::ListDirectory) $Password
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch {
        return $false
    }
}

function Ensure-FtpDirectory([string]$RemoteDir, [string]$Password, [System.Collections.Generic.HashSet[string]]$Created) {
    $dir = Normalize-FtpDir $RemoteDir
    if ($Created.Contains($dir)) { return }
    if (Test-FtpDirectory $dir $Password) {
        [void]$Created.Add($dir)
        return
    }
    try {
        $req = New-FtpRequest "ftp://$FtpServer$dir" ([System.Net.WebRequestMethods+Ftp]::MakeDirectory) $Password
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Host "Created directory: $dir" -ForegroundColor Blue
    } catch {
        if (-not (Test-FtpDirectory $dir $Password)) {
            throw "Could not create FTP directory $dir : $($_.Exception.Message)"
        }
    }
    [void]$Created.Add($dir)
}

function Ensure-FtpPathTree([string]$RemoteDir, [string]$Password, [System.Collections.Generic.HashSet[string]]$Created) {
    $dir = Normalize-FtpDir $RemoteDir
    $parts = $dir.Trim('/').Split('/', [StringSplitOptions]::RemoveEmptyEntries)
    $current = "/"
    foreach ($part in $parts) {
        $current = "$current$part/"
        Ensure-FtpDirectory $current $Password $Created
    }
}

function Get-FileSha256Hex([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $hash = $sha.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
        } finally {
            $stream.Close()
        }
    } finally {
        $sha.Dispose()
    }
}

function Write-DeployManifest([string]$Path, [hashtable]$FilesMap, [string]$Remote, [string]$Base) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $filesObj = [ordered]@{}
    foreach ($key in ($FilesMap.Keys | Sort-Object)) {
        $entry = $FilesMap[$key]
        $filesObj[$key] = [ordered]@{
            sha256 = $entry.sha256
            size   = $entry.size
        }
    }
    $doc = [ordered]@{
        remotePath = $Remote
        basePath   = $Base
        updatedAt  = (Get-Date).ToUniversalTime().ToString('o')
        files      = $filesObj
    }
    $json = $doc | ConvertTo-Json -Depth 6
    $tmp = "$Path.tmp"
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    Move-Item -Path $tmp -Destination $Path -Force
}

function Read-DeployManifestFiles([string]$Path) {
    $map = @{}
    if (-not (Test-Path $Path)) {
        return $map
    }
    $doc = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $doc.files) {
        return $map
    }
    foreach ($prop in $doc.files.PSObject.Properties) {
        $map[$prop.Name] = @{
            sha256 = [string]$prop.Value.sha256
            size   = [int64]$prop.Value.size
        }
    }
    return $map
}

function Test-MediaOnlyPath([string]$RelativePath) {
    if ($RelativePath -eq "gallery-data.js") { return $true }
    if ($RelativePath -eq "media/gallery.json") { return $true }
    if ($RelativePath.StartsWith("media/")) { return $true }
    return $false
}

function Copy-WebsiteDist {
    param(
        [string]$WebRoot,
        [string]$OutDir,
        [string]$SiteBase
    )

    if (Test-Path $OutDir) {
        Remove-Item -Recurse -Force $OutDir
    }
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $pageFiles = @("index.html", "styles.css", "main.js", "gallery-data.js")
    foreach ($name in $pageFiles) {
        $src = Join-Path $WebRoot $name
        if (-not (Test-Path $src)) {
            throw "Required site file missing: $name (run rebuild first if gallery-data.js is absent)"
        }
        Copy-Item $src (Join-Path $OutDir $name) -Force
    }

    $mediaSrc = Join-Path $WebRoot "media"
    if (-not (Test-Path $mediaSrc)) {
        throw "Missing web/media - run: python web/tools/rebuild_media.py"
    }
    Copy-Item $mediaSrc (Join-Path $OutDir "media") -Recurse -Force

    # Drop Godot import sidecars if they leaked into web/media.
    Get-ChildItem -Path (Join-Path $OutDir "media") -Recurse -File -Filter "*.import" -ErrorAction SilentlyContinue |
        Remove-Item -Force

    $htaccessSrc = Join-Path $WebRoot "public\.htaccess"
    if (Test-Path $htaccessSrc) {
        $htaccessBody = Get-Content -Raw $htaccessSrc
        $htaccessBody = $htaccessBody -replace '(?m)^(\s*RewriteBase\s+)\S+', "`${1}$SiteBase"
        Set-Content -Path (Join-Path $OutDir ".htaccess") -Value $htaccessBody -NoNewline
    } else {
        Write-Host "No web/public/.htaccess found - skipping" -ForegroundColor Gray
    }

    $manifestoSrc = Join-Path $WebRoot "public\futuremagic.json"
    if (Test-Path $manifestoSrc) {
        Copy-Item $manifestoSrc (Join-Path $OutDir "futuremagic.json") -Force
    }
}

function Upload-FtpFile([string]$LocalPath, [string]$RemoteFile, [string]$Password) {
    $ftpRequest = New-FtpRequest "ftp://$FtpServer$RemoteFile" ([System.Net.WebRequestMethods+Ftp]::UploadFile) $Password
    $stream = [System.IO.File]::OpenRead($LocalPath)
    try {
        $ftpRequest.ContentLength = $stream.Length
        $requestStream = $ftpRequest.GetRequestStream()
        try {
            $buffer = New-Object byte[] (1024 * 1024)
            while ($true) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $requestStream.Write($buffer, 0, $read)
            }
        } finally {
            $requestStream.Close()
        }
        $response = $ftpRequest.GetResponse()
        $response.Close()
    } finally {
        $stream.Close()
    }
}

try {
    if (-not (Test-Path $WebDir)) {
        throw "Website folder not found: $WebDir"
    }

    if (-not $SkipRebuild) {
        if (-not (Test-Path $RebuildScript)) {
            throw "Rebuild script missing: $RebuildScript"
        }
        Write-Host "Rebuilding website media from screenshots/ and videos/..." -ForegroundColor Yellow
        & python $RebuildScript
        if ($LASTEXITCODE -ne 0) {
            throw "rebuild_media.py failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Host "SkipRebuild: using existing web/media and gallery-data.js" -ForegroundColor Yellow
    }

    Write-Host "Staging static site into web/dist..." -ForegroundColor Yellow
    Copy-WebsiteDist -WebRoot $WebDir -OutDir $DistDir -SiteBase $BasePath

    if (-not (Test-Path (Join-Path $DistDir "index.html"))) {
        throw "Stage failed - no index.html in web/dist"
    }

    $files = @(Get-ChildItem -Path $DistDir -Recurse -File -Force)
    $distResolved = (Resolve-Path $DistDir).Path
    $prev = Read-DeployManifestFiles $ManifestPath
    if ($prev.Count -eq 0) {
        Write-Host "No local .deploy/manifest.json - will upload entire staged tree (still no remote wipe)." -ForegroundColor Yellow
    } else {
        Write-Host ("Loaded previous manifest with {0} file(s)." -f $prev.Count) -ForegroundColor Cyan
    }

    $stagedHashes = @{}
    $toUpload = New-Object System.Collections.Generic.List[object]
    $unchanged = 0
    $skippedScope = 0

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($distResolved.Length).TrimStart([char]'\', [char]'/').Replace('\', '/')
        $hash = Get-FileSha256Hex $file.FullName
        $stagedHashes[$relativePath] = @{
            sha256 = $hash
            size   = [int64]$file.Length
            fullName = $file.FullName
        }

        if ($MediaOnly -and -not (Test-MediaOnlyPath $relativePath)) {
            $skippedScope++
            continue
        }

        $prevEntry = $prev[$relativePath]
        if (
            $null -ne $prevEntry -and
            $prevEntry.sha256 -eq $hash -and
            [int64]$prevEntry.size -eq [int64]$file.Length
        ) {
            $unchanged++
            continue
        }

        $reason = if ($null -eq $prevEntry) { "new" } else { "changed" }
        $toUpload.Add([pscustomobject]@{
            RelativePath = $relativePath
            FullName     = $file.FullName
            Size         = [int64]$file.Length
            Reason       = $reason
        }) | Out-Null
    }

    $uploadBytes = ($toUpload | Measure-Object -Property Size -Sum).Sum
    if ($null -eq $uploadBytes) { $uploadBytes = 0 }

    Write-Host ""
    Write-Host "=== DELTA PLAN ===" -ForegroundColor Cyan
    Write-Host ("Staged files:     {0}" -f $files.Count)
    Write-Host ("Unchanged:        {0}" -f $unchanged)
    if ($MediaOnly) {
        Write-Host ("Outside MediaOnly:{0}" -f $skippedScope)
    }
    Write-Host ("To upload:        {0} ({1:N1} MB)" -f $toUpload.Count, ($uploadBytes / 1MB))

    if ($toUpload.Count -eq 0) {
        Write-Host "Nothing to upload - remote already matches staged site." -ForegroundColor Green
        if (-not $DryRun -and -not $MediaOnly) {
            Write-DeployManifest $ManifestPath $stagedHashes $RemotePath $BasePath
            Write-Host ("Manifest refreshed: {0}" -f $ManifestPath) -ForegroundColor Cyan
        }
        Write-Host "Site: $PublicUrl" -ForegroundColor Cyan
        exit 0
    }

    foreach ($item in ($toUpload | Sort-Object RelativePath)) {
        $sizeKB = [math]::Round($item.Size / 1KB, 1)
        Write-Host ("  [{0}] {1} ({2} KB)" -f $item.Reason, $item.RelativePath, $sizeKB) -ForegroundColor Yellow
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "DryRun complete - no files uploaded." -ForegroundColor Green
        exit 0
    }

    $FTP_PASSWORD = Get-FtpPassword
    $createdDirs = New-Object 'System.Collections.Generic.HashSet[string]'

    Write-Host ""
    Write-Host "Ensuring remote path exists: $RemotePath" -ForegroundColor Cyan
    Ensure-FtpPathTree $RemotePath $FTP_PASSWORD $createdDirs

    $dirSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in $toUpload) {
        $slash = $item.RelativePath.LastIndexOf('/')
        if ($slash -gt 0) {
            [void]$dirSet.Add($item.RelativePath.Substring(0, $slash))
        }
    }
    foreach ($relDir in ($dirSet | Sort-Object { $_.Length }, { $_ })) {
        Ensure-FtpPathTree "$RemotePath$relDir/" $FTP_PASSWORD $createdDirs
    }

    Write-Host "Uploading delta..." -ForegroundColor Green
    $uploaded = 0
    $failed = @()

    foreach ($item in $toUpload) {
        $remoteFile = "$RemotePath$($item.RelativePath)"
        try {
            Upload-FtpFile $item.FullName $remoteFile $FTP_PASSWORD
            $uploaded++
            $sizeKB = [math]::Round($item.Size / 1KB, 1)
            Write-Host ("Uploaded: {0} ({1} KB)" -f $item.RelativePath, $sizeKB) -ForegroundColor Green
        } catch {
            $failed += $item.RelativePath
            Write-Host ("Failed: {0} - {1}" -f $item.RelativePath, $_.Exception.Message) -ForegroundColor Red
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "=== FAILED UPLOADS ===" -ForegroundColor Red
        foreach ($failedFile in $failed) {
            Write-Host "[FAIL] $failedFile" -ForegroundColor Red
        }
        throw ("Delta deploy completed with {0} failed file(s); manifest not updated." -f $failed.Count)
    }

    # Manifest always reflects the full staged tree so the next delta is accurate.
    # MediaOnly still records page files that were staged but not uploaded this run
    # using their current local hashes (assumes remote already matched them).
    Write-Host "Writing deploy manifest..." -ForegroundColor Cyan
    $manifestFiles = @{}
    foreach ($key in $stagedHashes.Keys) {
        $manifestFiles[$key] = @{
            sha256 = $stagedHashes[$key].sha256
            size   = $stagedHashes[$key].size
        }
    }
    Write-DeployManifest $ManifestPath $manifestFiles $RemotePath $BasePath

    Write-Host ""
    Write-Host ("DELTA DEPLOYMENT finished! Uploaded {0}/{1} changed file(s)." -f $uploaded, $toUpload.Count) -ForegroundColor Green
    Write-Host ("Manifest saved: {0}" -f $ManifestPath) -ForegroundColor Cyan
    Write-Host "Site should now work at: $PublicUrl" -ForegroundColor Cyan

    if ($RegisterHub) {
        if (Test-Path $RegisterScript) {
            Write-Host ""
            & $RegisterScript `
                -Slug "EccentriCity" `
                -Title "Eccentri City" `
                -Path $BasePath `
                -FtpPassword $FTP_PASSWORD `
                -ManifestoLocalPath (Join-Path $DistDir "futuremagic.json") `
                -AppRemoteDir $RemotePath
        } else {
            Write-Host "[SKIP] Futuremagic registry helper not found: $RegisterScript" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host ("Delta deployment failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
