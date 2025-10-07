<#
PlaylistGen.ps1
--------------------------
Searches for audio files based on a CSV file containing song names and artists,
or creates a playlist from all audio files in a folder (recursive search).

The CSV should have format: "song name, artist name"

Supports:
    - Interactive mode if no params
    - Command-line arguments for automation
    - Fuzzy matching for artist names (default 80% threshold)
    - Fuzzy matching for song titles (default 50% threshold)
    - Multiple playlist formats (M3U, PLS, WPL)
    - Relative or absolute file paths in playlists
    - All files mode (recursive folder search when no CSV specified)

Usage examples:
---------------
# Fully automated with CSV and relative paths
.\PlaylistGen.ps1 -Src "D:\Music" -Dest "E:\Playlists" -CsvSrc "songs.csv" -ArtistThreshold 80 -SongThreshold 50 -PathType "Relative"

# With absolute paths for better compatibility
.\PlaylistGen.ps1 -Src "D:\Music" -Dest "E:\Playlists" -CsvSrc "songs.csv" -PathType "Absolute"

# Include all audio files (no CSV needed)
.\PlaylistGen.ps1 -Src "D:\Music" -Dest "E:\Playlists" -AllFiles

# Interactive (if you omit params)
.\PlaylistGen.ps1
#>

param(
    [string]$Src,
    [string]$Dest,
    [string]$CsvSrc,
    [int]$ArtistThreshold = 80,
    [int]$SongThreshold = 50,
    [string]$PlaylistFormat = "M3U",
    [string]$PlaylistName = "GeneratedPlaylist",
    [string]$PathType = "Relative",
    [switch]$DryRun,
    [switch]$AllFiles
)

# ------------------------------
# Defaults & validation
# ------------------------------
if (-not $Src) { $Src = (Get-Location).Path }
if (-not $Dest) { $Dest = (Get-Location).Path }

# If no CsvSrc specified or empty string, we'll generate playlist with all audio files
if ([string]::IsNullOrWhiteSpace($CsvSrc)) { 
    $AllFiles = $true
    $CsvSrc = $null
} else {
    # Default CSV path if only directory specified
    if (Test-Path $CsvSrc -PathType Container) {
        $CsvSrc = Join-Path $CsvSrc "addToPlaylist.csv"
    }
}

$allowedFormats = @("M3U", "PLS", "WPL")
if (-not $allowedFormats -contains $PlaylistFormat.ToUpper()) {
    $PlaylistFormat = "M3U"
}

$allowedPathTypes = @("Relative", "Absolute")
if (-not $allowedPathTypes -contains $PathType) {
    $PathType = "Relative"
}

# ------------------------------
# Interactive mode (if no args)
# ------------------------------
if (-not $PSBoundParameters.Count) {
    Write-Host "PlaylistGen Interactive Setup"
    Write-Host "----------------------------------`n"

    $Src = Read-Host "Enter the source music folder (default = current folder)"
    if (-not $Src) { $Src = (Get-Location).Path }
    while (-not (Test-Path $Src)) {
        $Src = Read-Host "Invalid source. Enter a valid folder path"
    }

    $Dest = Read-Host "Enter the destination folder for playlist (default = current folder)"
    if (-not $Dest) { $Dest = (Get-Location).Path }

    Write-Host "`nPlaylist source:"
    Write-Host "1: Use CSV file with specific songs"
    Write-Host "2: Include all audio files in source folder (recursive)"
    $sourceChoice = Read-Host "Enter choice (1-2)"
    
    if ($sourceChoice -eq "2") {
        $AllFiles = $true
        $CsvSrc = $null
    } else {
        $CsvSrc = Read-Host "Enter the CSV file path (default = addToPlaylist.csv in current folder)"
        if (-not $CsvSrc) { $CsvSrc = Join-Path (Get-Location).Path "addToPlaylist.csv" }
        while (-not (Test-Path $CsvSrc)) {
            $CsvSrc = Read-Host "Invalid CSV file. Enter a valid file path"
        }
    }

    $ArtistThreshold = Read-Host "Artist name matching threshold percentage (default = 80)"
    if (-not $ArtistThreshold) { $ArtistThreshold = 80 } else { $ArtistThreshold = [int]$ArtistThreshold }

    $SongThreshold = Read-Host "Song title matching threshold percentage (default = 50)"
    if (-not $SongThreshold) { $SongThreshold = 50 } else { $SongThreshold = [int]$SongThreshold }

    Write-Host "Choose playlist format:"
    Write-Host "1: M3U (default)"
    Write-Host "2: PLS"
    Write-Host "3: WPL"
    $choice = Read-Host "Enter choice (1-3)"
    switch ($choice) {
        "2"     { $PlaylistFormat = "PLS" }
        "3"     { $PlaylistFormat = "WPL" }
        default { $PlaylistFormat = "M3U" }
    }

    $PlaylistName = Read-Host "Enter playlist name (default = GeneratedPlaylist)"
    if (-not $PlaylistName) { $PlaylistName = "GeneratedPlaylist" }

    Write-Host "Choose path type for playlist entries:"
    Write-Host "1: Relative paths (default)"
    Write-Host "2: Absolute paths"
    $pathChoice = Read-Host "Enter choice (1-2)"
    switch ($pathChoice) {
        "2"     { $PathType = "Absolute" }
        default { $PathType = "Relative" }
    }

    $DryRun = (Read-Host "Perform dry run (show matches only)? (y/N)") -match "^(y|Y)$"
}

