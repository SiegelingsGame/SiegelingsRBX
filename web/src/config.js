// Mirrors values from GameConfigData.lua (Roblox) so the web build plays the same.
// 1 world unit = 1 Roblox stud.
export const CFG = {
  StartingCoins: 100,
  IncomeTickSeconds: 10,
  MaxInventorySize: 50,

  BaseMaxLevel: 10, EvolvedMaxLevel: 25, FinalMaxLevel: 50,
  BaseXPRequired: 50, XPScaling: 1.5, CaptureXP: 10,
  StatGainPerLevel: 0.08, StatGainByRank: [1.5, 1.25, 1.0, 0.75],
  RarityStatMultipliers: { Common: 1.0, Uncommon: 1.05, Rare: 1.1, Epic: 1.15, Legendary: 1.25 },
  VariantStatMultipliers: { Normal: 1.0, Silver: 1.15, Gold: 1.35, Legend: 1.6 },

  PlayerMaxLevel: 100, PlayerBaseXP: 100, PlayerXPScaling: 1.4,
  PlayerXP_Capture: 10, PlayerXP_IncomeTick: 1, PlayerXP_Kill: 5,

  // Base floors (BuyFloor) — each owned floor adds 6 income + 6 defense slots
  Floors: [
    { floor: 1, cost: 0, levelReq: 1, name: 'Ground Floor' },
    { floor: 2, cost: 500, levelReq: 5, name: 'Floor 2' },
    { floor: 3, cost: 5000, levelReq: 10, name: 'Floor 3' },
    { floor: 4, cost: 25000, levelReq: 25, name: 'Siegelord Arena' },
  ],
  IncomePointsPerFloor: 6,
  DefensePointsPerFloor: 6,
  FloorHeight: 16,
  BattleGridSize: 9,          // 3x3 battle grid (GameConfig.MaxBattleTeamSize)
  MaxBattleTeamCreatures: 5,  // GameConfig.MaxBattleTeamCreatures

  // Day / night
  DayNightCycleSeconds: 500,
  DayNightStartHour: 7,
  NightStartHour: 20, NightEndHour: 5,
  NightOnlyNightElementsEarn: true, // Shadow/Lightning keep earning at night (BaseIncomeSystem)
  NightSpawnSilverChance: 0.10, NightSpawnGoldChance: 0.05, ShinySpawnChance: 0.02,

  // Capture
  CaptureRange: 30, CaptureAnimationTime: 2.5, CaptureGracePeriod: 10, FaintDuration: 10,
  RarityCaptureCost: { Common: 10, Uncommon: 25, Rare: 60, Epic: 150, Legendary: 400 },

  // AI
  AI_WanderRadius: 60, AI_WanderSpeed: 5, AI_AggroRange: 40, AI_AttackRange: 26,
  AI_AttackCooldown: 2.0, AI_FleeSpeed: 12, AI_FleeRange: 35, AI_PackCallRange: 60,
  AI_PlayerDamage: 5, AI_CreatureProjectileSpeed: 80,

  // Companion
  CompanionAttackRange: 40, CompanionAttackCD: 2.0, CompanionBaseDamage: 1.1,
  CompanionFollowDist: 7, CompanionRespawnCD: 30,

  // Defense
  DefenseAttackRange: 34, DefenseAttackCD: 2.5, DefenseBaseDamage: 12,
  DefensePassiveXP: 3, DefenseKillXP: 15,

  // Player combat
  PlayerMaxHP: 100,
  PlayerRangedDamage: 4, PlayerRangedRange: 60, PlayerRangedCooldown: 0.45, PlayerRangedSpeed: 120,
  PlayerMeleeDamage: 6, PlayerMeleeRange: 10, PlayerMeleeCooldown: 1.2,
  WalkSpeed: 16, SprintSpeed: 28, JumpPower: 22, Gravity: 60,

  // AI raids on the player's base (AIRaidSystem, simplified)
  AIRaidEnabled: true, AIRaidInterval: 150, AIRaidPackSize: [1, 3],

  // Hub vendors
  CuratorCoinPrice: { Common: 1500, Uncommon: 7500, Rare: 45000, Epic: 75000, Legendary: 110000 },
  SellValue: { Common: 5, Uncommon: 15, Rare: 40, Epic: 100, Legendary: 250 },

  // World creature population
  MaxWorldCreatures: 90,
  CreatureActiveRadius: 260, // creatures beyond this are frozen + hidden
};

export const RARITY_COLORS = {
  Common: '#b4b4b4', Uncommon: '#4bc84b', Rare: '#3c82ff', Epic: '#b450ff', Legendary: '#ffb800',
};
export const RARITY_ORDER = { Common: 1, Uncommon: 2, Rare: 3, Epic: 4, Legendary: 5 };
export const VARIANT_COLORS = { Normal: '#c8c8c8', Silver: '#d8dde6', Gold: '#ffd700', Legend: '#ff64ff' };

export const ELEMENT_COLORS = {
  Fire: 0xff501e, Ice: 0x64c8ff, Wind: 0x96ffb4, Earth: 0xb48c50, Shadow: 0x7832b4, Light: 0xfffac8,
  Lightning: 0xffe63c, Water: 0x3296ff, Psychic: 0xc896ff, Metal: 0xa0aab4, Poison: 0x78dc50, Undead: 0x8c78a0,
};
