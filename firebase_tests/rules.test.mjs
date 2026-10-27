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
  deleteField,
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
    // Ending goes with the state and the time of the server (see "ending a game").
    await assertFails(updateDoc(room(owner), { status: 'ended' }));
    await admin((db) => updateDoc(room(db), { status: 'ended' }));
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
    await assertFails(updateDoc(room(owner), { status: 'ended' }));
  });

  it('the owner may change settings while in the lobby', async () => {
    await seedRoom();
    await assertSucceeds(updateDoc(room(as('owner')), { settings: settings({ goAmount: 300 }) }));
    await assertFails(updateDoc(room(as('stranger')), { settings: settings({ goAmount: 1 }) }));
  });

  it('a room cannot be deleted by a player, nor by its owner once it has started', async () => {
    await seedRoom({ status: 'playing' });
    await assertFails(deleteDoc(room(as('owner'))));
    await assertFails(deleteDoc(room(as('stranger'))));
  });
});

describe('creating a room with a password', () => {
  /** What the app writes when the owner opens a room: room, seat, member, presence. */
  function createRoomBatch(db, code, { memberOver = {}, roomOver = {} } = {}) {
    const batch = writeBatch(db);
    batch.set(room(db, code), metaData({ hasPassword: true, passwordHash: HASH, ...roomOver }));
    batch.set(seat(db, 'p1', code), seatData('owner'));
    batch.set(member(db, 'owner', code), memberData('เจ้าของ', memberOver));
    batch.set(presence(db, 'owner', code), { lastSeen: serverTimestamp() });
    return batch.commit();
  }

  it('the owner proves the password in their own member document too', async () => {
    await assertSucceeds(createRoomBatch(as('owner'), 'PASS22', { memberOver: { pwHash: HASH } }));
  });

  it('an owner who does not prove it is refused (the bug of the first release)', async () => {
    await assertFails(createRoomBatch(as('owner'), 'PASS23'));
  });

  it('an owner who proves it with another hash is refused', async () => {
    await assertFails(createRoomBatch(as('owner'), 'PASS24', { memberOver: { pwHash: 'b'.repeat(64) } }));
  });

  it('a room without a password needs no proof', async () => {
    await assertSucceeds(
      createRoomBatch(as('owner'), 'OPEN22', { roomOver: { hasPassword: false, passwordHash: null } }),
    );
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
    await assertFails(deleteDoc(member(as('u2'), 'u2')));
    await seedRoom({ ...twoPlayers, status: 'playing' });
    await assertFails(deleteDoc(member(as('owner'), 'u2')));
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
    await admin((db) => updateDoc(room(db), { status: 'playing' }));
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
async function seedPlaying({ settingsOver = {}, balances, seats = ['p1', 'p2', 'p3', 'p4'], stateOver = {} } = {}) {
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
        ...stateOver,
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

// ---- the rules of entries and of the state that moves with them

const BASE = { p1: 1500, p2: 1500, p3: 1500, p4: 1500 };
const uidOfSeat = { p1: 'owner', p2: 'u2', p3: 'u3', p4: 'u4' };

/** What one press of [kind] by [seat] writes, starting from the books [base]. */
function spec(kind, seat = 'p1', amount = 100, base = BASE) {
  const delta = kind === 'payBank' ? -amount : amount;
  const balances = { ...base, [seat]: base[seat] + delta };
  if ('bank' in base) balances.bank = base.bank - delta;
  const entry = {
    seat,
    kind,
    from: kind === 'payBank' ? seat : 'bank',
    to: kind === 'payBank' ? 'bank' : seat,
    amount,
    reason: kind === 'receive' ? 'ค่าเช่า' : kind === 'passGo' ? 'ผ่านจุดเริ่ม' : null,
  };
  return { entry, balances };
}
const receive = (...a) => spec('receive', ...a);
const passGo = (seat = 'p1', base = BASE) => spec('passGo', seat, 200, base);
const payBank = (...a) => spec('payBank', ...a);

/**
 * Writes an entry and the new state in one batch, as the app's transaction
 * does, with anything spoiled on request: [entry] and [stateExtra] are merged
 * over the good values, [drop] removes keys of the entry, [id] is the document
 * name, [skipEntry]/[skipState] leave one of the two writes out.
 */
function put(uid, s, { entry = {}, balances, stateExtra = {}, seqAfter = 1, id, drop = [], skipEntry = false, skipState = false } = {}) {
  const db = as(uid);
  const e = entryData({ seq: 0, by: uid, ...s.entry, ...entry });
  for (const key of drop) delete e[key];
  const batch = writeBatch(db);
  if (!skipEntry) batch.set(entryDoc(db, id ?? e.seq), e);
  if (!skipState) batch.update(stateDoc(db), { seq: seqAfter, balances: balances ?? s.balances, ...stateExtra });
  return batch.commit();
}
const asSeat = (s) => uidOfSeat[s.entry.seat];

describe('entries: what is accepted', () => {
  it('a receive with a reason, a pass over GO and a payment to the bank', async () => {
    await seedPlaying();
    await assertSucceeds(put('owner', receive('p1', 300)));
    await assertSucceeds(put('u2', passGo('p2', { ...BASE, p1: 1800 }), { entry: { seq: 1 }, id: 1, seqAfter: 2, balances: { ...BASE, p1: 1800, p2: 1700 } }));
    await assertSucceeds(
      put('u3', payBank('p3', 500, { ...BASE, p1: 1800, p2: 1700 }), {
        entry: { seq: 2 },
        id: 2,
        seqAfter: 3,
        balances: { p1: 1800, p2: 1700, p3: 1000, p4: 1500 },
      }),
    );
  });

  it('every one of the four players can press for their own seat', async () => {
    await seedPlaying();
    for (const [i, [seat, uid]] of Object.entries(uidOfSeat).entries()) {
      const base = (await adminGet(stateDoc)).data().balances;
      const s = receive(seat, 10, base);
      await assertSucceeds(put(uid, s, { entry: { seq: i }, id: i, seqAfter: i + 1 }));
    }
  });

  it('a payment may spend everything and leave 0', async () => {
    await seedPlaying();
    await assertSucceeds(put('owner', payBank('p1', 1500)));
  });

  it('the largest amount, 999,999,999, is allowed', async () => {
    await seedPlaying();
    await assertSucceeds(put('owner', receive('p1', 999999999)));
  });

  it('a reason of 60 units is allowed: 60 letters, 30 emoji, Thai', async () => {
    for (const [i, reason] of ['x'.repeat(60), '😀'.repeat(30), 'ก'.repeat(60)].entries()) {
      await env.clearFirestore();
      await seedPlaying();
      await assertSucceeds(put('owner', receive('p1', 100), { entry: { reason } }), `case ${i}`);
    }
  });

  it('a press code of 8 to 40 characters is allowed', async () => {
    for (const cid of ['abcdefgh', 'x'.repeat(40)]) {
      await env.clearFirestore();
      await seedPlaying();
      await assertSucceeds(put('owner', receive('p1', 100), { entry: { cid } }), cid);
    }
  });

  it('a payment may carry a reason or none', async () => {
    await seedPlaying();
    await assertSucceeds(put('owner', payBank('p1', 100), { entry: { reason: 'ภาษี' } }));
    await env.clearFirestore();
    await seedPlaying();
    await assertSucceeds(put('owner', payBank('p1', 100), { entry: { reason: null } }));
  });
});

describe('entries: what is refused', () => {
  const refuse = (title, run, setup) =>
    it(title, async () => {
      await (setup ?? seedPlaying)();
      await assertFails(run());
    });

  describe('the numbers', () => {
    refuse('the balance moves by more than the amount', () => put('owner', receive('p1', 100), { balances: { ...BASE, p1: 1601 } }));
    refuse('the balance moves by less than the amount', () => put('owner', receive('p1', 100), { balances: { ...BASE, p1: 1599 } }));
    refuse('the balance does not move at all', () => put('owner', receive('p1', 100), { balances: BASE }));
    refuse('the money goes to somebody else', () => put('owner', receive('p1', 100), { balances: { ...BASE, p2: 1600 } }));
    refuse('another seat changes too', () => put('owner', receive('p1', 100), { balances: { ...BASE, p1: 1600, p2: 1501 } }));
    refuse('a payment adds to the balance', () => put('owner', payBank('p1', 100), { balances: { ...BASE, p1: 1600 } }));
    refuse('a payment of more than the seat has', () => put('owner', payBank('p1', 2000)));
    refuse('a seat is added to the balances', () => put('owner', receive('p1', 100), { balances: { ...BASE, p1: 1600, p9: 5 } }));
    refuse('a seat is removed from the balances', () => {
      const { p4, ...rest } = BASE;
      void p4;
      return put('owner', receive('p1', 100), { balances: { ...rest, p1: 1600 } });
    });
    refuse('a balance that is not a whole number', () => put('owner', receive('p1', 100.5), { balances: { ...BASE, p1: 1600.5 } }));
    refuse('an amount of 0', () => put('owner', receive('p1', 0)));
    refuse('a negative amount', () => put('owner', receive('p1', -100)));
    refuse('an amount over 999,999,999', () => put('owner', receive('p1', 1000000000)));
    refuse('an amount that is text', () => put('owner', receive('p1', 100), { entry: { amount: '100' } }));
    refuse('balances that are not a map', () => put('owner', receive('p1', 100), { balances: [1, 2, 3, 4] }));
  });

  describe('the bank', () => {
    const limited = (bank = 5000) => () =>
      seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: { ...BASE, bank } });
    const withBank = (bank = 5000) => ({ ...BASE, bank });

    it('a room with a limited bank: the bank pays and receives the same amount', async () => {
      await limited()();
      await assertSucceeds(put('owner', receive('p1', 100, withBank())));
      await assertSucceeds(
        put('u2', payBank('p2', 300, { ...BASE, p1: 1600, bank: 4900 }), {
          entry: { seq: 1 },
          id: 1,
          seqAfter: 2,
          balances: { p1: 1600, p2: 1200, p3: 1500, p4: 1500, bank: 5200 },
        }),
      );
    });
    refuse('a receive that leaves the bank as it was', () => put('owner', receive('p1', 100, withBank()), { balances: { ...BASE, p1: 1600, bank: 5000 } }), limited());
    refuse('a receive that takes the wrong sum out of the bank', () => put('owner', receive('p1', 100, withBank()), { balances: { ...BASE, p1: 1600, bank: 4800 } }), limited());
    refuse('a payment that does not reach the bank', () => put('owner', payBank('p1', 100, withBank()), { balances: { ...BASE, p1: 1400, bank: 5000 } }), limited());
    refuse('the bank key is removed', () => put('owner', receive('p1', 100), { balances: { ...BASE, p1: 1600 } }), limited());
    refuse('more than the bank holds', () => put('owner', receive('p1', 100, withBank(50))), limited(50));
    refuse('a bank that holds a decimal', () => put('owner', receive('p1', 100, withBank()), { balances: { ...BASE, p1: 1600, bank: 4900.5 } }), limited());
    refuse('a bank key appears in a room whose bank has no limit', () => put('owner', receive('p1', 100), { balances: { ...BASE, p1: 1600, bank: 4900 } }));
  });

  describe('who presses', () => {
    refuse('for a seat that is not theirs', () => put('owner', receive('p2', 100)));
    refuse('under somebody else\'s uid', () => put('owner', receive('p1', 100), { entry: { by: 'u2' } }));
    refuse('a person who is not in the room', () => put('stranger', receive('p1', 100), { entry: { by: 'stranger' } }));
    refuse('a person who is not signed in', () => {
      const db = anonymous();
      const batch = writeBatch(db);
      const s = receive('p1', 100);
      batch.set(entryDoc(db, 0), entryData({ seq: 0, by: 'owner', ...s.entry }));
      batch.update(stateDoc(db), { seq: 1, balances: s.balances });
      return batch.commit();
    });
    refuse('a spectator', async () => {
      await admin((db) => setDoc(member(db, 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null })));
      return put('s1', receive('p1', 100), { entry: { by: 's1' } });
    });
    refuse('a seat that is not in the game', () => put('u3', receive('p3', 100)), () =>
      seedPlaying({ seats: ['p1', 'p2'], balances: BASE }));
    refuse('a seat that has gone bankrupt', () => put('u2', receive('p2', 100)), () =>
      seedPlaying({ stateOver: { bankrupt: ['p2'] } }));
    refuse('a seat that is made up', () => put('owner', receive('p1', 100), { entry: { seat: 'p9' } }));
  });

  describe('when', () => {
    refuse('before the game started (no state yet)', () => put('owner', receive('p1', 100)), () => seedRoom({ seats: ['owner', 'u2'] }));
    refuse('after the room has ended', () => put('owner', receive('p1', 100)), async () => {
      await seedPlaying();
      await admin((db) => updateDoc(room(db), { status: 'ended' }));
    });
    refuse('a seq that skips ahead', () => put('owner', receive('p1', 100), { entry: { seq: 1 }, id: 1, seqAfter: 2 }));
    it('a seq that was used already', async () => {
      await seedPlaying();
      await assertSucceeds(put('owner', receive('p1', 100)));
      await assertFails(
        put('u2', receive('p2', 100, { ...BASE, p1: 1600 }), { balances: { ...BASE, p1: 1600, p2: 1600 } }),
      );
    });
    refuse('a document name that is not the seq', () => put('owner', receive('p1', 100), { id: 'first' }));
    refuse('a document name with a leading zero', () => put('owner', receive('p1', 100), { id: '00' }));
    refuse('a seq that is text', () => put('owner', receive('p1', 100), { entry: { seq: '0' }, id: '0' }));
    refuse('a seq that is not a whole number', () => put('owner', receive('p1', 100), { entry: { seq: 0.5 }, id: '0.5' }));
    refuse('a state that jumps two steps', () => put('owner', receive('p1', 100), { seqAfter: 2 }));
    refuse('a state that goes back', () => put('owner', receive('p1', 100), { seqAfter: 0 }));
    refuse('an entry that is not stamped with the server time', () => put('owner', receive('p1', 100), { entry: { at: Timestamp.now() } }));
  });

  describe('the entry as a whole', () => {
    refuse('a key too many', () => put('owner', receive('p1', 100), { entry: { surprise: 1 } }));
    for (const key of ['v', 'seq', 'by', 'seat', 'at', 'kind', 'from', 'to', 'amount', 'reason', 'cid', 'voided']) {
      refuse(`the key ${key} left out`, () => put('owner', receive('p1', 100), { drop: [key], id: 0 }));
    }
    refuse('version 2', () => put('owner', receive('p1', 100), { entry: { v: 2 } }));
    refuse('an entry that is already undone', () => put('owner', receive('p1', 100), { entry: { voided: true } }));
    refuse('a press code that is too short', () => put('owner', receive('p1', 100), { entry: { cid: 'short' } }));
    refuse('a press code of 41 characters', () => put('owner', receive('p1', 100), { entry: { cid: 'x'.repeat(41) } }));
    refuse('a pass over GO that does not come from the bank', () => put('owner', passGo('p1'), { entry: { from: 'p2' } }));
    refuse('a payment of a kind that does not exist', () => put('owner', payBank('p1', 100), { entry: { kind: 'gift' } }));
    refuse('a payment in the shape of a transfer', () => put('owner', payBank('p1', 100), { entry: { kind: 'transfer' } }));
    refuse('a press code that is not text', () => put('owner', receive('p1', 100), { entry: { cid: 12345678 } }));
    refuse('a kind this slice does not have: mortgage', () => put('owner', { entry: { seat: 'p1', kind: 'mortgage', from: 'bank', to: 'p1', amount: 100, reason: 'ค่าเช่า' }, balances: { ...BASE, p1: 1600 } }));
    refuse('a kind this slice does not have: bankrupt', () => put('owner', { entry: { seat: 'p1', kind: 'bankrupt', from: null, to: null, amount: 100, reason: null }, balances: BASE }));
    refuse('a kind that does not exist', () => put('owner', receive('p1', 100), { entry: { kind: 'gift' } }));
    refuse('a receive that does not come from the bank', () => put('owner', receive('p1', 100), { entry: { from: 'p2' } }));
    refuse('a receive that goes to another seat', () => put('owner', receive('p1', 100), { entry: { to: 'p2' } }));
    refuse('a payment that goes to another seat', () => put('owner', payBank('p1', 100), { entry: { to: 'p2' } }));
    refuse('a payment from another seat', () => put('owner', payBank('p1', 100), { entry: { from: 'p2' } }));
  });

  describe('the reason', () => {
    const reasons = [
      ['missing (null)', null],
      ['empty', ''],
      ['one space', ' '],
      ['only spaces', '    '],
      ['only a tab', '\t'],
      ['61 letters', 'x'.repeat(61)],
      ['an emoji across the limit (59 letters and one emoji)', `${'x'.repeat(59)}😀`],
      ['31 emoji', '😀'.repeat(31)],
      ['a number', 5],
      ['a list', ['ค่าเช่า']],
    ];
    for (const [what, reason] of reasons) {
      refuse(`a receive with a reason that is ${what}`, () => put('owner', receive('p1', 100), { entry: { reason } }));
    }
    refuse('a payment with a reason that is only spaces', () => put('owner', payBank('p1', 100), { entry: { reason: '   ' } }));
    refuse('a payment with an empty reason', () => put('owner', payBank('p1', 100), { entry: { reason: '' } }));
    refuse('a payment with a reason over the limit', () => put('owner', payBank('p1', 100), { entry: { reason: 'x'.repeat(61) } }));
    refuse('a pass over GO with another reason', () => put('owner', passGo('p1'), { entry: { reason: 'โบนัส' } }));
    refuse('a pass over GO without a reason', () => put('owner', passGo('p1'), { entry: { reason: null } }));
    refuse('a pass over GO of another amount', () => put('owner', spec('passGo', 'p1', 201)));
    refuse('a pass over GO of 0', () => put('owner', spec('passGo', 'p1', 0)));
  });
});

describe('the state moves only with its entry', () => {
  it('a state update without an entry', async () => {
    await seedPlaying();
    await assertFails(put('owner', receive('p1', 100), { skipEntry: true }));
  });

  it('an entry without a state update', async () => {
    await seedPlaying();
    await assertFails(put('owner', receive('p1', 100), { skipState: true }));
  });

  it('a state update that also changes something else', async () => {
    for (const stateExtra of [{ status: 'ended' }, { bankrupt: ['p2'] }, { seats: ['p1'] }, { bankerSeat: 'p1' }, { v: 2 }]) {
      await env.clearFirestore();
      await seedPlaying();
      await assertFails(put('owner', receive('p1', 100), { stateExtra }), JSON.stringify(stateExtra));
    }
  });

  it('after a press neither the entry nor the state can be changed or deleted', async () => {
    await seedPlaying();
    await assertSucceeds(put('owner', receive('p1', 100)));
    const db = as('owner');
    await assertFails(updateDoc(entryDoc(db, 0), { amount: 1 }));
    await assertFails(updateDoc(entryDoc(db, 0), { voided: true }));
    await assertFails(deleteDoc(entryDoc(db, 0)));
    await assertFails(deleteDoc(stateDoc(db)));
    await assertFails(updateDoc(stateDoc(db), { seq: 2, balances: { ...BASE, p1: 1700 } }));
    await assertFails(setDoc(entryDoc(db, 0), entryData({ seq: 0, amount: 1 })));
  });

  it('a stranger cannot move the state by writing the entry of somebody else', async () => {
    await seedPlaying();
    const db = as('stranger');
    const batch = writeBatch(db);
    const s = receive('p1', 100);
    batch.set(entryDoc(db, 0), entryData({ seq: 0, by: 'stranger', ...s.entry }));
    batch.update(stateDoc(db), { seq: 1, balances: s.balances });
    await assertFails(batch.commit());
  });
});

// ---- transfers and taking back an entry

/** A transfer of [amount] from seat [from] to seat [to], from the books [base]. */
function transfer(from = 'p1', to = 'p2', amount = 100, base = BASE) {
  return {
    entry: { seat: from, kind: 'transfer', from, to, amount, reason: null },
    balances: { ...base, [from]: base[from] - amount, [to]: base[to] + amount },
  };
}

describe('transfers: what is accepted', () => {
  it('one player gives another some money', async () => {
    await seedPlaying();
    await assertSucceeds(put('owner', transfer('p1', 'p2', 700)));
    const state = (await adminGet(stateDoc)).data();
    assert.deepEqual(state.balances, { ...BASE, p1: 800, p2: 2200 });
  });

  it('every player can give to every other player', async () => {
    await seedPlaying();
    let seq = 0;
    let base = { ...BASE };
    for (const [from, uid] of Object.entries(uidOfSeat)) {
      for (const to of Object.keys(uidOfSeat).filter((t) => t !== from)) {
        const s = transfer(from, to, 10, base);
        await assertSucceeds(put(uid, s, { entry: { seq }, id: seq, seqAfter: seq + 1 }), `${from} to ${to}`);
        base = s.balances;
        seq++;
      }
    }
  });

  it('a transfer may spend everything, may be the largest amount, may say why', async () => {
    await seedPlaying({ balances: { p1: 999999999, p2: 1, p3: 1500, p4: 1500 } });
    await assertSucceeds(
      put('owner', transfer('p1', 'p2', 999999999, { p1: 999999999, p2: 1, p3: 1500, p4: 1500 }), {
        entry: { reason: 'ตามคำขอเรียกเก็บ' },
      }),
    );
  });

  it('in a room with a bank limit the bank does not move', async () => {
    const base = { ...BASE, bank: 5000 };
    await seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: base });
    await assertSucceeds(put('owner', transfer('p1', 'p2', 100, base)));
  });
});

