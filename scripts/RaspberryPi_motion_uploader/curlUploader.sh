#!/bin/bash
#   @author Roel Strauven <roel.strauven@rsolution.be>
#
#   Script to upload custom captured images to
#   http://motiondetection.be
#               
#   USAGE: 
#    . curluploader.sh "[ImageToUpload]" "[CamName or Empty]" "[limitThrotlleBytes]" "[username]" "[uploadKey]"
#       You can create config.sh to override variables: camname,limitThrotlleBytes,uploadUser,uploadKey,uploadBackend
#           -> This way you don't need to provide them on the commandline.
#
#   INSTALLATION:
#       Using this with motionEye (example):
#           - adding this script to motionEye configuration:
#               - Click "Backup" in motionEye configuration trough webinterface, save to tdisk
#               - Add this file (curlUploader.sh) to the saved archive (motioneye-config.tar.gz)
#               - Click "Restore" and choose your edited motioneye-config.tar.gz
#               OR
#               - Add custom command to motionEye, let it execute by a motion/command trigger:
#               - Field "Extra Motion Options": 
#                    on_picture_save curl http://motiondetection.be/SCRIPTS/curlUploader.sh > $(pwd)/curlUploader.sh;chmod +x $(pwd)/curlUploader.sh
#           - add in field "Extra Motion Options":
<<copy_paste
on_picture_save $(pwd)/curlUploader.sh %f "[CAMERANAME]" "[limitThrotlleBytes]" "[USERNAME]" "[UPLOADKEY]"
snapshot_interval 30
snapshot_filename %Y/%m/%d/%H/%M/%S-snapshot
jpeg_filename %Y/%m/%d/%H/%M/%S-%q
copy_paste
#
#       Using this with MOTION (example):
#           - add in thread1.conf:
#               on_picture_save $(pwd)/curlUploader.sh %f "[CamName or Empty]" "[limitThrotlleBytes]" "[username]" "[uploadKey]"
#
<<copy_paste
TESTING in bash:
    cd /var/tmp/motion_uploads/;watch -n 1 "echo Running Retries: \$(cat currentRunningRetries.txt); cat rateLimit.txt ;cat throtleMeasureSince;sec=\$(( \$(date +%s) - \$(cat throtleMeasureSince) ));echo \$(( \$(cat throtleMeasureBytes) / 1024 / \$sec )) kb/s in \$sec s.;echo \$(ls -laht /var/tmp/motion_uploads/todo/*.todo | wc -l) TODO items;ls -laht /var/tmp/motion_uploads/;echo \$(date -r currentRunningRetries.txt); tail /var/log/syslog"
copy_paste
#
#

uploadFile=$1
camname=${2-}; # if not isset then use ''
limitThrotlleBytes=${3-34952} # 34952b/s=2mb/min  69905b/s=4mb/min 
uploadUser=${4-}; # if not isset then use ''
uploadKey=${5-}; # if not isset then use ''

uploadBackend=http://motiondetection.be/upload.php


if [ ! -f "$uploadFile" ] 
then
    echo "uploadFile Not found: $uploadFile" | logger -t 'Webcam upload';
    echo "uploadFile Not found: $uploadFile";
    return;
fi


qPath=/var/tmp/motion_uploads/todo/
qPathImgs=$qPath"img/"
mkdir -p $qPathImgs
countThrottlepath=/tmp/currentRunningRetries.txt

# rate limit => should be removed on reboots => tmp path
rateLimitPath=/tmp/rateLimit.txt

timestamp=$(date +%s%3N);
timestampFile=$(date +%s%9N);

scriptPath=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd );
CONFIGFILE=$scriptPath"/config.sh" && test -f $CONFIGFILE && . $CONFIGFILE

# test PROVIDED config and fail with message + logger
function testEmpty {
    if [ "$1" == "" ]
	then
	  echo "Missing parameter/field '$2' add to config.sh";
	  echo "Missing parameter/field '$2' add to config.sh" | logger -t 'Webcam upload';
	  return 2;
    fi

}
testEmpty $uploadFile uploadFile
testEmpty $uploadUser uploadUser
testEmpty $uploadKey uploadKey

type="image"
[[ "$uploadFile" == *"snapshot"* || "$uploadFile" == *"ping"* ]] && type=ping;

#imgBase64data=`base64 --wrap=0 $uploadFile`
imgBase64="data:image/jpeg;base64,"
imageType="image/jpg"
echo -n $imgBase64 > $qPathImgs$timestampFile
base64 --wrap=0 $uploadFile >> $qPathImgs$timestampFile

curlCMD="curl $uploadBackend -X POST --compressed -F $uploadKey=<$qPathImgs$timestampFile -F u=$uploadUser -F imageType=$imageType -F timestamp=$timestamp -F type=$type -F camname=$camname"
logLine="-F imageType=$imageType -F timestamp=$timestamp -F type=$type -F camname=$camname key=$uploadKey u=$uploadUser "


# checks OK

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
    done

    echo "running: " $cmd
    eval $cmd
    
    rm -f "${lock}"
    trap - INT TERM EXIT
}