# ------------------------------
# Configuration display
# ------------------------------
$audioExtensions = @(".flac", ".mp3", ".wav", ".aac", ".ogg", ".wma")

Write-Host "`nConfiguration:"
Write-Host "Source music folder: $Src"
Write-Host "Destination folder: $Dest"
if ($AllFiles) {
    Write-Host "Mode: All audio files (recursive)"
} else {
    Write-Host "CSV file: $CsvSrc"
}
Write-Host "Artist matching threshold: $ArtistThreshold%"
Write-Host "Song matching threshold: $SongThreshold%"
Write-Host "Playlist format: $PlaylistFormat"
Write-Host "Playlist name: $PlaylistName"
Write-Host "Path type: $PathType"
if ($DryRun) { Write-Host "Dry run ENABLED (no playlist will be created)" }

# ------------------------------
# Helper functions
# ------------------------------
function Calculate-StringSimilarity {
    param(
        [string]$String1,
        [string]$String2
    )
    
    if ([string]::IsNullOrEmpty($String1) -or [string]::IsNullOrEmpty($String2)) {
        return 0
    }
    
    # Convert to lowercase for comparison
    $s1 = $String1.ToLower().Trim()
    $s2 = $String2.ToLower().Trim()
    
    if ($s1 -eq $s2) { return 100 }
    
    # Simple similarity calculation using common substrings
    $len1 = $s1.Length
    $len2 = $s2.Length
    
    if ($len1 -eq 0 -or $len2 -eq 0) { return 0 }
    
    # Check if one string contains the other
    if ($s1.Contains($s2) -or $s2.Contains($s1)) {
        $minLen = [Math]::Min($len1, $len2)
        $maxLen = [Math]::Max($len1, $len2)
        return [Math]::Round(($minLen / $maxLen) * 100, 2)
    }
    
    # Count matching characters in similar positions
    $matches = 0
    $maxLen = [Math]::Max($len1, $len2)
    $minLen = [Math]::Min($len1, $len2)
    
    for ($i = 0; $i -lt $minLen; $i++) {
        if ($s1[$i] -eq $s2[$i]) {
            $matches++
        }
    }
    
    # Also check for common substrings of length 2 or more
    $commonSubstrings = 0
    for ($i = 0; $i -lt ($len1 - 1); $i++) {
        $substring = $s1.Substring($i, 2)
        if ($s2.Contains($substring)) {
            $commonSubstrings++
        }
    }
    
    # Calculate similarity percentage
    $positionSimilarity = ($matches / $maxLen) * 50
    $substringSimilarity = ($commonSubstrings / [Math]::Max(1, $len1 - 1)) * 50
    $similarity = $positionSimilarity + $substringSimilarity
    
    return [Math]::Round([Math]::Min($similarity, 100), 2)
}

