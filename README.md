# ☁️ AWS EKS Full-Stack Backend Deployment (Tickify)

## 📌 About The Project

This project demonstrates a **production-like backend deployment on AWS
using EKS**, built with a real-world DevOps workflow.

The application is a **ticket management system (Tickify)**, deployed on
a Kubernetes cluster, backed by a managed AWS database, and fully
containerized using Docker.

👉 This repository focuses on the **cloud infrastructure and
deployment** of the project.\
👉 The full backend source code is available here:\
🔗 https://github.com/bukovinszkiakos/Tickify

The goal of this project is to showcase: - Cloud-native application
deployment on AWS - Kubernetes orchestration (EKS) - Infrastructure as
Code (Terraform) - Secure configuration and secrets management - Real
backend system with authentication

------------------------------------------------------------------------

## 🗺️ Architecture Flow

    Internet
       ↓
    AWS LoadBalancer (auto-provisioned by Kubernetes)
       ↓
    EKS Cluster (Multi-AZ)
       ↓
    Kubernetes Service (tickify-service)
       ↓
    Pods (ASP.NET Core Backend - 2 replicas)
       ↓
    AWS RDS (SQL Server - private subnet)

            ↑
            │
       AWS ECR (Docker Images)


------------------------------------------------------------------------

## 🧱 Architecture Overview

-   🧠 **Backend API (ASP.NET Core)** -- Ticket management system with
    authentication
-   ☸️ **AWS EKS Cluster** -- Runs containerized backend services
-   🐳 **Docker + ECR** -- Private container registry
-   🗄️ **AWS RDS (SQL Server)** -- Managed relational database
-   🌐 **AWS LoadBalancer (ELB)** -- Public API access
-   🔐 **Kubernetes Secrets** -- Secure configuration handling
-   📦 **Persistent Volume (EBS)** -- Storage provisioning via CSI
    driver

------------------------------------------------------------------------

## ✨ Key Features

-   ✅ Deployed backend API on AWS EKS
-   ✅ Private Docker images stored in AWS ECR
-   ✅ Managed database (AWS RDS) connected securely from EKS
-   ✅ Infrastructure fully provisioned with Terraform
-   ✅ Kubernetes Deployments & Services
-   ✅ Horizontal Pod Autoscaler (HPA)
-   ✅ Persistent storage using AWS EBS CSI Driver
-   ✅ Secure environment configuration using Kubernetes Secrets
-   ✅ JWT-based authentication system
-   ✅ Multi-AZ ready infrastructure (EKS + RDS)

------------------------------------------------------------------------

## ⚙️ Tech Stack

-   AWS (EKS, RDS, ECR, EC2, VPC)
-   Kubernetes
-   Terraform
-   Docker
-   ASP.NET Core (.NET)
-   SQL Server
-   Bash / CLI tools

------------------------------------------------------------------------

## 🚀 Deployment Flow

### 1️⃣ Provision infrastructure

``` bash
cd terraform
terraform init
terraform apply
```

### 2️⃣ Configure Kubernetes

``` bash
aws eks update-kubeconfig --region eu-central-1 --name akos-tickify-eks
```

### 3️⃣ Deploy application

``` bash
kubectl apply -f k8s/
```

### 4️⃣ Get public endpoint

``` bash
kubectl get svc
```

👉 Access API via LoadBalancer URL

------------------------------------------------------------------------

## ⚠️ Environment Setup

Before deploying, create your Kubernetes secret:

``` bash
kubectl apply -f k8s/secret.yaml
```

Use the provided template:

``` bash
k8s/secret.example.yaml
```

------------------------------------------------------------------------

## 🧪 API Testing

``` bash
curl -X POST http://<LOADBALANCER_URL>/Auth/Register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@test.com",
    "username": "testuser",
    "password": "Test123!"
}'
```

------------------------------------------------------------------------

## 🔐 Authentication

-   JWT-based authentication
-   Token stored in HTTP-only cookie
-   Role-based authorization supported

------------------------------------------------------------------------

## 📊 Scaling

-   Backend runs with multiple replicas
-   Horizontal Pod Autoscaler configured
-   EKS node group supports scaling

------------------------------------------------------------------------

## 🔐 Configuration & Secrets

-   Kubernetes Secrets store:
    -   Database connection string
    -   JWT configuration

------------------------------------------------------------------------

## 🧠 Infrastructure Design Highlights

-   Separate VPC with private subnets
-   RDS is not publicly accessible
-   Only EKS nodes can access database
-   Security groups restrict traffic

------------------------------------------------------------------------

## 📋 Task Coverage

This project implements the following requirements:

-   ✅ EKS cluster with multi-AZ node groups
-   ✅ Private ECR for container images
-   ✅ Managed AWS RDS database
-   ✅ Kubernetes deployment with scaling
-   ✅ Secure communication between services (Security Groups)
-   ✅ Infrastructure as Code with Terraform

------------------------------------------------------------------------

## 🧹 Teardown (Clean Destroy)

``` bash
kubectl delete -f k8s/
# Wait 2-3 minutes for AWS resources to release
terraform state rm module.ecr
terraform destroy
```

------------------------------------------------------------------------

## 🧭 Future Improvements

-   🌐 Frontend integration (Next.js)
-   🔐 AWS Secrets Manager integration
-   📈 Monitoring (Prometheus + Grafana)
-   🚀 CI/CD pipeline (GitHub Actions)

------------------------------------------------------------------------

## 💡 Why This Project Matters

This project demonstrates the ability to design, deploy, and manage a
production-like cloud infrastructure using modern DevOps practices.

------------------------------------------------------------------------

## 👨‍💻 Developer

Ákos Bukovinszki\
https://github.com/bukovinszkiakos

------------------------------------------------------------------------

## 🛡️ License

MIT License

---

<p align="right">(<a href="#top">Back to top</a>)</p>
