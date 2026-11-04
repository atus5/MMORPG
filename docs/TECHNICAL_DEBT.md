# M1 review technical debt

## F-002 — tick-sampled movement intent (deferred to M2)

Owner decision: do not fix this finding during M1 R1. Evaluate it when designing the M2 movement tick/shared-world simulation system.

R0 review: LOW. Between two 20Hz publish ticks, a newer direction replaces the previous intent. A short press/release within one tick may produce no displacement, or the last direction may apply over the sampled elapsed interval. This does not grant client authority or increase the configured server speed.

Preserve Session.advance(), the current direction/input_at assignment and tick timing in this fix round. Do not add sub-tick integration or select new gameplay values. M2 should compare tick sampling with timestamped/sub-tick integration and define regression cases with Owner approval before choosing a design.
