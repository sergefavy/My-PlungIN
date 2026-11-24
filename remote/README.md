# Télécommande Desk (iPhone, iPad, Apple Watch)

Un desk personnalisable sur tes appareils pour charger tes plugins via Plugindex sur le Mac.
Cette partie est indépendante de l'appli My_PlugIN.

## Comment ça marche

```
Apple Watch ──(iPhone)──▶ Desk (iPhone / iPad) ──Wi-Fi──▶ Pont (Mac) ──clavier──▶ Plugindex ──▶ Logic
```

- **Pont** (Mac, barre des menus) : s'annonce sur le Wi-Fi (Bonjour `_plugremote._tcp`), affiche un code
  d'appairage à 6 chiffres, puis pilote Plugindex **comme au clavier** : son raccourci d'ouverture
  (lu dans `~/.plugindex/settings.json`, par défaut Ctrl+Option+D), le nom du plugin, Entrée.
  Il lit aussi, sans rien modifier, ta bibliothèque et les images que Plugindex garde dans `~/.plugindex`.
- **Desk** (iPhone et iPad) : des pages de boutons que tu composes (plugin, nom, couleur, image, colonnes, ordre).
- **Desk Watch** : les boutons de la page que tu choisis comme « page de la montre ». La montre passe par l'iPhone.

Le pont n'utilise aucune API interne de Plugindex : il fait ce que tu ferais à la main, donc les limites
de la version gratuite (75 chargements par semaine) s'appliquent normalement.

## Installer

Il faut Xcode et [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd remote
xcodegen generate
open Telecommande.xcodeproj
```

1. Dans Xcode, pour chaque cible (Pont, Desk, DeskWatch) : onglet *Signing & Capabilities*, choisis ton équipe
   (ton identifiant Apple suffit pour tester ; les applis installées ainsi expirent au bout de 7 jours).
2. Lance **Pont** sur le Mac. Dans Réglages Système > Confidentialité et sécurité > **Accessibilité**,
   autorise « Pont Télécommande ».
3. Branche l'iPhone (ou l'iPad), choisis-le comme destination et lance **Desk**. Accepte l'accès au réseau local.
4. Dans Desk, touche ton Mac puis tape le code affiché par l'icône du pont dans la barre des menus.
5. « Modifier » > « + » pour ajouter tes plugins. Les réglages de page permettent de choisir la page de la montre.

Si Plugindex rate des lettres ou ne valide pas, augmente les délais dans le menu du pont.
