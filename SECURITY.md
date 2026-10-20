# Security policy

This is a personal portfolio project. It is deliberately over-engineered to show
infrastructure and delivery practices, and it holds no user data.

## Reporting a vulnerability

Please report security issues privately, not in a public issue:

1. Open the **Security** tab of this repository.
2. Choose **Report a vulnerability** (GitHub private vulnerability reporting).

If that option is not available, open an issue that says only that you have a
security concern, without details, and I will reply with a private channel.

## What to expect

- An acknowledgement within a few days. This is a spare-time project.
- A fix or a documented decision, and credit if you want it.

## Scope

In scope: the code, workflows and infrastructure definitions in this repository.
Out of scope: the services of GitHub and AWS themselves, and denial-of-service
testing against the live demo.

## How secrets are handled

No secrets are stored in the repository or in GitHub. AWS access from CI uses
short-lived OIDC tokens, and local runs use temporary credentials. If you find a
secret anywhere in the history, please report it as above.
