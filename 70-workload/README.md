# Phase 70 — Workload manifests

Plain K8s YAML, applied with `kubectl` from the bastion (or any host that can
reach the private control-plane endpoint).

```bash
# From the bastion:
gcloud container clusters get-credentials prod --region=us-central1 --project=$SERVICE_PROJECT

# Edit demo-app.yaml to replace <DEMO_GSA_EMAIL> with the output from phase 50.
kubectl apply -f namespace.yaml
kubectl apply -f network-policy.yaml
kubectl apply -f workload-identity-sa.yaml
kubectl apply -f demo-app.yaml
```

## What each file demonstrates

| File | Why |
|---|---|
| `namespace.yaml` | Labels the namespace `pod-security.kubernetes.io/enforce=restricted` — admission rejects any privileged, hostPath, hostNetwork pod, etc. |
| `network-policy.yaml` | Default-deny ingress + egress. Without Dataplane V2 (set in phase 50), this YAML would be inert. |
| `workload-identity-sa.yaml` | KSA annotated with the GSA email — this is half of the Workload Identity binding; the other half is the `roles/iam.workloadIdentityUser` grant created in phase 50. |
| `demo-app.yaml` | A pod using the KSA. Calls Secret Manager via `gcloud secrets versions access` to prove WI works end-to-end. |

## Binary Authorization demo

Once phase 60 is applied, this should fail because nginx:latest isn't attested:

```bash
kubectl run nginx --image=nginx:latest -n app
# Expected: admission webhook denied — image not attested.
```

To make it succeed, build your own image, push to the AR repo, and sign with
the attestor (see `60-supply-chain/outputs.tf` for the sign command).

## Adding gVisor sandbox

Phase 50 doesn't create a sandbox node pool by default (it adds a 2nd pool's
worth of node cost). To add one:

```bash
gcloud container node-pools create sandbox --cluster=prod --region=us-central1 \
  --sandbox=type=gvisor --machine-type=n2-standard-2 --num-nodes=1 \
  --service-account=$(terraform -chdir=../50-gke output -raw node_sa_email) \
  --project=$SERVICE_PROJECT
```

Then add `runtimeClassName: gvisor` to the pod spec (already commented in
`demo-app.yaml`).
