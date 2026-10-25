// Tests of firestore.rules on the Firestore emulator. Run from the repo root:
//   firebase emulators:exec --only firestore --project demo-hold-my-dice "npm --prefix firebase_tests test"
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const PROJECT = 'demo-hold-my-dice';
const CODE = 'ABC234';
const HASH = 'a'.repeat(64);

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const as = (uid) => env.authenticatedContext(uid).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

const settings = (over = {}) => ({
  startingCash: 1500,
  goAmount: 200,
  hideOthers: false,
  allowSpectators: true,
  bankLimit: null,
  maxPlayers: 4,
  ...over,
});

const metaData = (over = {}) => ({
  v: 1,
  ownerUid: 'owner',
  status: 'lobby',
  createdAt: serverTimestamp(),
  settings: settings(),
  hasPassword: false,
  passwordHash: null,
  ...over,
});

const seatData = (uid, name = 'ต้น', over = {}) => ({
  uid,
  name,
  color: 0xff3d5afe,
  joinedAt: serverTimestamp(),
  ...over,
});

const memberData = (name = 'ต้น', over = {}) => ({
  name,
  color: 0xff3d5afe,
  role: 'player',
  seat: 'p1',
  ...over,
});

const stateDoc = (db, code = CODE) => doc(db, 'rooms', code, 'state', 'current');

const stateData = (over = {}) => ({
  v: 1,
  seq: 0,
  seats: ['p1', 'p2'],
  balances: { p1: 1500, p2: 1500 },
  bankrupt: [],
  bankerSeat: null,
  status: 'playing',
  ...over,
});

const room = (db, code = CODE) => doc(db, 'rooms', code);
const seat = (db, id, code = CODE) => doc(db, 'rooms', code, 'seats', id);
const member = (db, uid, code = CODE) => doc(db, 'rooms', code, 'members', uid);
const presence = (db, uid, code = CODE) => doc(db, 'rooms', code, 'presence', uid);

/** A room as it stands after the owner created it, written past the rules. */
async function seedRoom({ status = 'lobby', metaOver = {}, seats = ['owner'] } = {}) {
  await admin(async (db) => {
    await setDoc(room(db), {
      ...metaData({ status, createdAt: Timestamp.now(), ...metaOver }),
    });
    for (const [i, uid] of seats.entries()) {
      await setDoc(seat(db, `p${i + 1}`), {
        ...seatData(uid, `คน ${i + 1}`, { joinedAt: Timestamp.now() }),
      });
      await setDoc(member(db, uid), memberData(`คน ${i + 1}`, { seat: `p${i + 1}` }));
    }
  });
}

/** Joins as a player the way the app does: seat + member in one batch. */
async function joinBatch(db, uid, seatId, { name = 'เพื่อน', pwHash, memberOver = {}, seatOver = {} } = {}) {
  const batch = writeBatch(db);
  batch.set(seat(db, seatId), seatData(uid, name, seatOver));
  batch.set(
    member(db, uid),
    memberData(name, { seat: seatId, ...(pwHash ? { pwHash } : {}), ...memberOver }),
  );
  return batch.commit();
}

