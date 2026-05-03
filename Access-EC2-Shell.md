# Access Shell of EC2 Instance
## Step 1 — Find Your Instance ID

### List all running instances in the ASG by name tag
```sh
aws ec2 describe-instances \
  --filters \
    "Name=tag:aws:autoscaling:groupName,Values=techkraft-app-asg" \
    "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].{ID:InstanceId,AZ:Placement.AvailabilityZone,IP:PrivateIpAddress,State:State.Name}" \
  --output table \
  --region us-east-1
```
Output:
```
-----------------------------------------------------------------
|                       DescribeInstances                       |
+------------+-----------------------+--------------+-----------+
|     AZ     |          ID           |     IP       |   State   |
+------------+-----------------------+--------------+-----------+
|  us-east-1b|  i-0075eee3c0d8c0773  |  10.0.11.147 |  running  |
|  us-east-1a|  i-0fe7b917d3d153f8b  |  10.0.10.190 |  running  |
+------------+-----------------------+--------------+-----------+
```

## Step 2 — Verify Instance Is SSM-Managed
```sh
## Check if SSM agent is registered and online
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-0075eee3c0d8c0773" \
  --query "InstanceInformationList[*].{ID:InstanceId,Ping:PingStatus,Agent:AgentVersion,Platform:PlatformName}" \
  --output table \
  --region us-east-1

## Should show PingStatus = Online
```

Output:
```sh
-----------------------------------------------------------------
|                  DescribeInstanceInformation                  |
+------------+-----------------------+---------+----------------+
|    Agent   |          ID           |  Ping   |   Platform     |
+------------+-----------------------+---------+----------------+
|  3.3.4108.0|  i-0075eee3c0d8c0773  |  Online |  Amazon Linux  |
+------------+-----------------------+---------+----------------+
```

## Step 3 — Start a Session (Interactive Shell)
```sh
## Basic shell session — equivalent of SSH
aws ssm start-session \
  --target i-0075eee3c0d8c0773 \
  --region us-east-1
```


## [Optional] Step 4: Restart Instance Template if needed:
```sh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name techkraft-app-asg \
  --preferences '{
    "MinHealthyPercentage": 50,
    "InstanceWarmup": 120
  }' \
  --region us-east-1
```

Watch instance being refreshed:
```sh
# Watch status every 10 seconds
watch -n 10 aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name techkraft-app-asg \
  --region us-east-1 \
  --query "InstanceRefreshes[0].{Status:Status,Complete:PercentageComplete,Reason:StatusReason}" \
  --output table
```

Output:
```sh
---------------------------------------------------------------------------------------------------------------------
|                                             DescribeInstanceRefreshes                                             |
+----------+--------------------------------------------------------------------------------------------------------+
|  Complete|  25                                                                                                    |
|  Reason  |  Waiting for instances to warm up before continuing. For example: i-0075eee3c0d8c0773 is warming up.   |
|  Status  |  InProgress                                                                                            |
+----------+--------------------------------------------------------------------------------------------------------+
```