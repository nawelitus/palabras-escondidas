# Play Console: suggested answers

These answers match what the app really does (checked against the code and the exported manifest). Re-verify them before submitting if the app changes, for example if ads, analytics or internet access are ever added.

## App content > Data safety

- Does your app collect or share any of the required user data types? **No**
- Because nothing is collected or shared, the remaining sections stay empty.
- Security practices: data is not transmitted, so "data is encrypted in transit" does not apply.
- What is stored locally: high score, chosen skin, sound and vibration switches (never leaves the device).

## App content > Privacy policy

Needs a public URL. Source text: store/privacy_policy_es.md, published as docs/privacy_policy.html.

Planned URL: https://nawelitus.github.io/palabras-escondidas/privacy_policy.html

It works once the repository is public and GitHub Pages is enabled: repository Settings > Pages >
Build and deployment > Deploy from a branch > branch `master`, folder `/docs`. Open the URL in a
browser before pasting it into Play Console.

## App content > Ads

Contains ads: **No**.

## App content > Content rating (IARC questionnaire)

Expected answers, all "No": violence, blood, fear, sexual content, language, controlled substances, gambling, user-generated content, sharing of location, digital purchases. The expected result is the lowest age rating. The category is "Game", subtype word/puzzle.

## App content > Target audience

Age groups: **13+** (do not select under 13, which would trigger the Families policy).

## App content > Government apps, Financial features, Health

Not applicable.

## App access

All functionality is available without any login.

## Release

- Format: Android App Bundle (.aab), release-signed with the upload key.
- Package: com.palabrasescondidas.game
- Target SDK: 36 (required since 2026-08-31 for new apps and updates).
- Play App Signing: accept it (Google keeps the app signing key, we only keep the upload key).

## Account requirement to check

Personal developer accounts created after 2023-11-13 must run a closed test with at least 12 testers opted in for 14 continuous days before production access. Organization accounts are exempt.
