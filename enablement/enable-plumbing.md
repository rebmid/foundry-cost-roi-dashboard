# Enablement: turn on the plumbing

Four sources feed the workbook. Do 1 and 2 for token counts and per-team attribution;
add 3 when you want billed dollars instead of an estimate.

## 1. Diagnostic settings on each Foundry / Azure OpenAI resource

Send **AllMetrics** and logs to one Log Analytics workspace. This gives the native
metrics (Processed Prompt Tokens, Generated Completion Tokens, Processed Inference
Tokens, Prompt Token Cache Match Rate).

```bash
# Variables
AOAI_ID=$(az cognitiveservices account show -g <rg> -n <aoai-name> --query id -o tsv)
LAW_ID=$(az monitor log-analytics workspace show -g <rg> -n <workspace> --query id -o tsv)

az monitor diagnostic-settings create \
  --name foundry-to-law \
  --resource "$AOAI_ID" \
  --workspace "$LAW_ID" \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]'
```

Repeat for every AOAI / Foundry resource (or apply at scale with Azure Policy
`DeployIfNotExists`).

## 2. APIM AI gateway: emit token metrics with a Team dimension

Front your models with Azure API Management and apply
[`apim-llm-emit-token-metric.xml`](apim-llm-emit-token-metric.xml). It writes token
counts to Application Insights as `customMetrics`, with `ModelDeploymentName` and
`Team` dimensions the workbook groups by.

- Prereq: an **Application Insights logger** attached to the APIM instance.
- The workbook's **AppInsights** parameter must point at this component.
- Fastest path: deploy the official
  [Azure-Samples/AI-Gateway `labs/finops-framework`](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/finops-framework),
  which wires the policy, KQL, budgets, and a cost workbook end to end.

## 3. (Optional) FOCUS cost export for billed dollars

Cost Management -> **Exports** -> new export, dataset **FOCUS**, to a storage account.
Use it as the source for the daily-spend and by-model panels when you want
invoice-accurate cost instead of the rate-card estimate.

```bash
# List existing exports (portal is easier for creating a FOCUS export)
az costmanagement export list --scope "/subscriptions/<sub-id>" -o table
```

## 4. Rate card

Edit [`../rate-card/rates.csv`](../rate-card/rates.csv) with your negotiated prices,
then mirror the same numbers in the `rates` datatable at the top of each query
(the queries are self-contained so each tile can run on its own).

## Governance (alongside the dashboard)

- **Microsoft Purview** for DLP at the AI gateway.
- **Foundry evaluations + observability** for accuracy, escalation, and responsible-AI
  metrics next to cost.
