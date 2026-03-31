param(
    [string]$Scenario,
    [switch]$ListScenarios,
    [switch]$ShowState
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-SimData {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $Value.Keys) { $hash[[string]$key] = ConvertTo-SimData $Value[$key] }
        return $hash
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $Value.PSObject.Properties) { $hash[$property.Name] = ConvertTo-SimData $property.Value }
        return $hash
    }
    if ($Value -is [System.Collections.IList] -and -not ($Value -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $Value) { [void]$list.Add((ConvertTo-SimData $item)) }
        return ,$list
    }
    return $Value
}

function New-List {
    param([object[]]$Items = @())
    $list = New-Object System.Collections.ArrayList
    foreach ($item in $Items) { [void]$list.Add($item) }
    return ,$list
}

function Get-ValueOrDefault {
    param($Object, [string]$Name, $Default = $null)
    if (($Object -is [System.Collections.IDictionary]) -and $Object.ContainsKey($Name)) { return $Object[$Name] }
    if ($null -ne $Object) {
        $property = $Object.PSObject.Properties[$Name]
        if ($property) { return $property.Value }
    }
    return $Default
}
function Get-DefaultConfig {
    return @{
        StartingCoins = 1000
        MaxInventorySize = 50
        MaxBattleTeamSize = 9
        BaseXPRequired = 50
        XPScaling = 1.5
        StatGainPerLevel = 0.08
        StatGainByRank = @(1.5, 1.25, 1.0, 0.75)
        RarityStatMultipliers = @{ Common = 1.0; Uncommon = 1.05; Rare = 1.1; Epic = 1.15; Legendary = 1.25 }
        VariantStatMultipliers = @{ Normal = 1.0; Silver = 1.15; Gold = 1.35; Legend = 1.6 }
        PlayerMaxLevel = 50
        PlayerBaseXP = 100
        PlayerXPScaling = 1.4
        Floor2Cost = 500
        Floor2LevelReq = 2
        Floor3Cost = 5000
        Floor3LevelReq = 5
        EvolutionMinLevel = 1
        EvolutionMinLevel2 = 1
        BaseMaxLevel = 10
        EvolvedMaxLevel = 25
        FinalMaxLevel = 50
        CaptureXP = 10
        PlayerXP_Capture = 15
        IncomePointsPerFloor = 6
        DefensePointsPerFloor = 6
        CosmeticItems = @{
            trail_fire = @{ id = 'trail_fire'; slot = 'trail'; coinCost = 300; gemCost = 0 }
            trail_ice = @{ id = 'trail_ice'; slot = 'trail'; coinCost = 300; gemCost = 0 }
            aura_flame = @{ id = 'aura_flame'; slot = 'aura'; coinCost = 500; gemCost = 0 }
            aura_electric = @{ id = 'aura_electric'; slot = 'aura'; coinCost = 500; gemCost = 0 }
            name_gold = @{ id = 'name_gold'; slot = 'nameColor'; coinCost = 200; gemCost = 0 }
            name_red = @{ id = 'name_red'; slot = 'nameColor'; coinCost = 200; gemCost = 0 }
            trail_rainbow = @{ id = 'trail_rainbow'; slot = 'trail'; coinCost = 0; gemCost = 10 }
            name_rainbow = @{ id = 'name_rainbow'; slot = 'nameColor'; coinCost = 0; gemCost = 12 }
        }
        RarityCaptureCosts = @{ Common = 10; Uncommon = 25; Rare = 60; Epic = 150; Legendary = 400 }
    }
}

function Get-DefaultCatalog {
    return @{
        cacty = @{ id='cacty'; displayName='Cacty'; rarity='Common'; element='Earth'; class='Bruiser'; health=60; attack=8; defense=12; speed=4; evolvesTo='jackedty' }
        jackedty = @{ id='jackedty'; displayName='Jacked''ty'; rarity='Uncommon'; element='Earth'; class='Bruiser'; health=110; attack=8; defense=22; speed=3; evolvesFrom='cacty'; evolvesTo='cactyjackedty' }
        cactyjackedty = @{ id='cactyjackedty'; displayName='CactyJackedty'; rarity='Epic'; element='Earth'; class='Bruiser'; health=200; attack=40; defense=28; speed=8; evolvesFrom='jackedty' }
        breezee = @{ id='breezee'; displayName='Breezee'; rarity='Common'; element='Wind'; class='Assassin'; health=42; attack=9; defense=6; speed=9; evolvesTo='gagglestand' }
        gagglestand = @{ id='gagglestand'; displayName='Gagglestand'; rarity='Uncommon'; element='Wind'; class='Support'; health=90; attack=9; defense=18; speed=7; evolvesFrom='breezee'; evolvesTo='hurricrane' }
        ceeponee = @{ id='ceeponee'; displayName='Ceeponee'; rarity='Common'; element='Ice'; class='Bruiser'; health=55; attack=11; defense=8; speed=6; evolvesTo='ceehorcee' }
        ceehorcee = @{ id='ceehorcee'; displayName='Ceehorcee'; rarity='Uncommon'; element='Ice'; class='Assassin'; health=65; attack=17; defense=9; speed=14; evolvesFrom='ceeponee'; evolvesTo='ceesteed' }
        draco = @{ id='draco'; displayName='Draco'; rarity='Common'; element='Fire'; class='Bruiser'; health=55; attack=10; defense=8; speed=6; evolvesTo='dracoil' }
        dracoil = @{ id='dracoil'; displayName='Dracoil'; rarity='Rare'; element='Fire'; class='Assassin'; health=100; attack=28; defense=12; speed=13; evolvesFrom='draco' }
        pylme = @{ id='pylme'; displayName='Pylme'; rarity='Common'; element='Earth'; class='Mage'; health=50; attack=9; defense=10; speed=5; evolvesTo='bonoblade' }
        bonoblade = @{ id='bonoblade'; displayName='Bonoblade'; rarity='Uncommon'; element='Earth'; class='Assassin'; health=70; attack=17; defense=10; speed=11; evolvesFrom='pylme'; evolvesTo='guerilla' }
    }
}

