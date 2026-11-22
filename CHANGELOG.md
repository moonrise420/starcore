# Changelog

## 1.0.3
**New**
- Crosshair aim: pilots and gunners switch the weapons between auto aim (the radar target, with lead) and the crosshair (key `starcore_key_aim`, default middle mouse). Gunners' turrets follow the crosshair without pressing fire.
- Free flight (player setting `starcore_free_flight`, off by default): the mouse turns the ship any way, A and D roll, nothing levels it. The nose follows the mouse and stops where the mouse stopped; the ship flies where its nose points.
- Admin setting "Ships may shoot at their owner's other ships" (`starcore_shoot_own_ships`, on by default).
- Admin setting "Seconds between two 'under attack' messages" (`starcore_attack_notice`, 120 by default, 0 = never), counted per ship.
- Docked ships go through a Stargate or Supergate together with their carrier.
- Hyperspace jumps take loose cargo along: crates and props lying in the ship, as well as standing players.
- New self-destruct sounds: an alarm at the start and at 4 and 1 seconds left, a beep every second, a stop sound, one blast. Without Ascension Gates the countdown uses Garry's Mod's own sounds.

**Changed**
- The ship fires all Ascension Gates ship weapons, but no longer devices that are not ship guns (Gate Overloader, AG-3 Satellite).
- With Ascension Gates 1.0.2: hull damage follows its "Weapons against ships" setting, and its weapons on the ship use the ship's power (ZPMs, generators and batteries welded on). The Power page counts those sources.
- Climbs and turns ease in and out; ships longer than 2000 units tilt less (12 instead of 30 degrees) and slower.
- Engineers repair 0.5 % of the hull a second each (two at most) and pause 5 seconds after a hit.
- Texts in all 12 languages read again and reworded.

**Fixed**
- A ship that hits a wall or the map's edge no longer bounces off faster and faster.
- Crosshair aim skips the own ship. Letting go of fire stops every weapon; drones launch with the crosshair beside, behind or below the ship and keep following it. The aim hint shows only the first time you sit down.
- Getting up from a seat puts you on the deck next to it, also in a tilted or rolled ship - never out through a window or into a console.
- Sitting down in a tilted ship no longer makes the tilt its new level.
- A removed core lets go of what its tractor beam held.
- Works with SpaceGrid's new big ships.
- Ship menu: no more big gaps between Parts, Seats and Size.

## 1.0.2
- Carriers: small ships dock in bigger ones (key N) and fly and jump with them
- Every ship has a name, a hull number and a class, shown on radar, HUD and screens
- New pilot HUD in three looks
- Tractor beam: aims where you look, can be seen, pulls in and pushes away (keys K, I, O); cloak key L
- The autopilot keeps its height over walls; ships fly straight when their parts are not lined up
- No cut-off texts in the ship window (12 languages), which opens on the last tab; clearer texts
- Ships go through Stargates in one piece (with Ascension Gates 1.0.1)

## 1.0.1
- Admin settings page: spawn menu Utilities > Admin > StarCore - every server setting as a checkbox, slider or choice (only admins can change them)
- New server setting: hyperspace jumps on/off (starcore_allow_jump)
- Pilot seat keys, changeable in the menu under Settings: look around (Alt - hold or tap), mouse steering on/off (M), hover on/off (H), freeze/unfreeze (J); also console binds starcore_toggle_look, _mouse, _hover, _freeze
- "Park" / "Hold position" is now called "Freeze" everywhere; the Wire input Park is now Freeze (wire old builds again), new Wire output Frozen
- Fixed: the menu window can be moved and resized again (title bar, edges, corner)
- The pilot seat hint shows only on the first sit-down of a game

## 1.0.0
First release.

- One core turns a build into a ship: hover, autopilot, hyperspace jumps with safety checks
- Radar, auto-defence, shields, cloak, tractor beam, crew seats, hull and repair
- Stargate tie-in and Asgard beaming with Ascension Gates (or CAP / EAP)
- 12 core designs in four families, HUD and ship screens in your own units
