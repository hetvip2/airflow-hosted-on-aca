try:
    from operators.azure_container_apps_job_operator import (
        AzureContainerAppsJobOperator,
    )
except ModuleNotFoundError:  # pragma: no cover - import fallback
    from plugins.operators.azure_container_apps_job_operator import (
        AzureContainerAppsJobOperator,
    )

__all__ = ["AzureContainerAppsJobOperator"]
