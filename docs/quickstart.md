# Quickstart
You need a clean Debian Linux version 12 (bookworm) with 4CPU, 8GB RAM and 40GB DISK.

## 1. Prerequisites
Set cgroupv1 
```bash
sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=0"/' /etc/default/grub
update-grub
reboot
```

## 2. Build Kubian setup package
```bash
cd ~
apt install -y git
git clone https://github.com/bihalu/kubian.git
cd kubian
./kubian-build-1.28.1.sh
```
Takes about 15 minutes ...  
coffe break ;-)

## 3. Setup kubernetes single node cluster 
```bash
./kubian-setup-1.28.1.tgz.self init single
```
Takes about 5 minutes ...  
almost done   

You can have a look at the cluster with k9s tool.  

```bash
k9s
```

![k9s screenshot](k9s.png)
Pods are created.  
 
## 4. Build Kubian app package for Wordpress 
```bash
cd apps
./kubian-wordpress-6.3.1.sh
```

## 5. Install Wordpress 
```bash
./kubian-wordpress-6.3.1.tgz.self install
```
Only 2 minutes left ...  
Follow the steps from the wordpress installation and you are done  

## Summary
You can set up a kubernetes cluster in under half an hour. If you have already built the setup and app package it is even faster. Save these packages on a usb stick and you can quickly set up a kubernetes cluster in no time.  

``/\_/\``  
``(='_')``   
``(,(")(")`` 
