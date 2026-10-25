# Runs the rules tests on the Firestore emulator from the repo root.
# On Windows the emulator's Java process can outlive "emulators:exec" and then
# blocks port 8080 on the next run, so any left-over one is stopped before and
# after the run.
$ErrorActionPreference = 'Stop'

function Stop-LeftoverEmulator {
  Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" |
    Where-Object { $_.CommandLine -like '*cloud-firestore-emulator*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

Set-Location (Join-Path $PSScriptRoot '..')
Stop-LeftoverEmulator
try {
  firebase emulators:exec --only firestore --project demo-hold-my-dice "npm --prefix firebase_tests test"
  $code = $LASTEXITCODE
} finally {
  Stop-LeftoverEmulator
}
exit $code
