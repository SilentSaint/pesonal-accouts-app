# 1. AWS Java Serverless (Quarkus) Backend with DynamoDB & Terraform IaC

Date: 2026-07-26

## Status

Accepted (Supersedes Firebase BaaS proposal)

## Context

The automatic expense tracker requires a secure, high-performance, cost-effective backend that supports real-time multi-device sync between the Android mobile application and Web browser interface. The architecture must handle transaction ingestion, deduplication, bill statements, peer debt ledgers, and email push webhooks.

We evaluated:
1. Java 21 Serverless (Quarkus / GraalVM Native) on AWS Lambda + Amazon DynamoDB + API Gateway (REST & WebSocket) + Terraform IaC.
2. Managed Serverless BaaS (Firebase / Supabase).
3. Self-hosted custom Spring Boot container on EC2/Fargate with RDS PostgreSQL.

## Decision

We chose **AWS Serverless with Java 21 (Quarkus / GraalVM Native)**, **Amazon DynamoDB**, **Amazon API Gateway**, and **Terraform** for Infrastructure as Code (IaC) deployment management.

## Key Components

1. **Backend Runtime**: Java 21 using Quarkus framework compiled to GraalVM Native Executables, ensuring ultra-fast (<50ms) AWS Lambda cold starts.
2. **Database**: Amazon DynamoDB (25 GB Always Free Tier) configured with single-table design principles for fast single-digit millisecond reads/writes across Transactions, Accounts, Categories, Bills, and Peer Debt Ledgers.
3. **API & Real-time Sync**: Amazon API Gateway providing REST endpoints for CRUD operations and WebSockets for real-time transaction broadcast sync to mobile/web clients.
4. **Email Webhooks**: Amazon SNS / EventBridge receiving real-time Gmail push webhooks and triggering Lambda ingestion handlers.
5. **Infrastructure as Code (IaC)**: **Terraform** scripts to define, provision, version, and deploy all AWS infrastructure reproducibly.

## Consequences

### Positive
* **AWS Always Free Tier ($0.00/month)**: Fits comfortably within AWS Always Free quotas (1M Lambda invocations/mo, 25GB DynamoDB storage, 1M SNS/EventBridge events/mo).
* **High Performance**: Native Java compilation yields near-instant response times without container overhead.
* **Reproducible Infrastructure**: Terraform HCL scripts automate deployment, environment variables, IAM roles, and DynamoDB table schemas.
* **Developer Familiarity**: Built on standard Java microservice patterns with enterprise-grade type safety.

### Negative / Trade-offs
* Requires managing Terraform HCL state and AWS IAM policies.
* DynamoDB single-table design requires upfront access-pattern modeling.
