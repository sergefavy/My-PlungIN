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

fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
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

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let open = MenuItemBuilder::with_id("open", "Ouvrir My_PlugIN")
        .accelerator("Ctrl+Alt+P")
        .build(app)?;
    let rescan = MenuItemBuilder::with_id("rescan", "Rechercher de nouveaux plugins").build(app)?;
    let quit = MenuItemBuilder::with_id("quit", "Quitter My_PlugIN").build(app)?;
    let menu = MenuBuilder::new(app)
        .item(&open)
        .separator()
        .item(&rescan)
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    use tauri_plugin_global_shortcut::ShortcutState;

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
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

            // Premier lancement : on montre la fenêtre pour que l'utilisateur
            // voie le scan. Ensuite l'app démarre discrètement dans la barre.
            if empty {
                show_main(app.handle());
            }
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
            plugin_icon
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement de l'application");
}
