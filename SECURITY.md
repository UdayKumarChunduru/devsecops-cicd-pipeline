
## aws branch specifics

This branch replaces every local-demo simplification listed above with
its stated production alternative:

- **Lambda auth**: no static token anywhere. The Lambda's IAM execution
  role is converted to a Kubernetes bearer token per-invocation via a
  SigV4-signed STS request, mapped into cluster RBAC through aws-auth.
  See aws/lambda/falco_remediation.py for the implementation.
- **Floci replaced**: SNS topic, Lambda, IAM roles, EKS cluster.
- **Nexus replaced**: ECR, with AWS's own image scanning enabled
  alongside Trivy.
- **falcosidekick credentials**: IRSA instead of fake accesskeyid/
  secretaccesskey - see aws/iam/setup-falcosidekick-irsa.sh.

**Still accepted as local-demo simplifications even on this branch**:
Jenkins/SonarQube/Nexus-for-Java-artifacts still run on the laptop, not
on AWS infrastructure - only the deployment target and the Falco→SNS→
Lambda chain moved to AWS. The Docker socket mount into Jenkins is
still present with the same accepted-risk reasoning as documented above.