function Get-SynergyDefinitions {
    return @{
        Fire = @(@{ count = 2; label = 'Ember'; bonuses = @{ attack = 0.10 } }, @{ count = 3; label = 'Inferno'; bonuses = @{ attack = 0.25 } })
        Ice = @(@{ count = 2; label = 'Frost'; bonuses = @{ defense = 0.10 } }, @{ count = 3; label = 'Blizzard'; bonuses = @{ defense = 0.25; speed = -0.10 } })
        Wind = @(@{ count = 2; label = 'Breeze'; bonuses = @{ speed = 0.15 } }, @{ count = 3; label = 'Tempest'; bonuses = @{ speed = 0.30; attack = 0.10 } })
        Earth = @(@{ count = 2; label = 'Roots'; bonuses = @{ health = 0.10 } }, @{ count = 3; label = 'Tectonic'; bonuses = @{ health = 0.25; defense = 0.10 } })
        Shadow = @(@{ count = 2; label = 'Dusk'; bonuses = @{ attack = 0.10; speed = 0.05 } }, @{ count = 3; label = 'Eclipse'; bonuses = @{ attack = 0.20; speed = 0.15 } })
        Lightning = @(@{ count = 2; label = 'Spark'; bonuses = @{ speed = 0.10; attack = 0.05 } }, @{ count = 3; label = 'Thunder'; bonuses = @{ speed = 0.20; attack = 0.15 } })
        Water = @(@{ count = 2; label = 'Tide'; bonuses = @{ defense = 0.10; speed = 0.05 } }, @{ count = 3; label = 'Tsunami'; bonuses = @{ defense = 0.20; speed = 0.15 } })
        Bruiser = @(@{ count = 2; label = 'Fury'; bonuses = @{ attack = 0.12 } }, @{ count = 3; label = 'Rampage'; bonuses = @{ attack = 0.25; health = 0.10 } })
        Mage = @(@{ count = 2; label = 'Focus'; bonuses = @{ attack = 0.10 } }, @{ count = 3; label = 'Arcane'; bonuses = @{ attack = 0.20 } })
        Guardian = @(@{ count = 2; label = 'Shield'; bonuses = @{ defense = 0.15 } }, @{ count = 3; label = 'Bastion'; bonuses = @{ defense = 0.30; health = 0.10 } })
        Assassin = @(@{ count = 2; label = 'Edge'; bonuses = @{ speed = 0.10; attack = 0.05 } }, @{ count = 3; label = 'Lethal'; bonuses = @{ speed = 0.20; attack = 0.20 } })
        Support = @(@{ count = 2; label = 'Mend'; bonuses = @{ health = 0.10 } }, @{ count = 3; label = 'Harmony'; bonuses = @{ health = 0.20; defense = 0.10 } })
    }
}

function New-PlayerState {
    param([hashtable]$Spec, [hashtable]$Config, [ref]$UidCounter)
    $floors = Get-ValueOrDefault -Object $Spec -Name 'ownedFloors' -Default @(1)
    if (-not ($floors -contains 1)) { $floors = @(1) + $floors }
    $player = @{
        name = [string](Get-ValueOrDefault -Object $Spec -Name 'name')
        userId = [int](Get-ValueOrDefault -Object $Spec -Name 'userId' -Default ($UidCounter.Value + 1))
        coins = [int](Get-ValueOrDefault -Object $Spec -Name 'coins' -Default $Config.StartingCoins)
        gems = [int](Get-ValueOrDefault -Object $Spec -Name 'gems' -Default 0)
        inventory = (New-List)
        baseSlots = (New-List)
        defenseSlots = (New-List)
        favoriteUid = (Get-ValueOrDefault -Object $Spec -Name 'favoriteUid')
        battleTeam = @{}
        playerLevel = [int](Get-ValueOrDefault -Object $Spec -Name 'playerLevel' -Default 1)
        playerXP = [double](Get-ValueOrDefault -Object $Spec -Name 'playerXP' -Default 0)
        ownedFloors = (New-List ($floors | Sort-Object -Unique))
        cosmetics = @{ owned = @{}; equipped = @{} }
    }
    foreach ($entry in (Get-ValueOrDefault -Object $Spec -Name 'inventory' -Default @())) {
        $uid = Get-ValueOrDefault -Object $entry -Name 'uid'
        if (-not $uid) { $UidCounter.Value++; $uid = ('sim-{0:0000}' -f $UidCounter.Value) }
        [void]$player.inventory.Add(@{ id = [string](Get-ValueOrDefault -Object $entry -Name 'id'); uid = [string]$uid; level = [int](Get-ValueOrDefault -Object $entry -Name 'level' -Default 1); xp = [double](Get-ValueOrDefault -Object $entry -Name 'xp' -Default 0); variant = [string](Get-ValueOrDefault -Object $entry -Name 'variant' -Default 'Normal') })
    }
    return $player
}

function Get-InventoryEntry {
    param([hashtable]$Player, [string]$Uid)
    foreach ($entry in $Player.inventory) { if ([string]$entry.uid -eq [string]$Uid) { return $entry } }
    return $null
}

