# Bragmat Beta — Tester Guide

Welcome to the Bragmat beta. Bragmat is a fishing log app for recording
your catches, trips and photos — your data stays on your phone.

This guide covers installing the beta and getting started. It assumes no
technical knowledge.

---

## Before you start

You will need:

1. An Android phone (Android 7 or newer).
2. The email address you gave the beta organiser — **you must sign up
   with exactly that email**, or the app will not let you in.
3. The Bragmat Beta app file or download link sent to you by the
   organiser.

---

## Step 1 — Install the app

The beta is not on the Play Store yet, so Android will ask for one extra
permission the first time.

1. Open the link or attachment the organiser sent you, and download the
   file `bragmat-beta-v10-release.apk`.
2. Tap the downloaded file.
3. If Android says "Install unknown apps" or "For your security, your
   phone is not allowed to install unknown apps":
   - Tap **Settings** on that prompt.
   - Turn on **Allow from this source** for the app you downloaded from
     (e.g. Chrome, Files, Gmail, or Drive).
   - Go back and tap the file again.
4. Tap **Install**, then **Open**.

If Play Protect shows a warning, tap **Install anyway** — the beta is
signed by the developer but not yet distributed through Google Play.

## Step 2 — Create your account

1. On the welcome screen, tap **"Invited? Create an account"**.
2. Enter **the email you were invited with** and choose a password
   (at least 6 characters).
3. Tap **Create Account**.
4. Check your email — you will receive a **confirmation link**
   (check Spam/Junk if it doesn't arrive in a few minutes).
5. Tap the link in the email. It opens the Bragmat app automatically and
   verifies your account.
6. Back in the app, sign in with your email and password.

You should land on the **My Catches** screen. If you instead see
"Awaiting Invitation", your account was created with an email that isn't
on the tester list — contact the organiser to check which email was
invited.

## Step 3 — Try it out

- Tap **+** (or Add Catch) on the Catches tab to record a catch.
- Attach photos with **Take Photo** or **Add Photo** — the app can use
  the photo's date and location.
- Explore the **Trips**, **Map**, **Stats** and **Settings** tabs.
- In **Settings → Tide Reference**, choose **Automatic** or pick a fixed
  tide station.

The app works **offline** — catches, photos and trips are stored on your
phone and stay there. Cloud backup is **not** part of this beta.

## Optional — tide data key (WorldTides)

Detailed tide predictions need a free WorldTides API key. Without one,
the app still works fully — you just get weather/moon data and can enter
tide details manually.

1. Go to <https://www.worldtides.info/> and register for a free account.
2. Copy your API key from their site.
3. In Bragmat: **Settings → API Keys**, paste the key into
   **WorldTides API Key**.
4. Tap **Test API** — you should see a success message.

If the organiser gave you a shared key instead, just paste it the same
way — skip steps 1–2.

## Making backups

Your data lives only on your phone, so occasional backups are a good
idea:

- **Settings → Backup Data** creates a single `.zip` file containing all
  catches and photos. Keep a copy somewhere off the phone (email it to
  yourself, or save to Drive).

## Reporting problems

If something goes wrong or looks odd, tell the organiser:

- **What you were doing** (e.g. "I tapped Add Catch and attached a photo")
- **What happened** vs what you expected
- **A screenshot** if possible (hold Power + Volume Down)
- **Your phone model** (e.g. Samsung A54)

If the app crashes or freezes, note roughly when it happened — that helps
find it in diagnostics.

## Notes

- The beta can be updated in place — if you get a newer app file, install
  it the same way; your data and sign-in are preserved.
- To remove the beta, uninstall "Bragmat" — **warning**: uninstalling
  permanently deletes all catches and photos stored in the app. Make a
  backup first.
