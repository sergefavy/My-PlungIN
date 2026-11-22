# My_PlugIN

Gestionnaire de plugins audio (VST2, VST3, AU, CLAP) pour Mac. Tout reste sur ton ordinateur.

## Ce que fait cette première version

- Scanne `/Library/Audio/Plug-Ins` et `~/Library/Audio/Plug-Ins` (VST, VST3, Components, CLAP) sans charger les plugins.
- Lit le nom, l'éditeur, la version, le type (instrument, effet, MIDI FX) et l'icône de chaque plugin.
- Range tout par éditeur, avec filtres par type et par format, recherche et favoris.
- Garde l'inventaire dans une base SQLite locale.

## Organisation du code

- `src/` : interface React (TypeScript).
- `src-tauri/core/` : scanner, base de données et icônes, en Rust pur (testable sans interface).
- `src-tauri/src/` : l'application Tauri qui relie les deux.

## Lancer en développement (Mac)

Prérequis : [Node.js](https://nodejs.org) 22+ et [Rust](https://rustup.rs).

```sh
npm install
npm run tauri dev
```

Tests du scanner : `cd src-tauri && cargo test -p plugin-core`.

Hors de l'app (`npm run dev` dans un navigateur), l'interface affiche des données de démonstration.

## Construire l'app

`npm run tauri build`, ou laisser GitHub Actions construire le `.dmg` (workflow « Mac »).

## Publier une nouvelle version (mises à jour automatiques)

1. Monter le numéro de version dans `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml` et `package.json`.
2. Pousser un tag du même numéro : `git tag v0.3.0 && git push origin v0.3.0`.
3. Le workflow « Publier une version » construit l'app, la signe et publie la version sur GitHub avec `latest.json`.
4. Les apps installées la proposent au lancement ou via « Rechercher des mises à jour… ».

La signature utilise le secret GitHub `TAURI_SIGNING_PRIVATE_KEY` ; la clé publique est dans `tauri.conf.json`. Sans cette clé, on ne peut plus publier de mise à jour reconnue par les apps installées.
