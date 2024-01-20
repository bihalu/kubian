# Kubian
<ins>Kub</ins>ernetes on Deb<ins>ian</ins> Linux  

If you have no idea about kubernetes, then you should read the documentation first -> [kubernetes docs](https://kubernetes.io/docs/concepts/overview/)  

TL;DR  

or you can easily try kubernetes with Kubian ;-)  
Use the [quickstart](docs/quickstart.md) guide for this.

# Description
Kubian is a shell script that creates a self-executable package for installing kubernetes.  
It is intended for Debian Linux and can also be used in an airgap environment.

# Apps
Kubernetes applications can be deployed with kubectl or helm. However, you need some experience for this. That's why I created so-called Kubian app packages for a few applications. This means that the applications can be installed just as easily as Kubian itself.

* [minio](docs/minio.md)
* [minecraft](docs/minecraft.md)
* [vaultwarden](docs/vaultwarden.md)

# Backup
 Backups are important, kubian uses [velero](docs/backup.md) for this.
