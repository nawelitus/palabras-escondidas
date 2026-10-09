# Play Console: suggested answers

These answers match what the app really does (checked against the code and the exported manifest). Re-verify them before submitting if the app changes, for example if ads, analytics or internet access are ever added.

## App content > Data safety

- Does your app collect or share any of the required user data types? **No** (the developer receives nothing: there are no servers, no analytics, no ads).
- Multiplayer: a player's chosen name and found words travel over the local WiFi to the device that hosts the room, which is another player's phone. This is user-to-user traffic inside the user's own network, never sent to the developer or to a third party. If Play Console's wizard insists on classifying it, the closest fit is Personal info > Name, shared with other users at the user's request, not collected; the app has no accounts or ids.
- Security practices: nothing leaves the local network, so there is no transmission to the developer. Room traffic on the LAN is not encrypted (say so if asked).
- Data deletion: stored locally only; removed by uninstalling or clearing the app's data.
- What is stored locally: high scores per round length, chosen skin and round length, sound and vibration switches, the player name used in rooms, and the last 20 multiplayer sessions (never leaves the device).

## App content > Privacy policy

Needs a public URL. Source text: store/privacy_policy_es.md, published as docs/privacy_policy.html.

Planned URL: https://nawelitus.github.io/palabras-escondidas/privacy_policy.html

It works once the repository is public and GitHub Pages is enabled: repository Settings > Pages >
Build and deployment > Deploy from a branch > branch `master`, folder `/docs`. Open the URL in a
browser before pasting it into Play Console.

## App content > Ads

Contains ads: **No**.

## App content > Content rating (IARC questionnaire)

Expected answers, all "No": violence, blood, fear, sexual content, language, controlled substances, gambling, sharing of location, digital purchases. The category is "Game", subtype word/puzzle.

Multiplayer changes one answer to review: users can see each other's chosen names inside a room (no chat, no free messages, no media). If the questionnaire asks whether users interact or exchange content, answer honestly (names only, local network only, no chat); this can raise the rating slightly ("users interact" notice), which is fine for 13+.

## App content > Target audience

Age groups: **13+** (do not select under 13, which would trigger the Families policy).

## App content > Government apps, Financial features, Health

Not applicable.

## App access

All functionality is available without any login. Multiplayer needs at least two devices on the same WiFi network; reviewers can verify it with two devices or one device plus the emulator.

## Permissions declared

`INTERNET` (needed for local sockets in multiplayer; the app never contacts a remote server) and `VIBRATE`. No other permission.

## Release

- Format: Android App Bundle (.aab), release-signed with the upload key.
- Package: com.palabrasescondidas.game
- Target SDK: 36 (required since 2026-08-31 for new apps and updates).
- Play App Signing: accept it (Google keeps the app signing key, we only keep the upload key).

## Account requirement to check

Personal developer accounts created after 2023-11-13 must run a closed test with at least 12 testers opted in for 14 continuous days before production access. Organization accounts are exempt.
