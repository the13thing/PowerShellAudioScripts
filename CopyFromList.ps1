<#
CopyFromList.ps1
--------------------------
Copies audio files from a list oWrite-Host "`nConfiguration:"
Write-Host "Source file: $Src"
Write-Host "Destination folder: $Dest"
Write-Host "Rename scheme: $RenameScheme"
if ($ConvertToMp3) { Write-Host "FLAC → MP3 conversion ENABLED" }
if ($DryRun) { Write-Host "Dry run ENABLED (no files will be copied or converted)" }l file paths while preserving folder structure
starting from the artist folder.

The input file should contain one full file path per line.

Supports:
    - Interactive mode if no params
    - Command-line arguments for automation
    - Preserves folder structure starting from artist folder
    - FLAC to MP3 conversion (optional)
    - Dry run mode
    - Progress reporting

Usage examples:
---------------
# Fully automated
.\CopyFromList.ps1 -Src "playlist-FullPaths.txt" -Dest "E:\Output"

# With FLAC conversion
.\CopyFromList.ps1 -Src "playlist-FullPaths.txt" -Dest "E:\Output" -ConvertToMp3

# With file renaming scheme
.\CopyFromList.ps1 -Src "playlist-FullPaths.txt" -Dest "E:\Output" -RenameScheme "ArtistSong"

# Combined options
.\CopyFromList.ps1 -Src "playlist-FullPaths.txt" -Dest "E:\Output" -ConvertToMp3 -RenameScheme "TrackArtistSong"

# Interactive (if you omit params)
.\CopyFromList.ps1
#>

param(
    [string]$Src,
    [string]$Dest,
    [switch]$ConvertToMp3,
    [ValidateSet("Original", "ArtistSong", "SongArtist", "TrackArtistSong")]
    [string]$RenameScheme = "Original",
    [switch]$DryRun
)

# ------------------------------
# Defaults & validation
# ------------------------------
if (-not $Src) { $Src = "" }
if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }
if (-not $RenameScheme) { $RenameScheme = "Original" }

# ------------------------------
# Interactive mode (if no args)
# ------------------------------
if (-not $PSBoundParameters.Count) {
    Write-Host "CopyFromList Interactive Setup"
    Write-Host "----------------------------------`n"

    $Src = Read-Host "Enter the full paths file (e.g., playlist-FullPaths.txt)"
    while (-not $Src -or -not (Test-Path $Src)) {
        $Src = Read-Host "Invalid file. Enter a valid file path"
    }

    $Dest = Read-Host "Enter the destination folder (default = Output in current folder)"
    if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }

    $ConvertToMp3 = (Read-Host "Convert FLAC to MP3? (y/N)") -match "^(y|Y)$"

    Write-Host "Rename scheme options:"
    Write-Host "  1 = Original (keep original filename)"
    Write-Host "  2 = ArtistSong (Artist - Song.ext)"
    Write-Host "  3 = SongArtist (Song - Artist.ext)"
    Write-Host "  4 = TrackArtistSong (01 Artist - Song.ext)"
    $renameChoice = Read-Host "Choose rename scheme (1-4, default = 1)"
    $RenameScheme = switch ($renameChoice) {
        "2" { "ArtistSong" }
        "3" { "SongArtist" }
        "4" { "TrackArtistSong" }
        default { "Original" }
    }

    $DryRun = (Read-Host "Perform dry run (show actions only)? (y/N)") -match "^(y|Y)$"
}

# ------------------------------
# Configuration display
# ------------------------------
$audioExtensions = @(".flac", ".mp3", ".wav", ".aac", ".ogg", ".m4a", ".wma")

Write-Host "`nConfiguration:"
Write-Host "Source file: $Src"
Write-Host "Destination folder: $Dest"
Write-Host "Rename scheme: $RenameScheme"
if ($ConvertToMp3) { Write-Host "FLAC → MP3 conversion ENABLED" }
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

