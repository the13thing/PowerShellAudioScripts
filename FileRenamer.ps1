<#
FileRenamer.ps1
--------------------------
Renames audio files that follow the "song title by artist" format and updates their metadata tags.
Recursively searches source directory and preserves folder structure in destination.

Supports:
    - Interactive mode if no params
    - Command-line arguments for automation
    - Multiple renaming schemes
    - Configurable naming convention for parsing
    - Tags-only mode (updates metadata without renaming/moving files)
    - Metadata tagging with artist and song title
    - Preserves original folder structure
    - Dry run mode
    - Progress reporting

Usage examples:
---------------
# Fully automated
.\FileRenamer.ps1 -Src "D:\Downloads\Music" -Dest "E:\OrganizedMusic"

# With custom rename scheme
.\FileRenamer.ps1 -Src "D:\Downloads" -Dest "E:\Output" -RenameScheme "SongArtist"

# Tags only mode (no renaming/moving)
.\FileRenamer.ps1 -Src "D:\Music" -TagsOnly

# Custom naming convention
.\FileRenamer.ps1 -Src "D:\Music" -Dest "E:\Output" -NamingConvention "track by artist"

# With dry run to preview
.\FileRenamer.ps1 -Src "D:\Music" -Dest "E:\Output" -DryRun

# Interactive (if you omit params)
.\FileRenamer.ps1
#>

param(
    [string]$Src,
    [string]$Dest,
    [ValidateSet("ArtistSong", "SongArtist", "TrackArtistSong", "Original")]
    [string]$RenameScheme = "ArtistSong",
    [string]$NamingConvention = "artist-track",
    [switch]$TagsOnly,
    [switch]$DryRun
)

# ------------------------------
# Defaults & validation
# ------------------------------
if (-not $Src) { $Src = "" }
if (-not $Dest -and -not $TagsOnly) { $Dest = Join-Path (Get-Location).Path "RenamedOutput" }
if (-not $RenameScheme) { $RenameScheme = "ArtistSong" }
if (-not $NamingConvention) { $NamingConvention = "artist-track" }

# ------------------------------
# Interactive mode (if no args)
# ------------------------------
if (-not $PSBoundParameters.Count) {
    Write-Host "FileRenamer Interactive Setup"
    Write-Host "-----------------------------`n"

    $Src = Read-Host "Enter the source directory with audio files to rename"
    while (-not $Src -or -not (Test-Path $Src)) {
        $Src = Read-Host "Invalid directory. Enter a valid source path"
    }

    Write-Host "`nMode selection:"
    Write-Host "1: Rename and move files to destination directory"
    Write-Host "2: Update metadata tags only (no renaming/moving)"
    $modeChoice = Read-Host "Choose mode (1-2, default = 1)"
    $TagsOnly = ($modeChoice -eq "2")

    if (-not $TagsOnly) {
        $Dest = Read-Host "Enter the destination directory (default = RenamedOutput in current folder)"
        if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "RenamedOutput" }

        Write-Host "Rename scheme options:"
        Write-Host "  1 = ArtistSong (Artist - Song.ext) [DEFAULT]"
        Write-Host "  2 = SongArtist (Song - Artist.ext)"
        Write-Host "  3 = TrackArtistSong (01 Artist - Song.ext)"
        Write-Host "  4 = Original (keep original filename)"
        $renameChoice = Read-Host "Choose rename scheme (1-4, default = 1)"
        $RenameScheme = switch ($renameChoice) {
            "2" { "SongArtist" }
            "3" { "TrackArtistSong" }
            "4" { "Original" }
            default { "ArtistSong" }
        }
    }

    $NamingConvention = Read-Host "Enter naming convention for parsing (default = 'artist-track')"
    if (-not $NamingConvention) { $NamingConvention = "artist-track" }

    $DryRun = (Read-Host "Perform dry run (show actions only)? (y/N)") -match "^(y|Y)$"
}

