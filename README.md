# Foundry Cost & ROI Dashboard

One **Azure Monitor Workbook** that turns Azure AI Foundry / Azure OpenAI token
telemetry into **dollars and ROI**. Azure Monitor gives you token *counts*; this
adds a **rate card** to get the *dollars*, plus a chargeback dimension and an ROI
panel. It fills the Foundry gap that Copilot-focused tools (Consumption Central,
ValueLens) do not cover.

**Standalone:** the [`infra/`](infra/) folder deploys the entire platform end to end (an
APIM AI gateway, per-team token throttling, budget auto-disable, Foundry model deployments,
sample teams, and both workbooks). No external accelerator required. Or drop a single
workbook into an existing Azure Monitor setup (see the workbook import steps below).

> The key idea: **Azure Monitor gives token counts; you add a rate card to get the
> dollars.** It is one workbook assembled from four data sources, panel by panel.

## What it looks like

![Foundry cost and chargeback workbook](docs/dashboard.png)

*The Log Analytics cost and chargeback workbook ([`workbook/FoundryCostAnalysis-LogAnalytics.workbook`](workbook/FoundryCostAnalysis-LogAnalytics.workbook)), a drop-in upgrade for the finops-framework lab.*

Two pickers scope everything: **Time range** and **Subscription** (the APIM subscription =
team). The KPI strip shows **total cost, total tokens, calls, and cost per 1K tokens** for the
selected scope. The **Live token volume** tile reads platform metrics (about 1 minute) for
near-real-time input / output / total tokens, faster than the log-based tiles. Below (not in
this view) are spend by model, spend by subscription, spend over time, anomaly detection,
budget vs actual, a PRICE MISSING data-quality tile, token split, and a top-consumers table.

![Spend by model, by subscription, and over time](docs/dashboard-breakdown.png)

*Breakdown tiles: spend by model, spend by subscription (chargeback), and spend over time.*

![Spend anomaly detection and budget vs actual](docs/dashboard-anomaly-budget.png)

*Spend anomaly detection (actual vs expected) and budget vs actual per subscription, with an OVER BUDGET / Warning / OK status.*

## What you get

| Panel | Source | Visual |
|---|---|---|
| Daily AI spend + anomaly | rate-card estimate (or FOCUS export for billed $) | line chart, anomaly via `series_decompose_anomalies()` |
| Spend by model | Processed/emitted tokens split by `ModelDeploymentName` x rate card | bar chart |
| Cost per 1K tokens | total $ / total tokens | KPI tile |
| Prompt cache hit rate | native metric *Prompt Token Cache Match Rate* (or emitted Cached Tokens) | KPI tile |
| Token volume by type | Prompt / Completion / Cached tokens | stacked column |
| Business value / ROI | tokens -> cost vs. business inputs (hours saved x loaded rate) | KPI + table |

## Deploy: two options

Everything is in [`infra/`](infra/). Pick based on whether you already run an APIM gateway.

### Option A: greenfield (creates a new APIM + Foundry)

Use this on a clean subscription with no gateway yet. It deploys **everything**: an APIM AI
gateway in front of Azure AI Foundry, per-product (per-team) `llm-token-limit` throttling, the
`azure-openai-emit-token-metric` policy, Foundry model deployments, the `PRICING_CL` +
`SUBSCRIPTION_QUOTA_CL` tables, all four workbooks + a portal dashboard, three sample products
(platinum/gold/silver) with four sample team subscriptions, and a **Logic App + scheduled-query
rules that auto-disable any team that exceeds its cost quota**.

```powershell
# 1. Deploy the platform (creates one APIM in a new resource group)
./infra/deploy.ps1 -Subscription <your-sub-id>

# 2. Populate prices/quotas and generate sample traffic
#    (pip install azure-identity azure-monitor-ingestion requests openai)
python infra/postdeploy.py --subscription <your-sub-id> --resource-group finops-standalone --deployment finops-standalone
```

Edit [`infra/params.json`](infra/params.json) for models, APIM SKU, products, and quotas. Tear
down with `az group delete -n finops-standalone -y`. Resource names come from
`uniqueString(subscription, resourceGroup)`, so deploying into an **existing** finops-framework
resource group reuses that APIM instead of creating a new one.

### Option B: bring your own APIM + workspace (no new APIM)

