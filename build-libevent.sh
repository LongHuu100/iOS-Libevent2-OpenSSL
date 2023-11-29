###########################################################################
# Choose your libevent version and your currently-installed iOS SDK version:
# xcodebuild -showsdks GET USERSDKVERSION = iOS SDKs(16.0)

VERSION="2.1.12-stable"
USERSDKVERSION="16.0"
MINIOSVERSION="15.0"
## Change your Path to SSL after build of 
## https://github.com/x2on/OpenSSL-for-iPhone
OPEN_SSL="/Users/HuuLong/Downloads/IOS-OpenSSL/bin/iPhoneOS16.0-arm64.sdk"

###########################################################################
# Don't change anything under this line!
###########################################################################

ARCHS="arm64"
DEVELOPER=`xcode-select -print-path`
SDKVERSION="${USERSDKVERSION}"

cd "`dirname \"$0\"`"
REPOROOT=$(pwd)

# Where we'll end up storing things in the end
OUTPUTDIR="${REPOROOT}/dependencies"
mkdir -p ${OUTPUTDIR}/include
mkdir -p ${OUTPUTDIR}/lib


BUILDDIR="${REPOROOT}/build"
# where we will keep our sources and build from.
SRCDIR="${BUILDDIR}/src"
mkdir -p $SRCDIR
# where we will store intermediary builds
INTERDIR="${BUILDDIR}/built"
mkdir -p $INTERDIR

########################################

cd $SRCDIR
# Exit the script if an error happens
set -e
if [ ! -e "${SRCDIR}/libevent-${VERSION}.tar.gz" ]; then
	echo "Downloading libevent-${VERSION}.tar.gz"
	curl -LO https://github.com/libevent/libevent/releases/download/release-${VERSION}/libevent-${VERSION}.tar.gz
fi

echo "Using libevent-${VERSION}.tar.gz"
tar zxf libevent-${VERSION}.tar.gz -C $SRCDIR
cd "${SRCDIR}/libevent-${VERSION}"

set +e # don't bail out of bash script if ccache doesn't exist
CCACHE=`which ccache`
if [ $? == "0" ]; then
	echo "Building with ccache: $CCACHE"
	CCACHE="${CCACHE} "
else
	echo "Building without ccache"
	CCACHE=""
fi
set -e # back to regular "bail out on error" mode

export ORIGINALPATH=$PATH
for ARCH in ${ARCHS}
do
	if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ];
	then
		PLATFORM="iPhoneSimulator"
		EXTRA_CONFIG="--host=${ARCH}-apple-darwin"
	else
		PLATFORM="iPhoneOS"
		EXTRA_CONFIG="--host=arm-apple-darwin"
	fi

	mkdir -p "${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"

	export PATH="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/:${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/usr/bin/:${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin:${DEVELOPER}/usr/bin:${ORIGINALPATH}"
	export CC="${CCACHE}`which gcc` -arch ${ARCH} -miphoneos-version-min=${MINIOSVERSION}"
	
	## --disable-openssl ##
	./configure PKG_CONFIG_PATH="${OPEN_SSL}/lib/pkgconfig" 										\
	--disable-shared --enable-static --disable-debug-mode ${EXTRA_CONFIG} --disable-clock-gettime 	\
	--prefix="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" 									\
	LDFLAGS="$LDFLAGS -L${OPEN_SSL}/lib -L${OUTPUTDIR}/lib" 										\
	CFLAGS="$CFLAGS -I${OPEN_SSL}/include -Os -I${OUTPUTDIR}/include -isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk" \
	CPPFLAGS="$CPPFLAGS -I${OPEN_SSL}/include -I${OUTPUTDIR}/include -isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${SDKVERSION}.sdk"

	# Build the application and install it to the fake SDK intermediary dir
	# we have set up. Make sure to clean up afterward because we will re-use
	# this source tree to cross-compile other targets.
	make -j$(sysctl hw.ncpu | awk '{print $2}')
	make install
	make clean
done

########################################
echo "Build library..."

OUTPUT_LIBS="libevent.a libevent_core.a libevent_extra.a libevent_openssl.a libevent_pthreads.a"
for OUTPUT_LIB in ${OUTPUT_LIBS}; do
	INPUT_LIBS=""
	for ARCH in ${ARCHS}; do
		if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ];
		then
			PLATFORM="iPhoneSimulator"
		else
			PLATFORM="iPhoneOS"
		fi
		INPUT_ARCH_LIB="${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib/${OUTPUT_LIB}"
		if [ -e $INPUT_ARCH_LIB ]; then
			INPUT_LIBS="${INPUT_LIBS} ${INPUT_ARCH_LIB}"
		fi
	done
	# Combine the three architectures into a universal library.
	if [ -n "$INPUT_LIBS"  ]; then
		lipo -create $INPUT_LIBS \
		-output "${OUTPUTDIR}/lib/${OUTPUT_LIB}"
	else
		echo "$OUTPUT_LIB does not exist, skipping (are the dependencies installed?)"
	fi
done

for ARCH in ${ARCHS}; do
	if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ];
	then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi
	cp -R ${INTERDIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/include/* ${OUTPUTDIR}/include/
	if [ $? == "0" ]; then
		break
	fi
done

####################
echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/libevent-${VERSION}"
echo "Done."
