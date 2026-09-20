# AWS credentials for agents

When an AWS CLI, SDK, Terraform, or integration-test command reports that
credentials are invalid or expired:

1. Ensure the shell has loaded the refreshable profile:

   ```bash
   source /home/rakshith/Antigravity/AutomaticExpenseTracker/scripts/aws-dev-auth.sh
   ```

2. Confirm the identity without printing credentials:

   ```bash
   aws sts get-caller-identity
   ```

3. If stale environment variables are overriding the profile, inspect only
   their names and remove them from the current agent shell if they are not
   intentionally being used:

   ```bash
   env | awk -F= '/^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN|SECURITY_TOKEN)=/ {print $1}'
   unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
   ```

4. Retry the AWS command. The `agent-login` profile obtains fresh credentials
   through `credential_process`; do not export the output of
   `aws configure export-credentials --format env`, because that is only a
   short-lived snapshot.

5. If the overall AWS login session has expired, ask the user for confirmation
   before running `aws_dev_login`. That command starts the browser-based login
   for the underlying `default` profile. Do not run plain `aws login` while
   `AWS_PROFILE=agent-login`, because it can overwrite the process profile.

See [the development authentication guide](../operations/aws-development-auth.md)
for setup and session-duration details.
