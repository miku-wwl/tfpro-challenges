# Terraform Professional Challenge Repository Instructions

## Repository Purpose

This repository contains hands-on challenges for the HashiCorp Terraform Authoring and Operations Professional exam.

The challenges must test practical Terraform diagnosis, repair, refactoring, state management, plan review, and convergence.

They must not become general AWS, Azure, Kubernetes, PowerShell, shell scripting, or provider-internals exercises.

## Scope of Work

When the user asks to modify a challenge:

1. Work only inside the challenge explicitly named by the user.
2. Read the existing `Readme.md` and the challenge `.tf` file completely before making changes.
3. Directly edit the files in the current workspace.
4. Do not modify other challenges unless explicitly instructed.
5. Do not create commits, branches, pull requests, or push changes unless explicitly requested.

## Required Challenge Structure

Every challenge directory must contain exactly two files:

```text
challenge-XX/
├── Readme.md
└── challenge-XX.tf
```

Do not create any additional files or directories inside a challenge.

Prohibited challenge contents include:

* additional `.tf` files;
* `.tfvars` files;
* modules;
* graders;
* scripts;
* solutions;
* answer files;
* saved plans;
* state files;
* `.terraform`;
* `.terraform.lock.hcl`;
* temporary files;
* generated reports;
* hidden evaluation files.

All starter Terraform configuration must remain in the single `challenge-XX.tf` file.

External agents will grade the challenge. Do not implement a grader inside the challenge directory.

## Challenge Numbering

Preserve the existing challenge number.

The filenames must remain:

* `Readme.md`
* `challenge-XX.tf`

Do not rename the challenge directory or change its number.

## Target Difficulty

Unless the user specifies otherwise, target a difficulty of approximately 90–95 out of 100.

A Terraform-experienced candidate should normally need approximately 35–60 minutes to complete the core challenge.

Difficulty must come from interacting Terraform concerns, not from:

* large directory structures;
* excessive numbers of resources;
* obscure provider implementation details;
* cloud-provider trivia;
* complicated shell commands;
* PowerShell programming;
* deliberately ambiguous instructions.

Each challenge should normally contain three to six related Terraform problems forming one coherent scenario.

Examples include:

* incompatible provider constraints;
* stale dependency selections;
* incorrect provider aliases;
* unstable `for_each` identities;
* resource-address migration;
* importing existing infrastructure without replacement;
* invalid complex-variable transformations;
* incorrect lifecycle behaviour;
* unsafe delete or replacement actions;
* output and state inconsistencies;
* configuration that applies but does not converge.

Do not repeatedly reuse the same combination of provider aliases, import, and `for_each` across many challenges.

## Terraform Professional Alignment

Challenges should focus on transferable Terraform Professional capabilities such as:

* Terraform CLI workflow;
* initialization and validation;
* planning and applying;
* saved plans;
* non-interactive automation;
* provider sources and version constraints;
* dependency lock management;
* provider aliases;
* variables, locals, collections, objects, maps, and sets;
* `for_each`, `count`, and resource addressing;
* expressions and dynamic configuration;
* dependencies and lifecycle;
* data sources;
* state inspection and state operations;
* import and refactoring;
* drift detection;
* backend and workspace behaviour;
* machine-readable output;
* sensitive values;
* variable validation;
* preconditions, postconditions, and checks;
* troubleshooting and final convergence.

Cloud resources are supporting fixtures. Cloud-provider knowledge must not be the primary difficulty.

If the existing challenge topic is clearly outside the Terraform Professional scope, preserve the challenge number but replace the topic with the nearest relevant Terraform Professional capability.

## Starter Requirements

The `.tf` file must remain an incomplete or defective starter, not a completed solution.

The starter may intentionally fail during:

* initialization;
* validation;
* planning;
* action review;
* import;
* apply;
* final convergence.

The candidate must be able to diagnose the problems using Terraform behaviour, diagnostics, state, and plan output.

Do not:

