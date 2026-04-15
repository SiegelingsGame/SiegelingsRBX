--[[
	LivingWorldData.lua - ReplicatedStorage/Modules
	Data for the "Living World" ticker: 8 NPC archetypes and 100 lore-accurate
	4-message conversations. Categories: rare_spawn, dungeon, world_event, pvp_koth, time_system.
]]

local LivingWorldData = {}

-- 8 distinct NPC archetypes (unique dialogue styles)
LivingWorldData.NPCs = {
	{ id = "salty_vet",    name = "Ser Grimjaw",     style = "Gruff, slang, 'back in my day'" },
	{ id = "rookie",       name = "Squire Val",     style = "ALL CAPS when excited, enthusiastic" },
	{ id = "merchant",     name = "Coinweaver Aldric", style = "Profit-focused, numbers, formal" },
	{ id = "scholar",      name = "Brother Codex",   style = "Formal, archaic, 'the chronicles say'" },
	{ id = "scout",        name = "Watchman Reed",  style = "Short, tactical, warnings" },
	{ id = "champion",     name = "Ser Vex",         style = "Boastful, arena-focused" },
	{ id = "mystic",       name = "The Veiled One",  style = "Brief, cryptic, poetic" },
	{ id = "crier",        name = "Herald Maren",    style = "Dramatic, announcements" },
}

-- Map NPC id -> display name for ticker
local function getNpcName(id)
	for _, npc in ipairs(LivingWorldData.NPCs) do
		if npc.id == id then return npc.name end
	end
	return "Unknown"
end
LivingWorldData.GetNpcName = getNpcName

