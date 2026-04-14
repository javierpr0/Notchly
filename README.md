# Notchly

A macOS menu bar app that puts Claude Code right in your MacBook's notch. Hover over the notch or click the menu bar icon to open a floating terminal panel with embedded sessions.

Based on [Notchy](https://github.com/adamlyttleapps/notchy) by Adam Lyttle.

[Leer en Español](#notchly-es)

## Features

- **Notch integration** — hover over the MacBook notch to reveal the terminal panel
- **Multi-session tabs** — run multiple Claude Code sessions side by side
- **Split panes** — split any terminal horizontally or vertically for side-by-side workflows
- **Tab reordering** — drag tabs or use Cmd+Shift+Arrow to reorder
- **Live status in the notch** — animated pill shows whether Claude is working, waiting, or done
- **Git checkpoints** — Cmd+S to snapshot your project before Claude makes changes
- **Terminal search** — Cmd+F to search through terminal output and scrollback
- **Command palette** — Cmd+P to quickly run saved commands per directory
- **Smart notifications** — macOS alerts with success/error detection when Claude finishes
- **Terminal themes** — 10 built-in themes (Dracula, Nord, Tokyo Night, etc.)
- **Auto-updates** — automatic update checks via Sparkle
- **Bilingual** — English and Spanish UI
- **Working directory persistence** — terminals remember where you were across restarts
- **Centered resize** — panel grows equally from both sides, size persists across sessions
- **Adjustable font size** — Cmd+/Cmd- to resize terminal text

## Installation

### Download

Download the latest `Notchly.dmg` from [Releases](https://github.com/javierpr0/Notchly/releases).

### Important: unsigned app

Notchly is not code-signed with an Apple Developer certificate. On first launch macOS will block it. To allow it:

1. Open the DMG and drag **Notchly.app** to **Applications**
2. Try to open Notchly — macOS will show "cannot be opened because the developer cannot be verified"
3. Go to **System Settings → Privacy & Security**
4. Scroll down — you'll see a message about Notchly being blocked
5. Click **"Open Anyway"**
6. Notchly will launch and you won't need to do this again

### Build from source

Requires macOS 26.0+ and Xcode with the macOS 26 SDK.

```bash
xcodebuild -project Notchy.xcodeproj -scheme Notchy -configuration Release build
```

Or open `Notchy.xcodeproj` in Xcode and build (Cmd+B).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `` ` `` (backtick) | Toggle panel |
| Cmd+D | Split pane right |
| Cmd+Shift+D | Split pane down |
| Cmd+Shift+W | Close focused pane |
| Cmd+] / Cmd+[ | Navigate between panes |
| Cmd+1-9 | Jump to nth tab |
| Cmd+Shift+Left/Right | Move tab left/right |
| Cmd+T | New terminal session |
| Cmd+S | Save checkpoint |
| Cmd+F | Search in terminal |
| Cmd+P | Command palette |
| Cmd+= / Cmd+- | Increase / decrease font |
| Cmd+0 | Reset font size |

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator view (via Swift Package Manager)
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-update framework

## License

[MIT](LICENSE)

---

<a id="notchly-es"></a>

# Notchly (Español)

Una app de barra de menu para macOS que pone Claude Code directamente en el notch de tu MacBook. Pasa el cursor sobre el notch o haz clic en el icono de la barra de menu para abrir un panel flotante con sesiones de terminal.

Basado en [Notchy](https://github.com/adamlyttleapps/notchy) por Adam Lyttle.

## Funcionalidades

- **Integracion con el notch** — pasa el cursor sobre el notch del MacBook para revelar el panel
- **Pestanas multi-sesion** — ejecuta multiples sesiones de Claude Code en paralelo
- **Paneles divididos** — divide cualquier terminal horizontal o verticalmente
- **Reordenar pestanas** — arrastra pestanas o usa Cmd+Shift+Flecha
- **Estado en vivo en el notch** — pastilla animada muestra si Claude esta trabajando, esperando o termino
- **Puntos de control Git** — Cmd+S para hacer snapshot de tu proyecto antes de que Claude haga cambios
- **Busqueda en terminal** — Cmd+F para buscar en el output y scrollback
- **Paleta de comandos** — Cmd+P para ejecutar comandos guardados por directorio
- **Notificaciones inteligentes** — alertas de macOS con deteccion de exito/error
- **Temas de terminal** — 10 temas incluidos (Dracula, Nord, Tokyo Night, etc.)
- **Actualizaciones automaticas** — verificacion automatica via Sparkle
- **Bilingue** — interfaz en ingles y espanol
- **Persistencia de directorio** — las terminales recuerdan donde estabas al reiniciar
- **Redimensionado centrado** — el panel crece equitativamente desde ambos lados
- **Tamano de fuente ajustable** — Cmd+/Cmd- para cambiar el tamano del texto

## Instalacion

### Descarga

Descarga el ultimo `Notchly.dmg` desde [Releases](https://github.com/javierpr0/Notchly/releases).

### Importante: app sin firmar

Notchly no esta firmada con un certificado de Apple Developer. En el primer inicio macOS la bloqueara. Para permitirla:

1. Abre el DMG y arrastra **Notchly.app** a **Aplicaciones**
2. Intenta abrir Notchly — macOS mostrara "no se puede abrir porque el desarrollador no se puede verificar"
3. Ve a **Ajustes del Sistema → Privacidad y Seguridad**
4. Desplazate hacia abajo — veras un mensaje sobre Notchly bloqueada
5. Haz clic en **"Abrir de todas formas"**
6. Notchly se abrira y no necesitaras hacer esto de nuevo

### Compilar desde codigo fuente

Requiere macOS 26.0+ y Xcode con el SDK de macOS 26.

```bash
xcodebuild -project Notchy.xcodeproj -scheme Notchy -configuration Release build
```

O abre `Notchy.xcodeproj` en Xcode y compila (Cmd+B).

## Atajos de teclado

| Atajo | Accion |
|-------|--------|
| `` ` `` (acento grave) | Abrir/cerrar panel |
| Cmd+D | Dividir panel a la derecha |
| Cmd+Shift+D | Dividir panel hacia abajo |
| Cmd+Shift+W | Cerrar panel enfocado |
| Cmd+] / Cmd+[ | Navegar entre paneles |
| Cmd+1-9 | Saltar a la pestana N |
| Cmd+Shift+Izq/Der | Mover pestana |
| Cmd+T | Nueva sesion de terminal |
| Cmd+S | Guardar punto de control |
| Cmd+F | Buscar en terminal |
| Cmd+P | Paleta de comandos |
| Cmd+= / Cmd+- | Aumentar / disminuir fuente |
| Cmd+0 | Restablecer tamano de fuente |

## Dependencias

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — vista de emulador de terminal (via Swift Package Manager)
- [Sparkle](https://github.com/sparkle-project/Sparkle) — framework de actualizaciones automaticas

## Licencia

[MIT](LICENSE)
