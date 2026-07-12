import base64
import json
import logging
import os

import botocore.session
from botocore.signers import RequestSigner
from kubernetes import client

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TARGET_NAMESPACE = os.environ.get("TARGET_NAMESPACE", "default")
EKS_CLUSTER_NAME = os.environ.get("EKS_CLUSTER_NAME")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

_cluster_info_cache = {}


def _get_cluster_info():
    if EKS_CLUSTER_NAME in _cluster_info_cache:
        return _cluster_info_cache[EKS_CLUSTER_NAME]

    eks = botocore.session.get_session().create_client("eks", region_name=AWS_REGION)
    desc = eks.describe_cluster(name=EKS_CLUSTER_NAME)["cluster"]
    info = {
        "endpoint": desc["endpoint"],
        "ca_data": desc["certificateAuthority"]["data"],
    }
    _cluster_info_cache[EKS_CLUSTER_NAME] = info
    return info


def _get_eks_bearer_token():
    session = botocore.session.get_session()
    sts = session.create_client("sts", region_name=AWS_REGION)
    signer = RequestSigner(
        sts.meta.service_model.service_id,
        AWS_REGION,
        "sts",
        "v4",
        session.get_credentials(),
        session.get_component("event_emitter"),
    )
    params = {
        "method": "GET",
        "url": f"https://sts.{AWS_REGION}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15",
        "body": {},
        "headers": {"x-k8s-aws-id": EKS_CLUSTER_NAME},
        "context": {},
    }
    signed_url = signer.generate_presigned_url(
        params, region_name=AWS_REGION, expires_in=60, operation_name=""
    )
    token = "k8s-aws-v1." + base64.urlsafe_b64encode(
        signed_url.encode("utf-8")
    ).decode("utf-8").rstrip("=")
    return token


def _k8s_api():
    info = _get_cluster_info()
    configuration = client.Configuration()
    configuration.host = info["endpoint"]
    configuration.ssl_ca_cert = None
    configuration.verify_ssl = True
    configuration.api_key = {"authorization": "Bearer " + _get_eks_bearer_token()}

    ca_path = "/tmp/eks-ca.crt"
    with open(ca_path, "wb") as f:
        f.write(base64.b64decode(info["ca_data"]))
    configuration.ssl_ca_cert = ca_path

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
                pod,
                namespace,
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
