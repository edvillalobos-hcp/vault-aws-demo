## Multi-feature Vault Demo running on AWS

# Features

* Auto unseal with AWS KMS
* Dynamic Database Secrets with RDS MySQL
* AWS IAM Authentication
* Encryption as a Service
* Automated PKI cert rotation
* Tokenization with PostgreSQL
* Format-Preserving Encryption

# Demo setup

1. Fork this repo (https://github.com/kevincloud/vault-aws-demo.git)
2. Create a workspace in Terraform Cloud using your newly-forked repo as the VCS
3. Create the following variables:
   * `aws_region`: The region to create these resources in. Default is `us-east-1`
   * `key_pair`: This is the key pair for being able to SSH into the EC2 instances. Required
   * `instance_type`: The name of the instance type to create for each EC2 instance. Default is `t3.small`
   * `db_instance_type`: The name of the instance type to use for the MySQL and PostgreSQL RDS instances. Default is `t3.small`
   * `num_nodes`: The total number of nodes to create for the cluster. This should be `1`, `3`, or `5` to satisfy `raft` requirements.
   * `db_user`: The username for the database instances. Default is `root`
   * `db_pass`: The password for the database instances. Required
   * `mysql_dbname`: The MySQL DB instance name. Default is `sedemovaultdb`
   * `postgres_dbname`: The PostgreSQL DB instance name. Default is `tokenizationdb`
   * `kms_key_id`: Your KMS Key ID to use for Auto Unseal. Required
   * `vault_dl_url`: The download URL for Vault. Default points to version 1.9.0
   * `vault_license`: The Vault Enterprise license key. Default is empty (not required)
   * `consul_tpl_url`: The download URL for Consul Template. Default points to 0.27.2
   * `autojoin_key`: The tag key used for Raft Storage auto-join. Default is `vault_server_cluster`
   * `autojoin_value`: The tag value used for Raft Storage auto-join. Default is `vault_raft`
   * `prefix`: A unique identifier to use when naming resources. Required
   * `git_branch`: The git branch to use when cloning this repo for running scripts. Default is `master`
   * `owner`: The email address of the person setting up this demo. Required
   * `se_region`: The region of the SE setting up this demo. Required
   * `purpose`: The purpose of this coonfiguration. Default is already set
   * `ttl`: The time-to-live for this configuration. Required
   * `terraform`: Whether this configuration is managed by Terraform. Default is `true`
4. Add your AWS credentials as environment variables. This should be done through Doormat.

To setup this demo:

1. Clone this repo to your machine
   ```bash
   git clone https://github.com/kevincloud/vault-aws-demo.git
   ```
2. Create a `terraform.tfvars` file and supply the following information:
   ```
   key_pair=<YOUR_AWS_KEY_PAIR>
   ```
3. Deploy the infrastructure
   ```bash
   terraform apply
   ```
4. Login to the vault server. The `vault-login` output from terraform contains an ssh command, though the key name and location may need to be modified to match your environment.

### Implementing Auto Unseal

This Vault instance is using defaults to manage the master key, using Shamir's secret sharing. Since we're likely to already have secrets, we really don't want to re-initialize Vault. Instead, we'll migrate from Shamir to AWS KMS.

Make sure you have already created a managed key in KMS. We'll need that key id.

#### Step 1. Update Vault Configuration

Once you're logged in, for the sake of simplicity, let's go ahead and login as root:

```bash
sudo su -
```

We'll need to add a few lines to Vault's configuration file, so let's start by stopping the vault service:

```bash
service vault stop
```

Using your favorite editor, edit the `/etc/vault.d/vault.hcl` file and add these lines, replacing <KEYID> with your AWS KMS key id:

```hcl
seal "awskms" {
    region = "us-east-1"
    kms_key_id = "<KEYID>"
}
```

Now, let start vault back up:

```bash
service vault start
```

#### Step 2. Unseal and Migrate

By default, Vault is sealed upon starting/restarting. So you would normally need to enter a quorum of unseal keys to unseal it. By implementing AWS KSM, we are eliminating the process of unsealing every time the service is restarted.

You can verify Vault is sealed by entering:

```bash
vault status
```

You'll see the specific line:

```bash
...
Sealed                   true
...
```

To complete the key migration, we'll need to manually unseal vault one last time. For this exercise, the unseal keys are located in the ~/init.txt file. Using the first three keys, enter the following commands, replacing <UNSEAL_KEY_X> with the respective key from the init.txt file:

```bash
vault operator unseal -migrate <UNSEAL_KEY_1>
vault operator unseal -migrate <UNSEAL_KEY_2>
vault operator unseal -migrate <UNSEAL_KEY_3>
```

The migration will now be complete. The vault will be unsealed, but to verify auto unseal is active, let's restart vault:

```bash
service vault restart
```

Now when you check the status of Vault:

```bash
vault status
```

You'll see it is unsealed by default:

```bash
...
Sealed                   false
...
```

#### Step 3. Remove Key Shares

We're almost done. Since our master key is managed by an external trusted source, we need to migrate away from a shared key to a single key.

```bash
vault operator rekey -init -target=recovery -key-shares=1 -key-threshold=1
```

Once again, we'll need our unseal keys from before as well as the nonce token provided after the rekey initialization:

```bash
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=<NONCE_TOKEN> <UNSEAL_KEY_1>
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=<NONCE_TOKEN> <UNSEAL_KEY_2>
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=<NONCE_TOKEN> <UNSEAL_KEY_3>
```

Review the status of vault...

```bash
vault status
```

...to ensure all settings are correct:

```bash
Key                      Value
---                      -----
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    1
Threshold                1
Version                  1.1.0
Cluster Name             vault-cluster-efcdaac3
Cluster ID               efe63829-a886-1d8d-3c5e-73cb5bc5cf3f
HA Enabled               false
```

Some fake credentials were automatically added to vault during setup. To verify all data is still intact, simply look up your credentials:

```bash
vault kv get secret/creds
```

You should see:

```bash
====== Metadata ======
Key              Value
---              -----
created_time     2019-04-05T18:01:18.980320626Z
deletion_time    n/a
destroyed        false
version          1

====== Data ======
Key         Value
---         -----
password    Super$ecret1
username    vault_user
```
