#!/bin/bash

# Auto unseal
sudo bash -c "cat >/root/unseal/s1_reconfig.sh" <<EOT
#!/bin/bash
BLACK="\033[0;30m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
GREY="\033[0;90m"
CYAN="\033[0;36m"
RED="\033[0;31m"
PURPLE="\033[0;35m"
WHITE="\033[1;37m"
COLOR_RESET="\033[0m"

clear
cat <<DESCRIPTION
$WHITEWe're adding a new "seal" stanza to our config file:$COLOR_RESET

$CYANseal "awskms" {
    region = "${AWS_REGION}"
    kms_key_id = "2582a2b2-ed55-44c9-b809-12e33914d844"
}$COLOR_RESET

Press any key to continue...
DESCRIPTION

read -n1 kbd

cat >>/etc/vault.d/vault.hcl <<VAULTCFG

seal "awskms" {
    region = "${AWS_REGION}"
    kms_key_id = "${AWS_KMS_KEY_ID}"
}
VAULTCFG

echo "Restarting Vault..."
sleep 5
service vault restart
echo "Done"
echo "Getting status..."
sleep 3
vault status
EOT
chmod a+x /root/unseal/s1_reconfig.sh

sudo bash -c "cat >/root/unseal/s2_unseal_migrate.sh" <<EOT
#!/bin/bash
BLACK="\033[0;30m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
GREY="\033[0;90m"
CYAN="\033[0;36m"
RED="\033[0;31m"
PURPLE="\033[0;35m"
WHITE="\033[1;37m"
COLOR_RESET="\033[0m"

clear
cat <<DESCRIPTION
$WHITENow we need to unseal Vault with migration flag to move the 
key to AWS KMS.$COLOR_RESET

$CYANvault operator unseal -migrate $UNSEAL_KEY_1
vault operator unseal -migrate $UNSEAL_KEY_2
vault operator unseal -migrate $UNSEAL_KEY_3$COLOR_RESET

Press any key to continue...
DESCRIPTION

read -n1 kbd

vault operator unseal -migrate $UNSEAL_KEY_1 > /dev/null
vault operator unseal -migrate $UNSEAL_KEY_2 > /dev/null
vault operator unseal -migrate $UNSEAL_KEY_3 > /dev/null
vault status
EOT
chmod a+x /root/unseal/s2_unseal_migrate.sh

sudo bash -c "cat >/root/unseal/s3_unseal_migrate.sh" <<EOT
#!/bin/bash
BLACK="\033[0;30m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
GREY="\033[0;90m"
CYAN="\033[0;36m"
RED="\033[0;31m"
PURPLE="\033[0;35m"
WHITE="\033[1;37m"
COLOR_RESET="\033[0m"

clear
cat <<DESCRIPTION
$WHITEKey shards are no longer necessary. Instead, we have recovery keys.
You can leave the recovery keys as is using Shamir secret sharing,
but we're going to rekey it to just have a single recovery key.$COLOR_RESET

$CYANvault operator rekey \\\\
    -init \\\\
    -target=recovery \\\\
    -key-shares=1 \\\\
    -key-threshold=1$COLOR_RESET

Press any key to continue...
DESCRIPTION

read -n1 kbd

vault operator rekey -init -target=recovery -key-shares=1 -key-threshold=1 > /root/unseal/rekey.txt

export NONCE_KEY=\$(cat /root/unseal/rekey.txt | sed -n '/^Nonce/p' | awk -F " " '{print \$2}')
vault status
EOT
chmod a+x /root/unseal/s3_unseal_migrate.sh

sudo bash -c "cat >/root/unseal/s4_unseal_rekey.sh" <<EOT
#!/bin/bash
BLACK="\033[0;30m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
GREY="\033[0;90m"
CYAN="\033[0;36m"
RED="\033[0;31m"
PURPLE="\033[0;35m"
WHITE="\033[1;37m"
COLOR_RESET="\033[0m"

clear
cat <<DESCRIPTION
$WHITEFinally, we can complete the rekey process using the NONCE token 
generated by the previous command. Using three of the unseal/recovery
keys, we'll finalize rekeying the recovery key(s).$COLOR_RESET

$CYANvault operator rekey \\\\
    -target=recovery \\\\
    -key-shares=1 \\\\
    -key-threshold=1 \\\\
    -nonce=\$NONCE_KEY \\\\
    $UNSEAL_KEY_1

vault operator rekey \\\\
    -target=recovery \\\\
    -key-shares=1 \\\\
    -key-threshold=1 \\\\
    -nonce=\$NONCE_KEY \\\\
    $UNSEAL_KEY_2

vault operator rekey \\\\
    -target=recovery \\\\
    -key-shares=1 \\\\
    -key-threshold=1 \\\\
    -nonce=\$NONCE_KEY \\\\
    $UNSEAL_KEY_3$COLOR_RESET

Press any key to continue...
DESCRIPTION

read -n1 kbd

vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=\$NONCE_KEY $UNSEAL_KEY_1 > /dev/null
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=\$NONCE_KEY $UNSEAL_KEY_2 > /dev/null
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=\$NONCE_KEY $UNSEAL_KEY_3 > /dev/null

vault write sys/license text=${VAULT_LICENSE} > /dev/null

vault status
EOT
chmod a+x /root/unseal/s4_unseal_rekey.sh

sudo bash -c "cat >/root/unseal/s99_batch_configure.sh" <<EOT
echo "Configuring auto unseal..."
cat >>/etc/vault.d/vault.hcl <<VAULTCFG

seal "awskms" {
    region = "${AWS_REGION}"
    kms_key_id = "${AWS_KMS_KEY_ID}"
}
VAULTCFG

sleep 5
service vault restart
sleep 3

vault operator unseal -migrate $UNSEAL_KEY_1 > /dev/null
vault operator unseal -migrate $UNSEAL_KEY_2 > /dev/null
vault operator unseal -migrate $UNSEAL_KEY_3 > /dev/null

vault operator rekey -init -target=recovery -key-shares=1 -key-threshold=1 > /root/unseal/rekey.txt

export NONCE_KEY=\$(cat /root/unseal/rekey.txt | sed -n '/^Nonce/p' | awk -F " " '{print \$2}')

vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=\$NONCE_KEY $UNSEAL_KEY_1 > /dev/null
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=\$NONCE_KEY $UNSEAL_KEY_2 > /dev/null
vault operator rekey -target=recovery -key-shares=1 -key-threshold=1 -nonce=\$NONCE_KEY $UNSEAL_KEY_3 > /dev/null

vault write sys/license text=${VAULT_LICENSE} > /dev/null

echo "Done!"
EOT
chmod a+x /root/unseal/s99_batch_configure.sh