describe('the room document (meta)', () => {
  it('a signed-in user can get a room', async () => {
    await seedRoom();
    await assertSucceeds(getDoc(room(as('stranger'))));
  });

  it('a user who is not signed in cannot get a room', async () => {
    await seedRoom();
    await assertFails(getDoc(room(anonymous())));
  });

  it('nobody can list the rooms', async () => {
    await seedRoom();
    await assertFails(getDocs(collection(as('owner'), 'rooms')));
    await assertFails(getDocs(collection(as('stranger'), 'rooms')));
  });

  it('create needs status lobby, v 1 and the writer as owner', async () => {
    const db = as('owner');
    await assertSucceeds(setDoc(room(db, 'GOOD22'), metaData()));
    await assertFails(setDoc(room(db, 'BAD222'), metaData({ status: 'playing' })));
    await assertFails(setDoc(room(db, 'BAD223'), metaData({ v: 2 })));
    await assertFails(setDoc(room(db, 'BAD224'), metaData({ ownerUid: 'someone-else' })));
    await assertFails(setDoc(room(anonymous(), 'BAD225'), metaData()));
  });

  it('create stamps the server time, not a made-up one', async () => {
    const db = as('owner');
    await assertFails(
      setDoc(room(db, 'TIME22'), metaData({ createdAt: Timestamp.fromMillis(1000) })),
    );
  });

  it('a password hash must be exactly 64 characters', async () => {
    const db = as('owner');
    for (const [i, len] of [0, 1, 63, 65].entries()) {
      await assertFails(
        setDoc(room(db, `LEN22${i}`), metaData({ hasPassword: true, passwordHash: 'a'.repeat(len) })),
        `length ${len}`,
      );
    }
  });

  it('create fails when the room already exists', async () => {
    await seedRoom();
    await assertFails(setDoc(room(as('intruder')), metaData({ ownerUid: 'intruder' })));
    await assertFails(setDoc(room(as('owner')), metaData()));
  });

  it('create needs exactly the known fields', async () => {
    const db = as('owner');
    await assertFails(setDoc(room(db, 'EXTRA2'), { ...metaData(), surprise: 1 }));
    const { passwordHash, ...withoutHash } = metaData();
    void passwordHash;
    await assertFails(setDoc(room(db, 'NOHASH'), withoutHash));
  });

  it('a password needs hasPassword true and a hash, and no password needs neither', async () => {
    const db = as('owner');
    await assertSucceeds(
      setDoc(room(db, 'PASS22'), metaData({ hasPassword: true, passwordHash: HASH })),
    );
    await assertFails(
      setDoc(room(db, 'PASS23'), metaData({ hasPassword: true, passwordHash: null })),
    );
    await assertFails(
      setDoc(room(db, 'PASS24'), metaData({ hasPassword: false, passwordHash: HASH })),
    );
  });

  it('settings.maxPlayers outside 2 to 8 fails', async () => {
    const db = as('owner');
    for (const bad of [0, 1, 9, 100, 2.5, '4']) {
      await assertFails(
        setDoc(room(db, `MAX${Math.abs(String(bad).length)}${Math.random().toString(36).slice(2, 5).toUpperCase()}`),
          metaData({ settings: settings({ maxPlayers: bad }) })),
      );
    }
    await assertSucceeds(setDoc(room(db, 'MAXLOW'), metaData({ settings: settings({ maxPlayers: 2 }) })));
    await assertSucceeds(setDoc(room(db, 'MAXTOP'), metaData({ settings: settings({ maxPlayers: 8 }) })));
  });

  it('settings must have sensible money', async () => {
    const db = as('owner');
    const bad = [
      { startingCash: 0 },
      { startingCash: -5 },
      { startingCash: 1000000000 },
      { goAmount: 0 },
      { bankLimit: 0 },
      { bankLimit: -1 },
      { hideOthers: 'yes' },
      { allowSpectators: 1 },
    ];
    for (const [i, over] of bad.entries()) {
      await assertFails(
        setDoc(room(db, `MONEY${i}`), metaData({ settings: settings(over) })),
        `case ${JSON.stringify(over)}`,
      );
    }
    await assertSucceeds(setDoc(room(db, 'MONEYA'), metaData({ settings: settings({ bankLimit: 20000 }) })));
  });

  it('status can only move lobby to playing to ended', async () => {
    await seedRoom();
    const owner = as('owner');
    await assertFails(updateDoc(room(owner), { status: 'ended' }));
    await assertSucceeds(updateDoc(room(owner), { status: 'playing' }));
    await assertFails(updateDoc(room(owner), { status: 'lobby' }));
    await assertSucceeds(updateDoc(room(owner), { status: 'ended' }));
    await assertFails(updateDoc(room(owner), { status: 'playing' }));
  });

  it('only the owner changes the status', async () => {
    await seedRoom({ seats: ['owner', 'u2'] });
    await assertFails(updateDoc(room(as('u2')), { status: 'playing' }));
    await assertFails(updateDoc(room(as('stranger')), { status: 'playing' }));
    await assertSucceeds(updateDoc(room(as('owner')), { status: 'playing' }));
  });

  it('meta fields are locked once playing', async () => {
    await seedRoom({ status: 'playing' });
    const owner = as('owner');
    await assertFails(updateDoc(room(owner), { settings: settings({ maxPlayers: 8 }) }));
    await assertFails(updateDoc(room(owner), { ownerUid: 'u2' }));
    await assertFails(updateDoc(room(owner), { v: 2 }));
    await assertSucceeds(updateDoc(room(owner), { status: 'ended' }));
  });

  it('the owner may change settings while in the lobby', async () => {
    await seedRoom();
    await assertSucceeds(updateDoc(room(as('owner')), { settings: settings({ goAmount: 300 }) }));
    await assertFails(updateDoc(room(as('stranger')), { settings: settings({ goAmount: 1 }) }));
  });

  it('a room cannot be deleted by a player', async () => {
    await seedRoom();
    await assertFails(deleteDoc(room(as('owner'))));
  });
});

