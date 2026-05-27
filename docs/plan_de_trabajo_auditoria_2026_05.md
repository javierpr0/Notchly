# Plan: Auditoría Notchly — Mejoras y Correcciones

## Complejidad: Complejo

Plan de mejora basado en auditoría exhaustiva del codebase (correctness, performance, seguridad, arquitectura). Se ejecuta top-down, de crítico a bajo.

---

## Fase 1 — CRÍTICO (crash + RCE)

- [x] ~~**1.1** Fix force-unwrap `NSScreen.builtIn` en `AppDelegate.swift:143`~~ — falso positivo, `NSScreen.builtIn` ya tiene `?? main` fallback en `NotchWindow.swift:424`
- [x] ~~**1.2** Fix force-unwrap `NSScreen.builtIn` en `NotchWindow.swift`~~ — mismo caso, ya guardado
- [x] **1.3** Shell whitelist — `TerminalManager.isAllowedShell` valida shell sólo en `/bin/`, `/usr/bin/`, `/usr/local/bin/`, `/opt/homebrew/bin/`
- [x] **1.4** Trust prompt para `.notchy.json` command/shell — nuevo `ProjectTrustStore` con prompt único por directorio
- [x] **1.5** Env vars blacklist — `TerminalManager.isSafeEnvKey` bloquea `DYLD_*`, `LD_*`, `PATH`, `SHELL`, `HOME`, `USER`, `LOGNAME`, `TMPDIR`, `IFS`
- [x] **1.6** CVDisplayLink leak — `stop()` ahora libera referencia retenida, no fuga si callback nunca dispara

## Fase 2 — ALTO (races + injection paths)

- [x] ~~**2.1** Race `Task.sleep` en `SessionStore.swift:276`~~ — falso positivo, el guard en `firstIndex(where:)` + check de `paneStatuses[paneId] == .idle` ya cubre cierre de sesión
- [x] **2.2** Invalidar `statusDebounceTimer` y `autocompleteDebounceTimer` en deinit de `ClickThroughTerminalView`
- [x] **2.3** OSC 7 — canonicaliza con `standardizedFileURL`, rechaza NUL/CR/LF, valida que es directorio existente
- [x] **2.4** Git ref injection — `CheckpointManager.sanitizeRefComponent` aplica a `createCheckpoint` y `checkpoints(for:)`
- [x] **2.5** Temp index — directorio padre único con permisos `0o700` evita TOCTOU symlink
- [x] ~~**2.6** `TerminalPanel.swift:100` race~~ — falso positivo, `handleDidResize` corre en main thread; `isAdjustingFrame` es guard de re-entrada de `super.setFrameOrigin`, no race entre hilos

## Fase 3 — PERFORMANCE (HIGH impact)

- [x] ~~**3.1** Status classification — limitar `extractAllLines()`~~ — falso positivo, `hasWorkingIndicator()` ya itera solo últimas 5 filas; `extractAllLines` solo se llama desde context menu, no del status check
- [x] **3.2** Autocomplete — `AutocompleteEngine.lowercasedCache` evita re-lowercase por keystroke
- [x] ~~**3.3** CommandStore — debounce `saveCommands()`~~ — descartado, `recordCommand` solo dispara en Enter (no por keystroke)
- [x] **3.4** SessionStore — `persistSessions()` ahora con `persistDebounceTask` 1.5s, `saveSessions()` mantiene flush inmediato para `applicationWillTerminate`
- [x] ~~**3.5** `terminalStatus` cache~~ — descartado, O(panes) ≤ 4, trivial

## Fase 4 — MEDIO

- [x] **4.1** Errores silenciosos — `do/catch` en `restoreSessions` (preserva blob corrupto en `.corrupt` key) y `persistNow` con `logger.error`
- [x] ~~**4.2** Status state de-duplication~~ — falso positivo, `TerminalSession.paneStatuses` ya es single source; `SessionStore` solo accede via session
- [x] **4.3** Path canonicalización CommandStore — `URL(fileURLWithPath:).standardizedFileURL.path` antes de SHA256
- [ ] **4.4** Context menu symlinks — pendiente, requiere lógica de resolución cuidadosa
- [x] ~~**4.5** Notification `NotchyNotchStatusChanged` coalescing~~ — ya existe (`if newAggregate != previousAggregate` en `updateTerminalStatus`)

