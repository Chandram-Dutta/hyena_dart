# Security Policy

## Supported versions

Security fixes are provided in the latest published major version. Users should
upgrade to the latest Hyena Dart release before reporting a vulnerability.

## Reporting a vulnerability

Please report suspected vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/Chandram-Dutta/hyena_dart/security/advisories/new).
Do not open a public issue for an unpatched vulnerability.

Include the affected version, impact, reproduction steps, and any suggested
mitigation. Avoid including real credentials, proprietary source code, or
unnecessary personal data. The maintainer will assess the report and coordinate
disclosure and a fix when warranted.

Hyena parses untrusted source repositories, but its CLI runs with the invoking
user's filesystem permissions. The MCP server does not execute target code and
confines requested targets to its configured workspace root; Dart analysis may
still read installed SDK and resolved dependency sources outside that root.