describe('transfers: what is refused', () => {
  const refuse = (title, run, setup) =>
    it(title, async () => {
      await (setup ?? seedPlaying)();
      await assertFails(run());
    });
  const base = BASE;

  refuse('to yourself', () => put('owner', transfer('p1', 'p1', 100)));
  refuse('to the bank', () => put('owner', { entry: { seat: 'p1', kind: 'transfer', from: 'p1', to: 'bank', amount: 100, reason: null }, balances: { ...base, p1: 1400 } }));
  refuse('to a seat that is not in the game', () => put('owner', { entry: { seat: 'p1', kind: 'transfer', from: 'p1', to: 'p9', amount: 100, reason: null }, balances: { ...base, p1: 1400, p9: 100 } }));
  refuse('with no one to give to', () => put('owner', transfer('p1', 'p2', 100), { entry: { to: null } }));
  refuse('to a player who is out', () => put('owner', transfer('p1', 'p2', 100)), () => seedPlaying({ stateOver: { bankrupt: ['p2'] } }));
  refuse('from a player who is out', () => put('owner', transfer('p1', 'p2', 100)), () => seedPlaying({ stateOver: { bankrupt: ['p1'] } }));
  refuse('more than the giver has', () => put('owner', transfer('p1', 'p2', 1501)));
  refuse('with the money going to somebody else', () => put('owner', transfer('p1', 'p2', 100), { balances: { ...base, p1: 1400, p3: 1600 } }));
  refuse('with the receiver getting too much', () => put('owner', transfer('p1', 'p2', 100), { balances: { ...base, p1: 1400, p2: 1601 } }));
  refuse('with a third seat moving as well', () => put('owner', transfer('p1', 'p2', 100), { balances: { ...base, p1: 1400, p2: 1600, p3: 1501 } }));
  refuse('with the giver paying too little', () => put('owner', transfer('p1', 'p2', 100), { balances: { ...base, p1: 1450, p2: 1600 } }));
  refuse('when the giver is not the one who presses', () => put('u2', transfer('p1', 'p2', 100)));
  refuse('when from is not the pressing seat', () => put('owner', transfer('p1', 'p2', 100), { entry: { from: 'p3' } }));
  refuse('with a reason that is only spaces', () => put('owner', transfer('p1', 'p2', 100), { entry: { reason: '   ' } }));
  refuse('an amount of 0', () => put('owner', transfer('p1', 'p2', 0)));
  refuse('a fractional amount', () => put('owner', transfer('p1', 'p2', 10.5)));
  refuse('moving the bank', () => put('owner', transfer('p1', 'p2', 100, { ...base, bank: 5000 }), { balances: { ...base, p1: 1400, p2: 1600, bank: 5100 } }), () => seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: { ...base, bank: 5000 } }));
});