function Get-MaxSlots {
    param([hashtable]$State, [hashtable]$Player, [string]$SlotType)
    if ($SlotType -eq 'defense') { return $Player.ownedFloors.Count * [int]$State.config.DefensePointsPerFloor }
    return $Player.ownedFloors.Count * [int]$State.config.IncomePointsPerFloor
}

function Ensure-Slots {
    param([hashtable]$State, [hashtable]$Player, [string]$SlotType)
    if ($SlotType -eq 'defense') {
        if ($null -eq $Player.defenseSlots) { $Player.defenseSlots = New-List }
        $slots = $Player.defenseSlots
    }
    else {
        if ($null -eq $Player.baseSlots) { $Player.baseSlots = New-List }
        $slots = $Player.baseSlots
    }
    while ($slots.Count -lt (Get-MaxSlots -State $State -Player $Player -SlotType $SlotType)) { [void]$slots.Add('') }
    return ,$slots
}

function Remove-FromAllAssignments {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid)
    foreach ($slotType in @('income','defense')) {
        $slots = Ensure-Slots -State $State -Player $Player -SlotType $slotType
        for ($i = 0; $i -lt $slots.Count; $i++) { if ([string]$slots[$i] -eq [string]$Uid) { $slots[$i] = '' } }
    }
    if ([string]$Player.favoriteUid -eq [string]$Uid) { $Player.favoriteUid = $null }
    foreach ($key in @($Player.battleTeam.Keys)) { if ([string]$Player.battleTeam[$key] -eq [string]$Uid) { $Player.battleTeam.Remove($key) } }
}
function Assign-Slot {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid, [int]$SlotIndex, [string]$SlotType)
    $slots = Ensure-Slots -State $State -Player $Player -SlotType $SlotType
    if (-not (Get-InventoryEntry -Player $Player -Uid $Uid)) { return @{ ok = $false; message = 'UID not in inventory' } }
    if ($SlotIndex -eq 0) {
        for ($i = 0; $i -lt $slots.Count; $i++) { if ([string]$slots[$i] -eq [string]$Uid) { $slots[$i] = '' } }
        return @{ ok = $true; message = 'Removed' }
    }
    Remove-FromAllAssignments -State $State -Player $Player -Uid $Uid
    if ($SlotIndex -ge 1 -and $SlotIndex -le $slots.Count) {
        $slots[$SlotIndex - 1] = [string]$Uid
        return @{ ok = $true; message = 'Assigned'; slot = $SlotIndex }
    }
    for ($i = 0; $i -lt $slots.Count; $i++) {
        if (-not [string]$slots[$i]) {
            $slots[$i] = [string]$Uid
            return @{ ok = $true; message = 'Assigned'; slot = $i + 1 }
        }
    }
    return @{ ok = $false; message = 'No empty slots' }
}

function Set-FavoriteEntry {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid)
    if (-not (Get-InventoryEntry -Player $Player -Uid $Uid)) { return @{ ok = $false; message = 'Creature not in inventory' } }
    Remove-FromAllAssignments -State $State -Player $Player -Uid $Uid
    $Player.favoriteUid = [string]$Uid
    return @{ ok = $true; message = 'Favorite set' }
}

function Owns-Floor {
    param([hashtable]$Player, [int]$Floor)
    return ($Player.ownedFloors -contains $Floor)
}

function Buy-FloorEntry {
    param([hashtable]$State, [hashtable]$Player, [int]$Floor)
    if (Owns-Floor -Player $Player -Floor $Floor) { return @{ ok = $false; message = 'Already owned' } }
    $requiredLevel = if ($Floor -eq 2) { [int]$State.config.Floor2LevelReq } else { [int]$State.config.Floor3LevelReq }
    if ($Player.playerLevel -lt $requiredLevel) { return @{ ok = $false; message = 'Level requirement not met' } }
    if ($Floor -eq 3 -and -not (Owns-Floor -Player $Player -Floor 2)) { return @{ ok = $false; message = 'Buy Floor 2 first' } }
    $cost = if ($Floor -eq 2) { [int]$State.config.Floor2Cost } else { [int]$State.config.Floor3Cost }
    if ($Player.coins -lt $cost) { return @{ ok = $false; message = 'Not enough coins' } }
    $Player.coins -= $cost
    [void]$Player.ownedFloors.Add($Floor)
    $Player.ownedFloors = New-List ($Player.ownedFloors | Sort-Object -Unique)
    Ensure-Slots -State $State -Player $Player -SlotType 'income' | Out-Null
    Ensure-Slots -State $State -Player $Player -SlotType 'defense' | Out-Null
    return @{ ok = $true; message = ('Floor ' + $Floor + ' unlocked') }
}

function Assign-BattleEntry {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid, [int]$Slot)
    if (-not (Owns-Floor -Player $Player -Floor 2)) { return @{ ok = $false; message = 'Floor 2 required' } }
    if ($Slot -lt 1 -or $Slot -gt 9) { return @{ ok = $false; message = 'Invalid battle slot' } }
    if (-not (Get-InventoryEntry -Player $Player -Uid $Uid)) { return @{ ok = $false; message = 'Creature not in inventory' } }
    Remove-FromAllAssignments -State $State -Player $Player -Uid $Uid
    $Player.battleTeam[[string]$Slot] = [string]$Uid
    return @{ ok = $true; message = 'Assigned to battle team' }
}

function Get-NextVariant {
    param([string]$Variant)
    $chain = @('Normal','Silver','Gold','Legend')
    for ($i = 0; $i -lt $chain.Count; $i++) { if ($chain[$i] -eq $Variant -and $i -lt ($chain.Count - 1)) { return $chain[$i + 1] } }
    return $null
}