function Get-AudioMetadata {
    param([string]$Path)
    
    $metadata = @{
        Artist = ""
        Title = ""
        Album = ""
    }
    
    # Validate input path
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $metadata
    }
    
    try {
        # Try to get metadata using ffprobe
        if (Get-Command "ffprobe" -ErrorAction SilentlyContinue) {
            $artistResult = & ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$Path" 2>$null
            $titleResult = & ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$Path" 2>$null
            $albumResult = & ffprobe -v error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$Path" 2>$null
            
            if ($artistResult) { $metadata.Artist = $artistResult.Trim() }
            if ($titleResult) { $metadata.Title = $titleResult.Trim() }
            if ($albumResult) { $metadata.Album = $albumResult.Trim() }
        }
    } catch {
        # Fallback to filename parsing if ffprobe fails
    }
    
    # Fallback to folder/filename if metadata is empty
    if (-not $metadata.Artist) {
        try {
            $parentDir = Split-Path $Path -Parent -ErrorAction SilentlyContinue
            if ($parentDir) {
                $metadata.Artist = Split-Path $parentDir -Leaf -ErrorAction SilentlyContinue
            }
            if (-not $metadata.Artist) {
                $metadata.Artist = "Unknown Artist"
            }
        } catch {
            $metadata.Artist = "Unknown Artist"
        }
    }
    if (-not $metadata.Title) {
        try {
            $metadata.Title = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        } catch {
            $metadata.Title = "Unknown Title"
        }
    }
    
    return $metadata
}