/**
 * A game with one press already in (past the rules): [s] describes it, the
 * state is what it left, and the entry is dated [at] by the server clock.
 */
async function seedOnePress(s, { at = Timestamp.now(), seedOver = {}, entryOver = {}, extra = false } = {}) {
  await seedPlaying(seedOver);
  await admin(async (db) => {
    await setDoc(entryDoc(db, 0), entryData({ seq: 0, by: uidOfSeat[s.entry.seat], at, ...s.entry, ...entryOver }));
    await setDoc(stateDoc(db), stateData({ seats: ['p1', 'p2', 'p3', 'p4'], seq: 1, balances: s.balances, ...(seedOver.stateOver ?? {}) }));
    if (extra) {
      // a later press by somebody else, so entry 0 is no longer the latest
      const later = receive('p4', 10, s.balances);
      await setDoc(entryDoc(db, 1), entryData({ seq: 1, by: 'u4', at: Timestamp.now(), ...later.entry }));
      await setDoc(stateDoc(db), stateData({ seats: ['p1', 'p2', 'p3', 'p4'], seq: 2, balances: later.balances }));
    }
  });
}

/** Takes entry [id] back and gives the balances back, in one batch. */
function takeBack(uid, { id = 0, entry = {}, balances = BASE, stateExtra = {}, skipEntry = false, skipState = false } = {}) {
  const db = as(uid);
  const batch = writeBatch(db);
  if (!skipEntry) batch.update(entryDoc(db, id), { voided: true, ...entry });
  if (!skipState) batch.update(stateDoc(db), { balances, ...stateExtra });
  return batch.commit();
}

describe('taking back an entry: what is accepted', () => {
  it('a receive, a pass over GO, a payment and a transfer, each by its owner', async () => {
    const cases = [
      [receive('p1', 300), 'owner'],
      [passGo('p1'), 'owner'],
      [payBank('p1', 500), 'owner'],
      [transfer('p1', 'p2', 700), 'owner'],
      [receive('p3', 300), 'u3'],
    ];
    for (const [s, uid] of cases) {
      await env.clearFirestore();
      await seedOnePress(s);
      await assertSucceeds(takeBack(uid), `${s.entry.kind} by ${uid}`);
      const e = (await adminGet((db) => entryDoc(db, 0))).data();
      assert.equal(e.voided, true);
      const state = (await adminGet(stateDoc)).data();
      assert.equal(state.seq, 1, 'the counter does not move');
      assert.deepEqual(state.balances, BASE);
    }
  });

  it('in a room with a bank limit the bank gets its share back', async () => {
    const base = { ...BASE, bank: 5000 };
    const s = receive('p1', 300, base);
    await seedOnePress(s, { seedOver: { settingsOver: { bankLimit: 5000 }, balances: base } });
    await assertSucceeds(takeBack('owner', { balances: base }));
  });

  it('after taking back, the next press goes in as the entry after it', async () => {
    await seedOnePress(receive('p1', 300));
    await assertSucceeds(takeBack('owner'));
    const next = receive('p2', 50);
    await assertSucceeds(put('u2', next, { entry: { seq: 1 }, id: 1, seqAfter: 2 }));
    const entries = [(await adminGet((db) => entryDoc(db, 0))).data(), (await adminGet((db) => entryDoc(db, 1))).data()];
    assert.deepEqual(entries.map((e) => e.voided), [true, false]);
  });

  it('just inside the 6.5 seconds', async () => {
    await seedOnePress(receive('p1', 300), { at: Timestamp.fromMillis(Date.now() - 4000) });
    await assertSucceeds(takeBack('owner'));
  });
});

describe('taking back an entry: what is refused', () => {
  const refuse = (title, setup, run) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });
  const one = (s = receive('p1', 300), opts = {}) => () => seedOnePress(s, opts);

  refuse('somebody else\'s entry', one(), () => takeBack('u2'));
  refuse('by a stranger', one(), () => takeBack('stranger'));
  refuse('an entry that is not the latest', one(receive('p1', 300), { extra: true }), () => takeBack('owner', { balances: { ...BASE, p4: 1510 } }));
  refuse('after 6.5 seconds', one(receive('p1', 300), { at: Timestamp.fromMillis(Date.now() - 9000) }), () => takeBack('owner'));
  refuse('a transfer that paid a request to pay', one(transfer('p1', 'p2', 300), { entryOver: { reason: 'ตามคำขอเรียกเก็บ' } }), () => takeBack('owner', { balances: BASE }));
  refuse('an entry already taken back', one(receive('p1', 300), { entryOver: { voided: true } }), () => takeBack('owner'));
  refuse('when the game is not being played', one(receive('p1', 300), { seedOver: {} }), async () => {
    await admin((db) => updateDoc(room(db), { status: 'ended' }));
    return takeBack('owner');
  });
  refuse('a kind that is not taken back here (mortgage)', one({ entry: { seat: 'p1', kind: 'mortgage', from: 'bank', to: 'p1', amount: 300, reason: 'x' }, balances: { ...BASE, p1: 1800 } }), () => takeBack('owner'));
  refuse('changing the amount at the same time', one(), () => takeBack('owner', { entry: { amount: 1 } }));
  refuse('changing who pressed at the same time', one(), () => takeBack('owner', { entry: { by: 'u2' } }));
  refuse('taking it back without giving the balances back', one(), () => takeBack('owner', { balances: { ...BASE, p1: 1800 } }));
  refuse('giving back too little', one(), () => takeBack('owner', { balances: { ...BASE, p1: 1510 } }));
  refuse('giving back to somebody else', one(), () => takeBack('owner', { balances: { ...BASE, p1: 1500, p2: 1300 } }));
  refuse('giving back so that a balance goes below zero', one(payBank('p1', 1500)), () => takeBack('owner', { balances: { ...BASE, p1: 3000 } }));
  refuse('a transfer whose receiver no longer holds the money', one(transfer('p1', 'p2', 700), { seedOver: { stateOver: {} } }), async () => {
    await admin((db) => updateDoc(stateDoc(db), { balances: { ...BASE, p1: 800, p2: 100 } }));
    return takeBack('owner');
  });
  refuse('moving the counter', one(), () => takeBack('owner', { stateExtra: { seq: 0 } }));
  refuse('changing something else of the state', one(), () => takeBack('owner', { stateExtra: { bankrupt: ['p2'] } }));
  for (const stateExtra of [{ status: 'ended' }, { seats: ['p1'] }, { bankerSeat: 'p1' }, { v: 2 }]) {
    refuse(`changing ${Object.keys(stateExtra)[0]} of the state at the same time`, one(), () => takeBack('owner', { stateExtra }));
  }
  refuse('the state alone, without taking the entry back', one(), () => takeBack('owner', { skipEntry: true }));
  refuse('the entry alone, without the balances', one(), () => takeBack('owner', { skipState: true }));
  refuse('deleting an entry', one(), () => deleteDoc(entryDoc(as('owner'), 0)));
});

