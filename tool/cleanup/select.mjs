// Which rooms the cleanup takes down. Pure: it looks at what was read from a
// room (see cleanup.mjs) and says "delete" or "keep" with the reason.

const HOUR = 60 * 60 * 1000;

/** A game that ended is kept this long, for the people who come back to it. */
export const ENDED_KEEP = 6 * HOUR;
/** A room that never ended is left alone until it is this old. */
export const OLD_ROOM = 24 * HOUR;
/** Somebody was in the room (a presence beat) within this long: leave it. */
export const PRESENCE_QUIET = 2 * HOUR;
/** Somebody pressed a button (an entry) within this long: leave it. */
export const ENTRY_QUIET = 6 * HOUR;

/**
 * @param {{
 *   exists: boolean,
 *   status?: string,
 *   createdAt?: Date|null,
 *   endedAt?: Date|null,
 *   lastPresence?: Date|null,
 *   lastEntry?: Date|null,
 * }} room what was read; `exists` is false for documents that are only the
 *   parent of a subcollection (what is left when a beat is written after the
 *   room was deleted).
 * @param {Date} now
 * @returns {{ action: 'delete' | 'keep', reason: string }}
 */
export function decide(room, now) {
  // Never seen counts as infinitely long ago; a time in the future as too soon.
  const since = (at) => (at ? now.getTime() - at.getTime() : Infinity);
  const nobodyHere = () => since(room.lastPresence) >= PRESENCE_QUIET;
  const noPlay = () => since(room.lastEntry) >= ENTRY_QUIET;

  if (!room.exists) {
    return nobodyHere() && noPlay()
      ? { action: 'delete', reason: 'what is left of a room that was deleted' }
      : { action: 'keep', reason: 'what is left of a deleted room, but somebody was there lately' };
  }
  if (room.status === 'ended' && room.endedAt) {
    return since(room.endedAt) >= ENDED_KEEP
      ? { action: 'delete', reason: 'ended over 6 hours ago' }
      : { action: 'keep', reason: 'ended less than 6 hours ago' };
  }
  if (!room.createdAt) return { action: 'keep', reason: 'no creation time to go by' };
  if (since(room.createdAt) < OLD_ROOM) return { action: 'keep', reason: 'less than 24 hours old' };
  if (!nobodyHere()) return { action: 'keep', reason: 'somebody was in the room in the last 2 hours' };
  if (!noPlay()) return { action: 'keep', reason: 'something was pressed in the last 6 hours' };
  return { action: 'delete', reason: 'over 24 hours old and nobody there' };
}
