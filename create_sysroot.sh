
TARGET=rpizero

SYSROOT=sysroot
mkdir -p $SYSROOT

rsync -avz --numeric-ids ${TARGET}:/lib $SYSROOT/
rsync -avz --numeric-ids ${TARGET}:/usr/lib $SYSROOT/usr/
rsync -avz --numeric-ids ${TARGET}:/usr/include $SYSROOT/usr/