describe('taking back and pressing at the same time', () => {
  it('a press and a take-back for the same moment: only one of them can go in', async () => {
    await seedOnePress(receive('p1', 300));
    const results = await Promise.allSettled([
      takeBack('owner'),
      put('u2', receive('p2', 50, { ...BASE, p1: 1800 }), { entry: { seq: 1 }, id: 1, seqAfter: 2 }),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    assert.equal(ok, 1, JSON.stringify(results.map((r) => r.status)));
    const state = (await adminGet(stateDoc)).data();
    const e0 = (await adminGet((db) => entryDoc(db, 0))).data();
    if (e0.voided) {
      assert.equal(state.seq, 1);
      assert.deepEqual(state.balances, BASE);
    } else {
      assert.equal(state.seq, 2);
      assert.deepEqual(state.balances, { ...BASE, p1: 1800, p2: 1550 });
    }
  });

  it('the same entry taken back from two places: one wins', async () => {
    await seedOnePress(receive('p1', 300));
    const results = await Promise.allSettled([takeBack('owner'), takeBack('owner')]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    assert.deepEqual((await adminGet(stateDoc)).data().balances, BASE);
  });
});

// ---- requests to pay

const reqDoc = (db, id = 'p2_p1', code = CODE) => doc(db, 'rooms', code, 'requests', id);

/** What the app writes to ask: p2 asks p1 for 300 unless told otherwise. */
const requestData = (over = {}) => ({
  fromSeat: 'p1',
  toSeat: 'p2',
  amount: 300,
  status: 'open',
  createdAt: serverTimestamp(),
  paidSeq: null,
  ...over,
});

/** A request that is already there (written past the rules). */
async function seedRequest(over = {}, { age = 0, id = 'p2_p1' } = {}) {
  await admin((db) =>
    setDoc(reqDoc(db, id), requestData({ createdAt: Timestamp.fromMillis(Date.now() - age), ...over })),
  );
}

const ask = (uid, over = {}, id = 'p2_p1') => setDoc(reqDoc(as(uid), id), requestData(over));

/** The payer pays: the transfer, the new state and the request, in one batch. */
function payRequest(uid, { id = 'p2_p1', amount = 300, from = 'p1', to = 'p2', paidSeq = 0, entry = {}, reqExtra = {}, balances, skipEntry = false, skipState = false, skipReq = false } = {}) {
  const db = as(uid);
  const t = transfer(from, to, amount);
  const batch = writeBatch(db);
  if (!skipEntry) {
    batch.set(entryDoc(db, 0), entryData({ seq: 0, by: uid, ...t.entry, reason: 'ตามคำขอเรียกเก็บ', ...entry }));
  }
  if (!skipState) batch.update(stateDoc(db), { seq: 1, balances: balances ?? t.balances });
  if (!skipReq) batch.update(reqDoc(db, id), { status: 'paid', paidSeq, ...reqExtra });
  return batch.commit();
}

describe('requests to pay: asking', () => {
  it('a player asks another for money', async () => {
    await seedPlaying();
    await assertSucceeds(ask('u2'));
    const r = (await adminGet((db) => reqDoc(db))).data();
    assert.equal(r.amount, 300);
    assert.equal(r.status, 'open');
  });

  it('every player can ask every other player, each pair has its own place', async () => {
    await seedPlaying();
    for (const [to, uid] of Object.entries(uidOfSeat)) {
      for (const from of Object.keys(uidOfSeat).filter((f) => f !== to)) {
        await assertSucceeds(ask(uid, { fromSeat: from, toSeat: to }, `${to}_${from}`), `${to} asks ${from}`);
      }
    }
  });

  it('asking again over a request that is closed', async () => {
    for (const status of ['cancelled', 'paid']) {
      await env.clearFirestore();
      await seedPlaying();
      await seedRequest({ status, paidSeq: status === 'paid' ? 0 : null });
      await assertSucceeds(ask('u2', { amount: 50 }), status);
      assert.equal((await adminGet((db) => reqDoc(db))).data().status, 'open');
    }
  });

  it('asking again over a request that has run out (2 minutes)', async () => {
    await seedPlaying();
    await seedRequest({}, { age: 3 * 60 * 1000 });
    await assertSucceeds(ask('u2', { amount: 50 }));
  });

  it('the largest amount', async () => {
    await seedPlaying();
    await assertSucceeds(ask('u2', { amount: 999999999 }));
  });
});

describe('requests to pay: asking is refused', () => {
  const refuse = (title, run, setup) =>
    it(title, async () => {
      await (setup ?? seedPlaying)();
      await assertFails(run());
    });
  const open = async () => {
    await seedPlaying();
    await seedRequest();
  };

  refuse('by somebody who is not the asker', () => ask('u3'));
  refuse('by a stranger', () => ask('stranger'));
  refuse('with the id of another pair', () => ask('u2', {}, 'p2_p3'));
  refuse('with an id that is not a pair', () => ask('u2', {}, 'abc'));
  refuse('to yourself', () => ask('u2', { fromSeat: 'p2' }, 'p2_p2'));
  refuse('of a seat that is not in the game', () => ask('u2', { fromSeat: 'p9' }, 'p2_p9'));
  refuse('of a player who is out', () => ask('u2'), () => seedPlaying({ stateOver: { bankrupt: ['p1'] } }));
  refuse('by a player who is out', () => ask('u2'), () => seedPlaying({ stateOver: { bankrupt: ['p2'] } }));
  refuse('when the game is not being played', () => ask('u2'), async () => {
    await seedRoom({ status: 'lobby', seats: ['owner', 'u2'] });
  });
  refuse('an amount of 0', () => ask('u2', { amount: 0 }));
  refuse('an amount that is too large', () => ask('u2', { amount: 1000000000 }));
  refuse('a fractional amount', () => ask('u2', { amount: 10.5 }));
  refuse('a request that is already paid', () => ask('u2', { status: 'paid', paidSeq: 0 }));
  refuse('a request that is born cancelled', () => ask('u2', { status: 'cancelled' }));
  refuse('when the game has ended', () => ask('u2'), async () => {
    await seedPlaying();
    await admin((db) => updateDoc(room(db), { status: 'ended' }));
  });
  refuse('of a seat that is not playing in this game', () => ask('u2', { fromSeat: 'p3' }, 'p2_p3'), () =>
    seedPlaying({ seats: ['p1', 'p2'], balances: { p1: 1500, p2: 1500 } }),
  );
  refuse('with a payment number', () => ask('u2', { paidSeq: 3 }));
  refuse('with a time of its own', () => ask('u2', { createdAt: Timestamp.now() }));
  refuse('with an extra field', () => ask('u2', { note: 'x' }));
  refuse('with a field missing', () => setDoc(reqDoc(as('u2')), (({ paidSeq, ...rest }) => rest)(requestData())));
  refuse('over a request that is open and fresh', () => ask('u2', { amount: 50 }), open);
  refuse('and nobody can delete one', () => deleteDoc(reqDoc(as('u2'))), open);
});

describe('requests to pay: closing', () => {
  const open = async () => {
    await seedPlaying();
    await seedRequest();
  };
  const cancel = (uid, extra = {}) => updateDoc(reqDoc(as(uid)), { status: 'cancelled', ...extra });

  it('the asker takes it back', async () => {
    await open();
    await assertSucceeds(cancel('u2'));
    assert.equal((await adminGet((db) => reqDoc(db))).data().status, 'cancelled');
  });

  it('the payer says no', async () => {
    await open();
    await assertSucceeds(cancel('owner'));
  });

  it('a third player cannot close it, nor a stranger', async () => {
    await open();
    await assertFails(cancel('u3'));
    await assertFails(cancel('stranger'));
  });

  it('a closed request cannot be closed again, a paid one cannot be cancelled', async () => {
    await seedPlaying();
    await seedRequest({ status: 'cancelled' });
    await assertFails(cancel('u2'));
    await env.clearFirestore();
    await seedPlaying();
    await seedRequest({ status: 'paid', paidSeq: 0 });
    await assertFails(cancel('u2'));
  });

  it('closing cannot change anything else', async () => {
    await open();
    await assertFails(cancel('u2', { amount: 1 }));
    await assertFails(cancel('u2', { fromSeat: 'p3' }));
    await assertFails(updateDoc(reqDoc(as('u2')), { status: 'open', amount: 1 }));
    await assertFails(updateDoc(reqDoc(as('u2')), { status: 'paid' }));
  });
});

describe('requests to pay: paying', () => {
  const open = async () => {
    await seedPlaying();
    await seedRequest();
  };

  it('the payer pays, the money moves and the request is closed', async () => {
    await open();
    await assertSucceeds(payRequest('owner'));
    const r = (await adminGet((db) => reqDoc(db))).data();
    assert.equal(r.status, 'paid');
    assert.equal(r.paidSeq, 0);
    const state = (await adminGet(stateDoc)).data();
    assert.deepEqual(state.balances, { ...BASE, p1: 1200, p2: 1800 });
  });

  it('paying the whole balance, and the largest amount', async () => {
    await seedPlaying({ balances: { p1: 999999999, p2: 1, p3: 1500, p4: 1500 } });
    await seedRequest({ amount: 999999999 });
    await assertSucceeds(
      payRequest('owner', { amount: 999999999, balances: { p1: 0, p2: 1000000000, p3: 1500, p4: 1500 } }),
    );
  });

  it('just inside the 2 minutes', async () => {
    await seedPlaying();
    await seedRequest({}, { age: 110 * 1000 });
    await assertSucceeds(payRequest('owner'));
  });

  const refuse = (title, run, setup) =>
    it(title, async () => {
      await (setup ?? open)();
      await assertFails(run());
    });

  refuse('by the asker', () => payRequest('u2'));
  refuse('leaving it open although it is paid', () => payRequest('owner', { reqExtra: { status: 'open' } }));
  refuse('by a stranger', () => payRequest('stranger'));
  refuse('after 2 minutes', () => payRequest('owner'), async () => {
    await seedPlaying();
    await seedRequest({}, { age: 125 * 1000 });
  });
  refuse('after it was cancelled', () => payRequest('owner'), async () => {
    await seedPlaying();
    await seedRequest({ status: 'cancelled' });
  });
  refuse('twice', () => payRequest('owner'), async () => {
    await seedPlaying();
    await seedRequest({ status: 'paid', paidSeq: 0 });
  });
  refuse('without the transfer', () => payRequest('owner', { skipEntry: true }));
  refuse('without the new state', () => payRequest('owner', { skipState: true }));
  refuse('with a transfer of another amount', () => payRequest('owner', { entry: { amount: 100 }, balances: { ...BASE, p1: 1400, p2: 1600 } }));
  refuse('with a transfer to somebody else', () => payRequest('owner', { entry: { to: 'p3' }, balances: { ...BASE, p1: 1200, p3: 1800 } }));
  refuse('with a transfer that is not for this reason', () => payRequest('owner', { entry: { reason: null } }));
  refuse('with the wrong number of the entry', () => payRequest('owner', { reqExtra: { paidSeq: 5 } }));
  refuse('with no number of the entry', () => payRequest('owner', { reqExtra: { paidSeq: null } }));
  refuse('changing the amount of the request too', () => payRequest('owner', { reqExtra: { amount: 1 } }));
  refuse('changing who is asked too', () => payRequest('owner', { reqExtra: { fromSeat: 'p3' } }));
  refuse('when the game is not being played', () => payRequest('owner'), async () => {
    await seedPlaying();
    await seedRequest();
    await admin((db) => updateDoc(room(db), { status: 'ended' }));
  });
  refuse('the request closed without the transfer', () => payRequest('owner', { skipEntry: true, skipState: true }));
});

describe('who reads the requests', () => {
  it('players and spectators read them, and a stranger does not', async () => {
    await seedPlaying();
    await seedRequest();
    await admin((db) => setDoc(member(db, 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null })));
    for (const uid of ['owner', 'u2', 's1']) {
      await assertSucceeds(getDoc(reqDoc(as(uid))), uid);
      await assertSucceeds(getDocs(collection(as(uid), 'rooms', CODE, 'requests')), uid);
    }
    await assertFails(getDoc(reqDoc(as('stranger'))));
    await assertFails(getDocs(collection(as('stranger'), 'rooms', CODE, 'requests')));
  });
});

describe('who reads the entries', () => {
  async function onePress() {
    await seedPlaying();
    await assertSucceeds(put('owner', receive('p1', 100)));
  }

  it('players and spectators read them, one by one and as a list', async () => {
    await onePress();
    await admin((db) => setDoc(member(db, 's1'), memberData('ผู้ชม', { role: 'spectator', seat: null })));
    for (const uid of ['owner', 'u2', 's1']) {
      await assertSucceeds(getDoc(entryDoc(as(uid), 0)), uid);
      await assertSucceeds(getDocs(collection(as(uid), 'rooms', CODE, 'entries')), uid);
    }
  });

  it('people who are not in the room cannot', async () => {
    await onePress();
    await assertFails(getDoc(entryDoc(as('stranger'), 0)));
    await assertFails(getDocs(collection(as('stranger'), 'rooms', CODE, 'entries')));
    await assertFails(getDocs(collection(anonymous(), 'rooms', CODE, 'entries')));
  });
});

// ---- 7e: a mortgage in the same press as a payment, and bankruptcy

const POOR = { ...BASE, p1: 400 };
const POOR_BANK = { ...POOR, bank: 5000 };
const bankRoom = () => seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: POOR_BANK });
const poorRoom = () => seedPlaying({ balances: POOR });

/** A payment of [amount] by [from], helped by [mortgage]: to the bank or to seat [to]. */
function mortgagePay(from, to, amount, mortgage, base = POOR) {
  const balances = { ...base, [from]: base[from] + mortgage - amount };
  if (to === 'bank') {
    if ('bank' in base) balances.bank = base.bank - mortgage + amount;
  } else {
    balances[to] = base[to] + amount;
    if ('bank' in base) balances.bank = base.bank - mortgage;
  }
  return {
    entry: { seat: from, kind: to === 'bank' ? 'payBank' : 'transfer', from, to, amount, reason: null, mortgage },
    balances,
  };
}

/** Seat [seat] goes out owing [owed] to seat [creditor] (null: the bank). */
function bankrupt(seat, creditor, owed, base = BASE, out = [], banker = null) {
  const cash = base[seat];
  const balances = { ...base, [seat]: 0 };
  if (creditor) {
    balances[creditor] = base[creditor] + owed;
    if ('bank' in base) balances.bank = base.bank - (owed - cash);
  } else if ('bank' in base) {
    balances.bank = base.bank + cash;
  }
  return {
    entry: {
      seat,
      kind: 'bankrupt',
      from: null,
      to: null,
      amount: null,
      reason: null,
      bankrupt: { seat, creditorSeat: creditor, cash, owed },
    },
    balances,
    stateExtra: { bankrupt: [...out, seat], bankerSeat: banker ?? seat },
  };
}
const goOut = (uid, s, opts = {}) => put(uid, s, { stateExtra: s.stateExtra, ...opts });

