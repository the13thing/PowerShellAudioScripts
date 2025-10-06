\# RandomSongs.ps1



A PowerShell script that copies a random subset of audio files from a source library with advanced features like FLAC to MP3 conversion, artist limits, and flexible renaming schemes.



\## Features



\- \*\*Random Selection\*\*: Pick random audio files from your music library

\- \*\*Two Modes\*\*: 

&nbsp; - \*\*Total Mode\*\*: Select a specific total number of files across entire library

&nbsp; - \*\*Per-Folder Mode\*\*: Select a specific number of files from each folder

\- \*\*Artist Limits\*\*: Limit maximum files per artist to ensure variety

\- \*\*FLAC to MP3 Conversion\*\*: Convert FLAC files to MP3 with metadata and cover art preservation

\- \*\*Flexible Renaming\*\*: Multiple file naming schemes

\- \*\*Dry Run\*\*: Preview actions without actually copying files

\- \*\*Interactive Mode\*\*: GUI-like prompts when run without parameters

\- \*\*Preserves Structure\*\*: Maintains original folder hierarchy in output



\## Supported Audio Formats



\- FLAC

\- MP3

\- WAV

\- AAC

\- OGG

\- M4A

\- WMA



\## Requirements



\- PowerShell 5.0 or later

\- \*\*ffmpeg\*\* and \*\*ffprobe\*\* (for FLAC conversion and metadata reading)

&nbsp; - Download from: https://ffmpeg.org/download.html

&nbsp; - Must be in system PATH



\## Usage



\### Interactive Mode

Simply run without parameters for guided setup:

```powershell

.\\RandomSongs.ps1

```



\### Command Line Examples



\*\*Basic usage - 100 random songs:\*\*

```powershell

.\\RandomSongs.ps1 -Src "D:\\Music" -Dest "E:\\Output" -Total 100

```



\*\*With artist limits and FLAC conversion:\*\*

```powershell

.\\RandomSongs.ps1 -Src "D:\\Music" -Dest "E:\\Output" -Total 500 -MaxPerArtist 3 -ConvertToMp3

```



\*\*Per-folder mode with custom naming:\*\*

```powershell

.\\RandomSongs.ps1 -Src "D:\\Music" -Dest "E:\\Output" -Count 5 -RenameScheme "artist-title"

```



\*\*Dry run to preview actions:\*\*

```powershell

.\\RandomSongs.ps1 -Src "D:\\Music" -Total 100 -DryRun

```



\## Parameters



| Parameter | Type | Description | Default |

|-----------|------|-------------|---------|

| `-Src` | String | Source music library path | Current directory |

| `-Dest` | String | Destination output path | "Output" folder |

| `-Count` | Integer | Files per folder (per-folder mode) | 3 |

| `-Total` | Integer | Total files to select (total mode) | Not set |

| `-ConvertToMp3` | Switch | Convert FLAC files to MP3 | False |

| `-MaxPerArtist` | Integer | Maximum files per artist | No limit |

| `-RenameScheme` | String | File naming scheme | "number-title" |

| `-DryRun` | Switch | Preview only, don't copy files | False |



\## Rename Schemes



1\. \*\*`number-title`\*\* (default): `01 Song Title.mp3`

2\. \*\*`number-artist-title`\*\*: `01 Artist Name - Song Title.mp3`

3\. \*\*`artist-title`\*\*: `Artist Name - Song Title.mp3`



\## How It Works



\### Total Mode (`-Total` specified)

1\. Scans entire source library for audio files

2\. Randomly selects specified number of files

3\. Respects per-artist limits if specified

4\. Copies to destination maintaining folder structure



\### Per-Folder Mode (default)

1\. Processes each subfolder individually

2\. Selects specified number of random files from each folder

3\. Copies non-audio files (cover art, etc.) from folders with selected audio

4\. Maintains original folder hierarchy



\### FLAC Conversion

When `-ConvertToMp3` is enabled:

\- Converts FLAC files to high-quality MP3 (VBR ~192kbps)

\- Preserves all metadata tags

\- Embeds cover art from FLAC file

\- Resizes cover art to 300x300px for efficiency



\## Output Structure



The script preserves the original folder structure:

```

Source:

D:\\Music\\

├── Artist A\\Album 1\\01 Song.flac

└── Artist B\\Album 2\\02 Track.mp3



Output:

E:\\Output\\

├── Artist A\\Album 1\\01 Song.mp3

└── Artist B\\Album 2\\02 Track.mp3

```



\## Performance Tips



\- Use `-MaxPerArtist` for faster processing with large libraries

\- The script uses directory names for artist detection (faster than metadata parsing)

\- FLAC conversion is CPU-intensive; consider smaller batches for older systems



\## Error Handling



\- Skips inaccessible files gracefully

\- Handles long file paths by truncating names

\- Validates all parameters before processing

\- Creates destination folders as needed



\## Examples



\*\*Create a 1000-song playlist with max 2 songs per artist:\*\*

```powershell

.\\RandomSongs.ps1 -Total 1000 -MaxPerArtist 2 -ConvertToMp3 -RenameScheme "artist-title"

```



\*\*Sample 5 songs from each album folder:\*\*

```powershell

.\\RandomSongs.ps1 -Count 5 -RenameScheme "number-artist-title"

```



\*\*Quick preview of what would be selected:\*\*

```powershell

.\\RandomSongs.ps1 -Total 50 -MaxPerArtist 1 -DryRun

```



\## License



This script is provided as-is for personal use. Ensure you have rights to copy and convert your audio files.