describe('seats', () => {
  it('get is allowed for a signed-in user, list is denied', async () => {
    await seedRoom();
    await assertSucceeds(getDoc(seat(as('stranger'), 'p1')));
    await assertFails(getDoc(seat(anonymous(), 'p1')));
    await assertFails(getDocs(collection(as('owner'), 'rooms', CODE, 'seats')));
  });

  it('the owner creates the room and sits at p1 in one batch', async () => {
    const db = as('owner');
    const batch = writeBatch(db);
    batch.set(room(db, 'NEW222'), metaData());
    batch.set(seat(db, 'p1', 'NEW222'), seatData('owner'));
    batch.set(member(db, 'owner', 'NEW222'), memberData('เจ้าของ'));
    await assertSucceeds(batch.commit());
  });

  it('a player joins the lowest free seat with seat and member together', async () => {
    await seedRoom();
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p2'));
  });

  it('only p1 to p8 exist', async () => {
    await seedRoom({ metaOver: { settings: settings({ maxPlayers: 8 }) } });
    for (const bad of ['p0', 'p9', 'p10', 'q1', 'P1', 'p']) {
      await assertFails(joinBatch(as('u2'), 'u2', bad), bad);
    }
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p8'));
  });

  it('a seat number above maxPlayers fails', async () => {
    await seedRoom({ metaOver: { settings: settings({ maxPlayers: 3 }) } });
    await assertFails(joinBatch(as('u2'), 'u2', 'p4'));
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p3'));
  });

  it('a player cannot sit after the game started', async () => {
    await seedRoom({ status: 'playing' });
    await assertFails(joinBatch(as('u2'), 'u2', 'p2'));
  });

  it('the second create of the same seat fails', async () => {
    await seedRoom();
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p2'));
    await assertFails(joinBatch(as('u3'), 'u3', 'p2'));
  });

  it('a seat written by someone else in my name fails', async () => {
    await seedRoom();
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { seatOver: { uid: 'u3' } }));
  });

  it('a seat name that is empty or too long fails even when the member name is fine', async () => {
    await seedRoom();
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { seatOver: { name: '' } }));
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { seatOver: { name: 'x'.repeat(21) } }));
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { seatOver: { name: 5 } }));
  });

  it('a person who already has a seat cannot take a second one', async () => {
    await seedRoom({ metaOver: { settings: settings({ maxPlayers: 8 }) } });
    await assertFails(setDoc(seat(as('owner'), 'p3'), seatData('owner')));
    await seedRoom();
  });

  it('a spectator cannot take a seat', async () => {
    await seedRoom();
    const spectator = as('s1');
    await setDoc(
      member(spectator, 's1'),
      memberData('ผู้ชม', { role: 'spectator', seat: null }),
    );
    await assertFails(setDoc(seat(spectator, 'p2'), seatData('s1')));
  });

  it('a seat without a member document is refused', async () => {
    await seedRoom();
    await assertFails(setDoc(seat(as('u2'), 'p2'), seatData('u2')));
  });

  it('a name over 20 characters fails and 20 is fine', async () => {
    await seedRoom();
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { name: 'x'.repeat(21) }));
    await assertSucceeds(joinBatch(as('u3'), 'u3', 'p3', { name: 'x'.repeat(20) }));
  });

  it('20 Thai characters with vowel and tone marks are accepted', async () => {
    await seedRoom();
    const thai = 'กรุงเทพมหานครอมรรัต'; // 19 letters; marks count as characters
    assert.ok(thai.length <= 20);
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p2', { name: thai + 'ั' }));
  });

  it('an empty name fails', async () => {
    await seedRoom();
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { name: '' }));
  });

  it('a wrong or missing password hash fails when the room has a password', async () => {
    await seedRoom({ metaOver: { hasPassword: true, passwordHash: HASH } });
    await assertFails(joinBatch(as('u2'), 'u2', 'p2'));
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { pwHash: 'b'.repeat(64) }));
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p2', { pwHash: HASH }));
  });

  describe('taking over a seat after losing the identity', () => {
    const takeover = (db, newUid, seatId, extra = {}) => {
      const batch = writeBatch(db);
      batch.update(seat(db, seatId), { uid: newUid });
      batch.set(member(db, newUid), memberData('เพื่อน', { seat: seatId, ...extra }));
      return batch.commit();
    };
    const beat = (uid, msAgo) =>
      admin((db) => setDoc(presence(db, uid), { lastSeen: Timestamp.fromMillis(Date.now() - msAgo) }));

    it('succeeds when the old uid presence is older than 2 minutes', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      await assertSucceeds(takeover(as('u9'), 'u9', 'p2'));
    });

    it('fails when the presence is fresh', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 30 * 1000);
      await assertFails(takeover(as('u9'), 'u9', 'p2'));
    });

    it('fails when the old uid has no presence at all', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await assertFails(takeover(as('u9'), 'u9', 'p2'));
    });

    it('works in the lobby too', async () => {
      await seedRoom({ seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      await assertSucceeds(takeover(as('u9'), 'u9', 'p2'));
    });

    it('the owner cannot hand a seat to someone else', async () => {
      await seedRoom({ seats: ['owner', 'u2'] });
      const owner = as('owner');
      const batch = writeBatch(owner);
      batch.update(seat(owner, 'p2'), { uid: 'u8' });
      batch.set(member(owner, 'u8'), memberData('เพื่อน', { seat: 'p2' }));
      await assertFails(batch.commit());
    });

    it('a takeover may not change anything but who sits there', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      const db = as('u9');
      const batch = writeBatch(db);
      batch.update(seat(db, 'p2'), { uid: 'u9', joinedAt: serverTimestamp() });
      batch.set(member(db, 'u9'), memberData('เพื่อน', { seat: 'p2' }));
      await assertFails(batch.commit());
    });

    it('fails once the game has ended', async () => {
      await seedRoom({ status: 'ended', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      await assertFails(takeover(as('u9'), 'u9', 'p2'));
    });

    it('needs the room password too', async () => {
      await seedRoom({
        status: 'playing',
        seats: ['owner', 'u2'],
        metaOver: { hasPassword: true, passwordHash: HASH },
      });
      await beat('u2', 3 * 60 * 1000);
      await assertFails(takeover(as('u9'), 'u9', 'p2'));
      await assertSucceeds(takeover(as('u9'), 'u9', 'p2', { pwHash: HASH }));
    });

    it('a takeover needs a member document of its own', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      await assertFails(updateDoc(seat(as('u9'), 'p2'), { uid: 'u9' }));
    });

    it('a spectator cannot take a stale seat', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      const db = as('s1');
      await setDoc(member(db, 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null }));
      await assertFails(updateDoc(seat(db, 'p2'), { uid: 's1' }));
    });

    it('a player who already has a seat cannot also take a stale one', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2', 'u3'] });
      await beat('u3', 3 * 60 * 1000);
      await assertFails(updateDoc(seat(as('u2'), 'p3'), { uid: 'u2' }));
    });

    it('nobody takes a seat in a name that is not theirs', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      const db = as('u9');
      const batch = writeBatch(db);
      batch.update(seat(db, 'p2'), { uid: 'u7' });
      batch.set(member(db, 'u9'), memberData('เพื่อน', { seat: 'p2' }));
      await assertFails(batch.commit());
    });

    it('a takeover cannot point a member at a seat it does not hold', async () => {
      await seedRoom({ status: 'playing', seats: ['owner', 'u2'] });
      await beat('u2', 3 * 60 * 1000);
      const db = as('u9');
      const batch = writeBatch(db);
      batch.update(seat(db, 'p2'), { uid: 'u9' });
      batch.set(member(db, 'u9'), memberData('เพื่อน', { seat: 'p1' }));
      await assertFails(batch.commit());
    });
  });
});