Use this if you already run an APIM AI gateway and a Log Analytics workspace. It creates only the
workspace-side pieces: the `PRICING_CL` + `SUBSCRIPTION_QUOTA_CL` tables (with data collection
rules) and the **Cost Analysis** + **Foundry Cost & ROI** workbooks. It does **not** create an
APIM. Run it in the resource group that holds your workspace.

```powershell
./infra/deploy-existing.ps1 -Subscription <your-sub-id> -ResourceGroup <workspace-rg> -WorkspaceName <workspace-name>
```

Then populate the two tables and confirm your gateway is logging (next section):
- **Rate card:** deploy [`pricing-refresh/`](pricing-refresh/) against the new `dcr-pricing-*` DCR
  (weekly auto-refresh from the Azure Retail Prices API), or seed `PRICING_CL` once.
- **Budgets:** write one `SUBSCRIPTION_QUOTA_CL` row per team (APIM subscription) with its `CostQuota`.

## Requirements: what must exist and be turned on

For the dashboards to show data, this chain has to be in place. **Option A sets all of it up for
you.** For **Option B** you point at what you already have and turn on the gateway logging
(requirements 2 and 3 are the ones people forget).

| # | Requirement | Feeds | How |
|---|---|---|---|
| 1 | An **APIM AI gateway** in front of Azure OpenAI / Foundry, with per-team **subscriptions** | team attribution | your gateway (Option A creates one) |
| 2 | APIM **resource diagnostic** to Log Analytics: `AllLogs` + resource-specific (Dedicated) tables | `ApiManagementGatewayLogs` | APIM > Diagnostic settings; or CLI below |
| 3 | An **`azureMonitor` logger** on APIM + the LLM API's **per-API diagnostic** with `largeLanguageModel.logs = enabled` | `ApiManagementGatewayLlmLog` (token counts) | API > Settings > Diagnostics logs (Azure Monitor), turn on **LLM logs** |
| 4 | **`PRICING_CL`** table populated (rate card) | dollars | Option A postdeploy, or [`pricing-refresh/`](pricing-refresh/) auto-refresh |
| 5 | **`SUBSCRIPTION_QUOTA_CL`** table populated | budget vs actual tile | one row per team with `CostQuota` |
| 6 | *(optional)* Foundry/AOAI **resource diagnostic** to the workspace (`AllMetrics`) | the **Live token volume** tile (`AzureMetrics`) | Foundry resource > Diagnostic settings |
| 7 | *(optional)* APIM **`azure-openai-emit-token-metric`** policy + an App Insights diagnostic | the App-Insights ROI variant (`customMetrics` / `AppMetrics`) | see [`enablement/`](enablement/) |
| 8 | **Reader** on the workspace to view; **Monitoring Metrics Publisher** on the DCRs to ingest prices/quotas | - | RBAC |

Turn on gateway logging for an existing APIM (requirements 2 and 3):

```powershell
# 2. Route APIM logs to your workspace as resource-specific (dedicated) tables
az monitor diagnostic-settings create --name finops-dashboards `
  --resource <apim-resource-id> `
  --workspace <workspace-resource-id> `
  --logs '[{"categoryGroup":"allLogs","enabled":true}]' `
  --metrics '[{"category":"AllMetrics","enabled":true}]' `
  --export-to-resource-specific true

# 3. Turn on LLM logging (portal is easiest):
#    APIM > APIs > <your Azure OpenAI API> > Settings > Diagnostics logs > Azure Monitor >
#    enable, select an azureMonitor logger, and turn ON the Large language model (LLM) logs.
```

Without requirements 2 and 3, `ApiManagementGatewayLlmLog` is empty and every cost tile reads zero.

## Architecture (four sources into one workbook)

```
Azure AI Foundry / Azure OpenAI ──(diagnostic settings: AllMetrics + logs)──► Log Analytics
        │                                                                         ▲
        └──(fronted by)──► APIM AI gateway ──(llm-emit-token-metric: +Team dim)──► Application Insights
                                                                                  │
Cost Management ──(FOCUS export)──► Storage (real billed $, optional)             │
                                                                                  ▼
                                          Azure Monitor Workbook (this repo) ◄─────
                                          + rate card (token -> $) + ROI inputs
