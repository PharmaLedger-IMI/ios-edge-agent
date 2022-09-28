#!/bin/bash

fullPath="$1"
frameworkDirectoryPart=$(basename $1)
sourceDirectory=$(dirname $1)
frameworkFile=${frameworkDirectoryPart%%.*}
echo "Framework is $frameworkDirectoryPart"
echo "Directory is $sourceDirectory"
echo "Framework file is $frameworkFile"


rm -f -R ./iphoneos
rm -f -R ./iphonesimulator

mkdir iphoneos
mkdir iphonesimulator

# Copy framework into the platform specific directories
cp -R "$fullPath" "iphoneos/$frameworkDirectoryPart"
cp -R "$fullPath" "iphonesimulator/$frameworkDirectoryPart"


# Look at the architectures in the original binary
xcrun lipo -i "$fullPath/$frameworkFile"

# lipo -remove i386 "iphoneos/$frameworkDirectoryPart/$frameworkFile" -o "iphoneos/$frameworkDirectoryPart/$frameworkFile"
xcrun lipo -remove x86_64 "iphoneos/$frameworkDirectoryPart/$frameworkFile" -o "iphoneos/$frameworkDirectoryPart/$frameworkFile"

xcrun lipo -remove arm64 "iphonesimulator/$frameworkDirectoryPart/$frameworkFile" -o "iphonesimulator/$frameworkDirectoryPart/$frameworkFile"
#xcrun lipo -remove armv7 "iphonesimulator/$frameworkDirectoryPart/$frameworkFile" -o "iphonesimulator/$frameworkDirectoryPart/$frameworkFile"


xcrun lipo -i "iphoneos/$frameworkDirectoryPart/$frameworkFile"
xcrun lipo -i "iphonesimulator/$frameworkDirectoryPart/$frameworkFile"

xcodebuild -create-xcframework -framework "iphoneos/$frameworkDirectoryPart" -framework "iphonesimulator/$frameworkDirectoryPart" -output "$sourceDirectory/$frameworkFile.xcframework"

