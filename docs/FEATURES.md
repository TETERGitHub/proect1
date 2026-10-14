# Feature catalogue

Generated from `src/data/Features.luau` by `python3 tools/gen_docs.py` - **145 features**: 62 `tested`, 60 `implemented`, 21 `env`, 2 `partial`.

Status meaning:

- **tested** - logic covered by automated tests
- **implemented** - implemented; only exercised against the mock Roblox layer
- **env** - depends on executor/engine behaviour; verify in the target environment
- **partial** - works with documented limitations

`tested` means an automated test in `tests/` exercises the logic and passed in the run recorded in [TESTING.md](TESTING.md). Nothing here has been run inside a real Roblox client or a specific executor.

## A. Interface & personalisation

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Theme switcher | Переключение темы | tested | `setting: ui.theme` |  |
| 2 | Accent colour | Акцентный цвет | implemented | `setting: ui.accent` |  |
| 3 | Window opacity | Прозрачность окна | implemented | `setting: ui.opacity` |  |
| 4 | Interface scale | Масштаб интерфейса | implemented | `setting: ui.scale` |  |
| 5 | Animation speed | Регулировка анимаций | implemented | `setting: ui.animSpeed` |  |
| 6 | Corner radius | Скругления | implemented | `setting: ui.cornerRadius` |  |
| 7 | Density | Плотность элементов | implemented | `setting: ui.density` |  |
| 8 | Text size | Размер текста | implemented | `setting: ui.textScale` |  |
| 9 | Interface sounds | Звуки интерфейса | env | `setting: sounds.uiClickEnabled` | No built-in Roblox sounds are used; nothing plays until you set a source on the Sounds page. |
| 10 | On-screen buttons | Экранные кнопки | implemented | `setting: ui.screenButtons` |  |
| 11 | Phone layout preset | Режим для телефона | tested | `ui/Platform:detect` |  |
| 12 | Compact mode | Компактный режим | implemented | `setting: ui.compact` |  |

## B. Window management

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Move window | Перемещение окна | implemented | `ui: Window.drag` |  |
| 2 | Resize window | Изменение размера | implemented | `ui: Window.resize` |  |
| 3 | Minimise | Сворачивание окна | implemented | `action: window.minimize` |  |
| 4 | Expand | Разворачивание окна | implemented | `action: window.expand` |  |
| 5 | Lock position | Закрепление положения | implemented | `setting: ui.lockPosition` |  |
| 6 | Save position | Сохранение координат | implemented | `ui: Window.savePosition` |  |
| 7 | Restore position | Восстановление положения | implemented | `ui: Window.restorePosition` |  |
| 8 | Tab hotkeys | Переключение вкладок клавишами | implemented | `action: window.nextTab` |  |
| 9 | Toggle visibility | Переключение видимости | implemented | `action: window.toggle` |  |
| 10 | Quick action bar | Компактная панель быстрых действий | implemented | `ui: Window.quickBar` |  |

## C. Search & navigation

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Global search | Глобальный поиск | tested | `core/Search:query` |  |
| 2 | Category filter | Поиск по категории | tested | `ui: Search.category` |  |
| 3 | Active-only filter | Фильтр активных функций | tested | `ui: Search.active` |  |
| 4 | Favourites filter | Фильтр избранного | tested | `ui: Search.favorites` |  |
| 5 | Recent features | Недавно открытые функции | tested | `core/Recents:touch` |  |
| 6 | Quick commands | Быстрые команды | tested | `core/Search:commands` |  |
| 7 | Keyboard navigation | Навигация с клавиатуры | implemented | `ui: Window.keyNav` |  |
| 8 | Hotkey list | Список горячих клавиш | implemented | `ui: Pages.hotkeys` |  |
| 9 | Search by description | Поиск по описанию | tested | `core/Search:query` |  |
| 10 | Contextual help | Контекстная справка | implemented | `setting: ui.showTooltips` |  |

## D. Configurations

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Create profile | Создание конфигурации | tested | `core/Config:create` |  |
| 2 | Rename profile | Переименование конфигурации | tested | `core/Config:rename` |  |
| 3 | Duplicate profile | Дублирование конфигурации | tested | `core/Config:duplicate` |  |
| 4 | Delete profile | Удаление конфигурации с подтверждением | tested | `core/Config:delete` |  |
| 5 | Export settings | Экспорт настроек | tested | `core/Config:exportString` |  |
| 6 | Import settings | Импорт настроек | tested | `core/Config:importString` |  |
| 7 | Format validation | Проверка формата конфигурации | tested | `core/Json:decode` |  |
| 8 | Schema migration | Миграция старых настроек | partial | `core/Version:migrate` | No legacy formats exist yet (schema 1 is the first release). |
| 9 | Reset category | Сброс отдельной категории | tested | `core/Settings:resetCategory` |  |
| 10 | Full reset | Полный сброс с подтверждением | tested | `core/Settings:resetAll` |  |

