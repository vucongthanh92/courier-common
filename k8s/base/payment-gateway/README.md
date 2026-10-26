# payment-gateway Kubernetes configuration

The Deployment mounts a SOPS-generated `payment-gateway-config` Secret with a
complete `config.yaml` key. It contains SePay, database, and Redis credentials;
only ciphertext is committed in the development overlay.

The Go entrypoint uses `flag`, so it must receive `--config=...` directly. Do
not prefix the argument with a `start` subcommand: Go flag parsing would ignore
the following config flag.
