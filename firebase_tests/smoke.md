# Release, rollback and smoke test

How a change that touches `firestore.rules` or the web build goes live, how to
go back, how to run the room cleanup, and what to try by hand on real phones.
`.firebaserc` maps `dev` to `hold-my-dice-dev` and `prod` to `hold-my-dice`.

## Order of a release

**Rules first, then the app.** A new rules file accepts everything an older app
writes (it is a superset), so it is safe on its own. A new app against old
rules has its writes refused (ending a game, closing a room, a payment with a
mortgage, a bankruptcy, the banker's presses). The web app goes live when
`main` is pushed, so the rules must already be on prod by then.

Players with the page open keep the old app until they reload. An older page
shows "ยอดไม่ตรง" on an entry it does not understand and its buttons stay off
until it is reloaded, so tell the players to reload after a release.

## Release, step by step

Run everything from the repository root, on `dev`, with the work committed.

1. Tests and builds, all green:

   ```
   dart format --set-exit-if-changed lib test
   flutter analyze
   flutter test
   powershell -File firebase_tests/run-rules-tests.ps1
   npm --prefix tool/cleanup ci
   firebase emulators:exec --only firestore --project demo-hold-my-dice "npm --prefix tool/cleanup test"
   flutter build apk
   flutter build web --release
   ```

2. Tag what is on dev now, then put the rules on the dev project:

   ```
   git tag pre-<what>-dev-rules-deploy
   firebase deploy --only firestore:rules --project dev
   ```

3. The automated check on the dev project (it makes real rooms, see below). It
   must pass before anything goes to prod:

   ```
   flutter build web --release --dart-define=FIREBASE_ENV=dev --output=build/web_dev
   python <a static server with index.html fallback> build/web_dev 8095
   cd tool/e2e && npm install && E2E_QUICK=1 node two_browsers.mjs http://127.0.0.1:8095
   ```

   Check that nothing else already listens on port 8095: an old server that
   serves `build/web` (the single-device build) makes the check fail at the
   first join.

4. Push `dev` (`git push origin dev`) and ask for the release.

5. The person who releases types these two, in this order (the rules before
   the app):

   ```
   git tag pre-<what>-prod-rules-deploy origin/main
   firebase deploy --only firestore:rules --project prod
   git push origin dev:main
   ```

6. Wait for the GitHub Action "Deploy web" (`gh run watch`), then run the same
   check on the live site (`E2E_QUICK=1` skips the two that wait over 2 minutes;
   if only the eight-browsers-at-once checks fail, run it once more, they race):

   ```
   cd tool/e2e && E2E_QUICK=1 node two_browsers.mjs https://hold-my-dice.pages.dev
   ```

7. Go through the short list by hand below, on a real phone.

## Going back

- **Rules.** Take the file from the tag made before the deploy and deploy it
  again, on the same project:

  ```
  git show pre-<what>-prod-rules-deploy:firestore.rules > firestore.rules
  firebase deploy --only firestore:rules --project prod
  git checkout firestore.rules
  ```

  Roll the app back at the same time (next point): old rules refuse what a new
  app writes, and a room that already has a banker loses the banker's presses
  with rules from before 7e.
- **Web app.** Either redeploy the previous build in the Cloudflare Pages
  dashboard (Deployments, the one before, Rollback to this deployment), or
  `git revert <the commits>` and push `main`: the Action builds it again.
- **Room cleanup.** Stop the deleting by deleting the repository variable
  `CLEANUP_DELETE` (or setting it to anything but `true`): the nightly run then
  only reports. To stop even that, disable the workflow "Clean up rooms" under
  Actions. Rooms that were deleted are gone; there is no undo, which is why the
  first runs only report.

## Room cleanup (`.github/workflows/cleanup-rooms.yml`)

It takes down the rooms nobody needs (`tool/cleanup/select.mjs` has the rules):
a game that ended over 6 hours ago; a room over 24 hours old with no beat of
presence in 2 hours and no entry in 6; what is left under a room that was
deleted. Rooms whose names are not room codes are never touched. At most 20
rooms go in one run.

It uses the secret `FIREBASE_SERVICE_ACCOUNT` of the GitHub environment
`prod-cleanup` (only `main` can use it): the key of the service account
`room-cleanup@hold-my-dice.iam.gserviceaccount.com`, role Cloud Datastore User.
To change the key, make a new one under that service account in Google Cloud
(IAM & Admin, Service Accounts, Keys), replace the secret, then delete the old
key and the downloaded file.

**First use, once it is on `main`:**

1. Actions, Clean up rooms, Run workflow, from `main`, with "Only report" on.
   Open the run and read its summary: every room it would delete, with the
   reason. A permission error here means the service account lacks the role.
2. Let the nightly runs report for 2 or 3 nights and read them the same way.
3. Only then set the repository variable `CLEANUP_DELETE` to `true`
   (Settings, Secrets and variables, Actions, Variables). From the next night it
   deletes. A manual run with "Only report" off deletes at once, up to
   "Most rooms to delete".

The same rules and the deleting are tested on the Firestore emulator:

```
npm --prefix tool/cleanup ci
firebase emulators:exec --only firestore --project demo-hold-my-dice "npm --prefix tool/cleanup test"
```

## Automated check (dev only, it makes real rooms)

`tool/e2e/two_browsers.mjs` drives up to nine browsers through the rooms: join
from a link, a password room, taking over a seat or a room, a game of eight
with a watcher (presses, a mortgage, a bankruptcy, the banker, offline and
reload), ending the game, the summary, playing again and closing the old room.
It leaves rooms behind on dev; delete them by hand if you want it clean. The
emulator variant (`FIREBASE_EMULATOR=127.0.0.1` with `firebase emulators:start
--only firestore,auth`) runs the same file against local rules.

## By hand on real phones

Once on an Android phone (the APK, `flutter build apk`) and once on an iPhone
(Safari, on the live site). Two or three devices at the same time; the
internet should be a real one, not the office Wi-Fi alone.

1. Open Pocket Banker: the choice "เครื่องเดียว / หลายเครื่อง" appears.
2. Create a room; the waiting room shows the code, a QR and your seat. Copy
   the link and send it by a chat app.
   A phone that has not seen the tours is shown one in the waiting room and
   another when the game starts (Settings can show them again, with the one
   of Pocket Banker).
3. On another phone, scan the QR or open the link: the join form opens with
   the room code and the owner's name. Join; the owner's list shows the
   newcomer without reloading.
4. Close the newcomer's page, wait 2 minutes, and take the seat over from a
   third device: it works. Doing the same while the page is still open is
   refused.
5. Start the game from the owner's phone: everyone leaves the waiting room.
   Press GO, a payment, a request to pay: the other phones show it at once.
6. Lock one phone for a minute, unlock: it is back in the game with no
   "offline" bar left. Turn flight mode on: the buttons go off within about 12
   seconds and come back with the signal.
7. Reload the page of a player: they are back in the game; the mode picker
   offers "กลับเข้าห้อง".
8. End the game from the owner's phone ("จบเกม", asked once): every phone,
   a watcher's too, shows the podium with all the balances and a line "ห้องจะ
   ถูกปิดใน X:XX" that counts down.
9. The owner presses "เล่นอีกรอบ": the others see "มีห้องใหม่แล้ว"; one tap on
   "เข้าร่วม" puts them in the new waiting room with the same name and colour.
10. Back on the old summary the owner presses "ปิดห้อง": asked once, then home;
    the others who still look at it are told the room is gone. A player has
    only "ออกจากห้อง".
11. Let a summary count down to 0 on a player's phone: the room goes without
    anyone pressing. Open `/room/ZZZZZZ`: "ห้องนี้จบแล้วหรือไม่มีอยู่" (not the
    router error page).
12. An older app against a room of a newer layout is told "ต้องอัปเดตแอพก่อน
    เข้าห้องนี้" and does not keep asking. (Cannot be tried by hand until a
    newer layout exists; the unit tests cover it.)

## Rules

The rules have their own tests: `powershell -File firebase_tests/run-rules-tests.ps1`
(a Firestore emulator and Node are needed).
