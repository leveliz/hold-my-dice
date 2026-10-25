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
