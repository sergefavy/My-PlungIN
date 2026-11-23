mod daw;

use plugin_core::{db, icon, scanner};

use std::sync::Mutex;
use tauri::image::Image;
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, WindowEvent};

struct AppState {
    db: Mutex<rusqlite::Connection>,
}

type CmdResult<T> = Result<T, String>;

/// Raccourci global pour afficher ou masquer la fenêtre.
const TOGGLE_SHORTCUT: &str = "ctrl+alt+p";

/// Fenêtre flottante façon panneau : visible sur tous les bureaux, y compris
/// par-dessus une app en plein écran, et au-dessus des fenêtres normales.
#[cfg(target_os = "macos")]
#[allow(unused_unsafe)]
fn make_floating_panel(window: &tauri::WebviewWindow) {
    use objc2_app_kit::{NSWindow, NSWindowCollectionBehavior};
    let Ok(ptr) = window.ns_window() else { return };
    // Le pointeur vient de Tauri et reste valide tant que la fenêtre existe.
    let ns: &NSWindow = unsafe { &*(ptr as *const NSWindow) };
    unsafe {
        ns.setCollectionBehavior(
            NSWindowCollectionBehavior::CanJoinAllSpaces
                | NSWindowCollectionBehavior::FullScreenAuxiliary,
        );
        // NSStatusWindowLevel (25) : passe aussi au-dessus d'une app plein écran.
        ns.setLevel(25);
    }
}

#[cfg(not(target_os = "macos"))]
fn make_floating_panel(_window: &tauri::WebviewWindow) {}

fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        make_floating_panel(&w);
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

fn toggle_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        if w.is_visible().unwrap_or(false) && w.is_focused().unwrap_or(false) {
            let _ = w.hide();
        } else {
            show_main(app);
        }
    }
}

/// Scan complet (bloquant) : met à jour la base, prévient l'interface
/// et renvoie l'inventaire.
fn run_scan(app: &AppHandle) -> CmdResult<Vec<db::Row>> {
    let found = scanner::scan(&scanner::default_roots());
    let state = app.state::<AppState>();
    let rows = {
        let mut conn = state.db.lock().map_err(|e| e.to_string())?;
        db::upsert_scan(&mut conn, &found).map_err(|e| e.to_string())?;
        db::list(&conn).map_err(|e| e.to_string())?
    };
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_tooltip(Some(format!("My_PlugIN · {} plugins", rows.len())));
    }
    let _ = app.emit("plugins-updated", &rows);
    Ok(rows)
}

