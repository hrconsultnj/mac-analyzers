# Excerpt: login-items-audit.sh — finding launchers of uninstalled apps

Real dry-run output (username anonymized). TeamViewer had been uninstalled
long ago; its launchers were still registered at every login. OneDrive's
updater daemons likewise.

```
### 1. ~/Library/LaunchAgents (user — removable without sudo)
  [ORPHAN]  org.xbmc.helper
            plist:  ~/Library/LaunchAgents/org.xbmc.helper.plist
            target: /Applications/Kodi.app/.../XBMCHelper  (MISSING)

### 2. /Library/LaunchAgents + /Library/LaunchDaemons (system — sudo needed)
  [ORPHAN·sudo]  com.teamviewer.desktop
                 target: /Applications/TeamViewer.app/Contents/MacOS/TeamViewer_Desktop_Proxy  (MISSING)
  [ORPHAN·sudo]  com.microsoft.OneDriveStandaloneUpdater
                 target: /Applications/OneDrive.app/.../OneDriveStandaloneUpdater  (MISSING)
  [ORPHAN·sudo]  com.microsoft.OneDriveUpdaterDaemon
                 target: /Applications/OneDrive.app/.../OneDriveUpdaterDaemon  (MISSING)

  [LEFTOVER?]  com.teamviewer.Helper  — target exists
               (/Library/PrivilegedHelperTools/com.teamviewer.Helper) but NO app
               from vendor 'com.teamviewer' is installed. Review; if unwanted:
               sudo launchctl bootout system/com.teamviewer.Helper; sudo rm ...

 DRY RUN — user-level orphans: 1, system-level: 7.
 Remove user-level with: ./login-items-audit.sh --apply

 System-level removals need sudo — run these yourself:
   sudo launchctl bootout system/com.teamviewer.desktop 2>/dev/null; sudo rm '...'
   ...
```

Two classes, two certainties:

- `[ORPHAN]` — the target binary is **gone**; the entry cannot run; removal
  cannot break anything. `--apply` removes user-level ones automatically.
- `[LEFTOVER?]` — the helper binary survived but no app from that vendor is
  installed (helpers outlive their apps). Review-only, never auto-removed.
