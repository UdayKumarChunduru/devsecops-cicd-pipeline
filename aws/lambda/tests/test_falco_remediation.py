import json
from unittest.mock import MagicMock, patch

import pytest
from kubernetes import client as k8s_client

import falco_remediation


def _sns_event(*records):
    return {"Records": [{"Sns": {"Message": json.dumps(body)}} for body in records]}


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.setenv("EKS_CLUSTER_NAME", "devsecops-real")
    monkeypatch.setenv("AWS_REGION", "us-east-1")


@pytest.fixture
def mock_api():
    with patch("falco_remediation._k8s_api") as mock_factory:
        api = MagicMock()
        mock_factory.return_value = api
        yield api


def test_non_critical_event_is_ignored(mock_api):
    event = _sns_event({
        "priority": "Warning",
        "rule": "Some Non Critical Rule",
        "output_fields": {"k8s.pod.name": "demo-service-abc", "k8s.ns.name": "default"},
    })
    result = falco_remediation.handler(event, None)
    mock_api.delete_namespaced_pod.assert_not_called()
    assert result == {"status": "ok"}


def test_missing_pod_name_does_not_crash(mock_api):
    event = _sns_event({
        "priority": "Critical",
        "rule": "Privilege Escalation In Demo Container",
        "output_fields": {"k8s.ns.name": "default"},
    })
    result = falco_remediation.handler(event, None)
    mock_api.delete_namespaced_pod.assert_not_called()
    assert result == {"status": "ok"}


def test_wellformed_event_extracts_pod_and_namespace(mock_api):
    event = _sns_event({
        "priority": "Critical",
        "rule": "Privilege Escalation In Demo Container",
        "output_fields": {
            "k8s.pod.name": "demo-service-5647db499-57mmn",
            "k8s.ns.name": "default",
        },
    })
    falco_remediation.handler(event, None)
    mock_api.delete_namespaced_pod.assert_called_once_with(
        name="demo-service-5647db499-57mmn", namespace="default"
    )


def test_namespace_defaults_when_absent(mock_api, monkeypatch):
    monkeypatch.setenv("TARGET_NAMESPACE", "staging")
    import importlib
    importlib.reload(falco_remediation)

    with patch("falco_remediation._k8s_api") as mock_factory:
        api = MagicMock()
        mock_factory.return_value = api

        event = _sns_event({
            "priority": "Critical",
            "rule": "Shell Spawned In Demo Container",
            "output_fields": {"k8s.pod.name": "demo-service-xyz"},
        })
        falco_remediation.handler(event, None)

        api.delete_namespaced_pod.assert_called_once_with(
            name="demo-service-xyz", namespace="staging"
        )

    importlib.reload(falco_remediation)


def test_pod_already_gone_404_is_handled_gracefully(mock_api):
    api_exception = k8s_client.ApiException(status=404, reason="Not Found")
    mock_api.delete_namespaced_pod.side_effect = api_exception

    event = _sns_event({
        "priority": "Critical",
        "rule": "Sensitive File Read In Demo Container",
        "output_fields": {"k8s.pod.name": "demo-service-gone", "k8s.ns.name": "default"},
    })
    result = falco_remediation.handler(event, None)
    assert result == {"status": "ok"}


def test_unexpected_api_error_is_re_raised(mock_api):
    api_exception = k8s_client.ApiException(status=403, reason="Forbidden")
    mock_api.delete_namespaced_pod.side_effect = api_exception

    event = _sns_event({
        "priority": "Critical",
        "rule": "Privilege Escalation In Demo Container",
        "output_fields": {"k8s.pod.name": "demo-service-abc", "k8s.ns.name": "default"},
    })
    with pytest.raises(k8s_client.ApiException) as exc_info:
        falco_remediation.handler(event, None)
    assert exc_info.value.status == 403


def test_malformed_sns_message_does_not_block_other_records(mock_api):
    event = {
        "Records": [
            {"Sns": {"Message": "this is not valid json {{{"}},
            {"Sns": {"Message": json.dumps({
                "priority": "Critical",
                "rule": "Privilege Escalation In Demo Container",
                "output_fields": {"k8s.pod.name": "demo-service-good", "k8s.ns.name": "default"},
            })}},
        ]
    }
    result = falco_remediation.handler(event, None)
    mock_api.delete_namespaced_pod.assert_called_once_with(
        name="demo-service-good", namespace="default"
    )
    assert result == {"status": "ok"}


def test_missing_sns_key_in_record_does_not_crash(mock_api):
    event = {"Records": [{"NotSns": "unexpected shape"}]}
    result = falco_remediation.handler(event, None)
    mock_api.delete_namespaced_pod.assert_not_called()
    assert result == {"status": "ok"}


def test_get_eks_bearer_token_produces_k8s_aws_v1_prefix(monkeypatch):
    monkeypatch.setenv("EKS_CLUSTER_NAME", "devsecops-real")
    with patch("botocore.session.get_session") as mock_get_session:
        mock_session = MagicMock()
        mock_sts = MagicMock()
        mock_sts.meta.service_model.service_id = "sts"
        mock_session.create_client.return_value = mock_sts
        mock_session.get_credentials.return_value = MagicMock()
        mock_get_session.return_value = mock_session

        with patch("botocore.signers.RequestSigner") as mock_signer_cls:
            mock_signer = MagicMock()
            mock_signer.generate_presigned_url.return_value = (
                "https://sts.us-east-1.amazonaws.com/?Action=GetCallerIdentity"
            )
            mock_signer_cls.return_value = mock_signer

            token = falco_remediation._get_eks_bearer_token()
            assert token.startswith("k8s-aws-v1.")