function Add-CreatureEntry {
    param([hashtable]$State, [hashtable]$Player, [string]$CreatureId, [string]$Uid, [int]$Level, [double]$Xp, [string]$Variant)
    if ($Player.inventory.Count -ge [int]$State.config.MaxInventorySize) { throw 'Inventory full' }
    if (-not $Uid) { $State.uidCounter++; $Uid = ('sim-{0:0000}' -f $State.uidCounter) }
    $entry = @{ id = $CreatureId; uid = $Uid; level = $Level; xp = $Xp; variant = $Variant }
    [void]$Player.inventory.Add($entry)
    return $entry
}

function Remove-CreatureEntry {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid)
    for ($i = 0; $i -lt $Player.inventory.Count; $i++) {
        if ([string]$Player.inventory[$i].uid -eq [string]$Uid) {
            $entry = $Player.inventory[$i]
            $Player.inventory.RemoveAt($i)
            Remove-FromAllAssignments -State $State -Player $Player -Uid $Uid
            return $entry
        }
    }
    return $null
}

function Combine-Creatures {
    param([hashtable]$State, [hashtable]$Player, [System.Collections.IList]$Uids, [string]$ResultUid)
    if ($Uids.Count -ne 3) { return @{ ok = $false; message = 'Need exactly 3 creatures' } }
    $entries = New-List
    foreach ($uid in $Uids) {
        $entry = Get-InventoryEntry -Player $Player -Uid $uid
        if (-not $entry) { return @{ ok = $false; message = 'Creature not found' } }
        [void]$entries.Add($entry)
    }
    $creatureId = [string]$entries[0].id
    $variant = [string]$entries[0].variant
    foreach ($entry in $entries) {
        if ([string]$entry.id -ne $creatureId) { return @{ ok = $false; message = 'All 3 must match' } }
        if ([string]$entry.variant -ne $variant) { return @{ ok = $false; message = 'Variants must match' } }
    }
    $nextVariant = Get-NextVariant -Variant $variant
    if (-not $nextVariant) { return @{ ok = $false; message = 'Cannot combine this variant' } }
    $bestLevel = 1
    $bestXp = 0
    foreach ($entry in $entries) { if ($entry.level -gt $bestLevel -or ($entry.level -eq $bestLevel -and $entry.xp -gt $bestXp)) { $bestLevel = $entry.level; $bestXp = $entry.xp } }
    foreach ($uid in $Uids) { Remove-CreatureEntry -State $State -Player $Player -Uid $uid | Out-Null }
    $newEntry = Add-CreatureEntry -State $State -Player $Player -CreatureId $creatureId -Uid $ResultUid -Level $bestLevel -Xp $bestXp -Variant $nextVariant
    return @{ ok = $true; message = 'Combined'; uid = $newEntry.uid; variant = $nextVariant }
}

function Evolve-Creature {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid)
    $entry = Get-InventoryEntry -Player $Player -Uid $Uid
    if (-not $entry) { return @{ ok = $false; message = 'Creature not found' } }
    $info = $State.catalog[[string]$entry.id]
    if (-not $info) { return @{ ok = $false; message = 'Missing creature data' } }
    $nextId = Get-ValueOrDefault -Object $info -Name 'evolvesTo'
    if (-not $nextId) { return @{ ok = $false; message = 'This creature cannot evolve' } }
    $minLevel = if (Get-ValueOrDefault -Object $info -Name 'evolvesFrom') { [int]$State.config.EvolutionMinLevel2 } else { [int]$State.config.EvolutionMinLevel }
    if ($entry.level -lt $minLevel) { return @{ ok = $false; message = ('Reach level ' + $minLevel + ' to evolve') } }
    $entry.id = [string]$nextId
    return @{ ok = $true; message = 'Evolved'; creatureId = $entry.id }
}

function Add-PlayerXPEntry {
    param([hashtable]$State, [hashtable]$Player, [double]$Amount)
    $Player.playerXP += $Amount
    while ($Player.playerLevel -lt [int]$State.config.PlayerMaxLevel) {
        $needed = if ($Player.playerLevel -le 1) { [int]$State.config.PlayerBaseXP } else { [math]::Floor([double]$State.config.PlayerBaseXP * [math]::Pow([double]$State.config.PlayerXPScaling, ($Player.playerLevel - 1))) }
        if ($Player.playerXP -lt $needed) { break }
        $Player.playerXP -= $needed
        $Player.playerLevel++
    }
    return @{ ok = $true; message = 'Player XP granted'; level = $Player.playerLevel }
}

function Get-MaxCreatureLevel {
    param([hashtable]$State, [string]$CreatureId)
    $info = $State.catalog[[string]$CreatureId]
    if (-not $info) { return [int]$State.config.BaseMaxLevel }
    $evolvesFrom = Get-ValueOrDefault -Object $info -Name 'evolvesFrom'
    $evolvesTo = Get-ValueOrDefault -Object $info -Name 'evolvesTo'
    if (-not $evolvesFrom) { return [int]$State.config.BaseMaxLevel }
    if ($evolvesTo) { return [int]$State.config.EvolvedMaxLevel }
    return [int]$State.config.FinalMaxLevel
}

function Get-CreatureXPNeeded {
    param([hashtable]$State, [int]$TargetLevel)
    if ($TargetLevel -le 1) { return 0 }
    return [math]::Floor([double]$State.config.BaseXPRequired * [math]::Pow([double]$State.config.XPScaling, ($TargetLevel - 2)))
}

