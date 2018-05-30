#!/bin/bash

# these are the defaults for the commandline-options
KEYSIZE=2048
PASSPHRASE=
FILENAME_INPUT=~/.ssh/id_test
KEYTYPE=rsa
HOST=host
USER=${USER}
HOSTS_FILENAME=

# use "-p <port>" if the ssh-server is listening on a different port
SSH_OPTS="-o PubkeyAuthentication=no"

#
# NO MORE CONFIG SETTING BELOW THIS LINE
#

function usage() {
	echo "Specify some parameters, ${1}valid ones are:"
    echo "  -u(--user) <username>, default: ${USER}"
    echo "  -f(--file) <file>, default: ${$FILENAME_INPUT}"
    echo "  -h(--host) <hostname>, default: ${HOST}"
    echo "  -hf(--hosts_file) <hostnames_file>, default: ${HOSTS_FILENAME}"
    echo "  -p(--port) <port>, default: <default ssh port>"
    echo "  -k(--keysize) <size>, default: ${KEYSIZE}"
    echo "  -t(--keytype) <type>, default: ${KEYTYPE}"
    echo "  -P(--passphrase) <key-passphrase>, default: ${PASSPHRASE}"
    exit 2
}

if [[ $# < 1 ]]
then
	usage
fi

while [[ $# > 0 ]]
do
	key="$1"
	shift
	case $key in
		-u|--user)
			USER="$1"
			shift
			;;
		-f|--file)
			FILENAME_INPUT="$1"
			shift
			;;
		-h|--host)
			HOST="$1"
			shift
			;;
		-hf|--hosts_file)
			HOSTS_FILENAME="$1"
			shift
			;;
		-p|--port)
			SSH_OPTS="${SSH_OPTS} -p $1"
			shift
			;;
		-k|--keysize)
			KEYSIZE="$1"
			shift
			;;
		-t|--keytype)
			KEYTYPE="$1"
			shift
			;;
		-P|--passphrase)
			PASSPHRASE="$1"
			shift
			;;
		*)
			# unknown option
			usage "unknown parameter: $key, "
			;;
	esac
done

# check that we have all necessary parts
SSH_KEYGEN=`which ssh-keygen`
SSH=`which ssh`
SSH_COPY_ID=`which ssh-copy-id`

if [ -z "$SSH_KEYGEN" ];then
    echo Could not find the 'ssh-keygen' executable
    exit 1
fi
if [ -z "$SSH" ];then
    echo Could not find the 'ssh' executable
    exit 1
fi

function do_work() {
    # perform the actual work
    if [ -f $FILENAME_INPUT ]
    then
        FILENAME=$FILENAME_INPUT
        echo Using existing key
    else
        echo Creating a new key using $SSH-KEYGEN
        FILENAME=~/.ssh/${HOST//./-}
        echo Output Filename $FILENAME

        $SSH_KEYGEN -t $KEYTYPE -b $KEYSIZE  -f $FILENAME -N "$PASSPHRASE"
        RET=$?
        if [ $RET -ne 0 ];then
            echo ssh-keygen failed: $RET
            exit 1
        fi
    fi


    echo "Transferring key from ${FILENAME} to ${USER}@${HOST} using options '${SSH_OPTS}', keysize ${KEYSIZE} and keytype: ${KEYTYPE}"
    echo Adjust permissions of generated key-files locally
    chmod 0600 ${FILENAME} ${FILENAME}.pub
    RET=$?
    if [ $RET -ne 0 ];then
        echo chmod failed: $RET
        exit 1
    fi

    echo "Creating ssh directory if needed"
    ssh $SSH_OPTS $USER@$HOST 'mkdir -p ~/.ssh'

    echo Copying the key to the remote machine $USER@$HOST, this should ask for the password
    if [ -z "$SSH_COPY_ID" ];then
        echo Could not find the 'ssh-copy-id' executable, using manual copy instead
        cat ${FILENAME}.pub | ssh $SSH_OPTS $USER@$HOST 'cat >> ~/.ssh/authorized_keys'
    else
        $SSH_COPY_ID $SSH_OPTS -i $FILENAME.pub $USER@$HOST
        RET=$?
        if [ $RET -ne 0 ];then
          echo Executing ssh-copy-id via $SSH_COPY_ID failed, trying to manually copy the key-file instead
          cat ${FILENAME}.pub | ssh $SSH_OPTS $USER@$HOST 'cat >> ~/.ssh/authorized_keys'
        fi
    fi

    RET=$?
    if [ $RET -ne 0 ];then
        echo ssh-copy-id failed: $RET
        exit 1
    fi

    echo Adjusting permissions to avoid errors in ssh-daemon, this will ask once more for the password
    $SSH $SSH_OPTS $USER@$HOST "chmod go-w ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
    RET=$?
    if [ $RET -ne 0 ];then
        echo ssh-chmod failed: $RET
        exit 1
    fi

    # Cut out PubKeyAuth=no here as it should work without it now
    echo Setup finished, now try to run $SSH `echo $SSH_OPTS | sed -e 's/-o PubkeyAuthentication=no//g'` -i $FILENAME $USER@$HOST
}

HOSTS_ARRAY=()
if [ -f $HOSTS_FILENAME ]; then
    while IFS='' read -r line || [[ -n "$line" ]]; do
        echo "$line"
        HOSTS_ARRAY+=($line)
    done < "$HOSTS_FILENAME"

    for array_elt in "${HOSTS_ARRAY[@]}"; do
        HOST=$array_elt
        echo "Setting up: $HOST"
        do_work
        echo "Adding $HOST to ~/.ssh/config"
        echo "
Host $HOST
    IdentityFile ~/.ssh/${HOST//./-}
    IdentitiesOnly yes" | cat >>~/.ssh/config

        echo "Setting up: $HOST DONE"
    done
else
    do_work
fi