function Get-AudioMetadata {
    param([string]$FilePath)
    
    if (-not (Get-Command "ffprobe" -ErrorAction SilentlyContinue)) {
        Write-Warning "ffprobe not found. Cannot extract metadata for renaming."
        return @{ Artist = ""; Title = ""; Track = "" }
    }
    
    try {
        $metadataJson = & ffprobe -v quiet -print_format json -show_format $FilePath 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @{ Artist = ""; Title = ""; Track = "" }
        }
        
        $metadata = $metadataJson | ConvertFrom-Json
        $tags = $metadata.format.tags
        
        # Try different tag name variations
        $artist = ""
        $title = ""
        $track = ""
        
        if ($tags) {
            # Artist variations
            if ($tags.artist) { $artist = $tags.artist }
            elseif ($tags.ARTIST) { $artist = $tags.ARTIST }
            elseif ($tags.albumartist) { $artist = $tags.albumartist }
            elseif ($tags.ALBUMARTIST) { $artist = $tags.ALBUMARTIST }
            
            # Title variations
            if ($tags.title) { $title = $tags.title }
            elseif ($tags.TITLE) { $title = $tags.TITLE }
            
            # Track variations
            if ($tags.track) { $track = $tags.track }
            elseif ($tags.TRACK) { $track = $tags.TRACK }
            elseif ($tags.tracknumber) { $track = $tags.tracknumber }
            elseif ($tags.TRACKNUMBER) { $track = $tags.TRACKNUMBER }
        }
        
        # Clean track number (remove "/total" if present)
        if ($track -and $track.Contains("/")) {
            $track = $track.Split("/")[0]
        }
        
        # Pad track number to 2 digits
        if ($track -and $track -match "^\d+$") {
            $track = $track.PadLeft(2, '0')
        }
        
        return @{
            Artist = $artist.Trim()
            Title = $title.Trim()
            Track = $track.Trim()
        }
    }
    catch {
        Write-Warning "Error extracting metadata from $FilePath`: $($_.Exception.Message)"
        return @{ Artist = ""; Title = ""; Track = "" }
    }
}

function Get-RenamedFileName {
    param(
        [string]$OriginalFileName,
        [string]$RenameScheme,
        [hashtable]$Metadata
    )
    
    $fileExtension = [System.IO.Path]::GetExtension($OriginalFileName)
    $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalFileName)
    
    switch ($RenameScheme) {
        "Original" {
            return $OriginalFileName
        }
        "ArtistSong" {
            if ($Metadata.Artist -and $Metadata.Title) {
                return Sanitize-FileName("$($Metadata.Artist) - $($Metadata.Title)$fileExtension")
            }
            return $OriginalFileName
        }
        "SongArtist" {
            if ($Metadata.Artist -and $Metadata.Title) {
                return Sanitize-FileName("$($Metadata.Title) - $($Metadata.Artist)$fileExtension")
            }
            return $OriginalFileName
        }
        "TrackArtistSong" {
            if ($Metadata.Artist -and $Metadata.Title) {
                $trackPrefix = if ($Metadata.Track) { "$($Metadata.Track) " } else { "" }
                return Sanitize-FileName("$trackPrefix$($Metadata.Artist) - $($Metadata.Title)$fileExtension")
            }
            return $OriginalFileName
        }
        default {
            return $OriginalFileName
        }
    }
}

function Get-ArtistFolderStructure {
    param([string]$FilePath)
    
    # Try to find the artist folder in the path
    # This assumes the structure is like: .../{Artist}/{Album}/{Song}
    # We'll take the last 2 or 3 directories as the structure to preserve
    
    $pathParts = $FilePath.Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)
    
    if ($pathParts.Length -ge 3) {
        # Take artist and album folders (last 2 directories before filename)
        $fileName = $pathParts[-1]
        $albumFolder = $pathParts[-2]
        $artistFolder = $pathParts[-3]
        
        return Join-Path $artistFolder $albumFolder
    } elseif ($pathParts.Length -eq 2) {
        # Just artist folder
        return $pathParts[-2]
    } else {
        # Fallback to just the filename
        return ""
    }
}