function Add-CreatureXPEntry {
    param([hashtable]$State, [hashtable]$Player, [string]$Uid, [double]$Amount)
    $entry = Get-InventoryEntry -Player $Player -Uid $Uid
    if (-not $entry) { return @{ ok = $false; message = 'Creature not found' } }
    $entry.xp += $Amount
    $maxLevel = Get-MaxCreatureLevel -State $State -CreatureId ([string]$entry.id)
    while ($entry.level -lt $maxLevel) {
        $needed = Get-CreatureXPNeeded -State $State -TargetLevel ($entry.level + 1)
        if ($entry.xp -lt $needed) { break }
        $entry.xp -= $needed
        $entry.level++
    }
    return @{ ok = $true; message = 'Creature XP granted'; level = $entry.level; xp = $entry.xp }
}

function Capture-Creature {
    param([hashtable]$State, [hashtable]$Player, [hashtable]$Step)
    $creatureId = [string](Get-ValueOrDefault -Object $Step -Name 'creatureId')
    $info = $State.catalog[$creatureId]
    if (-not $info) { return @{ ok = $false; message = 'Unknown creature' } }
    if ($Player.inventory.Count -ge [int]$State.config.MaxInventorySize) { return @{ ok = $false; message = 'Inventory full' } }
    $cost = Get-ValueOrDefault -Object $Step -Name 'cost' -Default ([int](Get-ValueOrDefault -Object $State.config.RarityCaptureCosts -Name ([string](Get-ValueOrDefault -Object $info -Name 'rarity')) -Default 10))
    if ($Player.coins -lt [int]$cost) { return @{ ok = $false; message = ('Need ' + $cost + ' gold'); cost = [int]$cost; coins = $Player.coins } }
    $Player.coins -= [int]$cost
    $entry = Add-CreatureEntry -State $State -Player $Player -CreatureId $creatureId -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'resultUid')) -Level ([int](Get-ValueOrDefault -Object $Step -Name 'level' -Default 1)) -Xp ([double](Get-ValueOrDefault -Object $Step -Name 'xp' -Default 0)) -Variant ([string](Get-ValueOrDefault -Object $Step -Name 'variant' -Default 'Normal'))
    $favoriteResult = $null
    if ($Player.favoriteUid) {
        $favoriteResult = Add-CreatureXPEntry -State $State -Player $Player -Uid ([string]$Player.favoriteUid) -Amount ([double](Get-ValueOrDefault -Object $Step -Name 'favoriteCaptureXp' -Default ([double]$State.config.CaptureXP)) )
    }
    $playerXpResult = Add-PlayerXPEntry -State $State -Player $Player -Amount ([double](Get-ValueOrDefault -Object $Step -Name 'playerCaptureXp' -Default ([double]$State.config.PlayerXP_Capture)) )
    return @{ ok = $true; message = 'Captured'; uid = $entry.uid; creatureId = $entry.id; cost = [int]$cost; coins = $Player.coins; playerLevel = $playerXpResult.level; playerXP = $Player.playerXP; favoriteXp = $favoriteResult }
}
function Get-EffectiveStats {
    param([hashtable]$State, [string]$CreatureId, [int]$Level, [string]$Variant)
    $info = $State.catalog[$CreatureId]
    if (-not $info) { return $null }
    $base = @{ health = [double]$info.health; attack = [double]$info.attack; defense = [double]$info.defense; speed = [double]$info.speed }
    $meta = @(@{ key='health'; value=$base.health; tie=1 }, @{ key='attack'; value=$base.attack; tie=2 }, @{ key='defense'; value=$base.defense; tie=3 }, @{ key='speed'; value=$base.speed; tie=4 }) | Sort-Object @{Expression={-1 * $_.value}}, @{Expression={$_.tie}}
    $rankOf = @{}
    for ($i = 0; $i -lt $meta.Count; $i++) { $rankOf[$meta[$i].key] = $i + 1 }
    $levelMult = @{}
    foreach ($key in @('health','attack','defense','speed')) {
        $rank = $rankOf[$key]
        $rankMult = [double]$State.config.StatGainByRank[$rank - 1]
        $levelMult[$key] = 1 + (($Level - 1) * [double]$State.config.StatGainPerLevel * $rankMult)
    }
    $variantMult = [double](Get-ValueOrDefault -Object $State.config.VariantStatMultipliers -Name $Variant -Default 1.0)
    $rarityMult = [double](Get-ValueOrDefault -Object $State.config.RarityStatMultipliers -Name ([string]$info.rarity) -Default 1.0)
    $mult = $variantMult * $rarityMult
    return @{ health = [math]::Floor($base.health * $levelMult.health * $mult); attack = [math]::Floor($base.attack * $levelMult.attack * $mult); defense = [math]::Floor($base.defense * $levelMult.defense * $mult); speed = [math]::Floor($base.speed * $levelMult.speed * $mult) }
}

