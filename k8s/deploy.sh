#!/bin/bash
set -e

readonly IMAGE_URL="554422868760.dkr.ecr.eu-central-1.amazonaws.com/akos-tickify-backend:$(git rev-parse --short HEAD)"
readonly APP_POD_ROLE_ARN=$(terraform output -raw app_pod_role_arn)

echo "Deploying image: $IMAGE_URL"
echo "Using IAM role: $APP_POD_ROLE_ARN"

sed -e "s|IMAGE_PLACEHOLDER|$IMAGE_URL|g" \
    k8s/deployment.yaml > k8s/deployment.generated.yaml

sed -e "s|\${APP_POD_ROLE_ARN}|$APP_POD_ROLE_ARN|g" \
    k8s/serviceaccount.yaml > k8s/serviceaccount.generated.yaml

kubectl apply -f k8s/serviceaccount.generated.yaml
kubectl apply -f k8s/deployment.generated.yaml

kubectl rollout status deployment/tickify-backend --timeout=120s