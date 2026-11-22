import { useEffect, useMemo, useState } from "react";
import {
  Daw,
  FORMAT_LABEL,
  Format,
  Kind,
  Plugin,
  hideWindow,
  isDemo,
  listPlugins,
  loadInDaw,
  onPluginsUpdated,
  pluginIcon,
  revealInFinder,
  scanPlugins,
  setFavorite,
  watchDaw,
} from "./api";
import "./App.css";

/** Un plugin tel que l'utilisateur le voit : toutes ses versions de format réunies. */
interface Entry {
  key: string;
  name: string;
  vendor: string;
  kind: Kind;
  favorite: boolean;
  icon: string | null;
  files: Plugin[];
}

type KindFilter = "all" | "Instrument" | "Effect" | "MidiFx";
type Side = { type: "all" } | { type: "fav" } | { type: "vendor"; vendor: string };

const KIND_LABEL: Record<Kind, string> = {
  Instrument: "Instrument",
  Effect: "Effet",
  MidiFx: "MIDI FX",
  Unknown: "Autre",
};

const FORMATS: Format[] = ["Vst3", "Au", "Clap", "Vst2"];

function group(plugins: Plugin[]): Entry[] {
  const map = new Map<string, Entry>();
  for (const p of plugins) {
    const key = `${p.vendor.toLowerCase()}|${p.name.toLowerCase()}`;
    const e = map.get(key);
    if (e) {
      e.files.push(p);
      e.favorite ||= p.favorite;
      e.icon ??= p.icon_path;
      if (e.kind === "Unknown") e.kind = p.kind;
    } else {
      map.set(key, {
        key,
        name: p.name,
        vendor: p.vendor,
        kind: p.kind,
        favorite: p.favorite,
        icon: p.icon_path,
        files: [p],
      });
    }
  }
  return [...map.values()];
}