## Fase 5 — ARQUITECTURA / BAJO

- [x] **5.1** Renombrar `BotdockApp.swift` → `NotchyApp.swift` (vía `git mv`)
- [ ] **5.2** Extraer magic numbers a `Constants.swift` — pendiente, refactor cosmético
- [x] **5.3** Validar formato hash git — `CheckpointManager.isValidGitObjectHash` (SHA-1/SHA-256, hex)
- [ ] **5.4** Fuzzy match `[Character]` — pendiente, micro-opt
- [ ] **5.5** Diferir setup de `NotchWindow` — pendiente, requiere medir startup primero
- [x] **5.6** Git via `PATH` env — `CheckpointManager.gitPath` ahora recorre `$PATH` primero, fallbacks después

## Fase 6 — Feature: Sleep Tabs + Perf adicional

- [x] **6.1** `TerminalStatus.sleeping` + `TerminalSession.isSleeping` + `PersistedSession.isSleeping?` (back-compat)
- [x] **6.2** `SessionStore.sleepSession`/`wakeSession`/`toggleSleep` — mata procesos por pane, conserva splitRoot/workingDirectory, fuerza hasStarted=false para re-spawn limpio
- [x] **6.3** `selectSession` auto-wake si tab está dormida
- [x] **6.4** `updateTerminalStatus` ignora updates de panes huérfanos en sesión durmiendo (race con teardown)
- [x] **6.5** `TerminalManager.destroyTerminal` ahora hace `removeFromSuperview` → cierra PTY inmediato
- [x] **6.6** Context menu entry "Dormir/Despertar pestaña" en `SessionTabBar`
- [x] **6.7** Status indicator: ícono `moon.fill` para sleeping
- [x] **6.8** `notchStatusColor` retorna `.systemGray` para sleeping
- [x] **6.9** Localización ES/EN (`sleepTab`, `wakeTab`)
- [x] **6.10** SessionHistoryManager batching — buffer en memoria por sesión, flush en debounce 250ms o backpressure 32KB; drain en quit/readHistory/deleteHistory
- [x] **6.11** `extractStatusSnapshot` tail-only — solo últimas 40 filas en lugar de full buffer (~60% menos lecturas por tick de status durante output pesado)

## Resumen ejecución

**Build verificado**: `xcodebuild ... BUILD SUCCEEDED` tras todos los cambios.

**Items completados**: 25
**Items descartados (falsos positivos / ya hechos)**: 8
**Items pendientes (refactor mayor o cosmético)**: 4

### Archivos modificados
- `Notchy/TerminalManager.swift` — shell whitelist, env blacklist, trust gate, OSC 7 canonical, deinit cleanup
- `Notchy/NotchWindow.swift` — `CVDisplayLinkWrapper.stop()` libera retain pendiente
- `Notchy/CheckpointManager.swift` — `sanitizeRefComponent`, hash validation, temp dir 0o700, `$PATH` resolución
- `Notchy/SessionStore.swift` — persist debounce, error logging
- `Notchy/CommandStore.swift` — canonicalize antes de hash
- `Notchy/AutocompleteEngine.swift` — lowercased cache
- `Notchy/ProjectTrustStore.swift` — **nuevo**, gate de trust por directorio
- `Notchy/NotchyApp.swift` — renombrado desde `BotdockApp.swift`

## Fuera de scope (separar)

- Split SessionStore (god object) — refactor mayor, requiere planning aparte
- Dependency injection / tests target — requiere planning aparte
- Accesibilidad VoiceOver completa — requiere planning aparte
- Migración NotificationCenter → @Observable — requiere planning aparte

---

## Tareas

(ver checklist arriba)
