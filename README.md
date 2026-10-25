# PathMaker (Enhanced — Legion 7.3.5)

An enhanced fork of [PathMaker](https://www.curseforge.com/wow/addons/pathmaker) by Spaxt3, backported to run on client patch 7.3.5 (Legion, build 26124). All credit for the original addon goes to the upstream author; this fork exists to run it on clients the original never targeted.

## What changed

- **Full Legion 7.3.5 support.** `C_Map` does not exist before Battle for Azeroth 8.0.1 — added a compatibility shim in `Core/Compat.lua` (`GetBestMapForUnit`, `GetMapInfo`, `GetPlayerMapPosition`, `GetMapChildren`) backed by Legion's own legacy global map API. The shim only installs when `C_Map` is absent, so the other ~120 call sites across the addon needed no changes at all.
- Added `Compat.isLegion` detection and a dedicated `PathMaker_Legion.toc`.
- Added a third `WorldMapFrame_Update()` fallback branch (alongside the existing `RefreshAllDataProviders`/`OnMapChanged` ones) at the three places that refresh the map view, since Legion's `WorldMapFrame` has neither of the newer methods.

## Installation

Drop this folder into `Interface/AddOns/PathMaker` on a 7.3.5 client. No additional configuration needed — the addon auto-detects the client version.

---

# PathMaker (улучшенная версия — Legion 7.3.5)

Улучшенный форк [PathMaker](https://www.curseforge.com/wow/addons/pathmaker) авторства Spaxt3, портированный для работы на клиенте патча 7.3.5 (Legion, сборка 26124). Вся заслуга за оригинальный аддон принадлежит автору; этот форк существует, чтобы запустить его на клиентах, которые оригинал никогда не поддерживал.

## Что изменено

- **Полная поддержка Legion 7.3.5.** `C_Map` не существует до Battle for Azeroth 8.0.1 — добавлена прослойка совместимости в `Core/Compat.lua` (`GetBestMapForUnit`, `GetMapInfo`, `GetPlayerMapPosition`, `GetMapChildren`), опирающаяся на старый (legacy) глобальный API карты самой Legion. Прослойка подключается только если `C_Map` отсутствует, поэтому остальные ~120 мест вызова по всему аддону трогать не пришлось.
- Добавлено определение `Compat.isLegion` и отдельный файл `PathMaker_Legion.toc`.
- Добавлена третья резервная ветка `WorldMapFrame_Update()` (рядом с существующими `RefreshAllDataProviders`/`OnMapChanged`) в трёх местах обновления карты — у `WorldMapFrame` в Legion нет ни одного из новых методов.

## Установка

Поместите эту папку в `Interface/AddOns/PathMaker` на клиенте 7.3.5. Дополнительная настройка не требуется — аддон сам определяет версию клиента.
