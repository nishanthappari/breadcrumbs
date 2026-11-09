import { readStatus, send, showHUD, todayCounts } from "./breadcrumbs";

export default async function Command() {
  const { worked, missed } = todayCounts();
  const s = readStatus();
  const running = s && s.phase !== "idle" && s.phase !== "completed" ? ` · sprint on box ${s.currentBox} of ${s.totalBoxes}` : "";
  await send("today");
  await showHUD(`${worked} ${worked === 1 ? "box" : "boxes"} ticked today${missed ? `, ${missed} missed` : ""}${running}`);
}
