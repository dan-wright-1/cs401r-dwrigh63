# cs401r-dwrigh63: notes for Claude Code sessions

Graded course repo (CS 401R, NorthStar Retail AI platform). Each lab is submitted by
tagging `labN-submit` and pushing it; the TA grades the tag, never the AWS account.

**Start here for Lab 6:** read `docs/lab6-handoff.md`. It covers what is still in AWS,
the rebuild order, known gaps and the Windows tooling traps already hit in Labs 2-5.

How to work on labs in this repo:
- **The user drives graded lab work.** Explain what the lab asks for, give one step at a
  time with the command and what to look for in its output, and let the user run it and
  make the decisions. Do the work directly only when the user asks.
- Run `terraform plan -out=tfplan` and have it reviewed before any apply; never interrupt
  an apply.
- Evidence is CLI output committed under `docs/`; capture it while resources are live,
  since it cannot be recreated after teardown.
- Never commit credentials (`.env`, `*.tfvars`, `*.tfstate` are ignored); run
  `bash scripts/check-secrets.sh` before tagging.
- Ignore `snowflake/` (not on this branch) when working on graded AWS labs.
