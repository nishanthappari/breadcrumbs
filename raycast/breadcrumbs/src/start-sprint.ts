import { readStatus, send, showHUD, sleep, clock } from "./breadcrumbs";

export default async function Command() {
  const before = readStatus();
  if (before && ["running", "paused", "awaitingCheckIn"].includes(before.phase)) {
    await send("start"); // brings a waiting check-in forward; otherwise a no-op
    const left = before.remainingSeconds !== undefined ? ` · ${clock(before.remainingSeconds)} left` : "";
    await showHUD(`Sprint already going: box ${before.currentBox} of ${before.totalBoxes}${left}`);
    return;
  }
  await send("start");
  await sleep(400);
  const s = readStatus();
  const shape = s ? `${s.boxesPerSprint} × ${s.intervalMinutes} min` : "";
  await showHUD(`Sprint started ${shape}`.trim());
}
