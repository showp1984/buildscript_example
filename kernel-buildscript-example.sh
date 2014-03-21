#!/bin/bash
#switches
USEAROMA=0;
USEPREBUILT=0;
USECHKS=0;
USEFTP=0;
#sourcedir
SOURCE_DIR="$(pwd)"
#crosscompile stuff
CROSSARCH="arm"
CROSSCC="$CROSSARCH-eabi-"
TOOLCHAIN="/PATH/TO/YOUR/TOOLCHAIN/bin"
#our used directories
PREBUILT="/PATH/TO/PREBUILTS/MEANING/ZIPCONTENTS/prebuilt"
OUT_DIR="$(pwd)/out"
#compile neccesities
USERCCDIR="$HOME/.ccache"
CODENAME="DEVICECODENAME"
DEFCONFIG=$CODENAME"_defconfig"
NRJOBS=$(( $(nproc) * 2 ))
#ftpstuff
RETRY="60s";
MAXCOUNT=30;
HOST="host.com"
USER="user"
PASS='pass'

#if we are not called with an argument, default to branch master
if [ -z "$1" ]; then
  BRANCH="master"
  echo "[BUILD]: WARNING: Not called with branchname, defaulting to $BRANCH!";
  echo "[BUILD]: If this is not what you want, call this script with the branchname.";
else
  BRANCH=$1;
fi

echo "[BUILD]: ####################################";
echo "[BUILD]: ####################################";
echo "[BUILD]: Building branch: $BRANCH";
echo "[BUILD]: ####################################";
echo "[BUILD]: ####################################";

OUT_ENABLED=1;
if [ ! -d "$OUT_DIR" ]; then
    echo "[BUILD]: Directory '$OUT_DIR' which is configure as output directory does not exist!";
    VALID=0;
    while [[ $VALID -eq 0 ]]
    do
        echo "[Y|y] Create it.";
        echo "[N|n] Don't create it, this will disable the output directory.";
        echo "Choose an option:";
        read DECISION;
        case "$DECISION" in
            y|Y)
            VALID=1;
            echo "Creating directory...";
            mkdir $OUT_DIR
            mkdir $OUT_DIR/kernel
            mkdir $OUT_DIR/modules
            ;;
            n|N)
            VALID=1;
            OUT_ENABLED=0;
            echo "Disabling output directory...";
            ;;
            *)
            echo "Error: Unknown input ($DECISION), try again.";
        esac
    done
else
    if [ ! -d "$OUT_DIR/kernel" ]; then
        mkdir $OUT_DIR/kernel
    fi
    if [ ! -d "$OUT_DIR/modules" ]; then
        mkdir $OUT_DIR/modules
    fi
fi

###CCACHE CONFIGURATION STARTS HERE, DO NOT MESS WITH IT!!!
TOOLCHAIN_CCACHE="$TOOLCHAIN/../bin-ccache"
gototoolchain() {
  echo "[BUILD]: Changing directory to $TOOLCHAIN/../ ...";
  cd $TOOLCHAIN/../
}

gotocctoolchain() {
  echo "[BUILD]: Changing directory to $TOOLCHAIN_CCACHE...";
  cd $TOOLCHAIN_CCACHE
}

#check ccache configuration
#if not configured, do that now.
if [ ! -d "$TOOLCHAIN_CCACHE" ]; then
    echo "[BUILD]: CCACHE: not configured! Doing it now...";
    gototoolchain
    mkdir bin-ccache
    gotocctoolchain
    ln -s $(which ccache) "$CROSSCC""gcc"
    ln -s $(which ccache) "$CROSSCC""g++"
    ln -s $(which ccache) "$CROSSCC""cpp"
    ln -s $(which ccache) "$CROSSCC""c++"
    gototoolchain
    chmod -R 777 bin-ccache
    echo "[BUILD]: CCACHE: Done...";
fi
export CCACHE_DIR=$USERCCDIR
###CCACHE CONFIGURATION ENDS HERE, DO NOT MESS WITH IT!!!

echo "[BUILD]: Setting cross compile env vars...";
export ARCH=$CROSSARCH
export CROSS_COMPILE=$CROSSCC
export PATH=$TOOLCHAIN_CCACHE:${PATH}:$TOOLCHAIN

gotosource() {
  echo "[BUILD]: Changing directory to $SOURCE_DIR...";
  cd $SOURCE_DIR
}

gotoout() {
    if [[ ! $OUT_ENABLED -eq 0 ]]; then
        echo "[BUILD]: Changing directory to $OUT_DIR...";
        cd $OUT_DIR;
    fi
}

gotosource

#Checking out latest upstream changes
echo "[BUILD]: Checking out branch: $BRANCH...";
git clean -f -d
git checkout $BRANCH

#saving new rev
REV=$(git log --pretty=format:'%h' -n 1)
echo "[BUILD]: Saved current hash as revision: $REV...";
#date of build
DATE=$(date +%Y%m%d_%H%M%S)
echo "[BUILD]: Start of build: $DATE...";