describe('members', () => {
  it('a member can read the members, a non-member cannot', async () => {
    await seedRoom({ seats: ['owner', 'u2'] });
    await assertSucceeds(getDocs(collection(as('u2'), 'rooms', CODE, 'members')));
    await assertSucceeds(getDoc(member(as('u2'), 'owner')));
    await assertFails(getDocs(collection(as('stranger'), 'rooms', CODE, 'members')));
    await assertFails(getDoc(member(as('stranger'), 'owner')));
    await assertFails(getDoc(member(anonymous(), 'owner')));
  });

  it('a spectator joins only when allowSpectators is on', async () => {
    await seedRoom({ metaOver: { settings: settings({ allowSpectators: false }) } });
    const spectator = memberData('ผู้ชม', { role: 'spectator', seat: null });
    await assertFails(setDoc(member(as('s1'), 's1'), spectator));
    await admin((db) => updateDoc(room(db), { settings: settings({ allowSpectators: true }) }));
    await assertSucceeds(setDoc(member(as('s1'), 's1'), spectator));
  });

  it('after the start only spectators can join', async () => {
    await seedRoom({ status: 'playing' });
    await assertFails(joinBatch(as('u2'), 'u2', 'p2'));
    await assertSucceeds(
      setDoc(member(as('s1'), 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null })),
    );
  });

  it('a spectator cannot claim a seat, and a player member needs a seat', async () => {
    await seedRoom();
    await assertFails(
      setDoc(member(as('s1'), 's1'), memberData('ผู้ชม', { role: 'spectator', seat: 'p2' })),
    );
    await assertFails(setDoc(member(as('u2'), 'u2'), memberData('เพื่อน', { seat: null })));
  });

  it('a player member needs the seat document in the same batch', async () => {
    await seedRoom();
    await assertFails(setDoc(member(as('u2'), 'u2'), memberData('เพื่อน', { seat: 'p2' })));
  });

  it('a spectator needs the password too', async () => {
    await seedRoom({ metaOver: { hasPassword: true, passwordHash: HASH } });
    const spectator = memberData('ผู้ชม', { role: 'spectator', seat: null });
    await assertFails(setDoc(member(as('s1'), 's1'), spectator));
    await assertSucceeds(setDoc(member(as('s1'), 's1'), { ...spectator, pwHash: HASH }));
  });

  it('nobody joins a room that has ended', async () => {
    await seedRoom({ status: 'ended' });
    await assertFails(
      setDoc(member(as('s1'), 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null })),
    );
  });

  it('only the roles player and spectator exist', async () => {
    await seedRoom();
    await assertFails(
      setDoc(member(as('s1'), 's1'), memberData('ผู้ชม', { role: 'admin', seat: null })),
    );
    await assertFails(joinBatch(as('u2'), 'u2', 'p2', { memberOver: { role: 'owner' } }));
  });

  it('a name is measured in UTF-16 units, so 10 emoji fit and 11 do not', async () => {
    await seedRoom();
    await assertSucceeds(joinBatch(as('u2'), 'u2', 'p2', { name: '😀'.repeat(10) }));
    await assertFails(joinBatch(as('u3'), 'u3', 'p3', { name: '😀'.repeat(11) }));
  });

  it('a member document can only be written for your own uid', async () => {
    await seedRoom({ metaOver: { settings: settings({ allowSpectators: true }) } });
    await assertFails(
      setDoc(member(as('s1'), 's2'), memberData('ผู้ชม', { role: 'spectator', seat: null })),
    );
  });

  it('the role cannot be changed by the member', async () => {
    await seedRoom({ seats: ['owner', 'u2'] });
    await assertFails(updateDoc(member(as('u2'), 'u2'), { role: 'spectator' }));
    await assertFails(updateDoc(member(as('u2'), 'u2'), { seat: 'p1' }));
    await assertSucceeds(updateDoc(member(as('u2'), 'u2'), { name: 'ชื่อใหม่', color: 1 }));
    await assertFails(updateDoc(member(as('u2'), 'owner'), { name: 'ปลอม' }));
  });

  it('a member document cannot be deleted by a player', async () => {
    await seedRoom({ seats: ['owner', 'u2'] });
    await assertFails(deleteDoc(member(as('u2'), 'u2')));
  });

  it('a name over 20 characters fails for a spectator too', async () => {
    await seedRoom();
    await assertFails(
      setDoc(member(as('s1'), 's1'), memberData('x'.repeat(21), { role: 'spectator', seat: null })),
    );
  });
});