# ------------------------------
# Configuration display
# ------------------------------
$audioExtensions = @(".flac", ".mp3", ".wav", ".aac", ".ogg", ".m4a", ".wma")

Write-Host "`nConfiguration:"
Write-Host "Source directory: $Src"
if ($TagsOnly) {
    Write-Host "Mode: Tags only (no renaming/moving)"
} else {
    Write-Host "Destination directory: $Dest"
    Write-Host "Rename scheme: $RenameScheme"
}
Write-Host "Naming convention: $NamingConvention"
if ($DryRun) { Write-Host "Dry run ENABLED (no files will be renamed or copied)" }

# ------------------------------
# Helper functions
# ------------------------------
function Ensure-Folder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Warning "Empty path provided to Ensure-Folder"
        return $false
    }
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Force -Path $Path | Out-Null
        }
        return $true
    }
    catch {
        Write-Warning "Failed to create directory: $Path - $($_.Exception.Message)"
        return $false
    }
}

function Sanitize-FileName {
    param($Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "Unknown"
    }
    
    # Only replace actual illegal filename characters for Windows
    # Keep Unicode characters intact as they're generally fine in modern Windows
    $sanitized = $Name -replace '[<>:"/\\|?*]', '_'
    
    # Remove control characters (0x00-0x1F) but keep printable Unicode
    $sanitized = $sanitized -replace '[\x00-\x1F]', ''
    
    # Trim whitespace and dots from start/end (Windows restriction)
    $sanitized = $sanitized.Trim(' .')
    
    # If result is empty, provide a fallback
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        return "Unknown"
    }
    
    # Ensure filename isn't too long (Windows limit is 255, leave some buffer)
    if ($sanitized.Length -gt 240) {
        $sanitized = $sanitized.Substring(0, 240).Trim(' .')
    }
    
    return $sanitized
}

function Parse-SongByArtist {
    param(
        [string]$FileName,
        [string]$NamingConvention = "artist-track"
    )
    
    # Remove file extension
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    
    # Parse based on naming convention
    $parsed = $false
    $songTitle = ""
    $artistName = ""
    
    # Convert naming convention to regex pattern
    switch ($NamingConvention.ToLower()) {
        "artist-track" {
            # Pattern: "Artist - Track" or "Artist - Track Title"
            if ($nameWithoutExt -imatch '^(.+?)\s*-\s*(.+)$') {
                $artistName = $matches[1].Trim()
                $songTitle = $matches[2].Trim()
                $parsed = $true
            }
        }
        "track by artist" {
            # Pattern: "Track by Artist" or "Track Title by Artist Name"
            if ($nameWithoutExt -imatch '^(.+?)\s+by\s+(.+)$') {
                $songTitle = $matches[1].Trim()
                $artistName = $matches[2].Trim()
                $parsed = $true
            }
        }
        "artist_track" {
            # Pattern: "Artist_Track" or "Artist Name_Track Title"
            if ($nameWithoutExt -imatch '^(.+?)_(.+)$') {
                $artistName = $matches[1].Trim()
                $songTitle = $matches[2].Trim()
                $parsed = $true
            }
        }
        default {
            # Try to parse the convention as a literal pattern
            # Replace placeholders with regex groups
            $pattern = $NamingConvention
            $pattern = $pattern -replace 'artist', '(.+?)'
            $pattern = $pattern -replace 'track', '(.+)'
            $pattern = "^$pattern$"
            
            if ($nameWithoutExt -imatch $pattern) {
                # Determine which group is which based on original convention
                if ($NamingConvention -match 'artist.*track') {
                    $artistName = $matches[1].Trim()
                    $songTitle = $matches[2].Trim()
                } else {
                    $songTitle = $matches[1].Trim()
                    $artistName = $matches[2].Trim()
                }
                $parsed = $true
            }
        }
    }
    
    # If parsing succeeded, clean up the values
    if ($parsed) {
        if ([string]::IsNullOrWhiteSpace($songTitle)) {
            $songTitle = "Unknown Song"
        }
        if ([string]::IsNullOrWhiteSpace($artistName)) {
            $artistName = "Unknown Artist"
        }
        
        return @{
            Song = $songTitle
            Artist = $artistName
            Parsed = $true
        }
    }
    
    # If no pattern matched, return original
    return @{
        Song = $nameWithoutExt
        Artist = ""
        Parsed = $false
    }
}

