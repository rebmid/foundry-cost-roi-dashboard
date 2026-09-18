"""Post-deploy for the standalone FinOps-for-AI platform.

Reads model/product/subscription config from params.json, pulls Azure Retail Prices into
PRICING_CL, uploads per-subscription cost quotas into SUBSCRIPTION_QUOTA_CL, and generates
sample traffic through the APIM gateway so the workbooks have data.

    python postdeploy.py --subscription <sub-id> [--resource-group finops-standalone] [--deployment finops-standalone]

Requires: azure-identity, azure-monitor-ingestion, requests, openai (pip install).
"""
import argparse, json, os, random, subprocess, time
from datetime import datetime, timezone

import requests
from azure.identity import AzureCliCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError
from openai import AzureOpenAI

HERE = os.path.dirname(os.path.abspath(__file__))

ap = argparse.ArgumentParser()
ap.add_argument("--subscription", required=True)
ap.add_argument("--resource-group", default="finops-standalone")
ap.add_argument("--deployment", default="finops-standalone")
ap.add_argument("--currency", default="USD")
ap.add_argument("--runs", type=int, default=24)
args = ap.parse_args()

params = json.load(open(os.path.join(HERE, "params.json")))["parameters"]
models_config = params["modelsConfig"]["value"]
products_config = params["apimProductsConfig"]["value"]
subs_config = params["apimSubscriptionsConfig"]["value"]
region = params["aiServicesConfig"]["value"][0]["location"]
inference_path = params.get("inferenceAPIPath", {}).get("value", "inference")


def az(a):
    r = subprocess.run(["az"] + a + ["--subscription", args.subscription],
                       capture_output=True, text=True, shell=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout


print("Fetching deployment outputs ...")
outs = json.loads(az(["deployment", "group", "show", "-g", args.resource_group,
                      "-n", args.deployment, "--query", "properties.outputs", "-o", "json"]))
gw = outs["apimResourceGatewayURL"]["value"]
subs = outs["apimSubscriptions"]["value"]
pricing_ep = outs["pricingDCREndpoint"]["value"]
pricing_id = outs["pricingDCRImmutableId"]["value"]
pricing_strm = outs["pricingDCRStream"]["value"]
quota_ep = outs["subscriptionQuotaDCREndpoint"]["value"]
quota_id = outs["subscriptionQuotaDCRImmutableId"]["value"]
quota_strm = outs["subscriptionQuotaDCRStream"]["value"]
print("Gateway:", gw)

cred = AzureCliCredential()


def upload_retry(client, rule_id, stream, body, attempts=6):
    for a in range(attempts):
        try:
            client.upload(rule_id=rule_id, stream_name=stream, logs=body)
            return True
        except HttpResponseError as e:
            msg = str(e)
            if a < attempts - 1 and any(t in msg for t in ("Forbidden", "403", "Authorization")):
                print(f"   (RBAC not ready, retry {a + 1} in 20s)")
                time.sleep(20)
                continue
            print("   upload error:", msg[:200])
            return False


print("\n== Pull retail prices (Foundry Models, %s) ==" % region)
url = ("https://prices.azure.com/api/retail/prices?currencyCode='%s'"
       "&$filter=serviceName eq 'Foundry Models' and unitOfMeasure eq '1K' and armRegionName eq '%s'"
       % (args.currency, region))
items, u, pages = [], url, 0
while u and pages < 20:
    j = requests.get(u).json()
    items += j.get("Items", [])
    u = j.get("NextPageLink")
    pages += 1
print(f"retail items pulled: {len(items)}")

print("\n== Upload model pricing -> PRICING_CL ==")
pc = LogsIngestionClient(endpoint=pricing_ep, credential=cred, logging_enable=False)
for m in models_config:
    inp = next((it["retailPrice"] for it in items if it.get("skuName") == m.get("inputTokensMeterSku")), None)
    outp = next((it["retailPrice"] for it in items if it.get("skuName") == m.get("outputTokensMeterSku")), None)
    print(f"  {m['name']:16s} in/out per 1K = {inp} / {outp}")
    body = [{"TimeGenerated": str(datetime.now(timezone.utc)), "Model": m["name"],
             "InputTokensPrice": inp, "OutputTokensPrice": outp}]
    upload_retry(pc, pricing_id, pricing_strm, body)

print("\n== Upload cost quotas -> SUBSCRIPTION_QUOTA_CL ==")
qc = LogsIngestionClient(endpoint=quota_ep, credential=cred, logging_enable=False)
for s in subs_config:
    cq = next((p["costQuota"] for p in products_config if p["name"] == s["product"]), None)
    body = [{"TimeGenerated": str(datetime.now(timezone.utc)), "Subscription": s["name"], "CostQuota": cq}]
    if upload_retry(qc, quota_id, quota_strm, body):
        print(f"  {s['name']} quota ${cq}")

print("\n== Generate test traffic through APIM ==")
api_version = "2025-03-01-preview"
prompts = ["In one sentence, what is FinOps?", "Give me a 5-word cost-saving tip.",
           "Name one Azure service for cost control.", "What is a savings plan, briefly?"]
ok = 0
for i in range(args.runs):
    s = random.choice(subs)
    m = random.choice(models_config)
    try:
        c = AzureOpenAI(azure_endpoint=f"{gw}/{inference_path}", api_key=s["key"], api_version=api_version)
        c.chat.completions.create(model=m["name"],
                                  messages=[{"role": "user", "content": random.choice(prompts)}],
                                  extra_headers={"x-user-id": "demo"})
        ok += 1
        print(f"  {i + 1:02d}/{args.runs} {s['name']:13s} {m['name']:16s} OK")
    except Exception as e:
        print(f"  {i + 1:02d}/{args.runs} {s['name']:13s} {m['name']:16s} ERR {str(e)[:110]}")
    time.sleep(0.2)
print(f"\ntraffic OK {ok}/{args.runs}")
print("DONE. Prices/quotas land in ~5-15 min (first write to a new custom table lags).")
