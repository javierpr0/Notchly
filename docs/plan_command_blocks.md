# Plan: Command Blocks (Warp-style)

Target: v0.21.0

## Alcance

Bloques visuales por comando ejecutado (solo shell, no TUI):
- Divisor horizontal entre bloques.
- Índice secuencial en gutter izquierdo.
- Duración a la derecha (0.062s, 5.07s…).
- Exit code indicado con color (verde éxito, rojo error).
- Right-click extendido: **Copy** (bloque completo), **Copy command**, **Copy output**.
- Se oculta cuando alt-buffer activo (Claude, vim, less, top).

Fuera de alcance:
- Colapsar bloques con click.
- Hover-floating icons (copy button flotante estilo Warp).
- Bash support (solo zsh en v0.21.0).
- Re-ejecutar comando desde bloque.

## Arquitectura

### 1. Shell integration
`scripts/notchly-shell-integration.zsh` — emite OSC 133 markers:
- `ESC ]133;A BEL` al inicio del prompt
- `ESC ]133;B BEL` al final del prompt (inicio del input)
- `ESC ]133;C BEL` antes de ejecutar comando (inicio del output)
- `ESC ]133;D;<exit> BEL` al terminar comando

Idempotente: check `$NOTCHLY_SHELL_INTEGRATION` para evitar doble source.

### 2. Installer en Settings
Botón en settings: "Install shell integration (zsh)".
- Copia script a `~/.notchly/shell-integration.zsh`
- Añade `[[ -f ~/.notchly/shell-integration.zsh ]] && source ~/.notchly/shell-integration.zsh` a `~/.zshrc` (idempotente, verifica si ya existe)
- Muestra estado: "Installed" / "Not installed" / "zshrc modified, restart terminal to apply"

### 3. Parser OSC 133
En `ClickThroughTerminalView.dataReceived`:
- Scan buffer recibido en busca de `\x1b]133;` hasta `\x07` o `\x1b\\`
- Al detectar cada marker, registra el absolute row actual (`terminal.buffer.yBase + terminal.buffer.y`) + timestamp
- Mantiene `CommandBlockStore` por pane

### 4. Modelo
```swift
struct CommandBlock: Identifiable {
    let id: UUID
    let index: Int
    var promptStartRow: Int
    var commandText: String?
    var outputStartRow: Int?
    var endRow: Int?
    var exitCode: Int?
    var startedAt: Date?
    var endedAt: Date?

    var duration: TimeInterval? {
        guard let s = startedAt, let e = endedAt else { return nil }
        return e.timeIntervalSince(s)
    }
    var isSuccess: Bool { exitCode == 0 }
}

class CommandBlockStore {
    private(set) var blocks: [CommandBlock] = []
    var onChange: (() -> Void)?
    // notify overlay when blocks change
}
```

### 5. BlocksOverlayView
Subview de `ClickThroughTerminalView`, bounds = terminal bounds.
- `override func draw(_:)` itera blocks visibles
- Para cada block: línea divisora 1px al inicio del promptRow + label de duración a la derecha + índice a la izquierda
- Hit-testing pasa al terminal (no intercepta eventos)
- Observa scroll + resize vía notifications
- Se oculta cuando `terminal.buffer.isAlternate == true`

### 6. Right-click menu
Extender `showContextMenu`:
- Nuevo item "Copy" arriba de todo: copia prompt line + command + output del bloque bajo el cursor
- Mantiene "Copy command" y "Copy output" existentes

### 7. Settings toggle
`showCommandBlocks: Bool` en UserDefaults, default `true`.
Cuando off, overlay.isHidden = true globalmente.

## Orden de implementación

1. `scripts/notchly-shell-integration.zsh` + helper class `ShellIntegration` en Swift
2. Botón de install en Settings + detección de estado
3. Parser OSC 133 + `CommandBlockStore`
4. `BlocksOverlayView` con divisor + timing badge (sin índice primero)
5. Integrar con alt-buffer detection
6. Extender context menu
7. Settings toggle
8. Índice en gutter (opcional, último)

## Fallback sin shell integration

Si el user no instala OSC 133, los bloques NO se muestran. El menú derecho sigue funcionando con el heurístico de prompt chars actual.
Mensaje en Settings: "Install shell integration to enable command blocks".

## Archivos a tocar

- `scripts/notchly-shell-integration.zsh` (nuevo)
- `Notchy/ShellIntegration.swift` (nuevo)
- `Notchy/CommandBlock.swift` (nuevo)
- `Notchy/CommandBlockStore.swift` (nuevo)
- `Notchy/BlocksOverlayView.swift` (nuevo)
- `Notchy/TerminalManager.swift` (extender ClickThroughTerminalView: overlay + OSC 133 parser)
- `Notchy/SettingsView.swift` o equivalente (botón de install + toggle)
- `Notchy/Localization.swift` (strings nuevos)