function formatSize(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(1)} Go`;
  if (bytes >= 1024 ** 2) return `${Math.round(bytes / 1024 ** 2)} Mo`;
  return `${Math.max(1, Math.round(bytes / 1024))} Ko`;
}

function initials(name: string): string {
  return name
    .split(/[\s-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join("");
}

function Thumb({ entry, large = false }: { entry: Entry; large?: boolean }) {
  const [src, setSrc] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    setSrc(null);
    if (entry.icon) pluginIcon(entry.icon).then((s) => live && setSrc(s));
    return () => {
      live = false;
    };
  }, [entry.icon]);

  return (
    <div className={`thumb ${large ? "thumb-lg" : ""}`}>
      {src ? (
        <img src={src} alt="" />
      ) : (
        <div className="thumb-fallback">
          <span className="thumb-vendor">{entry.vendor}</span>
          <span className="thumb-initials">{initials(entry.name)}</span>
          <span className="knobs" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
        </div>
      )}
    </div>
  );
}

export default function App() {
  const [plugins, setPlugins] = useState<Plugin[]>([]);
  const [scanning, setScanning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [kind, setKind] = useState<KindFilter>("all");
  const [formats, setFormats] = useState<Set<Format>>(new Set());
  const [side, setSide] = useState<Side>({ type: "all" });
  const [vendorQuery, setVendorQuery] = useState("");
  const [vendorSort, setVendorSort] = useState<"name" | "count">("name");
  const [selected, setSelected] = useState<string | null>(null);
  const [daw, setDaw] = useState<Daw | null>(null);
  const [toast, setToast] = useState<{ text: string; error?: boolean } | null>(null);

  useEffect(() => watchDaw(setDaw), []);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 5000);
    return () => clearTimeout(t);
  }, [toast]);

  const sendToDaw = async (e: Entry) => {
    if (!daw?.can_load) return;
    const file =
      e.files.find((f) => f.format === "Au") ?? e.files[0]!;
    setToast({ text: `Création de la piste « ${e.name} » dans ${daw.name}…` });
    try {
      const r = await loadInDaw(file.id);
      setToast({
        text:
          r === "LOADED"
            ? `Piste créée avec ${e.name} dans ${daw.name}.`
            : `Piste créée dans ${daw.name}, mais ${e.name} n'a pas pu être chargé automatiquement.`,
        error: r !== "LOADED",
      });
    } catch (err) {
      setToast({ text: String(err), error: true });
    }
  };

  const onCard = (e: Entry) => {
    setSelected(e.key);
    if (daw?.can_load && e.kind === "Instrument") void sendToDaw(e);
  };

  const runScan = async () => {
    setScanning(true);
    setError(null);
    try {
      setPlugins(await scanPlugins());
    } catch (e) {
      setError(String(e));
    } finally {
      setScanning(false);
    }
  };

  useEffect(() => {
    listPlugins()
      .then((list) => (list.length ? setPlugins(list) : runScan()))
      .catch((e) => setError(String(e)));
    return onPluginsUpdated(setPlugins);
  }, []);

  const entries = useMemo(() => group(plugins), [plugins]);

  const vendors = useMemo(() => {
    const counts = new Map<string, number>();
    for (const e of entries) counts.set(e.vendor, (counts.get(e.vendor) ?? 0) + 1);
    const list = [...counts.entries()].filter(([v]) =>
      v.toLowerCase().includes(vendorQuery.toLowerCase()),
    );
    list.sort((a, b) =>
      vendorSort === "count" ? b[1] - a[1] || a[0].localeCompare(b[0]) : a[0].localeCompare(b[0]),
    );
    return list;
  }, [entries, vendorQuery, vendorSort]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return entries.filter((e) => {
      if (side.type === "fav" && !e.favorite) return false;
      if (side.type === "vendor" && e.vendor !== side.vendor) return false;
      if (kind !== "all" && e.kind !== kind) return false;
      if (formats.size && !e.files.some((f) => formats.has(f.format))) return false;
      if (q && !`${e.name} ${e.vendor}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [entries, side, kind, formats, query]);

  const sel = entries.find((e) => e.key === selected) ?? null;
  const favCount = entries.filter((e) => e.favorite).length;

  const toggleFormat = (f: Format) =>
    setFormats((s) => {
      const n = new Set(s);
      n.has(f) ? n.delete(f) : n.add(f);
      return n;
    });

  const toggleFav = async (e: Entry) => {
    const next = !e.favorite;
    await Promise.all(e.files.map((f) => setFavorite(f.id, next)));
    setPlugins((ps) =>
      ps.map((p) => (e.files.some((f) => f.id === p.id) ? { ...p, favorite: next } : p)),
    );
  };

  return (
    <div className="app">
      <header className="topbar" data-tauri-drag-region>
        <svg className="logo" viewBox="0 0 32 32" role="img" aria-label="My_PlugIN">
          <circle cx="16" cy="16" r="12" />
          <path d="M9 18l4-6 3 8 3-10 4 8" />
        </svg>
        <label className="search inset">
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <circle cx="11" cy="11" r="7" />
            <path d="M20 20l-3.5-3.5" />
          </svg>
          <input
            type="search"
            placeholder="rechercher"
            aria-label="Rechercher un plugin"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </label>
        <span
          className={`status ${daw ? "on" : ""}`}
          title={daw ? `Connecté à ${daw.name}` : "Aucun logiciel de musique ouvert"}
        >
          <i className="dot" />
          {daw ? daw.name : "Aucun DAW"}
        </span>
        <span className="spacer" data-tauri-drag-region />
        <div className="segment inset">
          <button className="active">Bibliothèque</button>
          <button disabled title="Bientôt">
            Licences
          </button>
        </div>
        <button className="raised scan" onClick={runScan} disabled={scanning}>
          {scanning ? "Analyse…" : "Analyser"}
        </button>
        <button className="raised hide" onClick={hideWindow} title="Masquer la fenêtre">
          Masquer<kbd>⌃⌥P</kbd>
        </button>
      </header>

      <div className="filters">
        <div className="segment pill inset">
          {(
            [
              ["all", "Tous"],
              ["Instrument", "Instruments"],
              ["Effect", "Effets"],
              ["MidiFx", "MIDI FX"],
            ] as [KindFilter, string][]
          ).map(([k, label]) => (
            <button key={k} className={kind === k ? "active" : ""} onClick={() => setKind(k)}>
              {label}
            </button>
          ))}
        </div>
        <span className="eyebrow">FORMAT</span>
        <div className="segment pill inset">
          {FORMATS.map((f) => (
            <button
              key={f}
              className={formats.has(f) ? "active" : ""}
              aria-pressed={formats.has(f)}
              onClick={() => toggleFormat(f)}
            >
              {FORMAT_LABEL[f]}
            </button>
          ))}
        </div>
        <span className="spacer" />
        <span className="count">
          {visible.length} plugin{visible.length > 1 ? "s" : ""}
        </span>
      </div>

      <div className="body">
        <aside className="sidebar">
          <div className="eyebrow">À VOUS</div>
          <button
            className={`side-item ${side.type === "all" ? "active" : ""}`}
            onClick={() => setSide({ type: "all" })}
          >
            <span>Tous les plugins</span>
            <span className="badge">{entries.length}</span>
          </button>
          <button
            className={`side-item ${side.type === "fav" ? "active" : ""}`}
            onClick={() => setSide({ type: "fav" })}
          >
            <span>★ Favoris</span>
            <span className="badge">{favCount}</span>
          </button>

          <div className="eyebrow vendor-head">
            ÉDITEUR
            <span className="sort">
              <button
                className={vendorSort === "name" ? "on" : ""}
                onClick={() => setVendorSort("name")}
              >
                Nom
              </button>
              <button
                className={vendorSort === "count" ? "on" : ""}
                onClick={() => setVendorSort("count")}
              >
                Nombre
              </button>
            </span>
          </div>
          <input
            className="vendor-search inset"
            placeholder="filtrer les éditeurs"
            aria-label="Filtrer les éditeurs"
            value={vendorQuery}
            onChange={(e) => setVendorQuery(e.target.value)}
          />
          <div className="vendor-list">
            {vendors.map(([v, n]) => (
              <button
                key={v}
                className={`side-item ${side.type === "vendor" && side.vendor === v ? "active" : ""}`}
                onClick={() => setSide({ type: "vendor", vendor: v })}
              >
                <span className="ellipsis">{v}</span>
                <span className="badge">{n}</span>
              </button>
            ))}
          </div>
        </aside>

        <main className="shelf">
          {error && <div className="banner error">Le scan a échoué : {error}</div>}
          {isDemo && (
            <div className="banner">Aperçu navigateur : données de démonstration.</div>
          )}
          {!scanning && entries.length === 0 && !error && (
            <div className="empty">
              Aucun plugin trouvé dans /Library/Audio/Plug-Ins ni dans ton dossier
              utilisateur.
            </div>
          )}
          <div className="grid">
            {visible.map((e) => (
              <button
                key={e.key}
                className={`card ${selected === e.key ? "selected" : ""}`}
                onClick={() => onCard(e)}
                title={
                  daw?.can_load && e.kind === "Instrument"
                    ? `Cliquer pour créer une piste dans ${daw.name}`
                    : undefined
                }
              >
                <Thumb entry={e} />
                <div className="card-meta">
                  <div className="card-name ellipsis">
                    {e.favorite && <span className="star">★ </span>}
                    {e.name}
                  </div>
                  <div className="card-sub ellipsis">{e.vendor}</div>
                  <div className="formats">
                    {e.files.map((f) => (
                      <span key={f.id} className={`fmt fmt-${f.format}`}>
                        {FORMAT_LABEL[f.format]}
                      </span>
                    ))}
                  </div>
                </div>
              </button>
            ))}
          </div>
          <div className="shelf-floor" aria-hidden="true" />
        </main>

        {sel && (
          <aside className="detail" aria-label="Détails du plugin">
            <div className="detail-close">
              <button aria-label="Fermer" onClick={() => setSelected(null)}>
                ✕
              </button>
            </div>
            <Thumb entry={sel} large />
            <div>
              <div className="detail-name">{sel.name}</div>
              <div className="muted">
                {sel.vendor} · {KIND_LABEL[sel.kind]}
              </div>
            </div>
            {daw?.can_load && (
              <button className="raised send" onClick={() => sendToDaw(sel)}>
                Créer une piste dans {daw.name}
              </button>
            )}
            <div className="row">
              <button className="raised grow" onClick={() => toggleFav(sel)}>
                {sel.favorite ? "★ Retirer des favoris" : "☆ Ajouter aux favoris"}
              </button>
              <button className="raised grow" onClick={() => revealInFinder(sel.files[0]!.path)}>
                Afficher dans le Finder
              </button>
            </div>
            <div className="stats">
              <div className="stat">
                <div className="muted small">Version</div>
                <div className="mono">{sel.files[0]!.version ?? "?"}</div>
              </div>
              <div className="stat">
                <div className="muted small">Taille</div>
                <div>{formatSize(sel.files.reduce((s, f) => s + f.size_bytes, 0))}</div>
              </div>
              <div className="stat">
                <div className="muted small">Formats</div>
                <div>{sel.files.length}</div>
              </div>
            </div>
            <div className="eyebrow">FICHIERS</div>
            {sel.files.map((f) => (
              <div key={f.id} className="file">
                <span className={`fmt fmt-${f.format}`}>{FORMAT_LABEL[f.format]}</span>
                <span className="mono path ellipsis" title={f.path}>
                  {f.path}
                </span>
              </div>
            ))}
          </aside>
        )}
      </div>
      {toast && (
        <div className={`toast ${toast.error ? "error" : ""}`} role="status">
          {toast.text}
        </div>
      )}
    </div>
  );
}
