// Needs the Firestore emulator (FIRESTORE_EMULATOR_HOST); skipped without it.
//   firebase emulators:exec --only firestore --project demo-hold-my-dice "node --test"
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { run } from './cleanup.mjs';

const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const H = 60 * 60 * 1000;
const now = new Date('2026-10-27T12:00:00Z');
const ts = (msAgo) => Timestamp.fromMillis(now.getTime() - msAgo);

describe('the cleanup on an emulator', { skip: !emulator && 'no Firestore emulator' }, () => {
  initializeApp({ projectId: 'demo-hold-my-dice' });
  const db = getFirestore();
  const silent = () => {};

  /** Eight rooms: three to go, five to stay. */
  async function seed() {
    const room = (code, data) => db.doc(`rooms/${code}`).set(data);
    const under = async (code, kind, id, data) => db.doc(`rooms/${code}/${kind}/${id}`).set(data);
    // to go: ended 7 hours ago, with everything under it
    await room('ENDED7', { status: 'ended', createdAt: ts(30 * H), endedAt: ts(7 * H) });
    await under('ENDED7', 'seats', 'p1', { uid: 'a' });
    await under('ENDED7', 'members', 'a', { name: 'a' });
    await under('ENDED7', 'presence', 'a', { lastSeen: ts(7 * H) });
    await under('ENDED7', 'state', 'current', { seq: 2 });
    await under('ENDED7', 'entries', '0', { at: ts(8 * H) });
    await under('ENDED7', 'entries', '1', { at: ts(7.5 * H) });
    await under('ENDED7', 'requests', 'p2_p1', { status: 'open' });
    // to go: a lobby over a day old with nobody
    await room('LOBBY2', { status: 'lobby', createdAt: ts(40 * H) });
    await under('LOBBY2', 'presence', 'a', { lastSeen: ts(39 * H) });
    // to go: what is left of a room that was deleted
    await under('NOROOM', 'presence', 'a', { lastSeen: ts(30 * H) });
    // to stay: ended 2 hours ago
    await room('ENDED1', { status: 'ended', createdAt: ts(30 * H), endedAt: ts(2 * H) });
    // to stay: old but somebody beat 10 minutes ago
    await room('BUSY00', { status: 'playing', createdAt: ts(40 * H) });
    await under('BUSY00', 'presence', 'a', { lastSeen: ts(10 * 60 * 1000) });
    await under('BUSY00', 'presence', 'b', { lastSeen: ts(30 * H) });
    // to stay: old, nobody beat for a day, but something was pressed an hour ago
    await room('PLAYED', { status: 'playing', createdAt: ts(40 * H) });
    await under('PLAYED', 'presence', 'a', { lastSeen: ts(30 * H) });
    await under('PLAYED', 'entries', '0', { at: ts(30 * H) });
    await under('PLAYED', 'entries', '1', { at: ts(H) });
    // to stay: a young lobby
    await room('YOUNG0', { status: 'lobby', createdAt: ts(H) });
    // to stay: not written like a room code
    await room('lower1', { status: 'ended', createdAt: ts(90 * H), endedAt: ts(80 * H) });
  }

  const exists = async (path) => (await db.doc(path).get()).exists;
  const clear = async () => {
    for (const ref of await db.collection('rooms').listDocuments()) await db.recursiveDelete(ref);
  };

  it('a dry run reports and deletes nothing', async () => {
    await clear();
    await seed();
    const report = await run({ db, now, dryRun: true, log: silent });
    assert.deepEqual(report.wouldDelete.map((r) => r.code).sort(), ['ENDED7', 'LOBBY2', 'NOROOM']);
    assert.deepEqual(report.kept.map((r) => r.code).sort(), ['BUSY00', 'ENDED1', 'PLAYED', 'YOUNG0']);
    assert.deepEqual(report.skipped.map((r) => r.code), ['lower1']);
    assert.deepEqual(report.deleted, []);
    assert.equal(await exists('rooms/ENDED7'), true);
    assert.equal(await exists('rooms/ENDED7/entries/1'), true);
  });

  it('a real run takes down the rooms and everything under them, and leaves the others', async () => {
    await clear();
    await seed();
    const report = await run({ db, now, dryRun: false, maxDelete: 20, log: silent });
    assert.deepEqual(report.deleted.map((r) => r.code).sort(), ['ENDED7', 'LOBBY2', 'NOROOM']);
    for (const path of [
      'rooms/ENDED7', 'rooms/ENDED7/seats/p1', 'rooms/ENDED7/members/a', 'rooms/ENDED7/presence/a',
      'rooms/ENDED7/state/current', 'rooms/ENDED7/entries/0', 'rooms/ENDED7/entries/1', 'rooms/ENDED7/requests/p2_p1',
      'rooms/LOBBY2', 'rooms/LOBBY2/presence/a', 'rooms/NOROOM/presence/a',
    ]) assert.equal(await exists(path), false, path);
    for (const path of ['rooms/ENDED1', 'rooms/BUSY00', 'rooms/BUSY00/presence/a', 'rooms/PLAYED', 'rooms/PLAYED/entries/1', 'rooms/YOUNG0', 'rooms/lower1']) {
      assert.equal(await exists(path), true, path);
    }
  });

  it('takes down at most MAX_DELETE rooms, the longest forgotten first, and says what is left', async () => {
    await clear();
    await seed();
    const report = await run({ db, now, dryRun: false, maxDelete: 2, log: silent });
    // forgotten for 40 h (made), 30 h (last beat) and 7 h (ended), in that order
    assert.deepEqual(report.deleted.map((r) => r.code), ['LOBBY2', 'NOROOM']);
    assert.deepEqual(report.leftForNextRun.map((r) => r.code), ['ENDED7']);
    assert.equal(await exists('rooms/ENDED7/entries/1'), true);
    assert.equal(await exists('rooms/NOROOM/presence/a'), false);
    const next = await run({ db, now, dryRun: false, maxDelete: 2, log: silent });
    assert.deepEqual(next.deleted.map((r) => r.code), ['ENDED7']);
  });

  it('a limit of 0 deletes nothing', async () => {
    await clear();
    await seed();
    const report = await run({ db, now, dryRun: false, maxDelete: 0, log: silent });
    assert.deepEqual(report.deleted, []);
    assert.equal(report.leftForNextRun.length, 3);
    assert.equal(await exists('rooms/ENDED7'), true);
  });

  describe('as a command', () => {
    const script = fileURLToPath(new URL('./cleanup.mjs', import.meta.url));
    const command = (env) =>
      spawnSync(process.execPath, [script], {
        env: { ...process.env, PROJECT_ID: 'demo-hold-my-dice', FIREBASE_SERVICE_ACCOUNT: '', ...env },
        encoding: 'utf8',
      });
    const seedOld = () => db.doc('rooms/CMDOLD').set({ status: 'ended', createdAt: Timestamp.fromMillis(Date.now() - 30 * H), endedAt: Timestamp.fromMillis(Date.now() - 10 * H) });

    it('only reports unless told DRY_RUN=false', async () => {
      await clear();
      await seedOld();
      const out = command({});
      assert.equal(out.status, 0, out.stderr);
      assert.match(out.stdout, /DRY RUN/);
      assert.match(out.stdout, /would delete: 1/);
      assert.equal(await exists('rooms/CMDOLD'), true);
    });

    it('deletes with DRY_RUN=false and stops at MAX_DELETE', async () => {
      await clear();
      await seedOld();
      await db.doc('rooms/CMDTWO').set({ status: 'ended', createdAt: Timestamp.fromMillis(Date.now() - 31 * H), endedAt: Timestamp.fromMillis(Date.now() - 11 * H) });
      const out = command({ DRY_RUN: 'false', MAX_DELETE: '1' });
      assert.equal(out.status, 0, out.stderr);
      assert.match(out.stdout, /REAL RUN/);
      assert.match(out.stdout, /deleted: 1 /);
      assert.equal(await exists('rooms/CMDTWO'), false);
      assert.equal(await exists('rooms/CMDOLD'), true);
    });

    it('refuses a MAX_DELETE that is not a number', async () => {
      await clear();
      await seedOld();
      const out = command({ DRY_RUN: 'false', MAX_DELETE: 'many' });
      assert.notEqual(out.status, 0);
      assert.equal(await exists('rooms/CMDOLD'), true);
    });
  });

  it('nothing to do on an empty database', async () => {
    await clear();
    const report = await run({ db, now, dryRun: false, log: silent });
    assert.equal(report.seen, 0);
    assert.deepEqual(report.deleted, []);
  });
});
