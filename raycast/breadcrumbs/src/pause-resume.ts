import { readStatus, send, showHUD, sleep, clock } from "./breadcrumbs";

export default async function Command() {
  const s = readStatus();
  if (!s || s.phase === "idle" || s.phase === "completed") {
    await showHUD("No sprint running");
    return;
  }
  if (s.phase === "awaitingCheckIn") {
    await send("toggle"); // focuses the check-in
    await showHUD("Waiting for your check-in");
    return;
  }
  await send("toggle");
  await sleep(350);
  const after = readStatus();
  const left = after?.remainingSeconds !== undefined ? ` · ${clock(after.remainingSeconds)} left` : "";
  await showHUD(`${after?.phase === "paused" ? "Paused" : "Resumed"}${left}`);
}
