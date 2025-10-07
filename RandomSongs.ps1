<#
RandomSongs.ps1
--------------------------
Copies a RANDOM subset of audio files from a source library,
optionally converts FLAC to MP3 (with metadata & cover art),
limits files per artist, and renames files according to a scheme.

Supports:
    - Interactive mode if no params
    - Command-line arguments for automation
    - TOTAL / per-folder modes
    - Max files per artist
    - FLAC→MP3 conversion (metadata + cover)
    - Rename schemes
    - Dry run

Usage examples:
---------------
# Fully automated
.\RandomSongs.ps1 -Src "D:\Music" -Dest "E:\Output" -Total 100 -ConvertToMp3 -MaxPerArtist 5 -RenameScheme "artist-title"

# Interactive (if you omit params)
.\RandomSongs.ps1
#>

param(
    [string]$Src,
    [string]$Dest,
    [int]$Count,
    [int]$Total,
    [switch]$ConvertToMp3,
    [int]$MaxPerArtist,
    [string]$RenameScheme,
    [switch]$DryRun
)

# ------------------------------
# Defaults & validation
# ------------------------------
if (-not $Src) { $Src = (Get-Location).Path }
if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }
if (-not $Count -or $Count -lt 1) { $Count = 3 }

$allowedSchemes = @("number-title", "number-artist-title", "artist-title")
if (-not $RenameScheme -or -not $allowedSchemes -contains $RenameScheme) {
    $RenameScheme = "number-title"
}

# ------------------------------
# Interactive mode (if no args)
# ------------------------------
if (-not $PSBoundParameters.Count) {
    Write-Host "RandomSongs Interactive Setup"
    Write-Host "----------------------------------`n"

    $Src = Read-Host "Enter the source folder (default = current folder)"
    if (-not $Src) { $Src = (Get-Location).Path }
    while (-not (Test-Path $Src)) {
        $Src = Read-Host "Invalid source. Enter a valid folder path"
    }

    $Dest = Read-Host "Enter the destination folder (default = Output in current folder)"
    if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }

    $Count = Read-Host "Number of random audio files per folder (default = 3)"
    if (-not $Count) { $Count = 3 } else { $Count = [int]$Count }

    $Total = Read-Host "Total number of audio files (leave empty for per-folder mode)"
    if ($Total) { $Total = [int]$Total }

    $ConvertToMp3 = (Read-Host "Convert FLAC to MP3? (y/N)") -match "^(y|Y)$"

    $MaxPerArtist = Read-Host "Maximum number of files per artist (leave empty for no limit)"
    if ($MaxPerArtist) { $MaxPerArtist = [int]$MaxPerArtist }

    Write-Host "Choose file renaming scheme:"
    Write-Host "1: number-title (default)"
    Write-Host "2: number-artist-title"
    Write-Host "3: artist-title"
    $choice = Read-Host "Enter choice (1-3)"
    switch ($choice) {
        "2"     { $RenameScheme = "number-artist-title" }
        "3"     { $RenameScheme = "artist-title" }
        default { $RenameScheme = "number-title" }
    }

    $DryRun = (Read-Host "Perform dry run (show actions only)? (y/N)") -match "^(y|Y)$"
}

# ------------------------------
# Defaults & configuration
# ------------------------------
$audioExtensions = @(".flac", ".mp3", ".wav", ".aac", ".ogg", ".m4a", ".wma")
if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }
if (-not $Count -or $Count -lt 1) { $Count = 3 }

Write-Host "`nSource: $Src"
Write-Host "Destination: $Dest"
if ($Total) {
    Write-Host "Mode: TOTAL ($Total random audio files overall)"
} else {
    Write-Host "Mode: PER-FOLDER ($Count random audio files per folder)"
}
if ($ConvertToMp3) { Write-Host "FLAC → MP3 conversion ENABLED" }
if ($MaxPerArtist) { Write-Host "Max files per artist: $MaxPerArtist" }
Write-Host "Rename scheme: $RenameScheme"
if ($DryRun) { Write-Host "Dry run ENABLED (no files will be copied or converted)" }

