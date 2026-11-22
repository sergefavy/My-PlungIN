//! Base locale SQLite : inventaire des plugins + favoris et tags.

use crate::scanner::{Format, Kind, Plugin};
use rusqlite::{params, Connection};
use std::path::Path;

pub fn open(path: &Path) -> rusqlite::Result<Connection> {
    let conn = Connection::open(path)?;
    migrate(&conn)?;
    Ok(conn)
}

pub fn migrate(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS plugins (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            vendor TEXT NOT NULL,
            format TEXT NOT NULL,
            kind TEXT NOT NULL,
            version TEXT,
            bundle_id TEXT,
            path TEXT NOT NULL,
            system_wide INTEGER NOT NULL,
            icon_path TEXT,
            size_bytes INTEGER NOT NULL,
            present INTEGER NOT NULL DEFAULT 1,
            first_seen TEXT NOT NULL DEFAULT (datetime('now')),
            last_seen TEXT NOT NULL DEFAULT (datetime('now')),
            favorite INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS tags (
            plugin_id TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
            tag TEXT NOT NULL,
            PRIMARY KEY (plugin_id, tag)
        );",
    )
}

/// Enregistre le résultat d'un scan. Les plugins disparus sont marqués
/// absents (pas supprimés) pour garder favoris et tags.
pub fn upsert_scan(conn: &mut Connection, plugins: &[Plugin]) -> rusqlite::Result<()> {
    let tx = conn.transaction()?;
    tx.execute("UPDATE plugins SET present = 0", [])?;
    {
        let mut stmt = tx.prepare(
            "INSERT INTO plugins (id, name, vendor, format, kind, version, bundle_id, path,
                                  system_wide, icon_path, size_bytes, present)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 1)
             ON CONFLICT(id) DO UPDATE SET
                name = excluded.name, vendor = excluded.vendor, kind = excluded.kind,
                version = excluded.version, bundle_id = excluded.bundle_id,
                icon_path = excluded.icon_path, size_bytes = excluded.size_bytes,
                present = 1, last_seen = datetime('now')",
        )?;
        for p in plugins {
            stmt.execute(params![
                p.id,
                p.name,
                p.vendor,
                p.format.label(),
                kind_str(p.kind),
                p.version,
                p.bundle_id,
                p.path,
                p.system_wide,
                p.icon_path,
                p.size_bytes as i64,
            ])?;
        }
    }
    tx.commit()
}

#[derive(Debug, serde::Serialize)]
pub struct Row {
    #[serde(flatten)]
    pub plugin: Plugin,
    pub favorite: bool,
    pub tags: Vec<String>,
}

pub fn list(conn: &Connection) -> rusqlite::Result<Vec<Row>> {
    let mut stmt = conn.prepare(
        "SELECT id, name, vendor, format, kind, version, bundle_id, path, system_wide,
                icon_path, size_bytes, favorite,
                (SELECT group_concat(tag, char(31)) FROM tags t WHERE t.plugin_id = plugins.id)
         FROM plugins WHERE present = 1
         ORDER BY lower(vendor), lower(name)",
    )?;
    let rows = stmt.query_map([], |r| {
        let tags: Option<String> = r.get(12)?;
        Ok(Row {
            plugin: Plugin {
                id: r.get(0)?,
                name: r.get(1)?,
                vendor: r.get(2)?,
                format: format_from(&r.get::<_, String>(3)?),
                kind: kind_from(&r.get::<_, String>(4)?),
                version: r.get(5)?,
                bundle_id: r.get(6)?,
                path: r.get(7)?,
                system_wide: r.get(8)?,
                icon_path: r.get(9)?,
                size_bytes: r.get::<_, i64>(10)? as u64,
            },
            favorite: r.get(11)?,
            tags: tags
                .map(|t| t.split('\u{1f}').map(String::from).collect())
                .unwrap_or_default(),
        })
    })?;
    rows.collect()
}

pub fn set_favorite(conn: &Connection, id: &str, fav: bool) -> rusqlite::Result<()> {
    conn.execute("UPDATE plugins SET favorite = ?2 WHERE id = ?1", params![id, fav])?;
    Ok(())
}

fn kind_str(k: Kind) -> &'static str {
    match k {
        Kind::Instrument => "instrument",
        Kind::Effect => "effect",
        Kind::MidiFx => "midifx",
        Kind::Unknown => "unknown",
    }
}

fn kind_from(s: &str) -> Kind {
    match s {
        "instrument" => Kind::Instrument,
        "effect" => Kind::Effect,
        "midifx" => Kind::MidiFx,
        _ => Kind::Unknown,
    }
}

fn format_from(s: &str) -> Format {
    match s {
        "VST2" => Format::Vst2,
        "VST3" => Format::Vst3,
        "AU" => Format::Au,
        _ => Format::Clap,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(id: &str, name: &str) -> Plugin {
        Plugin {
            id: id.into(),
            name: name.into(),
            vendor: "V".into(),
            format: Format::Vst3,
            kind: Kind::Effect,
            version: None,
            bundle_id: None,
            path: id.into(),
            system_wide: true,
            icon_path: None,
            size_bytes: 10,
        }
    }

    #[test]
    fn rescan_keeps_favorites_and_hides_removed() {
        let mut c = Connection::open_in_memory().unwrap();
        migrate(&c).unwrap();
        upsert_scan(&mut c, &[p("a", "A"), p("b", "B")]).unwrap();
        set_favorite(&c, "a", true).unwrap();
        upsert_scan(&mut c, &[p("a", "A2")]).unwrap();
        let rows = list(&c).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].plugin.name, "A2");
        assert!(rows[0].favorite);
    }
}
