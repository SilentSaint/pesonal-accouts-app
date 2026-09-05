# 4. Staged Java Transaction Command Migration

Date: 2026-08-28

## Status

Accepted

## Context

ADR 0001 selects Java 21 Quarkus/Lambda and DynamoDB for the serverless
backend. Production instead currently invokes a Node.js CRUD Lambda, while
Java domain and application modules are un-deployed and its nominal DynamoDB
adapter stores state in process memory.

A big-bang replacement risks existing production data and makes it impossible
to compare each use case as it is migrated.

## Decision

Deploy a separate Java 21 transaction-command Lambda. Versioned `/v2` routes
will migrate a single complete use case at a time, while existing Node routes
remain unchanged until production parity is verified.

The first route is a health route plus unauthenticated-command rejection. Later
slices add verified gateway identity, AWS SDK DynamoDB repository adapters,
durable command queues, and canonical transaction processing. The Node handler
is retired only after migrated routes satisfy their end-to-end acceptance
criteria.

## Consequences

* The deployed topology incrementally converges on ADR 0001 without a second
  competing write path for any migrated route.
* Each versioned route must have explicit integration and browser verification
  before becoming canonical.
* The temporary Java 21 managed-runtime packaging is an executable migration
  foundation. Native Quarkus packaging is considered only after the command
  module is functionally complete and startup metrics justify it.
