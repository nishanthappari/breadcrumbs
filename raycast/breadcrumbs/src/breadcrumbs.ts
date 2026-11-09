import { open, showHUD } from "@raycast/api";
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const SUPPORT = join(homedir(), "Library", "Application Support", "Breadcrumbs");

export interface Status {
  phase: "idle" | "running" | "paused" | "awaitingCheckIn" | "completed";
  todayWorked: number;
  todayMissed: number;
  intervalMinutes: number;
  boxesPerSprint: number;
  currentBox?: number;
  totalBoxes?: number;
  remainingSeconds?: number;
}

export function readStatus(): Status | undefined {
  try {
    return JSON.parse(readFileSync(join(SUPPORT, "status.json"), "utf8")) as Status;
  } catch {
    return undefined;
  }
}

/** Counts today's boxes straight from history.json (the source of truth). */
export function todayCounts(): { worked: number; missed: number } {
  const file = join(SUPPORT, "history.json");
  if (!existsSync(file)) return { worked: 0, missed: 0 };
  const { entries } = JSON.parse(readFileSync(file, "utf8")) as { entries: { timestamp: string; worked: boolean }[] };
  const today = new Date().toDateString();
  const todays = entries.filter((e) => new Date(e.timestamp).toDateString() === today);
  const worked = todays.filter((e) => e.worked).length;
  return { worked, missed: todays.length - worked };
}

export async function send(command: string): Promise<void> {
  // Launches the app if needed; the app owns the timer.
  console.log(`breadcrumbs: sending ${command}`);
  await open(`breadcrumbs://${command}`);
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function clock(s: number): string {
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export { showHUD };
