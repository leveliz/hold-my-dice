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

  // The emulator's warning strip would sit on top of the bottom buttons.
  await p.page.addStyleTag({ content: '.firebase-emulator-warning{display:none!important}' });
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
async function keys(p, digits) {
  for (const d of digits) await p.page.getByRole('button', { name: d, exact: true }).first().click();
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
    check(await seen(thief, 'ยอดของฉัน'), 'the new owner starts the game');
  } else {
    // 5. The owner starts the game.
    await button(owner, 'เริ่มเกม').click();
    check(await seen(owner, 'ยอดของฉัน'), 'the owner starts the game');
  }

  // 6. Playing: eight players and a watcher, at the same time.
  const reasonText = 'ก'.repeat(50) + '😀'.repeat(5); // exactly 60 UTF-16 units
  const gone = async (p, t, timeout = 20000) => {
    try {
      await p.page.getByText(t).first().waitFor({ state: 'detached', timeout });
      return true;
    } catch {
      return false;
    }
  };
  const count = (p, t, opts = {}) => p.page.getByText(t, opts).count();
  const host = await person('host');
  await open(host, '/room/create');
  await typeName(host, 'P1');
  await button(host, 'เพิ่มที่นั่ง').click();
  await button(host, 'เพิ่มที่นั่ง').click();
  await button(host, 'ออกตั๋วห้อง').click();
  await host.page.waitForURL(/\/room\/[A-Z0-9]{6}$/, { timeout: 30000 });
  const playCode = host.page.url().split('/').pop();
  const players = [host];
  for (let k = 2; k <= 8; k++) {
    const g = await person(`P${k}`);
    await open(g, `/room/${playCode}`);
    await seen(g, 'ชวนคุณเข้าห้อง');
    await typeName(g, `P${k}`);
    await button(g, 'นั่งโต๊ะ').click();
    await seen(g, 'ห้องรอ');
    players.push(g);
  }
  const watcher = await person('watcher');
  await open(watcher, `/room/${playCode}`);
  await seen(watcher, 'ชวนคุณเข้าห้อง');
  await typeName(watcher, 'Watcher');
  await button(watcher, 'ขอดูเฉย ๆ').click();
  await seen(watcher, 'ห้องรอ');
  await button(host, 'เริ่มเกม').click();
  const everyoneIn = await Promise.all([...players, watcher].map((p) => seen(p, p === watcher ? 'คุณเป็นผู้ชม' : 'ยอดของฉัน')));
  check(everyoneIn.every(Boolean), 'all 8 players and the watcher reach the play screen');

  // 6a. Eight GO presses at the same moment: every one is written once.
  await Promise.all(players.map((p) => button(p, 'GO', true).click()));
  // Flutter merges a row's texts into one accessibility node, so the screen is
  // read as lines of text.
  const screenText = (p) =>
    p.page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')].map((e) => (e.innerText || e.getAttribute('aria-label') || '').trim()).join('\n'),
    );
  let at1700 = 0;
  for (let i = 0; i < 40 && at1700 < 8; i++) {
    const lines = (await screenText(host)).split('\n');
    at1700 = new Set(lines.filter((l) => /^(ยอดของฉัน · )?P\d 1,700$/.test(l))).size;
    if (at1700 < 8) await sleep(500);
  }
  check(at1700 === 8, `eight presses at once all went in (${at1700} of 8 players are at 1,700 on the host screen)`);
  await host.page.getByText('ทั้งหมด').first().click();
  check(await seen(host, 'ประวัติทั้งหมด'), 'the host opens the full history');
  await sleep(1000);
  const goBy = new Set([...(await screenText(host)).matchAll(/ผ่านจุดเริ่ม (P\d)/g)].map((m) => m[1]));
  check(goBy.size === 8, `the history holds a GO line for each of the eight players (${goBy.size})`);
  await host.page.keyboard.press('Escape');
  await sleep(1800);

  // 6a2. Three more rounds of eight at once: more entries than a device holds.
  for (let round = 0; round < 3; round++) {
    await sleep(2000);
    await Promise.all(players.map((p) => button(p, 'GO', true).click()));
  }
  let at2300 = 0;
  for (let i = 0; i < 40 && at2300 < 8; i++) {
    const lines = (await screenText(host)).split(String.fromCharCode(10));
    at2300 = new Set(lines.filter((l) => /^(ยอดของฉัน · )?P\d 2,300$/.test(l))).size;
    if (at2300 < 8) await sleep(500);
  }
  check(at2300 === 8, `32 presses in four rounds all went in (${at2300} of 8 players are at 2,300)`);
  await host.page.getByText('ทั้งหมด').first().click();
  check(await seen(host, 'แสดง 30 รายการล่าสุด'), 'a game longer than the window lists the newest 30');
  await host.page.keyboard.press('Escape');
  await sleep(1800);

  // 6b. A receive with the longest reason (Thai and emoji, 60 units); one unit
  // more is not accepted.
  const p2 = players[1];
  await button(p2, 'รับเงิน').click();
  await keys(p2, '7');
  const reasonBox = p2.page.getByRole('textbox').first();
  await reasonBox.click();
  await reasonBox.pressSequentially(reasonText + 'ข', { delay: 15 });
  await button(p2, 'ตกลง').click();
  await sleep(2500);
  await host.page.getByText('ทั้งหมด').first().click();
  await sleep(1000);
  check((await count(host, reasonText, { exact: false })) >= 1, 'the 60-unit Thai and emoji reason is stored whole');
  check((await count(host, reasonText + 'ข', { exact: false })) === 0, 'a 61st unit was not accepted');
  await host.page.keyboard.press('Escape');

  // 6b2. Transfers and taking back. Balances as the screens show them.
  const balancesOn = async (p) => {
    const out = {};
    for (const l of (await screenText(p)).split('\n')) {
      const m = l.match(/^(?:ยอดของฉัน · )?(P\d) ([\d,]+)$/);
      if (m) out[m[1]] = Number(m[2].replace(/,/g, ''));
    }
    return out;
  };
  const waitFor = async (fn, ms = 15000) => {
    for (let t = 0; t < ms; t += 400) {
      if (await fn()) return true;
      await sleep(400);
    }
    return false;
  };
  await waitFor(async () => (await balancesOn(host)).P1 !== undefined);
  const before1 = (await balancesOn(host)).P1;
  const before2 = (await balancesOn(players[1])).P2;
  await button(host, /^P2 [\d,]+/).click();
  await button(host, 'โอนให้ P2').click();
  await keys(host, '500');
  await button(host, 'ตกลง').click();
  check(await seen(host, 'โอน 500 ให้P2แล้ว', 10000), 'the giver gets the bar to take the transfer back');
  check(await waitFor(async () => (await balancesOn(players[1])).P2 === before2 + 500), 'the receiver sees the money arrive');
  check(await seen(players[1], 'P1 โอนให้คุณ +500', 8000), 'and is told who sent it');
  check((await balancesOn(host)).P1 === before1 - 500, 'the giver sees the balance go down');
  await button(host, 'เลิกทำ').click();
  check(await waitFor(async () => (await balancesOn(host)).P1 === before1), 'taking it back gives the giver the money back');
  check(await waitFor(async () => (await balancesOn(players[1])).P2 === before2), 'and takes it from the receiver');
  check(await seen(players[1], 'P1 ยกเลิกการโอน 500', 8000), 'who is told it was taken back');
  await sleep(2000);

  // A take-back against somebody else's press at the same moment: whatever
  // wins, every screen shows the same books and none cries "balances differ".
  await button(host, /^P2 [\d,]+/).click();
  await button(host, 'โอนให้ P2').click();
  await keys(host, '100');
  await button(host, 'ตกลง').click();
  await seen(host, 'โอน 100 ให้P2แล้ว', 10000);
  await Promise.allSettled([button(host, 'เลิกทำ').click({ timeout: 3000 }), button(players[2], 'GO', true).click()]);
  await sleep(4000);
  const hostBooks = await balancesOn(host);
  const watchBooks = await balancesOn(watcher);
  check(
    Object.keys(watchBooks).length === 8 && Object.entries(hostBooks).every(([k, v]) => watchBooks[k] === v),
    'after a take-back that races a press, the host and the watcher see the same balances',
  );
  check(!(await seen(host, 'ยอดไม่ตรงกับประวัติ', 1500)), 'and no screen says the balances differ');
  await sleep(2500);

  // 6b3. Requests to pay.
  const askFriend = async (p, name, digits) => {
    await button(p, new RegExp('^' + name + ' [\\d,]+')).click();
    await button(p, 'เรียกเก็บจาก ' + name).click();
    await keys(p, digits);
    await button(p, 'ส่งคำขอ').click();
  };
  await sleep(1500);
  const hostBefore = (await balancesOn(host)).P1;
  const p2Before = (await balancesOn(players[1])).P2;
  await askFriend(host, 'P2', '300');
  let waiting = false;
  try {
    await button(host, 'ยกเลิก').waitFor({ state: 'attached', timeout: 10000 });
    waiting = true;
  } catch {}
  check(waiting, 'the one who asks sees the request waiting (with its cancel button)');
  check(await seen(players[1], 'P1 เรียกเก็บ', 10000), 'the one who is asked sees the request');
  await askFriend(host, 'P2', '50');
  check(await seen(host, 'มีคำขอถึงคนนี้รออยู่แล้ว', 8000), 'asking the same person again is refused in words');
  await sleep(1200);
  await button(players[1], 'จ่าย 300').click();
  check(await waitFor(async () => (await balancesOn(players[1])).P2 === p2Before - 300), 'paying takes the money from the payer');
  check(await waitFor(async () => (await balancesOn(host)).P1 === hostBefore + 300), 'and gives it to the one who asked');
  check(await seen(host, 'P2 จ่ายตามที่เรียกเก็บ +300', 8000), 'who is told it was paid');
  check(await waitFor(async () => !(await seen(host, 'รอP2จ่าย', 500))), 'and the waiting bar is gone');
  await sleep(2500);

  // Saying no.
  await askFriend(host, 'P2', '40');
  await seen(players[1], 'P1 เรียกเก็บ', 10000);
  await button(players[1], 'ไม่จ่าย').click();
  check(await seen(host, 'คำขอถูกยกเลิก', 8000), 'the one who asked is told it was said no to');
  check((await balancesOn(host)).P1 === hostBefore + 300, 'and no money moved');

  // The asker takes it back while the payer pays: one of the two wins, and
  // every screen shows the same books.
  await askFriend(host, 'P2', '60');
  await seen(players[1], 'P1 เรียกเก็บ', 10000);
  await sleep(1000);
  await Promise.allSettled([button(host, 'ยกเลิก').click({ timeout: 3000 }), button(players[1], 'จ่าย 60').click({ timeout: 3000 })]);
  await sleep(4000);
  const afterHost = await balancesOn(host);
  const afterWatch = await balancesOn(watcher);
  check(
    Object.keys(afterWatch).length === 8 && Object.entries(afterHost).every(([k, v]) => afterWatch[k] === v),
    'after a cancel that races a payment, the host and the watcher see the same balances',
  );
  check(afterHost.P1 === hostBefore + 300 || afterHost.P1 === hostBefore + 360, 'and the request was either paid or not, never half');
  check(!(await seen(host, 'ยอดไม่ตรงกับประวัติ', 1500)), 'and no screen says the balances differ');
  await sleep(2500);
  if (!quick) {
    await askFriend(host, 'P2', '70');
    await sleep(125_000);
    check(await seen(host, 'คำขอหมดอายุ', 8000), 'a request nobody answers runs out after 2 minutes');
    check(!(await seen(players[1], 'P1 เรียกเก็บ', 1500)), 'and the card of the one asked goes away');
  }

  // 6c. Not enough money: mortgage and pay in one press; going bankrupt.
  const thousands = (n) => n.toLocaleString('en-US');
  const p3 = players[2];
  await waitFor(async () => (await balancesOn(p3)).P3 !== undefined);
  const b3 = (await balancesOn(p3)).P3;
  const owes3 = b3 + 500;
  await button(p3, 'จ่ายธนาคาร').click();
  await keys(p3, String(owes3));
  await button(p3, 'ตกลง').click();
  check(await seen(p3, 'เงินไม่พอ', 8000), 'paying more than you hold opens the "not enough money" sheet');
  check(await seen(p3, 'ขาด 500', 3000), 'and says what is missing');
  const mortgageBox = p3.page.getByRole('textbox').first();
  for (let attempt = 0; attempt < 4 && !(await button(p3, 'เพิ่ม').isEnabled()); attempt++) {
    // Flutter's text field sometimes loses the first keys of a fresh focus.
    await mortgageBox.click();
    await sleep(400);
    await mortgageBox.pressSequentially('600', { delay: 80 });
    await sleep(400);
  }
  await button(p3, 'เพิ่ม').click();
  await button(p3, `จ่าย ${thousands(owes3)}`).click();
  check(await waitFor(async () => (await balancesOn(p3)).P3 === 100), 'a payment helped by a mortgage leaves what is over');
  check(await waitFor(async () => (await balancesOn(host)).P3 === 100), 'and the host sees the same balance');
  await sleep(4500);

  // 6d. Without a connection the money buttons go off within about 12 seconds,
  // and come back with the signal.
  const p4 = players[3];
  const lostAt = Date.now();
  await p4.ctx.setOffline(true);
  const offlineSeen = await seen(p4, 'ออฟไลน์', 25000);
  const took = (Date.now() - lostAt) / 1000;
  check(offlineSeen && took < 20, `the offline bar shows (after ${took.toFixed(1)} s)`);
  check(await button(p4, 'GO', true).isDisabled(), 'the money buttons are off while offline');
  await p4.ctx.setOffline(false);
  check(await gone(p4, 'ออฟไลน์', 30000), 'the bar goes away when the signal is back');
  check(await button(p4, 'GO', true).isEnabled(), 'and the buttons work again');

  // 6e. Reloading the page puts the player back in the game, and the mode
  // picker offers the way back.
  const p5 = players[4];
  await p5.page.reload();
  await p5.page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 30000 });
  await p5.page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  check(await seen(p5, 'ยอดของฉัน', 20000), 'a reloaded page is back in the game');
  await open(p5, '/bank');
  check(await seen(p5, `กลับเข้าห้อง ${playCode}`, 20000), 'the mode picker offers the way back to the room');
  await p5.page.getByText(`กลับเข้าห้อง ${playCode}`).first().click();
  check(await seen(p5, 'ยอดของฉัน', 20000), 'the card leads back to the play screen');

  // 6f. The watcher sees the same history and cannot press.
  check(await seen(watcher, 'P8'), 'the watcher sees the players');
  check((await watcher.page.getByRole('button', { name: 'GO', exact: true }).count()) === 0, 'the watcher has no money buttons');
  const p6 = players[5];
  await waitFor(async () => (await balancesOn(p6)).P6 !== undefined);
  const owes6 = (await balancesOn(p6)).P6 + 1000;
  // (The latest line of the history also starts with these words, so the
  // button is looked up by its whole name.)
  const payBankButton = p6.page.getByRole('button', { name: 'จ่ายธนาคาร', exact: true });
  await waitFor(() => payBankButton.isEnabled());
  await payBankButton.click();
  await keys(p6, String(owes6));
  await button(p6, 'ตกลง').click();
  await seen(p6, 'เงินไม่พอ', 8000);
  await button(p6, 'ล้มละลาย').first().click();
  check(await seen(p6, 'ล้มละลาย?', 5000), 'going bankrupt asks for a confirmation first');
  await button(p6, 'ล้มละลาย').last().click();
  check(await seen(p6, 'คุณออกจากเกมแล้ว', 10000), 'the one who went bankrupt is out of the game');
  check(await seen(host, 'P6 ล้มละลาย', 8000), 'the others are told');
  check(
    await waitFor(async () => (await screenText(host)).split(String.fromCharCode(10)).some((l) => /^P6 .*ออกจากเกม/.test(l))),
    'and see the seat marked as out',
  );
  check(
    (await p6.page.getByRole('button', { name: 'จ่ายธนาคาร', exact: true }).count()) === 0,
    'the one who is out has no money buttons of their own (the banker has only the ones for the friends)',
  );
  await sleep(4500);


  // 6g. The one who went out first is the banker: presses the bank's buttons
  // for the others, hands the seat on.
  check(await seen(p6, 'คุณเป็นนายธนาคาร', 8000), 'the first to go out is told they are the banker');
  check(await seen(host, 'นายธนาคาร P6', 8000), 'the others see who the banker is');
  check((await host.page.getByRole('button', { name: 'GO', exact: true }).count()) === 0, 'a player has no GO button while there is a banker');
  const hostBeforeGo = (await balancesOn(host)).P1;
  await p6.page.getByRole('button', { name: 'GO', exact: true }).first().click();
  check(await waitFor(async () => (await balancesOn(host)).P1 === hostBeforeGo + 200), 'the banker pressed GO for the first friend');
  check(await seen(host, 'นายธนาคาร P6 กด GO ให้คุณ +200', 8000), 'who is told it was the banker');
  await button(p6, 'ส่งต่อ').click();
  await seen(p6, 'ส่งต่อตำแหน่งนายธนาคารให้', 5000);
  await p6.page.getByText('P1', { exact: true }).last().click();
  check(await seen(host, 'คุณเป็นนายธนาคาร', 8000), 'the seat is handed to a friend, who is the banker now');
  check((await host.page.getByRole('button', { name: 'GO', exact: true }).count()) >= 1, 'who has the GO button of their own again');
} finally {
  await browser.close();
}

console.log(failed === 0 ? '\nAll checks passed.' : `\n${failed} check(s) failed.`);
process.exit(failed === 0 ? 0 : 1);
