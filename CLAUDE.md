# Working in this repo

Several Claude sessions often run against this one checkout at the same time. Most of what follows
exists because two of them got in each other's way.

## Simulators: reuse, and never leave one booted

A booted simulator is not a window — it is a full iOS system running inside the Mac, about **120
processes each**. On 2026-09-17 three sessions had each created their own and left it booted: 489
simulator processes, two copies of the app foregrounded on an animating screen at 74% and 63% CPU
for half an hour, memory down to 29% free, 376,000 pageouts, and a Mac the owner described as
"very slow". 15 GB of simulator data. None of it was doing anything for anyone.

So:

1. **Look for a booted simulator before creating one.** `xcrun simctl list devices | grep Booted`.
   If one is already up, install onto it and use it.
2. **If you create one, delete it when you are done** — in the same session, not "later":
   `xcrun simctl shutdown <id> && xcrun simctl delete <id>`. Deleting is cheap; a simulator is
   recreated in seconds and the app reinstalls from a build. Nothing in git depends on one.
3. **Never leave a simulator booted at the end of your work.** If you are unsure whether a device
   is someone else's, `xcrun simctl shutdown all` is always safe — it deletes nothing.
4. **Do not delete another session's device while it may be mid-photograph.** Check first: no
   `xcodebuild` running, and no source file touched in the last ten minutes.

The owner's private simulators for a specific job (`T2S Onb` for the welcome, say) are the one
exception to reuse — but they still must not be left booted.

## One `xcodebuild` at a time

Two concurrent builds fight over the same build database and each other's CPU. Symptoms seen here:
`unable to attach DB: accessing build database …` in Xcode, and command-line builds killed with
exit 137. Wait for the other build to finish before starting yours:

```bash
while pgrep -f "Developer/usr/bin/xcodebuild" >/dev/null; do sleep 5; done
```

`scripts/build-app.sh` builds into `.build/DerivedData-App`, which is separate from Xcode's own
DerivedData — but the CPU and the disk are still shared.

## Disk

This drive fills fast and has hit single-digit gigabytes free more than once. **Check `df -h /`
before any build that creates a new DerivedData** (a fresh worktree costs about 2.2 GB). Survey and
ask the owner before deleting any of their caches; deleting *your own* simulators and worktrees
needs no permission.

## Committing when sessions share the checkout

The working tree regularly holds another session's half-finished work, and sometimes their staged
files.

- **Always `git add` explicit paths.** Never `git add -A`, never a bare `git commit -a`.
- **Check the index first** (`git diff --cached --name-only`). If another session has files staged,
  they are mid-commit — do not commit.
- If a file you need is dirty with someone else's edits, leave your change in the working tree for
  them rather than committing their unfinished work along with yours.
- Before merging or pushing, `git fetch` and check `origin/dev..dev`: another session may have
  pushed your commits already.

## Screens that animate

`TimelineView(.animation)` redraws every frame for as long as its view is on screen. Anything built
on it (`ImportGraphic`, the onboarding reel) must stop its clock when the scene stops being active,
and resume on the same frame — a freeze that resumes somewhere else is worse than no freeze. This
does not help an app left *foregrounded* and unwatched; only rule 3 above does.

## Audio

Never play sound on the owner's Mac. The simulator only, and only with `SIMCTL_CHILD_T2S_SILENT=1`.
Never change the system volume.
