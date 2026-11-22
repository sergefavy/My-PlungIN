//! Scanner de plugins audio (VST2, VST3, AU, CLAP).
//!
//! Le scan lit uniquement les métadonnées des bundles (Info.plist,
//! moduleinfo.json) : aucun plugin n'est chargé, donc un plugin cassé
//! ne peut pas faire planter l'application.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Format {
    Vst2,
    Vst3,
    Au,
    Clap,
}

impl Format {
    pub fn from_extension(ext: &str) -> Option<Self> {
        match ext.to_ascii_lowercase().as_str() {
            "vst" => Some(Format::Vst2),
            "vst3" => Some(Format::Vst3),
            "component" => Some(Format::Au),
            "clap" => Some(Format::Clap),
            _ => None,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Format::Vst2 => "VST2",
            Format::Vst3 => "VST3",
            Format::Au => "AU",
            Format::Clap => "CLAP",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Kind {
    Instrument,
    Effect,
    MidiFx,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Plugin {
    /// Identifiant stable : format + chemin.
    pub id: String,
    pub name: String,
    pub vendor: String,
    pub format: Format,
    pub kind: Kind,
    pub version: Option<String>,
    pub bundle_id: Option<String>,
    pub path: String,
    /// true si installé pour tous les utilisateurs (/Library).
    pub system_wide: bool,
    /// Icône du bundle (.icns / .png), en attendant la capture de l'interface.
    pub icon_path: Option<String>,
    pub size_bytes: u64,
}

/// Dossier racine à scanner avec le format attendu.
#[derive(Debug, Clone)]
pub struct ScanRoot {
    pub path: PathBuf,
    pub system_wide: bool,
}

/// Dossiers standard des plugins sur macOS.
pub fn default_roots() -> Vec<ScanRoot> {
    let subdirs = ["VST", "VST3", "Components", "CLAP"];
    let mut roots = Vec::new();
    for sub in subdirs {
        roots.push(ScanRoot {
            path: PathBuf::from("/Library/Audio/Plug-Ins").join(sub),
            system_wide: true,
        });
        if let Some(home) = dirs::home_dir() {
            roots.push(ScanRoot {
                path: home.join("Library/Audio/Plug-Ins").join(sub),
                system_wide: false,
            });
        }
    }
    roots
}

pub fn scan(roots: &[ScanRoot]) -> Vec<Plugin> {
    let mut out = Vec::new();
    for root in roots {
        if !root.path.is_dir() {
            continue;
        }
        let mut it = walkdir::WalkDir::new(&root.path)
            .follow_links(true)
            .max_depth(6)
            .into_iter();
        while let Some(entry) = it.next() {
            let Ok(entry) = entry else { continue };
            let p = entry.path();
            let Some(format) = p.extension().and_then(|e| e.to_str()).and_then(Format::from_extension)
            else {
                continue;
            };
            // Un bundle est un dossier : on ne descend pas dedans.
            if entry.file_type().is_dir() {
                it.skip_current_dir();
            }
            if let Some(plugin) = read_bundle(p, format, root.system_wide) {
                out.push(plugin);
            }
        }
    }
    out.sort_by(|a, b| {
        a.vendor
            .to_lowercase()
            .cmp(&b.vendor.to_lowercase())
            .then(a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    out
}

pub fn read_bundle(path: &Path, format: Format, system_wide: bool) -> Option<Plugin> {
    let file_stem = path.file_stem()?.to_string_lossy().to_string();
    let contents = path.join("Contents");
    let info: Option<plist::Dictionary> = plist::Value::from_file(contents.join("Info.plist"))
        .ok()
        .and_then(|v| v.into_dictionary());

    let get = |key: &str| -> Option<String> {
        info.as_ref()?
            .get(key)?
            .as_string()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    };

    let bundle_id = get("CFBundleIdentifier");
    let version = get("CFBundleShortVersionString").or_else(|| get("CFBundleVersion"));

    let mut name = get("CFBundleName").unwrap_or_else(|| file_stem.clone());
    let mut vendor: Option<String> = None;
    let mut kind = Kind::Unknown;

    // AU : AudioComponents[0] { name: "Éditeur: Plugin", type: "aumu" }
    if let Some(comp) = info
        .as_ref()
        .and_then(|d| d.get("AudioComponents"))
        .and_then(|v| v.as_array())
        .and_then(|a| a.first())
        .and_then(|v| v.as_dictionary())
    {
        if let Some(full) = comp.get("name").and_then(|v| v.as_string()) {
            if let Some((v, n)) = full.split_once(':') {
                vendor = Some(v.trim().to_string());
                name = n.trim().to_string();
            }
        }
        if let Some(t) = comp.get("type").and_then(|v| v.as_string()) {
            kind = match t {
                "aumu" => Kind::Instrument,
                "aumi" => Kind::MidiFx,
                "aufx" | "aumf" => Kind::Effect,
                _ => Kind::Unknown,
            };
        }
    }

    // VST3 : Contents/Resources/moduleinfo.json (SDK 3.7+)
    if format == Format::Vst3 {
        if let Some(mi) = read_moduleinfo(&contents.join("Resources/moduleinfo.json")) {
            if vendor.is_none() {
                vendor = mi.vendor;
            }
            if kind == Kind::Unknown {
                kind = mi.kind;
            }
        }
    }

    let vendor = vendor
        .or_else(|| bundle_id.as_deref().and_then(vendor_from_bundle_id))
        .unwrap_or_else(|| "Inconnu".to_string());

    let icon_path = get("CFBundleIconFile").and_then(|f| {
        let res = contents.join("Resources");
        [res.join(&f), res.join(format!("{f}.icns"))]
            .into_iter()
            .find(|p| p.is_file())
            .map(|p| p.to_string_lossy().to_string())
    });

    let path_str = path.to_string_lossy().to_string();
    Some(Plugin {
        id: format!("{}:{}", format.label(), path_str),
        name,
        vendor,
        format,
        kind,
        version,
        bundle_id,
        path: path_str,
        system_wide,
        icon_path,
        size_bytes: dir_size(path),
    })
}

struct ModuleInfo {
    vendor: Option<String>,
    kind: Kind,
}

fn read_moduleinfo(path: &Path) -> Option<ModuleInfo> {
    // moduleinfo.json est du JSON5 léger ; on retire les virgules finales.
    let raw = std::fs::read_to_string(path).ok()?;
    let cleaned = raw.replace(",\n}", "\n}").replace(",\n]", "\n]");
    let v: serde_json::Value = serde_json::from_str(&cleaned).ok()?;
    let vendor = v
        .pointer("/Factory Info/Vendor")
        .and_then(|x| x.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let sub = v
        .pointer("/Classes")
        .and_then(|c| c.as_array())
        .and_then(|a| {
            a.iter().find(|c| {
                c.get("Category").and_then(|x| x.as_str()) == Some("Audio Module Class")
            })
        })
        .and_then(|c| c.get("Sub Categories"))
        .and_then(|s| s.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>())
        .unwrap_or_default();
    let kind = if sub.iter().any(|s| s.starts_with("Instrument")) {
        Kind::Instrument
    } else if sub.iter().any(|s| s.starts_with("Fx")) {
        Kind::Effect
    } else {
        Kind::Unknown
    };
    Some(ModuleInfo { vendor, kind })
}

/// com.xferrecords.serum -> "Xferrecords"
fn vendor_from_bundle_id(id: &str) -> Option<String> {
    let parts: Vec<&str> = id.split('.').collect();
    let raw = match parts.as_slice() {
        [tld, v, ..] if ["com", "net", "org", "de", "fr", "io", "co", "uk"].contains(tld) => *v,
        [v, ..] => *v,
        _ => return None,
    };
    if raw.is_empty() {
        return None;
    }
    let mut c = raw.chars();
    Some(c.next()?.to_uppercase().collect::<String>() + c.as_str())
}

fn dir_size(path: &Path) -> u64 {
    walkdir::WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter_map(|e| e.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn bundle(root: &Path, name: &str, plist: &str) -> PathBuf {
        let b = root.join(name);
        fs::create_dir_all(b.join("Contents/Resources")).unwrap();
        fs::write(b.join("Contents/Info.plist"), plist).unwrap();
        b
    }

    fn plist(body: &str) -> String {
        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>{body}</dict></plist>"#
        )
    }

    #[test]
    fn scans_au_vst3_clap_vst2() {
        let tmp = tempfile::tempdir().unwrap();
        let comps = tmp.path().join("Components");
        let vst3 = tmp.path().join("VST3");
        let clap = tmp.path().join("CLAP");
        let vst = tmp.path().join("VST");

        bundle(
            &comps,
            "Serum.component",
            &plist(
                r#"<key>CFBundleIdentifier</key><string>com.xferrecords.Serum</string>
<key>CFBundleShortVersionString</key><string>1.36</string>
<key>AudioComponents</key><array><dict>
<key>name</key><string>Xfer Records: Serum</string><key>type</key><string>aumu</string>
</dict></array>"#,
            ),
        );
        let v3 = bundle(
            &vst3,
            "Pro-Q 3.vst3",
            &plist(r#"<key>CFBundleIdentifier</key><string>com.fabfilter.Pro-Q.3</string>"#),
        );
        fs::write(
            v3.join("Contents/Resources/moduleinfo.json"),
            r#"{ "Factory Info": { "Vendor": "FabFilter", },
                "Classes": [ { "Category": "Audio Module Class", "Sub Categories": ["Fx", "EQ"], }, ], }"#
                .replace(", }", " }")
                .replace(", ]", " ]"),
        )
        .unwrap();
        bundle(
            &clap,
            "Surge XT.clap",
            &plist(
                r#"<key>CFBundleIdentifier</key><string>org.surge-synth-team.surge-xt</string>
<key>CFBundleIconFile</key><string>surge</string>"#,
            ),
        );
        fs::write(clap.join("Surge XT.clap/Contents/Resources/surge.icns"), b"icns").unwrap();
        // Plugin rangé dans un sous-dossier d'éditeur, sans Info.plist.
        fs::create_dir_all(vst.join("Vendor/Old Synth.vst/Contents")).unwrap();

        let roots: Vec<ScanRoot> = [comps, vst3, clap, vst]
            .into_iter()
            .map(|path| ScanRoot { path, system_wide: true })
            .collect();
        let found = scan(&roots);
        assert_eq!(found.len(), 4, "{found:#?}");

        let serum = found.iter().find(|p| p.name == "Serum").unwrap();
        assert_eq!(serum.vendor, "Xfer Records");
        assert_eq!(serum.format, Format::Au);
        assert_eq!(serum.kind, Kind::Instrument);
        assert_eq!(serum.version.as_deref(), Some("1.36"));

        let q = found.iter().find(|p| p.format == Format::Vst3).unwrap();
        assert_eq!(q.vendor, "FabFilter");
        assert_eq!(q.kind, Kind::Effect);

        let surge = found.iter().find(|p| p.format == Format::Clap).unwrap();
        assert_eq!(surge.vendor, "Surge-synth-team");
        assert!(surge.icon_path.as_deref().unwrap().ends_with("surge.icns"));

        let old = found.iter().find(|p| p.format == Format::Vst2).unwrap();
        assert_eq!(old.name, "Old Synth");
        assert_eq!(old.vendor, "Inconnu");
    }

    #[test]
    fn missing_roots_are_ignored() {
        let roots = vec![ScanRoot { path: "/nope/nothing".into(), system_wide: false }];
        assert!(scan(&roots).is_empty());
    }
}
