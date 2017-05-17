# motiondetection.be
Camera scripts for motiondetection.be
This scripts implements bash queuing of pictures and throttle control for uploads to motiondetection.be 

[More info: http://motiondetection.be](http://motiondetection.be)


Howto install:
 - sudo apt-get install motion git rpi-update curl
 - cd /etc/motion
 - sudo git clone https://github.com/Rsolution-be/motiondetection.be.git
 - enable "thread /etc/motion/thread1.conf" in /etc/motion.conf
 - create /etc/motion/thread1.conf: sudo nano /etc/motion/thread1.conf
    - (or copy with: sudo cp /etc/motion/motiondetection.be/scripts/RaspberryPi_motion_uploader/motion_example_thread1.conf /etc/motion/thread1.conf)
    - add: on_picture_save /etc/motion/motiondetection.be/scripts/RaspberryPi_motion_uploader/curlUploader.sh "%f" "CAMERANAME" 20000"

 - login to [http://motiondetection.be/watch.php](http://motiondetection.be/watch.php)
    - click the "i"-icon and find your USERNAME and UPLOADKEY

 - edit /etc/motion/motiondetection.be/scripts/RaspberryPi_motion_uploader/config.sh
    - fill your uploadUser="xxUSERxx" and uploadKey="xxKEYxx"

 - enable motion deamon in: /etc/default/motion   (start_motion_daemon=yes)
 



Useful CRON's for Raspberry in combination with motiondetection.be:
sudo crontab -u motion -e

    # restart Camera thread1 every minute. (circumvent green images on light changes with Raspberry camera, refocus camera)
    * * * * * bash -c "if (( $(/bin/ps -ef | /bin/grep -v grep | /bin/grep 'motion' | /usr/bin/wc -l) > 0 )); then /usr/bin/curl localhost:8080/1/action/restart; fi;"

    # cleanup all motion images every
    */20 * * * * find /var/tmp/motion* -type f -mmin +120 -exec rm "{}" \;