function Copy-FileWithStructure {
    param(
        [string]$SourceFile,
        [string]$DestinationRoot,
        [bool]$ConvertFlac,
        [string]$RenameScheme,
        [bool]$IsDryRun
    )
    
    if (-not (Test-Path $SourceFile)) {
        Write-Warning "Source file not found: $SourceFile"
        return $false
    }
    
    # Get the folder structure to preserve
    $relativePath = Get-ArtistFolderStructure $SourceFile
    
    # Create destination path
    $destFolder = if ($relativePath) { 
        Join-Path $DestinationRoot $relativePath 
    } else { 
        $DestinationRoot 
    }
    
    $sourceFileInfo = Get-Item $SourceFile
    
    # Extract metadata for renaming (if needed)
    $metadata = @{ Artist = ""; Title = ""; Track = "" }
    if ($RenameScheme -ne "Original") {
        $metadata = Get-AudioMetadata $SourceFile
    }
    
    # Get the new filename based on rename scheme
    $originalFileName = $sourceFileInfo.Name
    $newFileName = Get-RenamedFileName -OriginalFileName $originalFileName -RenameScheme $RenameScheme -Metadata $metadata
    
    # Handle FLAC conversion
    if ($ConvertFlac -and $sourceFileInfo.Extension.ToLower() -eq ".flac") {
        $newFileName = [System.IO.Path]::ChangeExtension($newFileName, ".mp3")
        $destFullPath = Join-Path $destFolder $newFileName
        
        $displayAction = if ($RenameScheme -ne "Original" -and $newFileName -ne [System.IO.Path]::ChangeExtension($originalFileName, ".mp3")) {
            "Converting FLAC → MP3 + Renaming: $relativePath\$newFileName"
        } else {
            "Converting FLAC → MP3: $relativePath\$newFileName"
        }
        Write-Host $displayAction
        
        if (-not $IsDryRun) {
            Ensure-Folder $destFolder
            
            if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
                Write-Error "ffmpeg not found in PATH. Please install ffmpeg to use conversion."
                return $false
            }
            
            $ffmpegArgs = @(
                "-y", "-loglevel", "error",
                "-i", $SourceFile,
                "-codec:a", "libmp3lame", "-qscale:a", "2",
                "-map_metadata", "0", "-id3v2_version", "3",
                "-map", "0:a", "-map", "0:v?", "-disposition:v", "attached_pic",
                "-c:v", "mjpeg", "-vf", "scale=300:300:force_original_aspect_ratio=decrease",
                "-pix_fmt", "yuvj420p",
                $destFullPath
            )
            
            try {
                & ffmpeg @ffmpegArgs 2>$null
                if ($LASTEXITCODE -ne 0) { 
                    Write-Warning "ffmpeg conversion failed for $($sourceFileInfo.Name)"
                    return $false
                }
            } catch {
                Write-Warning "Error during ffmpeg conversion: $($_.Exception.Message)"
                return $false
            }
        }
    } else {
        # Regular copy
        $destFullPath = Join-Path $destFolder $newFileName
        
        $displayAction = if ($RenameScheme -ne "Original" -and $newFileName -ne $originalFileName) {
            "Copying + Renaming: $relativePath\$newFileName"
        } else {
            "Copying: $relativePath\$newFileName"
        }
        Write-Host $displayAction
        
        if (-not $IsDryRun) {
            Ensure-Folder $destFolder
            
            try {
                Copy-Item -LiteralPath $SourceFile -Destination $destFullPath -Force -ErrorAction Stop
            } catch {
                Write-Warning "Failed to copy $($sourceFileInfo.Name): $($_.Exception.Message)"
                return $false
            }
        }
    }
    
    return $true
}

# ------------------------------
# Main logic
# ------------------------------

# Validate source file
if (-not (Test-Path $Src)) {
    Write-Error "Source file not found: $Src"
    exit 1
}

# Read file paths
Write-Host "`nReading file paths..."
try {
    $filePaths = Get-Content -Path $Src -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
} catch {
    Write-Error "Error reading source file: $($_.Exception.Message)"
    exit 1
}

if ($filePaths.Count -eq 0) {
    Write-Error "No file paths found in source file."
    exit 1
}

Write-Host "Found $($filePaths.Count) file paths to process.`n"

# Create destination folder if it doesn't exist
if (-not $DryRun) {
    Ensure-Folder $Dest
}

# Process files
$successCount = 0
$failCount = 0
$currentIndex = 0

Write-Host "Processing files..."
Write-Host "==================="

foreach ($filePath in $filePaths) {
    $currentIndex++
    $filePath = $filePath.Trim()
    
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        continue
    }
    
    Write-Host "[$currentIndex/$($filePaths.Count)] Processing: $(Split-Path $filePath -Leaf)"
    
    if (Copy-FileWithStructure -SourceFile $filePath -DestinationRoot $Dest -ConvertFlac $ConvertToMp3 -RenameScheme $RenameScheme -IsDryRun $DryRun) {
        $successCount++
    } else {
        $failCount++
    }
}

# Results summary
Write-Host "`n==================="
Write-Host "Copy Summary:"
Write-Host "Total files processed: $($filePaths.Count)"
Write-Host "Successfully processed: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Success rate: $([Math]::Round(($successCount / $filePaths.Count) * 100, 1))%"

if ($DryRun) {
    Write-Host "`nDry run completed. No files were actually copied or converted."
} else {
    Write-Host "`nFiles copied to: $Dest" -ForegroundColor Green
}

# Build equivalent command string for logging
$commandArgs = @()
$commandArgs += "-Src '$Src'"
$commandArgs += "-Dest '$Dest'"
if ($ConvertToMp3) { $commandArgs += "-ConvertToMp3" }
if ($RenameScheme -ne "Original") { $commandArgs += "-RenameScheme '$RenameScheme'" }
if ($DryRun) { $commandArgs += "-DryRun" }
$equivalentCommand = ".\CopyFromList.ps1 " + ($commandArgs -join " ")

Write-Host "`nEquivalent command line:"
Write-Host $equivalentCommand -ForegroundColor Green
