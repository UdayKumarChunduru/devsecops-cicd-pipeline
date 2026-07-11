import json
import logging
import os

from kubernetes import client

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TARGET_NAMESPACE = os.environ.get("TARGET_NAMESPACE", "default")


def _k8s_api():
    configuration = client.Configuration()
    configuration.host = os.environ["KUBE_API_SERVER"]
    configuration.api_key = {"authorization": "Bearer " + os.environ["KUBE_SA_TOKEN"]}
    configuration.verify_ssl = os.environ.get("KUBE_VERIFY_SSL", "false").lower() == "true"
    return client.CoreV1Api(client.ApiClient(configuration))


def _extract_pod(falco_event):
    fields = falco_event.get("output_fields", {})
    return fields.get("k8s.pod.name"), fields.get("k8s.ns.name", TARGET_NAMESPACE)


def handler(event, context):
    api = _k8s_api()

    for record in event.get("Records", []):
        try:
            sns_body = record["Sns"]["Message"]
            falco_event = json.loads(sns_body)
        except (KeyError, json.JSONDecodeError):
            logger.warning("Skipping record, message is not valid Falco JSON")
            continue

        if falco_event.get("priority", "").lower() != "critical":
            logger.info("Ignoring non-critical event: %s", falco_event.get("rule"))
            continue

        pod, namespace = _extract_pod(falco_event)
        if not pod:
            logger.warning("Critical event without a pod name, nothing to do")
            continue

        try:
            api.delete_namespaced_pod(name=pod, namespace=namespace)
            logger.info(
                "Deleted pod %s in %s. Rule: %s. Output: %s",
                pod, namespace,
                falco_event.get("rule"),
                falco_event.get("output"),
            )
        except client.ApiException as exc:
            if exc.status == 404:
                logger.info("Pod %s in %s already gone, nothing to do", pod, namespace)
            else:
                logger.error("Failed to delete pod %s in %s: %s", pod, namespace, exc)
                raise

    return {"status": "ok"}
