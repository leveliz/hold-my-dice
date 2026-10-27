import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { decide, ENDED_KEEP, ENTRY_QUIET, OLD_ROOM, PRESENCE_QUIET } from './select.mjs';

const now = new Date('2026-10-27T12:00:00Z');
const ago = (ms) => new Date(now.getTime() - ms);
const H = 60 * 60 * 1000;
const verdict = (room) => decide(room, now).action;

describe('a game that ended', () => {
  const ended = (ms, over = {}) => ({ exists: true, status: 'ended', createdAt: ago(48 * H), endedAt: ago(ms), ...over });

  it('is kept for 6 hours', () => {
    assert.equal(verdict(ended(ENDED_KEEP - 1)), 'keep');
    assert.equal(verdict(ended(60 * 1000)), 'keep');
  });
  it('goes at 6 hours and after', () => {
    assert.equal(verdict(ended(ENDED_KEEP)), 'delete');
    assert.equal(verdict(ended(30 * H)), 'delete');
  });
  it('is judged by when it ended, not when it was made', () => {
    assert.equal(verdict(ended(H, { createdAt: ago(200 * H) })), 'keep');
    assert.equal(verdict(ended(7 * H, { createdAt: ago(8 * H) })), 'delete');
  });
  it('is judged by the end even when somebody beat lately', () => {
    assert.equal(verdict(ended(7 * H, { lastPresence: ago(60 * 1000), lastEntry: ago(60 * 1000) })), 'delete');
  });
  it('an end time in the future is kept', () => {
    assert.equal(verdict(ended(-H)), 'keep');
  });
  it('with no end time is judged like a room that never ended', () => {
    assert.equal(verdict(ended(0, { endedAt: null, createdAt: ago(30 * H) })), 'delete');
    assert.equal(verdict(ended(0, { endedAt: null, createdAt: ago(2 * H) })), 'keep');
  });
});

describe('a room that never ended (a lobby or a game being played)', () => {
  const room = (over = {}) => ({ exists: true, status: 'playing', createdAt: ago(OLD_ROOM + H), ...over });

  it('is kept while it is under 24 hours old, however quiet', () => {
    assert.equal(verdict(room({ createdAt: ago(OLD_ROOM - 1) })), 'keep');
    assert.equal(verdict(room({ createdAt: ago(H), status: 'lobby' })), 'keep');
  });
  it('goes at 24 hours when nobody is there', () => {
    assert.equal(verdict(room({ createdAt: ago(OLD_ROOM) })), 'delete');
    assert.equal(verdict(room({ status: 'lobby' })), 'delete');
  });
  it('is kept when somebody beat in the last 2 hours', () => {
    assert.equal(verdict(room({ lastPresence: ago(PRESENCE_QUIET - 1) })), 'keep');
    assert.equal(verdict(room({ lastPresence: ago(60 * 1000) })), 'keep');
  });
  it('goes when the last beat was 2 hours ago or more', () => {
    assert.equal(verdict(room({ lastPresence: ago(PRESENCE_QUIET) })), 'delete');
  });
  it('is kept when something was pressed in the last 6 hours', () => {
    assert.equal(verdict(room({ lastEntry: ago(ENTRY_QUIET - 1) })), 'keep');
  });
  it('goes when the last press was 6 hours ago or more', () => {
    assert.equal(verdict(room({ lastEntry: ago(ENTRY_QUIET) })), 'delete');
  });
  it('is kept when it has no creation time', () => {
    assert.equal(verdict(room({ createdAt: null })), 'keep');
    assert.equal(verdict({ exists: true, status: 'lobby' }), 'keep');
  });
  it('a beat or a press in the future keeps it', () => {
    assert.equal(verdict(room({ lastPresence: ago(-H) })), 'keep');
    assert.equal(verdict(room({ lastEntry: ago(-H) })), 'keep');
  });
});

describe('what is left of a room that was deleted', () => {
  const orphan = (over = {}) => ({ exists: false, ...over });

  it('goes when nobody beat or pressed lately', () => {
    assert.equal(verdict(orphan()), 'delete');
    assert.equal(verdict(orphan({ lastPresence: ago(PRESENCE_QUIET), lastEntry: ago(ENTRY_QUIET) })), 'delete');
  });
  it('is kept when somebody beat in the last 2 hours', () => {
    assert.equal(verdict(orphan({ lastPresence: ago(PRESENCE_QUIET - 1) })), 'keep');
  });
  it('is kept when something was pressed in the last 6 hours', () => {
    assert.equal(verdict(orphan({ lastEntry: ago(ENTRY_QUIET - 1) })), 'keep');
  });
});

describe('the reason is always given', () => {
  it('says why', () => {
    for (const room of [
      { exists: false },
      { exists: true, status: 'ended', endedAt: ago(7 * H) },
      { exists: true, status: 'lobby', createdAt: ago(H) },
      { exists: true, status: 'lobby' },
    ]) {
      assert.ok(decide(room, now).reason.length > 10);
    }
  });
});

describe('the times are the ones agreed', () => {
  it('24 hours for a room that never ended, 6 for one that ended', () => {
    assert.equal(verdict({ exists: true, status: 'lobby', createdAt: ago(24 * H - 1) }), 'keep');
    assert.equal(verdict({ exists: true, status: 'lobby', createdAt: ago(24 * H) }), 'delete');
    assert.equal(verdict({ exists: true, status: 'ended', endedAt: ago(6 * H - 1) }), 'keep');
    assert.equal(verdict({ exists: true, status: 'ended', endedAt: ago(6 * H) }), 'delete');
  });
  it('2 hours since a beat and 6 since a press', () => {
    const old = { exists: true, status: 'playing', createdAt: ago(48 * H) };
    assert.equal(verdict({ ...old, lastPresence: ago(2 * H - 1) }), 'keep');
    assert.equal(verdict({ ...old, lastPresence: ago(2 * H) }), 'delete');
    assert.equal(verdict({ ...old, lastEntry: ago(6 * H - 1) }), 'keep');
    assert.equal(verdict({ ...old, lastEntry: ago(6 * H) }), 'delete');
  });
});