```

- **Token counts (free, native):** enable diagnostic settings on each Foundry/AOAI
  resource. Native metrics include Processed Prompt Tokens, Generated Completion
  Tokens, Processed Inference Tokens, and Prompt Token Cache Match Rate.
- **Per-team attribution:** put an **APIM AI gateway** in front and emit token
  metrics with a `Team` (or app) dimension to Application Insights. See
  [`enablement/apim-llm-emit-token-metric.xml`](enablement/apim-llm-emit-token-metric.xml).
- **Real billed dollars (optional):** a **FOCUS cost export** gives amortized,
  invoice-accurate cost. Point the daily-spend panel at it instead of the rate card
  when you want billed truth rather than an estimate.
- **The dollars:** a small **rate card** ([`rate-card/rates.csv`](rate-card/rates.csv))
  converts token counts to cost. Replace the illustrative rates with your negotiated
  prices.

## Quick start

1. **Turn on the plumbing:** see [`enablement/enable-plumbing.md`](enablement/enable-plumbing.md)
   (diagnostic settings, APIM token metrics, optional FOCUS export).
2. **Set your prices:** this workbook holds the rate card as an inline `rates` datatable at
   the top of each query (that is what actually runs). [`rate-card/rates.csv`](rate-card/rates.csv)
   is only a human-readable copy, so edit the datatable values. If you would rather not edit
   queries, use the Log Analytics workbook below, which exposes the rate card as an **editable
   parameter** you change in the portal.
3. **Import the workbook**:
   - Azure portal -> **Monitor -> Workbooks -> New**.
   - Click **</> Advanced Editor**, choose **Gallery Template**, paste the contents of
     [`workbook/FoundryCostRoi.workbook`](workbook/FoundryCostRoi.workbook), click **Apply**.
   - **Save**, scope it to your AI subscriptions, and pin it to a shared dashboard.
   - Set the **Application Insights** parameter to the component your APIM gateway logs to.
4. **Set your ROI inputs:** open the ROI tile and edit `hoursSaved` and `loadedRate`
   at the top of the query (or wire them to workbook parameters).

## Two workbook variants (pick by telemetry source)

| File | Reads from | Best for |
|---|---|---|
| [`workbook/FoundryCostAnalysis-LogAnalytics.workbook`](workbook/FoundryCostAnalysis-LogAnalytics.workbook) | Log Analytics `ApiManagementGatewayLlmLog` priced from `PRICING_CL` | Chargeback + budget vs actual (deployed by `infra/`) |
| [`workbook/FoundryCostRoi-LogAnalytics.workbook`](workbook/FoundryCostRoi-LogAnalytics.workbook) | Log Analytics `ApiManagementGatewayLlmLog` priced from `PRICING_CL` | ROI + unit economics with no extra plumbing (deployed by `infra/`) |
| [`workbook/FoundryCostRoi.workbook`](workbook/FoundryCostRoi.workbook) | App Insights `customMetrics` (APIM `llm-emit-token-metric`) | ROI when you already emit token metrics to App Insights |

The Log Analytics cost workbook is what `infra/` deploys as **Cost Analysis** (it also drops
into any finops-framework-style setup): it prices from the
**`PRICING_CL` rates table** (refresh it from the Azure Retail Prices API instead of
hand-editing), a KPI strip (cost, tokens, calls, cost per 1K), spend by model, spend by
team, spend over time, **spend anomaly detection** (actual vs expected), a **live token tile
from platform metrics**, budget vs actual with an OVER BUDGET / Warning / OK status, a
**PRICE MISSING data-quality tile**, token split, and a top-consumers table. Costs are Azure
list price. Deploy it straight into the resource group:

```powershell
az deployment group create -g lab-finops-framework --template-file workbook/deploy-cost-analysis-workbook.bicep --parameters workspaceResourceId=<your Log Analytics workspace resource id>
```

Or import it via **Monitor > Workbooks > New > Advanced Editor** (replace the
`{workspace-id}` placeholder with your workspace resource id first).

## Keep the rate card current (auto-refresh)

`PRICING_CL` holds Azure list prices. To keep it current with **zero editing**, deploy the
included Automation runbook that re-pulls the **Azure Retail Prices API** on a weekly schedule
and writes to the same data collection rule the lab created:

- [`pricing-refresh/Refresh-PricingCL.ps1`](pricing-refresh/Refresh-PricingCL.ps1): the runbook (managed-identity auth, no keys).
- [`pricing-refresh/deploy-pricing-refresh.bicep`](pricing-refresh/deploy-pricing-refresh.bicep): Automation account + system-assigned identity + weekly schedule + the `Monitoring Metrics Publisher` grant on the DCR.

```powershell
az deployment group create -g <rg> --template-file pricing-refresh/deploy-pricing-refresh.bicep --parameters runbookRawUrl=<raw-url> dcrName=<dcr-name> dcrEndpoint=<dcr-endpoint> dcrImmutableId=<dcr-immutable-id> meterMapJson=<model-to-meter-json>
```

The only thing to maintain is the **model-to-meter map** (the Retail Prices API meter names do
not equal deployment names); the workbook's PRICE MISSING tile flags anything unmapped.

## Customize

- **Rates:** the `rates` datatable maps a model *family* to input/output USD per 1K
  tokens. Deployment names are mapped to a family with a `case()` expression; extend it
  for your deployments. (This is the `FoundryCostRoi.workbook` mechanism; the Log Analytics
  workbook reads the `PRICING_CL` rates table instead.)
- **Billed vs. estimate:** to show invoice-accurate cost, replace the rate-card math in
  the daily-spend and by-model queries with a query over your FOCUS export (cost is
  already in dollars there).
- **Cache hit rate:** if your APIM policy does not emit Cached Tokens, use the native
  Azure OpenAI metric *Prompt Token Cache Match Rate* instead (see
  [`queries/04-cache-hit-rate.kql`](queries/04-cache-hit-rate.kql)).

## Grafana (alternative, more polished surface)

Same panels and the same KQL, on a Grafana surface (closest match to a designed
dashboard: stat cards with colored deltas, value-labeled bars, stacked bars).

- File: [`grafana/foundry-cost-roi.json`](grafana/foundry-cost-roi.json).
- Import: Grafana -> **Dashboards -> New -> Import** -> upload the JSON.
- Prereqs: the **Azure Monitor** data source plugin (built in to Azure Managed Grafana).
- On import, set the two dashboard variables:
  - **Azure Monitor data source** -> your Azure Monitor data source.
  - **App Insights resource ID** -> the full resource ID of the Application Insights
    component your APIM gateway emits to.
- Panels query Application Insights `customMetrics` via the Azure Monitor **Logs**
  query type, so the rate-card / token math is identical to the workbook.

Rule of thumb: **Workbook** for the free in-portal ops view, **Grafana** for a polished
real-time / exec view, **Power BI** (FinOps toolkit) for billed-dollar finance reporting.
Power BI shows AI *dollars* (filter Service = Azure OpenAI / ServiceCategory =
"AI and Machine Learning") but not tokens or unit economics - that is what this
workbook/Grafana layer adds.

## Governance and quality: how to pair them with the cost view

The reason everything routes through **one APIM AI gateway into one Application Insights /
Log Analytics** is that cost, data-governance, and quality telemetry then share the **same
store and the same dimensions** (`ModelDeploymentName`, `Team`, `ApiId`, operation id).
That shared backbone is what lets you put cost next to governance and quality in one place
instead of three disconnected tools. A cost number on its own can mislead; pairing it with
**Purview** (is the spend *safe*?) and **Foundry evals** (is the spend *good*?) is what makes
this a governance dashboard rather than a billing chart.

| Layer | Produces | Lands in | Joins to cost on |
|---|---|---|---|
| Cost (this repo) | token counts x rate card = $ | App Insights `customMetrics` | `ModelDeploymentName`, `Team` |
| Purview DLP | sensitive-data hits, blocked / flagged requests | App Insights / APIM gateway logs | `ModelDeploymentName`, `Team`, `ApiId` |
| Foundry evals + tracing | groundedness / relevance / safety scores, agent traces, escalations | App Insights `traces` / `customEvents` | operation id, deployment |

### Microsoft Purview: DLP at the AI gateway
- **What:** enforce data-loss-prevention on prompts and responses at the *same* APIM
  gateway that emits your token metrics, so one control plane gives you cost **and** data
  protection.
- **Deploy:** the AI-Gateway lab "Microsoft Purview DLP at the AI Gateway"
  ([Azure-Samples/AI-Gateway](https://github.com/Azure-Samples/AI-Gateway)).
- **Pair it (add a tile):** DLP events carry the same `Team` / `ModelDeploymentName`
  dimensions, so rank the teams and models that are **both high-cost and high-DLP-hit**.
  Point the DLP part at wherever your DLP decisions log:

```kusto
// cost driver vs DLP risk per team  (adjust the DLP event name/source to your logging)
let cost = customMetrics
  | where name in ("Prompt Tokens","Completion Tokens")
  | extend team = tostring(customDimensions.Team)
  | summarize Tokens = sum(valueSum) by team;
