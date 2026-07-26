# Infrastructure as Code (IaC) Guidelines (Terraform)

## Terraform Structure & Best Practices

```text
terraform/
├── modules/                   # Reusable IaC modules (dynamodb, lambda, api_gateway, sns)
└── environments/              # Environment configurations (dev, prod)
```

## Infrastructure Best Practices

### 1. Zero Hardcoded Secrets & Dynamic References
* Never hardcode AWS account IDs, credentials, or sensitive environment variables in HCL files.
* Use Terraform input variables (`variables.tf`) and output variables (`outputs.tf`).

### 2. Principle of Least Privilege
* IAM roles and policies for AWS Lambda functions must specify exact resource ARNs and minimum necessary permissions (e.g. `dynamodb:PutItem`, `dynamodb:Query`).

### 3. Cost-Optimization Invariants
* DynamoDB tables must be configured with `PAY_PER_REQUEST` billing mode or 1 RCU / 1 WCU provisioned capacity to enforce $0.00 cost under AWS Free Tier.
