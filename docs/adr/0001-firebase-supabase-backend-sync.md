# 1. Managed BaaS (Firebase/Supabase) for Real-Time Multi-Device Sync

Date: 2026-07-26

## Status

Accepted

## Context

The expense tracking application requires seamless data synchronization across an Android mobile application (primary SMS ingestion engine) and a Web browser application (used for detailed viewing, management, and email connection management). The app is built for single-user personal use.

We evaluated three options:
1. Managed Serverless BaaS (Firebase/Supabase) with real-time database listeners and cloud functions.
2. Local-First with file-based personal cloud storage (Google Drive) sync.
3. Self-hosted custom API server (Node.js/Python + PostgreSQL on Docker/VPS).

## Decision

We chose **Managed Serverless BaaS (Firebase / Supabase)** with real-time database subscription capabilities and background cloud functions.

## Consequences

### Positive
* **Real-time Sync**: Transactions captured via local SMS parsing on Android sync immediately to the web app within milliseconds.
* **Zero Infrastructure Overhead**: No server management, SSL certificates, or database ops required.
* **Cost Efficiency**: Well within free-tier quotas for single-user scale ($0.00/month).
* **Background Email Scanning**: Cloud functions handle periodic Gmail API polling and PDF statement ingestion independently of whether the mobile app is active.

### Negative / Trade-offs
* Vendor coupling to Firebase / Supabase client SDKs.
* Requires internet connectivity for real-time sync between mobile and web (offline queue support will be handled locally on mobile client).
