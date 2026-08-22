# Plan: Fixes de la revisión de código (agosto 2026)

## Complejidad: Medio

## Tareas

### Fase 0 - Verificación y commit del trabajo previo
- [x] Ejecutar suite completa NotchlyTests sobre el árbol actual (76 tests OK)
- [x] Verificar identidad git (acevedo.eduardo@outlook.com)
- [x] Commits: `test: extract pure types, add test target and CI` y `docs: require build and tests for every change`

### Fase 1 - Fix persistencia de customCommand
- [x] Añadir `customCommand: String?` a `PersistedSession` + inicializador de conveniencia `init(from:)`
- [x] Mapear en restauración y persistencia
- [x] Tests: round-trip conserva customCommand; payloads legacy sin el campo decodifican a nil

### Fase 2 - Fix placeholder invisible
- [x] Quitar `.opacity(0)` en `placeholderView`
- [x] Añadir `.accessibilityLabel` con el mensaje + padding horizontal
- Nota: capa SwiftUI, fuera del target de tests por diseño (documentado en CLAUDE.md)

### Fase 3 - Fix sanitización de paste
- [x] Nuevo `ShellSafety.sanitizePastedText`: conserva `\n`/`\t` (pegar multilínea es legítimo), elimina ESC, CR, C0 restantes, DEL y C1
- [x] `pasteFromClipboard` pasa por el gate
- [x] Tests: multilínea intacta, secuencias ESC neutralizadas, CRLF no dispara doble Enter

### Fase 4 - Persistencia atómica a archivo
- [x] Nuevo `Notchy/SessionPersistence.swift` Foundation-only: sobre `~/.notchly/sessions.json`, escritura atómica, envelope versionado, backup con timestamp ante blob corrupto, lectura del legado de UserDefaults como fuente de migración
- [x] SessionStore guarda al archivo y retira las claves legacy tras el primer guardado exitoso
- [x] Registrado en target de tests (PBXFileReference + PBXBuildFile + Sources phase)
- [x] Tests (6): round-trip, puntero activo desconocido, reescritura, corrupto con backup, migración legado, legado basura
- [x] Migración real verificada en la app corriendo: sessions.json creado

### Fase 5 - Cancelación de tareas de transición
- [x] `completionTransitionTasks: [UUID: Task]`: una tarea por panel, se cancela antes de reprogramar
- [x] Cancelación en closeSession / sleepSession / restartSession
- [x] Gate puro `TaskCompletionGate.shouldConfirm` en TerminalSession.swift (testeable)
- [x] Tests: exige idle vigente, suprime tareas triviales, duración desconocida dispara

## Revisión

- Build Debug: OK tras cada fase.
- Suite final: 89 tests, 0 fallos (13 nuevos respecto a los 76 iniciales).
- App relanzada con todos los cambios; migración de sesiones comprobada en caliente.
- Commits de esta tanda pendientes de autorización explícita del usuario.

---

# Tanda 2

### Fase 6 - Persistir createdAt
- [x] `createdAt: Date?` en PersistedSession, mapeado en ambos sentidos (fallback a now solo para payloads legacy)
- [x] Tests: fecha sobrevive round-trip; payload legacy cae a now

### Fase 7 - Invalidar pantalla cacheada al cambiar displays
- [x] `cachedBuiltInScreen = nil` en el handler de didChangeScreenParameters

### Fase 8 - Panel del status item en el display correcto
- [x] showPanel(below:on:) recibe la pantalla del botón; fallback por geometría del rect

### Fase 9 - Revelar panel si el shell falla al arrancar
- [x] revealAfterFailedSpawn(message:) revela la vista y escribe aviso inline con exit code
- Nota: fases 7-9 son capa AppKit, fuera del target de tests por diseño

## Revisión tanda 2

- Build Debug: OK tras cada fase.
- Suite: 89 tests, 0 fallos (aserciones nuevas de createdAt dentro de tests existentes).
- Commits pendientes de autorización explícita del usuario.

---

# Tanda 3

### Fase 10 - Carrera de isShowingDialog
- [x] Nuevo DialogVisibilityRegistry (tipo puro testeable) en TerminalSession.swift
- [x] SessionStore expone setDialogVisible(_:owner:) y isShowingDialog derivado
- [x] PanelContentView y SessionTabBar reportan por owner; cleanup onDisappear y al cerrar sesión
- [x] Tests (3): composición de owners concurrentes, idempotencia, limpieza por prefijo

### Fase 11 - Shortcuts vs campos de texto + Cmd+W
- [x] performKeyEquivalent devuelve super si hay NSText/NSTextView/NSTextField como firstResponder
- [x] Cmd+W cierra el panel enfocado (Cmd+Shift+W se mantiene)

### Fase 12 - Capado de escaneo del menú contextual
- [x] Búsqueda de prompt limitada a 1000 filas atrás; bloque acotado a 2000 filas

### Fase 13 - flushSync en cada cmd-tab
- [x] Eliminado observer willResignActive de CommandStore; queda el flush en willTerminate