function Get-NewFileName {
    param(
        [string]$OriginalFileName,
        [string]$RenameScheme,
        [hashtable]$ParsedInfo,
        [string]$TrackNumber = ""
    )
    
    $fileExtension = [System.IO.Path]::GetExtension($OriginalFileName)
    
    if (-not $ParsedInfo.Parsed -or $RenameScheme -eq "Original") {
        return $OriginalFileName
    }
    
    switch ($RenameScheme) {
        "ArtistSong" {
            return Sanitize-FileName("$($ParsedInfo.Artist) - $($ParsedInfo.Song)$fileExtension")
        }
        "SongArtist" {
            return Sanitize-FileName("$($ParsedInfo.Song) - $($ParsedInfo.Artist)$fileExtension")
        }
        "TrackArtistSong" {
            $trackPrefix = if ($TrackNumber) { "$TrackNumber " } else { "" }
            return Sanitize-FileName("$trackPrefix$($ParsedInfo.Artist) - $($ParsedInfo.Song)$fileExtension")
        }
        default {
            return $OriginalFileName
        }
    }
}

function Update-AudioMetadata {
    param(
        [string]$FilePath,
        [hashtable]$ParsedInfo
    )
    
    if (-not $ParsedInfo.Parsed) {
        return $false
    }
    
    # Skip metadata update for empty files (test files)
    $fileInfo = Get-Item $FilePath -ErrorAction SilentlyContinue
    if (-not $fileInfo -or $fileInfo.Length -eq 0) {
        Write-Host "  → Skipping metadata update (empty or missing file)" -ForegroundColor Yellow
        return $true
    }
    
    if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
        Write-Host "  → ffmpeg not found, skipping metadata update" -ForegroundColor Yellow
        return $false
    }
    
    # Skip metadata update for files with paths that might cause ffmpeg issues
    if ($FilePath.Length -gt 200 -or $FilePath -match '[\x00-\x1F\x7F]') {
        Write-Host "  → Skipping metadata update (problematic file path)" -ForegroundColor Yellow
        return $true
    }
    if ($fileInfo.Length -eq 0) {
        Write-Host "  → Skipping metadata update (empty test file)" -ForegroundColor Yellow
        return $true
    }
    
    if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) {
        Write-Host "  → ffmpeg not found, skipping metadata update" -ForegroundColor Yellow
        return $false
    }
    
    # Skip metadata update for files with paths that might cause ffmpeg issues
    if ($FilePath.Length -gt 200 -or $FilePath -match '[\x00-\x1F\x7F]') {
        Write-Host "  → Skipping metadata update (problematic file path)" -ForegroundColor Yellow
        return $true
    }
    
    try {
        # Use Windows temp directory with a simple ASCII filename to avoid Unicode issues
        $tempFile = Join-Path $env:TEMP "ffmpeg_temp_$(Get-Random).mp3"
        
        # Ensure the file actually exists and is readable
        if (-not (Test-Path $FilePath)) {
            Write-Host "  → File not found for metadata update" -ForegroundColor Yellow
            return $false
        }
        
        # Clean metadata values for ffmpeg - escape quotes and problematic characters
        $cleanArtist = $ParsedInfo.Artist -replace '"', '""' -replace "[\r\n]", ""
        $cleanTitle = $ParsedInfo.Song -replace '"', '""' -replace "[\r\n]", ""
        
        # Debug: Show what we're trying to set
        Write-Host "  → Setting Artist: '$cleanArtist'" -ForegroundColor DarkGray
        Write-Host "  → Setting Title: '$cleanTitle'" -ForegroundColor DarkGray
        
        # Get file extension to determine format-specific metadata handling
        $fileExt = [System.IO.Path]::GetExtension($FilePath).ToLower()
        
        # Use & operator with proper argument array instead of Start-Process
        Write-Host "  → Running ffmpeg for $fileExt file..." -ForegroundColor DarkGray
        
        # Use format-specific metadata parameters
        if ($fileExt -eq ".mp3") {
            # For MP3, also set ID3v2 tags explicitly
            $result = & ffmpeg -y -loglevel error -i $FilePath -c copy -id3v2_version 3 -metadata "artist=$cleanArtist" -metadata "title=$cleanTitle" $tempFile 2>&1
        } else {
            # For other formats, use standard metadata
            $result = & ffmpeg -y -loglevel error -i $FilePath -c copy -metadata "artist=$cleanArtist" -metadata "title=$cleanTitle" $tempFile 2>&1
        }
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tempFile)) {
            # Use Copy-Item and Remove-Item for better Unicode support
            Copy-Item $tempFile $FilePath -Force
            Remove-Item $tempFile -Force
            
            # Verify metadata was written by reading it back
            try {
                $verifyResult = & ffprobe -v quiet -show_entries format_tags=artist,title -of default=noprint_wrappers=1 $FilePath 2>$null
                Write-Host "  → Verification: $verifyResult" -ForegroundColor DarkGray
            } catch {
                # Verification failed, but update might still be successful
            }
            
            Write-Host "  → Metadata updated successfully" -ForegroundColor Green
            return $true
        } else {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
            Write-Host "  → ffmpeg failed to update metadata (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
            if ($result) {
                Write-Host "  → ffmpeg output: $result" -ForegroundColor DarkGray
            }
            return $false
        }
    }
    catch {
        Write-Host "  → Error updating metadata: $($_.Exception.Message)" -ForegroundColor Yellow
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        return $false
    }
}

