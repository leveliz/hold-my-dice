# Smoke test after a deploy

Run this after deploying `firestore.rules` or a new web build. Use the dev
project first; repeat the short list on prod once dev is green.

## Deploy

```
git tag pre-<what>-deploy          # so the previous state can be restored
firebase deploy --only firestore --project dev     # or: prod
```

`.firebaserc` maps `dev` to `hold-my-dice-dev` and `prod` to `hold-my-dice`.
To go back: check out the tag and deploy again.

## Automated (dev only, it makes a real room)

```
flutter build web --release --dart-define=FIREBASE_ENV=dev --output=build/web_dev
python <a static server with index.html fallback> build/web_dev 8095
cd tool/e2e && npm install && node two_browsers.mjs http://127.0.0.1:8095
```

`E2E_QUICK=1` skips the two checks that wait over 2 minutes each (presence).

## By hand on the live site (https://hold-my-dice.pages.dev)

1. Open Pocket Banker: the choice "เครื่องเดียว / หลายเครื่อง" appears.
2. Create a room; the waiting room shows the code, a QR and your seat.
3. On another phone, scan the QR (or open the link): the join form opens with
   the room code and the name of the owner.
4. Join: the owner's list shows the newcomer without reloading.
5. Close the newcomer's page, wait 2 minutes, and take the seat over from a
   third device: it works. Doing the same while the page is still open is
   refused.
6. Start the game from the owner's phone: everyone leaves the waiting room.
7. Open `/room/ZZZZZZ`: "ห้องนี้จบแล้วหรือไม่มีอยู่" (not the router error page).

## Rules

The rules have their own tests: `powershell -File firebase_tests/run-rules-tests.ps1`.
