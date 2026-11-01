# AWS development foundation

This Terraform root is pinned to Sydney (`ap-southeast-2`) and uses the
bootstrap-created remote state bucket plus DynamoDB lock table. The agreed
baseline is an application `t4g.large`, a data `t4g.medium`, 110 GiB gp3 across
three volumes, PostgreSQL on the data node, and separate files/backups buckets.
Instances are expected to run about 120 hours/month each.

It provisions the AWS foundation only: VPC/security groups, ARM64 EC2 nodes,
EBS, private ECR repositories, files/backups buckets, SSM access, GitHub OIDC
image-publisher access, and cost/disk alerts. It does not store application
credentials, deploy stateful services, or publish images. It reserves a stable
Elastic IP for the Application node and permits public ports 80 and 443 for
the future Traefik ingress; an open security-group port does not by itself
publish a Kubernetes service.

Both instances use the public subnet because this cost-constrained design has
no NAT gateway. The data security group has **no inbound Internet rule**; it
accepts PostgreSQL, Redis, Kafka, and Qdrant only from the application security
group. Its public IP exists solely for outbound package/SSM access and may
change after a stop/start cycle.

K3s uses pod CIDR `10.244.0.0/16` and service CIDR `10.245.0.0/16`; neither
may overlap the VPC `10.42.0.0/16`. The application instance disables EC2
source/destination checking for K3s pod networking. This does not grant public
access; the security group remains the inbound boundary.

Before the first plan, migrate the prior local state to the remote backend:

```bash
AWS_PROFILE=courier-terraform terraform -chdir=infra/terraform/aws-dev init -migrate-state
```

Create a local ignored `dev.tfvars` with your alert email:

```hcl
budget_alert_email = "you@example.com"
```

Then run `terraform plan -var-file=dev.tfvars -out=aws-dev.tfplan` and review
the resource count and all public boundaries before applying. Do not commit
`*.tfvars`, state files, plans, or credentials.

## Public DNS

The Application Elastic IP is the sole public endpoint for the Courier ingress.
After an approved apply, obtain it with:

```bash
AWS_PROFILE=courier-terraform terraform -chdir=infra/terraform/aws-dev output -raw application_ingress_ip
```

Set the `courier.io.vn` apex `A` record in ZoneDNS to that exact value (TTL
300 is appropriate during the initial rollout). Do not use an EC2 instance's
temporary public IP or any registrar-provided placeholder IP. DNS, Traefik
routers, and TLS certificates are configured in a later deployment step.

## AMI updates

The AMI lookup supplies the latest AL2023 ARM64 image only when an instance is
first created. Existing instances ignore AMI drift so an AWS-published image
does not silently replace K3s or the stateful data node. Schedule and review
an explicit instance replacement for every OS upgrade; confirm backups and
application recovery before applying it.

The same rule applies to changes in Application EC2 bootstrap user data:
Terraform intentionally ignores them for an existing node because cloud-init
does not rerun them safely. Apply those changes through a reviewed SSM runbook,
or schedule an explicit replacement after confirming K3s/Argo CD recovery.
