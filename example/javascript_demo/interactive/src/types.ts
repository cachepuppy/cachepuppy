export interface DemoSession {
  clientId: string;
  userName: string;
  colour: string;
}

/** One sticky note in shared topic state (`setTopicState` / `state_updated`). */
export interface StickyNote {
  id: string;
  userName: string;
  colour: string;
  text: string;
}

/** Read `notes` from topic state returned by `getTopicState` / `state_updated`. */
export function notesFromState(state: Record<string, unknown>): StickyNote[] {
  const list = state.notes;
  return Array.isArray(list) ? (list as StickyNote[]) : [];
}