describe('a mortgage with a payment: what is accepted', () => {
  it('a payment to the bank that the cash does not cover', async () => {
    await poorRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'bank', 700, 360)));
    assert.equal((await adminGet(stateDoc)).data().balances.p1, 60);
  });

  it('a transfer that the cash does not cover', async () => {
    await poorRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'p2', 700, 360)));
    const b = (await adminGet(stateDoc)).data().balances;
    assert.deepEqual([b.p1, b.p2], [60, 2200]);
  });

  it('with a bank limit the bank pays out the mortgage and takes the payment', async () => {
    await bankRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'bank', 700, 360, POOR_BANK)));
    assert.equal((await adminGet(stateDoc)).data().balances.bank, 5000 - 360 + 700);
    await env.clearFirestore();
    await bankRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'p2', 700, 360, POOR_BANK)));
    assert.equal((await adminGet(stateDoc)).data().balances.bank, 5000 - 360);
  });

  it('what is left over may be half the starting cash, 750, exactly', async () => {
    await poorRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'bank', 700, 1050)));
    assert.equal((await adminGet(stateDoc)).data().balances.p1, 750);
  });

  it('what is left over may be more than a fifth of it, 600', async () => {
    await poorRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'bank', 700, 900)));
  });

  it('a mortgage of just what is missing', async () => {
    await poorRoom();
    await assertSucceeds(put('owner', mortgagePay('p1', 'bank', 700, 300)));
    assert.equal((await adminGet(stateDoc)).data().balances.p1, 0);
  });

  it('a bank below zero (after a bankruptcy) can still be paid', async () => {
    const base = { ...BASE, bank: -300 };
    await seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: base });
    await assertSucceeds(put('owner', payBank('p1', 100, base)));
    assert.equal((await adminGet(stateDoc)).data().balances.bank, -200);
  });
});

describe('a mortgage with a payment: what is refused', () => {
  const refuse = (title, run, setup = poorRoom) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });

  refuse('when the cash covers the payment', () => put('owner', mortgagePay('p1', 'bank', 400, 100)));
  refuse('when the cash covers it by a coin', () => put('owner', mortgagePay('p1', 'bank', 300, 100)));
  refuse('a mortgage that does not cover what is missing', () => put('owner', mortgagePay('p1', 'bank', 700, 299)));
  refuse('what is left over is 751', () => put('owner', mortgagePay('p1', 'bank', 700, 1051)));
  refuse('what is left over is 751 on a transfer', () => put('owner', mortgagePay('p1', 'p2', 700, 1051)));
  refuse('a mortgage of 0', () => put('owner', mortgagePay('p1', 'bank', 700, 0)));
  refuse('a negative mortgage', () => put('owner', mortgagePay('p1', 'bank', 700, -5)));
  refuse('a mortgage that is text', () => put('owner', mortgagePay('p1', 'bank', 700, 360), { entry: { mortgage: '360' } }));
  refuse('a mortgage with decimals', () => put('owner', mortgagePay('p1', 'bank', 700, 360.5), { balances: { ...POOR, p1: 60.5 } }));
  refuse('a mortgage that the balances do not show', () => put('owner', mortgagePay('p1', 'bank', 700, 360), { balances: { ...POOR, p1: 0 } }));
  refuse('a mortgage that gives the seat more than it should', () => put('owner', mortgagePay('p1', 'bank', 700, 360), { balances: { ...POOR, p1: 61 } }));
  refuse('a transfer whose mortgage the receiver gets', () => put('owner', mortgagePay('p1', 'p2', 700, 360), { balances: { ...POOR, p1: 60, p2: 2060 } }));
  refuse('a transfer to a player who is out', () => put('owner', mortgagePay('p1', 'p2', 700, 360)), () =>
    seedPlaying({ balances: POOR, stateOver: { bankrupt: ['p2'] } }));
  refuse('on a receive', () => put('owner', receive('p1', 100, POOR), { entry: { mortgage: 50 }, balances: { ...POOR, p1: 500 } }));
  refuse('on a pass over GO', () => put('owner', passGo('p1', POOR), { entry: { mortgage: 50 }, balances: { ...POOR, p1: 600 } }));
  refuse('when the bank holds less than the mortgage', () => put('owner', mortgagePay('p1', 'bank', 700, 360, { ...POOR, bank: 359 })), () =>
    seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: { ...POOR, bank: 359 } }));
  refuse('when the bank does not take the payment', () => put('owner', mortgagePay('p1', 'bank', 700, 360, POOR_BANK), { balances: { ...POOR, p1: 60, bank: 4640 } }), bankRoom);
  refuse('by somebody else', () => put('u2', mortgagePay('p1', 'bank', 700, 360)));
  refuse('when the bank does not pay out the mortgage of a transfer', () => put('owner', mortgagePay('p1', 'p2', 700, 360, POOR_BANK), { balances: { ...POOR, p1: 60, p2: 2200, bank: 5000 } }), bankRoom);
});

describe('bankruptcy: what is accepted', () => {
  it('owing a player: the player gets the whole debt, the seat ends at 0 and is out', async () => {
    await seedPlaying();
    await assertSucceeds(goOut('owner', bankrupt('p1', 'p2', 2000)));
    const state = (await adminGet(stateDoc)).data();
    assert.deepEqual(state.balances, { ...BASE, p1: 0, p2: 3500 });
    assert.deepEqual(state.bankrupt, ['p1']);
    assert.equal(state.bankerSeat, 'p1');
    assert.equal(state.seq, 1);
  });

  it('owing the bank: the cash goes to the bank', async () => {
    const base = { ...BASE, bank: 5000 };
    await seedPlaying({ settingsOver: { bankLimit: 5000 }, balances: base });
    await assertSucceeds(goOut('owner', bankrupt('p1', null, 2000, base)));
    const state = (await adminGet(stateDoc)).data();
    assert.deepEqual(state.balances, { ...BASE, p1: 0, bank: 6500 });
  });

  it('owing the bank in a room without a bank limit', async () => {
    await seedPlaying();
    await assertSucceeds(goOut('owner', bankrupt('p1', null, 2000)));
    assert.equal((await adminGet(stateDoc)).data().balances.p1, 0);
  });

  it('the bank pays what the cash does not cover, and may go below zero', async () => {
    const base = { ...BASE, bank: 100 };
    await seedPlaying({ settingsOver: { bankLimit: 100 }, balances: base });
    await assertSucceeds(goOut('owner', bankrupt('p1', 'p2', 2000, base)));
    assert.equal((await adminGet(stateDoc)).data().balances.bank, 100 - 500);
  });

  it('the debt may be 10 times the starting cash, 15,000, and the cash may be 0', async () => {
    const base = { ...BASE, p1: 0 };
    await seedPlaying({ balances: base });
    await assertSucceeds(goOut('owner', bankrupt('p1', 'p2', 15000, base)));
  });

  it('the second to go out does not become the banker', async () => {
    await seedPlaying({ stateOver: { bankrupt: ['p4'], bankerSeat: 'p4' } });
    await assertSucceeds(goOut('owner', bankrupt('p1', 'p2', 2000, BASE, ['p4'], 'p4')));
    const state = (await adminGet(stateDoc)).data();
    assert.deepEqual(state.bankrupt, ['p4', 'p1']);
    assert.equal(state.bankerSeat, 'p4');
  });
});

describe('bankruptcy: what is refused', () => {
  const refuse = (title, run, setup = seedPlaying) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });
  const out = (over = {}, extra = {}) => {
    const s = bankrupt('p1', 'p2', 2000);
    return { ...s, entry: { ...s.entry, ...over }, ...extra };
  };
  const info = (over) => {
    const s = bankrupt('p1', 'p2', 2000);
    return { ...s, entry: { ...s.entry, bankrupt: { ...s.entry.bankrupt, ...over } } };
  };

  refuse('the cash in the facts is not what the seat holds', () => goOut('owner', info({ cash: 1000 })));
  refuse('the debt equals the cash', () => goOut('owner', bankrupt('p1', 'p2', 1500)));
  refuse('the debt is less than the cash', () => goOut('owner', bankrupt('p1', 'p2', 1000)));
  refuse('the debt is over 15,000', () => goOut('owner', bankrupt('p1', 'p2', 15001)));
  refuse('the debt has decimals', () => goOut('owner', info({ owed: 2000.5 })));
  refuse('the debt is text', () => goOut('owner', info({ owed: '2000' })));
  refuse('the creditor is the seat itself', () => goOut('owner', info({ creditorSeat: 'p1' })));
  refuse('a creditor who is not in the game', () => goOut('owner', info({ creditorSeat: 'p9' })));
  refuse('a creditor who is out already', () => goOut('owner', bankrupt('p1', 'p2', 2000, BASE, ['p2'], 'p2')), () =>
    seedPlaying({ stateOver: { bankrupt: ['p2'], bankerSeat: 'p2' } }));
  refuse('the facts are for another seat', () => goOut('owner', info({ seat: 'p2' })));
  refuse('the facts have another key', () => goOut('owner', info({ extra: 1 })));
  refuse('the facts lack a key', () => {
    const s = bankrupt('p1', 'p2', 2000);
    delete s.entry.bankrupt.owed;
    return goOut('owner', s);
  });
  refuse('the facts are not a map', () => goOut('owner', out({ bankrupt: 'p1' })));
  refuse('no facts', () => goOut('owner', out({ bankrupt: null })));
  refuse('the creditor gets less than the debt', () => goOut('owner', bankrupt('p1', 'p2', 2000), { balances: { ...BASE, p1: 0, p2: 3499 } }));
  refuse('the creditor gets more than the debt', () => goOut('owner', bankrupt('p1', 'p2', 2000), { balances: { ...BASE, p1: 0, p2: 3501 } }));
  refuse('the cash in the facts is a lie that the numbers follow', () => goOut('owner', info({ cash: 1000 }), { balances: { ...BASE, p1: 500, p2: 3500 } }));
  refuse('owing the bank, with a seat that keeps money', () => goOut('owner', bankrupt('p1', null, 2000), { balances: { ...BASE, p1: 5 } }));
  refuse('owing the bank, with another seat getting the cash', () => goOut('owner', bankrupt('p1', null, 2000), { balances: { ...BASE, p1: 0, p2: 3000 } }));
  refuse('the seat keeps some money', () => goOut('owner', bankrupt('p1', 'p2', 2000), { balances: { ...BASE, p1: 1, p2: 3500 } }));
  refuse('another seat moves too', () => goOut('owner', bankrupt('p1', 'p2', 2000), { balances: { ...BASE, p1: 0, p2: 3500, p3: 1501 } }));
  refuse('the seat is not put on the list of those out', () => goOut('owner', bankrupt('p1', 'p2', 2000), { stateExtra: { bankerSeat: 'p1' } }));
  refuse('somebody else is put on the list', () => goOut('owner', bankrupt('p1', 'p2', 2000), { stateExtra: { bankrupt: ['p2'], bankerSeat: 'p1' } }));
  refuse('the banker is somebody else', () => goOut('owner', bankrupt('p1', 'p2', 2000), { stateExtra: { bankrupt: ['p1'], bankerSeat: 'p2' } }));
  refuse('no banker is set', () => goOut('owner', bankrupt('p1', 'p2', 2000), { stateExtra: { bankrupt: ['p1'], bankerSeat: null } }));
  refuse('the second to go out takes the banker over', () => goOut('owner', bankrupt('p1', 'p2', 2000, BASE, ['p4'], 'p1')), () =>
    seedPlaying({ stateOver: { bankrupt: ['p4'], bankerSeat: 'p4' } }));
  refuse('by somebody else', () => goOut('u2', bankrupt('p1', 'p2', 2000)));
  refuse('a seat that is out already', () => goOut('owner', bankrupt('p1', 'p2', 2000, BASE, ['p1'], 'p1')), () =>
    seedPlaying({ stateOver: { bankrupt: ['p1'], bankerSeat: 'p1' } }));
  refuse('with an amount', () => goOut('owner', out({ amount: 2000 })));
  refuse('with a reason', () => goOut('owner', out({ reason: 'x' })));
  refuse('with a party', () => goOut('owner', out({ to: 'p2' })));
  refuse('with a mortgage', () => goOut('owner', out({ mortgage: 100 })));
  refuse('facts on another kind', () => put('owner', { ...payBank('p1', 100), entry: { ...payBank('p1', 100).entry, bankrupt: bankrupt('p1', 'p2', 2000).entry.bankrupt } }));
  refuse('the list of those out changing with another kind of entry', () => put('owner', receive('p1', 100), { stateExtra: { bankrupt: ['p1'], bankerSeat: 'p1' } }));
});

