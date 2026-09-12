# CTLD 2.0.0-rc9 — release candidate

> **If you installed a mission with rc8, re-install it with this version.** rc8's engine does not
> start: it fails while loading, and your mission ends up with no CTLD radio menu at all. Nothing in
> your configuration is at fault and nothing needs changing — re-installing is the whole fix.

## Installation

1. Download **`ctld-tools.exe`** below — it is the only file you need.
2. Run it: the tool opens in your browser, locally, with nothing to install.
3. Open your `.miz`, adjust what you want, then **Install into mission**: the tool writes CTLD, the
   beacon sounds and your configuration into it.

**Windows blocks it on the first run?** The tool is not code-signed, so SmartScreen stops it: click
**More info** → **Run anyway**. If the file came through a browser you may also need right-click →
**Properties** → tick **Unblock** → **OK**.

Prefer doing it by hand? The files are attached to this release too — see the
[documentation](https://veaf.github.io/CTLD/2.0.0-rc9/mission-maker/).

---

This release candidate exists for one reason: **rc8 does not load**. Everything rc8 brought is still
here — it simply never got the chance to run.

## What was broken in rc8

The engine failed while loading, before it ever started. In game that looks like:

- **no CTLD radio menu** under F10, at all;
- everything else in the mission working normally, so nothing obviously points at CTLD;
- a single line in `dcs.log` mentioning *"CTLD configuration is not loaded"*.

It affected **every** mission installed with rc8 — it had nothing to do with your settings, your
theatre, or how the mission was built.

**If you use VEAF Mission Creation Tools**, the damage went further: VEAF loads its own scripts in the
same block, right after CTLD, so the failure took the whole VEAF framework down with it. Those
missions had **no radio menu whatsoever** — not CTLD's, not VEAF's. VEAF Tools 6.22.1 ships this fix;
until you update it, re-installing with `ctld-tools.exe` from this release works too.

Reported by **Tripack** (VEAF) within hours of the release — thank you.

## What caused it, briefly

rc8 added a deliberate safety check: asking CTLD for a setting before the engine has started is now
refused outright, with a message saying so, instead of failing later on something unrelated. That
check was right, and it is unchanged here.

What it caught was CTLD's own logging: the engine writes a log line while registering its built-in
FARP and FOB scenes, which happens *before* the engine starts — and writing that line asked for a
setting. Logging now tolerates being called that early, which is what it always should have done.

## And so that this cannot happen again

CTLD's continuous integration checked that the engine file *existed*, that it *parsed*, and that the
individual source modules behaved. Nothing ever **ran** the assembled engine — which is exactly where
the failure was. Every build now loads it end to end and refuses to publish if it does not come up.

## Nothing to change in your configuration

No setting was renamed, removed or given a new default since rc8. Re-install your mission and you are
done.
