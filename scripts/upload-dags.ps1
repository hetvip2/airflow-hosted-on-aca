#!/usr/bin/env pwsh
# Uploads the local DAGs and plugins to the Azure Files share that the Airflow
# Container Apps mount at /opt/airflow/shared. Run automatically by azd as a
# postprovision hook; safe to re-run any time you change DAGs/plugins.
$ErrorActionPreference = 'Stop'

if (-not $env:STORAGE_ACCOUNT_NAME) { throw 'STORAGE_ACCOUNT_NAME not set (is the deployment finished?)' }
if (-not $env:FILE_SHARE_NAME) { throw 'FILE_SHARE_NAME not set' }

$root = Split-Path -Parent $PSScriptRoot
$account = $env:STORAGE_ACCOUNT_NAME
$share = $env:FILE_SHARE_NAME

Write-Host "Uploading DAGs and plugins to share '$share' on '$account'..."

$key = az storage account keys list --account-name $account --query '[0].value' -o tsv

az storage directory create --account-name $account --account-key $key --share-name $share --name dags --only-show-errors | Out-Null
az storage directory create --account-name $account --account-key $key --share-name $share --name plugins --only-show-errors | Out-Null

az storage file upload-batch --account-name $account --account-key $key `
  --destination "$share/dags" --source "$root/airflow/dags" --pattern "*.py" --only-show-errors | Out-Null

az storage file upload-batch --account-name $account --account-key $key `
  --destination "$share/plugins" --source "$root/airflow/plugins" --pattern "*.py" --only-show-errors | Out-Null

Write-Host "Done. Airflow will pick up the DAGs within a minute."
if ($env:AIRFLOW_WEB_URL) { Write-Host "Web UI: $($env:AIRFLOW_WEB_URL)" }