* disclose the final fix in comments;
* leave the entire configuration blank;
* require candidates to guess hidden requirements;
* introduce random or non-reproducible failures;
* include real credentials;
* require Terraform or provider source-code modifications;
* convert required managed resources into placeholder resources to bypass the task.

LocalStack credentials such as `test` may be used only when clearly documented as local simulation credentials.

## README Style

Write `Readme.md` as an examination task brief, not a tutorial.

Use these sections where applicable:

1. Scenario
2. Exam Objectives
3. Starter State
4. Candidate Tasks
5. Constraints
6. Agent Grading Contract
7. Completion Conditions
8. Cleanup

Tasks must describe required outcomes without prescribing the exact sequence of commands or providing final HCL.

Do not provide step-by-step solutions such as:

* the exact `terraform import` command;
* the final `for_each` expression;
* the final provider mapping;
* the exact sequence of all CLI commands;
* complete replacement code.

It is acceptable to identify the Terraform capability that candidates are expected to use.

## Constraints

Use constraints only when they protect the intended Terraform skill.

Common valid constraints include:

* do not destroy and recreate legacy infrastructure;
* do not manually edit state JSON;
* do not use `-target` to fake convergence;
* do not change fixed physical resource names;
* do not use cloud CLIs to create Terraform-managed resources;
* do not hide required drift using `ignore_changes`;
* do not remove resources from state to bypass grading;
* do not add another `.tf` file.

Avoid arbitrary restrictions that do not serve the exam objective.

## Agent Grading Contract

Each README must contain concrete, machine-verifiable acceptance criteria.

The grading contract may inspect:

* Terraform formatting;
* validation;
* configuration structure;
* provider source and constraints;
* aliases;
* resource addresses;
* saved-plan actions;
* state contents;
* output JSON;
* LocalStack or target-platform resources;
* final `terraform plan -detailed-exitcode`;
* prohibited workarounds.

State exact expected facts where possible, including:

* required resource addresses;
* expected counts of create, update, import, delete, or replace actions;
* forbidden delete or replacement actions;
* required output keys and values;
* required resource attributes;
* final detailed exit code `0`.

Do not create grading scripts inside challenge directories.

## Completion Standard

A valid completed challenge should normally satisfy:

* `terraform fmt -check`;
* `terraform validate`;
* the approved saved plan is applied when required;
* state addresses match the target design;
* actual infrastructure matches the requirements;
* outputs match the grading contract;
* the final full plan reports no changes.

The starter itself does not need to pass validation or planning when failure is intentional.

Do not accidentally repair the starter into the final answer while performing repository-level checks.

## Low-Value Content

Unless it is the explicit challenge topic, avoid:

* provider-binary directory inspection;
* provider-binary size checks;
* deep `terraform providers schema -json` parsing;
* hashing the lockfile as an exercise;
* memorizing plugin cache paths;
* meaningless `-reconfigure` use with an unchanged local backend;
* excessive shell or PowerShell pipelines;
* cloud CLI operations as the main challenge;
* repository cleanup as the primary task;
* proving only that generated files exist;
* obscure provider protocol or RPC details.

## Validation Before Finishing

After modifying a challenge:

1. Confirm only `Readme.md` and `challenge-XX.tf` remain in its directory.
2. Confirm the challenge number and filenames are unchanged.
3. Check that README requirements match the starter.
4. Check that the README does not reveal the solution.
5. Confirm the starter contains meaningful, related defects.
6. Confirm the grading contract is objective and executable.
7. Run `terraform fmt -check` where appropriate.
8. Run any checks that the available environment supports.
9. Do not claim runtime validation that was not actually performed.
10. Do not modify files outside the requested challenge.

## Final Response

After completing a challenge, briefly report:

* what was wrong with the original challenge;
* the main Terraform Professional capabilities now tested;
* estimated difficulty and completion time;
* checks actually executed;
* checks not executed because of environment limitations;
* the final files present in the challenge directory.

Do not paste the full solution or complete Terraform configuration into the response.
