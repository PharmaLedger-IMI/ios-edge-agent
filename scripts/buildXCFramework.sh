

projectDir=${PROJECT_DIR:-"./../"}
cd "$projectDir"

source ./../scripts/preBuild.sh

projectDir=$(pwd)
outputDir=${3:-"$projectDir/xcframeworkOutput"}

echo "Project directory is: $projectDir"
echo "Output folder is: $outputDir"


project="$1"
scheme="$2"
finalFrameworkName="$scheme"

archiveOutputDirectory="archives"
deviceFrameworkOutputPath="$archiveOutputDirectory/framework-iOS.xcarchive"
simulatorFrameworkOutputPath="$archiveOutputDirectory/framework-iOS-simulator.xcarchive"

iOSDeviceDestination="generic/platform=iOS"
iOSSimulatorDestination="generic/platform=iOS Simulator"

function deletePreviousArchives {
    rm -r -f "$archiveOutputDirectory"
}

function deleteCurrentProducts {
    rm -r -f "$outputDir"
}


function callXcodeBuild {
# 1 - workspace, 2 - scheme, 3 - destination, 4 - output path
xcodebuild archive \
-project "$1" \
-scheme "$2" \
-destination  "$3" \
-archivePath "$4" \
SKIP_INSTALL=NO \
BUILD_LIBRARY_FOR_DISTRIBUTION=YES

}

function createXCFramework {
    # 1 - finalFrameworkName, 2 - output directory
  local genericFrameworkRootDirSuff="/Products/Library/Frameworks"
  local simulatorFrameworkRootDir="$simulatorFrameworkOutputPath""$genericFrameworkRootDirSuff"
  local deviceFrameworkRootDir="$deviceFrameworkOutputPath""$genericFrameworkRootDirSuff"

  xcodebuild -create-xcframework \
            -framework "$simulatorFrameworkRootDir/$1.framework" \
            -framework "$deviceFrameworkRootDir/$1.framework" \
            -output "$2/$1.xcframework"
}

deletePreviousArchives
deleteCurrentProducts

callXcodeBuild "$project" "$scheme" "$iOSDeviceDestination" "$deviceFrameworkOutputPath"

callXcodeBuild "$project" "$scheme" "$iOSSimulatorDestination" "$simulatorFrameworkOutputPath"

createXCFramework "$finalFrameworkName" "$outputDir"

deletePreviousArchives

echo "All done, the .xcframework can be found in $outputDir"

