import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case spanish = "es"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

@Observable
@MainActor
final class L10n {
    static let shared = L10n()

    private static let languageKey = "appLanguage"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.languageKey) ?? "en"
        language = AppLanguage(rawValue: saved) ?? .english
    }

    private var isSpanish: Bool { language == .spanish }

    // MARK: - AppDelegate / Status Menu

    var showInNotch: String { isSpanish ? "Mostrar en notch..." : "Show in notch..." }
    var newSession: String { isSpanish ? "Nueva sesión" : "New Session" }
    var checkpoint: String { isSpanish ? "Punto de control" : "Checkpoint" }
    var save: String { isSpanish ? "Guardar..." : "Save..." }
    var restoreFrom: String { isSpanish ? "Restaurar de…" : "Restore from…" }
    var checkForUpdates: String { isSpanish ? "Buscar actualizaciones…" : "Check for Updates…" }
    var quitNotchly: String { isSpanish ? "Salir de Notchly" : "Quit Notchly" }

    // MARK: - Panel Content

    var unpinPanel: String { isSpanish ? "Desanclar panel" : "Unpin panel" }
    var pinPanelOpen: String { isSpanish ? "Anclar panel" : "Pin panel open" }
    var settings: String { isSpanish ? "Ajustes" : "Settings" }
    var launchClaude: String { isSpanish ? "Iniciar Claude" : "Launch Claude" }
    var newTerminal: String { isSpanish ? "Nueva terminal" : "New terminal" }

    var restoreLastCheckpoint: String { isSpanish ? "Restaurar último punto" : "Restore last checkpoint" }
    var checkpointSaved: String { isSpanish ? "Punto guardado" : "Checkpoint Saved" }

    var clickTabToStart: String { isSpanish ? "Haz clic en una pestaña para iniciar" : "Click a project tab to start a terminal session" }
    var noSessions: String { isSpanish ? "Sin sesiones.\nHaz clic en + para crear una." : "No sessions.\nClick + to create a new session." }
    var selectProject: String { isSpanish ? "Selecciona un proyecto" : "Select a project to begin" }

    var restoreCheckpointTitle: String { isSpanish ? "Restaurar último punto" : "Restore last checkpoint" }
    var restoreCheckpointMessage: String { isSpanish ? "Esto sobrescribirá tu directorio actual con el punto de control. ¿Estás seguro?" : "This will overwrite your current working directory with the checkpoint. Are you sure?" }
    var cancel: String { isSpanish ? "Cancelar" : "Cancel" }

    // MARK: - Claude Menu

    var newSessionTitle: String { isSpanish ? "Nueva sesión" : "New Session" }
    var startFresh: String { isSpanish ? "Empezar de cero" : "Start fresh" }
    var continueTitle: String { isSpanish ? "Continuar" : "Continue" }
    var lastConversation: String { isSpanish ? "Última conversación" : "Last conversation" }
    var resumeTitle: String { isSpanish ? "Reanudar" : "Resume" }
    var pickConversation: String { isSpanish ? "Elige una conversación" : "Pick a conversation" }
    var useChrome: String { isSpanish ? "Usar Chrome" : "Use Chrome" }
    var skipPermissions: String { isSpanish ? "Saltar permisos" : "Skip Permissions" }

    // MARK: - Settings

    var theme: String { isSpanish ? "Tema" : "Theme" }
    var fontSize: String { isSpanish ? "Tamaño de fuente" : "Font Size" }
    var reset: String { isSpanish ? "Restablecer" : "Reset" }
    var languageLabel: String { isSpanish ? "Idioma" : "Language" }

    // MARK: - Notifications

    var actionRequired: String { isSpanish ? "Acción requerida" : "Action Required" }
    func needsInput(_ name: String) -> String { isSpanish ? "\(name) necesita tu atención" : "\(name) needs your input" }
    var taskCompleted: String { isSpanish ? "\u{2713} Tarea completada" : "\u{2713} Task Completed" }
    var taskFailed: String { isSpanish ? "\u{2717} Tarea fallida" : "\u{2717} Task Failed" }
    func sessionFinished(_ name: String) -> String { isSpanish ? "\(name) terminó" : "\(name) finished" }

    // MARK: - Tab Context Menu

    var saveCheckpoint: String { isSpanish ? "Guardar punto" : "Save Checkpoint" }
    var restoreLastCheckpointMenu: String { isSpanish ? "Restaurar último punto" : "Restore Last Checkpoint" }
    var moveLeft: String { isSpanish ? "Mover a la izquierda" : "Move Left" }
    var moveRight: String { isSpanish ? "Mover a la derecha" : "Move Right" }
    var sessionHistory: String { isSpanish ? "Historial de sesi��n" : "Session History" }
    var renameTab: String { isSpanish ? "Renombrar pestaña" : "Rename Tab" }
    var restart: String { isSpanish ? "Reiniciar" : "Restart" }
    var close: String { isSpanish ? "Cerrar" : "Close" }
    var restore: String { isSpanish ? "Restaurar" : "Restore" }

    // MARK: - Split Pane

    var splitRight: String { isSpanish ? "Dividir derecha (⌘D)" : "Split Right (⌘D)" }
    var splitDown: String { isSpanish ? "Dividir abajo (⇧⌘D)" : "Split Down (⇧⌘D)" }
    var closePane: String { isSpanish ? "Cerrar panel (⇧⌘W)" : "Close Pane (⇧⌘W)" }

    // MARK: - Terminal Context Menu

    var copyOutput: String { isSpanish ? "Copiar salida" : "Copy Output" }
    var copyCommand: String { isSpanish ? "Copiar comando" : "Copy Command" }
    var paste: String { isSpanish ? "Pegar" : "Paste" }
    var revealInFinder: String { isSpanish ? "Mostrar en Finder" : "Reveal in Finder" }
    var openInFinder: String { isSpanish ? "Abrir en Finder" : "Open in Finder" }
    var copyPath: String { isSpanish ? "Copiar ruta" : "Copy Path" }

    // MARK: - Search

    var search: String { isSpanish ? "Buscar..." : "Search..." }
    var found: String { isSpanish ? "Encontrado" : "Found" }
    var noResults: String { isSpanish ? "Sin resultados" : "No results" }

    // MARK: - Command Palette

    var runCommand: String { isSpanish ? "Ejecutar comando..." : "Run command..." }
    var deleteCommand: String { isSpanish ? "Eliminar comando" : "Delete Command" }

    // MARK: - History

    func historyTitle(_ name: String) -> String { isSpanish ? "Historial: \(name)" : "History: \(name)" }
    var noHistory: String { isSpanish ? "No hay historial disponible para esta sesión." : "No history available for this session." }

    // MARK: - Full Disk Access

    var fdaTitle: String { isSpanish ? "Acceso completo al disco" : "Full Disk Access" }
    var fdaMessage: String {
        isSpanish
            ? "Notchly necesita acceso completo al disco para que los comandos en la terminal puedan leer tus archivos en Documentos, Escritorio, Descargas y otras carpetas protegidas.\n\nSin este permiso, algunos comandos fallarán con \"Operation not permitted\".\n\nTu terminal funcionará igual que Terminal.app o iTerm2."
            : "Notchly needs Full Disk Access so terminal commands can read files in Documents, Desktop, Downloads and other protected folders.\n\nWithout this permission, some commands will fail with \"Operation not permitted\".\n\nYour terminal will work just like Terminal.app or iTerm2."
    }
    var fdaOpenSettings: String { isSpanish ? "Abrir Ajustes del Sistema" : "Open System Settings" }
    var fdaLater: String { isSpanish ? "Más tarde" : "Later" }
    var fdaDontAskAgain: String { isSpanish ? "No volver a preguntar" : "Don't ask again" }
    var fullDiskAccess: String { isSpanish ? "Acceso completo al disco" : "Full Disk Access" }
}