function Get-PlaylistPath {
    param(
        [string]$FilePath,
        [string]$SourcePath,
        [string]$PathType
    )
    
    # Validate input parameters
    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return ""
    }
    
    if ($PathType -eq "Absolute") {
        return $FilePath
    } else {
        # Return relative path from source directory
        if ([string]::IsNullOrWhiteSpace($SourcePath)) {
            return $FilePath
        }
        
        if ($FilePath.StartsWith($SourcePath, [StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $FilePath.Substring($SourcePath.Length).TrimStart('\', '/')
            return $relativePath
        } else {
            # If file is not under source path, return absolute path as fallback
            return $FilePath
        }
    }
}

function Find-MatchingFiles {
    param(
        [string]$SourcePath,
        [string]$TargetArtist,
        [string]$TargetSong,
        [int]$ArtistThreshold,
        [int]$SongThreshold
    )
    
    $script:foundMatches = @()
    $allAudioFiles = Get-ChildItem -LiteralPath $SourcePath -Recurse -File | 
                     Where-Object { $audioExtensions -contains $_.Extension.ToLower() }
    
    foreach ($file in $allAudioFiles) {
        $metadata = Get-AudioMetadata $file.FullName
        
        # Check artist similarity
        $artistSimilarity = Calculate-StringSimilarity $metadata.Artist $TargetArtist
        
        if ($artistSimilarity -ge $ArtistThreshold) {
            # Check song title similarity
            $songSimilarity = Calculate-StringSimilarity $metadata.Title $TargetSong
            
            if ($songSimilarity -ge $SongThreshold) {
                $script:foundMatches += [PSCustomObject]@{
                    File = $file
                    Artist = $metadata.Artist
                    Title = $metadata.Title
                    Album = $metadata.Album
                    ArtistSimilarity = $artistSimilarity
                    SongSimilarity = $songSimilarity
                    TargetArtist = $TargetArtist
                    TargetSong = $TargetSong
                }
            }
        }
    }
}

function Create-Playlist {
    param(
        [array]$Matches,
        [string]$OutputPath,
        [string]$Format,
        [string]$Name,
        [string]$SourcePath,
        [string]$PathType
    )
    
    $playlistFile = Join-Path $OutputPath "$Name.$($Format.ToLower())"
    
    switch ($Format.ToUpper()) {
        "M3U" {
            $content = @("#EXTM3U")
            foreach ($match in $Matches) {
                $content += "#EXTINF:-1,$($match.Artist) - $($match.Title)"
                $playlistPath = Get-PlaylistPath -FilePath $match.File.FullName -SourcePath $SourcePath -PathType $PathType
                $content += $playlistPath
            }
        }
        "PLS" {
            $content = @("[playlist]")
            for ($i = 0; $i -lt $Matches.Count; $i++) {
                $match = $Matches[$i]
                $playlistPath = Get-PlaylistPath -FilePath $match.File.FullName -SourcePath $SourcePath -PathType $PathType
                $content += "File$($i+1)=$playlistPath"
                $content += "Title$($i+1)=$($match.Artist) - $($match.Title)"
                $content += "Length$($i+1)=-1"
            }
            $content += "NumberOfEntries=$($Matches.Count)"
            $content += "Version=2"
        }
        "WPL" {
            $content = @('<?wpl version="1.0"?>')
            $content += "<smil>"
            $content += "<head>"
            $content += "<meta name=`"Generator`" content=`"PlaylistGen.ps1`"/>"
            $content += "<title>$Name</title>"
            $content += "</head>"
            $content += "<body>"
            $content += "<seq>"
            foreach ($match in $Matches) {
                $playlistPath = Get-PlaylistPath -FilePath $match.File.FullName -SourcePath $SourcePath -PathType $PathType
                $content += "<media src=`"$playlistPath`"/>"
            }
            $content += "</seq>"
            $content += "</body>"
            $content += "</smil>"
        }
    }
    
    $content | Out-File -FilePath $playlistFile -Encoding UTF8
    return $playlistFile
}

# ------------------------------
# Main logic
# ------------------------------

# Validate paths
if (-not (Test-Path $Src)) {
    Write-Error "Source folder not found: $Src"
    exit 1
}

if (-not $AllFiles -and -not [string]::IsNullOrWhiteSpace($CsvSrc) -and -not (Test-Path $CsvSrc)) {
    Write-Error "CSV file not found: $CsvSrc"
    exit 1
}

if (-not (Test-Path $Dest)) {
    try {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    } catch {
        Write-Error "Could not create destination folder: $Dest"
        exit 1
    }
}

# Read CSV file or prepare all files mode
if ($AllFiles) {
    Write-Host "`nScanning for all audio files..."
    
    # Get all audio files recursively
    $audioFiles = Get-ChildItem -Path $Src -Recurse -File | Where-Object { 
        $audioExtensions -contains $_.Extension.ToLower() 
    }
    
    Write-Host "Found $($audioFiles.Count) audio files.`n"
    
    # Create virtual CSV data for all files (using filename as both song and artist for compatibility)
    $csvData = @()
    foreach ($file in $audioFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $csvData += [PSCustomObject]@{
            Song = $baseName
            Artist = ""  # Empty artist for all-files mode
        }
    }
} else {
    Write-Host "`nReading CSV file..."
    try {
        $csvData = Import-Csv -Path $CsvSrc -Header "Song", "Artist"
    } catch {
        Write-Error "Error reading CSV file: $($_.Exception.Message)"
        exit 1
    }
    
    Write-Host "Found $($csvData.Count) songs in CSV file.`n"
}

# Search for matches
$allMatches = @()
$foundCount = 0
$notFoundCount = 0

if ($AllFiles) {
    Write-Host "Including all audio files..."
    Write-Host "========================="
    
    # For all files mode, create matches directly from the audio files
    $audioFiles = Get-ChildItem -Path $Src -Recurse -File | Where-Object { 
        $audioExtensions -contains $_.Extension.ToLower() 
    }
    
    foreach ($file in $audioFiles) {
        $metadata = Get-AudioMetadata -FilePath $file.FullName
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        
        # Create a match object compatible with the playlist creation
        $match = [PSCustomObject]@{
            File = $file
            Title = if ($metadata.Title) { $metadata.Title } else { $baseName }
            Artist = if ($metadata.Artist) { $metadata.Artist } else { "Unknown Artist" }
            ArtistSimilarity = 100  # Perfect match for compatibility
            SongSimilarity = 100    # Perfect match for compatibility
        }
        
        $allMatches += $match
        $foundCount++
        
        Write-Host "  ✓ Added: '$($match.Title)' by '$($match.Artist)'" -ForegroundColor Green
    }
} else {
    Write-Host "Searching for matches..."
    Write-Host "========================="

    foreach ($entry in $csvData) {
        $song = $entry.Song.Trim()
        $artist = $entry.Artist.Trim()
        
        if ([string]::IsNullOrWhiteSpace($song) -or [string]::IsNullOrWhiteSpace($artist)) {
            continue
        }
        
        Write-Host "Searching for: '$song' by '$artist'"
        
        # Use script-level variable instead of function return
        $script:foundMatches = @()
        Find-MatchingFiles -SourcePath $Src -TargetArtist $artist -TargetSong $song -ArtistThreshold $ArtistThreshold -SongThreshold $SongThreshold
        
        if ($script:foundMatches.Count -gt 0) {
            # Take the best match (highest combined similarity)
            $bestMatch = $script:foundMatches | Sort-Object { $_.ArtistSimilarity + $_.SongSimilarity } -Descending | Select-Object -First 1
            $allMatches += $bestMatch
            $foundCount++
            
            Write-Host "  ✓ Found: '$($bestMatch.Title)' by '$($bestMatch.Artist)' (Artist: $($bestMatch.ArtistSimilarity)%, Song: $($bestMatch.SongSimilarity)%)" -ForegroundColor Green
        } else {
            $notFoundCount++
            Write-Host "  ✗ No match found" -ForegroundColor Red
        }
    }
}

# Results summary
Write-Host "`n========================="
if ($AllFiles) {
    Write-Host "Summary:"
    Write-Host "Total audio files found: $foundCount" -ForegroundColor Green
} else {
    Write-Host "Search Summary:"
    Write-Host "Total songs searched: $($csvData.Count)"
    Write-Host "Matches found: $foundCount" -ForegroundColor Green
    Write-Host "Not found: $notFoundCount" -ForegroundColor Red
    Write-Host "Success rate: $([Math]::Round(($foundCount / $csvData.Count) * 100, 1))%"
}

# Create playlist
if ($allMatches.Count -gt 0 -and -not $DryRun) {
    Write-Host "`nCreating playlist..."
    try {
        $playlistPath = Create-Playlist -Matches $allMatches -OutputPath $Dest -Format $PlaylistFormat -Name $PlaylistName -SourcePath $Src -PathType $PathType
        Write-Host "Playlist created: $playlistPath" -ForegroundColor Green
        Write-Host "Playlist contains $($allMatches.Count) songs."
        
        # Also create a full paths file for use with CopyFromList.ps1
        $fullPathsFile = Join-Path $Dest "$PlaylistName-FullPaths.txt"
        $allMatches | ForEach-Object { $_.File.FullName } | Out-File -FilePath $fullPathsFile -Encoding UTF8
        Write-Host "Full paths file created: $fullPathsFile" -ForegroundColor Green
    } catch {
        Write-Error "Error creating playlist: $($_.Exception.Message)"
        exit 1
    }
} elseif ($DryRun) {
    Write-Host "`nDry run completed. Playlist would contain $($allMatches.Count) songs."
    if ($allMatches.Count -gt 0) {
        Write-Host "Full paths that would be saved:"
        $allMatches | ForEach-Object { Write-Host "  $($_.File.FullName)" }
    }
} else {
    Write-Host "`nNo matches found. No playlist created." -ForegroundColor Yellow
}

# Build equivalent command string for logging
$commandArgs = @()
$commandArgs += "-Src '$Src'"
$commandArgs += "-Dest '$Dest'"
if ($AllFiles) {
    $commandArgs += "-AllFiles"
} else {
    $commandArgs += "-CsvSrc '$CsvSrc'"
}
$commandArgs += "-ArtistThreshold $ArtistThreshold"
$commandArgs += "-SongThreshold $SongThreshold"
$commandArgs += "-PlaylistFormat '$PlaylistFormat'"
$commandArgs += "-PlaylistName '$PlaylistName'"
$commandArgs += "-PathType '$PathType'"
if ($DryRun) { $commandArgs += "-DryRun" }
$equivalentCommand = ".\PlaylistGen.exe " + ($commandArgs -join " ")

Write-Host "`nEquivalent command line:"
Write-Host $equivalentCommand -ForegroundColor Green