function Get-RelativePath {
    param(
        [string]$FullPath,
        [string]$BasePath
    )
    
    if ([string]::IsNullOrWhiteSpace($FullPath) -or [string]::IsNullOrWhiteSpace($BasePath)) {
        if ($FullPath) { 
            return Split-Path $FullPath -Leaf -ErrorAction SilentlyContinue 
        } else { 
            return "unknown" 
        }
    }
    
    try {
        $basePath = (Get-Item $BasePath -ErrorAction Stop).FullName.TrimEnd('\')
        $fullPath = (Get-Item $FullPath -ErrorAction Stop).FullName
        
        if ($fullPath.StartsWith($basePath, [StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $fullPath.Substring($basePath.Length).TrimStart('\')
            return $relativePath
        }
    }
    catch {
        # Fallback to manual path processing
        try {
            $basePath = $BasePath.TrimEnd('\')
            if ($FullPath.StartsWith($basePath, [StringComparison]::OrdinalIgnoreCase)) {
                return $FullPath.Substring($basePath.Length).TrimStart('\')
            }
        }
        catch {
            # Final fallback
        }
    }
    
    if ($FullPath) { 
        return Split-Path $FullPath -Leaf -ErrorAction SilentlyContinue 
    } else { 
        return "unknown" 
    }
}

function Process-AudioFile {
    param(
        [string]$SourceFile,
        [string]$SourceRoot,
        [string]$DestinationRoot,
        [string]$RenameScheme,
        [bool]$IsDryRun,
        [bool]$TagsOnly = $false,
        [string]$NamingConvention = "artist-track"
    )
    
    # Validate input parameters
    if ([string]::IsNullOrWhiteSpace($SourceFile)) {
        Write-Warning "Empty source file path provided"
        return $false
    }
    
    # Get relative path to preserve folder structure
    $relativePath = Get-RelativePath $SourceFile $SourceRoot
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        $relativePath = if ($SourceFile) { Split-Path $SourceFile -Leaf -ErrorAction SilentlyContinue } else { "unknown.mp3" }
    }
    
    $relativeDir = ""
    if ($relativePath -and $relativePath.Contains('\')) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
                $relativeDir = Split-Path $relativePath -Parent -ErrorAction Stop
            }
        }
        catch {
            $relativeDir = ""
        }
    }
    
    # Parse filename
    $originalFileName = if ($SourceFile) { Split-Path $SourceFile -Leaf -ErrorAction SilentlyContinue } else { "unknown.mp3" }
    if ([string]::IsNullOrWhiteSpace($originalFileName)) {
        Write-Warning "Could not extract filename from: $SourceFile"
        return $false
    }
    
    $parsedInfo = Parse-SongByArtist $originalFileName $NamingConvention
    
    # Handle TagsOnly mode differently
    if ($TagsOnly) {
        # Tags only mode - no file copying/renaming
        $actionText = if ($parsedInfo.Parsed) {
            "Updating metadata: $relativePath"
        } else {
            "No pattern match: $relativePath (skipping metadata update)"
        }
        
        Write-Host $actionText
        
        if ($parsedInfo.Parsed) {
            Write-Host "  → Artist: '$($parsedInfo.Artist)'" -ForegroundColor Cyan
            Write-Host "  → Song: '$($parsedInfo.Song)'" -ForegroundColor Cyan
        }
        
        if (-not $IsDryRun) {
            if ($parsedInfo.Parsed) {
                $metadataSuccess = Update-AudioMetadata -FilePath $SourceFile -ParsedInfo $parsedInfo
                return $metadataSuccess
            } else {
                Write-Host "  → Skipped (no pattern match)" -ForegroundColor Yellow
                return $true
            }
        }
        return $true
    }
    
    # Regular rename/move mode continues below...
    
    # Get new filename
    $newFileName = Get-NewFileName -OriginalFileName $originalFileName -RenameScheme $RenameScheme -ParsedInfo $parsedInfo
    
    # Create destination path
    $destDir = if ($relativeDir -and -not [string]::IsNullOrWhiteSpace($relativeDir)) { 
        try {
            Join-Path $DestinationRoot $relativeDir -ErrorAction Stop
        }
        catch {
            $DestinationRoot
        }
    } else { 
        $DestinationRoot 
    }
    
    # Ensure destDir is never empty
    if ([string]::IsNullOrWhiteSpace($destDir)) {
        $destDir = $DestinationRoot
    }
    
    try {
        $destFilePath = Join-Path $destDir $newFileName -ErrorAction Stop
    }
    catch {
        $destFilePath = [System.IO.Path]::Combine($destDir, $newFileName)
    }
    
    # Display action
    $actionText = if ($parsedInfo.Parsed) {
        if ($newFileName -ne $originalFileName) {
            "Parsing & Renaming: $relativePath → $newFileName"
        } else {
            "Parsing (Original name): $relativePath"
        }
    } else {
        "No pattern match: $relativePath (copying as-is)"
    }
    
    Write-Host $actionText
    
    if ($parsedInfo.Parsed) {
        Write-Host "  → Artist: '$($parsedInfo.Artist)'" -ForegroundColor Cyan
        Write-Host "  → Song: '$($parsedInfo.Song)'" -ForegroundColor Cyan
    }
    
    if (-not $IsDryRun) {
        try {
            # Validate destination directory path
            if ([string]::IsNullOrWhiteSpace($destDir)) {
                Write-Warning "Empty destination directory for file: $originalFileName"
                return $false
            }
            
            # Create destination directory
            if (-not (Ensure-Folder $destDir)) {
                Write-Warning "Failed to create destination directory: $destDir"
                return $false
            }
            
            # Copy file
            Copy-Item -LiteralPath $SourceFile -Destination $destFilePath -Force -ErrorAction Stop
            
            # Update metadata if parsed successfully
            if ($parsedInfo.Parsed) {
                $metadataSuccess = Update-AudioMetadata -FilePath $destFilePath -ParsedInfo $parsedInfo
                if (-not $metadataSuccess) {
                    Write-Warning "  Failed to update metadata for $newFileName"
                }
            }
            
            return $true
        }
        catch {
            Write-Warning "  Failed to copy $originalFileName`: $($_.Exception.Message)"
            return $false
        }
    }
    
    return $true
}

# ------------------------------
# Main logic
# ------------------------------

# Validate source directory
if (-not (Test-Path $Src)) {
    Write-Error "Source directory not found: $Src"
    exit 1
}

# Find all audio files recursively
Write-Host "`nScanning for audio files..."
try {
    $audioFiles = Get-ChildItem -Path $Src -Recurse -File | Where-Object { 
        $audioExtensions -contains $_.Extension.ToLower() 
    }
} catch {
    Write-Error "Error scanning source directory: $($_.Exception.Message)"
    exit 1
}

if ($audioFiles.Count -eq 0) {
    Write-Error "No audio files found in source directory."
    exit 1
}

Write-Host "Found $($audioFiles.Count) audio files to process.`n"

# Create destination directory if it doesn't exist
if (-not $DryRun) {
    Ensure-Folder $Dest
}

# Process files
$successCount = 0
$failCount = 0
$parsedCount = 0
$currentIndex = 0

Write-Host "Processing files..."
Write-Host "==================="

foreach ($audioFile in $audioFiles) {
    $currentIndex++
    Write-Host "[$currentIndex/$($audioFiles.Count)]" -NoNewline -ForegroundColor Yellow
    Write-Host " " -NoNewline
    
    # Validate file object
    if (-not $audioFile -or [string]::IsNullOrWhiteSpace($audioFile.FullName)) {
        Write-Host "ERROR: Invalid file object at index $currentIndex" -ForegroundColor Red
        $failCount++
        Write-Host ""
        continue
    }
    
    # Check if file has "by" pattern for statistics
    $tempParsed = Parse-SongByArtist $audioFile.Name $NamingConvention
    if ($tempParsed.Parsed) { $parsedCount++ }
    
    if (Process-AudioFile -SourceFile $audioFile.FullName -SourceRoot $Src -DestinationRoot $Dest -RenameScheme $RenameScheme -IsDryRun $DryRun -TagsOnly $TagsOnly -NamingConvention $NamingConvention) {
        $successCount++
    } else {
        $failCount++
    }
    
    Write-Host ""
}

# Results summary
Write-Host "==================="
Write-Host "Processing Summary:"
Write-Host "Total files processed: $($audioFiles.Count)"
Write-Host "Successfully processed: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
Write-Host "Files with 'by' pattern: $parsedCount" -ForegroundColor Cyan
Write-Host "Success rate: $([Math]::Round(($successCount / $audioFiles.Count) * 100, 1))%"

if ($DryRun) {
    Write-Host "`nDry run completed. No files were actually copied or renamed."
} else {
    Write-Host "`nFiles processed to: $Dest" -ForegroundColor Green
}

# Build equivalent command string for logging
$commandArgs = @()
$commandArgs += "-Src '$Src'"
$commandArgs += "-Dest '$Dest'"
if ($RenameScheme -ne "ArtistSong") { $commandArgs += "-RenameScheme '$RenameScheme'" }
if ($DryRun) { $commandArgs += "-DryRun" }
$equivalentCommand = ".\FileRenamer.ps1 " + ($commandArgs -join " ")

Write-Host "`nEquivalent command line:"
Write-Host $equivalentCommand -ForegroundColor Green