/** The owner presses start: status and state in one batch. */
function startBatch(db, stateOver = {}, { stateId = 'current' } = {}) {
  const batch = writeBatch(db);
  batch.update(room(db), { status: 'playing' });
  batch.set(doc(db, 'rooms', CODE, 'state', stateId), stateData(stateOver));
  return batch.commit();
}

const twoPlayers = { seats: ['owner', 'u2'] };

describe('state', () => {
  it('the owner starts the game: status playing and state created in one batch', async () => {
    await seedRoom(twoPlayers);
    await assertSucceeds(startBatch(as('owner')));
  });

  it('a player who is not the owner cannot start', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('u2')));
  });

  it('state cannot be created while the room is still in the lobby', async () => {
    await seedRoom(twoPlayers);
    await assertFails(setDoc(stateDoc(as('owner')), stateData()));
  });

  it('state cannot be created in a room that already plays', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await assertFails(setDoc(stateDoc(as('owner')), stateData()));
  });

  it('only the document named current exists', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('owner'), {}, { stateId: 'other' }));
  });

  it('every balance must be the starting cash', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 99999 } }));
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 1500, p3: 1500 } }));
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500 } }));
  });

  it('a bank balance equal to bankLimit is needed when the room has one', async () => {
    await seedRoom({ ...twoPlayers, metaOver: { settings: settings({ bankLimit: 5000 }) } });
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 1500, bank: 4000 } }));
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 1500 } }));
    await assertSucceeds(startBatch(as('owner'), { balances: { p1: 1500, p2: 1500, bank: 5000 } }));
  });

  it('in a room with a bank, the seats and the bank are all there is', async () => {
    await seedRoom({ ...twoPlayers, metaOver: { settings: settings({ bankLimit: 5000 }) } });
    await assertFails(
      startBatch(as('owner'), { balances: { p1: 1500, p2: 1500, p3: 1500, bank: 5000 } }),
    );
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 777, bank: 5000 } }));
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 1500, bank: 1500 } }));
  });

  it('a bank balance is refused when the room has no bank limit', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p2: 1500, bank: 1500 } }));
  });

  it('seats must be 2 up to maxPlayers distinct seat ids', async () => {
    await seedRoom({ ...twoPlayers, metaOver: { settings: settings({ maxPlayers: 3 }) } });
    const bal = (ids) => Object.fromEntries(ids.map((i) => [i, 1500]));
    await assertFails(startBatch(as('owner'), { seats: ['p1'], balances: bal(['p1']) }));
    await assertFails(
      startBatch(as('owner'), { seats: ['p1', 'p2', 'p3', 'p4'], balances: bal(['p1', 'p2', 'p3', 'p4']) }),
    );
    await assertFails(startBatch(as('owner'), { seats: ['p1', 'p1'], balances: bal(['p1']) }));
    await assertFails(startBatch(as('owner'), { seats: ['p1', 'q2'], balances: bal(['p1', 'q2']) }));
    await assertSucceeds(startBatch(as('owner'), { seats: ['p1', 'p3'], balances: bal(['p1', 'p3']) }));
  });

  it('balances must be keyed by exactly the seats', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('owner'), { balances: { p1: 1500, p3: 1500 } }));
  });

  it('a new game starts at seq 0, v 1, nobody bankrupt, no banker, status playing', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('owner'), { v: 2 }));
    await assertFails(startBatch(as('owner'), { seq: 1 }));
    await assertFails(startBatch(as('owner'), { bankrupt: ['p2'] }));
    await assertFails(startBatch(as('owner'), { bankerSeat: 'p2' }));
    await assertFails(startBatch(as('owner'), { status: 'ended' }));
  });

  it('state has exactly the known fields', async () => {
    await seedRoom(twoPlayers);
    await assertFails(startBatch(as('owner'), { surprise: 1 }));
  });

  it('state cannot be changed or deleted directly, not even by the owner', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await admin((db) => setDoc(stateDoc(db), stateData()));
    await assertFails(updateDoc(stateDoc(as('owner')), { seq: 1 }));
    await assertFails(deleteDoc(stateDoc(as('owner'))));
  });

  it('a member can read the state, a non-member cannot', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await admin((db) => setDoc(stateDoc(db), stateData()));
    await assertSucceeds(getDoc(stateDoc(as('u2'))));
    await assertFails(getDoc(stateDoc(as('stranger'))));
    await assertFails(getDoc(stateDoc(anonymous())));
  });
});

