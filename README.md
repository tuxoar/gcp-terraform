# GCP / GKE Ramp-Up Lab

A staged Terraform lab that builds a production-shaped GCP environment, ending in
a hardened private GKE cluster. Each numbered directory is an independent
Terraform root module — apply them in order. The phases mirror the lab in the
chat that produced this scaffold.

## Goals

1. Internalize GCP's resource hierarchy (Organization → Folder → Project) and
   the difference between IAM and Org Policy.
2. Stand up a Shared-VPC networking pattern (the prod default).
3. Deploy a GKE cluster with the security controls a senior interviewer will
   probe: Workload Identity, private nodes, private control-plane endpoint,
   Shielded Nodes, Binary Authorization, Dataplane V2 + NetworkPolicy,
   CMEK on etcd and boot disks, dedicated minimally-privileged node SA.
4. Wire up a minimal supply chain (Artifact Registry + Binary Authorization
   attestor) so you can demo an unattested image being denied at admit time.

## Prerequisites

| Requirement | Notes |
|---|---|
| GCP Organization | If you only have a personal `@gmail.com`, set up Cloud Identity Free first (≈15 min) so you get an Organization resource. Without an org, Folders and most Org Policies don't exist. |
| Billing account | Set a budget alert at $20. A regional GKE control plane is ~$73/mo; **destroy when not actively learning**. |
| Roles on the org/folder you'll build under | `roles/resourcemanager.folderAdmin`, `roles/resourcemanager.projectCreator`, `roles/billing.user`, `roles/orgpolicy.policyAdmin`, `roles/iam.organizationRoleAdmin`. |
| Local tools | `gcloud` (with `gke-gcloud-auth-plugin`), `kubectl`, `terraform >= 1.6`. |
| Auth | `gcloud auth application-default login` — Terraform's google provider uses ADC. |

## Architecture

```
Organization (yourdomain.com)
│
├── Project: tf-state-<suffix>                        ← 00-bootstrap creates
│   ├── KMS keyring "tf-state" + key "state"
│   └── GCS bucket "tf-state-<suffix>" (versioned, UBLA,
│       public-access-prevention, CMEK)               ← holds Terraform state
│                                                       for every other phase
│
└── Folder: lab                                        ← 10-org applies org policies here
    │
    ├── Folder: shared
    │   └── Project: net-host-<suffix>                 ← 20-projects creates
    │       └── VPC: prod-vpc                          ← 30-network
    │           ├── subnet gke-nodes
    │           │   ├── secondary range pods (10.20.0.0/16)
    │           │   └── secondary range services (10.30.0.0/20)
    │           ├── Cloud Router + Cloud NAT (egress for private nodes)
    │           ├── Firewall: allow IAP→SSH on bastion SA
    │           └── Private Google Access ON
    │
    └── Folder: workloads
        └── Project: gke-prod-<suffix>                 ← 20-projects creates
            ├── KMS keyring "gke"                      ← 40-security
            │   ├── key etcd            (etcd app-layer secrets encryption)
            │   ├── key disks           (CMEK on node boot disks)
            │   └── key ar              (CMEK on Artifact Registry)
            ├── SA: gke-node-sa         (minimal: logWriter, metricWriter,
            │                            monitoring.viewer, AR reader)
            ├── GKE cluster "prod"                     ← 50-gke
            │   ├── Regional, VPC-native, Shared-VPC service project
            │   ├── Private nodes + Private endpoint
            │   ├── Master authorized networks (your bastion subnet)
            │   ├── Workload Identity (workload_pool = project.svc.id.goog)
            │   ├── Shielded Nodes + Secure Boot + Integrity Monitoring
            │   ├── Dataplane V2 (Cilium/eBPF) → native NetworkPolicy
            │   ├── Binary Authorization: PROJECT_SINGLETON_POLICY_ENFORCE
            │   ├── database_encryption: CMEK on etcd Secrets
            │   ├── Release channel: REGULAR (no version pinning)
            │   ├── Image streaming, secret-manager addon
            │   └── Node pool with WORKLOAD_METADATA = GKE_METADATA
            ├── Bastion VM (IAP SSH, private endpoint access)  ← 50-gke (optional)
            ├── Artifact Registry repo "apps" (CMEK)           ← 60-supply-chain
            └── Binary Authorization policy + attestor          ← 60-supply-chain
                                                                ↑
                                                70-workload: kubectl-applied
                                                manifests (namespace + PSA
                                                restricted, default-deny
                                                NetworkPolicy, KSA bound to GSA
                                                via Workload Identity, demo
                                                Deployment)
```

## Apply order

Each phase reads outputs from the previous one. Two patterns to wire them up:

- **Easy**: copy outputs into the next phase's `terraform.tfvars`.
- **Clean**: enable the GCS backend (see `versions.tf` in each module) and use
  `data "terraform_remote_state"` to read prior outputs directly. Left as an
  exercise once you've done it once the easy way.

