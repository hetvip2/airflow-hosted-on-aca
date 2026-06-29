# Airflow hosted on Azure Container Apps

[![CI](https://github.com/hetvip2/airflow-hosted-on-aca/actions/workflows/ci.yml/badge.svg)](https://github.com/hetvip2/airflow-hosted-on-aca/actions/workflows/ci.yml)

A self-contained [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
template that **hosts Apache Airflow on Azure Container Apps** and uses it to
orchestrate **Azure Container Apps Jobs**. You run one command, `azd up`, and get
a working Airflow (web + scheduler + triggerer) plus a sample ACA Job for Airflow
to drive — no servers to manage, scale-to-zero job execution, per-execution billing.

> **Two ways to combine Airflow + ACA Jobs**
> - **This repo (you host Airflow):** deploy the whole Airflow control plane on
>   Azure Container Apps. Good when you don't already run Airflow and want a
>   turnkey orchestrator next to your jobs.
> - **[`airflow-on-aca-jobs`](https://github.com/hetvip2/airflow-on-aca-jobs) (host nothing):**
>   drop the same operator into an Airflow you *already* run (Managed Airflow,
>   MWAA, self-hosted) and point it at ACA Jobs. Lowest ownership.
>
> Both share the exact same operator/trigger code, so you can start here and
> graduate to host-nothing later with zero DAG changes.

---

## Architecture

```
                         Azure Container Apps environment
   ┌───────────────────────────────────────────────────────────────┐
   │                                                                 │
   │   airflow-web        airflow-scheduler      airflow-triggerer   │
   │   (ingress :8080)    (LocalExecutor)        (deferrable ops)    │
   │        │                   │                      │             │
   │        └──────── Postgres Flexible Server (metadata DB) ────────┤
   │                                                                 │
   │   DAGs + plugins  ◄──  Azure Files share (mounted /shared)      │
   │                                                                 │
   │   user-assigned managed identity  ──► ARM Jobs API ──►  ACA Job │
   │   (Contributor on the resource group)                  (sample) │
   └───────────────────────────────────────────────────────────────┘
```

- **Airflow** runs as three Container Apps using **LocalExecutor** (tasks run in
  the scheduler process — simple, no Celery/Redis to operate).
- **DAGs and plugins** are delivered to a mounted **Azure Files** share, so you
  update workflows by re-uploading files — no image rebuild.
- A **user-assigned managed identity** (Contributor on the resource group) lets
  the operator call the ARM Jobs API with **no secrets in Airflow**.
- A **sample ACA Job** is deployed as the "muscle" Airflow drives out of the box.

---

## Quick start (local, ~5 minutes)

Run the exact same Airflow stack on your laptop with Docker before touching Azure.

```bash
git clone https://github.com/hetvip2/airflow-hosted-on-aca
cd airflow-hosted-on-aca

cp .env.example .env        # fill in your ACA Job + auth (see below)
docker compose up --build
```

Open <http://localhost:8080> (user `airflow` / password `airflow`), unpause
`aca_jobs_example`, and **Trigger DAG w/ config** to run your ACA Job.

For a local demo, the quickest auth is a short-lived ARM token:

```bash
az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
# paste into AZURE_ACCESS_TOKEN in .env
```

---

## Deploy to Azure (`azd up`)

### Prerequisites

- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI (`az`)](https://learn.microsoft.com/cli/azure/install-azure-cli) (used by the post-deploy upload hook)
- An Azure subscription and `azd auth login`

### Steps

```bash
azd env new my-airflow

# Required secrets (or azd will prompt):
azd env set POSTGRES_ADMIN_PASSWORD "$(openssl rand -base64 24)"
azd env set AIRFLOW_ADMIN_PASSWORD  "$(openssl rand -base64 18)"

azd up
```

`azd up` will:

1. Provision the infrastructure in `infra/main.bicep` (Log Analytics, ACA
   environment, managed identity + role assignment, Postgres, storage + file
   share, the three Airflow apps, and the sample ACA Job).
2. Run the **postprovision hook** (`scripts/upload-dags.*`) to upload `airflow/dags`
   and `airflow/plugins` to the file share.

When it finishes, `azd` prints the Airflow web URL (also `azd env get-values`
→ `AIRFLOW_WEB_URL`). Log in with `airflow` / your `AIRFLOW_ADMIN_PASSWORD`.

### Updating DAGs / plugins later

Edit files under `airflow/`, then re-run the upload hook:

```bash
azd hooks run postprovision       # or: ./scripts/upload-dags.sh
```

Airflow picks up the changes within a minute — no redeploy needed.

### Configurable parameters

| azd env variable | Default | Purpose |
| --- | --- | --- |
| `AZURE_LOCATION` | _(prompted)_ | Region (Postgres Flexible Server must be available there) |
| `POSTGRES_ADMIN_PASSWORD` | _(required)_ | Postgres admin password |
| `AIRFLOW_ADMIN_PASSWORD` | _(required)_ | Airflow web UI admin password |
| `NAME_PREFIX` | `aflo` | Prefix for resource names |
| `POSTGRES_ADMIN_USER` | `airflowadmin` | Postgres admin login |
| `AIRFLOW_ADMIN_USER` | `airflow` | Airflow web UI admin username |

---

## Running your own jobs

The included DAGs are **parameterized** — no code changes to run different
workloads:

- **`aca_jobs_example`** — "Trigger DAG w/ config" and fill the form: `job_name`,
  optional `command`, `args`, and `env` overrides. Blank fields fall back to the
  `aca_*` Airflow Variables (set from infra for the sample job).
- **`aca_jobs_pipeline`** — a multi-step / fan-out example showing how to chain
  and parallelize ACA Job executions.

To target *your* job instead of the sample, either pass `job_name` at trigger
time or set the Airflow Variables `azure_subscription_id`, `aca_resource_group`,
`aca_job_name` (the infra wires these automatically for the sample job).

### Authentication options

The operator resolves credentials in this order:

1. **Airflow Connection** (`azure_conn_id`) — service principal, pre-fetched
   token, or managed identity stored as an Airflow Connection.
2. **`AZURE_ACCESS_TOKEN`** env var — a short-lived ARM token (handy locally).
3. **`DefaultAzureCredential`** — on Azure this transparently uses the
   **user-assigned managed identity** (no secrets). Locally it falls back to your
   `az login` / environment credentials.

On the `azd`-deployed stack, option 3 is automatic via the managed identity.

---

## Project structure

```
airflow-hosted-on-aca/
├─ airflow/
│  ├─ dags/                 # aca_jobs_example, aca_jobs_pipeline (parameterized)
│  ├─ plugins/
│  │  ├─ operators/         # AzureContainerAppsJobOperator + ARM/auth helpers
│  │  └─ triggers/          # async trigger for deferrable execution
│  └─ requirements.txt      # azure-identity, requests
├─ infra/
│  ├─ main.bicep            # all Azure resources
│  └─ main.parameters.json  # azd → bicep parameter mapping
├─ scripts/
│  ├─ upload-dags.sh / .ps1 # postprovision: upload DAGs+plugins to the share
├─ tests/                   # 35 offline unit tests (mocked ARM, no Azure)
├─ Dockerfile               # stock apache/airflow + operator + DAGs (local stack)
├─ docker-compose.yml       # local Postgres + web + scheduler + triggerer
├─ azure.yaml               # azd template definition + hooks
└─ pyproject.toml           # pip-installable + pytest/ruff config
```

---

## Testing

The operator/trigger have **offline unit tests** (ARM calls mocked — no Azure
needed):

```bash
pip install -e ".[test]"
pytest
```

CI runs these on Python 3.10 and 3.11 and validates that the Bicep compiles.

> Airflow does not run natively on Windows. To run the tests on Windows, use the
> Docker image (`docker run --rm -v "${PWD}:/work" -w /work apache/airflow:2.10.2
> bash -lc "pip install -q pytest ruff && pytest"`).

---

## Notes & caveats

- **Executor:** LocalExecutor keeps the stack simple. For very high task
  concurrency, switch to CeleryExecutor/KubernetesExecutor — the operator code is
  unchanged. Scale has been validated to ~50 concurrent ACA Job executions.
- **Networking:** this template uses public ACA ingress and "allow Azure
  services" on Postgres for a fast start. For production, add a VNet + private
  endpoints (the [`n8n-on-aca`](https://github.com/simonjj/n8n-on-aca) template is a good private-networking reference).
- **Least privilege:** the managed identity gets `Contributor` on the resource
  group for simplicity. Scope it to a custom role limited to
  `Microsoft.App/jobs/*/start` + read for production.
- The Bicep is validated by `az bicep build` in CI; a live `azd up` deploy incurs
  Azure costs and is not run in CI.

## License

Apache-2.0 — see [LICENSE](LICENSE).