## E. Input

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Assign hotkeys | Назначение горячих клавиш | tested | `core/Input:bind` |  |
| 2 | Change hotkey | Изменение назначенной клавиши | tested | `core/Input:rebind` |  |
| 3 | Conflict check | Проверка конфликтов клавиш | tested | `core/Input:conflicts` |  |
| 4 | Unbind | Отмена назначения | tested | `core/Input:clear` |  |
| 5 | Hotkeys master switch | Включение и отключение обработки ввода | tested | `setting: input.enabled` |  |
| 6 | Keyboard support | Поддержка клавиатуры | implemented | `core/Input:connect` |  |
| 7 | Mouse support | Поддержка мыши | implemented | `core/Input:connect` |  |
| 8 | Typing guard | Управление фокусом | tested | `setting: input.ignoreTyping` |  |
| 9 | Focus-loss handling | Обработка потери фокуса | tested | `core/Input:focusLost` |  |
| 10 | Input restore on close | Восстановление ввода после закрытия окна | tested | `core/Input:cancelCapture` |  |

## F. Visual tools

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Custom crosshair | Настраиваемый прицел | implemented | `setting: crosshair.enabled` |  |
| 2 | Crosshair size | Регулировка размера прицела | implemented | `setting: crosshair.size` |  |
| 3 | Line thickness | Настройка толщины линий | implemented | `setting: crosshair.thickness` |  |
| 4 | Crosshair colour | Выбор цвета прицела | implemented | `setting: crosshair.color` |  |
| 5 | Crosshair opacity | Настройка прозрачности прицела | implemented | `setting: crosshair.opacity` |  |
| 6 | Centre dot | Центральная точка | implemented | `setting: crosshair.centerDot` |  |
| 7 | Dynamic spread | Настройка динамического прицела | env | `setting: crosshair.dynamic` | Needs a Humanoid on the local character. |
| 8 | Own character opacity | Настройка отображения собственного персонажа | env | `setting: camera.ownOpacity` | The game's camera scripts may also write LocalTransparencyModifier. |
| 9 | Local invisibility | Локальная невидимость | implemented | `setting: ghost.enabled` |  |
| 10 | Colour filter presets | Доступные локальные визуальные эффекты | implemented | `setting: lighting.filter` |  |
| 11 | Bloom effect | Настройка визуальных эффектов камеры | implemented | `setting: lighting.bloomEnabled` |  |

## G. Graphics & environment

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Brightness | Настройка яркости | env | `setting: lighting.brightness` | The game may rewrite Lighting; the hub re-applies at 2 Hz. |
| 2 | Colour correction | Контроль цветокоррекции | implemented | `setting: lighting.colorEnabled` |  |
| 3 | Saturation | Настройка насыщенности | implemented | `setting: lighting.saturation` |  |
| 4 | Contrast | Настройка контраста | implemented | `setting: lighting.contrast` |  |
| 5 | Time-of-day preset | Выбор доступного оформления неба | env | `setting: lighting.timePreset` | Uses Lighting properties only; no custom sky assets are loaded. |
| 6 | Decorative effects | Управление декоративными эффектами | implemented | `setting: ui.decor` |  |
| 7 | Hit particles | Настройка частиц в собственном тестовом окружении | implemented | `setting: training.particles` |  |
| 8 | Blur | Настройка размытия | implemented | `setting: lighting.blurEnabled` |  |
| 9 | Colour tint | Настройка цветовых фильтров | implemented | `setting: lighting.tint` |  |
| 10 | Reset graphics | Сброс графических настроек | implemented | `action: lighting.reset` |  |

## H. Camera

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Mouse sensitivity | Настройка чувствительности камеры | env | `setting: camera.sensitivity` | Writable from LocalScripts per Roblox docs; executors normally allow it, but some games re-set it. |
| 2 | Zoom speed | Настройка скорости прокрутки зума | env | `setting: camera.zoomSpeed` | Takes over zoom by driving Min/MaxZoomDistance; game camera scripts may interfere. |
| 3 | Remember zoom | Сохранение предпочтительного зума | env | `setting: camera.rememberZoom` | Relies on Player.CameraMinZoomDistance/MaxZoomDistance being writable on the local player. |
| 4 | Camera mode | Переключение доступных режимов камеры | env | `setting: camera.mode` | Writes Player.CameraMode; the game can restrict it. |
| 5 | Head bob intensity | Настройка интенсивности тряски | env | `setting: camera.bobIntensity` | Other scripts that write CameraOffset (some game cameras) can fight this. |
| 6 | Disable camera effects | Отключение необязательных эффектов камеры | implemented | `setting: camera.disableEffects` |  |
| 7 | Smoothing | Настройка сглаживания | partial | `setting: camera.smoothing` | Does not smooth mouse look; Roblox does not expose that. |
| 8 | Field of view | Регулировка поля зрения там, где это разрешено | env | `setting: camera.fov` | The game may reset FOV; the hub re-applies it. |
| 9 | Crosshair position | Настройка положения прицела на экране | implemented | `setting: crosshair.offsetX` |  |
| 10 | Reset camera | Сброс параметров камеры | implemented | `action: camera.reset` |  |