describe('presence', () => {
  const beatNow = (db, uid = 'u2') => setDoc(presence(db, uid), { lastSeen: serverTimestamp() });

  it('a member writes their own presence with the server time', async () => {
    await seedRoom(twoPlayers);
    await assertSucceeds(beatNow(as('u2')));
    await assertSucceeds(beatNow(as('u2')));
  });

  it('lastSeen must be the server time, not a made-up one', async () => {
    await seedRoom(twoPlayers);
    await assertFails(setDoc(presence(as('u2'), 'u2'), { lastSeen: Timestamp.fromMillis(1) }));
    await assertFails(setDoc(presence(as('u2'), 'u2'), { lastSeen: Timestamp.now() }));
  });

  it('presence holds nothing but lastSeen', async () => {
    await seedRoom(twoPlayers);
    await assertFails(setDoc(presence(as('u2'), 'u2'), { lastSeen: serverTimestamp(), x: 1 }));
    await assertFails(setDoc(presence(as('u2'), 'u2'), {}));
  });

  it('another member cannot write my presence', async () => {
    await seedRoom(twoPlayers);
    await assertFails(beatNow(as('owner'), 'u2'));
  });

  it('a person who is not in the room cannot write presence', async () => {
    await seedRoom(twoPlayers);
    await assertFails(beatNow(as('stranger'), 'stranger'));
    await assertFails(beatNow(anonymous(), 'stranger'));
  });

  it('presence can be created in the same batch as joining', async () => {
    await seedRoom();
    const db = as('u2');
    const batch = writeBatch(db);
    batch.set(seat(db, 'p2'), seatData('u2'));
    batch.set(member(db, 'u2'), memberData('เพื่อน', { seat: 'p2' }));
    batch.set(presence(db, 'u2'), { lastSeen: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });

  it('a spectator joins together with their presence', async () => {
    await seedRoom();
    const db = as('s1');
    const batch = writeBatch(db);
    batch.set(member(db, 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null }));
    batch.set(presence(db, 's1'), { lastSeen: serverTimestamp() });
    await assertSucceeds(batch.commit());
  });

  it('a member reads one presence, a stranger cannot, and it cannot be listed or deleted', async () => {
    await seedRoom(twoPlayers);
    await beatNow(as('u2'));
    await assertSucceeds(getDoc(presence(as('owner'), 'u2')));
    await assertFails(getDoc(presence(as('stranger'), 'u2')));
    await assertFails(getDocs(collection(as('owner'), 'rooms', CODE, 'presence')));
    await assertFails(deleteDoc(presence(as('u2'), 'u2')));
  });
});

const staleBeat = (uid, msAgo = 3 * 60 * 1000) =>
  admin((db) => setDoc(presence(db, uid), { lastSeen: Timestamp.fromMillis(Date.now() - msAgo) }));

describe('a room whose owner is gone', () => {
  const claim = (db, uid, extra = {}) => updateDoc(room(db), { ownerUid: uid, ...extra });

  it('a member takes over a lobby when the owner was last seen over 2 minutes ago', async () => {
    await seedRoom(twoPlayers);
    await staleBeat('owner');
    await assertSucceeds(claim(as('u2'), 'u2'));
  });

  it('fails while the owner was seen within 2 minutes or never', async () => {
    await seedRoom(twoPlayers);
    await assertFails(claim(as('u2'), 'u2'));
    await staleBeat('owner', 30 * 1000);
    await assertFails(claim(as('u2'), 'u2'));
  });

  it('fails once the game has started', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await staleBeat('owner');
    await assertFails(claim(as('u2'), 'u2'));
  });

  it('a person who is not in the room cannot take it over', async () => {
    await seedRoom(twoPlayers);
    await staleBeat('owner');
    await assertFails(claim(as('stranger'), 'stranger'));
  });

  it('a member cannot hand the room to someone else or change other fields', async () => {
    await seedRoom(twoPlayers);
    await staleBeat('owner');
    await assertFails(claim(as('u2'), 'u3'));
    await assertFails(claim(as('u2'), 'u2', { status: 'playing' }));
    await assertFails(claim(as('u2'), 'u2', { settings: settings({ goAmount: 1 }) }));
  });
});

