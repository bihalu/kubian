# Vault
Vault Server is launched on node port 30010.  
You have to initialize and unseal the vault first.

## Build
```bash
cd ~/kubian/apps
./kubian-vault-1.15.0.sh
```

## Install
```bash
./kubian-vault-1.15.0.tgz.self install

kubectl exec -n vault -ti vault-server-0 -- vault operator init
Unseal Key 1: <topsecretunsealkey1>
Unseal Key 2: <topsecretunsealkey2>
Unseal Key 3: <topsecretunsealkey3>
Unseal Key 4: <topsecretunsealkey4>
Unseal Key 5: <topsecretunsealkey5>

Initial Root Token: <initialroottoken>

Vault initialized with 5 key shares and a key threshold of 3. Please securely
distribute the key shares printed above. When the Vault is re-sealed,
restarted, or stopped, you must supply at least 3 of these keys to unseal it
before it can start servicing requests.

Vault does not store the generated root key. Without at least 3 keys to
reconstruct the root key, Vault will remain permanently sealed!

It is possible to generate new unseal keys, provided you have a quorum of
existing unseal keys shares. See "vault operator rekey" for more information.

kubectl exec -n vault -ti vault-server-0 -- vault operator unseal <topsecretunsealkey1>
kubectl exec -n vault -ti vault-server-0 -- vault operator unseal <topsecretunsealkey2>
kubectl exec -n vault -ti vault-server-0 -- vault operator unseal <topsecretunsealkey3>
```

## Uninstall
```bash
./kubian-vault-1.15.0.tgz.self uninstall
```