<p align="center">
  <img src="assets/banner.svg" width="830" alt="cr-cron banner">
</p>
<p align="center">
  <a href="https://github.com/Celine1337/cr-cron/releases"><img src="assets/nav-releases.svg" alt="Releases"></a>
  <a href="https://en.wikipedia.org/wiki/Cron"><img src="assets/nav-spec.svg" alt="cron syntax"></a>
  <a href="LICENSE"><img src="assets/nav-mit.svg" alt="MIT"></a>
</p>

<img src="assets/section-about.svg" width="830" alt="About">

**cr-cron** answers the question every scheduler script eventually asks: *when does this cron expression actually run next?* Give it a standard 5-field cron expression and it prints the next `count` matching times as ISO8601 UTC lines, strictly after a base time. It implements real cron semantics — `*`, single values, ranges, lists, `*/n` and `a-b/n` steps, and the classic day-of-month/day-of-week **OR** rule when both are restricted — so the answers match what a crontab would do, not a naive approximation.

Why Crystal? Because it compiles to a single fast native binary with a genuinely good `Time` library, and the whole tool is one dependency-free source file. Pass an explicit base time and the output is fully deterministic — perfect for tests, docs and reproducible shell pipelines; omit it and it uses the current UTC time.

<img src="assets/section-features.svg" width="830" alt="Features">

- **Full 5-field syntax** — minute, hour, day-of-month, month, day-of-week with `*`, `a`, `a-b`, `a,b,c`, `*/n`, `a-b/n` and `a/n`.
- **Real cron day rule** — when both day-of-month and day-of-week are restricted, a day matches if *either* matches; otherwise fields are ANDed.
- **Sunday done right** — dow accepts `0-7`, with both `0` and `7` meaning Sunday.
- **Deterministic mode** — pass a base time like `2026-11-12T10:00:00` to get reproducible output; defaults to now (UTC) in real use.
- **Strictly-after semantics** — results always follow the base time; a run time equal to the base rolls to the next match.
- **Fast sparse search** — month/day/hour skipping means even `0 0 29 2 *` (leap days) resolves instantly, with a 4-year horizon and a clear error if nothing matches.
- **Scriptable exit codes** — `0` success, `1` invalid expression or no match, `2` bad usage; errors go to stderr.
- **Tested** — 35 self-contained shell assertions on exact outputs and exit codes.

<img src="assets/section-stack.svg" width="830" alt="Tech stack">

<img src="assets/section-install.svg" width="830" alt="Install">

Requires [Crystal](https://crystal-lang.org/) 1.22+ to build; the resulting binary has no runtime dependencies.

```bash
git clone https://github.com/Celine1337/cr-cron.git
cd cr-cron
./build.sh          # crystal build --release -> bin/cr-cron
./bin/cr-cron "*/15 * * * *" 5
```

<img src="assets/section-usage.svg" width="830" alt="Usage">

```bash
cr-cron "<cron expr>" [count] [base-time]

cr-cron "*/15 * * * *"                          # next 5 quarter-hours from now
cr-cron "0 9-17/2 * * 1-5" 4                    # business-hours slots
cr-cron "0 0 13 * 5" 5 2026-11-12T10:00:00      # Fridays OR the 13th (cron OR rule)
cr-cron "0 0 29 2 *" 1 2026-11-12T10:00:00      # next leap day
```

```text
$ cr-cron "*/15 * * * *" 5 2026-11-12T10:00:00
2026-11-12T10:15:00Z
2026-11-12T10:30:00Z
2026-11-12T10:45:00Z
2026-11-12T11:00:00Z
2026-11-12T11:15:00Z
```

Exit codes: `0` success, `1` invalid cron expression / fewer matches than requested within 4 years, `2` bad usage (argument count, count or base-time malformed).

<img src="assets/section-license.svg" width="830" alt="License">

MIT — see [LICENSE](LICENSE).