describe('a person who lost their identity leaves an old member document', () => {
  const takeoverAndRemove = (db, newUid, oldUid, seatId) => {
    const batch = writeBatch(db);
    batch.update(seat(db, seatId), { uid: newUid });
    batch.set(member(db, newUid), memberData('เพื่อน', { seat: seatId }));
    batch.delete(member(db, oldUid));
    return batch.commit();
  };

  it('is removed in the same batch as the takeover', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await staleBeat('u2');
    await assertSucceeds(takeoverAndRemove(as('u9'), 'u9', 'u2', 'p2'));
  });

  it('cannot be removed while its seat still belongs to it', async () => {
    await seedRoom(twoPlayers);
    await assertFails(deleteDoc(member(as('owner'), 'u2')));
    await assertFails(deleteDoc(member(as('u2'), 'u2')));
  });

  it('cannot be removed by a person who does not hold the seat now', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await staleBeat('u2');
    const db = as('stranger');
    const batch = writeBatch(db);
    batch.update(seat(db, 'p2'), { uid: 'stranger' });
    batch.delete(member(db, 'u2'));
    await assertFails(batch.commit());
  });

  it('a leftover one is removed by the seat holder later, not by a third person', async () => {
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await staleBeat('u2');
    const db = as('u9');
    const batch = writeBatch(db);
    batch.update(seat(db, 'p2'), { uid: 'u9' });
    batch.set(member(db, 'u9'), memberData('เพื่อน', { seat: 'p2' }));
    await batch.commit();
    await assertFails(deleteDoc(member(as('owner'), 'u2')));
    await assertSucceeds(deleteDoc(member(as('u9'), 'u2')));
  });

  it('a spectator document is not removable', async () => {
    await seedRoom();
    await admin((db) =>
      setDoc(member(db, 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null })),
    );
    await assertFails(deleteDoc(member(as('s1'), 's1')));
    await assertFails(deleteDoc(member(as('owner'), 's1')));
  });
});

// ---- the money entries: the experiment that decides how the app submits them

const entryDoc = (db, id, code = CODE) => doc(db, 'rooms', code, 'entries', String(id));

/** A stored entry as the app writes it (the layout of RoomEntry.toMap). */
const entryData = (over = {}) => ({
  v: 1,
  seq: 0,
  by: 'owner',
  seat: 'p1',
  at: serverTimestamp(),
  kind: 'receive',
  from: 'bank',
  to: 'p1',
  amount: 100,
  reason: 'ค่าเช่า',
  cid: 'abcdefghij0123456789',
  voided: false,
  ...over,
});

/** A game of four that has just started: state/current at seq 0. */
async function seedPlaying({ settingsOver = {}, balances, seats = ['p1', 'p2', 'p3', 'p4'] } = {}) {
  await seedRoom({
    status: 'playing',
    seats: ['owner', 'u2', 'u3', 'u4'],
    metaOver: { settings: settings({ maxPlayers: 4, ...settingsOver }) },
  });
  await admin((db) =>
    setDoc(
      stateDoc(db),
      stateData({
        seats,
        balances: balances ?? Object.fromEntries(seats.map((s) => [s, 1500])),
      }),
    ),
  );
}

const seatOf = { owner: 'p1', u2: 'p2', u3: 'p3', u4: 'p4' };

/** Reads a document past the rules (the admin helper does not return values). */
async function adminGet(ref) {
  let snap;
  await env.withSecurityRulesDisabled(async (ctx) => {
    snap = await getDoc(ref(ctx.firestore()));
  });
  return snap;
}

