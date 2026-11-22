import { invoke, isTauri } from "@tauri-apps/api/core";
import { revealItemInDir } from "@tauri-apps/plugin-opener";
import ad2 from "./assets/demo/ad2.webp";
import kontakt from "./assets/demo/kontakt.webp";
import loop from "./assets/demo/loop.webp";
import triton from "./assets/demo/triton.webp";

export type Format = "Vst2" | "Vst3" | "Au" | "Clap";
export type Kind = "Instrument" | "Effect" | "MidiFx" | "Unknown";

export interface Plugin {
  id: string;
  name: string;
  vendor: string;
  format: Format;
  kind: Kind;
  version: string | null;
  bundle_id: string | null;
  path: string;
  system_wide: boolean;
  icon_path: string | null;
  size_bytes: number;
  favorite: boolean;
  tags: string[];
}

export const FORMAT_LABEL: Record<Format, string> = {
  Vst2: "VST2",
  Vst3: "VST3",
  Au: "AU",
  Clap: "CLAP",
};

/** Hors de l'app (navigateur), on affiche des données de démonstration. */
const demo = !isTauri();

const DEMO_ICONS: Record<string, string> = { ad2, kontakt, loop, triton };

function demoPlugin(
  name: string,
  vendor: string,
  format: Format,
  kind: Kind,
  icon?: string,
  version = "1.0.0",
): Plugin {
  return {
    id: `${format}:${vendor}/${name}`,
    name,
    vendor,
    format,
    kind,
    version,
    bundle_id: null,
    path: `/Library/Audio/Plug-Ins/${format === "Au" ? "Components" : FORMAT_LABEL[format]}/${name}`,
    system_wide: true,
    icon_path: icon ? `demo:${icon}` : null,
    size_bytes: Math.round((name.length * 37 + 12) * 1024 * 1024),
    favorite: false,
    tags: [],
  };
}

let demoData: Plugin[] = [
  demoPlugin("Addictive Drums 2", "XLN Audio", "Vst3", "Instrument", "ad2", "2.4.1"),
  demoPlugin("Addictive Drums 2", "XLN Audio", "Au", "Instrument", "ad2", "2.4.1"),
  demoPlugin("Kontakt 7", "Native Instruments", "Vst3", "Instrument", "kontakt", "7.10.5"),
  demoPlugin("Kontakt 7", "Native Instruments", "Au", "Instrument", "kontakt", "7.10.5"),
  demoPlugin("Triton", "KORG", "Vst3", "Instrument", "triton", "1.4.3"),
  demoPlugin("Loopcloud", "Loopmasters", "Vst3", "Effect", "loop", "2.3.0"),
  demoPlugin("Pro-Q 3", "FabFilter", "Clap", "Effect", undefined, "3.24"),
  demoPlugin("Pro-C 2", "FabFilter", "Vst3", "Effect", undefined, "2.18"),
  demoPlugin("Surge XT", "Surge Synth Team", "Clap", "Instrument", undefined, "1.3.4"),
  demoPlugin("Arpeggiator", "Inconnu", "Au", "MidiFx"),
];

export async function listPlugins(): Promise<Plugin[]> {
  if (demo) return demoData;
  return invoke<Plugin[]>("list_plugins");
}

export async function scanPlugins(): Promise<Plugin[]> {
  if (demo) {
    await new Promise((r) => setTimeout(r, 600));
    return demoData;
  }
  return invoke<Plugin[]>("scan_plugins");
}

export async function setFavorite(id: string, favorite: boolean): Promise<void> {
  if (demo) {
    demoData = demoData.map((p) => (p.id === id ? { ...p, favorite } : p));
    return;
  }
  await invoke("set_favorite", { id, favorite });
}

const iconCache = new Map<string, Promise<string | null>>();

export function pluginIcon(iconPath: string): Promise<string | null> {
  if (iconPath.startsWith("demo:")) {
    return Promise.resolve(DEMO_ICONS[iconPath.slice(5)] ?? null);
  }
  let p = iconCache.get(iconPath);
  if (!p) {
    p = invoke<string | null>("plugin_icon", { path: iconPath }).catch(() => null);
    iconCache.set(iconPath, p);
  }
  return p;
}

export async function revealInFinder(path: string): Promise<void> {
  if (demo) return;
  await revealItemInDir(path);
}

export const isDemo = demo;