function Get-BattleSynergySummary {
    param([hashtable]$State, [System.Collections.IList]$CreatureIds)
    $elementCounts = @{}
    $classCounts = @{}
    foreach ($id in $CreatureIds) {
        $info = $State.catalog[[string]$id]
        if (-not $info) { continue }
        $elementCounts[[string]$info.element] = [int](Get-ValueOrDefault -Object $elementCounts -Name ([string]$info.element) -Default 0) + 1
        $classCounts[[string]$info.class] = [int](Get-ValueOrDefault -Object $classCounts -Name ([string]$info.class) -Default 0) + 1
    }
    $active = New-List
    foreach ($bucket in @(@{ counts=$elementCounts; kind='element' }, @{ counts=$classCounts; kind='class' })) {
        foreach ($trait in $bucket.counts.Keys) {
            $tiers = $State.synergies[$trait]
            if (-not $tiers) { continue }
            $count = [int]$bucket.counts[$trait]
            $best = $null
            foreach ($tier in $tiers) { if ($count -ge [int]$tier.count) { $best = $tier } }
            if ($best) { [void]$active.Add(@{ trait=$trait; traitType=$bucket.kind; count=$count; label=$best.label; bonuses=$best.bonuses }) }
        }
    }
    return @{ active=$active; elementCounts=$elementCounts; classCounts=$classCounts }
}
function Get-PathValue {
    param($Root, [string]$Path)
    $current = $Root
    foreach ($segment in ($Path -split '\.')) {
        if ($segment -notmatch '^([^\[]+)(?:\[(\d+)\])?$') { throw ('Unsupported path segment ' + $segment) }
        $name = $matches[1]
        $index = $matches[2]
        if (-not ($current -is [System.Collections.IDictionary]) -or -not $current.ContainsKey($name)) { return $null }
        $current = $current[$name]
        if ($index) {
            if ($current -is [System.Collections.IList]) {
                $i = [int]$index - 1
                if ($i -lt 0 -or $i -ge $current.Count) { return $null }
                $current = $current[$i]
            }
            elseif ($current -is [System.Collections.IDictionary]) {
                $current = $current[[string]$index]
            }
            else { return $null }
        }
    }
    if (($current -is [System.Collections.IList]) -and -not ($current -is [string])) { return ,$current }
    return $current
}

function Format-Value {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return '"' + $Value + '"' }
    if ($Value -is [System.Collections.IDictionary] -or ($Value -is [System.Collections.IList] -and -not ($Value -is [string]))) { return (ConvertTo-Json -InputObject $Value -Depth 20 -Compress) }
    return [string]$Value
}

function Test-DeepEquals {
    param($Actual, $Expected)
    if (($Actual -is [System.Collections.IDictionary]) -or ($Expected -is [System.Collections.IDictionary]) -or (($Actual -is [System.Collections.IList]) -and -not ($Actual -is [string])) -or (($Expected -is [System.Collections.IList]) -and -not ($Expected -is [string]))) {
        return (ConvertTo-Json -InputObject $Actual -Depth 20 -Compress) -eq (ConvertTo-Json -InputObject $Expected -Depth 20 -Compress)
    }
    return [string]$Actual -eq [string]$Expected
}

function Test-Invariants {
    param([hashtable]$State, [hashtable]$Player)
    $errors = New-List
    $seen = @{}
    $valid = @{}
    foreach ($entry in $Player.inventory) { $valid[[string]$entry.uid] = $true }
    foreach ($slotType in @('income','defense')) {
        $slots = Ensure-Slots -State $State -Player $Player -SlotType $slotType
        for ($i = 0; $i -lt $slots.Count; $i++) {
            $uid = [string]$slots[$i]
            if (-not $uid) { continue }
            if (-not $valid.ContainsKey($uid)) { [void]$errors.Add(($slotType + ' slot references missing uid ' + $uid)); continue }
            if ($seen.ContainsKey($uid)) { [void]$errors.Add(('duplicate assignment for uid ' + $uid)) } else { $seen[$uid] = $true }
        }
    }
    if ($Player.favoriteUid) {
        $uid = [string]$Player.favoriteUid
        if (-not $valid.ContainsKey($uid)) { [void]$errors.Add(('favorite uid missing: ' + $uid)) }
        elseif ($seen.ContainsKey($uid)) { [void]$errors.Add(('favorite uid also assigned elsewhere: ' + $uid)) } else { $seen[$uid] = $true }
    }
    foreach ($key in @($Player.battleTeam.Keys)) {
        $uid = [string]$Player.battleTeam[$key]
        if (-not $uid) { continue }
        if (-not $valid.ContainsKey($uid)) { [void]$errors.Add(('battle uid missing: ' + $uid)); continue }
        if ($seen.ContainsKey($uid)) { [void]$errors.Add(('battle uid also assigned elsewhere: ' + $uid)) } else { $seen[$uid] = $true }
    }
    return ,$errors
}

function Get-PlayerSummaryLines {
    param([hashtable]$State)
    $lines = New-List
    foreach ($name in ($State.players.Keys | Sort-Object)) {
        $player = $State.players[$name]
        $baseCount = 0; foreach ($uid in $player.baseSlots) { if ([string]$uid) { $baseCount++ } }
        $defCount = 0; foreach ($uid in $player.defenseSlots) { if ([string]$uid) { $defCount++ } }
        $favorite = if ($player.favoriteUid) { [string]$player.favoriteUid } else { '-' }
        [void]$lines.Add(('{0}: coins={1}, gems={2}, inventory={3}, favorite={4}, base={5}, defense={6}, battle={7}, floors={8}' -f $player.name, $player.coins, $player.gems, $player.inventory.Count, $favorite, $baseCount, $defCount, $player.battleTeam.Keys.Count, (($player.ownedFloors | ForEach-Object { [string]$_ }) -join ',')))
    }
    return ,$lines
}