let dlp = customEvents
  | where name == "PurviewDlpBlocked"          // <-- your Purview / APIM DLP event name
  | extend team = tostring(customDimensions.Team)
  | summarize DlpHits = count() by team;
cost | join kind=leftouter dlp on team
| project team, Tokens, DlpHits = coalesce(DlpHits, 0)
| order by DlpHits desc, Tokens desc
```

### Foundry evaluations + observability
- **What:** Foundry **evaluations** score quality (groundedness, relevance, safety);
  Foundry **tracing / observability** (OpenTelemetry to Application Insights) captures agent
  traces, tool calls, and escalations.
- **Deploy:** turn on Foundry tracing to your Application Insights, and use the AI-Gateway
  lab "Foundry Models Evals" (pulls LLM logs from APIM and runs evals in Foundry)
  ([Azure-Samples/AI-Gateway](https://github.com/Azure-Samples/AI-Gateway)).
- **Pair it (turn ROI into unit economics):** because eval results and traces land in the
  *same* App Insights as the token cost, compute **cost per good outcome** (per passing
  eval, per resolved or escalated conversation) instead of just hours saved:

```kusto
// cost per passing eval by deployment  (adjust the eval event name to your Foundry export)
let rates = datatable(family:string, inK:real, outK:real)["gpt-4o",0.0025,0.010,"gpt-4o-mini",0.00015,0.0006];
let cost = customMetrics
  | where name in ("Prompt Tokens","Completion Tokens")
  | extend dep = tostring(customDimensions.ModelDeploymentName)
  | extend family = iff(dep has "mini","gpt-4o-mini","gpt-4o")
  | summarize inTok=sumif(valueSum,name=="Prompt Tokens"), outTok=sumif(valueSum,name=="Completion Tokens") by dep, family
  | lookup rates on family
  | extend CostUsd = (inTok/1000.0*inK)+(outTok/1000.0*outK);
