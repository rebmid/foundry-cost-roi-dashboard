# ROI model (Foundry Cost & ROI workbook)

The **Foundry Cost & ROI** workbook turns AI token spend into a business ROI by comparing the
**cost of the AI** against the **value of the human time it saves**. Two inputs drive it, and both
are about the humans, not the model:

- **Hours saved / month** — the number of *human* work hours the AI/agent avoids each month (staff
  time no longer spent because the model does the work). Estimate it from the workflow: tasks or
  calls handled x minutes saved each, or a simple before/after time study.
- **Loaded rate ($/hr)** — the *fully loaded* hourly cost of that human labor: base pay **plus**
  benefits, taxes, and overhead. Finance usually publishes a standard loaded-cost figure per role.

The AI-side number is the **token cost**, pulled automatically from the `PRICING_CL` rate card
(Azure list price) for the current month. You never edit that. An optional **Platform cost / month**
input lets you add the always-on services around the tokens (APIM, Log Analytics, Application
Insights, Foundry hosting) so the run cost reflects the full platform, not just marginal tokens.

## The math

```
Value of time saved      = Hours saved / month  x  Loaded rate ($/hr)
Agent run cost (MTD)      = model token cost for the current month (from PRICING_CL)  +  Platform cost / month
Net ROI (%)              = (Value of time saved - Agent run cost) / Agent run cost  x 100
Payback (share of value) = Agent run cost / Value of time saved
```

- **Net ROI** - for every $1 of AI run cost, how many extra dollars of human time you got back. When
  monthly spend is under $1 it shows **n/a (spend < $1, illustrative)** instead of a meaningless
  multi-million-percent figure.
- **Payback (share of value)** — the fraction of the value the AI cost consumed. Small is good.

## Worked example (the values in the screenshot)

| Input / output | Value |
|---|---|
| Hours saved / month | 1,240 |
| Loaded rate ($/hr) | $64 |
| **Value of time saved** | 1,240 x $64 = **$79,360** |
| Agent run cost (MTD) | $0.04 (tokens) + $0 (platform) |
| **Net ROI** | n/a (spend < $1, illustrative) |
| Payback (share of value) | n/a |

Because monthly spend here is only a few cents (well under $1), Net ROI shows **n/a (spend < $1,
illustrative)** rather than a multi-million-percent number: a near-zero denominator makes the
percentage meaningless in a low-volume lab. Once real monthly spend is above $1 it becomes simply
(value - cost) / cost and the figure is meaningful. Add the always-on **Platform cost / month** to
put the token cost in context of the full platform. The workbook does the comparison automatically
off live token cost, so the estimate stays current on its own.

## Setting the inputs

They are workbook **parameters** (the pills labeled *Hours saved / month*, *Loaded rate ($/hr)*, and
*Platform cost ($/month)*), so you change them in the portal without touching any query. Defaults are
**1,240 hours**, **$74/hr**, and **$0** platform cost; set them to your own numbers.

> The App Insights variant, [`workbook/FoundryCostRoi.workbook`](../workbook/FoundryCostRoi.workbook),
> keeps the same two inputs as `hoursSaved` and `loadedRate` `let` values at the top of the ROI query
> instead of as pills.

## Making it more precise

- Split **Hours saved** by team or workflow and weight by each one's actual volume rather than one
  global number.
- Use a **role-specific loaded rate** (a senior engineer hour is not a support-agent hour).
- For a stricter unit-economics view, replace "hours saved" with **cost per good outcome** (per
  resolved conversation, per passing eval); see the Governance section of the main
  [README](../README.md).
