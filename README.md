<a id="top"></a>
# Tickify — AWS EKS & DevOps Project

**Infrastructure as Code · Kubernetes · CI/CD · AWS**

Tickify is a cloud deployment project focused on provisioning, deploying, and operating a containerized application on AWS using Terraform, Amazon EKS, Kubernetes, and GitHub Actions.

## About the Project

The main goal of this project is to demonstrate practical DevOps and cloud engineering skills, including Infrastructure as Code, container orchestration, CI/CD automation, cloud networking, identity and access management, and infrastructure lifecycle management.

The infrastructure is provisioned with Terraform, application workloads run on Amazon EKS, container images are stored in Amazon ECR, and GitHub Actions automates the build and deployment process using AWS OIDC authentication.

The application consists of a Next.js frontend and an ASP.NET Core Web API backend. These components serve primarily as workloads for demonstrating cloud infrastructure, container orchestration, and the deployment pipeline.

## Architecture

```text
                             Users
                               |
                               v
                 AWS Application Load Balancer
                            (HTTP)
                               |
                  +------------+-------------+
                  |                          |
            /api/* and /Auth/*               /*
                  |                          |
                  v                          v
          Backend ClusterIP           Frontend ClusterIP
               Service                     Service
                  |                          |
                  v                          v
          ASP.NET Core Pods             Next.js Pods
             (HPA: 2–5)                 (2 replicas)
                  |
             +----+----+
             |         |
             v         v
          Amazon RDS  Amazon S3
         SQL Server   Uploaded images
         Express      and screenshots

    Kubernetes Ingress configures ALB routing
    AWS Load Balancer Controller manages the ALB

    Container Registry: Amazon ECR
    Infrastructure as Code: Terraform
    Orchestration: Amazon EKS / Kubernetes
    CI/CD: GitHub Actions + AWS OIDC
```

**Traffic flow:** The Kubernetes Ingress resource defines the routing configuration, and the AWS Load Balancer Controller manages the corresponding AWS Application Load Balancer. The Ingress resource itself is not a separate network hop.

### Architecture Overview

- **Amazon EKS:** Runs the containerized application workloads.
- **Amazon VPC:** Provides network infrastructure with public subnets, private subnets for worker nodes, and dedicated database subnets for RDS.
- **Application Load Balancer:** Receives incoming HTTP traffic and routes requests according to the configured Ingress rules.
- **AWS Load Balancer Controller:** Manages the ALB based on Kubernetes Ingress resources.
- **Amazon ECR:** Stores backend and frontend container images in separate repositories.
- **Amazon RDS:** Hosts the SQL Server Express database in dedicated private database subnets.
- **Amazon S3:** Stores uploaded screenshots and comment images.
- **Terraform:** Provisions and manages AWS infrastructure.
- **GitHub Actions:** Builds, scans, and deploys application container images.

## Key DevOps Features

### Infrastructure as Code

- Modular Terraform configuration for AWS infrastructure.
- Remote Terraform state stored in Amazon S3.
- Native S3 state locking using Terraform's `use_lockfile` functionality.
- Infrastructure provisioning and configuration through a bootstrap script.
- Separate infrastructure modules for networking, EKS (including IRSA configuration), RDS, S3, and ECR. GitHub Actions IAM and developer access are configured in the Terraform root.

### Kubernetes and Container Orchestration

- Separate Kubernetes Deployments for frontend and backend workloads.
- ClusterIP Services for internal application routing.
- Ingress-based traffic routing through an AWS Application Load Balancer.
- Horizontal Pod Autoscaler for backend workloads.
- AWS Load Balancer Controller installed through Helm.
- EKS managed node group with configurable scaling limits.
- Deployment rollout checks and component-specific rollback steps in the GitHub Actions workflow.

### CI/CD Automation

GitHub Actions automates the application's build and deployment workflow. The workflow runs when changes are pushed to the `master` branch.

The pipeline performs the following steps:

1. Checks out the source code.
2. Restores and builds the .NET backend, runs backend tests, installs frontend dependencies, and builds the frontend.
3. Authenticates to AWS using GitHub OIDC and an IAM role.
4. Builds separate Docker images for the backend and frontend.
5. Tags both images with the first seven characters of the Git commit SHA for version traceability.
6. Scans both locally built images with Trivy for HIGH and CRITICAL vulnerabilities that have available fixes. Findings are informational and do not currently fail the workflow.
7. Pushes the images to their respective Amazon ECR repositories.
8. Updates the Kubernetes configuration and applies the required ServiceAccount, Secret, Services, Ingress, and HPA resources.
9. Deploys the backend and waits for its rollout.
10. Deploys the frontend and waits for its rollout.
11. Attempts to roll back the affected Deployment if its rollout fails and a previous revision is available.

