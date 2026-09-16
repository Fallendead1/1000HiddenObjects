<#
    Creates every 1000 Hidden Objects game pass and developer product on Roblox through
    Open Cloud, uploads their icons (output/creator-hub), and writes the new IDs into
    src/shared/Config/MonetizationConfig.luau. Rojo then syncs them into Studio.

    One-time setup:
      1. Creator Hub > Open Cloud > API Keys > Create API Key.
         Access permissions: add "game-pass" (Read + Write) and "developer-product"
         (Read + Write), and pick the experience "1000 Hidden Objects".
         Copy the key.
      2. In PowerShell (the key stays in this window only):
            $env:ROBLOX_API_KEY = "<paste your key>"
      3. From the project folder:
            powershell -ExecutionPolicy Bypass -File .\tools\create-monetization.ps1

    Safe to re-run: anything that already exists with the same name is reused, not
    duplicated. Use -DryRun to see what would happen without creating anything.
    Names and prices here must match MonetizationConfig.luau (StoreName / SuggestedPrice).
#>
param(
    [string]$UniverseId = "10766140950",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
# The key is read from the environment (this window, or saved for the Windows user) and is
# never printed.
$apiKey = @(
    $env:ROBLOX_OPEN_CLOUD_API_KEY,
    [Environment]::GetEnvironmentVariable("ROBLOX_OPEN_CLOUD_API_KEY", "User"),
    $env:ROBLOX_API_KEY
) | Where-Object { $_ } | Select-Object -First 1
if (-not $apiKey -and -not $DryRun) {
    throw 'Set ROBLOX_OPEN_CLOUD_API_KEY first (see the top of this script).'
}

$root = Split-Path -Parent $PSScriptRoot
$icons = Join-Path $root "output\creator-hub"
$configPath = Join-Path $root "src\shared\Config\MonetizationConfig.luau"
$api = "https://apis.roblox.com"
$headers = @{ "x-api-key" = $apiKey }

$passes = @(
    @{ Key = "DoubleCash";    Name = "2x Cash";        Price = 149; Icon = "Pass_DoubleCash.png";    Description = "Double Cash from every object you clean into a bin. Forever." },
    @{ Key = "StrongerHands"; Name = "Stronger Hands"; Price = 149; Icon = "Pass_StrongerHands.png"; Description = "Lift one weight class heavier than your Strength. Forever." },
    @{ Key = "FastHands";     Name = "Fast Hands";     Price = 99;  Icon = "Pass_FastHands.png";     Description = "Heavy objects feel lighter and snappier to handle. Forever." },
    @{ Key = "ThrowBoost";    Name = "Throw Boost";    Price = 99;  Icon = "Pass_ThrowBoost.png";    Description = "+15% throw power. Forever." },
    @{ Key = "VIP";           Name = "VIP Searcher";   Price = 299; Icon = "Pass_VIP.png";           Description = "Gold VIP tag, +10% speed in rooms and a free Super Hint every room." },
    @{ Key = "DoubleXP";        Name = "2x XP";               Price = 99;  Icon = "Pass_DoubleXP.png";        Description = "Double Cleaner XP forever. Level up and unlock titles faster." },
    @{ Key = "RainbowTrail";    Name = "Rainbow Trail";       Price = 19;  Icon = "Pass_RainbowTrail.png";    Description = "A rainbow trail follows you around the lobby. Show it off!" },
    @{ Key = "PetVacuumCat";    Name = "Vacuum Cat";          Price = 149; Icon = "Pass_PetVacuumCat.png";    Description = "A Rare helper pet that grabs a second small object on every trip. Yours forever." },
    @{ Key = "PetGoldenDragon"; Name = "Golden Broom Dragon"; Price = 399; Icon = "Pass_PetGoldenDragon.png"; Description = "The Legendary helper: fastest trips, and it bursts packed junk open for you." },
    @{ Key = "PetSlot";         Name = "+1 Pet Slot";         Price = 149; Icon = "Pass_PetSlot.png";         Description = "Equip one more helper pet at a time. Forever." },
    @{ Key = "FasterPets";      Name = "Faster Pets";         Price = 99;  Icon = "Pass_FasterPets.png";      Description = "All your pets work 25% faster. Forever." }
)
$products = @(
    @{ Key = "QuickHint";       Name = "Quick Hint";           Price = 19;  Icon = "Product_QuickHint.png";       Description = "Instantly receive the next clue." },
    @{ Key = "SuperHint";       Name = "Super Hint";           Price = 39;  Icon = "Product_SuperHint.png";       Description = "Highlight the correct search region for 15 seconds." },
    @{ Key = "Cash10Min";       Name = "2x Cash (10 min)";     Price = 29;  Icon = "Product_Cash10Min.png";       Description = "Double Cash from bin deposits for 10 minutes. Carries over between rooms." },
    @{ Key = "Strength10Min";   Name = "2x Strength (10 min)"; Price = 49;  Icon = "Product_Strength10Min.png";   Description = "Lift twice the weight for 10 minutes." },
    @{ Key = "TeamMuscleBoost"; Name = "Team Muscle Boost";    Price = 129; Icon = "Product_TeamMuscleBoost.png"; Description = "Everyone in your room gets +50% Strength and +25% throw power for 10 minutes." },
    @{ Key = "SpeedBoost10Min"; Name = "2x Speed (10 min)";    Price = 3;   Icon = "Product_SpeedBoost10Min.png"; Description = "Run up to twice as fast for 10 minutes. Carries over between rooms." },
    @{ Key = "DoubleXP15Min";   Name = "2x XP (15 min)";       Price = 9;   Icon = "Product_DoubleXP15Min.png";   Description = "Double Cleaner XP for 15 minutes. Level up and unlock titles faster." },
    @{ Key = "LiftItNow";       Name = "Lift It Now";          Price = 5;   Icon = "Product_LiftItNow.png";       Description = "Lift that too-heavy object, and anything as heavy, for 60 seconds." },
    @{ Key = "JunkBlaster";     Name = "Junk Blaster";         Price = 5;   Icon = "Product_JunkBlaster.png";     Description = "Bursts open the packed junk around you. Never the junk hiding the object." },
    @{ Key = "TreasureRadar";   Name = "Treasure Radar";       Price = 9;   Icon = "Product_TreasureRadar.png";   Description = "Every treasure in this room sparkles through the junk." },
    @{ Key = "StarterPack";     Name = "Starter Pack";         Price = 49;  Icon = "Product_StarterPack.png";     Description = "30 min 2X Cash and 2 Quick Hints for your next rooms, plus a Mop Pup helper pet. Once per player." },
    @{ Key = "PetSnack";        Name = "Pet Snack";            Price = 5;   Icon = "Product_PetSnack.png";        Description = "Your pets work twice as fast for 5 minutes." }
)

function Get-All([string]$url, [string]$listField) {
    $items = @()
    $token = $null
    do {
        $page = $url + "?pageSize=100" + ($(if ($token) { "&pageToken=$token" } else { "" }))
        $result = Invoke-RestMethod -Method Get -Uri $page -Headers $headers
        if ($result.$listField) { $items += $result.$listField }
        $token = $result.nextPageToken
    } while ($token)
    return $items
}

function New-Multipart([string]$url, $item) {
    $iconPath = Join-Path $icons $item.Icon
    $curlArgs = @("-s", "-S", "-X", "POST", $url, "-H", "x-api-key: $apiKey",
        "-F", "name=$($item.Name)",
        "-F", "description=$($item.Description)",
        "-F", "price=$($item.Price)",
        "-F", "isForSale=true")
    if (Test-Path $iconPath) {
        $curlArgs += @("-F", "imageFile=@$iconPath;type=image/png")
    } else {
        Write-Warning "Icon missing, creating without one: $iconPath"
    }
    $raw = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) { throw "curl failed for $($item.Name)" }
    try { return $raw | ConvertFrom-Json } catch { throw "Unexpected response for $($item.Name): $raw" }
}

