# OpenEBS jiva

# replication factor
I have set the replication factor for jiva volumes to 1.  
This means that the volumes are of course not redundant.  
You can increase the factor, but this requires more nodes and disks.  

```bash
kubectl get jivavolumepolicy openebs-jiva-default-policy --namespace openebs -o yaml | \
sed 's/replicationFactor: ./replicationFactor: 3/' | \
kubectl apply -f -
```