
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

## terraform-aws-cloud branch specifics

Removes every laptop dependency remaining in terraform-aws:

- Jenkins and SonarQube run on a single EC2 instance in a private
  subnet, no public IP, no SSH, reachable only through AWS Systems
  Manager Session Manager, authenticated by IAM identity rather than
  network location or an open port.
- No secret is stored on any local disk. Every credential lives in
  AWS Secrets Manager, encrypted with a dedicated KMS key, pulled by
  the instance's IAM role at boot. The instance's write permission is
  scoped to exactly the one secret it legitimately needs to write
  back (the SonarQube token), not the full secrets prefix.
- Image builds run inside AWS CodeBuild, an isolated ephemeral
  container destroyed after each run, not a shared host Docker daemon
  reached through a socket mount.
- A real GitHub webhook triggers builds, not interval polling. The
  ALB accepts inbound traffic only from GitHub's published webhook
  CIDR ranges.
- Every terraform apply and ansible playbook run happens inside
  GitHub Actions, authenticated via OIDC federation scoped to this
  exact repository and branch. No AWS access key or secret key is
  stored anywhere, in GitHub or otherwise. The GitHub Actions IAM
  role is scoped to the specific services this project touches, not
  a blanket allow on every action and every resource.
- Secrets never appear as a command line argument anywhere in this
  branch's terraform, ansible or CI code, always passed as an
  environment variable, so they never land in shell history or a
  process list.

**Accepted, justified tradeoff**: the ALB listens on plain HTTP, not
HTTPS. No domain is owned, and ACM cannot issue a certificate without
domain ownership validation. Scoped as tightly as possible without
one: security groups restrict the ALB to GitHub's published webhook
CIDR ranges only, nothing else reaches it, and Jenkins/SonarQube UI
traffic never touches the ALB at all, it goes through an IAM
authenticated SSM tunnel instead.

**Still present, same reasoning as documented above for the aws
branch**: the Docker socket is still mounted into the Jenkins
container itself (in the user-data script's docker-compose.yml), used
only by Jenkins's own container lifecycle needs, not for building the
demo-service image, that moved to CodeBuild specifically to remove
this exposure from the image build path. The remaining mount is a
narrower, lower-frequency exposure than before, not a full elimination,
noted here rather than left implicit.

