# Cachepuppy Core Kubernetes Runtime Contract

This document describes the Kubernetes runtime contract for running the
`cachepuppy/cachepuppy` image. The managed service repo should treat this as the
source spec for generating manifests, Helm values, or controller-owned
resources.

## Runtime Modes

Cachepuppy supports two runtime modes:

- `CACHEPUPPY_RUNTIME=local` uses `Cluster.Strategy.DNSPoll`. This is the
  default and preserves the Docker Compose behavior.
- `CACHEPUPPY_RUNTIME=kubernetes` uses `Cluster.Strategy.Kubernetes.DNS`. This
  discovers pods through a Kubernetes headless Service and does not require
  Kubernetes API RBAC.

Use `kubernetes` for managed Kubernetes deployments.

## Required Environment

Set these variables for Kubernetes:

```yaml
env:
  - name: PHX_SERVER
    value: "true"
  - name: PORT
    value: "4000"
  - name: PHX_HOST
    value: "cachepuppy.example.com"
  - name: CACHEPUPPY_RUNTIME
    value: "kubernetes"
  - name: RELEASE_DISTRIBUTION
    value: "name"
  - name: RELEASE_COOKIE
    valueFrom:
      secretKeyRef:
        name: cachepuppy-core-secrets
        key: release-cookie
  - name: SECRET_KEY_BASE
    valueFrom:
      secretKeyRef:
        name: cachepuppy-core-secrets
        key: secret-key-base
```

The managed service owns min/max autoscaling policy through Kubernetes
Deployment/HPA settings. Cachepuppy core does not contact the Kubernetes API and
does not enforce the max node count.

## Node Identity

Every pod must have a unique Erlang node name. For IP-based Kubernetes DNS
discovery, derive it from the pod IP:

```yaml
env:
  - name: POD_IP
    valueFrom:
      fieldRef:
        fieldPath: status.podIP
  - name: RELEASE_NODE
    value: "cachepuppy_core@$(POD_IP)"
```

`RELEASE_NODE` must use the same basename as `LIBCLUSTER_NODE_BASENAME`.

## Clustering

Recommended Kubernetes discovery:

```yaml
env:
  - name: LIBCLUSTER_NODE_BASENAME
    value: "cachepuppy_core"
  - name: LIBCLUSTER_K8S_SERVICE
    value: "cachepuppy-headless"
  - name: LIBCLUSTER_POLLING_INTERVAL_MS
    value: "5000"
```

Create a headless Service for pod discovery:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cachepuppy-headless
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app: cachepuppy-core
  ports:
    - name: http
      port: 4000
      targetPort: http
    - name: epmd
      port: 4369
      targetPort: epmd
    - name: dist
      port: 9100
      targetPort: dist
```

`publishNotReadyAddresses: true` lets pods discover each other while they are
still starting.

## Erlang Distribution Ports

Use a fixed distribution port so NetworkPolicies and Services can allow
pod-to-pod clustering traffic:

```yaml
env:
  - name: ERL_AFLAGS
    value: "-kernel inet_dist_listen_min 9100 inet_dist_listen_max 9100"
```

Expose these container ports:

```yaml
ports:
  - name: http
    containerPort: 4000
  - name: epmd
    containerPort: 4369
  - name: dist
    containerPort: 9100
```

Allow pod-to-pod traffic on `4369` and the fixed distribution port.

## Persistence

Cachepuppy persists shard WAL, snapshot, checkpoint, and ownership metadata on
disk. The persistence directory is shared by shard owners across the cluster, so
Kubernetes deployments must mount a shared ReadWriteMany filesystem.

Recommended mount:

```yaml
env:
  - name: CACHE_STORAGE_DIR
    value: "/app/tmp/cache_shards"
volumeMounts:
  - name: cache-shards
    mountPath: /app/tmp/cache_shards
```

Use an RWX-capable storage backend such as EFS, Filestore, CephFS, or another
cluster-supported shared filesystem. Do not use independent per-pod RWO volumes
for the same Cachepuppy cluster.

Do not set `CACHE_PERSISTENCE_TEST_MODE=true` in production. It lowers WAL and
snapshot thresholds for local testing.

## Probes

Use `/healthz` for process health:

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  periodSeconds: 10
  timeoutSeconds: 3

readinessProbe:
  httpGet:
    path: /healthz
    port: http
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 12
```

`/healthz` only checks that the HTTP server is alive.

For diagnostics, call `/api/health` to inspect the current node name, cluster
size, and connected nodes.

## Optional Environment

Authentication:

```yaml
env:
  - name: AUTH_ENABLED
    value: "true"
  - name: JWT_SECRET
    valueFrom:
      secretKeyRef:
        name: cachepuppy-core-secrets
        key: jwt-secret
  - name: JWT_IDENTITY_CLAIM
    value: "sub"
```

Snapshot tuning:

```yaml
env:
  - name: CACHE_SNAPSHOT_INTERVAL_MS
    value: "300000"
```

## Autoscaling

Cachepuppy can run with Kubernetes autoscaling when the managed service supplies
the scale policy:

- Configure the HPA or Deployment min replicas from the managed console minimum.
- Configure the HPA max replicas from the managed console maximum.
- New pods join through libcluster DNS.

This model intentionally avoids Kubernetes API credentials and RBAC. Health
checks only confirm that the process is serving HTTP.

## Ingress and WebSockets

Cachepuppy serves HTTP and Phoenix WebSockets on the same port. The ingress or
gateway must support WebSocket upgrades and long-lived connections.

Managed service ingress should preserve:

- `Host`
- `X-Forwarded-Host`
- `X-Forwarded-For`
- `X-Forwarded-Proto`
- `Upgrade`
- `Connection`

Configure idle/read timeouts high enough for long-lived WebSocket sessions.

## StatefulSet Notes

A Deployment can work if pod IP based node names are acceptable. Use a
StatefulSet if you want stable pod identities instead.
