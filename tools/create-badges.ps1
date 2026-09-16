<#
    Creates the 1000 Hidden Objects badges on Roblox through Open Cloud, uploads their images
    (output/creator-hub/Badge_*.png) and writes the new IDs into the Badges table of
    src/shared/Config/MonetizationConfig.luau.

    Roblox gives each experience a few free badges per day. This script only creates badges
    while free quota is left (expected cost 0, so Roblox refuses any charge); the rest are
    skipped and created on a later run. Pass -AllowSpend -ExpectedCost <robux> to pay for extra
    badges instead.

    Key: the Open Cloud API key in ROBLOX_OPEN_CLOUD_API_KEY (never printed). It needs the badge
    permission for this experience.

    Safe to re-run: badges that already exist with the same name are reused.
#>
param(
    [string]$UniverseId = "10766140950",
    [int]$PaymentSourceType = 2, # 1 = user funds, 2 = group funds (the game is group-owned)
    [switch]$AllowSpend,
    [int]$ExpectedCost = 0,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$apiKey = @(
    $env:ROBLOX_OPEN_CLOUD_API_KEY,
    [Environment]::GetEnvironmentVariable("ROBLOX_OPEN_CLOUD_API_KEY", "User"),
    $env:ROBLOX_API_KEY
) | Where-Object { $_ } | Select-Object -First 1
if (-not $apiKey -and -not $DryRun) {
    throw 'Set ROBLOX_OPEN_CLOUD_API_KEY first.'
}

$root = Split-Path -Parent $PSScriptRoot
$icons = Join-Path $root "output\creator-hub"
$configPath = Join-Path $root "src\shared\Config\MonetizationConfig.luau"

# In priority order: badges players can earn today come first.
$badges = @(
    @{ Key = "FirstObject";        Name = "First Find!";               Description = "Find your first hidden object." },
    @{ Key = "FirstFinderWin";     Name = "Finder!";                   Description = "Be the one who grabs the hidden object for your team." },
    @{ Key = "Room001Speed";       Name = "Speedy Cleaner: Room #001"; Description = "Find the Golden Key in Room #001 in under 5 minutes." },
    @{ Key = "TenObjects";         Name = "10 Objects Found";          Description = "Collect 10 hidden objects." },
    @{ Key = "HundredObjects";     Name = "100 Objects Found";         Description = "Collect 100 hidden objects." },
    @{ Key = "FiveHundredObjects"; Name = "500 Objects Found";         Description = "Collect 500 hidden objects." },
    @{ Key = "ThousandObjects";    Name = "All 1000 Found!";           Description = "Complete the whole collection of 1000 hidden objects." },
    @{ Key = "Room002Speed";       Name = "Speedy Cleaner: Room #002"; Description = "Find Grandma's Diamond Ring in Room #002 in under 5 minutes." },
    @{ Key = "Room003Speed";       Name = "Speedy Cleaner: Room #003"; Description = "Find the Golden TV Remote in Room #003 in under 6 minutes." },
    @{ Key = "Room004Speed";       Name = "Speedy Cleaner: Room #004"; Description = "Find the Golden Wrench in Room #004 in under 7 minutes." },
    @{ Key = "Room005Clear";       Name = "Attic Explorer";            Description = "Clear the Giant Attic, the first Mega Room." },
    @{ Key = "Room005Speed";       Name = "Speedy Cleaner: Room #005"; Description = "Find the Treasure Map in the Giant Attic in under 15 minutes." }
)

# Existing badges (public list) so a re-run never duplicates.
$existing = @()
$cursor = ""
do {
    $page = Invoke-RestMethod -Uri ("https://badges.roblox.com/v1/universes/$UniverseId/badges?limit=100&sortOrder=Asc" + ($(if ($cursor) { "&cursor=$cursor" } else { "" })))
    $existing += $page.data
    $cursor = $page.nextPageCursor
} while ($cursor)

$freeLeft = [int](Invoke-RestMethod -Uri "https://badges.roblox.com/v1/universes/$UniverseId/free-badges-quota")
Write-Host "Free badges left today: $freeLeft"

$ids = @{}
foreach ($b in $badges) {
    $found = $existing | Where-Object { $_.name -eq $b.Name } | Select-Object -First 1
    if ($found) {
        Write-Host ("= {0,-28} already exists  id {1}" -f $b.Name, $found.id)
        $ids[$b.Key] = $found.id
        continue
    }
    $cost = 0
    if ($freeLeft -le 0) {
        if (-not $AllowSpend) {
            Write-Host ("- {0,-28} skipped (no free quota left today; re-run tomorrow)" -f $b.Name)
            continue
        }
        $cost = $ExpectedCost
    }
    if ($DryRun) {
        Write-Host ("+ {0,-28} would be created (cost {1} R$)" -f $b.Name, $cost)
        $freeLeft--
        continue
    }
    $icon = Join-Path $icons ("Badge_" + $b.Key + ".png")
    $curlArgs = @("-s", "-S", "-X", "POST", "https://apis.roblox.com/legacy-badges/v1/universes/$UniverseId/badges",
        "-H", "x-api-key: $apiKey",
        "-F", "name=$($b.Name)",
        "-F", "description=$($b.Description)",
        "-F", "paymentSourceType=$PaymentSourceType",
        "-F", "expectedCost=$cost",
        "-F", "isActive=true")
    if (Test-Path $icon) {
        $curlArgs += @("-F", "files=@$icon;type=image/png")
    } else {
        Write-Warning "Icon missing, creating without one: $icon"
    }
    $raw = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) { throw "curl failed for $($b.Name)" }
    $created = $null
    try { $created = $raw | ConvertFrom-Json } catch { }
    if (-not $created -or -not $created.id) { throw "Roblox refused '$($b.Name)': $raw" }
    Write-Host ("+ {0,-28} created         id {1}  (cost {2} R$)" -f $b.Name, $created.id, $cost)
    $ids[$b.Key] = $created.id
    $freeLeft--
}

if ($DryRun -or $ids.Count -eq 0) { Write-Host "Config unchanged."; return }

# Write the IDs into the Badges table (UTF-8 without BOM).
$text = [IO.File]::ReadAllText($configPath)
foreach ($key in $ids.Keys) {
    $pattern = "(?m)^(\s*$key = )\d+"
    if ($text -notmatch $pattern) { Write-Warning "Could not find '$key = <id>' in MonetizationConfig.luau"; continue }
    $text = [regex]::Replace($text, $pattern, "`${1}$($ids[$key])")
}
[IO.File]::WriteAllText($configPath, $text, (New-Object Text.UTF8Encoding $false))
Write-Host ""
Write-Host "Badge IDs written to src/shared/Config/MonetizationConfig.luau."
