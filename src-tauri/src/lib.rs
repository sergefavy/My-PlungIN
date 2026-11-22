use plugin_core::{db, icon, scanner};

use std::sync::Mutex;
use tauri::Manager;

struct AppState {
    db: Mutex<rusqlite::Connection>,
}

type CmdResult<T> = Result<T, String>;

/// Scanne les dossiers standard puis renvoie l'inventaire.
#[tauri::command]
async fn scan_plugins(state: tauri::State<'_, AppState>) -> CmdResult<Vec<db::Row>> {
    let found = tauri::async_runtime::spawn_blocking(|| scanner::scan(&scanner::default_roots()))
        .await
        .map_err(|e| e.to_string())?;
    let mut conn = state.db.lock().map_err(|e| e.to_string())?;
    db::upsert_scan(&mut conn, &found).map_err(|e| e.to_string())?;
    db::list(&conn).map_err(|e| e.to_string())
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
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let conn = db::open(&dir.join("inventaire.sqlite"))?;
            app.manage(AppState { db: Mutex::new(conn) });
            Ok(())
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