/// Cherche une nouvelle version publiée sur GitHub et propose de l'installer.
/// `manual` : lancé depuis le menu (on répond aussi quand il n'y a rien).
async fn check_updates(app: AppHandle, manual: bool) {
    use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
    use tauri_plugin_updater::UpdaterExt;

    let ask = |app: &AppHandle, title: &str, text: String, kind: MessageDialogKind, buttons| {
        let d = app
            .dialog()
            .message(text)
            .title(title)
            .kind(kind)
            .buttons(buttons);
        d.blocking_show()
    };

    let result = match app.updater() {
        Ok(u) => u.check().await,
        Err(e) => Err(e),
    };
    // Aucune version encore publiée sur GitHub (pas de latest.json) :
    // ce n'est pas une erreur, il n'y a simplement rien de plus récent.
    let result = match result {
        Err(e) if e.to_string().contains("valid release JSON") => Ok(None),
        other => other,
    };
    match result {
        Ok(Some(update)) => {
            let app2 = app.clone();
            let text = format!(
                "La version {} de My_PlugIN est disponible (tu as la {}).\n\nL'installer maintenant ? L'app redémarrera toute seule.",
                update.version, update.current_version
            );
            let yes = tauri::async_runtime::spawn_blocking(move || {
                ask(
                    &app2,
                    "Mise à jour disponible",
                    text,
                    MessageDialogKind::Info,
                    MessageDialogButtons::OkCancelCustom("Installer".into(), "Plus tard".into()),
                )
            })
            .await
            .unwrap_or(false);
            if !yes {
                return;
            }
            match update.download_and_install(|_, _| {}, || {}).await {
                Ok(()) => app.restart(),
                Err(e) => {
                    let app2 = app.clone();
                    let _ = tauri::async_runtime::spawn_blocking(move || {
                        ask(
                            &app2,
                            "Mise à jour",
                            format!("L'installation a échoué : {e}"),
                            MessageDialogKind::Error,
                            MessageDialogButtons::Ok,
                        )
                    })
                    .await;
                }
            }
        }
        Ok(None) if manual => {
            let version = app.package_info().version.to_string();
            let app2 = app.clone();
            let _ = tauri::async_runtime::spawn_blocking(move || {
                ask(
                    &app2,
                    "Mise à jour",
                    format!("Tu as déjà la dernière version ({version})."),
                    MessageDialogKind::Info,
                    MessageDialogButtons::Ok,
                )
            })
            .await;
        }
        Err(e) if manual => {
            let app2 = app.clone();
            let _ = tauri::async_runtime::spawn_blocking(move || {
                ask(
                    &app2,
                    "Mise à jour",
                    format!("Impossible de vérifier les mises à jour : {e}"),
                    MessageDialogKind::Warning,
                    MessageDialogButtons::Ok,
                )
            })
            .await;
        }
        _ => {}
    }
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let open = MenuItemBuilder::with_id("open", "Ouvrir My_PlugIN")
        .accelerator("Ctrl+Alt+P")
        .build(app)?;
    let rescan = MenuItemBuilder::with_id("rescan", "Rechercher de nouveaux plugins").build(app)?;
    let updates =
        MenuItemBuilder::with_id("updates", "Rechercher des mises à jour…").build(app)?;
    let quit = MenuItemBuilder::with_id("quit", "Quitter My_PlugIN").build(app)?;
    let menu = MenuBuilder::new(app)
        .item(&open)
        .separator()
        .item(&rescan)
        .separator()
        .item(&updates)
        .separator()
        .item(&quit)
        .build()?;

    TrayIconBuilder::with_id("main")
        .icon(Image::from_bytes(include_bytes!("../icons/tray.png"))?)
        .icon_as_template(true)
        .tooltip("My_PlugIN")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => show_main(app),
            "rescan" => {
                let app = app.clone();
                tauri::async_runtime::spawn_blocking(move || {
                    if let Err(e) = run_scan(&app) {
                        eprintln!("scan échoué : {e}");
                    }
                });
            }
            "updates" => {
                tauri::async_runtime::spawn(check_updates(app.clone(), true));
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    Ok(())
}

/// Scanne les dossiers standard puis renvoie l'inventaire.
#[tauri::command]
async fn scan_plugins(app: AppHandle) -> CmdResult<Vec<db::Row>> {
    tauri::async_runtime::spawn_blocking(move || run_scan(&app))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
fn list_plugins(state: tauri::State<'_, AppState>) -> CmdResult<Vec<db::Row>> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::list(&conn).map_err(|e| e.to_string())
}

#[tauri::command]
fn set_favorite(state: tauri::State<'_, AppState>, id: String, favorite: bool) -> CmdResult<()> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::set_favorite(&conn, &id, favorite).map_err(|e| e.to_string())
}

/// Icône du plugin en PNG (data URL) pour la vignette.
#[tauri::command]
async fn plugin_icon(path: String) -> Option<String> {
    tauri::async_runtime::spawn_blocking(move || icon::icon_data_url(std::path::Path::new(&path)))
        .await
        .ok()
        .flatten()
}

/// DAW actuellement détecté (ou null).
#[tauri::command]
fn get_daw() -> Option<daw::Daw> {
    daw::current()
}

/// Crée une piste dans le DAW ouvert avec ce plugin.
/// Renvoie "LOADED" (piste + plugin) ou "TRACK_ONLY" (piste seule).
#[tauri::command]
async fn load_in_daw(state: tauri::State<'_, AppState>, id: String) -> CmdResult<String> {
    let daw = daw::current().ok_or("Aucun logiciel de musique ouvert.")?;
    if !daw.can_load {
        return Err(format!("{} n'est pas encore pris en charge.", daw.name));
    }
    let plugin = {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        db::list(&conn)
            .map_err(|e| e.to_string())?
            .into_iter()
            .find(|r| r.plugin.id == id)
            .ok_or("Plugin introuvable.")?
            .plugin
    };
    if !daw::accessibility_trusted(true) {
        return Err("macOS demande l'autorisation : active My_PlugIN dans Réglages Système › Confidentialité et sécurité › Accessibilité, puis quitte et relance My_PlugIN.".into());
    }
    let script = daw::logic_script(&daw.bundle_id, &plugin.vendor, &plugin.name);
    let out = tauri::async_runtime::spawn_blocking(move || {
        std::process::Command::new("osascript").arg("-e").arg(script).output()
    })
    .await
    .map_err(|e| e.to_string())?
    .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        let err = String::from_utf8_lossy(&out.stderr).to_string();
        if err.contains("-1719") || err.contains("-25211") || err.contains("assistive") {
            Err(format!(
                "macOS bloque encore l'accès (Accessibilité) alors que My_PlugIN est autorisé. Détail : {}",
                err.trim()
            ))
        } else if err.contains("-1743") {
            Err("Autorise My_PlugIN à contrôler « System Events » dans Réglages Système › Confidentialité et sécurité › Automatisation.".into())
        } else {
            Err(format!("Logic n'a pas répondu comme prévu : {}", err.trim()))
        }
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    use tauri_plugin_global_shortcut::ShortcutState;

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_shortcuts([TOGGLE_SHORTCUT])
                .expect("raccourci invalide")
                .with_handler(|app, _shortcut, event| {
                    if event.state == ShortcutState::Pressed {
                        toggle_main(app);
                    }
                })
                .build(),
        )
        .setup(|app| {
            // App de barre des menus : pas d'icône dans le Dock.
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let conn = db::open(&dir.join("inventaire.sqlite"))?;
            let empty = db::list(&conn).map(|r| r.is_empty()).unwrap_or(true);
            app.manage(AppState { db: Mutex::new(conn) });

            build_tray(app.handle())?;
            daw::watch(app.handle().clone());

            // Premier lancement : on montre la fenêtre pour que l'utilisateur
            // voie le scan. Ensuite l'app démarre discrètement dans la barre.
            if empty {
                show_main(app.handle());
            }

            // Vérification discrète au lancement : on ne dit rien s'il n'y a rien.
            tauri::async_runtime::spawn(check_updates(app.handle().clone(), false));
            Ok(())
        })
        .on_window_event(|window, event| {
            // Fermer la fenêtre la masque : l'app reste dans la barre des menus.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            scan_plugins,
            list_plugins,
            set_favorite,
            plugin_icon,
            get_daw,
            load_in_daw
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement de l'application");
}
