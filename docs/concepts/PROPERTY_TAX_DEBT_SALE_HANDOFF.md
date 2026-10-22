# Property sale tax-debt gate — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: prevent selling an owned lot while it has unpaid land tax.

## Change

`RAProperty.sell(lot_id)` now checks the lot's `tax_debt` immediately after retrieving its state. If positive, the sale returns “Pay your land dues first.” before the storage check, refund or deletion. Debt-free lots retain the existing storage restriction, sale refund, and state removal behavior. The guard is specific to land tax debt; it does not change rent-debt rules.

## Verification and limits

This is a narrow sale-path guard only; it does not change how dues accrue or are paid, or add a UI step. Static source review and `git diff --check` only. No parser, runtime sale, save/load or gameplay behavior check was run.