$ids = @{}

# Game passes
$passUrl = "$api/game-passes/v1/universes/$UniverseId/game-passes"
$existingPasses = if ($DryRun -and -not $apiKey) { @() } else { Get-All "$passUrl/creator" "gamePasses" }
foreach ($p in $passes) {
    $found = $existingPasses | Where-Object { $_.name -eq $p.Name } | Select-Object -First 1
    if ($found) {
        $id = if ($found.gamePassId) { $found.gamePassId } else { $found.id }
        Write-Host ("= pass    {0,-22} already exists  id {1}" -f $p.Name, $id)
    } elseif ($DryRun) {
        Write-Host ("+ pass    {0,-22} would be created at {1} R$" -f $p.Name, $p.Price); continue
    } else {
        $created = New-Multipart $passUrl $p
        $id = if ($created.gamePassId) { $created.gamePassId } else { $created.id }
        if (-not $id) { throw "No gamePassId returned for $($p.Name): $($created | ConvertTo-Json -Compress)" }
        Write-Host ("+ pass    {0,-22} created         id {1}  ({2} R$)" -f $p.Name, $id, $p.Price)
    }
    $ids[$p.Key] = $id
}

# Developer products
$productUrl = "$api/developer-products/v2/universes/$UniverseId/developer-products"
$existingProducts = if ($DryRun -and -not $apiKey) { @() } else { Get-All "$productUrl/creator" "developerProducts" }
foreach ($p in $products) {
    $found = $existingProducts | Where-Object { $_.name -eq $p.Name } | Select-Object -First 1
    if ($found) {
        $id = $found.productId
        Write-Host ("= product {0,-22} already exists  id {1}" -f $p.Name, $id)
    } elseif ($DryRun) {
        Write-Host ("+ product {0,-22} would be created at {1} R$" -f $p.Name, $p.Price); continue
    } else {
        $created = New-Multipart $productUrl $p
        $id = $created.productId
        if (-not $id) { throw "No productId returned for $($p.Name): $($created | ConvertTo-Json -Compress)" }
        Write-Host ("+ product {0,-22} created         id {1}  ({2} R$)" -f $p.Name, $id, $p.Price)
    }
    $ids[$p.Key] = $id
}

if ($DryRun) { Write-Host "Dry run: nothing created, config unchanged."; return }

# Write the IDs into MonetizationConfig.luau (UTF-8 without BOM, LF line endings kept).
$text = [IO.File]::ReadAllText($configPath)
foreach ($key in $ids.Keys) {
    $pattern = "(?m)^(\s*$key = )\d+"
    if ($text -notmatch $pattern) { Write-Warning "Could not find '$key = <id>' in MonetizationConfig.luau"; continue }
    $text = [regex]::Replace($text, $pattern, "`${1}$($ids[$key])")
}
[IO.File]::WriteAllText($configPath, $text, (New-Object Text.UTF8Encoding $false))
Write-Host ""
Write-Host "IDs written to src/shared/Config/MonetizationConfig.luau. Rojo will sync them into Studio."
Write-Host "Next: publish the place so live servers get the new IDs."
