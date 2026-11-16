--[[
StarCore - licence and credits (this file ships inside the Workshop item; gmad does not pack LICENSE/CREDITS.md)

StarCore code: MIT License

Copyright (c) 2026 StarCore authors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Third-party content: the core models (models/starcore/cores/*, materials/models/starcore/cores/*) are NOT under the
MIT License. They are works by the Sketchfab artists below, licensed under Creative Commons Attribution 4.0
(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), converted to Source models and resized for StarCore
(changes: format conversion, scale, orientation, texture size; military_case: floating lid and loose parts removed).
The list below (StarCore.Credits) is the credits table the in-game menu shows (Settings tab, "Credits").
]]

StarCore.Credits = {
	{ design = "crystal_heart",    title = "Crystal Golem Heart",       author = "DonKalishman",  url = "https://sketchfab.com/3d-models/crystal-golem-heart-53d0e4d69acc413e99d27680cddd11ac" },
	{ design = "crystal_energy",   title = "Crystal",                   author = "xNiru",         url = "https://sketchfab.com/3d-models/crystal-d963c19d8132441eb0666c513d558583" },
	{ design = "crystal_cluster",  title = "Stylized Crystal",          author = "lowlypoly",     url = "https://sketchfab.com/3d-models/stylized-crystal-0a0c75dab0844e7fa5b299d4af858bec" },
	{ design = "alien_prism",      title = "Prism of Enlightenment",    author = "duz_vr",        url = "https://sketchfab.com/3d-models/prism-of-enlightenment-25c72b016ace4f7aac72c5974437c5f2" },
	{ design = "alien_artifact",   title = "Alien Artifact",            author = "Hana_3D",       url = "https://sketchfab.com/3d-models/alien-artifact-f7a1a7a7127847899d0911e986d231e7" },
	{ design = "alien_tesseract",  title = "Advena Tesseract",          author = "distance880",   url = "https://sketchfab.com/3d-models/advena-tesseract-72a4cfb360484d9b801beabbf1909901" },
	{ design = "reactor_core",     title = "Sci Fi Energy Core 1",      author = "FilipZelinka",  url = "https://sketchfab.com/3d-models/sci-fi-energy-core-1-a5aefe7b281f46529aed2ec9d873bc52" },
	{ design = "reactor_bak",      title = "BAK-1NG Class Power Core",  author = "lorneadavis",   url = "https://sketchfab.com/3d-models/bak-1ng-class-power-core-e55ce2838c6b4ae49149586af72124fb" },
	{ design = "reactor_cell",     title = "Sci Fi Power Cell",         author = "roger.soucy",   url = "https://sketchfab.com/3d-models/sci-fi-power-cell-814eedf8b7b345948d733f4f923cbecf" },
	{ design = "military_battery", title = "Sci-fi Battery",            author = "andreas9343",   url = "https://sketchfab.com/3d-models/sci-fi-battery-3057f7bfa48e42d2aa1bf213db6ee4e0" },
	{ design = "military_cell",    title = "E-7 Portable Power Cell",   author = "uliana-",       url = "https://sketchfab.com/3d-models/e-7-portable-power-cell-low-poly-sci-fi-prop-2f184ba0cdbc4abf8f44cd672b3c3ce7" },
	{ design = "military_case",    title = "Military Case & Batteries", author = "xylvnking",     url = "https://sketchfab.com/3d-models/military-case-batteries-49550795b9814754a0fa961999cbbe25" },
}
for _, c in ipairs(StarCore.Credits) do c.license = "CC BY 4.0" end