### AWS Identity and Access Management

- GitHub Actions authenticates to AWS through an IAM role and OpenID Connect (OIDC), avoiding long-lived AWS access keys in the workflow.
- The OIDC trust policy is intended to restrict access to the configured GitHub repository and branch.
- Kubernetes workloads use IAM Roles for Service Accounts (IRSA) for scoped AWS access.
- GitHub repository Secrets and Variables are configured by the bootstrap script.

### Storage and Database

- Amazon RDS for SQL Server Express stores relational application data.
- Amazon S3 stores uploaded images and screenshots.
- The backend stores S3 object keys and generates presigned URLs when files are requested.
- S3 public access is blocked and server-side encryption is enabled.
- Application access to S3 is configured through IRSA.

## Technology Stack

| Category | Technologies |
|---|---|
| Cloud Provider | AWS |
| Infrastructure as Code | Terraform |
| Containerization | Docker |
| Container Orchestration | Amazon EKS, Kubernetes |
| Compute | EC2 managed node group |
| Networking | VPC, public subnets, private subnets, dedicated DB subnets, Internet Gateway, NAT Gateway |
| Load Balancing | Application Load Balancer, AWS Load Balancer Controller |
| Container Registry | Amazon ECR |
| Relational Database | Amazon RDS for SQL Server Express |
| Object Storage | Amazon S3 |
| Identity and Access | IAM, OIDC, IRSA |
| CI/CD | GitHub Actions |
| Image Scanning | Trivy |
| Operations Tools | AWS CLI, Helm, kubectl, GitHub CLI, Bash |
| Application Workloads | Next.js, ASP.NET Core Web API, .NET 8 |

## Infrastructure Highlights

### Amazon EKS

- Hosts the frontend and backend workloads.
- Uses Kubernetes Deployments, Services, Ingress, and Horizontal Pod Autoscaler resources.
- Uses an EC2 managed node group configured with `t3.medium` instances.
- Desired node count: `2`.
- Minimum node count: `1`.
- Maximum node count: `4`.

The EKS control plane is managed by AWS across multiple Availability Zones. Worker-node placement across the three private subnets is not strictly guaranteed.

### Networking

- Public subnets, private worker-node subnets, and dedicated database subnets across three Availability Zones in `eu-central-1`.
- Internet Gateway for public subnet connectivity.
- A single NAT Gateway to reduce infrastructure costs.
- Internet-facing ALB for incoming application traffic.
- RDS access restricted by a VPC-scoped security group rule.

The current RDS security group allows TCP port `1433` from the configured VPC CIDR. This is broader than allowing traffic only from EKS worker nodes and should be reviewed for stricter deployments.

### Kubernetes Autoscaling

The backend Horizontal Pod Autoscaler is configured with:

- Minimum replicas: `2`
- Maximum replicas: `5`
- Target CPU utilization: `70%`

The node group and HPA provide separate scaling mechanisms: the HPA adjusts the number of backend pods, while the managed node group controls the available worker-node capacity.

### Amazon RDS

- SQL Server Express engine.
- Default instance configuration: `db.t3.micro`.
- Deployed in dedicated private database subnets.
- Single-AZ configuration (`multi_az = false`) to reduce costs for this demonstration environment.

### Amazon S3

- Stores uploaded application images and screenshots.
- Server-side encryption enabled.
- Public access blocked.
- Presigned URLs generated by the backend when files are requested.
- Application access provided through IRSA.

### Amazon ECR

- Separate repositories for backend and frontend images.
- Image scanning on push enabled.
- Lifecycle policy configured to retain a limited number of images.
- Repository cleanup configured through Terraform.

The ECR image scanning configuration is separate from the Trivy scan performed in the GitHub Actions workflow.

## Repository Structure

```text
.
├── .github/
│   └── workflows/
│       └── deploy.yml
├── backend/
├── frontend/
├── k8s/
├── scripts/
│   ├── bootstrap.sh
│   ├── apply-infrastructure.sh
│   └── destroy.sh
└── terraform/
    ├── modules/
    ├── main.tf
    ├── variables.tf
    └── terraform.tfvars.example
```