# ------------------------------
# Helper functions
# ------------------------------
function Ensure-Folder {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Sanitize-FileName {
    param($Name)

    # Only fix actual illegal filename characters, keep UTF-8 characters intact
    return ($Name -replace '[<>:"/\\|?*]', '_')
}

function Get-AudioArtist {
    param([string]$Path)
    try {
        # Use Start-Process to better control encoding
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "ffprobe"
        $psi.Arguments = "-v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 `"$Path`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($psi)
        $artist = $process.StandardOutput.ReadToEnd().Trim()
        $process.WaitForExit()

        if ($artist -and $artist.Trim()) {
            return $artist.Trim()
        }
    } catch {}
    return (Split-Path $Path -Parent | Split-Path -Leaf)
}

function Get-AudioTitle {
    param([string]$Path)
    try {
        # Use Start-Process to better control encoding
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "ffprobe"
        $psi.Arguments = "-v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 `"$Path`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($psi)
        $title = $process.StandardOutput.ReadToEnd().Trim()
        $process.WaitForExit()

        if ($title -and $title.Trim()) {
            return $title.Trim()
        }
    } catch {}

    # Fallback to filename - keep original UTF-8 characters intact
    $fallbackTitle = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    return $fallbackTitle
}

function Rename-File {
    param([System.IO.FileInfo]$File)

    $artist = Get-AudioArtist $File.FullName
    $title  = Get-AudioTitle  $File.FullName
    # Keep the original UTF-8 characters intact
    $number = ($File.BaseName -split " ")[0]

    $newName = switch ($RenameScheme) {
        "number-title"        { "$number $title" }
        "number-artist-title" { "$number $artist - $title" }
        "artist-title"        { "$artist - $title" }
    }

    if ([string]::IsNullOrWhiteSpace($newName)) {
        $newName = $File.BaseName
    }

    return "$newName$($File.Extension)"
}

function Get-RelativePath($FullPath, $BasePath) {
    return $FullPath.Substring($BasePath.Length).TrimStart('\')
}

# ------------------------------
# Global state
# ------------------------------
$script:jobIndex   = 0
$script:totalJobs  = 0
$artistCounts      = @{}
$foldersWithFiles  = @{}

# ------------------------------
# Safe copy / convert
# ------------------------------
function Copy-FilesSafely {
    param([array]$Files, [string]$TargetDir)

    foreach ($f in $Files) {
        if (-not $f -or -not (Test-Path $f.FullName)) { continue }

        $script:jobIndex++
        $artist = Get-AudioArtist $f.FullName

        # Per-artist limit check BEFORE creating folders
        if ($MaxPerArtist) {
            if (-not $artistCounts.ContainsKey($artist)) { $artistCounts[$artist] = 0 }
            if ($artistCounts[$artist] -ge $MaxPerArtist) {
                Write-Host "[$script:jobIndex/$script:totalJobs] Skipping $($f.Name) (max per artist reached)"
                continue
            }
        }

        # Create folder only if file will be processed
        $parentDir = Split-Path -Parent (Join-Path $TargetDir $f.Name)
        Ensure-Folder $parentDir
        $foldersWithFiles[$parentDir] = $true

        # Determine destination filename
        try {
            $destFileName = Sanitize-FileName (Rename-File -File $f)
            if ([string]::IsNullOrWhiteSpace($destFileName)) {
                $destFileName = Sanitize-FileName $f.Name
            }
        } catch {
            Write-Warning "Error renaming file $($f.Name); using original name"
            $destFileName = Sanitize-FileName $f.Name
        }

        # Convert or copy
        if ($ConvertToMp3 -and $f.Extension.ToLower() -eq ".flac") {
            $destFileName = [System.IO.Path]::ChangeExtension($destFileName, ".mp3")
            $destFullPath = Join-Path $parentDir $destFileName

            Write-Host "[$script:jobIndex/$script:totalJobs] Converting FLAC → MP3: $destFileName"
            if (-not $DryRun) {
                if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
                    Write-Error "ffmpeg not found in PATH. Please install ffmpeg to use conversion."
                    continue
                }

                $ffmpegArgs = @(
                    "-y", "-loglevel", "error",
                    "-i", $f.FullName,
                    "-codec:a", "libmp3lame", "-qscale:a", "2",
                    "-map_metadata", "0", "-id3v2_version", "3",
                    "-map", "0:a", "-map", "0:v?", "-disposition:v", "attached_pic",
                    "-c:v", "mjpeg", "-vf", "scale=300:300:force_original_aspect_ratio=decrease",
                    "-pix_fmt", "yuvj420p",
                    $destFullPath
                )

                try {
                    & ffmpeg @ffmpegArgs 2>$null
                    if ($LASTEXITCODE -ne 0) { Write-Warning "ffmpeg conversion failed for $($f.Name)" }
                } catch {
                    Write-Warning "Error during ffmpeg conversion: $($_.Exception.Message)"
                }
            }
        } else {
            $destFullPath = Join-Path $parentDir $destFileName
            Write-Host "[$script:jobIndex/$script:totalJobs] Copying: $destFileName"
            if (-not $DryRun) {
                try {
                    Copy-Item -LiteralPath $f.FullName -Destination $destFullPath -Force -ErrorAction Stop
                } catch {
                    Write-Warning "Failed to copy $($f.Name): $($_.Exception.Message)"
                }
            }
        }

        if ($MaxPerArtist) { $artistCounts[$artist]++ }
    }
}

# ------------------------------
# Main logic
# ------------------------------
# Build equivalent command string for logging
$commandArgs = @()
$commandArgs += "-Src `"$Src`""
$commandArgs += "-Dest `"$Dest`""
if ($Total) { $commandArgs += "-Total $Total" } else { $commandArgs += "-Count $Count" }
if ($ConvertToMp3) { $commandArgs += "-ConvertToMp3" }
if ($MaxPerArtist) { $commandArgs += "-MaxPerArtist $MaxPerArtist" }
$commandArgs += "-RenameScheme `"$RenameScheme`""
if ($DryRun) { $commandArgs += "-DryRun" }
$equivalentCommand = ".\RandomSongs.ps1 " + ($commandArgs -join " ")

if ($Total) {
    $allFiles = Get-ChildItem -LiteralPath $Src -Recurse -File |
                Where-Object { $audioExtensions -contains $_.Extension.ToLower() }

    $selectedFiles = $allFiles | Get-Random -Count ([Math]::Min($Total, $allFiles.Count))
    $script:totalJobs = $selectedFiles.Count
    Write-Host "`nTotal files to process: $script:totalJobs`n"

    foreach ($f in $selectedFiles) {
        $relPath = Get-RelativePath $f.DirectoryName $Src
        $targetDir = if ($relPath) { Join-Path $Dest $relPath } else { $Dest }
        Copy-FilesSafely -Files @($f) -TargetDir $targetDir
    }
} else {
    # Include the source folder itself so selecting a single folder works
    $folders = @()
    $srcItem = Get-Item -LiteralPath $Src
    if ($srcItem.PSIsContainer) { $folders += $srcItem }
    $folders += Get-ChildItem -LiteralPath $Src -Directory -Recurse

    # Preselect picks per-folder so we can compute totalJobs
    $folderSelections = @()
    foreach ($folderItem in $folders) {
        $files = Get-ChildItem -LiteralPath $folderItem.FullName -File
        $audioFiles = $files | Where-Object { $audioExtensions -contains $_.Extension.ToLower() }
        if ($audioFiles.Count -eq 0) { continue }

        $numToPick = [Math]::Min($Count, $audioFiles.Count)
        $picked = $audioFiles | Get-Random -Count $numToPick
        $otherFiles = $files | Where-Object { $audioExtensions -notcontains $_.Extension.ToLower() }

        $folderSelections += [pscustomobject]@{
            Folder     = $folderItem
            Picks      = $picked
            OtherFiles = $otherFiles
        }
    }

    # Compute total jobs for progress reporting
    $script:totalJobs = ($folderSelections | ForEach-Object { $_.Picks.Count + $_.OtherFiles.Count } | Measure-Object -Sum).Sum
    if (-not $script:totalJobs) { $script:totalJobs = 0 }

    Write-Host "`nTotal files to process: $script:totalJobs`n"

    # Process preselected files
    foreach ($sel in $folderSelections) {
        $folderItem = $sel.Folder
        $picked = $sel.Picks
        $otherFiles = $sel.OtherFiles

        # Process each file individually to preserve correct folder structure
        foreach ($f in $picked) {
            $relPath = Get-RelativePath $f.DirectoryName $Src
            $targetDir = if ($relPath) { Join-Path $Dest $relPath } else { $Dest }
            Copy-FilesSafely -Files @($f) -TargetDir $targetDir
        }

        # Copy non-audio files to the same folder structure as the processed audio files
        if ($otherFiles.Count -gt 0) {
            $folderRelPath = Get-RelativePath $folderItem.FullName $Src
            $folderTargetDir = if ($folderRelPath) { Join-Path $Dest $folderRelPath } else { $Dest }

            # Only copy non-audio files if we actually processed audio files from this folder
            if ($picked.Count -gt 0 -and $foldersWithFiles.ContainsKey($folderTargetDir)) {
                foreach ($otherFile in $otherFiles) {
                    $script:jobIndex++
                    Write-Host "[$script:jobIndex/$script:totalJobs] Copying non-audio: $($otherFile.Name)"
                    if (-not $DryRun) {
                        $destPath = Join-Path $folderTargetDir $otherFile.Name
                        Copy-Item -LiteralPath $otherFile.FullName -Destination $destPath -Force
                    }
                }
            }
        }
    }
}

Write-Host "`nDone! Processed $script:jobIndex files."
if ($DryRun) { Write-Host "Dry run: no files were actually copied or converted." }

# Log the equivalent command
Write-Host "`nEquivalent command line:"
Write-Host $equivalentCommand -ForegroundColor Green

# # Save run log
# $logFile = Join-Path $Dest "RandomSongs_LastRun.log"
# $logEntry = @"
# $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") - RandomSongs Execution Log
# Source: $Src
# Destination: $Dest
# Files Processed: $script:jobIndex
# Command: $equivalentCommand

# "@
# try {
#     Add-Content -Path $logFile -Value $logEntry
#     Write-Host "Log saved to: $logFile" -ForegroundColor Yellow
# } catch {
#     Write-Warning "Could not write to log file: $logFile"
# }