let evals = customEvents
  | where name == "gen_ai.evaluation"          // <-- your Foundry eval event name
  | extend dep = tostring(customDimensions.ModelDeploymentName), passed = tobool(customDimensions.passed)
  | summarize Passing = countif(passed == true), Total = count() by dep;
cost | join kind=leftouter evals on dep
| extend CostPerPassingEval = round(CostUsd / max_of(toreal(Passing), 1.0), 4)
| project dep, CostUsd = round(CostUsd,2), Passing, Total, CostPerPassingEval
| order by CostUsd desc
```

Add either query as a new tile (Workbook) or panel (Grafana) next to the cost tiles - same
data source, same time range. That is the whole pairing: one gateway, one telemetry store,
three questions (what does it cost, is it safe, is it good) answered off the same rows.

## What gets deployed (infra/)

Everything in this repo deploys from [`infra/`](infra/); nothing external is required.

| Component | What it does |
|---|---|
| APIM AI gateway + `inference-api` | Fronts Azure AI Foundry; one endpoint, per-team keys |
| `llm-token-limit` per product | Throttles platinum/gold/silver at different tokens-per-minute and token quotas |
| `azure-openai-emit-token-metric` | Emits token metrics with a team/product dimension |
| Foundry + model deployments | gpt-4.1, gpt-4.1-mini, DeepSeek-V3.2 (edit in `params.json`) |
| `PRICING_CL` + `SUBSCRIPTION_QUOTA_CL` (+ DCRs) | Rate card and per-team budgets |
| Cost Analysis + Foundry Cost & ROI workbooks | This repo's cost/chargeback and ROI views |
| Azure OpenAI Insights + Alerts workbooks + dashboard | Operational monitoring |
| Logic App + scheduled-query rules | **Auto-disables** any team subscription that exceeds its cost quota, and re-enables it when spend drops back under |

The infra is adapted from the MIT-licensed Azure-Samples/AI-Gateway project; see
[`NOTICE`](NOTICE) for attribution. On top of it, this repo adds the improved cost workbook,
the ROI workbook, weekly rate-card auto-refresh, and the Grafana surface.

## Notes

- Rates in this repo are **illustrative**; replace them with your contract prices.
- The workbook queries assume APIM `llm-emit-token-metric` writes to Application Insights
  (`customMetrics` table). For workspace-based App Insights, the table is `AppMetrics`.
- No customer-specific data is included; this is a reusable template.

## License

MIT. See [LICENSE](LICENSE).