function checkresultRemoveAddQue {
	curlCMD=$1
	timestamp=$2
	qPath=$3
	logLine=$4
	
	touch $rateLimitPath
	updateFileWithLock "lastUpload=\$(cat $rateLimitPath); [ \"\$lastUpload\" == '' ] && lastUpload=0" "$rateLimitPath"

	#echo $(( $lastUpload+500 < $(date +%s%3N) ));

	curlResult=
	throtthleResult=0
	# check last upload within 500ms
	#if (( $lastUpload+500 < $(date +%s%3N))) ; then
	    . $scriptPath/countThrottle.sh "$uploadFile" "$limitThrotlleBytes"
	    throtthleResult=$?
        #else
	#    curlResult=" within 500ms "
	#fi

	
	curlResultUploadOK=

	if [ "$throtthleResult" == "1" ] ; then
		#echo $curlCMD
		curlResult=$($curlCMD);
		echo "CURL result: $curlResult ";
		echo "$curlResult $logLine" | logger -t 'Webcam upload';
		curlResultUploadOK=${curlResult:0:9}

		# rate limit
		updateFileWithLock "echo \$(date +%s%3N) > $rateLimitPath" "$rateLimitPath"
	else
		curlResult="Too fast, canceled by CLIENT ($curlResult)"
		[ "$throtthleResult" == "0" ] && curlResult="$curlResult (by Throttle)"
		echo $curlResult
	fi
	
	if [ "$curlResultUploadOK" == "upload ok" ] || [ "$type" == "ping" ]
	then
		# remove image file when OK or when an ping/snapshot-type
		rm $qPathImgs$timestamp
	else
		echo "ERROR uploading: $curlResult $logLine shedule retry $timestamp" | logger -t 'Webcam upload';
		mkdir -p $qPath
		echo $curlCMD > $qPath$timestamp.todo;
		echo "Resheduled in $qPath$timestamp.todo"
	fi
}  

checkresultRemoveAddQue "$curlCMD" "$timestampFile" "$qPath" "$logLine"
##### END uploading current, NEXT check & upload queue
#no more ping types, we don't shedule these! -> they are not relevant (too old)
type=



if [ -f $countThrottlepath ]; then
    # check age of $countThrottlepath, if greater then X minutes, remove
    ageMilliSec=$(( $(date +%s%3N) - $(date -r $countThrottlepath +%s%3N) ));
    ageMilliSec=${ageMilliSec-0};# 0 if empty
    if (( $ageMilliSec > 300000)); then
	## too old, force remove!
	echo "Lock on PREVIOUS failed images is too old ($ageMilliSec), RETRY." | logger -t 'Webcam upload';
	#rm -f $countThrottlepath
	echo "0" > $countThrottlepath
    fi
else
    echo "0" > $countThrottlepath
fi


# trap on exit, cleanup
function finish {
    #updateFileWithLock "currentRunning=\$(cat $countThrottlepath); (( currentRunning-- )); echo \$currentRunning > $countThrottlepath" "$countThrottlepath"
    # Set our signal mask to ignore SIGINT
    trap - SIGINT TERM
    break;
}

#updateFileWithLock "currentRunning=\$(cat $countThrottlepath); [ \"\$currentRunning\" == '' ] && currentRunning=0;" "$countThrottlepath"
# trap finish 
trap finish SIGINT TERM

touch $countThrottlepath
updateFileWithLock "currentRunning=\$(cat $countThrottlepath); if [ \"\$currentRunning\" == '' ]; then currentRunning=0;fi; (( currentRunning++ )); if [ \"\$currentRunning\" == '1' ]; then echo \$currentRunning > $countThrottlepath; fi; " "$countThrottlepath"

if [[ "$currentRunning" == "1" ]]; then
	echo "PROCESSING PREVIOUS failed images in $qPath"

	loopCount=0
	for f in $qPath*.todo
	do
	  if [ -f "$f" ];
	  then
	     (( loopCount++ ))
	     #echo "Processing RETRY$loopCount $f file..."  | logger -t 'Webcam upload';
	     contentRetry=$(cat $f)
	     rm -f "$f"
	     timestamp=$(basename $f)
	     # remove .todo from timestamp
	     timestamp=${timestamp/.todo/}
	     # echo $contentRetry
	     
	     # no bash for floats!
	     throttleSleep=$(echo print $limitThrotlleBytes / 35000. | perl)
	     [ "$contentRetry" != "" ] && sleep $throttleSleep && checkresultRemoveAddQue "$contentRetry" "$timestamp" "$qPath" "RETRY (sleep:$throttleSleep s.) ($currentRunning)/$loopCount $f" 
	   fi

	   if (( $loopCount > 50 )); then
	      break;
	   fi
	done

	updateFileWithLock "currentRunning=\$(cat $countThrottlepath); (( currentRunning-- )); echo \$currentRunning > $countThrottlepath" "$countThrottlepath"
else
    echo Other running instances detected: $currentRunning: no queue retry;
fi

#updateFileWithLock "currentRunning=\$(cat $countThrottlepath); (( currentRunning-- )); echo \$currentRunning > $countThrottlepath" "$countThrottlepath"

trap - SIGINT TERM

