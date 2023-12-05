#! /bin/bash

set -eux

setup_export() {
    export KERNEL_PATH=~/Repos/kernels/kernel_xiaomi_cepheus
    export ANYKERNEL_PATH=~/Repos/AnyKernel3
    export BUILDER_PATH=$PWD
    export CLANG_PATH=~/Repos/toolchains/proton-clang
    export PATH=${CLANG_PATH}/bin:${PATH}
    # export CLANG_TRIPLE=aarch64-linux-gnu- # Enable when use google AOSP clang
    export ARCH=arm64
    export SUBARCH=arm64
    export KERNEL_DEFCONFIG=raphael_defconfig
    export VOID_FIX_PATCH=false # Enable fix-void-err-patch;disable when use proton clang 13
    export SETUP_ENVIRONMENT=false # Set up the build environment
    export SETUP_KERNELSU=true # Enable if you want KernelSU
    export USE_KPROBES=true # Integrate with kprobe or patch
## Select KernelSU tag or branch; Stable tag: KERNELSU_TAG=stable; Dev branch: KERNELSU_TAG=main; Custom tag(Such as v0.5.2): KERNELSU_TAG=V0.5.2
    export KERNELSU_TAG=stable  
    # export ENABLE_LTO=false   # Enable LTO optimize
}

update_kernel() {
    cd $KERNEL_PATH
    git stash
    git pull
}

setup_environment() {
    cd $KERNEL_PATH
    sudo apt update
    sudo apt install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
                        git git-lfs gnupg gperf lib32readline-dev lib32z1-dev \
                        libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
                        lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev
    if [ ! -d $CLANG_PATH ]; then
      git clone https://github.com/kdrag0n/proton-clang.git --depth=1 $CLANG_PATH
    fi
    if [ ! -d $ANYKERNEL_PATH ]; then
       git clone -b raphael https://github.com/gklkf/AnyKernel3 --depth=1 $ANYKERNEL_PATH
    fi
}

setup_kernelsu() {
    cd $KERNEL_PATH
    if test $KERNELSU_TAG = stable 
    then
        curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash - 
    else
        curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s $KERNELSU_TAG
    fi

    if test $USE_KPROBES = true 
    then
        echo [INFO] Enable KPROBES
        scripts/config --file "arch/$ARCH/configs/$KERNEL_DEFCONFIG" -e MODULES -e KPROBES -e HAVE_KPROBES -e KPROBE_EVENTS     # Enable KPROBES
    else
        echo [INFO] KernelSU patch
        scripts/config --file "arch/$ARCH/configs/$KERNEL_DEFCONFIG" -e KSU     # Enable KSU
        git apply $BUILDER_PATH/ksu-patch/*.patch       # Apply kenelSU patchs
    fi
}

setup_void_fix(){
    cd $KERNEL_PATH
    git apply $BUILDER_PATH/fix-void-err-patch/*.patch
}

clean(){
    # Clean garbage
    echo [INFO] Clean garbage 
    cd $KERNEL_PATH
    make mrproper
    # git reset --hard HEAD     # edited code will be cleaned up
    # test -d $KERNEL_PATH/out/arch/arm64/boot && rm -rf $KERNEL_PATH/out/arch/arm64/boot/*
}

build_kernel() {
    cd $KERNEL_PATH
  # Disable LTO
    # if [[ $(echo "$(awk '/MemTotal/ {print $2}' /proc/meminfo) < 16000000" | bc -l) -eq 1 ]]; then
    #     scripts/config --file out/.config -d LTO -d LTO_CLANG -d THINLTO -e LTO_NONE
    # fi

    # Begin compile
    make  O=out CC="ccache clang" CXX="ccache clang++" ARCH=arm64 CROSS_COMPILE=$CLANG_PATH/bin/aarch64-linux-gnu- CROSS_COMPILE_ARM32=$CLANG_PATH/bin/arm-linux-gnueabi- LD=ld.lld $KERNEL_DEFCONFIG
    time make -j$(nproc --all) O=out CC="ccache clang" CXX="ccache clang++" ARCH=arm64  CROSS_COMPILE=$CLANG_PATH/bin/aarch64-linux-gnu- CROSS_COMPILE_ARM32=$CLANG_PATH/bin/arm-linux-gnueabi- LD=ld.lld 2>&1 | tee kernel.log
}

make_anykernel3_zip() {
    cd $KERNEL_PATH
        if test -e $KERNEL_PATH/out/arch/arm64/boot/Image
        then
            zip_name="${KERNEL_DEFCONFIG%_*}-$(grep "^VERSION =" Makefile | awk '{print $3}').$(grep "^PATCHLEVEL =" Makefile | awk '{print $3}').$(grep "^SUBLEVEL =" Makefile | awk '{print $3}')-$(git rev-parse --short HEAD)-$(date +"%Y%m%d").zip"
            cp $KERNEL_PATH/out/arch/arm64/boot/Image $ANYKERNEL_PATH
            cd $ANYKERNEL_PATH
            zip -r ${zip_name} ./*
            mv ${zip_name} $KERNEL_PATH/out/
            echo [INFO] out $zip_name to $KERNEL_PATH/out
        else
        echo [INFO] Build failed
    fi
}

clear
setup_export

# update_kernel   //Please uncomment if you need it

if test $SETUP_ENVIRONMENT = true 
then
    setup_environment
fi

if test $SETUP_KERNELSU = true
then
   setup_kernelsu
   echo [INFO] KerneSU Set up
else
   echo [INFO] KernelSU will not be Compiled
fi

if test $VOID_FIX_PATCH = true
then    
    echo [INFO]Applay fix-void-err-patch
    setup_void_fix
fi

clean
build_kernel

make_anykernel3_zip

echo [INFO] Done