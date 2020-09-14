#!/bin/bash

#
# function to make gpg keys non-interactively, taken from here:
# https://serverfault.com/questions/691120/how-to-generate-gpg-key-without-user-interaction
#

gpg_key=INVALID
function make_keys() {
    export GNUPGHOME=$1
    rm -rf $GNUPGHOME
    mkdir -m 0700 $GNUPGHOME
    # Need to kill the agent since we have removed $GNUPGHOME
    # The agent will be restarted by gnupg
    gpgconf --kill gpg-agent
    cat >keydetails <<EOF
     %echo Generating a key for Ubuntu PPA
     Key-Type: RSA
     Key-Length: 2048
     Subkey-Type: RSA
     Subkey-Length: 2048
     Name-Real: GTSAM Builder
     Name-Comment: GTSAM Builder
     Name-Email: gtsam.builder@foo.bar
     Expire-Date: 0
     %no-ask-passphrase
     %no-protection
     # Do a commit here, so that we can later print "done" :-)
     %commit
     %echo done
EOF
    echo '---------- listing keys: ---------------'
    gpg2 --no-default-keyring --list-keys
    echo '---------- generating key --------------'
    gpg2 --verbose --batch --gen-key keydetails
    echo '---------- listing keys 2: ---------------'
    gpg2 --no-default-keyring --list-keys
    echo '--------- setting trust for key --------'
    # Set trust to 5 for the key so we can encrypt without prompt.
    echo -e "5\ny\n" |  gpg2 --command-fd 0 --expert --edit-key gtsam.builder@foo.bar trust;
    rm keydetails
    echo '------------ listing keys again ---------------'
    # Test that the key was created and the permission the trust was set.
    gpg2 --list-keys
    # Test the key can encrypt and decrypt.
    # gpg2 -e -a -r gtsam.builder@foo.bar keydetails
    # Delete the options and decrypt the original to stdout.
    # gpg2 -d keydetails.asc
    # rm keydetails.asc

    # remember the key
    gpg_key=`gpg --list-keys gtsam.builder@foo.bar | sed '2q;d' | sed 's/ //g'`
}

#
# function to duplicate the complete packaging repo
#
function copy_repo() {
    packaging_repo=$1
    build_repo=$2
    orig_repo=$3
    tmp_name=gtsam-packaging-tmp
    echo "cleaning existing directory $tmp_name"
    rm -rf $tmp_name
    echo "cloning $orig_repo"
    git clone $orig_repo $tmp_name
    cd gtsam-packaging-tmp
    echo "getting all branches from $orig_repo"
    git pull --all
    echo "setting origin to $packaging_repo"
    git remote set-url origin $packaging_repo
    echo "pushing all branches to new repo $packaging_repo"
    git push origin --mirror
    cd ..
    rm -rf $tmp_name
}

function replace_string() {
    file=$1
    #to_replace=${2//\//\\/}
    to_replace=$2
    replacement=$3
    echo "replacing $to_replace with $replacement in file $file"
    # use bash variable expansion to replace / -> \/
    # so sed can handle it
    sed -i "s|${to_replace}|${replacement}|g" $file
}

# this your repo that tracks the sources, but doesn't do the
# nightly builds. It can be private or public.
# my_packaging_repo=https://github.com/mygithub/gtsam-packaging-test.git
my_packaging_repo=$1

# This is your PRIVATE repo that does the nightly build and holds
# the secret keys that are necessary to upload the package to the
# ubuntu ppa
# my_private_build_repo=https://github.com/mygithub/gtsam-building-test.git
my_private_build_repo=$2

#
# pass in the URL of your ubuntu ppa here
#
#my_ppa=ppa:myppa/gtsam-test
my_ppa=$3


# original packaging repo that has all the tracking branches already set up
borglab_packaging_repo=https://github.com/borglab/gtsam-packaging.git
# GTSAM source repo
gtsam_source_repo=https://github.com/borglab/gtsam.git
# Base version for snapshot. This determines the pristine tar ball
# that is used for building. Usually no need to touch that
gtsam_base_version=4.1.0


#
# make complete copy of borglab packaging repo
#
# copy_repo $my_packaging_repo $my_private_build_repo $borglab_packaging_repo

#
# now checkout the nightly build repo so we can modifiy the parameters there
#
tmp_build_name=gtsam-building-tmp
rm -rf $tmp_build_name
git clone -b nightly_build --single-branch $borglab_packaging_repo $tmp_build_name
cd $tmp_build_name
git checkout nightly_build

#
# generate the ubuntu secret key in the subdirectory
#
gpg_home=`pwd`/build_ubuntu/.gnupg
make_keys $gpg_home

#
# adjust the workflow file to match your repo and ppa
#
workflow_file=.github/workflows/main.yml
replace_string $workflow_file MY_GPG_KEY $gpg_key
replace_string $workflow_file MY_PPA_NAME $my_ppa
replace_string $workflow_file GTSAM_UPSTREAM_REPO $gtsam_source_repo
replace_string $workflow_file MY_PACKAGING_REPO $my_packaging_repo
replace_string $workflow_file MY_GPG_KEY $gpg_key
replace_string $workflow_file SNAPSHOT_BASE_VERSION $gtsam_base_version

#
# commit the changes (.gnupg files, workflow file) and
# push to the home repo
#
git add build_ubuntu/.gnupg
git add $workflow_file
git commit -a -m 'added ubuntu key, modified workflow file'
git remote set-url origin $my_private_build_repo
git push -f origin nightly_build:master

#
# print out instructions for the rest
#
echo '----------------------------------------------------------------'
echo ''
echo ' THIS IS YOUR PPA SECRET KEY: ' $gpg_key
echo ''
echo ' register it with the ubuntu keyserver by running this command: '
echo ''
echo "gpg --send-keys --keyserver keyserver.ubuntu.com $gpg_key"
echo ''
echo 'Then enroll it as a key on the ubuntu launchpad website'
echo ''
echo 'Make 100% sure the repo $my_private_build_repo is PRIVATE!'