## I. Performance

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | FPS indicator | Индикатор FPS | implemented | `setting: ui.showFpsBadge` |  |
| 2 | Network ping | Индикатор задержки сети | env | `ui: Perf.ping` | Documented Roblox API; shows n/a if the call is unavailable. |
| 3 | Module timings | Мониторинг времени обновления модулей | tested | `core/Perf:timings` |  |
| 4 | Visual update rate | Контроль частоты визуальных обновлений | tested | `setting: perf.visualHz` |  |
| 5 | Decorative object limit | Ограничение количества декоративных элементов | tested | `setting: perf.maxDecor` |  |
| 6 | UI object reuse | Переиспользование UI-объектов | tested | `core/Pool:Acquire` |  |
| 7 | Temporary object cleanup | Очистка временных объектов | implemented | `action: training.clear` |  |
| 8 | Connection monitor | Контроль подключённых событий | tested | `core/Maid:stats` |  |
| 9 | Long operation detection | Диагностика длительных операций | tested | `setting: perf.warnMs` |  |
| 10 | Low load profile | Профиль низкой нагрузки | tested | `setting: perf.lowProfile` |  |

## J. Reliability

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Error log | Журнал ошибок | tested | `core/Logger:entries` |  |
| 2 | Diagnostic report export | Экспорт диагностического отчёта | tested | `action: diagnostics.export` |  |
| 3 | Dependency check | Проверка обязательных зависимостей | tested | `core/Core:checkDependencies` |  |
| 4 | Re-initialisation detection | Обнаружение повторной инициализации | tested | `core/Core:boot` |  |
| 5 | Safe shutdown | Безопасное выключение модулей | tested | `action: hub.unload` |  |
| 6 | Event cleanup | Очистка событий при закрытии | tested | `core/Cleanup:run` |  |
| 7 | Value validation | Проверка значений настроек | tested | `core/Settings:validateMap` |  |
| 8 | Module recovery | Восстановление после ошибки отдельного модуля | tested | `core/Core:restart` |  |
| 9 | Version info | Информация о версиях | implemented | `ui: Pages.about` |  |
| 10 | Help & documentation | Экран справки и документации | implemented | `ui: Pages.help` |  |

## K. Extra tools

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Active modules list | Список активных модулей | tested | `core/Core:status` |  |
| 2 | Favourites panel | Настраиваемая панель избранного | tested | `core/Recents:toggleFavorite` |  |
| 3 | Session timer | Счётчик времени сессии | tested | `features/Tools:sessionSeconds` |  |
| 4 | Local notes | Локальные заметки пользователя | tested | `features/Tools:setNotes` |  |
| 5 | Timers & stopwatch | Таймеры и секундомер | tested | `features/Tools:addTimer` |  |
| 6 | Settings change history | История изменений настроек | tested | `core/Settings:history` |  |
| 7 | Compare configurations | Сравнение двух конфигураций | tested | `core/Config:diff` |  |
| 8 | Setting conflict finder | Поиск конфликтующих параметров | tested | `core/Settings:conflicts` |  |
| 9 | Reset module | Сброс настроек конкретного модуля | tested | `core/Settings:resetModule` |  |
| 10 | Config integrity check | Автоматическая проверка целостности конфигурации | tested | `core/Config:checkIntegrity` |  |

## L. Local training range

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Training range | Тренировочный полигон | implemented | `setting: training.enabled` |  |
| 2 | Target modes | Режимы мишеней | implemented | `setting: training.mode` |  |
| 3 | Demo guide | Демонстрационное наведение | implemented | `setting: training.demoGuide` |  |
| 4 | Accuracy stats | Статистика точности | implemented | `features/Training:getStats` |  |
| 5 | Physics stand | Физический стенд | implemented | `action: training.launch` |  |
| 6 | Hitbox lab | Лаборатория хитбокса | implemented | `action: training.spawnLab` |  |
| 7 | Hitbox motion modes | Режимы движения хитбокса | tested | `features/HitboxMath:offset` |  |
| 8 | Geometry intersection checks | Проверка пересечений | tested | `features/Geometry:rayBox` |  |
| 9 | Physical probe projectiles | Пробные снаряды | implemented | `action: training.fireProbe` |  |
| 10 | Select Aim (test targets) | Выбор цели (тестовые мишени) | implemented | `setting: selectaim.enabled` |  |
| 11 | Target selection rules | Правила выбора цели | tested | `features/SelectLogic:evaluate` |  |
| 12 | Target switching | Переключение целей | tested | `features/SelectLogic:cycle` |  |
| 13 | Movement prediction | Прогноз положения мишени | tested | `features/SelectLogic:intercept` |  |
| 14 | Select / lock / reset / switch keys | Клавиши выбора цели | implemented | `action: selectaim.next` |  |
| 15 | Reset dummy | Сброс стенда | implemented | `action: training.resetDummy` |  |

