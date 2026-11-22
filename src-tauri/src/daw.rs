//! Détection du logiciel de musique (DAW) ouvert, et envoi d'un plugin
//! vers ce logiciel.

use serde::Serialize;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

/// DAW reconnus, par identifiant d'application macOS (préfixe).
const DAWS: &[(&str, &str)] = &[
    ("com.apple.mobilelogic", "Logic"),
    ("com.apple.logic10", "Logic"),
    ("com.apple.logic", "Logic"),
    ("com.ableton.live", "Ableton"),
    ("com.avid.ProTools", "Pro Tools"),
    ("com.image-line.flstudio", "FL Studio"),
    ("com.steinberg.cubase", "Cubase"),
    ("com.bitwig.BitwigStudio", "Bitwig"),
    ("com.cockos.reaper", "Reaper"),
    ("com.presonus.studioone", "Studio One"),
    ("com.apple.garageband", "GarageBand"),
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Daw {
    pub name: String,
    pub bundle_id: String,
    /// Peut recevoir un plugin (création de piste) : Logic pour l'instant.
    pub can_load: bool,
}

pub fn daw_for(bundle_id: &str) -> Option<Daw> {
    DAWS.iter()
        .find(|(prefix, _)| bundle_id.starts_with(prefix))
        .map(|(_, name)| Daw {
            name: (*name).to_string(),
            bundle_id: bundle_id.to_string(),
            can_load: *name == "Logic",
        })
}

/// Choisit le DAW à afficher : celui au premier plan s'il y en a un,
/// sinon le dernier utilisé encore ouvert, sinon le premier trouvé.
pub fn pick(frontmost: Option<&str>, running: &[String], last: Option<&Daw>) -> Option<Daw> {
    if let Some(d) = frontmost.and_then(daw_for) {
        return Some(d);
    }
    if let Some(l) = last {
        if running.iter().any(|b| b == &l.bundle_id) {
            return Some(l.clone());
        }
    }
    running.iter().find_map(|b| daw_for(b))
}

#[cfg(target_os = "macos")]
#[allow(unused_unsafe)]
fn snapshot() -> (Option<String>, Vec<String>) {
    use objc2_app_kit::NSWorkspace;
    unsafe {
        let ws = NSWorkspace::sharedWorkspace();
        let front = ws
            .frontmostApplication()
            .and_then(|a| a.bundleIdentifier())
            .map(|s| s.to_string());
        let running = ws
            .runningApplications()
            .iter()
            .filter_map(|a| a.bundleIdentifier().map(|s| s.to_string()))
            .collect();
        (front, running)
    }
}

#[cfg(not(target_os = "macos"))]
fn snapshot() -> (Option<String>, Vec<String>) {
    (None, Vec::new())
}

pub fn current() -> Option<Daw> {
    let (front, running) = snapshot();
    pick(front.as_deref(), &running, None)
}

/// Surveille les applications ouvertes et envoie « daw-status » à
/// l'interface à chaque changement.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut last: Option<Daw> = None;
        let mut first = true;
        loop {
            let (front, running) = snapshot();
            let now = pick(front.as_deref(), &running, last.as_ref());
            if first || now != last {
                let _ = app.emit("daw-status", &now);
                first = false;
            }
            last = now;
            std::thread::sleep(Duration::from_millis(1500));
        }
    });
}

/// Script AppleScript (via System Events, donc l'Accessibilité de macOS)
/// qui crée une piste d'instrument logiciel dans Logic puis charge le
/// plugin dans l'emplacement instrument de la nouvelle piste.
pub fn logic_script(bundle_id: &str, vendor: &str, name: &str) -> String {
    let esc = |s: &str| s.replace('\\', "\\\\").replace('"', "\\\"");
    format!(
        r#"
set bid to "{bid}"
set vendorName to "{vendor}"
set pluginName to "{name}"
tell application id bid to activate
delay 0.4
tell application "System Events"
	set p to first application process whose bundle identifier is bid
	tell p
		set frontmost to true
		-- 1) Menu Piste > Nouvelle piste d'instrument logiciel (français ou anglais)
		set trackMenu to missing value
		repeat with mbi in menu bar items of menu bar 1
			if name of mbi is in {{"Piste", "Track"}} then
				set trackMenu to menu 1 of mbi
				exit repeat
			end if
		end repeat
		if trackMenu is missing value then error "NO_TRACK_MENU"
		set made to false
		repeat with mi in menu items of trackMenu
			set t to name of mi
			if t is not missing value then
				if t starts with "Nouvelle piste d’instrument logiciel" or t starts with "Nouvelle piste d'instrument logiciel" or t starts with "New Software Instrument Track" then
					click mi
					set made to true
					exit repeat
				end if
			end if
		end repeat
		if not made then error "NO_NEW_TRACK_ITEM"
		delay 0.8
		-- 2) Emplacement instrument de la tranche de l'Inspecteur
		set slot to missing value
		set w to front window
		set cands to (entire contents of w)
		repeat with e in cands
			try
				set d to description of e
				if d is in {{"Instrument", "instrument", "Emplacement d’instrument", "Instrument slot"}} then
					set slot to e
					exit repeat
				end if
			end try
		end repeat
		if slot is missing value then return "TRACK_ONLY"
		perform action "AXShowMenu" of slot
		delay 0.5
		-- 3) Menu : Instruments AU > Éditeur > Plugin
		set m to menu 1 of slot
		set auItem to missing value
		repeat with mi in menu items of m
			set t to name of mi
			if t is in {{"AU Instruments", "Instruments AU"}} then
				set auItem to mi
				exit repeat
			end if
		end repeat
		if auItem is missing value then
			key code 53
			return "TRACK_ONLY"
		end if
		set vm to menu 1 of auItem
		set target to missing value
		repeat with vi in menu items of vm
			if name of vi is vendorName then
				repeat with pi in menu items of menu 1 of vi
					if name of pi is pluginName then
						set target to pi
						exit repeat
					end if
				end repeat
			else if name of vi is pluginName then
				set target to vi
			end if
			if target is not missing value then exit repeat
		end repeat
		if target is missing value then
			key code 53
			return "TRACK_ONLY"
		end if
		click target
		return "LOADED"
	end tell
end tell
"#,
        bid = esc(bundle_id),
        vendor = esc(vendor),
        name = esc(name)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_frontmost_then_last_then_any() {
        let running = vec!["com.apple.Safari".into(), "com.ableton.live".into(), "com.apple.logic10".into()];
        assert_eq!(pick(Some("com.apple.logic10"), &running, None).unwrap().name, "Logic");
        let last = daw_for("com.ableton.live");
        assert_eq!(pick(Some("com.apple.Safari"), &running, last.as_ref()).unwrap().name, "Ableton");
        assert_eq!(pick(None, &running, None).unwrap().name, "Ableton");
        assert!(pick(None, &["com.apple.Safari".into()], None).is_none());
        assert!(daw_for("com.apple.mobilelogic").unwrap().can_load);
        assert!(!daw_for("com.ableton.live").unwrap().can_load);
    }

    #[test]
    fn script_escapes_quotes() {
        let s = logic_script("com.apple.logic10", "Native \"NI\"", "Kontakt 7");
        assert!(s.contains("Native \\\"NI\\\""));
        assert!(s.contains("\"Kontakt 7\""));
    }
}
