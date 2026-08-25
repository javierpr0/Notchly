# Plan: Performance de apertura de terminales

## Complejidad: Medio

Diagnóstico medido: spawn frío de terminal paga ~1.1s de login shell
(~0.61s nvm + ~0.5s p10k/resto del rc). El warm pool actual tiene
profundidad 1 y re-arm de 250ms, así que abrir tabs seguidas cae al camino
frío. Además, panes en background fuerzan repaint completo a ~30fps aunque
el panel esté oculto.

## Tareas

### Fase A - Warm pool de profundidad 3
- [x] Nueva política pura `WarmPoolPolicy` (Foundation-only): cálculo de déficit y selección LIFO de terminal viva para reclamar
- [x] `TerminalManager`: reemplazar `warmTerminal` único por pool acotado; llenado escalonado (un spawn por tick de 250ms hasta capacidad)
- [x] `processTerminated`: limpiar entradas muertas del pool
- [x] Registrar `WarmPoolPolicy.swift` en target NotchlyTests (PBXFileReference + PBXBuildFile + Sources phase)
- [x] Tests (6): déficit con capacidad/in-flight, claim LIFO salta shells muertas, sin vivas devuelve nil, índices muertos

### Fase B - Lazy-load de nvm en ~/.zshrc (config del usuario)
- [x] Backup en ~/.zshrc.backup-perf-20260824
- [x] PATH estático al bin default (resuelve alias "22" con glob numérico zsh `(Non[1])`) + loaders perezosos nvm/node/npx/corepack
- [x] Shim `nvm_find_nvmrc`: la config de Herd lo llama al arranque; sin .nvmrc responde vacío sin cargar nvm, con .nvmrc dispara la carga real y delega
- [x] Eliminada la llamada `npm config get prefix` por shell (~0.13s); el prefix bajo nvm ES el bin default ya agregado
- [x] Medición: login shell 1.08-1.28s → 0.05-0.08s (~95%). Verificado: node/nvm lazy OK, auto-switch .nvmrc OK (v20 en dir con rc), claude resuelve, sin errores de arranque

### Fase C - Repaint forzado solo con panel visible
- [x] Política pura `PaneRepaintPolicy.shouldPaint(...)` en TerminalSession.swift
- [x] El flush coalescido de `dataReceived` no pinta cuando la ventana no es visible (sesiones en background siguen stream-eando); dirty marks sobreviven y el show repinta
- [x] Tests (5): key window, panel oculto, ventana nil, pane inicializando, caso normal
- [ ] Verificación visual pendiente del usuario: output vivo correcto al reabrir el panel tras estar oculto con sesiones activas

### Fase D - Instrumentación os_signpost
- [x] Intervalos `OpenTerminal` y `WarmFill`, eventos `Path.warmClaim` / `Path.coldSpawn` (subsystem com.emac.notchly, category terminalOpen)
- [x] Build OK
- [ ] Captura en vivo pendiente del usuario: la automatización de teclado quedó bloqueada por permisos de Accesibilidad (osascript error 1002)

### Captura (Fase D)
```bash
# Mientras usas Notchly y abres tabs:
log stream --predicate 'subsystem == "com.emac.notchly"' --style compact
# O con Instruments: template "os_signpost", filtro terminalOpen
```

## Revisión

- Build Debug: OK tras cada fase.
- Suite final: 106 tests, 0 fallos (11 nuevos).
- Fase A: sin test automatizado del spawn real (capa AppKit/SwiftTerm fuera del target por diseño); la política de pool sí está cubierta.
- Fase D: observabilidad pura, sin delta de comportamiento, sin test aplicable.
- Commits de esta tanda pendientes de autorización explícita del usuario.
