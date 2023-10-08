# Vaultwarden
Vaultwarden Server is launched on node port 30010.  
Vaultwarden only works over https or localhost.  
You can forward the node port to your localhost and then log in.

## Port forward
```bash
ssh -i id_kubian_ed25519 -L 30010:192.168.178.60:30010 root@192.168.178.60
```

## Build
```bash
cd ~/kubian/apps
./kubian-vaultwarden-2023.7.1.sh
```

## Install
```bash
./kubian-vaultwarden-2023.7.1.tgz.self install
```

## Uninstall
```bash
./kubian-vaultwarden-2023.7.1.tgz.self uninstall
```