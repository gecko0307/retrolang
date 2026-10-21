psxavenc -t xa -f 37800 -b 4 -c 2 channel0.mp3 channel0.xa
psxavenc -t xa -f 37800 -b 4 -c 2 channel1.mp3 channel1.xa
"../../../xatool/xatool.exe" -o ../iso/MUSIC/FILE0.XA --file 0 channel0.xa channel1.xa
