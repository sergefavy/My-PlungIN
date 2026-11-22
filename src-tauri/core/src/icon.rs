//! Conversion de l'icône d'un bundle (.icns ou .png) en image PNG
//! affichable par l'interface (data URL).

use base64::Engine;
use std::path::Path;

/// Renvoie une data URL PNG pour l'icône, ou None si illisible.
pub fn icon_data_url(path: &Path) -> Option<String> {
    let png = match path.extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase) {
        Some(ext) if ext == "png" => std::fs::read(path).ok()?,
        _ => icns_to_png(path)?,
    };
    Some(format!(
        "data:image/png;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(png)
    ))
}

fn icns_to_png(path: &Path) -> Option<Vec<u8>> {
    let file = std::io::BufReader::new(std::fs::File::open(path).ok()?);
    let family = icns::IconFamily::read(file).ok()?;
    // La plus grande taille disponible, au plus 512 px.
    let mut types = family.available_icons();
    types.sort_by_key(|t| std::cmp::Reverse(t.pixel_width()));
    let best = types.into_iter().find(|t| t.pixel_width() <= 512)?;
    let image = family.get_icon_with_type(best).ok()?;
    let mut out = Vec::new();
    image.write_png(&mut out).ok()?;
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_icns() {
        let tmp = tempfile::tempdir().unwrap();
        let img = icns::Image::new(icns::PixelFormat::RGBA, 32, 32);
        let mut fam = icns::IconFamily::new();
        fam.add_icon(&img).unwrap();
        let p = tmp.path().join("a.icns");
        fam.write(std::fs::File::create(&p).unwrap()).unwrap();
        let url = icon_data_url(&p).unwrap();
        assert!(url.starts_with("data:image/png;base64,"));
        assert!(icon_data_url(&tmp.path().join("absent.icns")).is_none());
    }
}