function Invoke-Step {
    param([hashtable]$State, [hashtable]$Step)
    $action = [string](Get-ValueOrDefault -Object $Step -Name 'action')
    $playerName = Get-ValueOrDefault -Object $Step -Name 'player'
    $player = $null
    if ($playerName) { $player = $State.players[[string]$playerName] }
    switch ($action) {
        'add_creature' { return @{ ok = $true; message = 'Creature added'; uid = (Add-CreatureEntry -State $State -Player $player -CreatureId ([string](Get-ValueOrDefault -Object $Step -Name 'creatureId')) -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) -Level ([int](Get-ValueOrDefault -Object $Step -Name 'level' -Default 1)) -Xp ([double](Get-ValueOrDefault -Object $Step -Name 'xp' -Default 0)) -Variant ([string](Get-ValueOrDefault -Object $Step -Name 'variant' -Default 'Normal'))).uid } }
        'grant_coins' { $player.coins += [int](Get-ValueOrDefault -Object $Step -Name 'amount' -Default 0); return @{ ok = $true; message = 'Coins granted' } }
        'grant_gems' { $player.gems += [int](Get-ValueOrDefault -Object $Step -Name 'amount' -Default 0); return @{ ok = $true; message = 'Gems granted' } }
        'grant_player_xp' { return Add-PlayerXPEntry -State $State -Player $player -Amount ([double](Get-ValueOrDefault -Object $Step -Name 'amount' -Default 0)) }
        'capture' { return Capture-Creature -State $State -Player $player -Step $Step }
        'assign_base' { return Assign-Slot -State $State -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) -SlotIndex ([int](Get-ValueOrDefault -Object $Step -Name 'slot' -Default -1)) -SlotType 'income' }
        'assign_defense' { return Assign-Slot -State $State -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) -SlotIndex ([int](Get-ValueOrDefault -Object $Step -Name 'slot' -Default -1)) -SlotType 'defense' }
        'set_favorite' { return Set-FavoriteEntry -State $State -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) }
        'clear_favorite' { $player.favoriteUid = $null; return @{ ok = $true; message = 'Favorite cleared' } }
        'buy_floor' { return Buy-FloorEntry -State $State -Player $player -Floor ([int](Get-ValueOrDefault -Object $Step -Name 'floor' -Default 0)) }
        'assign_battle' { return Assign-BattleEntry -State $State -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) -Slot ([int](Get-ValueOrDefault -Object $Step -Name 'slot' -Default 1)) }
        'remove_battle' { foreach ($key in @($player.battleTeam.Keys)) { if ([string]$player.battleTeam[$key] -eq [string](Get-ValueOrDefault -Object $Step -Name 'uid')) { $player.battleTeam.Remove($key) } }; return @{ ok = $true; message = 'Removed from battle team' } }
        'combine' { return Combine-Creatures -State $State -Player $player -Uids (New-List (Get-ValueOrDefault -Object $Step -Name 'uids' -Default @())) -ResultUid ([string](Get-ValueOrDefault -Object $Step -Name 'resultUid')) }
        'evolve' { return Evolve-Creature -State $State -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) }
        'buy_cosmetic' {
            $item = $State.config.CosmeticItems[[string](Get-ValueOrDefault -Object $Step -Name 'cosmeticId')]
            if (-not $item) { return @{ ok = $false; message = 'Invalid cosmetic' } }
            $currency = [string](Get-ValueOrDefault -Object $Step -Name 'currency')
            if ($currency -eq 'coins') {
                if ($player.coins -lt [int]$item.coinCost) { return @{ ok = $false; message = 'Not enough coins' } }
                $player.coins -= [int]$item.coinCost
            } else {
                if ($player.gems -lt [int]$item.gemCost) { return @{ ok = $false; message = 'Not enough gems' } }
                $player.gems -= [int]$item.gemCost
            }
            $player.cosmetics.owned[$item.id] = $true
            $player.cosmetics.equipped[$item.slot] = $item.id
            return @{ ok = $true; message = 'Purchased cosmetic' }
        }
        'effective_stats' {
            $entry = if (Get-ValueOrDefault -Object $Step -Name 'uid') { Get-InventoryEntry -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid')) } else { $null }
            $creatureId = if ($entry) { [string]$entry.id } else { [string](Get-ValueOrDefault -Object $Step -Name 'creatureId') }
            $level = if ($entry) { [int]$entry.level } else { [int](Get-ValueOrDefault -Object $Step -Name 'level' -Default 1) }
            $variant = if ($entry) { [string]$entry.variant } else { [string](Get-ValueOrDefault -Object $Step -Name 'variant' -Default 'Normal') }
            return @{ ok = $true; message = 'Calculated effective stats'; stats = (Get-EffectiveStats -State $State -CreatureId $creatureId -Level $level -Variant $variant) }
        }
        'battle_synergies' {
            $creatureIds = New-List
            $explicitIds = Get-ValueOrDefault -Object $Step -Name 'creatureIds'
            if ($explicitIds) { $creatureIds = New-List $explicitIds } else { foreach ($key in ($player.battleTeam.Keys | Sort-Object {[int]$_})) { $entry = Get-InventoryEntry -Player $player -Uid ([string]$player.battleTeam[$key]); if ($entry) { [void]$creatureIds.Add([string]$entry.id) } } }
            return @{ ok = $true; message = 'Calculated battle synergies'; summary = (Get-BattleSynergySummary -State $State -CreatureIds $creatureIds) }
        }
        'expect' {
            $path = [string](Get-ValueOrDefault -Object $Step -Name 'path')
            $actual = Get-PathValue -Root $State -Path $path
            if ($Step.ContainsKey('equals') -and -not (Test-DeepEquals -Actual $actual -Expected $Step.equals)) { throw ('Expectation failed for ' + $path + ': expected ' + (Format-Value $Step.equals) + ', got ' + (Format-Value $actual)) }
            if ($Step.ContainsKey('contains')) {
                $expected = $Step.contains
                $ok = $false
                if ($actual -is [System.Collections.IList]) { foreach ($item in $actual) { if (Test-DeepEquals -Actual $item -Expected $expected) { $ok = $true; break } } }
                elseif ($actual -is [System.Collections.IDictionary]) { $ok = $actual.ContainsKey([string]$expected) }
                else { $ok = ([string]$actual).Contains([string]$expected) }
                if (-not $ok) { throw ('Expectation failed for ' + $path + ': expected to contain ' + (Format-Value $expected) + ', got ' + (Format-Value $actual)) }
            }
            if ($Step.ContainsKey('count')) {
                $actualCount = if ($actual -is [System.Collections.IList]) { $actual.Count } elseif ($actual -is [System.Collections.IDictionary]) { $actual.Keys.Count } elseif ($null -eq $actual) { 0 } else { 1 }
                if ($actualCount -ne [int]$Step.count) { throw ('Expectation failed for ' + $path + ': expected count ' + $Step.count + ', got ' + $actualCount) }
            }
            return @{ ok = $true; message = 'Expectation passed' }
        }
        'expect_creature' {
            $entry = Get-InventoryEntry -Player $player -Uid ([string](Get-ValueOrDefault -Object $Step -Name 'uid'))
            $field = [string](Get-ValueOrDefault -Object $Step -Name 'field')
            $actual = Get-ValueOrDefault -Object $entry -Name $field
            $expected = Get-ValueOrDefault -Object $Step -Name 'equals'
            if (-not (Test-DeepEquals -Actual $actual -Expected $expected)) { throw ('Creature expectation failed for ' + $field + ': expected ' + (Format-Value $expected) + ', got ' + (Format-Value $actual)) }
            return @{ ok = $true; message = 'Creature expectation passed' }
        }
        'assert_invariants' {
            $players = if ($player) { @($player) } else { $State.players.Values }
            foreach ($p in $players) { $errors = Test-Invariants -State $State -Player $p; if ($errors.Count -gt 0) { throw ('Invariant check failed for ' + $p.name + ': ' + (($errors | ForEach-Object { [string]$_ }) -join '; ')) } }
            return @{ ok = $true; message = 'Invariant check passed' }
        }
        default { throw ('Unsupported action ' + $action) }
    }
}

$simRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scenarioRoot = Join-Path $simRoot 'scenarios'
if ($ListScenarios) { Get-ChildItem -Path $scenarioRoot -Filter '*.json' | Sort-Object Name | ForEach-Object { Write-Host $_.Name }; exit 0 }
if (-not $Scenario) { Write-Host 'Usage: powershell -ExecutionPolicy Bypass -File .\\tools\\sim\\run.ps1 -Scenario .\\tools\\sim\\scenarios\\favorite-base-flow.json'; exit 1 }
$scenarioPath = if (Test-Path $Scenario) { $Scenario } else { Join-Path $scenarioRoot $Scenario }
if (-not (Test-Path $scenarioPath)) { throw ('Scenario not found: ' + $Scenario) }

$rawScenario = Get-Content -Path $scenarioPath -Raw | ConvertFrom-Json
$scenarioData = ConvertTo-SimData -Value $rawScenario
$scenarioName = Get-ValueOrDefault -Object $scenarioData -Name 'name'
if (-not ($scenarioName -is [string]) -or -not $scenarioName) { $scenarioName = [IO.Path]::GetFileNameWithoutExtension($scenarioPath) }
$state = @{ config = Get-DefaultConfig; catalog = Get-DefaultCatalog; synergies = Get-SynergyDefinitions; players = @{}; uidCounter = 0; lastResult = $null; scenarioName = [string]$scenarioName }
$configOverrides = Get-ValueOrDefault -Object $scenarioData -Name 'configOverrides' -Default @{}
if (-not ($configOverrides -is [System.Collections.IDictionary])) { $configOverrides = @{} }
foreach ($property in $configOverrides.Keys) { $state.config[$property] = $configOverrides[$property] }
$catalogOverrides = Get-ValueOrDefault -Object $scenarioData -Name 'catalog' -Default @{}
if (-not ($catalogOverrides -is [System.Collections.IDictionary])) { $catalogOverrides = @{} }
foreach ($property in $catalogOverrides.Keys) { $state.catalog[$property] = $catalogOverrides[$property] }
$uidCounter = [ref]0
$playersData = Get-ValueOrDefault -Object $scenarioData -Name 'players' -Default @()
$players = @($playersData)
foreach ($playerSpec in $players) { $player = New-PlayerState -Spec $playerSpec -Config $state.config -UidCounter $uidCounter; $state.players[$player.name] = $player }
$state.uidCounter = $uidCounter.Value

Write-Host ('Scenario: ' + $state.scenarioName)
$stepsData = Get-ValueOrDefault -Object $scenarioData -Name 'steps' -Default @()
$steps = @($stepsData)
for ($i = 0; $i -lt $steps.Count; $i++) {
    $step = $steps[$i]
    $result = Invoke-Step -State $state -Step $step
    if ($step.action -notin @('expect','expect_creature','assert_invariants')) { $state.lastResult = $result }
    $playerName = Get-ValueOrDefault -Object $step -Name 'player'
    if ($playerName -and ($step.action -notin @('expect','expect_creature','assert_invariants'))) {
        $errors = Test-Invariants -State $state -Player $state.players[[string]$playerName]
        if ($errors.Count -gt 0) { throw ('Invariant check failed after step ' + ($i + 1) + ': ' + (($errors | ForEach-Object { [string]$_ }) -join '; ')) }
    }
    Write-Host ('[' + ($i + 1) + '] ' + $step.action + ' -> ' + $result.message)
}
Write-Host 'Summary:'
foreach ($line in (Get-PlayerSummaryLines -State $state)) { Write-Host ('  ' + $line) }
if ($ShowState) { Write-Host (ConvertTo-Json -InputObject @{ players = $state.players; lastResult = $state.lastResult } -Depth 25) }