-- Conversations: initiatorId, responderId, category, messages[4]
-- Message order: Initiator, Responder, Initiator follow-up, Responder goodbye
LivingWorldData.Conversations = {
	-- ========== RARE SPAWNS (25) ==========
	{
		category = "rare_spawn",
		initiatorId = "rookie",
		responderId = "scout",
		messages = {
			"JUST SAW A SHADOW DRAKE NEAR THE WHISPERING WOODS!!!",
			"They only hunt when the moon is high. Watch your back.",
			"I'm not going near that without a Holy Enchantment!",
			"Good call. Stay safe out there.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "salty_vet",
		responderId = "scholar",
		messages = {
			"Spotted a Cinderstag east of the old forge. Rare sight.",
			"The chronicles say they appear when the ember-winds blow. You were fortunate.",
			"Back in my day we didn't need chronicles. We had eyes.",
			"Indeed. May your eyes keep you alive, Ser.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "scout",
		responderId = "mystic",
		messages = {
			"Nightfang pack moving through the northern pass.",
			"Shadows taste the same at dawn.",
			"Understood. I'll report at the next bell.",
			"Go.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "merchant",
		responderId = "champion",
		messages = {
			"A Frost Wisp was seen near the Ice Sanctum. Estimated value: substantial.",
			"I've crushed frost. Bring your coin; I'll bring the proof.",
			"Twenty percent finder's fee if you tag it first.",
			"Deal. The arena pays; the wild pays better.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "crier",
		responderId = "rookie",
		messages = {
			"ATTENTION: A Pylord has been sighted in the Ember Depths!",
			"NO WAY!! I WANT TO SEE IT!!!",
			"Only the boldest dare approach. You have been warned.",
			"I'M GONNA BE BOLD!!!",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "scholar",
		responderId = "scout",
		messages = {
			"The texts speak of a Solgator in the volcanic basin. I wish to verify.",
			"Basin's hot and it hits hard. Bring a full team.",
			"I shall. The chronicles must be updated.",
			"Update them from a distance. Good luck.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "mystic",
		responderId = "salty_vet",
		messages = {
			"Something stirs in the deep wood. Rare.",
			"Yeah, I felt it too. Kids these days'll run in blind.",
			"The blind see nothing. The prepared see enough.",
			"Then stay prepared. Don't get cocky.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "champion",
		responderId = "merchant",
		messages = {
			"I heard a Dracoil's been spawning near the lava pits. I want it.",
			"Dracoil pelts fetch a fine price. I'll fund your trip for a cut.",
			"Fifty-fifty. I do the fighting.",
			"Sixty-forty. I do the risk. Agreed.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "rookie",
		responderId = "mystic",
		messages = {
			"SOMEONE SAID THERE'S A GOLD VARIANT NEAR THE LAKE!!!",
			"Gold is what you make of the light.",
			"SO GO AT SUNSET??",
			"Or dawn. The lake does not care.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "salty_vet",
		responderId = "scout",
		messages = {
			"Hexweaver spotted in the swamp. Nasty piece of work.",
			"Confirmed. Avoid unless you've got dispel or a full squad.",
			"I've got both. Just wanted the intel.",
			"Intel delivered. Don't say we didn't warn you.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "merchant",
		responderId = "scholar",
		messages = {
			"Rumors of a Silver Cinderstag in the high meadows. Rare market.",
			"The chronicles note that silver variants emerge under the full moon.",
			"Then I'll have my buyers there at moonrise. Thank you, Brother.",
			"Knowledge serves commerce. May your ledgers balance.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "crier",
		responderId = "salty_vet",
		messages = {
			"By order of the Watch: a Furnacejaw has been seen near the forge district!",
			"Great. Another thing setting the place on fire.",
			"Citizens are advised to avoid the area until the beast is subdued.",
			"I'll subdue it. Someone's gotta do it.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "scout",
		responderId = "rookie",
		messages = {
			"Pyleer activity in the eastern vents. Stay clear if you're new.",
			"I'M NOT NEW I'VE BEEN HERE LIKE TWO WEEKS!!!",
			"Two weeks is new. Stay clear.",
			"FINE BUT I'M COMING BACK WHEN I'M READY!!!",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "scholar",
		responderId = "mystic",
		messages = {
			"I have read of a creature that appears only at the stroke of midnight. Do you know it?",
			"The hour knows. I do not.",
			"Then I shall observe the hour and record what I see.",
			"Record. The hour will not repeat.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "champion",
		responderId = "crier",
		messages = {
			"I'm hunting the Pylord. Make sure everyone knows who bagged it.",
			"The Herald shall announce: Ser Vex seeks the Pylord!",
			"Good. I don't do quiet.",
			"Neither does the beast. May your name be remembered.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "mystic",
		responderId = "scout",
		messages = {
			"Three shadows move as one past the western gate.",
			"Noted. I'll double the watch there tonight.",
			"They seek the same as we. Only the path differs.",
			"Understood. We'll be ready.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "rookie",
		responderId = "champion",
		messages = {
			"I HEARD NIGHTFANGS ARE EASIER TO CATCH AT NIGHT IS THAT TRUE???",
			"Everything's easier when you're not scared. Are you scared?",
			"NO!!! WELL. A LITTLE.",
			"Good. Fear keeps you sharp. Now go catch one.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "salty_vet",
		responderId = "merchant",
		messages = {
			"Shadeblob cluster near the crypt. Nasty but valuable if you know how.",
			"I know how. What's your cut for the location?",
			"Ten percent. I'm too old to farm them myself.",
			"Fifteen and I throw in antidotes. Done.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "merchant",
		responderId = "rookie",
		messages = {
			"A rare egg merchant passed through. Gold-tier potential. Did you see him?",
			"I SAW SOMEONE WITH A WEIRD CART WAS THAT HIM???",
			"Likely. Next time, note his direction. I pay for leads.",
			"I WILL!!! I NEED COINS!!!",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "crier",
		responderId = "scholar",
		messages = {
			"The Council requests verification: has the legendary Stormcaller been seen this season?",
			"The chronicles do not lie. It was seen once, at the equinox. Not since.",
			"Then the announcement shall stand: still at large.",
			"As it has been. As it may ever be.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "scout",
		responderId = "champion",
		messages = {
			"Duskmoth swarm in the vale. Don't go alone.",
			"I don't go alone. I go with my team. We'll clear it.",
			"Your call. Just don't say I didn't warn you.",
			"Warnings noted. Trophies incoming.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "scholar",
		responderId = "rookie",
		messages = {
			"According to the Codex, a Gloomrat nest holds a single alpha with silver fur. Have you seen such a thing?",
			"I SAW A WEIRD BIG ONE ONCE!!! BY THE OLD WELL!!!",
			"Fascinating. The Codex shall be updated. Thank you, Squire.",
			"NO PROBLEM!!! CAN I GET CREDIT???",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "champion",
		responderId = "scout",
		messages = {
			"I need a challenge. What's the rarest thing in the wild right now?",
			"Pylord, if you're stupid. Solgator if you're smart.",
			"Pylord it is. Watch the ticker for my name.",
			"I'll watch the ticker for your obituary. Your choice.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "mystic",
		responderId = "crier",
		messages = {
			"The wind carries a name. Rare. It will not last.",
			"Shall I announce it? The people deserve to know.",
			"Announce only that something rare passes. Let them seek.",
			"So it shall be. The Herald speaks.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "rookie",
		responderId = "salty_vet",
		messages = {
			"OLD SER DO YOU KNOW WHERE SILVER VARIANTS SPAWN???",
			"Kid, I've forgotten more spawns than you've seen. Check the moon.",
			"THE MOON!!! THANKS!!!",
			"Yeah. And don't call me old.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "salty_vet",
		responderId = "crier",
		messages = {
			"Saw a Gold Fawny near the frost lake. Pretty thing.",
			"Shall we announce it? The hunters would thank you.",
			"Nah. Let the kids find it themselves. Builds character.",
			"Wise. The Herald will stay silent.",
		},
	},
	{
		category = "rare_spawn",
		initiatorId = "merchant",
		responderId = "scout",
		messages = {
			"I've had three reports of a legendary creature near the arena. Can you confirm?",
			"Confirming would require going there. I'm not paid to fight legends.",
			"I'll pay. Scout only. No engagement.",
			"Then we have a deal. I'll report by dusk.",
		},
	},
	-- ========== DUNGEONS (25) ==========
	{
		category = "dungeon",
		initiatorId = "scout",
		responderId = "scholar",
		messages = {
			"Legendary dungeon just opened in the Fire biome. Heavy resistance.",
			"The chronicles speak of such gates. They close as swiftly as they open.",
			"How long do we have?",
			"Two bells, perhaps. Gather your strongest.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "champion",
		responderId = "rookie",
		messages = {
			"I'm heading into the Ice dungeon. Who's with me?",
			"ME!!! PICK ME!!!",
			"You're in. Don't freeze. Literally.",
			"I WON'T!!! I BROUGHT POTIONS!!!",
		},
	},
	{
		category = "dungeon",
		initiatorId = "merchant",
		responderId = "salty_vet",
		messages = {
			"The Earth dungeon is open. Loot estimates are substantial.",
			"I've run that one. Bring a tank and a dispel. Boss hits like a wagon.",
			"Noted. I'm funding a run. Ten percent to you for the map.",
			"Deal. Map's in my head. Let's go.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "crier",
		responderId = "mystic",
		messages = {
			"By the Council's word: a new dungeon has manifested in the Shadowlands!",
			"Manifested. Or awakened. The difference matters not to the fallen.",
			"Citizens are advised to prepare before entering.",
			"Prepare. Then step. Or do not step at all.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "scholar",
		responderId = "scout",
		messages = {
			"I have located the entrance to the Lost Sanctum. It is as the Codex described.",
			"How many inside?",
			"Unknown. The Codex does not number the dead.",
			"I'll number them. Give me an hour.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "rookie",
		responderId = "champion",
		messages = {
			"THE DUNGEON BOSS DROPPED A LEGENDARY EGG!!!",
			"Which dungeon? I want one.",
			"THE FIRE ONE BY THE VOLCANO!!!",
			"Good. Save me a spot next run.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "salty_vet",
		responderId = "merchant",
		messages = {
			"Boss in the Earth dungeon's down. Loot's up for trade.",
			"What tier? I'll make an offer.",
			"Epic tier. Two pieces. You know what I want.",
			"The Holy Enchantment. Done. Meet at the market.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "mystic",
		responderId = "crier",
		messages = {
			"The gate weakens. It will not hold another cycle.",
			"Then the Herald shall cry: the dungeon closes at nightfall!",
			"Cry well. Many will not hear in time.",
			"They will hear. The rest is fate.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "scout",
		responderId = "champion",
		messages = {
			"Ice dungeon boss has a freeze aura. Plan accordingly.",
			"I've got fire types. We're good.",
			"Fire types slow it. You still need a dispel for the adds.",
			"Noted. I'll bring the squad.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "merchant",
		responderId = "scholar",
		messages = {
			"I'm organizing a paid run through the Shadow dungeon. Need a chronicler.",
			"I shall chronicle. In exchange, first pick of any codex or scroll.",
			"Deal. We leave at dawn.",
			"So be it. The chronicles will grow.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "crier",
		responderId = "rookie",
		messages = {
			"ATTENTION: The Legendary Dungeon in the Fire biome will close in ONE HOUR!",
			"NOOO I HAVEN'T FINISHED MY RUN YET!!!",
			"All knights are advised to evacuate or complete objectives immediately!",
			"I'M GOING BACK IN!!!",
		},
	},
	{
		category = "dungeon",
		initiatorId = "champion",
		responderId = "salty_vet",
		messages = {
			"We wiped on the Earth boss. Need someone who's cleared it.",
			"Fine. I'll lead. You follow. No heroics.",
			"Just get us the clear. I'll handle heroics after.",
			"Heroics get people killed. Follow the plan.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "scholar",
		responderId = "mystic",
		messages = {
			"The dungeon's layout matches the pre-Siege maps. Something changed beneath.",
			"Beneath is where the old world sleeps. You walk on history.",
			"Then I shall record what history leaves behind.",
			"Record. Do not wake what sleeps.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "rookie",
		responderId = "scout",
		messages = {
			"HOW DO I KNOW WHICH DUNGEON IS LEGENDARY???",
			"Gold gate. Red glow. You'll hear the crier.",
			"OH!!! I SAW ONE BUT I WAS SCARED!!!",
			"Good. Next time, bring a team. Don't go alone.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "salty_vet",
		responderId = "crier",
		messages = {
			"Shadow dungeon's open. Tell the rookies to stay out.",
			"The Herald shall announce: experienced knights only in the Shadowlands!",
			"Yeah. We lost two last time. No more greenhorns.",
			"So it shall be cried. Stay safe, Ser.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "mystic",
		responderId = "scout",
		messages = {
			"Three gates will open before the moon sets.",
			"Which biomes?",
			"Fire. Ice. Shadow.",
			"I'll spread the word. Be ready.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "scout",
		responderId = "merchant",
		messages = {
			"Dungeon loot tables are updated. Epic drop rate's up in Ice.",
			"I'll redirect my buyers. What's the window?",
			"Until the next patch. So they say.",
			"Then we move fast. Thank you, Watchman.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "merchant",
		responderId = "champion",
		messages = {
			"I'm buying dungeon carries. Top rate for a clean Legendary clear.",
			"I don't carry. I lead. Same rate?",
			"Same rate. I need three runs this week.",
			"Done. Send me the times.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "crier",
		responderId = "scholar",
		messages = {
			"The Council seeks a chronicler for the next dungeon expedition. Brother Codex?",
			"I shall answer. The Codex must be complete.",
			"Then you are summoned. The gate opens at dawn.",
			"I shall be there. The chronicles await.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "champion",
		responderId = "mystic",
		messages = {
			"I've cleared every dungeon. What's next?",
			"The next gate is not one you walk through.",
			"Then I'll break it. That's what I do.",
			"Perhaps. Or perhaps it breaks you.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "rookie",
		responderId = "merchant",
		messages = {
			"I GOT AN EPIC FROM THE DUNGEON!!! WHAT DO I DO WITH IT???",
			"Sell it to me. I'll give you market minus ten. Or use it and get stronger.",
			"STRONGER!!! I WANNA FIGHT THE BOSS!!!",
			"Then equip it. Come back when you have more. I'll buy.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "scholar",
		responderId = "rookie",
		messages = {
			"The Lost Sanctum holds a boss that has never been felled. Do you wish to join the attempt?",
			"YES!!! I MEAN... IS IT DANGEROUS???",
			"Extremely. The chronicles list seventeen failed attempts.",
			"THEN I'M THE EIGHTEENTH!!! I MEAN SUCCESS!!!",
		},
	},
	{
		category = "dungeon",
		initiatorId = "salty_vet",
		responderId = "scout",
		messages = {
			"Running the Shadow dungeon at dusk. You in?",
			"Shadow at dusk is suicide. You know that.",
			"I've done it before. Need a steady hand at the back.",
			"Fine. But we leave at first light. Not dusk.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "mystic",
		responderId = "rookie",
		messages = {
			"The gate waits. So do the dead.",
			"THAT'S CREEPY!!! BUT I STILL WANNA GO!!!",
			"Then go. Or do not. The gate does not care.",
			"I'M GONNA GO!!!",
		},
	},
	{
		category = "dungeon",
		initiatorId = "crier",
		responderId = "champion",
		messages = {
			"Ser Vex! The Herald announces: you hold the record for fastest Ice dungeon clear!",
			"Of course I do. Who's second?",
			"Squire Val. By three minutes.",
			"Val? Good. I'll make sure they don't catch up.",
		},
	},
	{
		category = "dungeon",
		initiatorId = "scout",
		responderId = "rookie",
		messages = {
			"Dungeon boss mechanics: don't stand in the red. Heal the tank.",
			"WHAT'S THE RED???",
			"The bad stuff on the ground. You'll see it.",
			"OH!!! I'LL WATCH FOR IT!!!",
		},
	},
	{
		category = "dungeon",
		initiatorId = "merchant",
		responderId = "crier",
		messages = {
			"I need the next dungeon opening announced. I'll pay for the slot.",
			"The Herald does not sell announcements. But we accept donations.",
			"Donation. Right. How much for 'Coinweaver Aldric sponsors the next run'?",
			"Fifty gold. And we say 'generously sponsors.' Your choice.",
		},
	},
	-- ========== WORLD EVENTS / RAIDS (20) ==========
	{
		category = "world_event",
		initiatorId = "crier",
		responderId = "scout",
		messages = {
			"RAID ALERT: Incoming assault on the western strongholds! All defenders to arms!",
			"Scouts confirm three waves. First wave in five.",
			"The Council demands a full muster!",
			"We're ready. Just keep the civilians clear.",
		},
	},
	{
		category = "world_event",
		initiatorId = "scout",
		responderId = "champion",
		messages = {
			"World event's live. Big one. Arena's locked for the duration.",
			"Then I'm going to the event. More glory there.",
			"Glory and death. Bring a full team.",
			"I always do. See you on the field.",
		},
	},
	{
		category = "world_event",
		initiatorId = "rookie",
		responderId = "salty_vet",
		messages = {
			"THERE'S A RAID COMING!!! WHAT DO I DO???",
			"Get to your base. Slot your defense team. Don't panic.",
			"MY BASE!!! OK!!!",
			"Good. And kid? Stay calm. Panic gets you robbed.",
		},
	},
	{
		category = "world_event",
		initiatorId = "merchant",
		responderId = "scholar",
		messages = {
			"Market's closing for the raid. All assets secured?",
			"The chronicles are locked. The vault holds.",
			"Good. I've moved the high-value stock. See you after.",
			"May the siege break before it reaches us.",
		},
	},
	{
		category = "world_event",
		initiatorId = "scholar",
		responderId = "mystic",
		messages = {
			"The old texts speak of a raid that lasts three bells. This feels like that.",
			"Three bells. Or three days. Time bends in the siege.",
			"Then we hold until it unbends.",
			"Hold. Or fall. There is no third path.",
		},
	},
	{
		category = "world_event",
		initiatorId = "champion",
		responderId = "crier",
		messages = {
			"I'm leading the counter-raid. Announce it.",
			"THE HERALD CRIES: Ser Vex leads the counter-raid! Who stands with him?",
			"Anyone with a shield and a spine.",
			"So it shall be announced! May valor prevail!",
		},
	},
	{
		category = "world_event",
		initiatorId = "mystic",
		responderId = "scout",
		messages = {
			"The winds shift. Something comes.",
			"Direction?",
			"North. Then east. Then everywhere.",
			"Understood. I'll alert the watch.",
		},
	},
	{
		category = "world_event",
		initiatorId = "salty_vet",
		responderId = "rookie",
		messages = {
			"Raid's hitting the south gate. You lot, with me.",
			"ME??? REALLY???",
			"Yeah. Stick close. Do what I say. You'll live.",
			"I WILL!!! I WON'T LET YOU DOWN!!!",
		},
	},
	{
		category = "world_event",
		initiatorId = "crier",
		responderId = "merchant",
		messages = {
			"The raid has been repelled! Rejoice!",
			"Rejoice and reopen. I've got buyers waiting.",
			"The Council will hold a victory gathering at dusk!",
			"I'll be there. With my ledger.",
		},
	},
	{
		category = "world_event",
		initiatorId = "scout",
		responderId = "merchant",
		messages = {
			"Second wave incoming. Stronger than the first.",
			"How long until they hit the market district?",
			"Ten minutes if we don't hold the bridge.",
			"Then hold it. I'll pay the defenders bonus.",
		},
	},
	{
		category = "world_event",
		initiatorId = "rookie",
		responderId = "champion",
		messages = {
			"I SURVIVED MY FIRST RAID!!! WE WON!!!",
			"Good. Next time, get a kill. That's when it counts.",
			"I GOT TWO!!! WELL ONE AND A HALF!!!",
			"Half doesn't count. But two next time. You're learning.",
		},
	},
	{
		category = "world_event",
		initiatorId = "merchant",
		responderId = "scout",
		messages = {
			"I'm offering a bounty for every raid attacker defeated. Paid on proof.",
			"What counts as proof?",
			"Kill feed. Capture. Or a witness. Your call.",
			"Then my watch is for hire. We'll deliver.",
		},
	},
	{
		category = "world_event",
		initiatorId = "scholar",
		responderId = "crier",
		messages = {
			"The chronicles record this as the seventh great raid of the age. We endure.",
			"Shall the Herald announce the historical significance?",
			"If you wish. The people may take comfort in precedent.",
			"So it shall be cried. We have endured before; we endure again.",
		},
	},
	{
		category = "world_event",
		initiatorId = "champion",
		responderId = "salty_vet",
		messages = {
			"Raid boss is down. Who's cleaning up the rest?",
			"I'll take the east. You take the west. Rookies hold the square.",
			"Done. Meet at the gate when it's clear.",
			"Don't be late. I'm not waiting.",
		},
	},
	{
		category = "world_event",
		initiatorId = "mystic",
		responderId = "rookie",
		messages = {
			"When the bells ring thrice, the veil thins.",
			"WHAT DOES THAT MEAN???",
			"It means run to your base. Now.",
			"OK!!!",
		},
	},
	{
		category = "world_event",
		initiatorId = "salty_vet",
		responderId = "scout",
		messages = {
			"Heard the AI raiders are hitting harder this cycle.",
			"Confirmed. They're targeting income slots first now.",
			"Smart. We'll need to rotate defenders.",
			"I'll draw up a roster. Send me your availability.",
		},
	},
	{
		category = "world_event",
		initiatorId = "crier",
		responderId = "rookie",
		messages = {
			"ATTENTION: World event in FIFTEEN MINUTES! Prepare your defenses!",
			"I'M PREPARED!!! I THINK!!!",
			"Slot your defense team! Secure your Siegelings!",
			"I DID!!! MY MOM IS ON DEFENSE!!!",
		},
	},
	{
		category = "world_event",
		initiatorId = "scout",
		responderId = "scholar",
		messages = {
			"Event boss has a new mechanic. We need intel from the old raids.",
			"The Codex holds three accounts. I shall retrieve them.",
			"Fast. We've got one hour before it spawns.",
			"I shall be swift. The chronicles serve the living.",
		},
	},
	{
		category = "world_event",
		initiatorId = "merchant",
		responderId = "champion",
		messages = {
			"Raid recovery market is open. Selling potions and repair kits at cost.",
			"I'll take twenty of each. Put it on my tab.",
			"Tab's full, Ser. Cash or trade.",
			"Trade. I've got dungeon loot. We'll settle after.",
		},
	},
	{
		category = "world_event",
		initiatorId = "scholar",
		responderId = "salty_vet",
		messages = {
			"The chronicles say the ninth wave is always the hardest. We are at eight.",
			"Then we hold. Like we always do.",
			"May the Codex record our victory.",
			"May we live to read it. Form up.",
		},
	},
	-- ========== PVP / KING OF THE HILL (20) ==========
	{
		category = "pvp_koth",
		initiatorId = "champion",
		responderId = "crier",
		messages = {
			"I'm taking the Hill today. Make sure everyone knows.",
			"The Herald announces: Ser Vex challenges for the Hill!",
			"Not a challenge. A statement. I'm taking it.",
			"So it shall be cried! May the best knight prevail!",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "rookie",
		responderId = "scout",
		messages = {
			"WHO'S ON THE HILL RIGHT NOW???",
			"Ser Vex. Three hours. No challengers yet.",
			"CAN I CHALLENGE???",
			"You can. I wouldn't. Not yet.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "merchant",
		responderId = "scholar",
		messages = {
			"I'm taking bets on the next King of the Hill. Who's the favorite?",
			"The chronicles favor the reigning champion until the reign ends. Currently Ser Vex.",
			"Odds on him holding another hour?",
			"Even. The Hill is fickle. So say the chronicles.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "salty_vet",
		responderId = "champion",
		messages = {
			"Heard you got knocked off the Hill. Tough break.",
			"Temporary. I'm going back up in an hour.",
			"Kid who took it's got a mean team. Don't underestimate.",
			"I don't underestimate. I prepare. Then I win.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "crier",
		responderId = "rookie",
		messages = {
			"NEW CHAMPION: Squire Val has claimed the Hill!",
			"WAIT THAT'S ME!!! I DID IT!!!",
			"The Herald confirms: Squire Val holds the Hill!",
			"I'M GONNA HOLD IT FOREVER!!!",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "scout",
		responderId = "merchant",
		messages = {
			"Rumor: a dark horse is gathering a team to take the Hill tonight.",
			"Name? I'll adjust the odds.",
			"Won't say. But they've got funding. Serious.",
			"Then I'll hedge. Always hedge.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "scholar",
		responderId = "mystic",
		messages = {
			"The Codex records that the Hill has changed hands seven times this week. Unprecedented.",
			"The Hill wants what it wants. It does not keep.",
			"Then we are in turbulent times.",
			"Or the Hill is awake. Both are true.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "mystic",
		responderId = "champion",
		messages = {
			"The crown is heavy. You wear it well. For now.",
			"For now? I'll wear it as long as I want.",
			"The Hill does not care what you want.",
			"Then we'll see who cares. I'm not stepping down.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "champion",
		responderId = "rookie",
		messages = {
			"Who's next? I'm bored.",
			"ME!!! I MEAN CAN I TRY???",
			"You can try. Bring your best. Don't cry when you lose.",
			"I WON'T!!! I'M GONNA GIVE IT EVERYTHING!!!",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "rookie",
		responderId = "salty_vet",
		messages = {
			"SER GRIMJAW DO YOU THINK I CAN BE KING OF THE HILL???",
			"Maybe. When you stop typing in caps and start winning.",
			"I'M WORKING ON IT!!!",
			"Good. Work harder. The Hill doesn't care about enthusiasm.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "merchant",
		responderId = "crier",
		messages = {
			"Can you announce the current Hill standings? I've got a betting pool.",
			"The Herald announces: Ser Vex, one hour. No challengers in queue.",
			"Add: Coinweaver Aldric offers even odds on the next upset.",
			"So it shall be cried. May the odds serve you.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "crier",
		responderId = "scholar",
		messages = {
			"The Council requests a formal record of Hill succession this month.",
			"I shall compile the chronicles. Seven holders in thirty days.",
			"Make it official. The Council meets at dusk.",
			"It shall be done. The Codex will hold the truth.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "salty_vet",
		responderId = "scout",
		messages = {
			"I'm sitting out the Hill this week. Too much drama.",
			"Smart. The new blood's fighting dirty. Metaphorically.",
			"Yeah. Let them burn out. I'll be back when it's quiet.",
			"If it ever is. I'll keep you posted.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "scout",
		responderId = "champion",
		messages = {
			"Someone's gunning for you. Full meta team. They've been practicing.",
			"Let them. I've beaten meta before.",
			"Just saying. Don't get cocky.",
			"Cocky wins the Hill. I'm good.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "scholar",
		responderId = "rookie",
		messages = {
			"The chronicles note that the youngest to hold the Hill was Squire Val. That is you.",
			"REALLY??? I'M IN THE CHRONICLES???",
			"Indeed. Your name is recorded. Honor it.",
			"I WILL!!! I'LL HOLD IT AGAIN!!!",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "mystic",
		responderId = "salty_vet",
		messages = {
			"The Hill will have a new master by week's end. Or the same. The wind is unclear.",
			"Helpful. So either someone wins or they don't.",
			"Yes.",
			"Yeah. I'll stick to the ticker. Less cryptic.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "champion",
		responderId = "merchant",
		messages = {
			"I'm defending the Hill at dusk. You in for the side bets?",
			"I'm always in. What's the spread?",
			"Me by three. Take it or leave it.",
			"Done. Don't disappoint the ledger.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "rookie",
		responderId = "mystic",
		messages = {
			"THE VEILED ONE!!! WHO DO YOU THINK WILL WIN THE HILL NEXT???",
			"The one who stands when the bell rings.",
			"THAT'S SO VAGUE!!!",
			"Perhaps. Or perhaps it is all that can be said.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "crier",
		responderId = "salty_vet",
		messages = {
			"Ser Grimjaw! Rumor says you're returning to the Hill. True?",
			"Maybe. When I feel like it. Don't cry it yet.",
			"The Herald awaits your word!",
			"You'll hear it when I'm on top. Not before.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "merchant",
		responderId = "champion",
		messages = {
			"Your reign's been good for business. Longer you hold, longer the odds shift.",
			"So keep the odds in my favor. I like winning.",
			"I keep the odds in my favor. You're just the current vehicle.",
			"Vehicle. Right. Just don't crash me.",
		},
	},
	{
		category = "pvp_koth",
		initiatorId = "salty_vet",
		responderId = "rookie",
		messages = {
			"Kid took the Hill. Good for them. Now we see if they can keep it.",
			"YOU MEAN SQUIRE VAL??? THAT'S ME!!!",
			"Yeah. You. Don't let it go to your head.",
			"I WON'T!!! I PROMISE!!!",
		},
	},
	-- ========== TIME SYSTEM (10) ==========
	{
		category = "time_system",
		initiatorId = "scholar",
		responderId = "scout",
		messages = {
			"The fourth bell approaches. The chronicles mark it as a time of transition.",
			"Fourth bell. Shift change. I'll pass the word.",
			"May the new shift find the realm at peace.",
			"So we hope. Stay vigilant.",
		},
	},
	{
		category = "time_system",
		initiatorId = "crier",
		responderId = "mystic",
		messages = {
			"The hour strikes four! All is well!",
			"Four. The middle of the long dark. Or the long light. The hour does not say.",
			"The Herald declares: the realm holds!",
			"It holds. For now.",
		},
	},
	{
		category = "time_system",
		initiatorId = "merchant",
		responderId = "rookie",
		messages = {
			"Market closes at the eighth bell. Plan your trades.",
			"WHAT BELL IS IT NOW???",
			"Sixth. You have time. Don't waste it.",
			"OK!!! I'LL HURRY!!!",
		},
	},
	{
		category = "time_system",
		initiatorId = "scout",
		responderId = "salty_vet",
		messages = {
			"Twelfth bell in ten. Night watch begins.",
			"I'm on it. Same as always.",
			"Double the patrols. You know the drill.",
			"Yeah. See you at dawn.",
		},
	},
	{
		category = "time_system",
		initiatorId = "mystic",
		responderId = "scholar",
		messages = {
			"The sun crosses the line. The hour turns.",
			"Which hour? The chronicles must be precise.",
			"The hour that is. No more. No less.",
			"I shall record: the hour turned. So be it.",
		},
	},
	{
		category = "time_system",
		initiatorId = "rookie",
		responderId = "crier",
		messages = {
			"IS IT NIGHT YET??? I WANNA HUNT NIGHTFANGS!!!",
			"The eighth bell has not yet rung! Day holds!",
			"OK!!! I'LL WAIT!!!",
			"Patience, Squire! The night comes for us all!",
		},
	},
	{
		category = "time_system",
		initiatorId = "champion",
		responderId = "merchant",
		messages = {
			"What bell? I've got a run at the next interval.",
			"Next interval is four bells. You've got time.",
			"Good. Don't start without me.",
			"The market waits for no one. But I'll hold your slot.",
		},
	},
	{
		category = "time_system",
		initiatorId = "salty_vet",
		responderId = "mystic",
		messages = {
			"Nightfall's coming. You feel it?",
			"The shadows lengthen. They always do.",
			"Yeah. Stay sharp. Things get weird after dark.",
			"Weird is only a word. The dark is real.",
		},
	},
	{
		category = "time_system",
		initiatorId = "scholar",
		responderId = "crier",
		messages = {
			"Brother Codex notes: the twentieth hour approaches. Nightfall.",
			"Then the Herald shall cry: Nightfall approaches! Prepare yourselves!",
			"The chronicles advise vigilance. So do I.",
			"So it shall be announced! The realm is warned!",
		},
	},
	{
		category = "time_system",
		initiatorId = "crier",
		responderId = "scout",
		messages = {
			"Four-hour mark! All stations report!",
			"Watch reports clear. No incidents.",
			"The Council is pleased! Hold the line!",
			"We hold. Next report at eight bells.",
		},
	},
}

-- System alerts: injected at Nightfall or at 4-hour intervals, in character voices.
-- Each entry: npcId, text (may use placeholder like {hour} for time alerts)
LivingWorldData.SystemAlerts = {
	nightfall = {
		{ npcId = "scholar",  text = "The chronicles warn: nightfall approaches. The shadows stir." },
		{ npcId = "crier",    text = "By the Council's word: NIGHTFALL approaches! Secure your holdings!" },
		{ npcId = "scout",    text = "Night watch in ten. Stay sharp." },
		{ npcId = "mystic",   text = "The moon rises. What sleeps will wake." },
		{ npcId = "salty_vet", text = "Heads up. It's getting dark. Slot your defenses." },
		{ npcId = "merchant", text = "Market closes at nightfall. Final trades now." },
		{ npcId = "champion", text = "Night means rare spawns. And raiders. Be ready." },
		{ npcId = "rookie",   text = "NIGHTFALL!!! DON'T FORGET TO SET YOUR DEFENSE TEAM!!!" },
	},
	time = {
		{ npcId = "crier",    text = "The hour strikes {hour}! All is well in the realm!" },
		{ npcId = "scholar",  text = "The {hour}th bell. The chronicles mark this as a time of change." },
		{ npcId = "merchant", text = "{hour} bells. Market open. Come and trade." },
		{ npcId = "scout",    text = "{hour} o'clock. Watch reports clear." },
		{ npcId = "mystic",   text = "The wheel turns. Hour {hour}." },
		{ npcId = "salty_vet", text = "Hour {hour}. Same as always. Stay alert." },
		{ npcId = "champion", text = "{hour} bells. Training grounds are open. Who's with me?" },
		{ npcId = "rookie",   text = "IT'S {hour} O'CLOCK!!! WHAT DO WE DO NOW???" },
	},
}

return LivingWorldData