/**
 * One press the way the app does it: a transaction that reads the state and
 * the entry it is about to write, then writes the entry and the new state.
 * [tried] is told which seq the press was built on.
 */
function press(uid, { amount = 100, kind = 'receive', reason = 'ค่าเช่า', tried } = {}) {
  const db = as(uid);
  const seat = seatOf[uid];
  return runTransaction(db, async (tx) => {
    const st = await tx.get(stateDoc(db));
    const seq = st.data().seq;
    tried?.(seq);
    const free = await tx.get(entryDoc(db, seq));
    if (free.exists()) throw new Error('entry exists');
    const balances = { ...st.data().balances };
    if (kind === 'receive') balances[seat] += amount;
    if (kind === 'payBank') balances[seat] -= amount;
    if ('bank' in balances) balances.bank += kind === 'receive' ? -amount : amount;
    tx.set(
      entryDoc(db, seq),
      entryData({
        seq,
        by: uid,
        seat,
        kind,
        from: kind === 'payBank' ? seat : 'bank',
        to: kind === 'payBank' ? 'bank' : seat,
        amount,
        reason: kind === 'payBank' ? null : reason,
        cid: `cid-${uid}-${Math.random().toString(36).slice(2, 12)}`,
      }),
    );
    tx.update(stateDoc(db), { seq: seq + 1, balances });
  });
}

/**
 * What the app has to do with a refusal: when the state moved on since the
 * press was built, the refusal was the race, so build the press again; a
 * refusal on a state that did not move is a real refusal. Finding the entry
 * of the seq already there is the same race, seen from inside.
 */
async function pressWithRetry(uid, opts = {}, { attempts = 12 } = {}) {
  for (let attempt = 1; ; attempt++) {
    let triedSeq = -1;
    try {
      await press(uid, { ...opts, tried: (seq) => (triedSeq = seq) });
      return { attempts: attempt };
    } catch (e) {
      // The entry of this seq already exists: the two reads of the transaction
      // straddled another press (the emulator does not keep them consistent).
      if (e?.message === 'entry exists' && attempt < attempts) continue;
      const refused = e?.code === 'permission-denied';
      if (!refused || attempt >= attempts) throw e;
      const now = (await getDoc(stateDoc(as(uid)))).data();
      if (now.seq === triedSeq) throw e;
    }
  }
}

describe('pressing at the same time', () => {
  it('one press writes the entry and moves the state', async () => {
    await seedPlaying();
    await assertSucceeds(press('owner', { amount: 250 }));
    const state = (await adminGet(stateDoc)).data();
    assert.equal(state.seq, 1);
    assert.equal(state.balances.p1, 1750);
    const entry = (await adminGet((db) => entryDoc(db, 0))).data();
    assert.equal(entry.amount, 250);
  });

  async function checkBooks(presses, results) {
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    const state = (await adminGet(stateDoc)).data();
    assert.equal(state.seq, ok, 'the state counts the presses that went through');
    const books = { p1: 1500, p2: 1500, p3: 1500, p4: 1500 };
    for (let seq = 0; seq < ok; seq++) {
      const e = await adminGet((db) => entryDoc(db, seq));
      assert.ok(e.exists(), `entry ${seq} exists`);
      books[e.data().seat] += e.data().amount;
    }
    assert.ok(!(await adminGet((db) => entryDoc(db, ok))).exists(), 'no entry beyond the state');
    assert.deepEqual(state.balances, books);
    return ok;
  }

  it('eight presses at once, each retried after a race, all go through with matching books', async () => {
    await seedPlaying();
    const who = ['owner', 'u2', 'u3', 'u4', 'owner', 'u2', 'u3', 'u4'];
    const results = await Promise.allSettled(
      who.map((uid, i) => pressWithRetry(uid, { amount: 100 + i })),
    );
    const attempts = results.map((r) => (r.status === 'fulfilled' ? r.value.attempts : `lost: ${r.reason?.code}`));
    console.log(`    attempts per press: ${JSON.stringify(attempts)}`);
    const ok = await checkBooks(8, results);
    assert.equal(ok, 8, 'every press goes through');
  });

  it('a hundred presses in waves of eight keep the books', async () => {
    await seedPlaying();
    const all = [];
    for (let wave = 0; wave < 12; wave++) {
      const who = ['owner', 'u2', 'u3', 'u4', 'owner', 'u2', 'u3', 'u4'];
      all.push(
        ...(await Promise.allSettled(who.map((uid, i) => pressWithRetry(uid, { amount: 10 + i + wave })))),
      );
    }
    const lost = all.filter((r) => r.status === 'rejected').map((r) => `${r.reason?.code}: ${String(r.reason?.message).slice(0, 160)}`);
    console.log(`    ${all.length} presses, lost: ${JSON.stringify(lost)}`);
    const ok = await checkBooks(all.length, all);
    assert.equal(ok, all.length);
  });
});
