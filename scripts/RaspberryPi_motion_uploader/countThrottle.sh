#!/bin/bash
#   @author Roel Strauven <roel.strauven@rsolution.be>
#   script returns true/false, based on the filesize, and provided limits
#
uploadFile=$1
limitBytesToCompare=${2-60000} # 34952b/s=2mb/min  69905b/s=4mb/min 
# Seconds to reset the counter
throthleCleanup=35
# Seconds after restart counter
throthleNewStart=1

ScriptLocation=/tmp
blockSameMomentFile=$ScriptLocation/throtleBlockSameMomentFile
measureSinceFile=$ScriptLocation/throtleMeasureSince
measureBytesFile=$ScriptLocation/throtleMeasureBytes
mkdir -p $ScriptLocation


# updateFileWithLock "echo $(( $(cat $measureBytesFile) + valueToAdd )) > $measureBytesFile" "$measureBytesFile" 
updateFileWithLock () 
{
    local cmd=$1 file=$2 lock=$2.lock
    
    [ -f "${file}" ] || return $?
    # Wait for lock...
    trap 'rm -f "${lock}"; exit $?' INT TERM EXIT
    until ln "${file}" "${lock}" 2>/dev/null
    do 
	echo "Waiting for ${lock}... "
	sleep 0.1
	#[ -s "${file}" ] || return $?
	#|| touch "${file}" 
	#[ -f "${file}" ] || return $?
    done

    echo "running: " $cmd
    eval $cmd
    
    rm -f "${lock}"
    trap - INT TERM EXIT
}

# block run on same second!
#touch $blockSameMomentFile
#updateFileWithLock "[ -f \"$blockSameMomentFile\" ] || echo $(date +%s) " "$blockSameMomentFile"

# defaults
touch $measureSinceFile
touch $measureBytesFile
# defaults, update if is empty
updateFileWithLock "[ -s \"$measureSinceFile\" ] || echo $(date +%s) > $measureSinceFile" "$measureSinceFile"
updateFileWithLock "[ -s \"$measureBytesFile\" ] || echo '0' > $measureBytesFile" "$measureBytesFile"


#ls -laht $ScriptLocation/thro*;cat $ScriptLocation/thro*;echo 'DEBUG EXIT'; return;


newFilesize=$(stat -c%s $uploadFile)
#measureSince=$(cat $measureSinceFile)
updateFileWithLock "measureSince=\$(cat $measureSinceFile)" "$measureSinceFile"
updateFileWithLock "measureBytes=\$(cat $measureBytesFile)" "$measureBytesFile"
now=$(date +%s)
measuredTimeSeconds=$(( ($now-$measureSince+1) ))

bytesPerSecond=$(($measureBytes / $measuredTimeSeconds))
kilobytesPerSecond=$(($bytesPerSecond / 1024))
echo "OLD bytes: $measureBytes  $kilobytesPerSecond kb/s"

if (( $bytesPerSecond > $limitBytesToCompare )); then
    # already over limit! exit here!
    echo "  Over Throttle (before current file)! $kilobytesPerSecond kb/s  $measuredTimeSeconds s. "
    return 0;
fi

# don't write bytes direct to disk: updateFileWithLock "echo \$(( \$(cat $measureBytesFile) +$newFilesize )) > $measureBytesFile;measureBytes=\$(cat $measureBytesFile)" "$measureBytesFile"
measureBytes=$(( $measureBytes + $newFilesize ))
echo NEW bytes: $measureBytes
measureKiloBytes=$(($measureBytes / 1024))

bytesPerSecond=$(($measureBytes / $measuredTimeSeconds))
kilobytesPerSecond=$(($bytesPerSecond / 1024))
megabytesPerSecond=$(($kilobytesPerSecond / 1024))

echo "	Sent $measureKiloBytes kb in $measuredTimeSeconds s.  (new filesize=$newFilesize)"
echo "  $kilobytesPerSecond kb/s - $bytesPerSecond b/s - $megabytesPerSecond Mb/s   (limit: $limitBytesToCompare b/s)"
echo 

# exit code, check with: $ ?
if (( $bytesPerSecond > $limitBytesToCompare )); then
    echo "  Over Throttle! ($limitBytesToCompare b/s) $kilobytesPerSecond kb/s  $measuredTimeSeconds s."
    # subtract $newFilesize again from bytes file
    # don't write bytes direct to disk: updateFileWithLock "echo \$(( \$(cat $measureBytesFile) - $newFilesize )) > $measureBytesFile" "$measureBytesFile"
    return 0
else
    # cleanup, assume with averages, if bigger then XXXseconds, reduce to YY seconds
    if (( $measuredTimeSeconds > $throthleCleanup )); then
	echo Resetting count..
	measureSince=$(( $now - $throthleNewStart ))
	measuredTimeSeconds=$throthleNewStart
	measureBytes=$(( $bytesPerSecond * $throthleNewStart))
	
	updateFileWithLock "echo $measureSince > $measureSinceFile" "$measureSinceFile"
	updateFileWithLock "echo $measureBytes > $measureBytesFile" "$measureBytesFile"
	echo "New values: $measureBytes in $measuredTimeSeconds seconds = " $(( $measureBytes / $measuredTimeSeconds / 1024)) "kb/s" 
    fi

    # write new bytes to DISK
    updateFileWithLock "echo \$(( \$(cat $measureBytesFile) +$newFilesize )) > $measureBytesFile;measureBytes=\$(cat $measureBytesFile)" "$measureBytesFile"
    echo "  Throttle OK! ($limitBytesToCompare b/s) $kilobytesPerSecond kb/s  $measuredTimeSeconds s."
    return 1
fi
