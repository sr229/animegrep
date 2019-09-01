#!/bin/bash
# Copyright Daniel Jones and Ayane Satomi 2019

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Make sure the script fails if the other commands fail as well
set -eo pipefail

print_help() {
	echo "$0 [-d <directory> | -f <file> ] -t <track> -w <WORD> -m -h "
	echo ""
	echo "animegrep is a bash script that extracts the subtitles from an mkv video file, greps them for a specified word, parses them and extracts only that time frame from the source video file"
	echo ""
	echo "-d <directory> sets a directory as your source media"
	echo "-f <file> sets a file as your source media. You cannot set directory and files at the same time."
	echo "-t <track> Not Documented. "
	echo "-w <word> track number for your source media."
	echo "-m to merge multiple output files as one. Useful if you have -d set."
}

POSITIONAL=();

if [ -z "$@" ]; then 
  print_help
  exit 3;
fi

while getopts d:f:t:w:m:h opt; do
  case "${opt}" in
    d) DIRECTORY="${OPTARG}" ;;
	f) FILE="${OPTARG}" ;;
	t) TRACK="${OPTARG}" ;;
	w) WORD="${OPTARG}" ;;
	m) MERGE=1 ;;
	h) print_help ;;
	*) print_help; exit 3 ;;
   esac 
done 
shift $(($OPTIND -1))

POSITIONAL="$@"


# check for mkvextract
command -v mkvextract >/dev/null 2>&1 || { echo >&2 "Requires mkvextract. Aborting."; exit 3; }

# check if out directory exists
# TODO handle case out exists but other subdirs don't
if [ -z "$MERGE" ]; then

	if [ ! -d "out" ]; then
		echo "making out directory..";
		mkdir out;
		mkdir out/clips;
	fi

	if ! [ -z "$FILE" ] || [ -z "$DIRECTORY" ]; then
		echo "You have both -d and -f set.. choose one, not both..";
		exit;
	fi
	
	if [ -z "$FILE"  ] && [ -z "$DIRECTORY" ]; then
		echo "no file or directory provided (use -f [file] or -d [dir])..";
		exit;
	fi

	if [ -z "$TRACK" ]; then
		#assume subtitle track = 2
		echo "track not set (use -t [truck number]). You kind find the subtitle track number using 'mkvinfo [file]'..";
		exit 3;
	fi

	if [ -z "$WORD" ]; then
		echo "no word set, please set a word to grep to (use -w [word] to set the word)..";
		exit 3;
	fi

	if  [ ! -z "$FILE" ]; then
		#echo "using single file..";
		SINGLEFILE=true;
	fi

	if  [ ! -z "$DIRECTORY" ]; then
		#echo "using directory";
		SINGLEFILE=false;
	fi
fi
# we're done the boring stuff

x=0;


function grepsubs()
{
	# $1 = file $2 = CFILE
	while read -r line; do
		((x++)) || true;
		#echo "line in grep ${line}";
		#parselinie $x "$1" $line;
		parseline "$1" "$line" "$2";
	done < <(grep -i "$WORD" out/subs.srt);
}

getsubs() {
	# $1 = file
	#echo "getting subs for "$1"";
	rm out/subs.srt || true;
	CFILE=$(basename "$1" .mkv);
	#echo "CFILE is "$CFILE"";
	#echo "extracting subs from $1 track ${TRACK} to out/subs.srt";
	mkvextract tracks "$1" ${TRACK}:out/subs.srt;
	grepsubs "$1" "$CFILE";
}

parseline() {

	# $1 = file $2 = line $3 = CFILE
	IFS=',' read -r -a array <<< "$2";
	echo "start time: ${array[1]}";
	echo "end time: ${array[2]}";
	cutvideo "$1" "${array[1]}" "${array[2]}" "$3";
}

cutvideo() {
	# $1 = file $2 = start time $3 = end time $4 = CFILE
	
	echo "$1" start time\: "$2" end time: "$3" >> out/times.txt;

	ffmpeg -i "$1" -ss 0"$2" -to 0"$3" -async 1 -c:v libx264 -preset ultrafast out/clips/clip_"$x".mkv < /dev/null

	#ffmpeg -i "$1" -ss 0"$2" -to 0"$3" -async 1 -map 0:0 -map 0:2 -c:v libx264 -preset ultrafast out/clips/clip_"$x".mkv < /dev/null;
}

merge() {
	echo "merging mkv's..";
	ls -Q out/clips | grep -E "\.mkv" | sed -e "s/^/file /g" > video_files.txt;
	ffmpeg -f concat -i video_files.txt out/out.mkv;
	rm video_files.txt
}

# getsubs function will run the chain that does the whole process

if ! [ -z "$MERGE" ]; then
	merge;
	exit;
fi

if [ "$SINGLEFILE" == true ]; then
	echo "doing one file";
	getsubs "$FILE";
fi

if [ "$SINGLEFILE" == false ]; then
	for f in "$DIRECTORY"/*.mkv; do
		getsubs "$f";
	done;
fi