```bash
# 0. One-time
gcloud auth application-default login
cp terraform.tfvars.example 00-bootstrap/terraform.tfvars  # edit values

# 0a. Bootstrap — create the project + GCS bucket that will hold Terraform state.
#     Bootstrap's OWN state stays local (chicken-and-egg).
cd 00-bootstrap && terraform init && terraform apply
# capture: bucket_name
#
# (Optional) migrate bootstrap's local state into the bucket it just built:
#   edit 00-bootstrap/versions.tf, uncomment the backend "gcs" block, set
#   bucket = "<bucket_name>", then:
#     terraform init -migrate-state
#
# For each subsequent phase, do the same: uncomment the backend block in
# that phase's versions.tf with the same bucket and a unique prefix, then
# `terraform init -migrate-state` (or just `terraform init` on first apply).

# 1. Folders + Org Policies on the lab folder
cd ../10-org && terraform init && terraform apply
# capture: lab_folder_id

# 2. Host + service projects (Shared VPC), billing, API enablement
cd ../20-projects && terraform init && terraform apply
# capture: host_project_id, service_project_id, service_project_number

# 3. Networking: VPC, subnets, NAT, firewall, Shared VPC attach
cd ../30-network && terraform init && terraform apply
# capture: subnet self-link, pod/svc secondary range names

# 4. KMS keys + service-agent grants
cd ../40-security && terraform init && terraform apply

# 5. GKE cluster + node pool + bastion
cd ../50-gke && terraform init && terraform apply
# Then connect:
gcloud compute ssh bastion --tunnel-through-iap --project=$SERVICE_PROJECT --zone=$REGION-a
# from bastion: gcloud container clusters get-credentials prod --region=us-central1

# 6. Artifact Registry + Binary Authorization policy
cd ../60-supply-chain && terraform init && terraform apply

# 7. (from bastion) Apply the K8s manifests
kubectl apply -f 70-workload/
```

## Phase-by-phase: what to study while it applies

### Phase 00 — State backend (pre-lab)
- **Why a dedicated `tf-state` project?** So a `terraform destroy` of the
  lab folder can't take out your state bucket. The bootstrap project sits
  parallel to the lab folder, not under it.
- **What hardens a state bucket?**
  - Versioning (rollback after a bad apply).
  - Uniform bucket-level access (no per-object ACLs, IAM-only).
  - Public access prevention `enforced` — defense in depth even if a future
    IAM mistake grants `allUsers` something.
  - CMEK with a rotating KMS key — you own the encryption key.
  - Lifecycle rules to prune ancient noncurrent versions so the bucket
    doesn't grow unbounded.
- **State locking** in GCS is built into the backend — Terraform uses GCS
  object generation numbers to prevent concurrent writes. No DynamoDB-equivalent
  to configure, unlike S3.
- The bootstrap module's own state is local on first apply; optionally
  migrate it into the bucket it just created (`terraform init -migrate-state`).

### Phase 10 — Org & policies
- **Why**: IAM in GCP is additive only down the hierarchy. Org Policies are the
  separate guardrail system (the closest GCP analogue to SCPs).
- **Hot policies in this module**:
  - `iam.disableServiceAccountKeyCreation` — kills the #1 GCP credential-leak vector.
  - `iam.allowedPolicyMemberDomains` — only your Cloud Identity customer ID can
    receive IAM grants. Stops anyone from granting `allUsers viewer` on a bucket.
  - `compute.vmExternalIpAccess` — deny by default. Public IPs become a request,
    not an oversight.
  - `compute.requireOsLogin` — SSH gated by IAM, not project SSH metadata.
  - `storage.uniformBucketLevelAccess` — kills GCS ACL-based access.
  - `compute.restrictSharedVpcSubnetworks` — service projects can only use
    subnets you explicitly allow.

### Phase 20 — Projects
- **Why**: Projects are the unit of IAM scope, billing, and quota in GCP. You
  will have *many* more projects than you'd have AWS accounts.
- **The pattern**: one host project that owns the VPC (`net-host-*`), one
  service project per workload boundary (`gke-prod-*`). Real orgs run 10s–100s.

### Phase 30 — Network
- **VPC-native (alias IPs)**: pods get real VPC IPs from a secondary range.
  This is the only mode you should use; it's required for most features.
- **Firewall rules use service accounts as targets**, not tags — tags can be
  set by anyone with `compute.instances.setTags`, SAs require `iam.serviceAccountUser`.
- **Cloud NAT** gives private nodes egress without giving them public IPs.
- **Private Google Access** on the subnet is what lets private nodes reach
  Artifact Registry / Logging / Monitoring without internet egress.

### Phase 40 — KMS / CMEK
- The `etcd` key powers **application-layer secrets encryption** — without it,
  K8s Secrets in etcd are only base64'd inside Google's at-rest encryption (not
  encrypted under *your* key). The `database_encryption` block on the cluster
  references this key.