describe('taking back a payment with a mortgage', () => {
  it('a payment to the bank, with and without a bank limit', async () => {
    for (const [base, room] of [[POOR, {}], [POOR_BANK, { settingsOver: { bankLimit: 5000 }, balances: POOR_BANK }]]) {
      await env.clearFirestore();
      await seedOnePress(mortgagePay('p1', 'bank', 700, 360, base), { seedOver: room });
      await assertSucceeds(takeBack('owner', { balances: base }));
    }
  });

  it('a transfer, with and without a bank limit', async () => {
    for (const [base, room] of [[POOR, {}], [POOR_BANK, { settingsOver: { bankLimit: 5000 }, balances: POOR_BANK }]]) {
      await env.clearFirestore();
      await seedOnePress(mortgagePay('p1', 'p2', 700, 360, base), { seedOver: room });
      await assertSucceeds(takeBack('owner', { balances: base }));
    }
  });

  it('is refused when the mortgage is left out of the numbers', async () => {
    await seedOnePress(mortgagePay('p1', 'bank', 700, 360));
    await assertFails(takeBack('owner', { balances: { ...POOR, p1: 760 } }));
    await env.clearFirestore();
    await seedOnePress(mortgagePay('p1', 'p2', 700, 360));
    await assertFails(takeBack('owner', { balances: { ...POOR, p1: 760, p2: 800 } }));
  });

  it('a bankruptcy is not taken back', async () => {
    await seedOnePress(bankrupt('p1', 'p2', 2000));
    await assertFails(takeBack('owner', { balances: BASE }));
  });
});

// ---- 7e: the banker presses the bank's buttons for the others

// p4 went out first and is the banker; u4 is the person at p4.
const OUT4 = { ...BASE, p4: 0 };
const BANKED = { stateOver: { bankrupt: ['p4'], bankerSeat: 'p4' }, balances: OUT4 };
const withBanker = (over = {}) => () => seedPlaying({ ...BANKED, ...over });
const POOR_OUT4 = { ...OUT4, p3: 400 };
const noReason = { entry: { reason: null } };

describe('a banker: what is accepted', () => {
  it('presses a receive for another seat, with or without a reason', async () => {
    await withBanker()();
    await assertSucceeds(put('u4', receive('p1', 300, OUT4), noReason));
    const b = { ...OUT4, p1: 1800 };
    await assertSucceeds(put('u4', receive('p2', 100, b), { entry: { seq: 1 }, id: 1, seqAfter: 2 }));
    assert.equal((await adminGet(stateDoc)).data().balances.p2, 1600);
    const e = (await adminGet((db) => entryDoc(db, 0))).data();
    assert.equal(e.by, 'u4');
    assert.equal(e.seat, 'p1');
  });

  it('presses a pass over GO and a payment for another seat', async () => {
    await withBanker()();
    await assertSucceeds(put('u4', passGo('p2', OUT4)));
    await assertSucceeds(
      put('u4', payBank('p3', 500, { ...OUT4, p2: 1700 }), { entry: { seq: 1 }, id: 1, seqAfter: 2 }),
    );
  });

  it('presses a payment helped by a mortgage for a seat that cannot pay', async () => {
    await withBanker({ balances: POOR_OUT4 })();
    await assertSucceeds(put('u4', mortgagePay('p3', 'bank', 700, 360, POOR_OUT4)));
    assert.equal((await adminGet(stateDoc)).data().balances.p3, 60);
  });

  it('with a bank limit the bank moves as for any press', async () => {
    const base = { ...OUT4, bank: 5000 };
    await withBanker({ settingsOver: { bankLimit: 5000 }, balances: base })();
    await assertSucceeds(put('u4', receive('p1', 300, base), noReason));
    assert.equal((await adminGet(stateDoc)).data().balances.bank, 4700);
  });

  it('declares a seat bankrupt when it owes the bank, and stays the banker', async () => {
    await withBanker()();
    await assertSucceeds(goOut('u4', bankrupt('p2', null, 2000, OUT4, ['p4'], 'p4')));
    const state = (await adminGet(stateDoc)).data();
    assert.deepEqual(state.bankrupt, ['p4', 'p2']);
    assert.equal(state.bankerSeat, 'p4');
  });

  it('a player still goes bankrupt on their own, owing a player', async () => {
    await withBanker()();
    await assertSucceeds(goOut('u2', bankrupt('p2', 'p3', 2000, OUT4, ['p4'], 'p4')));
  });

  it('a player still gives a friend money on their own', async () => {
    await withBanker()();
    await assertSucceeds(put('u2', transfer('p2', 'p3', 100, OUT4)));
  });

  it('takes back what the banker pressed, within the time', async () => {
    await seedOnePress(receive('p1', 300, OUT4), {
      seedOver: BANKED,
      entryOver: { by: 'u4' },
    });
    await assertSucceeds(takeBack('u4', { balances: OUT4 }));
  });

  it('a banker who is still playing presses for their own seat with a reason, and for others without', async () => {
    await seedPlaying({ stateOver: { bankerSeat: 'p1' } });
    await assertSucceeds(put('owner', receive('p1', 100)));
    await assertSucceeds(put('owner', receive('p2', 100, { ...BASE, p1: 1600 }), { entry: { seq: 1, reason: null }, id: 1, seqAfter: 2 }));
  });
});

describe('a banker who still plays', () => {
  it('pays a friend with a mortgage from their own seat, like any player without a banker', async () => {
    const base = { ...BASE, p1: 400 };
    await seedPlaying({ stateOver: { bankerSeat: 'p1' }, balances: base });
    await assertSucceeds(put('owner', mortgagePay('p1', 'p2', 700, 360, base)));
    assert.equal((await adminGet(stateDoc)).data().balances.p1, 60);
  });
});

describe('a banker: what is refused', () => {
  const refuse = (title, run, setup = withBanker()) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });

  refuse('a player pressing a receive for their own seat', () => put('u2', receive('p2', 100, OUT4)));
  refuse('a player pressing a pass over GO for their own seat', () => put('u2', passGo('p2', OUT4)));
  refuse('a player paying the bank for their own seat', () => put('u2', payBank('p2', 100, OUT4)));
  refuse('a player pressing for somebody else', () => put('u2', receive('p1', 100, OUT4), noReason));
  refuse('the banker pressing a transfer for somebody else', () => put('u4', transfer('p1', 'p2', 100, OUT4)));
  refuse('the banker pressing a transfer of their own, out as they are', () => put('u4', transfer('p4', 'p2', 100, OUT4)));
  refuse('the banker pressing for a seat that is out', () => put('u4', receive('p4', 100, OUT4), noReason));
  refuse('the banker pressing for a seat that is not in the game', () => put('u4', receive('p9', 100, OUT4), noReason));
  refuse('a receive with a reason that is only spaces', () => put('u4', receive('p1', 100, OUT4), { entry: { reason: '   ' } }));
  refuse('the banker declaring a seat bankrupt when it owes a player', () => goOut('u4', bankrupt('p2', 'p3', 2000, OUT4, ['p4'], 'p4')));
  refuse('somebody else declaring a seat bankrupt', () => goOut('u3', bankrupt('p2', null, 2000, OUT4, ['p4'], 'p4')));
  refuse('a transfer helped by a mortgage, which is a bank action', () => put('u2', mortgagePay('p2', 'p3', 700, 360, { ...OUT4, p2: 400 })), withBanker({ balances: { ...OUT4, p2: 400 } }));
  refuse('pressing in the name of somebody else', () => put('u2', receive('p1', 100, OUT4), { entry: { by: 'u4' }, noReason }));
  refuse('a banker whose press says it was made by another person', () => put('u4', receive('p1', 100, OUT4), { entry: { by: 'u2', reason: null } }));
  refuse('a banker who is not the person at the banker seat any more', () => put('owner', receive('p2', 100, OUT4), noReason));
  refuse('a player taking back what the banker pressed', () => takeBack('u2', { balances: OUT4 }), () =>
    seedOnePress(receive('p2', 300, OUT4), { seedOver: BANKED, entryOver: { by: 'u4' } }));
  refuse('the person pressed for taking back what the banker pressed', () => takeBack('u1', { balances: OUT4 }), () =>
    seedOnePress(receive('p1', 300, OUT4), { seedOver: BANKED, entryOver: { by: 'u4' } }));
  refuse('somebody else as banker taking it back', () => takeBack('u3', { balances: OUT4 }), () =>
    seedOnePress(receive('p1', 300, OUT4), { seedOver: BANKED, entryOver: { by: 'u4' } }));
  refuse('a banker who is still playing pressing a receive for their own seat with no reason', () => put('owner', receive('p1', 100), noReason), () =>
    seedPlaying({ stateOver: { bankerSeat: 'p1' } }));
});

// ---- 7e: handing the banker's seat on, and taking it over from a banker who is gone

const passBanker = (uid, to, extra = {}) => updateDoc(stateDoc(as(uid)), { bankerSeat: to, ...extra });
const takeOver = (uid, to, { beat = true, extra = {} } = {}) => {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.update(stateDoc(db), { bankerSeat: to, ...extra });
  if (beat) batch.set(presence(db, uid), { lastSeen: serverTimestamp() });
  return batch.commit();
};

describe('handing the banker on', () => {
  it('the banker gives it to another seat of the game, and that person presses next', async () => {
    await withBanker()();
    await assertSucceeds(passBanker('u4', 'p1'));
    assert.equal((await adminGet(stateDoc)).data().bankerSeat, 'p1');
    await assertSucceeds(put('owner', receive('p2', 100, OUT4), { entry: { reason: null } }));
    await assertFails(put('u4', receive('p2', 100, { ...OUT4, p2: 1600 }), { entry: { seq: 1, reason: null }, id: 1, seqAfter: 2 }));
  });

  it('a seat that is out may be given it too', async () => {
    await seedPlaying({ ...BANKED, stateOver: { bankrupt: ['p4', 'p3'], bankerSeat: 'p4' } });
    await assertSucceeds(passBanker('u4', 'p3'));
  });
});

describe('handing the banker on: what is refused', () => {
  const refuse = (title, run, setup = withBanker()) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });

  refuse('by somebody who is not the banker', () => passBanker('u2', 'p2'));
  refuse('to the banker itself, which changes nothing', () => passBanker('u4', 'p4'));
  refuse('to nobody', () => passBanker('u4', null));
  refuse('to a seat that is not in the game', () => passBanker('u4', 'p9'));
  refuse('to something that is not a seat', () => passBanker('u4', 7));
  refuse('with another thing of the state changing too', () => passBanker('u4', 'p1', { balances: { ...OUT4, p1: 1600 } }));
  refuse('with the counter moving', () => passBanker('u4', 'p1', { seq: 1 }));
  refuse('when there is no banker yet', () => passBanker('owner', 'p1'), () => seedPlaying());
  refuse('by a stranger', () => passBanker('stranger', 'p1'));
});

describe('taking the banker over from one who is gone', () => {
  it('a player takes it after 2 minutes, with their own presence written in the same batch', async () => {
    await withBanker()();
    await staleBeat('u4');
    await assertSucceeds(takeOver('u3', 'p3'));
    assert.equal((await adminGet(stateDoc)).data().bankerSeat, 'p3');
  });

  it('a seat that is out can take it too', async () => {
    await seedPlaying({ ...BANKED, stateOver: { bankrupt: ['p4', 'p2'], bankerSeat: 'p4' } });
    await staleBeat('u4');
    await assertSucceeds(takeOver('u2', 'p2'));
  });

  it('a banker who has no presence document at all can be replaced at once', async () => {
    await withBanker()();
    await assertSucceeds(takeOver('u3', 'p3'));
    assert.equal((await adminGet(stateDoc)).data().bankerSeat, 'p3');
  });
});

