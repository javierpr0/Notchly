# Plan: Compatibilidad con opencode

## Complejidad: Medio

Notchly detectaba estado, lanzaba y trataba drag-drop solo para Claude Code.
El usuario ejecuta sesiones de opencode (TUI TypeScript, repo
anomalyco/opencode) dentro de Notchly; el objetivo es soporte nativo.

## Marcadores reales de la TUI (v1.18.x, verificados en fuente)

- Spinner: frames braille `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` a 80ms (`component/spinner.tsx`)
- Busy: `<frame> Thinking`, `<frame> Thinking: <tarea>`, o frame + título de
  herramienta (Shell command, Edit <path>, Read, Glob "...", Grep "...",
  List, WebFetch, Task, Access external directory, Call tool)
- Permiso: cabecera "Permission required" con opciones "Allow once" /
  "Allow always" / "Reject"; confirmaciones "Cancel/Confirm permission rejection"
- Idle: placeholder del editor `Ask anything... "<tip>"` (`prompt/index.tsx:1319`)
- Interrumpido: sufijo `· interrupted` en el mensaje del usuario
- Drag-drop: ambas TUIs aceptan menciones `@path`

## Tareas

- [x] Clasificador: `hasOpenCodeSpinnerLine` (frame + label conocido; braille suelto NO cuenta para evitar falsos positivos de scrollback), waiting por "Permission required"/(Allow once + Reject), interrupted por "· interrupted"
- [x] Detección de TUI: `looksLikeOpenCode` + `looksLikeAgentCLI` (Claude OR opencode)
- [x] Política pura `AgentLaunchPolicy`: CLAUDE.md → claude, AGENTS.md → opencode, ambos → claude (comportamiento histórico), ninguno → shell limpio
- [x] `TerminalManager.sendClaudeLaunch` → `sendAgentLaunch`: sondeo async off-main de ambos archivos, comando según política
- [x] Drag-drop `@path` también en sesiones opencode (`isAgentCLIOnScreen`)
- [x] Tests (13 nuevos): spinner opencode con labels, braille sin label idle, diálogo de permisos, interrumpido, placeholder idle, detección TUI, matriz de lanzamiento
- [x] CAPABILITIES.md actualizado

## Notas

- `approveWaitingPane` manda Enter: sirve igual para el diálogo de opencode
  (primera opción resaltada = Allow once). Sin cambios.
- Notificaciones taskCompleted / actionRequired salen de las transiciones de
  status: funcionan automáticamente con el clasificador extendido.
- Verificación visual pendiente del usuario: relanzar Notchly con este build,
  abrir un proyecto con AGENTS.md (sin CLAUDE.md) y ver pill/notificaciones
  durante una sesión real de opencode.

## Revisión

- Build Debug OK. Suite: 119 tests, 0 fallos.

---

# Tanda 2

- [x] Diálogo de preguntas de opencode como waitingForInput: el pie fijo
  `esc dismiss` + (`↑↓ select` / `enter submit` / `enter toggle` /
  `enter confirm`) es su único texto estable; se exigen ambas partes.
  Fuente: `routes/session/question.tsx`
- [x] Summary de notificación: `extractSummary` corta en la línea
  "Ask anything…" para resumir la salida del agente y no el tip del prompt
- [x] Botón dedicado de opencode en el chrome (junto al de Claude): popover
  con Nueva sesión y Continuar última (`opencode --continue`, flag
  verificada con `opencode --help`), enviados al panel enfocado como el menú
  de Claude. Registrado en el registry de diálogos (resign-key hiding)
- [x] L10n ES/EN: launchOpenCode, continueLastSession

## Revisión tanda 2

- Build Debug OK. Suite: 122 tests, 0 fallos (3 nuevos).
- Verificación visual pendiente del usuario: botón opencode, pill/notificaciones durante pregunta y permiso reales.

---

# Tanda 3 (cierre de huecos restantes)

- [x] Comandos default del autocomplete: bloque de 27 entradas de opencode
  (flags verificadas contra `opencode --help` del binario instalado) junto
  al bloque existente de claude. Dato semilla, sin test aplicable.
- [x] Reason del activity token de sleep-prevention neutralizado
  ("Agent CLI working"); era lo último de superficie interna solo-Claude en
  SessionStore. Las notificaciones ya usaban el nombre del tab (neutras).
- [x] Auditoría de restos: notificaciones, pill y tabs ya son neutras al
  agente. `createClaudeSession` no tiene callers (dead code preexistente,
  se deja intacto); `L10n.statusWorking/statusWaitingForInput` son cadenas
  muertas preexistentes que mencionan Claude (se dejan, sin uso).

## Revisión tanda 3

- Build Debug OK. Suite: 122 tests, 0 fallos.