- The `disks` key encrypts node boot disks.
- KMS keys are regional and must live in the same region as the cluster.
- Service-agent grants: the GKE service agent
  (`service-<PROJECT_NUMBER>@container-engine-robot.iam.gserviceaccount.com`)
  needs `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the etcd key. The
  Compute service agent needs the same on the disks key.

### Phase 50 — The cluster
Every flag on `google_container_cluster` in `50-gke/main.tf` is annotated.
Re-read it slowly — it's the densest part of the lab.

**Workload Identity** is the most-asked GKE security question:
- KSA `app/app-ksa` gets the annotation `iam.gke.io/gcp-service-account=app-gsa@…`
- GSA `app-gsa` grants `roles/iam.workloadIdentityUser` to the KSA principal
  (`serviceAccount:PROJECT.svc.id.goog[app/app-ksa]`)
- Pod's call to the GKE metadata server returns a short-lived access token for
  `app-gsa` — no long-lived keys, no node-SA reuse.
- Be ready to contrast with: mounting JSON keys (bad), node SA with broad
  scopes (bad), the GCE metadata server being reachable from `hostNetwork`
  pods (defense in depth — node SA stays minimal).

**Other talking points the module enables**:
- `enable_private_endpoint = true` — the control plane has no public IP at all.
  Authorized networks alone still leaves the public IP exposed to bugs.
- `binary_authorization { evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE" }`
  — the cluster will only admit images that meet the project's Binauthz policy.
- `database_encryption { state = "ENCRYPTED" }` — CMEK on etcd Secrets.
- `release_channel = REGULAR` — auto-upgrades. Pinning a version in prod is an
  anti-pattern; release channels are the answer to "how do you patch?"
- Dedicated node SA — defense in depth if a pod escapes Workload Identity (e.g.
  via `hostNetwork: true` reaching the GCE metadata server, which returns the
  *node* SA's token).
- Confidential GKE Nodes: variable `enable_confidential_nodes` — flip to true
  to add AMD SEV memory encryption. Costs n2d machine types only.

### Phase 60 — Supply chain
- Artifact Registry repo with CMEK.
- A Binary Authorization attestor backed by a KMS asymmetric signing key.
- A Binauthz policy: default `ALWAYS_DENY`, with the cluster requiring an
  attestation from this attestor. The bypass list allows Google's system
  images so kube-system pods still admit.
- Try to `kubectl run nginx --image=nginx:latest` and watch it get denied —
  this is the canonical demo.

### Phase 70 — Workload (kubectl)
Plain YAML, no `kubernetes` provider, so you can read each object on its own.
- `namespace.yaml` — labeled with `pod-security.kubernetes.io/enforce=restricted`.
- `network-policy.yaml` — default-deny ingress and egress.
- `workload-identity-sa.yaml` — KSA annotated with the GSA email.
- `demo-app.yaml` — Deployment that uses the KSA, has a `runtimeClassName`
  comment showing how to swap to gVisor sandbox if you stood up a sandbox pool.

## Cost & teardown

Idle daily cost with everything applied is ~$3–5 (control plane dominates).
To stop the meter:

```bash
# Fast: delete just the expensive things
cd 50-gke && terraform destroy
# Full reset (note: 00-bootstrap stays — keeps your state bucket alive)
for d in 60-supply-chain 50-gke 40-security 30-network 20-projects 10-org; do
  (cd "$d" && terraform destroy -auto-approve)
done
# Nuke even the bootstrap (loses all state history)
cd 00-bootstrap && terraform destroy
```

Deleted projects sit in a 30-day "pending deletion" state — they still count
against project quota but cost nothing.

## Interview cheat-sheet

Re-read this list once before any GCP interview:

1. **GCP IAM is additive only**; Org Policies are the deny mechanism.
2. **Project = IAM scope, billing, quota** — not "account."
3. **Workload Identity** flow end-to-end: KSA annotation → GSA binding →
   GKE metadata server → short-lived token.
4. **Private nodes vs private endpoint** — authorized networks alone is not
   enough; a bug in the API server is internet-reachable until you also enable
   the private endpoint.
5. **NetworkPolicy is YAML until you enable Dataplane V2 (or Calico)** — the
   API exists in every cluster but enforcement does not.
6. **Application-layer secrets encryption** with CMEK; default at-rest
   encryption uses Google-managed keys.
7. **Binary Authorization** — admission control for images, attestor-driven.
8. **VPC Service Controls** — perimeter around Google API surfaces, no clean
   AWS analogue. Practice this one.
9. **Default Compute Engine SA has `roles/editor`** project-wide — never use it
   for node SA. This module proves you didn't.
10. **Release channels** are the GKE answer to "how do you patch?" — never pin
    a version long-term.

## What's intentionally out of scope

- Anthos / Fleet / Config Sync / Policy Controller.
- Cloud Service Mesh (Istio managed).
- Multi-cluster Ingress / Gateway.
- VPC Service Controls perimeter (worth reading about; not built here because
  it requires existing data services to be useful).

Add these as Phase 80+ if the role calls them out.