- `.github/workflows/deploy.yml` — CI/CD build, image scanning, and deployment workflow.
- `k8s/` — Kubernetes Deployments, Services, Ingress, and autoscaling configuration.
- `scripts/bootstrap.sh` — Initial infrastructure setup and deployment preparation.
- `scripts/apply-infrastructure.sh` — Infrastructure update workflow.
- `scripts/destroy.sh` — Ordered infrastructure teardown.
- `terraform/modules/` — Reusable Terraform modules.

## Prerequisites

The bootstrap workflow requires:

- Terraform `>= 1.10`
- AWS CLI
- Helm
- kubectl
- GitHub CLI (`gh`)
- OpenSSL

For local application development, Docker, Node.js 22, and the .NET 8 SDK may also be required.

You also need:

- An AWS account with sufficient permissions to create the required infrastructure.
- A GitHub account with write access to the repository.
- AWS CLI credentials configured locally.
- GitHub CLI authenticated to the appropriate account.

Verify your AWS identity and GitHub CLI authentication:

```bash
aws sts get-caller-identity
gh auth status
```

## Deployment

The recommended initial setup is handled by `scripts/bootstrap.sh`.

### 1. Configure Terraform variables

From the repository root:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` and configure the required values, including:

- `region`
- `db_username`
- `github_repository`

The GitHub repository value must use the owner/repository format, for example:

```hcl
github_repository = "bukovinszkiakos/Tickify"
```

Review `terraform/terraform.tfvars.example` for the complete list of required variables and defaults.

**Do not commit `terraform/terraform.tfvars` or any real credentials to Git.**

### 2. Configure AWS and GitHub access

Configure AWS credentials if necessary:

```bash
aws configure
aws sts get-caller-identity
```

Authenticate GitHub CLI:

```bash
gh auth login
gh auth status
```

### 3. Bootstrap the infrastructure

Run the script from the repository root:

```bash
./scripts/bootstrap.sh
```

The bootstrap workflow prepares the remote Terraform state, initializes and applies Terraform, configures EKS access, installs the AWS Load Balancer Controller through Helm, and configures the GitHub repository Secrets and Variables required by CI/CD.

Review the script's prompts and planned changes before confirming infrastructure creation.

### 4. Deploy the application

Once infrastructure and repository configuration are ready, push a change to the configured deployment branch:

```bash
git push origin master
```

GitHub Actions builds and tests the application, builds and scans the Docker images, pushes the images to ECR, and updates the Kubernetes workloads.

The pipeline uses the Git commit SHA to tag the images, making it possible to associate a deployed image with the source commit.

### 5. Retrieve the application endpoint

Run:

```bash
kubectl get ingress
```

Use the address displayed in the `ADDRESS` column. ALB provisioning can take several minutes.

Both Kubernetes Services use `ClusterIP`, so the public endpoint is obtained from the Ingress rather than from `kubectl get svc`.

### Important Kubernetes Configuration Note

Do **not** apply the entire `k8s/` directory manually as a substitute for the documented deployment workflow.

Some manifests contain placeholders that are populated or managed by the bootstrap and CI/CD process. In particular, `k8s/secret.yaml` contains `REPLACE_WITH_...` placeholder values. Applying it directly can create invalid application configuration and prevent backend pods from starting.

The deployment workflow manages the required Kubernetes Secret using GitHub Secrets and applies the ServiceAccount with its configured IAM role ARN.

## GitHub Actions Configuration

The bootstrap script configures the repository settings required by the deployment workflow.

### GitHub Secrets

The workflow uses these secret names:

- `GH_ACTIONS_ROLE_ARN`
- `APP_POD_ROLE_ARN`
- `AWS_BUCKET_NAME`
- `DB_CONNECTION_STRING`
- `JWT_SIGNING_KEY`
- `SEEDING_ADMIN_PASSWORD`
- `SEEDING_SUPERADMIN_PASSWORD`

### GitHub Variables

The workflow uses these repository variables:

- `AWS_REGION`
- `ECR_BACKEND_REPOSITORY`
- `ECR_FRONTEND_REPOSITORY`
- `EKS_CLUSTER_NAME`

The repository name and branch must match the values allowed by the GitHub OIDC trust policy.

## Operational Commands

Inspect Kubernetes resources:

```bash
kubectl get pods
kubectl get deployments
kubectl get services
kubectl get ingress
```

Inspect backend logs:

```bash
kubectl logs deployment/tickify-backend
```

Check backend rollout status:

```bash
kubectl rollout status deployment/tickify-backend
```

Check frontend rollout status:

```bash
kubectl rollout status deployment/tickify-frontend
```

These commands require a valid AWS identity, Kubernetes context, and cluster access.

## Availability and Cost Considerations

The infrastructure is designed as a learning and demonstration environment with cost-conscious choices.

- The EKS control plane is managed by AWS across multiple Availability Zones.
- The managed node group has a desired capacity of two nodes, with a minimum of one and maximum of four.
- Worker nodes are associated with private subnets across three Availability Zones, but placement across all zones is not guaranteed.
- RDS is single-AZ and does not provide Multi-AZ database failover in the current configuration.
- A single NAT Gateway reduces cost but creates a potential availability bottleneck for outbound traffic.

AWS resources continue to incur costs while provisioned, including the EKS control plane, EC2 worker nodes, RDS, NAT Gateway, ALB, storage, and data transfer.

**This project is not free to leave running.** Review current AWS pricing before deployment, monitor costs, and destroy the environment when it is no longer required.

## Updating and Destroying Infrastructure

For infrastructure-only updates, use the repository's infrastructure script:

```bash
./scripts/apply-infrastructure.sh
```

To destroy the deployed environment:

```bash
./scripts/destroy.sh
```

**Warning: destroying the infrastructure is destructive and can permanently delete application data.** Review the script and its prompts before confirming.

The destroy script removes Kubernetes resources in an ordered process, allowing the Ingress-managed ALB and related security groups to be released before Terraform destroys the infrastructure. It also empties and removes the application uploads bucket.

The Terraform state bucket, named in the form `tickify-terraform-state-{account-id}`, is intentionally preserved. If the environment is being retired permanently, verify the bucket and its contents before manually deleting it.

## Troubleshooting

### GitHub Actions cannot authenticate to AWS

- Verify that `aws sts get-caller-identity` works locally.
- Confirm that `github_repository` matches the actual repository owner and name.
- Check the OIDC trust policy for the expected repository and branch.
- Review the GitHub Actions logs for IAM permission errors.

### The application endpoint is missing

- Run `kubectl get ingress` and wait for the ALB address.
- Inspect Ingress events and the AWS Load Balancer Controller logs.
- Confirm that the controller was installed successfully during bootstrap.

### Backend pods fail to start

- Check `kubectl logs deployment/tickify-backend`.
- Verify the database connection string and other required settings.
- Confirm that the Kubernetes Secret was created through the deployment workflow.
- Do not apply placeholder values from `k8s/secret.yaml`.

### Terraform initialization fails

- Verify that the bootstrap process created or located the remote state bucket.
- Confirm that the AWS identity has permission to access the state bucket.
- Use the documented bootstrap workflow for a fresh deployment instead of running Terraform initialization without the required backend configuration.

## Future Improvements

Potential future improvements include:

- Enable HTTPS/TLS for public traffic.
- Restrict CORS to trusted frontend origins.
- Improve secret management and rotation.
- Configure Trivy findings to fail deployments based on an agreed severity threshold.
- Review RDS backup, recovery, and high-availability requirements.
- Evaluate NAT Gateway redundancy based on availability requirements and budget.
- Expand automated integration tests.
- Add monitoring, alerting, and operational dashboards.

## What This Project Demonstrates

- AWS infrastructure provisioning and lifecycle management with Terraform.
- Kubernetes workload deployment, service discovery, Ingress routing, and autoscaling.
- CI/CD automation using GitHub Actions.
- AWS authentication through OIDC and workload permissions through IRSA.
- Container image management using Amazon ECR and commit-based image tags.
- Vulnerability scanning with Trivy.
- Cloud networking, database connectivity, and object storage.
- Operational troubleshooting and awareness of security, availability, and cost trade-offs.

## Developer

Ákos Bukovinszki\
https://github.com/bukovinszkiakos

------------------------------------------------------------------------

## License

MIT License

---

<p align="right">(<a href="#top">Back to top</a>)</p>

*This is a learning and demonstration project. Review the current Terraform configuration, Kubernetes manifests, and GitHub Actions workflow before reusing it in another environment.*
