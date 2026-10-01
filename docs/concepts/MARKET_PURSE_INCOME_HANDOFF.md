# Market hourly purse income handoff

`RAMarket.tick_hours()` previously rounded `15 * hours / 24` on every call. With hourly calls that produced 24 gold per day, while `tick_day()` produced 15. It now stores the fractional purse-income remainder in `_purse_carry`: twenty-four 1-hour ticks accrue 15 gold, matching one 24-hour tick. When purse income reaches the 600-gold cap, the remainder is cleared so it cannot accumulate invisibly at the cap.

The carry is serialized as `purse_carry`. Deserialization defaults legacy saves to zero and accepts only numeric finite values in `[0, 1)`. This is separate from the per-good stock carry dictionary. Existing buying, selling, stock updates, and callers are unchanged.

Only static source review and `git diff --check` were performed. No parser, runtime, economy cadence, save/load, or gameplay validation was run.