describe('taking the banker over: what is refused', () => {
  const refuse = (title, run, { beatAgo = 3 * 60 * 1000, setup = withBanker() } = {}) =>
    it(title, async () => {
      await setup();
      if (beatAgo !== null) await staleBeat('u4', beatAgo);
      await assertFails(run());
    });

  refuse('while the banker was seen less than 2 minutes ago', () => takeOver('u3', 'p3'), { beatAgo: 100 * 1000 });
  refuse('without writing their own presence', () => takeOver('u3', 'p3', { beat: false }));
  refuse('for somebody else\'s seat', () => takeOver('u3', 'p2'));
  refuse('by the banker themselves', () => takeOver('u4', 'p4'));
  refuse('by a stranger', () => takeOver('stranger', 'p3'));
  refuse('with another thing of the state changing too', () => takeOver('u3', 'p3', { extra: { balances: { ...OUT4, p3: 1600 } } }));
  refuse('when there is no banker', () => takeOver('u3', 'p3'), { beatAgo: null, setup: () => seedPlaying() });
});

// ---- deleting a room that has not started

describe('the owner deletes a room that has not started', () => {
  const uids = ['owner', 'u2', 'u3'];

  async function lobbyOf(list = uids, metaOver = {}) {
    await seedRoom({ seats: list, metaOver });
    await admin(async (db) => {
      for (const uid of list) await setDoc(presence(db, uid), { lastSeen: Timestamp.now() });
    });
  }

  /** What the app does: every seat, member and presence document, then the room. */
  function wipe(uid, list = uids, only = null) {
    const db = as(uid);
    const batch = writeBatch(db);
    if (only !== 'room') {
      list.forEach((u, i) => {
        batch.delete(seat(db, `p${i + 1}`));
        batch.delete(member(db, u));
        batch.delete(presence(db, u));
      });
    }
    if (only !== 'subdocs') batch.delete(room(db));
    return batch.commit();
  }

  it('removes the seats, the members, the presence and the room', async () => {
    await lobbyOf();
    await assertSucceeds(wipe('owner'));
    assert.equal((await adminGet(room)).exists(), false);
    assert.equal((await adminGet((db) => seat(db, 'p2'))).exists(), false);
    assert.equal((await adminGet((db) => member(db, 'u2'))).exists(), false);
    assert.equal((await adminGet((db) => presence(db, 'u3'))).exists(), false);
  });

  it('works for a full room of eight in one batch', async () => {
    const eight = ['owner', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8'];
    await lobbyOf(eight, { settings: settings({ maxPlayers: 8 }) });
    await assertSucceeds(wipe('owner', eight));
    assert.equal((await adminGet(room)).exists(), false);
  });

  it('works for the one who took the room over', async () => {
    await lobbyOf();
    await admin((db) => updateDoc(room(db), { ownerUid: 'u2' }));
    await assertSucceeds(wipe('u2'));
  });

  it('a room without anyone but the owner can go too', async () => {
    await lobbyOf(['owner']);
    await assertSucceeds(wipe('owner', ['owner']));
  });
});

describe('deleting a room: what is refused', () => {
  const uids = ['owner', 'u2', 'u3'];
  const refuse = (title, run, setup) =>
    it(title, async () => {
      await (setup ?? (async () => {
        await seedRoom({ seats: uids });
        await admin(async (db) => {
          for (const uid of uids) await setDoc(presence(db, uid), { lastSeen: Timestamp.now() });
        });
      }))();
      await assertFails(run());
    });

  refuse('the room by somebody who is not the owner', () => deleteDoc(room(as('u2'))));
  refuse('the room by a stranger', () => deleteDoc(room(as('stranger'))));
  refuse('the room by somebody who is not signed in', () => deleteDoc(room(anonymous())));
  refuse('a seat by a player', () => deleteDoc(seat(as('u2'), 'p3')));
  refuse('a seat by a stranger', () => deleteDoc(seat(as('stranger'), 'p3')));
  refuse('the member document of another player, by a player', () => deleteDoc(member(as('u2'), 'u3')));
  refuse('the presence of another player, by a player', () => deleteDoc(presence(as('u2'), 'u3')));
  refuse('the own presence of a player on the way out', () => deleteDoc(presence(as('u2'), 'u2')));
  refuse('the room once the game has started', () => deleteDoc(room(as('owner'))), () => seedPlaying());
  refuse('a seat once the game has started', () => deleteDoc(seat(as('owner'), 'p2')), () => seedPlaying());
  refuse('a member once the game has started', () => deleteDoc(member(as('owner'), 'u2')), () => seedPlaying());
  refuse('the state of a game', () => deleteDoc(stateDoc(as('owner'))), () => seedPlaying());
  refuse('an entry of a game', async () => {
    await admin((db) => setDoc(entryDoc(db, 0), entryData({ seq: 0 })));
    return deleteDoc(entryDoc(as('owner'), 0));
  }, () => seedPlaying());
  refuse('a request of a game', async () => {
    await admin((db) => setDoc(reqDoc(db), requestData()));
    return deleteDoc(reqDoc(as('owner')));
  }, () => seedPlaying());
});

// ---- 7g: ending a game

const TEN = 10 * 60 * 1000;
/** The room and its state move to ended in one batch, as the app does. */
function endBatch(uid, { roomOver = {}, stateOver = {}, skipRoom = false, skipState = false } = {}) {
  const db = as(uid);
  const batch = writeBatch(db);
  if (!skipRoom) batch.update(room(db), { status: 'ended', endedAt: serverTimestamp(), ...roomOver });
  if (!skipState) batch.update(stateDoc(db), { status: 'ended', ...stateOver });
  return batch.commit();
}
const withBankerState = { stateOver: { bankrupt: ['p4'], bankerSeat: 'p4' }, balances: { ...BASE, p4: 0 } };

describe('ending a game: what is accepted', () => {
  it('the owner ends it, at once', async () => {
    await seedPlaying();
    await assertSucceeds(endBatch('owner'));
    const r = (await adminGet(room)).data();
    assert.equal(r.status, 'ended');
    assert.ok(r.endedAt);
    assert.equal((await adminGet(stateDoc)).data().status, 'ended');
    assert.equal((await adminGet(stateDoc)).data().seq, 0, 'the counter does not move');
  });

  it('the banker ends it, at once', async () => {
    await seedPlaying(withBankerState);
    await staleBeat('owner', 30 * 1000);
    await assertSucceeds(endBatch('u4'));
  });

  it('a player ends it when the owner and the banker were last seen over 10 minutes ago', async () => {
    await seedPlaying(withBankerState);
    await staleBeat('owner', TEN + 30 * 1000);
    await staleBeat('u4', TEN + 30 * 1000);
    await assertSucceeds(endBatch('u2'));
  });

  it('a player ends it when owner and banker have no presence document at all', async () => {
    await seedPlaying(withBankerState);
    await assertSucceeds(endBatch('u3'));
  });

  it('without a banker only the owner has to be gone', async () => {
    await seedPlaying();
    await staleBeat('owner', TEN + 30 * 1000);
    await assertSucceeds(endBatch('u2'));
  });
});

describe('ending a game: what is refused', () => {
  const refuse = (title, run, setup = () => seedPlaying()) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });

  refuse('the room alone, with no state, by the owner', () => endBatch('owner', { skipState: true }));
  refuse('the state alone, by the owner', () => endBatch('owner', { skipRoom: true }));
  refuse('the room alone by the banker', () => endBatch('u4', { skipState: true }), () => seedPlaying(withBankerState));
  refuse('the state alone by a stale-owner player', () => endBatch('u2', { skipRoom: true }), async () => {
    await seedPlaying();
    await staleBeat('owner', TEN + 30 * 1000);
  });
  refuse('an end time that is not the time of the server', () => endBatch('owner', { roomOver: { endedAt: Timestamp.fromMillis(1) } }));
  refuse('no end time', () => endBatch('owner', { roomOver: { endedAt: deleteField() } }));
  refuse('the settings changing with it', () => endBatch('owner', { roomOver: { settings: settings({ startingCash: 1 }) } }));
  refuse('the balances changing with it', () => endBatch('owner', { stateOver: { balances: { ...BASE, p1: 9999 } } }));
  refuse('the counter moving with it', () => endBatch('owner', { stateOver: { seq: 1 } }));
  refuse('a player while the owner was seen 9 minutes ago', () => endBatch('u2'), async () => {
    await seedPlaying();
    await staleBeat('owner', 9 * 60 * 1000);
  });
  refuse('a player while the banker was seen 9 minutes ago (the owner is gone)', () => endBatch('u2'), async () => {
    await seedPlaying(withBankerState);
    await staleBeat('owner', TEN + 30 * 1000);
    await staleBeat('u4', 9 * 60 * 1000);
  });
  refuse('a player while the owner is fresh and the banker gone', () => endBatch('u2'), async () => {
    await seedPlaying(withBankerState);
    await staleBeat('owner', 60 * 1000);
    await staleBeat('u4', TEN + 30 * 1000);
  });
  refuse('a watcher', () => endBatch('s1'), async () => {
    await seedPlaying();
    await admin((db) => setDoc(member(db, 's1'), memberData('ดู', { role: 'spectator', seat: null })));
  });
  refuse('a stranger', () => endBatch('stranger'), async () => {
    await seedPlaying();
    await staleBeat('owner', TEN + 30 * 1000);
  });
  refuse('somebody who is not signed in', () => {
    const db = anonymous();
    const batch = writeBatch(db);
    batch.update(room(db), { status: 'ended', endedAt: serverTimestamp() });
    batch.update(stateDoc(db), { status: 'ended' });
    return batch.commit();
  });
  refuse('a game that has not started', () => endBatch('owner', { skipState: true }), () => seedRoom());
  refuse('the old way: the owner changing only the status, with no end time', () =>
    updateDoc(room(as('owner')), { status: 'ended' }));

  refuse('a member whose seat has been taken over by somebody else', () => endBatch('ghost'), async () => {
    await seedPlaying();
    await admin((db) => setDoc(member(db, 'ghost'), memberData('ผี', { seat: 'p2' })));
  });

  describe('once it has ended', () => {
    const ended = async () => {
      await seedPlaying();
      await admin(async (db) => {
        await updateDoc(room(db), { status: 'ended', endedAt: Timestamp.now() });
        await updateDoc(stateDoc(db), { status: 'ended' });
      });
    };
    refuse('a receive', () => put('owner', receive('p1', 100)), ended);
    refuse('a payment to the bank', () => put('owner', payBank('p1', 100)), ended);
    refuse('a transfer', () => put('owner', transfer('p1', 'p2', 100)), ended);
    refuse('the game going back to playing', () => updateDoc(room(as('owner')), { status: 'playing' }), ended);
    refuse('ending it again', () => endBatch('owner'), ended);
    refuse('moving the end time of the room alone', () => updateDoc(room(as('owner')), { status: 'ended', endedAt: serverTimestamp() }), ended);
    refuse('a new member', () => setDoc(member(as('late'), 'late'), memberData('สาย', { seat: null, role: 'spectator' })), ended);
  });
});

// ---- 7g: closing a game that ended, and the next game

const FIVE = 5 * 60 * 1000;
const SPECTATOR = 's1';

