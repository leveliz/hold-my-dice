// End-to-end check of the multi-device mode with several browsers at once.
//
//   cd tool/e2e && npm install && node two_browsers.mjs [BASE_URL]
//
// BASE_URL is a running copy of the web app (default http://127.0.0.1:8095),
// built with --dart-define=FIREBASE_ENV=dev (or =FIREBASE_EMULATOR=localhost
// with the emulators running). It makes a real room, so use the dev project.
// Set E2E_QUICK=1 to skip the two presence checks that wait over 2 minutes each.
import { chromium } from 'playwright';

const base = process.argv[2] ?? 'http://127.0.0.1:8095';
const quick = process.env.E2E_QUICK === '1';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = 0;

function check(ok, what) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`);
  if (!ok) failed++;
}

const browser = await chromium.launch();

async function person(label) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log(`[${label}] page error: ${e.message}`));
  return { ctx, page, label };
}

/** Flutter paints on a canvas; this asks it to also build the accessibility tree. */
async function open(p, path) {
  await p.page.goto(base + path);
  await p.page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
  await p.page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.page.waitForSelector('flt-semantics', { state: 'attached', timeout: 15000 });
}

const text = (p, t, opts = {}) => p.page.getByText(t, opts).first();
const button = (p, name) => p.page.getByRole('button', { name }).first();
/** The second 'take over' button: the guest's seat (p2), under the owner's. */
const takeOverGuestSeat = (p) => p.page.getByRole('button', { name: 'เข้าแทน' }).nth(1);
async function seen(p, t, timeout = 15000) {
  try {
    await text(p, t).waitFor({ state: 'attached', timeout });
    return true;
  } catch {
    return false;
  }
}
async function typeName(p, value) {
  // Typing key by key: Flutter ignores a value that is filled in at once.
  const box = p.page.getByRole('textbox').first();
  await box.click();
  await box.pressSequentially(value, { delay: 40 });
}

try {
  // 1. The owner opens a room.
  const owner = await person('owner');
  await open(owner, '/room/create');
  await typeName(owner, 'Owner');
  await button(owner, 'ออกตั๋วห้อง').click();
  await owner.page.waitForURL(/\/room\/[A-Z0-9]{6}$/, { timeout: 30000 });
  const code = owner.page.url().split('/').pop();
  check(await seen(owner, 'ห้องรอ'), `owner is in the waiting room ${code}`);

  // 2. A guest joins from the link (typed in lower case), the owner sees them live.
  const guest = await person('guest');
  await open(guest, `/room/${code.toLowerCase()}`);
  check(await seen(guest, 'ชวนคุณเข้าห้อง'), 'the link opens the join form');
  await typeName(guest, 'Guest');
  await button(guest, 'นั่งโต๊ะ').click();
  check(await seen(guest, 'ห้องรอ'), 'the guest is in the waiting room');
  check(await seen(owner, 'Guest'), 'the owner sees the guest appear without reloading');
  const joinedAt = Date.now();

  // 2b. The longest name the rules accept (20 UTF-16 units: Thai letters and
  // emoji) is stored whole and shown to the owner as typed.
  const longName = 'สวัสดีชาวโลก😀😀😀😀';
  const thai = await person('thai');
  await open(thai, `/room/${code}`);
  await typeName(thai, longName);
  await button(thai, 'นั่งโต๊ะ').click();
  check(await seen(thai, 'ห้องรอ'), 'a 20-unit Thai and emoji name can join');
  check(await seen(owner, longName), 'the owner sees that name whole');

  // 2b2. A room with a password: the owner can open it, a wrong password is
  // refused with its own message, the right one gets in.
  const secretOwner = await person('secret-owner');
  await open(secretOwner, '/room/create');
  await typeName(secretOwner, 'Keeper');
  await secretOwner.page.getByRole('switch', { name: 'ตั้งรหัสผ่านห้อง' }).click();
  const fields = secretOwner.page.getByRole('textbox');
  await fields.nth(3).click();
  await fields.nth(3).pressSequentially('abcd', { delay: 40 });
  await button(secretOwner, 'ออกตั๋วห้อง').click();
  await secretOwner.page.waitForURL(/\/room\/[A-Z0-9]{6}$/, { timeout: 30000 });
  const secretCode = secretOwner.page.url().split('/').pop();
  check(await seen(secretOwner, 'ห้องรอ'), `an owner can open a room with a password (${secretCode})`);
  const visitor = await person('visitor');
  await open(visitor, `/room/${secretCode}`);
  check(await seen(visitor, 'มีรหัสผ่าน'), 'the join form says the room has a password');
  const visitorFields = visitor.page.getByRole('textbox');
  await visitorFields.nth(0).click();
  await visitorFields.nth(0).pressSequentially('wrong', { delay: 40 });
  await visitorFields.nth(1).click();
  await visitorFields.nth(1).pressSequentially('Visitor', { delay: 40 });
  await button(visitor, 'นั่งโต๊ะ').click();
  check(await seen(visitor, 'รหัสผ่านห้องไม่ถูกต้อง'), 'a wrong password is refused');
  await visitorFields.nth(0).fill('');
  await visitorFields.nth(0).pressSequentially('abcd', { delay: 40 });
  await button(visitor, 'นั่งโต๊ะ').click();
  check(await seen(visitor, 'ห้องรอ'), 'the right password gets in');
  await secretOwner.ctx.close();
  await visitor.ctx.close();

  // 2c. Without a connection a join says so (and does not claim the room ended).
  const late = await person('late');
  await open(late, `/room/${code}`);
  await typeName(late, 'Late');
  await late.ctx.setOffline(true);
  await button(late, 'นั่งโต๊ะ').click();
  check(await seen(late, 'ออฟไลน์อยู่', 30000), 'a join without signal says it is offline');
  check(!(await seen(late, 'ห้องนี้จบแล้ว', 1000)), 'and does not say the room has ended');
  await late.ctx.close();

  if (!quick) {
    // 3. The guest stays open: their beats keep the seat from being taken over.
    await sleep(Math.max(0, 150_000 - (Date.now() - joinedAt)));
    const thief = await person('thief');
    await open(thief, `/room/${code}`);
    await takeOverGuestSeat(thief).click();
    check(
      await seen(thief, 'ยังมีคนใช้อยู่', 8000),
      'a seat whose person is still there cannot be taken over after 2 minutes',
    );

    // 4. The guest leaves; after 2 minutes the seat can be taken over.
    await guest.ctx.close();
    await sleep(150_000);
    await open(thief, `/room/${code}`);
    await takeOverGuestSeat(thief).click();
    check(await seen(thief, 'ห้องรอ', 15000), 'a seat left alone for 2 minutes is taken over');
    check(await seen(owner, 'Guest'), 'the owner still sees the seat by its name');

    // 5. The owner disappears; after 2 minutes a member takes the room over
    // and starts the game.
    await owner.ctx.close();
    await sleep(150_000);
    await open(thief, `/room/${code}`);
    check(await seen(thief, 'ห้องรอ'), 'the member is back in the waiting room');
    await button(thief, 'รับเป็นเจ้าของแทน').click();
    check(await seen(thief, 'เริ่มเกม'), 'a member takes the room over from a gone owner');
    await button(thief, 'เริ่มเกม').click();
    check(await seen(thief, 'เกมเริ่มแล้ว'), 'the new owner starts the game');
  } else {
    // 5. The owner starts the game.
    await button(owner, 'เริ่มเกม').click();
    check(await seen(owner, 'เกมเริ่มแล้ว'), 'the owner starts the game');
  }
} finally {
  await browser.close();
}

console.log(failed === 0 ? '\nAll checks passed.' : `\n${failed} check(s) failed.`);
process.exit(failed === 0 ? 0 : 1);
