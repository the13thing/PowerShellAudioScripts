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



# Force defaults and enforce allowed values



# ------------------------------



if (-not $Src) { $Src = (Get-Location).Path }



if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }



if (-not $Count -or $Count -lt 1) { $Count = 3 }



$allowedSchemes = @("number-title","number-artist-title","artist-title")



if (-not $RenameScheme -or -not $allowedSchemes -contains $RenameScheme) {



    $RenameScheme = "number-title"



}







# ------------------------------



# INTERACTIVE MODE (if no args supplied)



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



        "2" { $RenameScheme = "number-artist-title" }



        "3" { $RenameScheme = "artist-title" }



        default { $RenameScheme = "number-title" }



    }







    $DryRun = (Read-Host "Perform dry run (show actions only)? (y/N)") -match "^(y|Y)$"



}







# ------------------------------



# DEFAULTS



# ------------------------------



$audioExtensions = @(".flac", ".mp3", ".wav", ".aac", ".ogg", ".m4a", ".wma")



if (-not $Dest) { $Dest = Join-Path (Get-Location).Path "Output" }



if (-not $Count -or $Count -lt 1) { $Count = 3 }







Write-Host "`nSource: $Src"



Write-Host "Destination: $Dest"



if ($Total) { Write-Host "Mode: TOTAL ($Total random audio files overall)" }



else { Write-Host "Mode: PER-FOLDER ($Count random audio files per folder)" }



if ($ConvertToMp3) { Write-Host "FLAC → MP3 conversion ENABLED" }



if ($MaxPerArtist) { Write-Host "Max files per artist: $MaxPerArtist" }



Write-Host "Rename scheme: $RenameScheme"



if ($DryRun) { Write-Host "Dry run ENABLED (no files will be copied or converted)" }







# ------------------------------



# HELPERS



# ------------------------------



function Ensure-Folder {



    param([string]$Path)



    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path $Path)) {



        New-Item -ItemType Directory -Force -Path $Path | Out-Null



    }



}







function Sanitize-FileName { param($Name) return ($Name -replace '[<>:"/\\|?*]', '_') }







function Get-AudioArtist {



    param([string]$Path)



    try {



        $artist = ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "`"$Path`""



        if ($artist) { return $artist.Trim() }



    } catch {}



    return (Split-Path $Path -Parent | Split-Path -Leaf)



}







function Get-AudioTitle {



    param([string]$Path)



    try {



        $title = ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "`"$Path`""



        if ($title) { return $title.Trim() }



    } catch {}



    return [System.IO.Path]::GetFileNameWithoutExtension($Path)



}







function Rename-File {



    param([System.IO.FileInfo]$File)



    $artist = Get-AudioArtist $File.FullName



    $title = Get-AudioTitle $File.FullName



    $number = ($File.BaseName -split " ")[0]







    $newName = switch ($RenameScheme) {



        "number-title"        { "$number $title" }



        "number-artist-title" { "$number $artist - $title" }



        "artist-title"        { "$artist - $title" }



    }







    # Fallback if something went wrong



    if ([string]::IsNullOrWhiteSpace($newName)) {



        $newName = $File.BaseName



    }







    return "$newName$($File.Extension)"



}







# ------------------------------



# GLOBAL STATE



# ------------------------------



$script:jobIndex = 0



$script:totalJobs = 0



$artistCounts = @{}



# Track which folders actually have files copied to them



$foldersWithFiles = @{}







# ------------------------------



# SAFE COPY/CONVERT FUNCTION



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







        # Only create folder after confirming file will be processed



        $parentDir = Split-Path -Parent (Join-Path $TargetDir $f.Name)



        Ensure-Folder $parentDir



        $foldersWithFiles[$parentDir] = $true







        try {



            $destFileName = Sanitize-FileName (Rename-File -File $f)



            if ([string]::IsNullOrWhiteSpace($destFileName)) {



                $destFileName = $f.Name



            }



        } catch {



            Write-Warning "Error renaming file $($f.Name), using original name"



            $destFileName = $f.Name



        }







        if ($ConvertToMp3 -and $f.Extension.ToLower() -eq ".flac") {



            # Change extension to .mp3 for converted files



            $destFileName = [System.IO.Path]::ChangeExtension($destFileName, ".mp3")



            $destFullPath = Join-Path $parentDir $destFileName







            Write-Host "[$script:jobIndex/$script:totalJobs] Converting FLAC → MP3: $($f.Name)"



            if (-not $DryRun) {



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



                & ffmpeg @ffmpegArgs 2>$null



            }



        } else {



            $destFullPath = Join-Path $parentDir $destFileName



            Write-Host "[$script:jobIndex/$script:totalJobs] Copying: $($f.Name)"



            if (-not $DryRun) { Copy-Item -LiteralPath $f.FullName -Destination $destFullPath -Force }



        }







        if ($MaxPerArtist) { $artistCounts[$artist]++ }



    }



}







# ------------------------------



# MAIN LOGIC (fixed relative folder structure)



# ------------------------------



function Get-RelativePath($FullPath, $BasePath) {



    return $FullPath.Substring($BasePath.Length).TrimStart('\')



}







if ($Total) {



    $allFiles = Get-ChildItem -LiteralPath $Src -Recurse -File | Where-Object { $audioExtensions -contains $_.Extension.ToLower() }







    $selectedFiles = $allFiles | Get-Random -Count ([Math]::Min($Total, $allFiles.Count))







    $script:totalJobs = $selectedFiles.Count



    Write-Host "`nTotal files to process: $script:totalJobs`n"







    foreach ($f in $selectedFiles) {



        $relPath = Get-RelativePath $f.DirectoryName $Src



        $targetDir = if ($relPath) { Join-Path $Dest $relPath } else { $Dest }



        Copy-FilesSafely -Files @($f) -TargetDir $targetDir



    }



} else {



    # Per-folder mode



    $folders = Get-ChildItem -LiteralPath $Src -Directory -Recurse



    foreach ($folderItem in $folders) {



        $files = Get-ChildItem -LiteralPath $folderItem.FullName -File



        $audioFiles = $files | Where-Object { $audioExtensions -contains $_.Extension.ToLower() }



        if ($audioFiles.Count -eq 0) { continue }







        $numToPick = [Math]::Min($Count, $audioFiles.Count)



        $picked = $audioFiles | Get-Random -Count $numToPick







        $relPath = Get-RelativePath $folderItem.FullName $Src



        $targetDir = if ($relPath) { Join-Path $Dest $relPath } else { $Dest }



        Copy-FilesSafely -Files $picked -TargetDir $targetDir







        # Only copy non-audio files if we actually copied audio files to this folder



        if ($foldersWithFiles.ContainsKey($targetDir)) {



            $otherFiles = $files | Where-Object { $audioExtensions -notcontains $_.Extension.ToLower() }



            if ($otherFiles.Count -gt 0) {



                foreach ($otherFile in $otherFiles) {



                    Write-Host "[$script:jobIndex/$script:totalJobs] Copying non-audio: $($otherFile.Name)"



                    if (-not $DryRun) {



                        $destPath = Join-Path $targetDir $otherFile.Name



                        Copy-Item -LiteralPath $otherFile.FullName -Destination $destPath -Force



                    }



                }



            }



        }



    }



}











Write-Host "`nDone! Processed $script:jobIndex files."



if ($DryRun) { Write-Host "Dry run: no files were actually copied or converted." }



