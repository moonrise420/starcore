# StarCore - Ship System
<img src=".github/images/thumbnail.jpg" width="220" align="right" alt="">
> Build anything. Put a core in it. Fly it.

StarCore turns whatever you built into a real spaceship. Weld one core to your build, sit down, and it flies: hover, jump through hyperspace, raise shields, fire your guns. No E2, no wiring, no setup - the core finds the ship by itself.

## Install
**Steam Workshop (easiest):** subscribe [there](https://steamcommunity.com/sharedfiles/filedetails/?id=3840678974).

**By hand:** download `starcore-1.0.2.zip` from [Releases](../../releases/latest) and unpack it into
`garrysmod/addons/` (you get the folder `garrysmod/addons/starcore`).

## Bugs, problems and wishes
Please use [Issues](../../issues): pick *Bug report* or *Wish or idea*. On the Steam Workshop page the comments work too.

## Pictures
<p>
<img src=".github/images/01_gal_sc_reactor_core_1.jpg" width="49%" alt="">
<img src=".github/images/02_gal_sc_crystal_heart_2.jpg" width="49%" alt="">
<img src=".github/images/03_gal_sc_alien_artifact_1.jpg" width="49%" alt="">
<img src=".github/images/04_gal_sc_military_case_2.jpg" width="49%" alt="">
<img src=".github/images/05_gal_sc_crystal_heart_1.jpg" width="49%" alt="">
<img src=".github/images/06_gal_sc_reactor_core_2.jpg" width="49%" alt="">
<img src=".github/images/07_gal_sc_alien_artifact_2.jpg" width="49%" alt="">
</p>

---

## What's inside

### Flight
- Hover, height lock, WASD, turn, climb and dive, boost - or steer with the mouse
- Keys you can change for looking around (Alt: hold or tap), mouse steering, hover, freeze, tractor beam (grab, pull in, push away), cloak and docking
- Walk around the bridge while the ship flies: nobody slides off
- Autopilot: fly to a point or follow a target, climbing over obstacles on the way
- Carriers: small ships dock in bigger ones and fly and jump with them
- Hyperspace jumps to saved marks or coordinates, with safety checks before every jump, and three jump effects to choose from

### Combat and crew
- Radar with friend and foe, auto-defence, aim with lead for any Wire weapon that has a Fire input (CAP turrets, cannons, rail guns, Wire turrets)
- Shields, cloak, self-destruct, a tractor beam you can see that grabs what you look at, pulls it in or pushes it away
- Crew seats: pilot, gunner, engineer, passenger. Hull points from the ship's mass, repair tool, engineers repair on board
- Owner, crew and friends are never targeted

### Stargate tie-in
With Ascension Gates (or CAP, CAP Enhanced, EAP): the ship's own gate and iris, dialling from the helm, auto-iris, jump to a gate, and Asgard beaming with the ship's transporter.

### Looks and comfort
- 12 core designs in four families: reactor, crystal, alien and military - swap a placed core's look whenever the ship is landed
- Every ship has a name, a hull number and a class (shuttle to capital ship), shown on radar, HUD and screens
- Pilot HUD in three looks and ship screens with true speed and height, in your own units (metres, feet or game units)
- One window for everything, which stays open while you fly
- Wire inputs and outputs for E2 fans

---

## Required
Nothing. StarCore works alone.
- **PowerGrid** (or Spacebuild): jumps and systems use the ship's real energy
- **Ascension Gates** (or CAP / EAP): Stargate and transporter features
- [Wiremod](https://steamcommunity.com/sharedfiles/filedetails/?id=160250458): weapons and E2 control

All Ascension Gates addons in one click: [Ascension Gates - Complete](https://steamcommunity.com/sharedfiles/filedetails/?id=3840681489)

## First flight
1. Build something with a seat. Freeze it.
2. Take the **StarCore** tool and left click your build: a core sits there, welded on.
3. Sit in the seat. Space lifts off, Ctrl goes down, WASD flies, Shift boosts.
4. Press R for the ship window: helm, jumps, weapons, systems, crew.

## Server settings
Admins find every server setting in the spawn menu under *Utilities > Admin > StarCore*: speed and prop limits, jumps on/off, jump range and charge time, hull damage, weapons, tractor beams, cloak, fleets, self-destruct. Only admins can change them.

## Privacy
StarCore collects nothing and never goes online on its own. The Workshop, GitHub and tip buttons in its menu only open a page when you click them.

---

## Fuel for the hyperdrive
> Hyperspace is free. Building the hyperdrive took a lot of coffee.

If StarCore got your ship off the ground, a small tip helps the next one take off:
[![](.github/images/donate.png)](https://www.paypal.me/soulridejourney)
A thumbs-up and a favourite help a lot too.

---

## Licence
StarCore's code is MIT. The core models are works of Sketchfab artists under CC BY 4.0 - authors, titles and links are in the game (Settings > Credits) and inside the addon (lua/starcore/sh_license.lua).
