# The lab at a glance

A visual tour of what this lab is and how it works — written for any
reader, technical or not. Diagrams render directly on GitHub.

**One sentence**: this repo *is* the lab's control plane — every
machine in the lab continuously pulls this repository and reshapes
itself to match what's written here, so operating the entire
infrastructure means editing files in Git.

## The nerve center

```mermaid
flowchart TD
    repo["🐙 THIS REPO on GitHub<br/>single source of truth:<br/>inventory · roles · workloads · CI"]

    subgraph lab["🏠 The lab"]
        hv["Hypervisor host(s)"]
        k8s["Kubernetes nodes (M2)"]
        apps["Banking workloads (M3)<br/>ledger · payments · fraud-sim"]
        mon["Observability (M4)<br/>Prometheus · Grafana · Loki"]
    end

    dev["🧑‍💻 Operator<br/>(me)"]

    dev -->|"git push"| repo
    hv -.->|"git pull + ansible, every 5 min"| repo
    k8s -.->|"git pull + ansible, every 5 min"| repo
    apps -.->|"GitOps controller watches apps/"| repo
    mon -.->|"GitOps controller"| repo
```

Nothing pushes config *to* machines. Every machine pulls, on a timer,
and self-heals any drift — a machine that someone hand-edits reverts
to the repo's desired state on its next pull. Adding a machine to the
lab is one command (`bootstrap/enroll.sh`); deciding what that machine
*becomes* is a Git commit that moves its hostname into a group.

```mermaid
sequenceDiagram
    participant M as New machine
    participant R as This repo
    participant O as Operator

    M->>R: enroll.sh — clone + install reconcile timer
    Note over M: gets the minimal baseline<br/>(updates, hardening, agent)
    O->>R: commit: add hostname to "k8s_node" group
    M->>R: next timed pull (≤5 min)
    Note over M: becomes a Kubernetes node,<br/>no one ever logged into it
```

## Milestones and what each one changes in the infra

```mermaid
flowchart LR
    M0["M0<br/>Repo scaffold<br/>─────<br/>infra impact:<br/>none yet"]
    M1["M1<br/>The pull loop<br/>─────<br/>commits start<br/>changing real<br/>machines"]
    M2["M2<br/>Network + k8s<br/>─────<br/>VLANs, VMs via<br/>Terraform, cluster<br/>self-assembles"]
    M3["M3<br/>Banking workloads<br/>─────<br/>deploy = merge;<br/>first real HA/DR<br/>requirements"]
    M4["M4<br/>Observability<br/>+ security<br/>─────<br/>every host auto-<br/>monitored; SOPS<br/>secrets; tested<br/>backup/restore"]
    M5["M5<br/>CI/CD maturity<br/>+ failure drills<br/>─────<br/>infra exercised:<br/>kill a node, watch<br/>alerting catch it"]

    M0 --> M1 --> M2 --> M3 --> M4 --> M5
```

Full details per milestone: [`ROADMAP.md`](../ROADMAP.md). Current
state: [`STATUS.md`](../STATUS.md). The design and its trade-offs
(why pull not push, why a public repo makes enrollment trivial, how
secrets are the one deliberate exception): [`ARCHITECTURE.md`](../ARCHITECTURE.md).

## How it's validated

Same doctrine as any production platform, scaled to a lab: CI lints
every change (YAML, Ansible; Terraform plan and image scanning join at
M2/M5), and the end state (M5) is scheduled failure drills — kill a
node on purpose, verify the HA design holds and the alerting actually
fires, write up the results in `docs/`.
