// Takes down the rooms that nobody needs any more (see select.mjs for which).
//
//   FIREBASE_SERVICE_ACCOUNT='{...json...}' node cleanup.mjs      (a dry run)
//   DRY_RUN=false MAX_DELETE=20 ... node cleanup.mjs              (deletes)
//
// Settings, all from the environment:
//   PROJECT_ID    the Firebase project (default hold-my-dice, the prod one)
//   DRY_RUN       anything but the word "false" only reports (default: report)
//   MAX_DELETE    most rooms taken down in one run (default 20)
//   FIREBASE_SERVICE_ACCOUNT  the JSON key of the service account; without it
//                 the default credentials are used, and with
//                 FIRESTORE_EMULATOR_HOST set no credentials are needed
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { cert, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { decide } from './select.mjs';

const ROOM_CODE = /^[A-Z0-9]{6}$/;

const dateOf = (value) => (value && typeof value.toDate === 'function' ? value.toDate() : null);

/** The newest of some dates, null for none. */
const newest = (dates) => dates.filter(Boolean).reduce((a, b) => (!a || b > a ? b : a), null);

/** What select.mjs needs to know about the room [ref]. */
async function readRoom(ref) {
  const [room, presence, entries] = await Promise.all([
    ref.get(),
    ref.collection('presence').get(),
    ref.collection('entries').orderBy('at', 'desc').limit(1).get(),
  ]);
  const data = room.data() ?? {};
  return {
    code: ref.id,
    exists: room.exists,
    status: data.status,
    createdAt: dateOf(data.createdAt),
    endedAt: dateOf(data.endedAt),
    lastPresence: newest(presence.docs.map((d) => dateOf(d.data().lastSeen))),
    lastEntry: newest(entries.docs.map((d) => dateOf(d.data().at))),
  };
}

/**
 * Looks at every room and, unless [dryRun], takes down at most [maxDelete] of
 * those that should go (the longest forgotten first). Returns what it found.
 */
export async function run({ db, now = new Date(), dryRun = true, maxDelete = 20, log = console.log }) {
  // listDocuments also gives the rooms whose own document is gone but that
  // still have presence or entries under them.
  const refs = await db.collection('rooms').listDocuments();
  const report = { seen: refs.length, deleted: [], wouldDelete: [], kept: [], skipped: [], leftForNextRun: [] };
  const doomed = [];
  for (const ref of refs) {
    if (!ROOM_CODE.test(ref.id)) {
      report.skipped.push({ code: ref.id, reason: 'not written like a room code' });
      continue;
    }
    const room = await readRoom(ref);
    const verdict = decide(room, now);
    log(`${room.code}  ${verdict.action.toUpperCase().padEnd(6)} ${verdict.reason}`);
    if (verdict.action === 'keep') report.kept.push({ code: room.code, reason: verdict.reason });
    else doomed.push({ ref, room, reason: verdict.reason });
  }
  // The longest forgotten first.
  const stamp = (r) => (r.room.endedAt ?? r.room.createdAt ?? r.room.lastPresence ?? new Date(0)).getTime();
  doomed.sort((a, b) => stamp(a) - stamp(b));
  for (const [i, d] of doomed.entries()) {
    const item = { code: d.room.code, reason: d.reason };
    if (dryRun) report.wouldDelete.push(item);
    else if (i >= maxDelete) report.leftForNextRun.push(item);
    else {
      // The room, and every document under it, whatever it is called.
      await db.recursiveDelete(d.ref);
      log(`${d.room.code}  DELETED`);
      report.deleted.push(item);
    }
  }
  return report;
}

function summary(report, { dryRun, maxDelete, project }) {
  const lines = [
    `## Room cleanup of \`${project}\` (${dryRun ? 'dry run: nothing was deleted' : 'real run'})`,
    '',
    `- rooms seen: ${report.seen}`,
    `- kept: ${report.kept.length}`,
    `- skipped (not room codes): ${report.skipped.length}`,
    dryRun
      ? `- would delete: ${report.wouldDelete.length}`
      : `- deleted: ${report.deleted.length} (at most ${maxDelete} per run), left for the next run: ${report.leftForNextRun.length}`,
  ];
  for (const item of [...report.wouldDelete, ...report.deleted, ...report.leftForNextRun]) {
    lines.push(`  - ${item.code}: ${item.reason}`);
  }
  return lines.join('\n') + '\n';
}

async function main() {
  const project = process.env.PROJECT_ID || 'hold-my-dice';
  const dryRun = process.env.DRY_RUN !== 'false';
  const maxDelete = Number.parseInt(process.env.MAX_DELETE ?? '20', 10);
  if (!Number.isInteger(maxDelete) || maxDelete < 0) throw new Error(`MAX_DELETE is not a number: ${process.env.MAX_DELETE}`);
  const key = process.env.FIREBASE_SERVICE_ACCOUNT;
  initializeApp({ projectId: project, ...(key ? { credential: cert(JSON.parse(key)) } : {}) });
  console.log(`${dryRun ? 'DRY RUN' : 'REAL RUN'} on ${project}, at most ${maxDelete} rooms`);
  const report = await run({ db: getFirestore(), dryRun, maxDelete });
  const text = summary(report, { dryRun, maxDelete, project });
  console.log('\n' + text);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, text);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
