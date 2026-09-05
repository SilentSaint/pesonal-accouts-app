# Infrastructure as Code (IaC) Guidelines (Terraform)

Read and follow the repository [engineering workflow](../docs/engineering/workflow.md)
first. This file adds infrastructure-specific constraints only.

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

## Mandatory TDD and Vertical-Slice Workflow

* Invoke the `/tdd` skill before changing Terraform that affects runtime behavior, permissions, routes, Lambda wiring, or data storage.
* Start with a failing test or executable plan/validation at the public infrastructure seam, then make the smallest IaC change and re-run validation.
* Treat infrastructure work as part of one vertical slice with the application adapter and runtime behavior. Do not implement horizontal batches of Terraform resources detached from a verified use case.
* Do not close an issue for an HCL-only change until the relevant plan, deployment, backend tests, and runtime verification satisfy its acceptance criteria.