## M. Defence

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Anti-fling guard | Анти-флинг | implemented | `setting: antifling.enabled` |  |
| 2 | Ghost collisions | Коллизии-призраки | env | `setting: antifling.noCollide` | Relies on the client simulating your character; a game that re-enables collisions each frame can undo it. |
| 3 | Fling detection logic | Логика обнаружения флинга | tested | `features/AntiFlingLogic:evaluate` |  |

## N. Customisation

| # | Feature | RU | Status | Implementation | Notes |
|---|---|---|---|---|---|
| 1 | Custom gun | Свой пистолет | env | `features/CustomLogic:apply` | Needs your gun/knife to be a Tool with a Handle named as set on the page; a game that rebuilds its tools differently needs the tool name adjusted. Unverified in a real client. |
| 2 | Custom knife | Свой нож | env | `features/CustomLogic:apply` | Needs your gun/knife to be a Tool with a Handle named as set on the page; a game that rebuilds its tools differently needs the tool name adjusted. Unverified in a real client. |
| 3 | Custom character | Свой персонаж | env | `features/CustomLogic:apply` | Costumes are static Part models welded to your root part: they do not animate with your limbs. Unverified in a real client. |
| 4 | Model preview | Предпросмотр модели | implemented | `features/Cosmetics:buildPreview` |  |
| 5 | Per-page presets | Пресеты по страницам | tested | `features/CustomLogic:savePreset` |  |
| 6 | Look validation | Проверка параметров вида | tested | `features/CustomLogic:normalize` |  |
| 7 | Murderer kill sound | Звук убийства: Murderer | env | `features/KillSounds:playEvent` | A kill is confirmed on your client (another player's death soon after your own knife use, nearby); a client cannot prove who killed whom. Sounds are only those you add. |
| 8 | Sheriff kill sound | Звук убийства: Sheriff | env | `features/KillSounds:playEvent` | A kill is confirmed on your client (another player's death soon after your own gun use); a client cannot prove who killed whom. Sounds are only those you add. |
| 9 | Confirmed-kill events | Подтверждённые убийства | tested | `features/KillEvents:report` |  |
| 10 | Imported real meshes | Импорт настоящих мешей | env | `features/MeshModels:build` | Needs getcustomasset (or an asset id) and an executor that may set MeshId; unverified in a real client. The hub ships no third-party meshes. |
| 11 | Bundled sounds | Встроенные звуки | tested | `features/SoundPack:ensure` |  |
| 12 | Silence the game's own sounds | Заглушение звуков игры | env | `features/GameAudio:rescan` | Which sounds count is decided by keywords; the defaults are guesses about the game. Use Learn to find the real names. Unverified in a real client. |
| 13 | Learn the game's sounds | Узнать звуки игры | tested | `features/GameAudio:learn` |  |
| 14 | Round-end song | Песня конца раунда | env | `features/GameAudio:songPlay` | Round-end detection relies on the sound keywords. Unverified in a real client. |

## Settings schema (261 keys)

| Key | Type | Default | Range / options | Module |
|---|---|---|---|---|
| `ui.theme` | enum | iOS | iOS, iOS Light, Midnight, Obsidian, Ocean, Rose, Forest, HighContrast | Interface |
| `ui.useThemeAccent` | bool | true |  | Interface |
| `ui.accent` | color | rgb(110,120,255) |  | Interface |
| `ui.opacity` | number | 0.96 | 0.5..1 step 0.01 | Interface |
| `ui.glass` | number | 0.7 | 0..1 step 0.05 | Interface |
| `ui.reduceEffects` | bool | false |  | Interface |
| `ui.scale` | number | 1 | 0.7..1.5 step 0.05 | Interface |
| `ui.animSpeed` | number | 1 | 0..2 step 0.1 | Interface |
| `ui.cornerRadius` | number | 8 | 0..16 step 1 | Interface |
| `ui.density` | enum | Normal | Compact, Normal, Comfortable | Interface |
| `ui.textScale` | number | 1 | 0.8..1.4 step 0.05 | Interface |
| `ui.compact` | bool | false |  | Interface |
| `ui.lockPosition` | bool | false |  | Interface |
| `ui.showTooltips` | bool | true |  | Interface |
| `ui.decor` | bool | true |  | Interface |
| `ui.language` | enum | ru | en, ru | Interface |
| `ui.notifications` | bool | true |  | Interface |
| `ui.notifyDuration` | number | 4 | 2..12 step 1 | Interface |
| `ui.showLauncher` | bool | true |  | Interface |
| `ui.screenButtons` | bool | false |  | Interface |
| `ui.screenButtonSize` | number | 46 | 34..70 step 2 | Interface |
| `ui.screenButtonOpacity` | number | 0.85 | 0.3..1 step 0.05 | Interface |
| `ui.showFpsBadge` | bool | true |  | Interface |
| `state.posX` | number | -1 | -1..8000 step 1 | State |
| `state.posY` | number | -1 | -1..8000 step 1 | State |
| `state.width` | number | 820 | 460..1600 step 1 | State |
| `state.height` | number | 560 | 320..1200 step 1 | State |
| `state.minimized` | bool | false |  | State |
| `state.page` | string | dashboard |  | State |
| `state.favorites` | strlist | {} |  | State |
| `state.recent` | strlist | {} |  | State |
| `state.platform` | string |  |  | State |
| `state.buttonPos` | strlist | {} |  | State |
| `state.activeProfile` | string | Default |  | State |
| `crosshair.enabled` | bool | false |  | Crosshair |
| `crosshair.style` | enum | Cross | Cross, Dot, Circle, CrossCircle | Crosshair |
| `crosshair.size` | number | 10 | 2..60 step 1 | Crosshair |
| `crosshair.thickness` | number | 2 | 1..8 step 1 | Crosshair |
| `crosshair.gap` | number | 4 | 0..30 step 1 | Crosshair |
| `crosshair.color` | color | rgb(255,255,255) |  | Crosshair |
| `crosshair.opacity` | number | 1 | 0..1 step 0.05 | Crosshair |
| `crosshair.centerDot` | bool | false |  | Crosshair |
| `crosshair.dotSize` | number | 2 | 1..8 step 1 | Crosshair |
| `crosshair.outline` | bool | true |  | Crosshair |
| `crosshair.dynamic` | bool | false |  | Crosshair |
| `crosshair.dynamicAmount` | number | 8 | 0..30 step 1 | Crosshair |
| `crosshair.offsetX` | number | 0 | -200..200 step 1 | Crosshair |
| `crosshair.offsetY` | number | 0 | -200..200 step 1 | Crosshair |
| `crosshair.hideCursor` | bool | false |  | Crosshair |
| `camera.sensitivityEnabled` | bool | false |  | Camera |
| `camera.sensitivity` | number | 1 | 0.1..3 step 0.05 | Camera |
| `camera.zoomEnabled` | bool | false |  | Camera |
| `camera.zoomSpeed` | number | 1 | 0.25..4 step 0.05 | Camera |
| `camera.minZoom` | number | 0.5 | 0.5..20 step 0.5 | Camera |
| `camera.maxZoom` | number | 128 | 5..500 step 1 | Camera |
| `camera.rememberZoom` | bool | false |  | Camera |
| `camera.preferredZoom` | number | 12 | 0.5..500 step 0.5 | Camera |
| `camera.mode` | enum | Default | Default, FirstPerson, ThirdPerson | Camera |
| `camera.fovEnabled` | bool | false |  | Camera |
| `camera.fov` | number | 70 | 30..120 step 1 | Camera |
| `camera.smoothing` | number | 0.35 | 0..0.95 step 0.05 | Camera |
| `camera.bobIntensity` | number | 0 | 0..1 step 0.05 | Camera |
| `camera.ownOpacity` | number | 1 | 0..1 step 0.05 | Camera |
| `camera.disableEffects` | bool | false |  | Camera |
| `lighting.brightnessEnabled` | bool | false |  | Lighting |
| `lighting.brightness` | number | 2 | 0..5 step 0.1 | Lighting |
| `lighting.timePreset` | enum | Game | Game, Dawn, Noon, Dusk, Night | Lighting |
| `lighting.colorEnabled` | bool | false |  | Lighting |
| `lighting.saturation` | number | 0 | -1..2 step 0.05 | Lighting |
| `lighting.contrast` | number | 0 | -1..1 step 0.05 | Lighting |
| `lighting.exposure` | number | 0 | -0.5..0.5 step 0.05 | Lighting |
| `lighting.filter` | enum | None | None, Warm, Cool, Mono, Sepia, Vivid | Lighting |
| `lighting.tint` | color | rgb(255,255,255) |  | Lighting |
| `lighting.blurEnabled` | bool | false |  | Lighting |
| `lighting.blurSize` | number | 6 | 0..24 step 1 | Lighting |
| `lighting.bloomEnabled` | bool | false |  | Lighting |
| `lighting.bloomIntensity` | number | 1 | 0..3 step 0.1 | Lighting |
| `lighting.bloomSize` | number | 24 | 0..56 step 1 | Lighting |
| `lighting.bloomThreshold` | number | 2 | 0..4 step 0.1 | Lighting |
| `training.enabled` | bool | false |  | Training |
| `training.mode` | enum | Strafing | Static, Strafing, Popup | Training |
| `training.count` | number | 4 | 1..12 step 1 | Training |
| `training.targetSize` | number | 3 | 1..8 step 0.5 | Training |
| `training.speed` | number | 8 | 0..30 step 1 | Training |
| `training.distance` | number | 35 | 15..80 step 1 | Training |
| `training.targetColor` | color | rgb(255,90,90) |  | Training |
| `training.particles` | bool | true |  | Training |
| `training.demoGuide` | bool | false |  | Training |
| `training.hbShape` | enum | Sphere | Sphere, Box | Training |
| `training.hbSize` | number | 3 | 1..8 step 0.5 | Training |
| `training.hbOffsetX` | number | 0 | -6..6 step 0.5 | Training |
| `training.hbOffsetY` | number | 0 | -6..6 step 0.5 | Training |
| `training.hbOffsetZ` | number | 0 | -6..6 step 0.5 | Training |
| `training.hbShow` | bool | true |  | Training |
| `training.hbCollide` | bool | false |  | Training |
| `training.hbMode` | enum | Orbit | Off, Orbit, Jitter, Blink | Training |
| `training.orbitRadius` | number | 8 | 2..25 step 1 | Training |
| `training.orbitSpeed` | number | 8 | 1..30 step 1 | Training |
| `training.orbitTilt` | number | 0.3 | 0..1 step 0.05 | Training |
| `training.jitterAmplitude` | number | 3 | 0.5..10 step 0.5 | Training |
| `training.jitterSpeed` | number | 8 | 1..30 step 1 | Training |
| `training.blinkRange` | number | 10 | 2..25 step 1 | Training |
| `training.blinkInterval` | number | 0.8 | 0.2..3 step 0.1 | Training |
| `training.physImpulse` | number | 120 | 0..500 step 5 | Training |
| `training.physMaxSpeed` | number | 80 | 10..200 step 5 | Training |
| `training.physDirection` | enum | Forward | Up, Forward, Back, Left, Right | Training |
| `selectaim.enabled` | bool | false |  | SelectAim |
| `selectaim.mode` | enum | Crosshair | Crosshair, Distance, Manual | SelectAim |
| `selectaim.lock` | bool | false |  | SelectAim |
| `selectaim.fov` | number | 150 | 20..600 step 5 | SelectAim |
| `selectaim.showFov` | bool | true |  | SelectAim |
| `selectaim.highlight` | bool | true |  | SelectAim |
| `selectaim.visibilityCheck` | bool | true |  | SelectAim |
| `selectaim.autoAcquire` | bool | true |  | SelectAim |
| `selectaim.prediction` | bool | false |  | SelectAim |
| `selectaim.projectileSpeed` | number | 200 | 50..500 step 10 | SelectAim |
| `selectaim.leadMax` | number | 0.6 | 0.05..1.5 step 0.05 | SelectAim |
| `selectaim.highlightColor` | color | rgb(255,214,10) |  | SelectAim |
| `ghost.enabled` | bool | false |  | Ghost |
| `ghost.opacity` | number | 0.15 | 0..1 step 0.05 | Ghost |
| `ghost.fadeTime` | number | 0.35 | 0..2 step 0.05 | Ghost |
| `ghost.includeAccessories` | bool | true |  | Ghost |
| `ghost.includeFace` | bool | true |  | Ghost |
| `ghost.includeTools` | bool | false |  | Ghost |
| `ghost.hideName` | bool | true |  | Ghost |
| `ghost.restoreOnDeath` | bool | true |  | Ghost |
| `antifling.enabled` | bool | false |  | AntiFling |
| `antifling.maxSpeed` | number | 120 | 60..300 step 10 | AntiFling |
| `antifling.angularLimit` | number | 60 | 20..200 step 5 | AntiFling |
| `antifling.noCollide` | bool | true |  | AntiFling |
| `antifling.notify` | bool | true |  | AntiFling |
| `perf.lowProfile` | bool | false |  | Performance |
| `perf.autoLow` | bool | false |  | Performance |
| `perf.autoLowFps` | number | 25 | 15..60 step 1 | Performance |
| `perf.visualHz` | number | 30 | 10..60 step 1 | Performance |
| `perf.maxDecor` | number | 12 | 1..24 step 1 | Performance |
| `perf.warnMs` | number | 8 | 2..50 step 1 | Performance |
| `tools.notesAutosave` | bool | true |  | Tools |
| `tools.timerSound` | bool | true |  | Tools |
| `input.enabled` | bool | true |  | Input |
| `input.ignoreTyping` | bool | true |  | Input |
| `cosmetics.gunEnabled` | bool | false |  | Cosmetics |
| `cosmetics.gunSource` | string | proc:neon |  | Cosmetics |
| `cosmetics.gunTool` | string | Gun |  | Cosmetics |
| `cosmetics.gunScale` | number | 1 | 0.2..4 step 0.05 | Cosmetics |
| `cosmetics.gunOffsetX` | number | 0 | -3..3 step 0.05 | Cosmetics |
| `cosmetics.gunOffsetY` | number | 0 | -3..3 step 0.05 | Cosmetics |
| `cosmetics.gunOffsetZ` | number | 0 | -3..3 step 0.05 | Cosmetics |
| `cosmetics.gunRotY` | number | 0 | -180..180 step 5 | Cosmetics |
| `cosmetics.knifeEnabled` | bool | false |  | Cosmetics |
| `cosmetics.knifeSource` | string | proc:blade |  | Cosmetics |
| `cosmetics.knifeTool` | string | Knife |  | Cosmetics |
| `cosmetics.knifeScale` | number | 1 | 0.2..4 step 0.05 | Cosmetics |
| `cosmetics.knifeOffsetX` | number | 0 | -3..3 step 0.05 | Cosmetics |
| `cosmetics.knifeOffsetY` | number | 0 | -3..3 step 0.05 | Cosmetics |
| `cosmetics.knifeOffsetZ` | number | 0 | -3..3 step 0.05 | Cosmetics |
| `cosmetics.knifeRotY` | number | 0 | -180..180 step 5 | Cosmetics |
| `cosmetics.charEnabled` | bool | false |  | Cosmetics |
| `cosmetics.charSource` | string | proc:halo |  | Cosmetics |
| `cosmetics.charAttach` | enum | Head | Head, Torso, RootPart | Cosmetics |
| `cosmetics.charScale` | number | 1 | 0.2..4 step 0.05 | Cosmetics |
| `cosmetics.charOffsetY` | number | 1.2 | -5..5 step 0.1 | Cosmetics |
| `cosmetics.bodyColorEnabled` | bool | false |  | Cosmetics |
| `cosmetics.bodyColor` | color | rgb(120,90,255) |  | Cosmetics |
| `cosmetics.neon` | bool | false |  | Cosmetics |
| `music.playlist` | strlist | {} |  | Music |
| `music.volume` | number | 0.5 | 0..1 step 0.05 | Music |
| `music.loop` | enum | All | Off, One, All | Music |
| `music.shuffle` | bool | false |  | Music |
| `music.speed` | number | 1 | 0.5..2 step 0.05 | Music |
| `music.autoplay` | bool | false |  | Music |
| `music.index` | number | 1 | 1..40 step 1 | Music |
| `sounds.master` | number | 1 | 0..1 step 0.05 | Sounds |
| `sounds.gunShotEnabled` | bool | false |  | Sounds |
| `sounds.gunShotSource` | string |  |  | Sounds |
| `sounds.gunShotVolume` | number | 0.8 | 0..1 step 0.05 | Sounds |
| `sounds.gunShotPitch` | number | 1 | 0.5..2 step 0.05 | Sounds |
| `sounds.knifeSwingEnabled` | bool | false |  | Sounds |
| `sounds.knifeSwingSource` | string |  |  | Sounds |
| `sounds.knifeSwingVolume` | number | 0.8 | 0..1 step 0.05 | Sounds |
| `sounds.knifeSwingPitch` | number | 1 | 0.5..2 step 0.05 | Sounds |
| `sounds.hitEnabled` | bool | false |  | Sounds |
| `sounds.hitSource` | string |  |  | Sounds |
| `sounds.hitVolume` | number | 0.8 | 0..1 step 0.05 | Sounds |
| `sounds.hitPitch` | number | 1 | 0.5..2 step 0.05 | Sounds |
| `sounds.killEnabled` | bool | false |  | Sounds |
| `sounds.killSource` | string |  |  | Sounds |
| `sounds.killVolume` | number | 0.8 | 0..1 step 0.05 | Sounds |
| `sounds.killPitch` | number | 1 | 0.5..2 step 0.05 | Sounds |
| `sounds.uiClickEnabled` | bool | false |  | Sounds |
| `sounds.uiClickSource` | string |  |  | Sounds |
| `sounds.uiClickVolume` | number | 0.8 | 0..1 step 0.05 | Sounds |
| `sounds.uiClickPitch` | number | 1 | 0.5..2 step 0.05 | Sounds |
| `custom.gunEnabled` | bool | false |  | CustomGun |
| `custom.gunStyle` | string | Custom |  | CustomGun |
| `custom.gunPrimary` | color | rgb(150,154,162) |  | CustomGun |
| `custom.gunSecondary` | color | rgb(112,70,40) |  | CustomGun |
| `custom.gunGrip` | color | rgb(112,70,40) |  | CustomGun |
| `custom.gunDetail` | color | rgb(196,154,72) |  | CustomGun |
| `custom.gunGlow` | color | rgb(255,214,120) |  | CustomGun |
| `custom.gunMaterial` | enum | Metal | SmoothPlastic, Plastic, Metal, DiamondPlate, Foil, Glass, Marble, Slate, Wood | CustomGun |
| `custom.gunGlowAmount` | number | 0.2 | 0..1 step 0.05 | CustomGun |
| `custom.gunDecor` | number | 0 | 0..0.6 step 0.05 | CustomGun |
| `custom.gunEffects` | bool | true |  | CustomGun |
| `custom.gunApplied` | string |  |  | CustomGun |
| `custom.gunPresets` | string |  |  | CustomGun |
| `custom.gunModel` | string | revolver |  | CustomGun |
| `custom.knifeEnabled` | bool | false |  | CustomKnife |
| `custom.knifeStyle` | string | Custom |  | CustomKnife |
| `custom.knifePrimary` | color | rgb(196,202,212) |  | CustomKnife |
| `custom.knifeSecondary` | color | rgb(120,126,138) |  | CustomKnife |
| `custom.knifeGrip` | color | rgb(98,62,36) |  | CustomKnife |
| `custom.knifeDetail` | color | rgb(196,154,72) |  | CustomKnife |
| `custom.knifeGlow` | color | rgb(255,214,120) |  | CustomKnife |
| `custom.knifeMaterial` | enum | Metal | SmoothPlastic, Plastic, Metal, DiamondPlate, Foil, Glass, Marble, Slate, Wood | CustomKnife |
| `custom.knifeGlowAmount` | number | 0.2 | 0..1 step 0.05 | CustomKnife |
| `custom.knifeDecor` | number | 0 | 0..0.6 step 0.05 | CustomKnife |
| `custom.knifeEffects` | bool | true |  | CustomKnife |
| `custom.knifeApplied` | string |  |  | CustomKnife |
| `custom.knifePresets` | string |  |  | CustomKnife |
| `custom.knifeModel` | string | classic |  | CustomKnife |
| `custom.charEnabled` | bool | false |  | CustomChar |
| `custom.charStyle` | string | Custom |  | CustomChar |
| `custom.charPrimary` | color | rgb(255,255,255) |  | CustomChar |
| `custom.charSecondary` | color | rgb(210,214,224) |  | CustomChar |
| `custom.charGrip` | color | rgb(40,40,46) |  | CustomChar |
| `custom.charDetail` | color | rgb(255,224,120) |  | CustomChar |
| `custom.charGlow` | color | rgb(255,232,140) |  | CustomChar |
| `custom.charMaterial` | enum | SmoothPlastic | SmoothPlastic, Plastic, Metal, DiamondPlate, Foil, Glass, Marble, Slate, Wood | CustomChar |
| `custom.charGlowAmount` | number | 0.5 | 0..1 step 0.05 | CustomChar |
| `custom.charDecor` | number | 0 | 0..0.6 step 0.05 | CustomChar |
| `custom.charEffects` | bool | true |  | CustomChar |
| `custom.charApplied` | string |  |  | CustomChar |
| `custom.charPresets` | string |  |  | CustomChar |
| `custom.charCostume` | string |  |  | CustomChar |
| `custom.charHead` | string |  |  | CustomChar |
| `custom.charBack` | string |  |  | CustomChar |
| `custom.charAura` | string |  |  | CustomChar |
| `ksound.murdererEnabled` | bool | false |  | MurdererKillSound |
| `ksound.murdererPick` | string |  |  | MurdererKillSound |
| `ksound.murdererSource` | string |  |  | MurdererKillSound |
| `ksound.murdererVolume` | number | 0.8 | 0..1 step 0.05 | MurdererKillSound |
| `ksound.murdererLibrary` | string |  |  | MurdererKillSound |
| `ksound.sheriffEnabled` | bool | false |  | SheriffKillSound |
| `ksound.sheriffPick` | string |  |  | SheriffKillSound |
| `ksound.sheriffSource` | string |  |  | SheriffKillSound |
| `ksound.sheriffVolume` | number | 0.8 | 0..1 step 0.05 | SheriffKillSound |
| `ksound.sheriffLibrary` | string |  |  | SheriffKillSound |
| `gameaudio.muteKill` | bool | true |  | GameAudio |
| `gameaudio.muteShot` | bool | false |  | GameAudio |
| `gameaudio.muteReload` | bool | false |  | GameAudio |
| `gameaudio.muteKnife` | bool | false |  | GameAudio |
| `gameaudio.kwKill` | string | kill,death,elimin |  | GameAudio |
| `gameaudio.kwShot` | string | shoot,shot,fire,gunshot |  | GameAudio |
| `gameaudio.kwReload` | string | reload |  | GameAudio |
| `gameaudio.kwKnife` | string | knife,slash,swing,stab |  | GameAudio |
| `gameaudio.kwWin` | string | win,victory,defeat,roundend,gameover |  | GameAudio |
| `gameaudio.songEnabled` | bool | false |  | GameAudio |
| `gameaudio.songSource` | string |  |  | GameAudio |
| `gameaudio.songVolume` | number | 0.8 | 0..1 step 0.05 | GameAudio |
| `gameaudio.muteWin` | bool | true |  | GameAudio |
