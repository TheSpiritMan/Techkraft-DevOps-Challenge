# Cleanup: Infrastructure Tear Down Guide
This document explains how to safely destroy all AWS resources created for the Techkraft DevOps Challenge alongwith the Terraform remote state bucket.

## Important Note
- Akll infrastructures are managed using Terraform (IaC).
- Only one resource is intentionally `NOT` managed by Terraform:
    - Terraform S3 Backend Bucket named `techkraft-tfstate`.
- This bucket must be deleted manually using `aws` cli or from AWS Console [if needed].

## Steps:
### Cleanup using Terraform
- Move into Terraform directory
    ```sh
    cd Terraform-Files\(Optional\)  
    ```

- Destroy All Infrastructure
    ```sh
    terraform destroy
    ```
    Output:
    ```sh
    Do you really want to destroy all resources?
    Terraform will destroy all your managed infrastructure, as shown above.
    There is no undo. Only 'yes' will be accepted to confirm.

    Enter a value: 
    ```
- Here, it will ask for confirmation. We have pass `yes` then only it will start destroying resources. It might take some time depending on the size of the resources.

- Now all resources provisioned using `Terraform` are destroyed.

### Cleanup using AWS CLI
- Delete `S3 Bucket` that we used as Terraform Remote Backend Storage.
- Empty Bucket:
    ```sh
    aws s3 rm s3://techkraft-tfstate --recursive
    ```
    Output:
    ```sh
    delete: s3://techkraft-tfstate/prod/terraform.tfstate
    ```

- Delete Versions silently:
    ```sh
    aws s3api list-object-versions \
      --bucket techkraft-tfstate \
      --output json \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
      | jq -c '.Objects[]' | while read -r obj; do
        key=$(echo $obj | jq -r '.Key')
        version=$(echo $obj | jq -r '.VersionId')

        aws s3api delete-object \
          --bucket techkraft-tfstate \
          --key "$key" \
          --version-id "$version" \
          --no-cli-pager > /dev/null
    done
    ```

- Delete delete-markers silently:
    ```sh
    aws s3api list-object-versions \
      --bucket techkraft-tfstate \
      --output json \
      --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
    | jq -c '.[]' | while read -r obj; do
        key=$(echo $obj | jq -r '.Key')
        version=$(echo $obj | jq -r '.VersionId')

        aws s3api delete-object \
          --bucket techkraft-tfstate \
          --key "$key" \
          --version-id "$version" \
          --no-cli-pager > /dev/null
    done
    ```

- Finally Delete S3 Bucket:
    ```sh
    aws s3api delete-bucket \
    --bucket techkraft-tfstate \
    --no-cli-pager
    ```