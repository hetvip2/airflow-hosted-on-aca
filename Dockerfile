# Airflow image with the ACA Jobs operator + example DAGs baked in.
# Used by both the local docker-compose stack and the Azure Container Apps deploy,
# so what you run locally is exactly what runs in Azure.
FROM apache/airflow:2.10.2

# Operator dependencies (azure-identity, requests). apache-airflow is already in the base.
COPY airflow/requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# Bake in the operator/trigger (plugins) and the example + pipeline DAGs.
COPY airflow/plugins/ /opt/airflow/plugins/
COPY airflow/dags/ /opt/airflow/dags/