#build the kernel
echo "[BUILD]: Cleaning kernel (make mrproper)...";
make mrproper
echo "[BUILD]: Using defconfig: $DEFCONFIG...";
make $DEFCONFIG
echo "[BUILD]: Changing CONFIG_LOCALVERSION to: -kernel-"$CODENAME"-"$BRANCH" ...";
sed -i "/CONFIG_LOCALVERSION=\"/c\CONFIG_LOCALVERSION=\"-kernel-"$CODENAME"-"$BRANCH"\"" .config
echo "[BUILD]: Bulding the kernel...";
time make -j$NRJOBS || { return 1; }
echo "[BUILD]: Done!...";

if [[ ! $OUT_ENABLED -eq 0 ]]; then
    gotoout
    #prepare our zip structure
    echo "[BUILD]: Cleaning out directory...";
    find $OUT_DIR/* -maxdepth 0 ! -name '*.zip' ! -name '*.md5' ! -name '*.sha1' ! -name kernel ! -name modules ! -name out -exec rm -rf '{}' ';'
    if [ ! $USEPREBUILT -eq 0 ]; then
        if [ -d "$PREBUILT" ]; then
            echo "[BUILD]: Copying prebuilts to out directory...";
            cp -R $PREBUILT/* $OUT_DIR/
        fi
    fi
    if [ ! $USEAROMA -eq 0 ]; then
        echo "[BUILD]: Changing aroma version/data/device to: $BRANCH-$REV/$DATE/$CODENAME...";
        sed -i "/ini_set(\"rom_version\",/c\ini_set(\"rom_version\", \""$BRANCH-$REV"\");" $OUT_DIR/META-INF/com/google/android/aroma-config
        sed -i "/ini_set(\"rom_date\",/c\ini_set(\"rom_date\", \""$DATE"\");" $OUT_DIR/META-INF/com/google/android/aroma-config
        sed -i "/ini_set(\"rom_device\",/c\ini_set(\"rom_device\", \""$CODENAME"\");" $OUT_DIR/META-INF/com/google/android/aroma-config
    fi
    gotosource

    #copy stuff for our zip
    echo "[BUILD]: Copying kernel (zImage) to $OUT_DIR/kernel/...";
    cp arch/arm/boot/zImage $OUT_DIR/kernel/
    echo "[BUILD]: Copying modules (*.ko) to $OUT_DIR/modules/...";
    find $SOURCE_DIR/ -name \*.ko -exec cp '{}' $OUT_DIR/modules/ ';'
    echo "[BUILD]: Done!...";

    gotoout

    #create zip and clean folder
    echo "[BUILD]: Creating zip: kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip ...";
    zip -r kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip . -x "*.zip" "*.sha1" "*.md5"
    echo "[BUILD]: Cleaning out directory...";
    find $OUT_DIR/* -maxdepth 0 ! -name '*.zip' ! -name '*.md5' ! -name '*.sha1' ! -name kernel ! -name modules ! -name out -exec rm -rf '{}' ';'
    echo "[BUILD]: Done!...";

    if [ ! $USECHKS -eq 0 ]; then
        echo "[BUILD]: Creating sha1 & md5 sums...";
        md5sum kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip > kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip.md5
        sha1sum kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip > kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip.sha1
    fi

    if [ ! $USEFTP -eq 0 ]; then
        echo "[BUILD]: Testing connection to $HOST...";
        SUCCESS=0;
        ZERO=0;
        COUNT=0;
        while [ $SUCCESS -eq $ZERO ]
        do
            COUNT=$(($COUNT + 1));
            if [ $COUNT -eq $MAXCOUNT ]; then
                return 1;
            fi
            ping -c1 $HOST
            case "$?" in
                0)
                echo "[BUILD]: $HOST is online, continuing...";
                SUCCESS=1 ;;
                1)
                echo "[BUILD]: Packet Loss while pinging $HOST. Retrying in $RETRY!";
                sleep $RETRY ;;
                2)
                echo "[BUILD]: $HOST is unknown (offline). Retrying in $RETRY!";
                sleep $RETRY ;;
                *)
                echo "[BUILD]: Some unknown error occured while trying to connect to $HOST. Retrying in $RETRY seconds!";
                sleep $RETRY ;;
            esac
        done

echo "[BUILD]: Uploading files to $HOST...";
# Uses the ftp command with the -inv switches.
#  -i turns off interactive prompting
#  -n Restrains FTP from attempting the auto-login feature
#  -v enables verbose and progress
ftp -inv $HOST << End-Of-Session
user $USER $PASS
cd /$CODENAME/$BRANCH/
put kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip
put kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip.md5
put kernel_"$CODENAME"_"$DATE"_"$BRANCH"-"$REV".zip.sha1
bye
End-Of-Session
    fi
fi

echo "[BUILD]: All done!...";
gotosource

