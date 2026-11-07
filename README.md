# PathMaker (Enhanced — Legion 7.3.5)

An enhanced fork of [PathMaker](https://www.curseforge.com/wow/addons/pathmaker) by Spaxt3, backported to run on client patch 7.3.5 (Legion, build 26124). All credit for the original addon goes to the upstream author; this fork exists to run it on clients the original never targeted.

## What changed

- **Full Legion 7.3.5 support.** `C_Map` does not exist before Battle for Azeroth 8.0.1 — added a compatibility shim in `Core/Compat.lua` (`GetBestMapForUnit`, `GetMapInfo`, `GetPlayerMapPosition`, `GetMapChildren`) backed by Legion's own legacy global map API. The shim only installs when `C_Map` is absent, so the other ~120 call sites across the addon needed no changes at all.
- Added `Compat.isLegion` detection and a dedicated `PathMaker_Legion.toc`.
- Added a third `WorldMapFrame_Update()` fallback branch (alongside the existing `RefreshAllDataProviders`/`OnMapChanged` ones) at the three places that refresh the map view, since Legion's `WorldMapFrame` has neither of the newer methods.
- **Added: verified/unverified flag for bundled node imports.** Routes built from `PathMaker_Nodes`' bundled dataset had no way to tell a dataset entry apart from a node the player had actually found on this server. Nodes now carry an explicit `verified` flag: `RecordNode` (the existing gather-confirmation path, already wired to `UNIT_SPELLCAST_SUCCEEDED`) sets `verified = true` on both the promote-existing-node and insert-new-node branches, while both bundle-import paths (`PathMaker.lua`'s `InjectNode` and `Options.lua`'s `ImportExternalNodeTables`) set `verified = false` on insert. A one-time migration backfills existing saves: nodes already marked `source = "learned"` become `verified = true`, everything else `false`.
- **Added: "Verified Nodes Only" filter on the Route Generator tab.** Routes auto-generated from imported node types could silently include bundled nodes that have never been confirmed to exist on this server. A new checkbox next to Avoid Areas, when checked, drops any node without `verified == true` from the candidate points before the route gets optimized/clustered.

## Installation

Drop this folder into `Interface/AddOns/PathMaker` on a 7.3.5 client. No additional configuration needed — the addon auto-detects the client version.

---

# PathMaker (улучшенная версия — Legion 7.3.5)

Улучшенный форк [PathMaker](https://www.curseforge.com/wow/addons/pathmaker) авторства Spaxt3, портированный для работы на клиенте патча 7.3.5 (Legion, сборка 26124). Вся заслуга за оригинальный аддон принадлежит автору; этот форк существует, чтобы запустить его на клиентах, которые оригинал никогда не поддерживал.

## Что изменено

- **Полная поддержка Legion 7.3.5.** `C_Map` не существует до Battle for Azeroth 8.0.1 — добавлена прослойка совместимости в `Core/Compat.lua` (`GetBestMapForUnit`, `GetMapInfo`, `GetPlayerMapPosition`, `GetMapChildren`), опирающаяся на старый (legacy) глобальный API карты самой Legion. Прослойка подключается только если `C_Map` отсутствует, поэтому остальные ~120 мест вызова по всему аддону трогать не пришлось.
- Добавлено определение `Compat.isLegion` и отдельный файл `PathMaker_Legion.toc`.
- Добавлена третья резервная ветка `WorldMapFrame_Update()` (рядом с существующими `RefreshAllDataProviders`/`OnMapChanged`) в трёх местах обновления карты — у `WorldMapFrame` в Legion нет ни одного из новых методов.
- **Добавлено: флаг «проверено/не проверено» для импортированных узлов из набора.** Маршруты, построенные на основе встроенного набора данных `PathMaker_Nodes`, не позволяли отличить запись из набора от узла, который игрок действительно нашёл на этом сервере. Теперь узлы несут явный флаг `verified`: `RecordNode` (существующий путь подтверждения сбора, уже привязанный к `UNIT_SPELLCAST_SUCCEEDED`) устанавливает `verified = true` как при повышении существующего узла, так и при добавлении нового. Оба пути импорта из набора (`InjectNode` в `PathMaker.lua` и `ImportExternalNodeTables` в `Options.lua`) устанавливают `verified = false` при добавлении. Одноразовая миграция восстанавливает флаг для уже существующих сохранений: узлы с `source = "learned"` становятся `verified = true`, все остальные — `false`.
- **Добавлено: фильтр «Только проверенные узлы» на вкладке генератора маршрутов.** Маршруты, автоматически сгенерированные из импортированных типов узлов, могли незаметно включать узлы из набора данных, никогда не подтверждённые на этом сервере. Новый флажок рядом с «Избегать зон», если включён, убирает из кандидатов все узлы без `verified == true` перед оптимизацией/кластеризацией маршрута.

## Установка

Поместите эту папку в `Interface/AddOns/PathMaker` на клиенте 7.3.5. Дополнительная настройка не требуется — аддон сам определяет версию клиента.
