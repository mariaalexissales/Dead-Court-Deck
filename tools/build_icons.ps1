#----------#
#--ESTRAL--#
#----------#

# bakes the TTRPG Legacy [Cards] asset pack into 64x64 item icons.
# art by Ddant1100 - https://ddant1100.itch.io
#
#   powershell -ExecutionPolicy Bypass -File tools\build_icons.ps1
#
# every card in the pack sits at the same spot on its 512x512 canvas, so one fixed crop
# keeps all 353 icons aligned with each other.

param(
    [string]$Source = "$env:USERPROFILE\Downloads\ttrpg_legacy_cards_1.1",
    [string]$Out
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
if (-not $Out) { $Out = Join-Path $root "Contents\mods\DeadCourtDeck\42\media\textures" }

if (-not (Test-Path $Source)) { throw "asset pack not found at $Source (pass -Source)" }
if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }

# the card inside the canvas, measured off the art.
$CROP = New-Object System.Drawing.Rectangle(99, 35, 314, 442)

# 64x64 to match the other mods' icons. the card is portrait, so it fits to height and is
# centred on a transparent square rather than stretched.
$SIZE = 64
$cardH = $SIZE
$cardW = [int][math]::Round($CROP.Width * $SIZE / $CROP.Height)
$cardX = [int][math]::Floor(($SIZE - $cardW) / 2)

$design = "design_2"

# mod name -> asset pack name
$suits  = [ordered]@{ Hearts = "heart"; Diamonds = "diamond"; Clubs = "club"; Spades = "spade" }
$races  = [ordered]@{ Human = "human"; Goblin = "goblin"; Elf = "elves"; Dwarf = "dwarf" }
$ranks  = [ordered]@{ A = "ace"; "2" = "2"; "3" = "3"; "4" = "4"; "5" = "5"; "6" = "6";
                      "7" = "7"; "8" = "8"; "9" = "9"; "10" = "10"; J = "jack"; Q = "queen"; K = "king" }
$courts = @("J", "Q", "K")

# the common tier takes its colour from the suit; the rest are the metal prints.
$suitColor = @{ Hearts = "red"; Spades = "cyan"; Clubs = "black"; Diamonds = "green" }
$tiers = @("Standard", "Bronze", "Silver", "Gold")

# the pack ships a dozen misspelled names. anything not caught here still falls back to the
# token-set index below.
$aliases = @{
    "ace_of_spade_bronze_${design}.png" = "ace_of_space_bronze_${design}.png"
    "ace_of_spade_silver_${design}.png" = "ace_of_space_silver_${design}.png"
    "ace_of_spade_gold_${design}.png"   = "ace_of_space_gold_${design}.png"
}
foreach ($race in @("human", "elves", "dwarf")) {
    foreach ($metal in @("bronze", "silver", "gold")) {
        $aliases["${race}_queen_of_club_${metal}_${design}.png"] = "${race}_queen_club_of_${metal}_${design}.png"
    }
}

# tokens sorted, "of" dropped: catches any other word-order typo in the pack.
$index = @{}
foreach ($file in Get-ChildItem $Source -File -Filter "*${design}*.png") {
    $key = (($file.BaseName -split "_" | Where-Object { $_ -ne "of" }) | Sort-Object) -join " "
    if (-not $index.ContainsKey($key)) { $index[$key] = $file.Name }
}

function Resolve-Asset([string]$name) {
    $path = Join-Path $Source $name
    if (Test-Path $path) { return $path }

    if ($aliases.ContainsKey($name)) {
        $alt = Join-Path $Source $aliases[$name]
        if (Test-Path $alt) { return $alt }
    }

    $key = ((($name -replace "\.png$","") -split "_" | Where-Object { $_ -ne "of" }) | Sort-Object) -join " "
    if ($index.ContainsKey($key)) { return (Join-Path $Source $index[$key]) }

    return $null
}

# SourceCopy keeps the resampled alpha instead of blending it onto the empty canvas, and the
# tiled wrap stops bicubic from sampling past the crop and leaving a seam down the edge.
function Write-Icon([string]$from, [string]$to) {
    $src = New-Object System.Drawing.Bitmap($from)
    $dst = New-Object System.Drawing.Bitmap($SIZE, $SIZE, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)

    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)

    $dstRect = New-Object System.Drawing.Rectangle($cardX, 0, $cardW, $cardH)
    $g.DrawImage($src, $dstRect, $CROP.X, $CROP.Y, $CROP.Width, $CROP.Height,
        [System.Drawing.GraphicsUnit]::Pixel, $attr)

    $attr.Dispose()
    $g.Dispose()
    $dst.Save($to, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
    $src.Dispose()
}

$written = 0
$missing = @()

foreach ($suit in $suits.Keys) {
    $assetSuit = $suits[$suit]

    foreach ($tier in $tiers) {
        $color = if ($tier -eq "Standard") { $suitColor[$suit] } else { $tier.ToLower() }

        foreach ($rank in $ranks.Keys) {
            $assetRank = $ranks[$rank]
            $variants = if ($courts -contains $rank) { @($races.Keys) } else { @("") }

            foreach ($race in $variants) {
                if ($race -ne "") {
                    $asset = "$($races[$race])_${assetRank}_of_${assetSuit}_${color}_${design}.png"
                    $icon = "Item_DCD_${suit}_${rank}_${race}_${tier}.png"
                } else {
                    $asset = "${assetRank}_of_${assetSuit}_${color}_${design}.png"
                    $icon = "Item_DCD_${suit}_${rank}_${tier}.png"
                }

                $from = Resolve-Asset $asset
                if (-not $from) { $missing += $asset; continue }

                Write-Icon $from (Join-Path $Out $icon)
                $written++
            }
        }
    }
}

# the pack itself.
$joker = Join-Path $Source "extra\joker_lady.png"
if (Test-Path $joker) {
    Write-Icon $joker (Join-Path $Out "Item_DCD_CardPack.png")
    $written++
} else {
    $missing += "extra\joker_lady.png"
}

Write-Host ("wrote {0} icons at {1}x{1} to {2}" -f $written, $SIZE, $Out)

if ($missing.Count -gt 0) {
    Write-Host ("{0} source files not found:" -f $missing.Count)
    $missing | ForEach-Object { Write-Host "  $_" }
    exit 1
}