/** A game of four that ended [age] ms ago, with an entry, a request and presence. */
async function seedEnded(age = FIVE + 30 * 1000, { stateOver = {} } = {}) {
  await seedPlaying({ stateOver: { seq: 1, ...stateOver } });
  await admin(async (db) => {
    await updateDoc(room(db), { status: 'ended', endedAt: Timestamp.fromMillis(Date.now() - age) });
    await updateDoc(stateDoc(db), { status: 'ended' });
    await setDoc(entryDoc(db, 0), entryData({ seq: 0 }));
    await setDoc(reqDoc(db), requestData());
    for (const uid of ['owner', 'u2', 'u3', 'u4']) await setDoc(presence(db, uid), { lastSeen: Timestamp.now() });
    await setDoc(member(db, SPECTATOR), memberData('ดู', { role: 'spectator', seat: null }));
    await setDoc(presence(db, SPECTATOR), { lastSeen: Timestamp.now() });
  });
}

const closeAll = ['owner', 'u2', 'u3', 'u4', SPECTATOR];
/** What the app deletes first: all the game's documents but the room, the caller's own seat and member document. */
function closeFirst(db, uid) {
  const batch = writeBatch(db);
  batch.delete(entryDoc(db, 0));
  batch.delete(reqDoc(db));
  batch.delete(stateDoc(db));
  for (let i = 1; i <= 4; i++) if (`p${i}` !== seatOf[uid]) batch.delete(seat(db, `p${i}`));
  for (const u of closeAll) {
    batch.delete(presence(db, u));
    if (u !== uid) batch.delete(member(db, u));
  }
  return batch.commit();
}
/** The last batch: the caller's own seat and member document, and the room. */
function closeLast(db, uid) {
  const batch = writeBatch(db);
  if (seatOf[uid]) batch.delete(seat(db, seatOf[uid]));
  batch.delete(member(db, uid));
  batch.delete(room(db));
  return batch.commit();
}

describe('closing a game that ended: what is accepted', () => {
  it('the owner takes it all down at once', async () => {
    await seedEnded(10 * 1000);
    const db = as('owner');
    await assertSucceeds(closeFirst(db, 'owner'));
    await assertSucceeds(closeLast(db, 'owner'));
    assert.equal((await adminGet(room)).exists(), false);
    assert.equal((await adminGet(stateDoc)).exists(), false);
    assert.equal((await adminGet((d) => entryDoc(d, 0))).exists(), false);
  });

  it('a player takes it down once 5 minutes have gone by since the end', async () => {
    await seedEnded();
    const db = as('u2');
    await assertSucceeds(closeFirst(db, 'u2'));
    await assertSucceeds(closeLast(db, 'u2'));
    assert.equal((await adminGet(room)).exists(), false);
  });

  it('a player deletes 400 entries in one batch (the size the app uses)', async () => {
    await seedEnded();
    await admin(async (db) => {
      for (let i = 1; i < 400; i++) await setDoc(entryDoc(db, i), entryData({ seq: i }));
    });
    const db = as('u2');
    const batch = writeBatch(db);
    for (let i = 0; i < 400; i++) batch.delete(entryDoc(db, i));
    await assertSucceeds(batch.commit());
    assert.equal((await adminGet((d) => entryDoc(d, 399))).exists(), false);
  });

  it('the banker has no more right than another player', async () => {
    await seedEnded(FIVE + 30 * 1000, { stateOver: { bankerSeat: 'p4', bankrupt: ['p4'], balances: { ...BASE, p4: 0 } } });
    await assertSucceeds(closeFirst(as('u4'), 'u4'));
  });
});

describe('closing a game that ended: what is refused', () => {
  const refuse = (title, run, setup = () => seedEnded()) =>
    it(title, async () => {
      await setup();
      await assertFails(run());
    });

  const parts = {
    state: (db) => deleteDoc(stateDoc(db)),
    entry: (db) => deleteDoc(entryDoc(db, 0)),
    request: (db) => deleteDoc(reqDoc(db)),
    seat: (db) => deleteDoc(seat(db, 'p2')),
    member: (db) => deleteDoc(member(db, 'u3')),
    presence: (db) => deleteDoc(presence(db, 'u3')),
    room: (db) => deleteDoc(room(db)),
  };
  for (const [name, del] of Object.entries(parts)) {
    refuse(`the ${name} by a player 4 minutes after the end`, () => del(as('u2')), () => seedEnded(4 * 60 * 1000));
    refuse(`the ${name} by a watcher, long after the end`, () => del(as(SPECTATOR)), () => seedEnded(60 * 60 * 1000));
    refuse(`the ${name} by a stranger, long after the end`, () => del(as('stranger')), () => seedEnded(60 * 60 * 1000));
    refuse(`the ${name} by somebody who is not signed in`, () => del(anonymous()), () => seedEnded(60 * 60 * 1000));
    refuse(`the ${name} by the owner while the game is played`, () => del(as('owner')), () => seedPlaying({ stateOver: { seq: 1 } }));
  }
  refuse('the room by a player whose seat was taken over (a member of nothing)', () => deleteDoc(room(as('ghost'))), async () => {
    await seedEnded();
    await admin((db) => setDoc(member(db, 'ghost'), memberData('ผี', { seat: 'p2' })));
  });
});

describe('the next game: nextCode on a game that ended', () => {
  const NEXT = 'NEW234';
  const seedNext = (over = {}) => admin((db) => setDoc(room(db, NEXT), metaData({ createdAt: Timestamp.now(), ...over })));
  const point = (uid, code = NEXT, extra = {}) => updateDoc(room(as(uid)), { nextCode: code, ...extra });

  it('the owner points to a room of theirs that is a lobby', async () => {
    await seedEnded(10 * 1000);
    await seedNext();
    await assertSucceeds(point('owner'));
    assert.equal((await adminGet(room)).data().nextCode, NEXT);
  });

  const refuse = (title, run, { next = {}, noNext = false, ended = true } = {}) =>
    it(title, async () => {
      if (ended) await seedEnded(10 * 1000);
      else await seedPlaying();
      if (!noNext) await seedNext(next);
      await assertFails(run());
    });

  refuse('a player', () => point('u2'));
  refuse('a stranger', () => point('stranger'));
  refuse('somebody who is not signed in', () => updateDoc(room(anonymous()), { nextCode: NEXT }));
  refuse('the code of a room of somebody else', () => point('owner'), { next: { ownerUid: 'u2' } });
  refuse('the code of a room that is being played', () => point('owner'), { next: { status: 'playing' } });
  refuse('the code of a room that does not exist', () => point('owner'), { noNext: true });
  it('a player who has a lobby of their own', async () => {
    await seedEnded(10 * 1000);
    await seedNext({ ownerUid: 'u2' });
    await assertFails(point('u2'));
  });
  for (const odd of ['new234', 'NEW23', 'NEW2345']) {
    it(`a code of a room that exists but is not written like one (${odd})`, async () => {
      await seedEnded(10 * 1000);
      await admin((db) => setDoc(room(db, odd), metaData({ createdAt: Timestamp.now() })));
      await assertFails(point('owner', odd));
    });
  }
  refuse('a code that is not a string', () => point('owner', 123456));
  refuse('another field with it', () => point('owner', NEXT, { status: 'lobby' }));
  refuse('a game that is still played', () => point('owner'), { ended: false });
  it('again, when the first room is gone', async () => {
    await seedEnded(10 * 1000);
    await seedNext();
    await seedNext2();
    await assertSucceeds(point('owner'));
    await assertSucceeds(point('owner', 'NEW235'));
    assert.equal((await adminGet(room)).data().nextCode, 'NEW235');
  });
  async function seedNext2() {
    await admin((db) => setDoc(room(db, 'NEW235'), metaData({ createdAt: Timestamp.now() })));
  }
});

describe('the rules agree with the Ledger', () => {
  const cases = JSON.parse(readFileSync('parity_cases.json', 'utf8'));

  /** What one press (or taking one back) does to the books, the plain way. */
  function natural(c) {
    const after = { ...c.balances };
    const sign = c.op === 'undo' ? -1 : 1;
    if (c.kind === 'bankrupt') {
      after[c.seat] = 0;
      if (c.creditor) {
        after[c.creditor] = (c.creditor === c.seat ? 0 : after[c.creditor]) + c.owed;
        if ('bank' in after) after.bank -= c.owed - c.cash;
      } else if ('bank' in after) {
        after.bank += c.cash;
      }
      return after;
    }
    if ('mortgage' in c) {
      // the payment helped by a mortgage: the seat gets the mortgage, pays the amount
      const give = sign * (c.mortgage - c.amount);
      after[c.seat] += give;
      if (c.kind === 'transfer') {
        after[c.to] -= sign * -c.amount;
        if ('bank' in after) after.bank -= sign * c.mortgage;
      } else if ('bank' in after) {
        after.bank -= give;
      }
      return after;
    }
    if (c.kind === 'transfer') {
      after[c.seat] = (after[c.seat] ?? 0) - sign * c.amount;
      after[c.to] = (after[c.to] ?? 0) + sign * c.amount;
      return after;
    }
    const delta = sign * (c.kind === 'payBank' ? -c.amount : c.amount);
    after[c.seat] += delta;
    if ('bank' in after) after.bank -= delta;
    return after;
  }

  const entryOf = (c) =>
    c.kind === 'bankrupt'
      ? {
          seat: c.seat,
          kind: 'bankrupt',
          from: null,
          to: null,
          amount: null,
          reason: null,
          bankrupt: { seat: c.seat, creditorSeat: c.creditor ?? null, cash: c.cash, owed: c.owed },
        }
      : {
          seat: c.seat,
          kind: c.kind,
          from: c.kind === 'payBank' || c.kind === 'transfer' ? c.seat : 'bank',
          to: c.kind === 'payBank' ? 'bank' : c.kind === 'transfer' ? c.to : c.seat,
          amount: c.amount,
          reason: c.kind === 'receive' ? 'ค่าเช่า' : c.kind === 'passGo' ? 'ผ่านจุดเริ่ม' : null,
          ...('mortgage' in c ? { mortgage: c.mortgage } : {}),
        };

  it(`accepts and refuses ${cases.length} made-up presses and take-backs exactly as the Ledger does`, async () => {
    await seedPlaying();
    const disagreements = [];
    for (const [i, c] of cases.entries()) {
      const seats = ['p1', 'p2', 'p3', 'p4'];
      await admin(async (db) => {
        await deleteDoc(entryDoc(db, 0));
        await setDoc(stateDoc(db), stateData({ seats, seq: c.op === 'undo' ? 1 : 0, balances: c.balances, bankrupt: c.bankrupt, bankerSeat: c.bankerSeat ?? null }));
        if (c.op === 'undo') {
          await setDoc(entryDoc(db, 0), entryData({ seq: 0, by: uidOfSeat[c.seat], at: Timestamp.now(), ...entryOf(c) }));
        }
      });
      const after = natural(c);
      if (c.accepted) assert.deepEqual(after, c.after, `case ${i}: the plain formula and the Ledger agree`);
      let accepted = true;
      try {
        if (c.op === 'undo') await takeBack(uidOfSeat[c.seat], { balances: after });
        else if (c.kind === 'bankrupt') {
          await put(uidOfSeat[c.seat], { entry: entryOf(c), balances: after }, { stateExtra: { bankrupt: [...c.bankrupt, c.seat], bankerSeat: c.bankerSeat ?? c.seat } });
        } else await put(uidOfSeat[c.seat], { entry: entryOf(c), balances: after });
      } catch {
        accepted = false;
      }
      if (accepted !== c.accepted) {
        disagreements.push(`case ${i}: ${c.op} ${c.kind} ${c.amount} by ${c.seat}${c.to ? ' to ' + c.to : ''} on ${JSON.stringify(c.balances)} out ${JSON.stringify(c.bankrupt)}: Ledger ${c.accepted}, rules ${accepted}`);
      }
    }
    assert.deepEqual(disagreements, []);
  });
});
