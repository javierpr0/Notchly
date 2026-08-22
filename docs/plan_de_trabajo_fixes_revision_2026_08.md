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
