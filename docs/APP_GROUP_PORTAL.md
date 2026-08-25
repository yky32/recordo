# App Group portal checklist (Live Activity)

Group **created**: `group.com.recordo.live`

## Required on both App IDs
1. https://developer.apple.com/account/resources/identifiers/list
2. Open **Recordo** (`com.recordo`)
3. Enable **App Groups** → Configure → tick `group.com.recordo.live` → Save
4. Open **Recordo Live Activity** (`com.recordo.RecordoLiveActivity`)
5. Same: App Groups → tick `group.com.recordo.live` → Save
6. Tell agent → restore entitlements + force profile regen + TF

Until both IDs include the group, CI provisioning profiles reject the entitlement and TF archive fails.
