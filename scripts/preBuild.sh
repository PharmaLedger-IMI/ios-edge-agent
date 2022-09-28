#!/bin/bash

projDir=${PROJECT_DIR:-"./../"}
scriptsDirectory="$projDir/../scripts"
startingDir=$(pwd)

cd "$projDir"
pwd
echo "Begin fetching required dependencies"

title='Dependencies fetch error'
description='In order to properly compile the project please make sure that on the build machine the \"carthage\" utility is installed'

cmd='set titleText to '"\"$title\""'
set dialogText to '"\"$description\""'
display dialog dialogText with icon stop with title titleText'

showDialog() {
    /usr/bin/osascript -e "$cmd" &
}

printToConsole() {
    printf "%s\n%s" "$title" "$description"
}

ensureCommandExists() {
    if ! command -v "$1" &> /dev/null; then
        showDialog
        printToConsole
        exit 1
    fi
}

ensureCommandExists "carthage"

XCODE_XCCONFIG_FILE="$scriptsDirectory/overrideCheckedOutBuildSettings.xcconfig" carthage update --use-xcframeworks --platform ios

carthageBinariesDirectory="$projDir/Carthage/Build/iOS"

if [ -d "$carthageBinariesDirectory" ]; then
    echo "Converting any fat binaries into xcframeworks from $carthageBinariesDirectory"
    cd "$scriptsDirectory"
    pwd
    ./processFatFrameworks.sh "$carthageBinariesDirectory"
fi

cd "$startingDir"
echo "Dependency fetch done"

